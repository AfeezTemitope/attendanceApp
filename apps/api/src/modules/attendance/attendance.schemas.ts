import { z } from 'zod';
import { localDateSchema, objectIdSchema, timeOfDaySchema } from '../../core/http/schemas.js';
import { memberCodeSchema, pinSchema } from '../members/member.schemas.js';
import { ATTENDANCE_STATUSES } from './attendance-record.model.js';

/** Every field is a string of a fixed shape, so query-operator injection ({"$ne": null}) is rejected with a 400. */
export const checkInSchema = z.discriminatedUnion('method', [
  z.object({ method: z.literal('CODE'), code: memberCodeSchema, pin: pinSchema.optional() }),
  z.object({ method: z.literal('QR'), token: z.string().regex(/^qr_[\w-]{20,64}$/, 'is not a valid QR token') }),
]);

export const dailyQuerySchema = z.object({ date: localDateSchema.optional() });

export const manualRecordSchema = z.object({
  memberId: objectIdSchema,
  date: localDateSchema,
  status: z.enum(ATTENDANCE_STATUSES),
  time: timeOfDaySchema.optional(),
  note: z.string().trim().max(200).optional(),
});

export type ManualRecordInput = z.infer<typeof manualRecordSchema>;
