import { Schema, model, type Types } from 'mongoose';
import type { LocalDate } from '../../core/time/local-date.js';

export interface Holiday {
  orgId: Types.ObjectId;
  date: LocalDate;
  name: string;
}

const holidaySchema = new Schema<Holiday>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    date: { type: String, required: true },
    name: { type: String, required: true, trim: true, maxlength: 80 },
  },
  { timestamps: true },
);

holidaySchema.index({ orgId: 1, date: 1 }, { unique: true });

export const HolidayModel = model<Holiday>('Holiday', holidaySchema);
