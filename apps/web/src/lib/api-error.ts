/** Shape of every API error body: `{ error: { code, message, details? } }` */
interface ErrorBody {
  error?: { code?: string; message?: string; details?: unknown };
}

/** A failed API call. `code` and `reason` are stable and safe to branch on; `message` is user-facing. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = 'ApiError';
  }

  /** `details.reason` when the API supplied one (e.g. WINDOW_CLOSED, TOKEN_EXPIRED). */
  get reason(): string | undefined {
    const details = this.details;
    if (details && typeof details === 'object' && 'reason' in details && typeof details.reason === 'string') {
      return details.reason;
    }
    return undefined;
  }

  /** Field-level validation issues keyed by dotted path, e.g. { "user.email": "must be a valid email address" }. */
  get fieldErrors(): Record<string, string> {
    if (!Array.isArray(this.details)) return {};
    return Object.fromEntries(
      this.details
        .filter((issue): issue is { path: string; message: string } => typeof issue?.path === 'string')
        .map((issue) => [issue.path, issue.message]),
    );
  }

  static async fromResponse(response: Response): Promise<ApiError> {
    let body: ErrorBody = {};
    try {
      body = (await response.json()) as ErrorBody;
    } catch {
      // Non-JSON error (proxy page, captive portal…): fall back to a generic message.
    }
    return new ApiError(
      response.status,
      body.error?.code ?? `HTTP_${response.status}`,
      body.error?.message ?? defaultMessage(response.status),
      body.error?.details,
    );
  }

  static network(cause: unknown): ApiError {
    const error = new ApiError(0, 'NETWORK_ERROR', 'Cannot reach the server. Check your internet connection.');
    error.cause = cause;
    return error;
  }
}

function defaultMessage(status: number): string {
  if (status === 429) return 'Too many attempts. Wait a few minutes and try again.';
  if (status >= 500) return 'The server had a problem. Try again in a moment.';
  return 'The request could not be completed.';
}

export function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return 'Something went wrong.';
}
