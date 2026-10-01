import { minutesOfDay } from '../../../core/time/local-date.js';
import { AttendancePolicy, type CheckInDecision } from './attendance-policy.js';

/** Schools and shift work: check-in closes at `closesAt`. */
export class FixedWindowPolicy extends AttendancePolicy {
  readonly kind = 'FIXED_WINDOW';

  protected evaluateTimeOfDay(minute: number): CheckInDecision {
    const closesAt = this.config.closesAt ?? this.config.lateAfter;
    if (minute > minutesOfDay(closesAt)) {
      return this.reject('WINDOW_CLOSED', `Check-in closed at ${closesAt}`);
    }
    return this.allow(this.statusAt(minute));
  }
}
