import type { AccessTokenService } from '../../core/auth/access-token.service.js';
import type { AuthContext } from '../../core/auth/context.js';
import type { Role } from '../../core/auth/roles.js';
import { ConflictError, ForbiddenError, UnauthorizedError } from '../../core/errors/index.js';
import type { PasswordHasher } from '../../core/security/password-hasher.js';
import type { Clock } from '../../core/time/clock.js';
import { toOrganizationDto, type OrganizationDto } from '../organizations/organization.dto.js';
import type { OrganizationService } from '../organizations/organization.service.js';
import type { LoginInput, RegisterInput } from './auth.schemas.js';
import { MembershipModel } from './membership.model.js';
import type { ClientMeta, SessionService } from './session.service.js';
import { UserModel } from './user.model.js';

export interface Profile {
  user: { id: string; name: string; email: string };
  organization: OrganizationDto;
  role: Role;
  organizations: Array<{ id: string; name: string; role: Role }>;
}

export interface AuthResult {
  accessToken: string;
  expiresIn: number;
  refreshToken: string;
  refreshExpiresAt: Date;
  profile: Profile;
}

const INVALID_LOGIN = 'Invalid email or password';

export class AuthService {
  /** Hash compared against when the email does not exist, so response time does not reveal registered emails. */
  private timingDummyHash: Promise<string> | undefined;

  constructor(
    private readonly organizations: OrganizationService,
    private readonly sessions: SessionService,
    private readonly passwords: PasswordHasher,
    private readonly accessTokens: AccessTokenService,
    private readonly clock: Clock,
  ) {}

  async register(input: RegisterInput, meta: ClientMeta): Promise<AuthResult> {
    if (await UserModel.exists({ email: input.user.email })) {
      throw new ConflictError('An account with this email already exists');
    }

    // No multi-document transaction so this also runs on a standalone local MongoDB.
    // If a later step fails, earlier documents are removed (compensating actions).
    const org = await this.organizations.create(input.organization);
    let userId: string | undefined;
    try {
      const user = await UserModel.create({
        email: input.user.email,
        name: input.user.name,
        passwordHash: await this.passwords.hash(input.user.password),
      });
      userId = user._id.toString();
      await MembershipModel.create({ userId, orgId: org._id, role: 'OWNER' });
    } catch (error) {
      await Promise.all([
        this.organizations.delete(org._id.toString()),
        userId ? UserModel.deleteOne({ _id: userId }).exec() : undefined,
      ]);
      throw error;
    }

    return this.startSession({ userId, orgId: org._id.toString(), role: 'OWNER' }, meta);
  }

  async login(input: LoginInput, meta: ClientMeta): Promise<AuthResult> {
    const user = await UserModel.findOne({ email: input.email }).select('+passwordHash').exec();
    if (!user) {
      await this.passwords.verify(input.password, await this.dummyHash());
      throw new UnauthorizedError(INVALID_LOGIN);
    }
    if (!(await this.passwords.verify(input.password, user.passwordHash))) {
      throw new UnauthorizedError(INVALID_LOGIN);
    }

    const membership = await MembershipModel.findOne({
      userId: user._id,
      ...(input.organizationId ? { orgId: input.organizationId } : {}),
    })
      .sort({ createdAt: 1 })
      .lean()
      .exec();
    if (!membership) throw new ForbiddenError('This account does not have access to an organization');

    user.lastLoginAt = this.clock.now();
    await user.save();

    return this.startSession(
      { userId: user._id.toString(), orgId: membership.orgId.toString(), role: membership.role },
      meta,
    );
  }

  async refresh(refreshToken: string, meta: ClientMeta): Promise<AuthResult> {
    const session = await this.sessions.consume(refreshToken);
    const userId = session.userId.toString();
    const orgId = session.orgId.toString();

    // Role changes and removals take effect here, at most one access-token lifetime later.
    const membership = await MembershipModel.findOne({ userId, orgId }).lean().exec();
    if (!membership) {
      await this.sessions.revokeAllForUser(userId, orgId);
      throw new UnauthorizedError('You no longer have access to this organization');
    }
    return this.startSession({ userId, orgId, role: membership.role }, meta);
  }

  async logout(refreshToken: string | undefined): Promise<void> {
    if (refreshToken) await this.sessions.revoke(refreshToken);
  }

  async profile(auth: AuthContext): Promise<Profile> {
    const [user, memberships] = await Promise.all([
      UserModel.findById(auth.userId).lean().exec(),
      MembershipModel.find({ userId: auth.userId }).sort({ createdAt: 1 }).lean().exec(),
    ]);
    if (!user) throw new UnauthorizedError('Account no longer exists');

    const orgs = await this.organizations.findManyByIds(memberships.map((m) => m.orgId.toString()));
    const current = orgs.find((org) => org._id.toString() === auth.orgId);
    if (!current) throw new UnauthorizedError('You no longer have access to this organization');

    const nameById = new Map(orgs.map((org) => [org._id.toString(), org.name]));
    return {
      user: { id: user._id.toString(), name: user.name, email: user.email },
      organization: toOrganizationDto(current),
      role: auth.role,
      organizations: memberships.map((m) => ({
        id: m.orgId.toString(),
        name: nameById.get(m.orgId.toString()) ?? 'Unknown',
        role: m.role,
      })),
    };
  }

  private async startSession(context: AuthContext, meta: ClientMeta): Promise<AuthResult> {
    const { accessToken, expiresIn } = this.accessTokens.sign(context);
    const [issued, profile] = await Promise.all([
      this.sessions.issue(context.userId, context.orgId, meta),
      this.profile(context),
    ]);
    return { accessToken, expiresIn, refreshToken: issued.refreshToken, refreshExpiresAt: issued.expiresAt, profile };
  }

  private dummyHash(): Promise<string> {
    this.timingDummyHash ??= this.passwords.hash('timing-equaliser-not-a-real-password');
    return this.timingDummyHash;
  }
}
