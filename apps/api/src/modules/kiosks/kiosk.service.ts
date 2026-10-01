import type { KioskContext } from '../../core/auth/context.js';
import type { KioskAuthenticator } from '../../core/auth/guards.js';
import { TenantRepository, toLean, type Lean } from '../../core/db/tenant-repository.js';
import { NotFoundError, UnauthorizedError } from '../../core/errors/index.js';
import { randomToken, sha256 } from '../../core/security/tokens.js';
import type { Clock } from '../../core/time/clock.js';
import { KioskModel, type Kiosk } from './kiosk.model.js';

export type KioskRecord = Lean<Kiosk>;

const LAST_SEEN_RESOLUTION_MS = 5 * 60 * 1000;

export class KioskRepository extends TenantRepository<Kiosk> {
  constructor() {
    super(KioskModel);
  }

  list(orgId: string): Promise<KioskRecord[]> {
    return KioskModel.find(this.scoped(orgId)).sort({ createdAt: -1 }).lean<KioskRecord[]>().exec();
  }

  async create(orgId: string, data: Omit<Kiosk, 'orgId'>): Promise<KioskRecord> {
    return toLean<Kiosk>(await KioskModel.create({ ...data, orgId }));
  }

  revoke(orgId: string, id: string, at: Date): Promise<KioskRecord | null> {
    return KioskModel.findOneAndUpdate(
      this.scoped(orgId, { _id: id, revokedAt: { $exists: false } }),
      { $set: { revokedAt: at } },
      { returnDocument: 'after' },
    )
      .lean<KioskRecord>()
      .exec();
  }
}

export class KioskService implements KioskAuthenticator {
  constructor(
    private readonly kiosks: KioskRepository,
    private readonly clock: Clock,
  ) {}

  list(orgId: string): Promise<KioskRecord[]> {
    return this.kiosks.list(orgId);
  }

  /** Registers a device. The token is shown once; only its hash is stored. */
  async create(orgId: string, name: string): Promise<{ kiosk: KioskRecord; token: string }> {
    const token = `kio_${randomToken(32)}`;
    const kiosk = await this.kiosks.create(orgId, { name, tokenHash: sha256(token), tokenHint: token.slice(-4) });
    return { kiosk, token };
  }

  async revoke(orgId: string, id: string): Promise<void> {
    const revoked = await this.kiosks.revoke(orgId, id, this.clock.now());
    if (!revoked) throw new NotFoundError('Active kiosk');
  }

  async authenticate(token: string): Promise<KioskContext> {
    const kiosk = await KioskModel.findOne({ tokenHash: sha256(token), revokedAt: { $exists: false } })
      .lean<KioskRecord>()
      .exec();
    if (!kiosk) throw new UnauthorizedError('Kiosk token is invalid or has been revoked');

    const now = this.clock.now();
    if (!kiosk.lastSeenAt || now.getTime() - kiosk.lastSeenAt.getTime() > LAST_SEEN_RESOLUTION_MS) {
      // Fire-and-forget: a heartbeat must never slow down or fail a check-in.
      void KioskModel.updateOne({ _id: kiosk._id }, { $set: { lastSeenAt: now } })
        .exec()
        .catch(() => undefined);
    }
    return { id: kiosk._id.toString(), orgId: kiosk.orgId.toString(), name: kiosk.name };
  }
}

export function toKioskDto(kiosk: KioskRecord) {
  return {
    id: kiosk._id.toString(),
    name: kiosk.name,
    tokenHint: kiosk.tokenHint,
    lastSeenAt: kiosk.lastSeenAt ?? null,
    revokedAt: kiosk.revokedAt ?? null,
    createdAt: kiosk.createdAt,
  };
}
