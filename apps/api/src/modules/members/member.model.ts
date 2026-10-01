import { Schema, model, type Types } from 'mongoose';
import type { LocalDate } from '../../core/time/local-date.js';

export const MEMBER_STATUSES = ['ACTIVE', 'ARCHIVED'] as const;
export type MemberStatus = (typeof MEMBER_STATUSES)[number];

/**
 * A person whose attendance is tracked (student, teacher, employee).
 * Distinct from User, which is someone who logs into the dashboard.
 */
export interface Member {
  orgId: Types.ObjectId;
  fullName: string;
  /** Check-in code, unique within the organisation. */
  code: string;
  /** Class, department, team… free text used for filtering and reports. */
  group?: string | undefined;
  pinHash?: string | undefined;
  pinSet: boolean;
  qrTokenHash?: string | undefined;
  qrIssuedAt?: Date | undefined;
  status: MemberStatus;
  /** First day attendance is expected (org-local date). No absences are counted before it. */
  joinedOn: LocalDate;
  /** Set when archived. No absences are counted from this date on. History is kept. */
  archivedOn?: LocalDate | undefined;
}

const memberSchema = new Schema<Member>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    fullName: { type: String, required: true, trim: true, maxlength: 120 },
    code: { type: String, required: true, trim: true, uppercase: true, maxlength: 20 },
    group: { type: String, trim: true, maxlength: 60 },
    pinHash: { type: String, select: false },
    pinSet: { type: Boolean, required: true, default: false },
    qrTokenHash: { type: String, select: false },
    qrIssuedAt: { type: Date },
    status: { type: String, enum: MEMBER_STATUSES, required: true, default: 'ACTIVE' },
    joinedOn: { type: String, required: true },
    archivedOn: { type: String },
  },
  { timestamps: true },
);

memberSchema.index({ orgId: 1, code: 1 }, { unique: true });
memberSchema.index({ orgId: 1, status: 1, fullName: 1 });
memberSchema.index({ qrTokenHash: 1 });

export const MemberModel = model<Member>('Member', memberSchema);
