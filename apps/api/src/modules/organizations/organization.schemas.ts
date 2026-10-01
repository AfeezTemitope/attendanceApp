import { z } from 'zod';
import { isValidTimeZone } from '../../core/time/local-date.js';
import { ORGANIZATION_TYPES } from './organization.model.js';

export const timezoneSchema = z.string().refine(isValidTimeZone, 'must be a valid IANA timezone, e.g. Africa/Lagos');

export const createOrganizationSchema = z.object({
  name: z.string().trim().min(2).max(120),
  type: z.enum(ORGANIZATION_TYPES),
  timezone: timezoneSchema.default('Africa/Lagos'),
});

export const updateOrganizationSchema = z
  .object({
    name: z.string().trim().min(2).max(120).optional(),
    timezone: timezoneSchema.optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'provide at least one field to update');

export type CreateOrganizationInput = z.infer<typeof createOrganizationSchema>;
export type UpdateOrganizationInput = z.infer<typeof updateOrganizationSchema>;
