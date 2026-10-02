import { describe, expect, it } from 'vitest';
import type { DailyView } from '@/api/types';
import { summarizeDay } from './today-summary';

const day = (overrides: Partial<DailyView>, totals: Partial<DailyView['totals']> = {}): DailyView => ({
  date: '2026-09-28',
  isToday: true,
  isWorkday: true,
  holiday: null,
  rows: [],
  ...overrides,
  totals: { expected: 24, present: 15, late: 3, absent: 0, notCheckedIn: 6, ...totals },
});

describe('summarizeDay', () => {
  it('reads like a sentence during the day', () => {
    expect(summarizeDay(day({}))).toBe('18 of 24 in. 3 late. 6 not in yet.');
  });

  it('switches to past tense with absences for past days', () => {
    expect(summarizeDay(day({ isToday: false }, { notCheckedIn: 0, absent: 6 }))).toBe(
      '18 of 24 attended. 3 late. 6 absent.',
    );
  });

  it('celebrates a full register, and handles holidays and empty registers', () => {
    expect(summarizeDay(day({}, { present: 24, late: 0, notCheckedIn: 0 }))).toBe(
      '24 of 24 in. Everyone is accounted for.',
    );
    expect(summarizeDay(day({ holiday: 'Independence Day' }))).toBe('Holiday: Independence Day. Nobody is expected.');
    expect(summarizeDay(day({}, { expected: 0 }))).toMatch(/Add people/);
  });
});
