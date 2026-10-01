import { describe, expect, it } from 'vitest';
import {
  createAttendancePolicy,
  DEFAULT_POLICIES,
  FixedWindowPolicy,
  FlexibleHoursPolicy,
  policyConfigSchema,
  type CheckInContext,
} from '../../src/modules/attendance/policies/index.js';

const MONDAY = 1;
const SATURDAY = 6;
const at = (localTime: string, overrides: Partial<CheckInContext> = {}): CheckInContext => ({
  localTime,
  weekday: MONDAY,
  isHoliday: false,
  ...overrides,
});

describe('FixedWindowPolicy (school default: opens 07:00, late after 08:00, closes 08:30)', () => {
  const policy = createAttendancePolicy({ ...DEFAULT_POLICIES.SCHOOL, workDays: [1, 2, 3, 4, 5] });

  it('is selected by the factory for FIXED_WINDOW', () => {
    expect(policy).toBeInstanceOf(FixedWindowPolicy);
  });

  it.each([
    ['06:59', { allowed: false, reason: 'TOO_EARLY' }],
    ['07:00', { allowed: true, status: 'PRESENT' }],
    ['08:00', { allowed: true, status: 'PRESENT' }],
    ['08:01', { allowed: true, status: 'LATE' }],
    ['08:30', { allowed: true, status: 'LATE' }],
    ['08:31', { allowed: false, reason: 'WINDOW_CLOSED' }],
    ['15:00', { allowed: false, reason: 'WINDOW_CLOSED' }],
    ['23:59', { allowed: false, reason: 'WINDOW_CLOSED' }],
  ])('at %s → %o', (time, expected) => {
    expect(policy.evaluateCheckIn(at(time))).toMatchObject(expected);
  });

  it('rejects non-working days before looking at the time', () => {
    expect(policy.evaluateCheckIn(at('07:30', { weekday: SATURDAY }))).toMatchObject({
      allowed: false,
      reason: 'NON_WORKDAY',
    });
  });

  it('rejects holidays', () => {
    expect(policy.evaluateCheckIn(at('07:30', { isHoliday: true }))).toMatchObject({
      allowed: false,
      reason: 'HOLIDAY',
    });
  });
});

describe('FlexibleHoursPolicy (company default: opens 06:00, late after 09:00)', () => {
  const policy = createAttendancePolicy({ ...DEFAULT_POLICIES.COMPANY, workDays: [1, 2, 3, 4, 5] });

  it('is selected by the factory for FLEXIBLE_HOURS', () => {
    expect(policy).toBeInstanceOf(FlexibleHoursPolicy);
    expect(policy.allowsCheckOut).toBe(true);
  });

  it('accepts check-in all day after opening, marking late arrivals', () => {
    expect(policy.evaluateCheckIn(at('05:59'))).toMatchObject({ allowed: false, reason: 'TOO_EARLY' });
    expect(policy.evaluateCheckIn(at('09:00'))).toMatchObject({ allowed: true, status: 'PRESENT' });
    expect(policy.evaluateCheckIn(at('14:30'))).toMatchObject({ allowed: true, status: 'LATE' });
  });
});

describe('isExpectedDay', () => {
  const policy = createAttendancePolicy({ ...DEFAULT_POLICIES.SCHOOL, workDays: [1, 2, 3, 4, 5] });

  it('expects work days that are not holidays', () => {
    const holidays = new Set(['2026-10-01']); // Independence Day, a Thursday
    expect(policy.isExpectedDay('2026-09-28', holidays)).toBe(true); // Monday
    expect(policy.isExpectedDay('2026-10-01', holidays)).toBe(false); // holiday
    expect(policy.isExpectedDay('2026-10-03', holidays)).toBe(false); // Saturday
  });
});

describe('policyConfigSchema', () => {
  const base = { workDays: [1, 2, 3, 4, 5], opensAt: '07:00', lateAfter: '08:00', allowCheckOut: false };

  it('requires closesAt for FIXED_WINDOW', () => {
    expect(policyConfigSchema.safeParse({ kind: 'FIXED_WINDOW', ...base }).success).toBe(false);
    expect(policyConfigSchema.safeParse({ kind: 'FIXED_WINDOW', ...base, closesAt: '08:30' }).success).toBe(true);
  });

  it('rejects times out of order', () => {
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, lateAfter: '06:00' }).success).toBe(false);
    expect(policyConfigSchema.safeParse({ kind: 'FIXED_WINDOW', ...base, closesAt: '07:30' }).success).toBe(false);
  });

  it('normalises work days (dedupe + sort) and rejects invalid ones', () => {
    const parsed = policyConfigSchema.parse({ kind: 'FLEXIBLE_HOURS', ...base, workDays: [5, 1, 1, 3] });
    expect(parsed.workDays).toEqual([1, 3, 5]);
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, workDays: [0] }).success).toBe(false);
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, workDays: [] }).success).toBe(false);
  });

  it('rejects malformed times', () => {
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, opensAt: '7am' }).success).toBe(false);
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, opensAt: '24:00' }).success).toBe(false);
  });
});
