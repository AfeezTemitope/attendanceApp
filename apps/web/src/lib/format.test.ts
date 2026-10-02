import { describe, expect, it } from 'vitest';
import { addDays, formatPercent, plural, timeIn, todayIn } from './format';

describe('format', () => {
  it('uses the organisation timezone, not the browser’s', () => {
    const lateEvening = new Date('2026-09-30T23:30:00.000Z'); // already 1 Oct in Lagos (UTC+1)
    expect(todayIn('Africa/Lagos', lateEvening)).toBe('2026-10-01');
    expect(todayIn('UTC', lateEvening)).toBe('2026-09-30');
    expect(timeIn('Africa/Lagos', '2026-09-28T06:45:00.000Z')).toBe('07:45');
  });

  it('does calendar arithmetic without timezone drift', () => {
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
  });

  it('writes counts and rates the way people read them', () => {
    expect(plural(1, 'absence')).toBe('1 absence');
    expect(plural(4, 'absence')).toBe('4 absences');
    expect(plural(1, 'person', 'people')).toBe('1 person');
    expect(plural(24, 'person', 'people')).toBe('24 people');
    expect(formatPercent(null)).toBe('–');
    expect(formatPercent(90)).toBe('90%');
    expect(formatPercent(83.333)).toBe('83.3%');
  });
});
