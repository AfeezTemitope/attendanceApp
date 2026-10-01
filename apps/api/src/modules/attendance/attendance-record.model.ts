import { Schema, model, type Types } from 'mongoose';
import type { LocalDate } from '../../core/time/local-date.js';
import type { AttendanceStatus } from './policies/attendance-policy.js';

export const ATTENDANCE_STATUSES = ['PRESENT', 'LATE'] as const;
export const CHECK_IN_METHODS = ['CODE', 'QR', 'MANUAL'] as const;
export type CheckInMethod = (typeof CHECK_IN_METHODS)[number];

/**
 * One row per member per day they attended. Absences are derived, never stored:
 * expected days (work days − holidays, within the member's active span) minus attended days.
 */
export interface AttendanceRecord {
  orgId: Types.ObjectId;
  memberId: Types.ObjectId;
  /** Organisation-local calendar date. */
  date: LocalDate;
  checkInAt: Date;
  checkOutAt?: Date | undefined;
  status: AttendanceStatus;
  method: CheckInMethod;
  kioskId?: Types.ObjectId | undefined;
  /** Dashboard user who recorded or corrected it manually. */
  recordedBy?: Types.ObjectId | undefined;
  note?: string | undefined;
}

const attendanceRecordSchema = new Schema<AttendanceRecord>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    memberId: { type: Schema.Types.ObjectId, ref: 'Member', required: true },
    date: { type: String, required: true },
    checkInAt: { type: Date, required: true },
    checkOutAt: { type: Date },
    status: { type: String, enum: ATTENDANCE_STATUSES, required: true },
    method: { type: String, enum: CHECK_IN_METHODS, required: true },
    kioskId: { type: Schema.Types.ObjectId, ref: 'Kiosk' },
    recordedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    note: { type: String, trim: true, maxlength: 200 },
  },
  { timestamps: true },
);

// The database itself guarantees one check-in per member per day, even under concurrent requests.
attendanceRecordSchema.index({ memberId: 1, date: 1 }, { unique: true });
attendanceRecordSchema.index({ orgId: 1, date: 1 });

export const AttendanceRecordModel = model<AttendanceRecord>('AttendanceRecord', attendanceRecordSchema);
