import { z } from 'zod';
import { timeOfDaySchema } from '../../../core/http/schemas.js';
import { minutesOfDay } from '../../../core/time/local-date.js';

export const POLICY_KINDS = ['FIXED_WINDOW', 'FLEXIBLE_HOURS'] as const;
export type PolicyKind = (typeof POLICY_KINDS)[number];

/**
 * FIXED_WINDOW   – check-in only between opensAt and closesAt (schools, shifts).
 * FLEXIBLE_HOURS – check-in any time after opensAt on a work day (offices).
 * Both mark people LATE after `lateAfter`.
 */
export interface AttendancePolicyConfig {
  kind: PolicyKind;
  /** ISO weekdays: 1 = Monday … 7 = Sunday */
  workDays: number[];
  opensAt: string;
  lateAfter: string;
  closesAt?: string | undefined;
  allowCheckOut: boolean;
}

const workDaysSchema = z
  .array(z.number().int().min(1).max(7))
  .min(1, 'at least one work day is required')
  .transform((days) => [...new Set(days)].sort((a, b) => a - b));

const sharedFields = {
  workDays: workDaysSchema,
  opensAt: timeOfDaySchema,
  lateAfter: timeOfDaySchema,
  allowCheckOut: z.boolean(),
};

export const policyConfigSchema = z
  .discriminatedUnion('kind', [
    z.object({ kind: z.literal('FIXED_WINDOW'), ...sharedFields, closesAt: timeOfDaySchema }),
    z.object({ kind: z.literal('FLEXIBLE_HOURS'), ...sharedFields }),
  ])
  .superRefine((policy, ctx) => {
    if (minutesOfDay(policy.lateAfter) < minutesOfDay(policy.opensAt)) {
      ctx.addIssue({ code: 'custom', path: ['lateAfter'], message: 'must be at or after opensAt' });
    }
    if (policy.kind === 'FIXED_WINDOW' && minutesOfDay(policy.closesAt) < minutesOfDay(policy.lateAfter)) {
      ctx.addIssue({ code: 'custom', path: ['closesAt'], message: 'must be at or after lateAfter' });
    }
  });

export const WEEKDAYS: readonly number[] = [1, 2, 3, 4, 5];

export const DEFAULT_POLICIES = {
  SCHOOL: {
    kind: 'FIXED_WINDOW',
    workDays: [...WEEKDAYS],
    opensAt: '07:00',
    lateAfter: '08:00',
    closesAt: '08:30',
    allowCheckOut: false,
  },
  COMPANY: {
    kind: 'FLEXIBLE_HOURS',
    workDays: [...WEEKDAYS],
    opensAt: '06:00',
    lateAfter: '09:00',
    allowCheckOut: true,
  },
} as const satisfies Record<string, AttendancePolicyConfig>;
