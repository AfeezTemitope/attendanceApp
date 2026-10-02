import type { CheckInResult, CheckOutResult } from '@/api/types';
import { ApiError } from '@/lib/api-error';
import { timeIn } from '@/lib/format';

export type Outcome =
  | { kind: 'in'; late: boolean; name: string; detail: string }
  | { kind: 'out'; name: string; detail: string }
  | { kind: 'error'; message: string };

const firstName = (fullName: string) => fullName.split(/\s+/)[0] ?? fullName;

export function checkInOutcome(result: CheckInResult, timeZone: string): Outcome {
  const time = timeIn(timeZone, result.checkInAt);
  return {
    kind: 'in',
    late: result.status === 'LATE',
    name: firstName(result.member.fullName),
    detail: result.status === 'LATE' ? `Late, checked in at ${time}` : `On time, checked in at ${time}`,
  };
}

export function checkOutOutcome(result: CheckOutResult, timeZone: string): Outcome {
  return {
    kind: 'out',
    name: firstName(result.member.fullName),
    detail: `Checked out at ${timeIn(timeZone, result.checkOutAt)}`,
  };
}

/** Turns an API failure into one clear instruction for the person at the device. */
export function errorOutcome(error: unknown, timeZone: string): Outcome {
  if (!(error instanceof ApiError)) return { kind: 'error', message: 'Something went wrong. Try again.' };
  if (error.code === 'NETWORK_ERROR')
    return { kind: 'error', message: 'No internet connection. Try again in a moment.' };
  if (error.status === 429)
    return { kind: 'error', message: 'Too many wrong tries on this device. Wait a few minutes.' };
  if (error.status === 400) return { kind: 'error', message: 'That code doesn’t look right. Check it and try again.' };
  if (error.reason === 'INVALID_CREDENTIALS') {
    return { kind: 'error', message: 'We don’t recognise that code. Check it, and add your PIN if you have one.' };
  }
  if (error.reason === 'ALREADY_CHECKED_IN') {
    const at = (error.details as { checkInAt?: string | null } | undefined)?.checkInAt;
    return { kind: 'error', message: at ? `${error.message} at ${timeIn(timeZone, at)}.` : `${error.message}.` };
  }
  return { kind: 'error', message: error.message };
}
