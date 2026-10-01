import { Schema, model, type Types } from 'mongoose';

/** A registered check-in device (tablet at the gate, reception PC). */
export interface Kiosk {
  orgId: Types.ObjectId;
  name: string;
  tokenHash: string;
  /** Last characters of the token, so admins can tell devices apart without seeing the secret. */
  tokenHint: string;
  lastSeenAt?: Date;
  revokedAt?: Date;
}

const kioskSchema = new Schema<Kiosk>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true, index: true },
    name: { type: String, required: true, trim: true, maxlength: 80 },
    tokenHash: { type: String, required: true, unique: true, select: false },
    tokenHint: { type: String, required: true },
    lastSeenAt: { type: Date },
    revokedAt: { type: Date },
  },
  { timestamps: true },
);

export const KioskModel = model<Kiosk>('Kiosk', kioskSchema);
