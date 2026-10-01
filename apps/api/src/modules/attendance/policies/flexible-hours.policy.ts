import { AttendancePolicy, type CheckInDecision } from './attendance-policy.js';

/** Offices: people can check in any time after opening; arriving after `lateAfter` is recorded as late. */
export class FlexibleHoursPolicy extends AttendancePolicy {
  readonly kind = 'FLEXIBLE_HOURS';

  protected evaluateTimeOfDay(minute: number): CheckInDecision {
    return this.allow(this.statusAt(minute));
  }
}
