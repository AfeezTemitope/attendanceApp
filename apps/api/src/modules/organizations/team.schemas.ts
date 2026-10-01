import { z } from 'zod';
import { ROLES } from '../../core/auth/roles.js';
import { objectIdSchema } from '../../core/http/schemas.js';
import { emailSchema, passwordSchema, personNameSchema } from '../auth/auth.schemas.js';

export const addTeammateSchema = z.object({
  email: emailSchema,
  role: z.enum(ROLES),
  /** Required only when the email has no account yet. Share it with them privately; they should change it. */
  name: personNameSchema.optional(),
  temporaryPassword: passwordSchema.optional(),
});

export const updateTeammateSchema = z.object({ role: z.enum(ROLES) });

export const userIdParamsSchema = z.object({ userId: objectIdSchema });

export type AddTeammateInput = z.infer<typeof addTeammateSchema>;
