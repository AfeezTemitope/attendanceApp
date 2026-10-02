import { describe, expect, it } from 'vitest';
import { ApiError } from '@/lib/api-error';
import { checkInOutcome, errorOutcome } from './outcome';

const LAGOS = 'Africa/Lagos';

describe('kiosk outcomes', () => {
  it('greets by first name with the local arrival time', () => {
    const outcome = checkInOutcome(
      {
        member: { id: '1', fullName: 'Chidi Okeke', group: null },
        status: 'LATE',
        date: '2026-09-28',
        checkInAt: '2026-09-28T07:12:00.000Z',
      },
      LAGOS,
    );
    expect(outcome).toEqual({ kind: 'in', late: true, name: 'Chidi', detail: 'Late, checked in at 08:12' });
  });

  it.each([
    [new ApiError(422, 'CHECK_IN_REJECTED', 'x', { reason: 'INVALID_CREDENTIALS' }), /don’t recognise that code/],
    [
      new ApiError(422, 'CHECK_IN_REJECTED', 'Check-in closed at 08:30', { reason: 'WINDOW_CLOSED' }),
      /^Check-in closed at 08:30$/,
    ],
    [
      new ApiError(409, 'CONFLICT', 'Chidi Okeke already checked in today', {
        reason: 'ALREADY_CHECKED_IN',
        checkInAt: '2026-09-28T06:45:00.000Z',
      }),
      /^Chidi Okeke already checked in today at 07:45\.$/,
    ],
    [new ApiError(429, 'TOO_MANY_REQUESTS', 'x'), /Wait a few minutes/],
    [new ApiError(0, 'NETWORK_ERROR', 'x'), /No internet connection/],
  ])('explains %s plainly', (error, expected) => {
    const outcome = errorOutcome(error, LAGOS);
    expect(outcome.kind).toBe('error');
    expect(outcome.kind === 'error' && outcome.message).toMatch(expected);
  });
});
