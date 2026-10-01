import type { Lean } from '../../core/db/tenant-repository.js';
import { UnauthorizedError } from '../../core/errors/index.js';
import { randomToken, sha256 } from '../../core/security/tokens.js';
import type { Clock } from '../../core/time/clock.js';
import { SessionModel, type Session } from './session.model.js';

export interface ClientMeta {
  userAgent?: string | undefined;
  ip?: string | undefined;
}

export interface IssuedRefreshToken {
  refreshToken: string;
  expiresAt: Date;
}

/** Two tabs refreshing at the same moment is normal; a token replayed long after rotation is theft. */
const REUSE_GRACE_MS = 30_000;
const DAY_MS = 86_400_000;

/**
 * Refresh-token sessions with rotation: every refresh revokes the presented token and issues a new one.
 * Presenting an already-rotated token (outside a short grace window) revokes every session of that user.
 */
export class SessionService {
  constructor(
    private readonly ttlDays: number,
    private readonly clock: Clock,
  ) {}

  async issue(userId: string, orgId: string, meta: ClientMeta): Promise<IssuedRefreshToken> {
    const refreshToken = randomToken(32);
    const expiresAt = new Date(this.clock.now().getTime() + this.ttlDays * DAY_MS);
    await SessionModel.create({
      userId,
      orgId,
      tokenHash: sha256(refreshToken),
      expiresAt,
      userAgent: meta.userAgent?.slice(0, 300),
      ip: meta.ip,
    });
    return { refreshToken, expiresAt };
  }

  /** Validates and consumes a refresh token. Returns the session it belonged to. */
  async consume(refreshToken: string): Promise<Lean<Session>> {
    const now = this.clock.now();
    const session = await SessionModel.findOne({ tokenHash: sha256(refreshToken) })
      .lean<Lean<Session>>()
      .exec();
    if (!session) throw new UnauthorizedError('Session not found', { reason: 'SESSION_INVALID' });

    if (session.revokedAt) {
      if (now.getTime() - session.revokedAt.getTime() > REUSE_GRACE_MS) {
        await this.revokeAllForUser(session.userId.toString());
      }
      throw new UnauthorizedError('Session is no longer valid', { reason: 'SESSION_REVOKED' });
    }
    if (session.expiresAt <= now) {
      throw new UnauthorizedError('Session expired', { reason: 'SESSION_EXPIRED' });
    }

    // Atomic claim: if another request rotated this token first, this one loses.
    const claimed = await SessionModel.updateOne(
      { _id: session._id, revokedAt: { $exists: false } },
      { $set: { revokedAt: now } },
    ).exec();
    if (claimed.modifiedCount !== 1) {
      throw new UnauthorizedError('Session is no longer valid', { reason: 'SESSION_REVOKED' });
    }
    return session;
  }

  async revoke(refreshToken: string): Promise<void> {
    await SessionModel.updateOne(
      { tokenHash: sha256(refreshToken), revokedAt: { $exists: false } },
      { $set: { revokedAt: this.clock.now() } },
    ).exec();
  }

  async revokeAllForUser(userId: string, orgId?: string): Promise<void> {
    await SessionModel.updateMany(
      { userId, ...(orgId ? { orgId } : {}), revokedAt: { $exists: false } },
      { $set: { revokedAt: this.clock.now() } },
    ).exec();
  }
}
