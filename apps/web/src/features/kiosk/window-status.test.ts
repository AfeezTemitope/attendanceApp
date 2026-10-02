import { describe, expect, it } from 'vitest';
import type { KioskSession } from '@/api/types';
import { windowStatus } from './window-status';

const school: Pick<KioskSession, 'policy' | 'today'> = {
  policy: { kind: 'FIXED_WINDOW', opensAt: '07:00', lateAfter: '08:00', closesAt: '08:30', allowCheckOut: false },
  today: { date: '2026-09-28', time: '07:30', isWorkday: true, isHoliday: false },
};
const office: Pick<KioskSession, 'policy' | 'today'> = {
  ...school,
  policy: { kind: 'FLEXIBLE_HOURS', opensAt: '06:00', lateAfter: '09:00', closesAt: null, allowCheckOut: true },
};

describe('windowStatus', () => {
  it.each([
    ['06:59', 'closed', 'Check-in opens at 07:00.'],
    ['07:00', 'open', 'On time until 08:00.'],
    ['08:00', 'open', 'On time until 08:00.'],
    ['08:01', 'late', 'Arrivals now count as late. Check-in closes at 08:30.'],
    ['08:30', 'late', 'Arrivals now count as late. Check-in closes at 08:30.'],
    ['08:31', 'closed', 'Check-in closed at 08:30.'],
  ])('fixed window at %s is %s', (time, tone, message) => {
    expect(windowStatus(school, time)).toEqual({ tone, message });
  });

  it('flexible hours never close, and mention check-out after a fixed window closes when allowed', () => {
    expect(windowStatus(office, '15:00')).toEqual({ tone: 'late', message: 'Arrivals now count as late.' });
    const withCheckOut = { ...school, policy: { ...school.policy, allowCheckOut: true } };
    expect(windowStatus(withCheckOut, '16:00').message).toBe('Check-in closed at 08:30. You can still check out.');
  });

  it('is closed on holidays and non-working days', () => {
    expect(windowStatus({ ...school, today: { ...school.today, isHoliday: true } }, '07:30').message).toMatch(
      /holiday/,
    );
    expect(windowStatus({ ...school, today: { ...school.today, isWorkday: false } }, '07:30')).toEqual({
      tone: 'closed',
      message: 'No check-in today.',
    });
  });
});
