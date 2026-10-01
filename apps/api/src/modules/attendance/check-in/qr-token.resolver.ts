import { sha256 } from '../../../core/security/tokens.js';
import type { MemberRecord, MemberRepository } from '../../members/member.repository.js';
import { MemberResolver, type QrCredentials } from './member-resolver.js';

/** Scanned QR token from a printed ID card. Rotating the token invalidates the old card. */
export class QrTokenResolver extends MemberResolver<QrCredentials> {
  readonly method = 'QR';

  constructor(private readonly members: MemberRepository) {
    super();
  }

  async resolve(orgId: string, { token }: QrCredentials): Promise<MemberRecord> {
    const member = await this.members.findActiveByQrHash(orgId, sha256(token));
    return member ?? this.reject();
  }
}
