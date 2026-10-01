import { DateTime, IANAZone } from 'luxon';

/** A calendar date in an organisation's own timezone, formatted YYYY-MM-DD. Sorts lexicographically. */
export type LocalDate = string;

const LOCAL_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export function isValidLocalDate(value: string): boolean {
  return LOCAL_DATE_PATTERN.test(value) && DateTime.fromISO(value, { zone: 'utc' }).isValid;
}

export function isValidTimeZone(zone: string): boolean {
  return IANAZone.isValidZone(zone);
}

export interface ZonedMoment {
  date: LocalDate;
  /** HH:mm, 24h */
  time: string;
  /** ISO weekday: 1 = Monday … 7 = Sunday */
  weekday: number;
}

/** Converts an absolute instant into the organisation's local calendar date and wall-clock time. */
export function toZonedMoment(instant: Date, zone: string): ZonedMoment {
  const local = DateTime.fromJSDate(instant, { zone });
  return {
    date: local.toFormat('yyyy-MM-dd'),
    time: local.toFormat('HH:mm'),
    weekday: local.weekday,
  };
}

export function toLocalDate(instant: Date, zone: string): LocalDate {
  return toZonedMoment(instant, zone).date;
}

/** Combines a local date and HH:mm in a zone into an absolute instant. */
export function toInstant(date: LocalDate, time: string, zone: string): Date {
  return DateTime.fromISO(`${date}T${time}`, { zone }).toJSDate();
}

export function isoWeekday(date: LocalDate): number {
  return DateTime.fromISO(date, { zone: 'utc' }).weekday;
}

export function minutesOfDay(time: string): number {
  const [hours = 0, minutes = 0] = time.split(':').map(Number);
  return hours * 60 + minutes;
}

export function daysInclusive(from: LocalDate, to: LocalDate): number {
  const start = DateTime.fromISO(from, { zone: 'utc' });
  const end = DateTime.fromISO(to, { zone: 'utc' });
  return Math.floor(end.diff(start, 'days').days) + 1;
}

/** Every calendar date from `from` to `to`, inclusive. */
export function eachDate(from: LocalDate, to: LocalDate): LocalDate[] {
  const dates: LocalDate[] = [];
  let cursor = DateTime.fromISO(from, { zone: 'utc' });
  const end = DateTime.fromISO(to, { zone: 'utc' });
  while (cursor <= end) {
    dates.push(cursor.toFormat('yyyy-MM-dd'));
    cursor = cursor.plus({ days: 1 });
  }
  return dates;
}

export function formatDayLabel(date: LocalDate): string {
  return DateTime.fromISO(date, { zone: 'utc' }).toFormat('ccc dd/MM');
}

export function formatTime(instant: Date | undefined | null, zone: string): string {
  return instant ? DateTime.fromJSDate(instant, { zone }).toFormat('HH:mm') : '';
}

export function formatDateTime(instant: Date, zone: string): string {
  return DateTime.fromJSDate(instant, { zone }).toFormat('yyyy-MM-dd HH:mm');
}
