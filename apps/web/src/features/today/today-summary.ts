import type { DailyView } from '@/api/types';

/** The day's register in one plain sentence, e.g. "18 of 24 in. 3 late. 6 not in yet." */
export function summarizeDay(day: DailyView): string {
  if (day.holiday) return `Holiday: ${day.holiday}. Nobody is expected.`;
  if (!day.isWorkday) return 'Not a working day. Nobody is expected.';
  const { expected, present, late, absent, notCheckedIn } = day.totals;
  if (expected === 0) return 'Nobody is expected yet. Add people to start taking attendance.';

  const attended = present + late;
  const parts = [day.isToday ? `${attended} of ${expected} in.` : `${attended} of ${expected} attended.`];
  if (late > 0) parts.push(`${late} late.`);
  if (day.isToday && notCheckedIn > 0) parts.push(`${notCheckedIn} not in yet.`);
  if (absent > 0) parts.push(`${absent} absent.`);
  if (attended === expected) parts.push('Everyone is accounted for.');
  return parts.join(' ');
}
