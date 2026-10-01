import type { AuthContext } from '../../core/auth/context.js';
import type { Role } from '../../core/auth/roles.js';
import {
  BusinessRuleError,
  ConflictError,
  ForbiddenError,
  NotFoundError,
  ValidationError,
} from '../../core/errors/index.js';
import type { PasswordHasher } from '../../core/security/password-hasher.js';
import { MembershipModel } from '../auth/membership.model.js';
import type { SessionService } from '../auth/session.service.js';
import { UserModel } from '../auth/user.model.js';
import type { AddTeammateInput } from './team.schemas.js';

export interface TeammateDto {
  userId: string;
  name: string;
  email: string;
  role: Role;
  addedAt: Date;
}

/** Dashboard accounts (owners, admins, viewers) of an organisation. */
export class TeamService {
  constructor(
    private readonly passwords: PasswordHasher,
    private readonly sessions: SessionService,
  ) {}

  async list(orgId: string): Promise<TeammateDto[]> {
    const memberships = await MembershipModel.find({ orgId }).sort({ createdAt: 1 }).lean().exec();
    const users = await UserModel.find({ _id: { $in: memberships.map((m) => m.userId) } })
      .lean()
      .exec();
    const userById = new Map(users.map((user) => [user._id.toString(), user]));

    return memberships.flatMap((membership) => {
      const user = userById.get(membership.userId.toString());
      return user
        ? [
            {
              userId: user._id.toString(),
              name: user.name,
              email: user.email,
              role: membership.role,
              addedAt: membership.createdAt,
            },
          ]
        : [];
    });
  }

  async add(actor: AuthContext, input: AddTeammateInput): Promise<TeammateDto> {
    if (input.role === 'OWNER' && actor.role !== 'OWNER') {
      throw new ForbiddenError('Only an owner can add another owner');
    }

    let user = await UserModel.findOne({ email: input.email }).lean().exec();
    if (!user) {
      if (!input.name || !input.temporaryPassword) {
        throw new ValidationError('This email has no account yet. Provide name and temporaryPassword to create one.');
      }
      const created = await UserModel.create({
        email: input.email,
        name: input.name,
        passwordHash: await this.passwords.hash(input.temporaryPassword),
      });
      user = created.toObject();
    }

    if (await MembershipModel.exists({ userId: user._id, orgId: actor.orgId })) {
      throw new ConflictError('This person is already on the team');
    }
    const membership = await MembershipModel.create({ userId: user._id, orgId: actor.orgId, role: input.role });
    return {
      userId: user._id.toString(),
      name: user.name,
      email: user.email,
      role: membership.role,
      addedAt: membership.createdAt,
    };
  }

  async changeRole(actor: AuthContext, userId: string, role: Role): Promise<void> {
    const membership = await this.getMembership(actor.orgId, userId);
    if (membership.role === 'OWNER' && role !== 'OWNER') {
      await this.assertAnotherOwnerExists(actor.orgId, userId);
    }
    await MembershipModel.updateOne({ _id: membership._id }, { $set: { role } }).exec();
  }

  async remove(actor: AuthContext, userId: string): Promise<void> {
    const membership = await this.getMembership(actor.orgId, userId);
    if (membership.role === 'OWNER') {
      await this.assertAnotherOwnerExists(actor.orgId, userId);
    }
    await MembershipModel.deleteOne({ _id: membership._id }).exec();
    await this.sessions.revokeAllForUser(userId, actor.orgId);
  }

  private async getMembership(orgId: string, userId: string) {
    const membership = await MembershipModel.findOne({ orgId, userId }).lean().exec();
    if (!membership) throw new NotFoundError('Team member');
    return membership;
  }

  private async assertAnotherOwnerExists(orgId: string, exceptUserId: string): Promise<void> {
    const otherOwners = await MembershipModel.countDocuments({
      orgId,
      role: 'OWNER',
      userId: { $ne: exceptUserId },
    }).exec();
    if (otherOwners === 0) {
      throw new BusinessRuleError('An organization must keep at least one owner');
    }
  }
}
