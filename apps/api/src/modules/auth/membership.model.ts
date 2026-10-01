import { Schema, model, type Types } from 'mongoose';
import { ROLES, type Role } from '../../core/auth/roles.js';

/** Links a login (User) to an Organization with a role. One user can belong to several organisations. */
export interface Membership {
  userId: Types.ObjectId;
  orgId: Types.ObjectId;
  role: Role;
  createdAt: Date;
  updatedAt: Date;
}

const membershipSchema = new Schema<Membership>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    role: { type: String, enum: ROLES, required: true },
  },
  { timestamps: true },
);

membershipSchema.index({ userId: 1, orgId: 1 }, { unique: true });
membershipSchema.index({ orgId: 1, role: 1 });

export const MembershipModel = model<Membership>('Membership', membershipSchema);
