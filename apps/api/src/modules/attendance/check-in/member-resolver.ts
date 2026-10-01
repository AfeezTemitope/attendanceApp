import type { MemberRecord } from '../../members/member.repository.js';
import { CheckInRejectedError } from './check-in.errors.js';

export interface CodeCredentials {
  method: 'CODE';
  code: string;
  pin?: string | undefined;
}

export interface QrCredentials {
  method: 'QR';
  token: string;
}

export type CheckInCredentials = CodeCredentials | QrCredentials;

/**
 * Strategy for identifying who is checking in. Each check-in method (typed code, QR card, and later
 * NFC or geofenced phone check-in) is one subclass; the attendance service never branches on method.
 */
export abstract class MemberResolver<C extends CheckInCredentials = CheckInCredentials> {
  abstract readonly method: C['method'];

  abstract resolve(orgId: string, credentials: C): Promise<MemberRecord>;

  /** One message for "unknown code", "wrong PIN" and "revoked QR", so responses never confirm which part was right. */
  protected reject(): never {
    throw new CheckInRejectedError('INVALID_CREDENTIALS', 'Check-in details not recognised');
  }
}

export class MemberResolverRegistry {
  private readonly byMethod = new Map<CheckInCredentials['method'], MemberResolver>();

  constructor(resolvers: MemberResolver[]) {
    for (const resolver of resolvers) this.byMethod.set(resolver.method, resolver);
  }

  resolve(orgId: string, credentials: CheckInCredentials): Promise<MemberRecord> {
    const resolver = this.byMethod.get(credentials.method);
    if (!resolver) throw new Error(`No resolver registered for check-in method ${credentials.method}`);
    return resolver.resolve(orgId, credentials);
  }
}
