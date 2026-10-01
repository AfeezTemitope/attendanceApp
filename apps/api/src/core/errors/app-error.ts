export type ErrorDetails = Record<string, unknown> | readonly unknown[];

export interface ErrorBody {
  code: string;
  message: string;
  details?: ErrorDetails;
}

/**
 * Base class for every error the API raises on purpose.
 * Subclasses only declare their HTTP status and machine-readable code;
 * the error middleware handles all of them the same way (polymorphism over instanceof chains).
 */
export abstract class AppError extends Error {
  abstract readonly statusCode: number;
  abstract readonly code: string;
  readonly details: ErrorDetails | undefined;

  constructor(message: string, details?: ErrorDetails) {
    super(message);
    this.name = new.target.name;
    this.details = details;
  }

  toJSON(): ErrorBody {
    return {
      code: this.code,
      message: this.message,
      ...(this.details === undefined ? {} : { details: this.details }),
    };
  }
}

export class ValidationError extends AppError {
  readonly statusCode = 400;
  readonly code: string = 'VALIDATION_ERROR';
}

export class UnauthorizedError extends AppError {
  readonly statusCode = 401;
  readonly code = 'UNAUTHORIZED';

  constructor(message = 'Authentication required', details?: ErrorDetails) {
    super(message, details);
  }
}

export class ForbiddenError extends AppError {
  readonly statusCode = 403;
  readonly code = 'FORBIDDEN';

  constructor(message = 'You do not have permission to perform this action', details?: ErrorDetails) {
    super(message, details);
  }
}

export class NotFoundError extends AppError {
  readonly statusCode = 404;
  readonly code = 'NOT_FOUND';

  constructor(resource: string, details?: ErrorDetails) {
    super(`${resource} not found`, details);
  }
}

export class ConflictError extends AppError {
  readonly statusCode = 409;
  readonly code = 'CONFLICT';
}

/** The request is well-formed but breaks a domain rule (e.g. check-in window closed). */
export class BusinessRuleError extends AppError {
  readonly statusCode = 422;
  readonly code: string = 'RULE_VIOLATION';
}
