import { isoWeekday, minutesOfDay, type LocalDate } from '../../../core/time/local-date.js';
import type { AttendancePolicyConfig, PolicyKind } from './policy-config.js';

export type AttendanceStatus = 'PRESENT' | 'LATE';

export type CheckInRejection = 'NON_WORKDAY' | 'HOLIDAY' | 'TOO_EARLY' | 'WINDOW_CLOSED';

export interface CheckInContext {
  /** Wall-clock time in the organisation's timezone, HH:mm */
  localTime: string;
  /** ISO weekday of the organisation's local date */
  weekday: number;
  isHoliday: boolean;
}

export type CheckInDecision =
  { allowed: true; status: AttendanceStatus } | { allowed: false; reason: CheckInRejection; message: string };

const allow = (status: AttendanceStatus): CheckInDecision => ({ allowed: true, status });
const reject = (reason: CheckInRejection, message: string): CheckInDecision => ({ allowed: false, reason, message });

/**
 * Decides whether a check-in is allowed and whether it is on time.
 *
 * Template method: `evaluateCheckIn` applies the rules every organisation shares
 * (work days, holidays, opening time), then hands the time-of-day decision to the subclass.
 * Pure and synchronous – no database, no clock – so it is trivially unit-testable.
 */
export abstract class AttendancePolicy {
  abstract readonly kind: PolicyKind;

  constructor(protected readonly config: AttendancePolicyConfig) {}

  evaluateCheckIn(context: CheckInContext): CheckInDecision {
    if (!this.isWorkday(context.weekday)) {
      return reject('NON_WORKDAY', 'Check-in is not open today');
    }
    if (context.isHoliday) {
      return reject('HOLIDAY', 'Today is a holiday');
    }
    const minute = minutesOfDay(context.localTime);
    if (minute < minutesOfDay(this.config.opensAt)) {
      return reject('TOO_EARLY', `Check-in opens at ${this.config.opensAt}`);
    }
    return this.evaluateTimeOfDay(minute);
  }

  isWorkday(weekday: number): boolean {
    return this.config.workDays.includes(weekday);
  }

  /** A day on which attendance is expected: a work day that is not a holiday. Used to derive absences. */
  isExpectedDay(date: LocalDate, holidays: ReadonlySet<LocalDate>): boolean {
    return this.isWorkday(isoWeekday(date)) && !holidays.has(date);
  }

  get allowsCheckOut(): boolean {
    return this.config.allowCheckOut;
  }

  /** On time up to and including `lateAfter`; late from the next minute. */
  protected statusAt(minute: number): AttendanceStatus {
    return minute > minutesOfDay(this.config.lateAfter) ? 'LATE' : 'PRESENT';
  }

  protected allow(status: AttendanceStatus): CheckInDecision {
    return allow(status);
  }

  protected reject(reason: CheckInRejection, message: string): CheckInDecision {
    return reject(reason, message);
  }

  protected abstract evaluateTimeOfDay(minuteOfDay: number): CheckInDecision;
}
