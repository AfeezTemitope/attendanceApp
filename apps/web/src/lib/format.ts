/** API dates come in two shapes: org-local calendar dates ("2026-09-28") and absolute ISO instants. */

const LOCALE = 'en-NG';

/** Calendar date in a timezone, as YYYY-MM-DD. */
export function todayIn(timeZone: string, now: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

/** Wall-clock HH:mm in a timezone. */
export function timeIn(timeZone: string, instant: Date | string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', minute: '2-digit', hour12: false }).format(
    new Date(instant),
  );
}

/** Calendar dates are formatted in UTC so the viewer's own timezone can never shift them by a day. */
function calendar(date: string): Date {
  return new Date(`${date}T00:00:00Z`);
}

export function formatLongDate(date: string): string {
  return new Intl.DateTimeFormat(LOCALE, {
    timeZone: 'UTC',
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(calendar(date));
}

export function formatShortDate(date: string): string {
  return new Intl.DateTimeFormat(LOCALE, { timeZone: 'UTC', day: 'numeric', month: 'short', year: 'numeric' }).format(
    calendar(date),
  );
}

export function formatDayLabel(date: string): { weekday: string; day: string } {
  const d = calendar(date);
  return {
    weekday: new Intl.DateTimeFormat(LOCALE, { timeZone: 'UTC', weekday: 'narrow' }).format(d),
    day: String(d.getUTCDate()),
  };
}

export function addDays(date: string, days: number): string {
  const d = calendar(date);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

export function startOfMonth(date: string): string {
  return `${date.slice(0, 7)}-01`;
}

export function formatPercent(rate: number | null): string {
  if (rate === null) return '–';
  return `${Number.isInteger(rate) ? rate : rate.toFixed(1)}%`;
}

export function relativeTime(instant: string | null, now: Date = new Date()): string {
  if (!instant) return 'Never';
  const minutes = Math.round((now.getTime() - new Date(instant).getTime()) / 60_000);
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} h ago`;
  return `${Math.round(hours / 24)} days ago`;
}

export const WEEKDAYS = [
  { value: 1, short: 'Mon', long: 'Monday' },
  { value: 2, short: 'Tue', long: 'Tuesday' },
  { value: 3, short: 'Wed', long: 'Wednesday' },
  { value: 4, short: 'Thu', long: 'Thursday' },
  { value: 5, short: 'Fri', long: 'Friday' },
  { value: 6, short: 'Sat', long: 'Saturday' },
  { value: 7, short: 'Sun', long: 'Sunday' },
] as const;

/** "1 day", "2 days", "1 person", "3 people". */
export function plural(count: number, one: string, many = `${one}s`): string {
  return `${count} ${count === 1 ? one : many}`;
}
