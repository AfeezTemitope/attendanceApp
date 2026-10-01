import { z } from 'zod';
import { dateRangeSchema, localDateSchema } from '../../core/http/schemas.js';
import { daysInclusive } from '../../core/time/local-date.js';
import { PERIOD_TYPES } from './period.model.js';

export const MAX_RANGE_DAYS = 400;

export const createHolidaySchema = z.object({
  date: localDateSchema,
  name: z.string().trim().min(2).max(80),
});

export const holidayQuerySchema = dateRangeSchema;

const periodFields = {
  name: z.string().trim().min(2).max(80),
  type: z.enum(PERIOD_TYPES),
  startsOn: localDateSchema,
  endsOn: localDateSchema,
};

const validRange = (period: { startsOn?: string | undefined; endsOn?: string | undefined }) =>
  !period.startsOn || !period.endsOn || period.startsOn <= period.endsOn;

const withinLimit = (period: { startsOn?: string | undefined; endsOn?: string | undefined }) =>
  !period.startsOn || !period.endsOn || daysInclusive(period.startsOn, period.endsOn) <= MAX_RANGE_DAYS;

export const createPeriodSchema = z
  .object(periodFields)
  .refine(validRange, { message: 'endsOn must be on or after startsOn', path: ['endsOn'] })
  .refine(withinLimit, { message: `a period can span at most ${MAX_RANGE_DAYS} days`, path: ['endsOn'] });

export const updatePeriodSchema = z
  .object({
    name: periodFields.name.optional(),
    type: periodFields.type.optional(),
    startsOn: periodFields.startsOn.optional(),
    endsOn: periodFields.endsOn.optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'provide at least one field to update');

export type CreatePeriodInput = z.infer<typeof createPeriodSchema>;
export type UpdatePeriodInput = z.infer<typeof updatePeriodSchema>;
