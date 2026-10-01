import { z } from 'zod';
import { localDateSchema, paginationSchema } from '../../core/http/schemas.js';
import { MEMBER_STATUSES } from './member.model.js';

export const memberCodeSchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z0-9-]{3,20}$/, 'must be 3–20 characters: letters, digits or dashes');

export const pinSchema = z.string().regex(/^\d{4,6}$/, 'must be 4–6 digits');

const fullNameSchema = z.string().trim().min(2).max(120);
const groupSchema = z.string().trim().min(1).max(60);

export const createMemberSchema = z.object({
  fullName: fullNameSchema,
  code: memberCodeSchema.optional(),
  group: groupSchema.optional(),
  pin: pinSchema.optional(),
  joinedOn: localDateSchema.optional(),
});

export const updateMemberSchema = z
  .object({
    fullName: fullNameSchema.optional(),
    code: memberCodeSchema.optional(),
    group: groupSchema.nullable().optional(),
    pin: pinSchema.nullable().optional(),
    status: z.enum(MEMBER_STATUSES).optional(),
    joinedOn: localDateSchema.optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'provide at least one field to update');

export const listMembersQuerySchema = paginationSchema.extend({
  search: z.string().trim().max(100).optional(),
  status: z.enum([...MEMBER_STATUSES, 'ALL']).default('ACTIVE'),
  group: groupSchema.optional(),
});

export const importMembersSchema = z.object({
  members: z
    .array(
      z.object({
        fullName: fullNameSchema,
        code: memberCodeSchema.optional(),
        group: groupSchema.optional(),
        joinedOn: localDateSchema.optional(),
      }),
    )
    .min(1)
    .max(1000, 'import at most 1000 members per request'),
});

export type CreateMemberInput = z.infer<typeof createMemberSchema>;
export type UpdateMemberInput = z.infer<typeof updateMemberSchema>;
export type ImportMembersInput = z.infer<typeof importMembersSchema>;
