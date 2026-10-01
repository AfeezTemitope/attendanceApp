import { BusinessRuleError } from '../../../core/errors/index.js';

export type CheckInRejectionReason =
  | 'NON_WORKDAY'
  | 'HOLIDAY'
  | 'TOO_EARLY'
  | 'WINDOW_CLOSED'
  | 'INVALID_CREDENTIALS'
  | 'CHECK_OUT_DISABLED'
  | 'NOT_CHECKED_IN';

/** A kiosk request that is valid but not allowed right now. 422 so kiosk clients never treat it as a logout. */
export class CheckInRejectedError extends BusinessRuleError {
  override readonly code = 'CHECK_IN_REJECTED';

  constructor(
    readonly reason: CheckInRejectionReason,
    message: string,
  ) {
    super(message, { reason });
  }
}
