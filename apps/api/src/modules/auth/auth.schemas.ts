import { z } from 'zod';
import { objectIdSchema } from '../../core/http/schemas.js';
import { createOrganizationSchema } from '../organizations/organization.schemas.js';

export const emailSchema = z.string().trim().toLowerCase().pipe(z.email('must be a valid email address').max(254));

export const passwordSchema = z
  .string()
  .min(8, 'must be at least 8 characters')
  .max(128, 'must be at most 128 characters');

export const personNameSchema = z.string().trim().min(2).max(120);

export const registerSchema = z.object({
  organization: createOrganizationSchema,
  user: z.object({
    name: personNameSchema,
    email: emailSchema,
    password: passwordSchema,
  }),
});

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1).max(128),
  organizationId: objectIdSchema.optional(),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
