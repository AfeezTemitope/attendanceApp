import type { AttendancePolicy } from './attendance-policy.js';
import { FixedWindowPolicy } from './fixed-window.policy.js';
import { FlexibleHoursPolicy } from './flexible-hours.policy.js';
import type { AttendancePolicyConfig } from './policy-config.js';

export * from './attendance-policy.js';
export * from './policy-config.js';
export { FixedWindowPolicy, FlexibleHoursPolicy };

/** Factory: the stored `kind` picks the concrete policy. Adding a policy = one class + one case here. */
export function createAttendancePolicy(config: AttendancePolicyConfig): AttendancePolicy {
  switch (config.kind) {
    case 'FIXED_WINDOW':
      return new FixedWindowPolicy(config);
    case 'FLEXIBLE_HOURS':
      return new FlexibleHoursPolicy(config);
    default: {
      const unreachable: never = config.kind;
      throw new Error(`Unknown attendance policy: ${String(unreachable)}`);
    }
  }
}
