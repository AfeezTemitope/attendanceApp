import { z } from 'zod';
import { localDateSchema, objectIdSchema } from '../../core/http/schemas.js';
import { REPORT_FORMATS } from './report.types.js';

/** Either a saved period (term, session…) or an explicit from/to range. */
export const attendanceReportQuerySchema = z
  .object({
    periodId: objectIdSchema.optional(),
    from: localDateSchema.optional(),
    to: localDateSchema.optional(),
    group: z.string().trim().min(1).max(60).optional(),
    format: z.enum(REPORT_FORMATS).default('json'),
  })
  .refine((query) => Boolean(query.periodId) !== Boolean(query.from && query.to), {
    message: 'provide either periodId, or both from and to',
  })
  .refine((query) => !query.from || !query.to || query.from <= query.to, {
    message: '"from" must be on or before "to"',
    path: ['to'],
  });

export const memberReportQuerySchema = z
  .object({ from: localDateSchema, to: localDateSchema })
  .refine((query) => query.from <= query.to, { message: '"from" must be on or before "to"', path: ['to'] });
