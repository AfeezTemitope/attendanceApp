import type { KioskSession } from '@/api/types';

export interface WindowStatus {
  tone: 'open' | 'late' | 'closed';
  message: string;
}

/** What the kiosk tells people walking up, at a given wall-clock time (HH:mm, org timezone). */
export function windowStatus(session: Pick<KioskSession, 'policy' | 'today'>, time: string): WindowStatus {
  const { policy, today } = session;
  if (today.isHoliday) return { tone: 'closed', message: 'Today is a holiday. Check-in is closed.' };
  if (!today.isWorkday) return { tone: 'closed', message: 'No check-in today.' };
  if (time < policy.opensAt) return { tone: 'closed', message: `Check-in opens at ${policy.opensAt}.` };
  if (time <= policy.lateAfter) return { tone: 'open', message: `On time until ${policy.lateAfter}.` };
  if (policy.kind === 'FIXED_WINDOW' && policy.closesAt) {
    if (time <= policy.closesAt)
      return { tone: 'late', message: `Arrivals now count as late. Check-in closes at ${policy.closesAt}.` };
    return {
      tone: 'closed',
      message: `Check-in closed at ${policy.closesAt}.${policy.allowCheckOut ? ' You can still check out.' : ''}`,
    };
  }
  return { tone: 'late', message: 'Arrivals now count as late.' };
}
