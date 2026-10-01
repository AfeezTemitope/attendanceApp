import { Schema, model, type Types } from 'mongoose';
import type { LocalDate } from '../../core/time/local-date.js';

export const PERIOD_TYPES = ['MONTH', 'TERM', 'SESSION', 'CUSTOM'] as const;
export type PeriodType = (typeof PERIOD_TYPES)[number];

/** A named reporting range: "1st Term 2026/27", "2026/27 Session", "Q3 2026"… */
export interface Period {
  orgId: Types.ObjectId;
  name: string;
  type: PeriodType;
  startsOn: LocalDate;
  endsOn: LocalDate;
}

const periodSchema = new Schema<Period>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    name: { type: String, required: true, trim: true, maxlength: 80 },
    type: { type: String, enum: PERIOD_TYPES, required: true },
    startsOn: { type: String, required: true },
    endsOn: { type: String, required: true },
  },
  { timestamps: true },
);

periodSchema.index({ orgId: 1, startsOn: -1 });

export const PeriodModel = model<Period>('Period', periodSchema);
