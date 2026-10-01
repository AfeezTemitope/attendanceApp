import type { PasswordHasher } from '../../../core/security/password-hasher.js';
import type { MemberRecord, MemberRepository } from '../../members/member.repository.js';
import { MemberResolver, type CodeCredentials } from './member-resolver.js';

/** Typed check-in code, plus a PIN when the member has one set. */
export class CodePinResolver extends MemberResolver<CodeCredentials> {
  readonly method = 'CODE';

  constructor(
    private readonly members: MemberRepository,
    private readonly pinHasher: PasswordHasher,
  ) {
    super();
  }

  async resolve(orgId: string, { code, pin }: CodeCredentials): Promise<MemberRecord> {
    const member = await this.members.findActiveByCodeWithPin(orgId, code);
    if (!member) return this.reject();
    if (member.pinHash) {
      if (!pin || !(await this.pinHasher.verify(pin, member.pinHash))) return this.reject();
    }
    const { pinHash: _secret, ...safe } = member;
    return safe as MemberRecord;
  }
}
