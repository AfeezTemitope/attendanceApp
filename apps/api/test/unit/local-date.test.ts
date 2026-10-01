import { describe, expect, it } from 'vitest';
import {
  daysInclusive,
  eachDate,
  isValidLocalDate,
  isValidTimeZone,
  minutesOfDay,
  toInstant,
  toZonedMoment,
} from '../../src/core/time/local-date.js';

describe('timezone handling', () => {
  it('converts UTC instants to the organisation-local date, time and weekday', () => {
    // 23:30 UTC on Monday is 00:30 on Tuesday in Lagos (UTC+1).
    expect(toZonedMoment(new Date('2026-09-28T23:30:00Z'), 'Africa/Lagos')).toEqual({
      date: '2026-09-29',
      time: '00:30',
      weekday: 2,
    });
  });

  it('round-trips a local date and time through an absolute instant', () => {
    const instant = toInstant('2026-09-28', '07:45', 'Africa/Lagos');
    expect(instant.toISOString()).toBe('2026-09-28T06:45:00.000Z');
    expect(toZonedMoment(instant, 'Africa/Lagos')).toMatchObject({ date: '2026-09-28', time: '07:45' });
  });

  it('validates IANA zones', () => {
    expect(isValidTimeZone('Africa/Lagos')).toBe(true);
    expect(isValidTimeZone('Mars/Olympus')).toBe(false);
  });
});

describe('calendar helpers', () => {
  it('lists every date inclusively across month boundaries', () => {
    expect(eachDate('2026-09-29', '2026-10-02')).toEqual(['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02']);
    expect(daysInclusive('2026-09-29', '2026-10-02')).toBe(4);
    expect(eachDate('2026-09-29', '2026-09-29')).toEqual(['2026-09-29']);
  });

  it('rejects impossible or malformed dates', () => {
    expect(isValidLocalDate('2026-02-28')).toBe(true);
    expect(isValidLocalDate('2026-02-30')).toBe(false);
    expect(isValidLocalDate('2026-9-1')).toBe(false);
    expect(isValidLocalDate('2026-09-01T00:00')).toBe(false);
  });

  it('converts HH:mm into minutes since midnight', () => {
    expect(minutesOfDay('00:00')).toBe(0);
    expect(minutesOfDay('08:30')).toBe(510);
    expect(minutesOfDay('23:59')).toBe(1439);
  });
});
