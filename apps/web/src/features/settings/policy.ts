import type { Policy } from '@/api/types';

/** Mirrors the API rule set so mistakes are caught before saving. */
export function validatePolicy(policy: Policy): string | null {
  if (policy.workDays.length === 0) return 'Choose at least one working day.';
  if (policy.lateAfter < policy.opensAt) return '“Late after” must be at or after the opening time.';
  if (policy.kind === 'FIXED_WINDOW' && (!policy.closesAt || policy.closesAt < policy.lateAfter)) {
    return '“Closes at” must be at or after “Late after”.';
  }
  return null;
}
