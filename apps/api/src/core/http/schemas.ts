import { isValidObjectId } from 'mongoose';
import { z } from 'zod';
import { isValidLocalDate } from '../time/local-date.js';

export const objectIdSchema = z
  .string()
  .refine((value) => isValidObjectId(value) && /^[a-f\d]{24}$/i.test(value), 'must be a valid id');

export const idParamsSchema = z.object({ id: objectIdSchema });

export const localDateSchema = z.string().refine(isValidLocalDate, 'must be a valid date in YYYY-MM-DD format');

export const timeOfDaySchema = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'must be a time in HH:mm (24h) format');

export const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

export const dateRangeSchema = z
  .object({ from: localDateSchema, to: localDateSchema })
  .refine((range) => range.from <= range.to, { message: '"from" must be on or before "to"', path: ['to'] });
