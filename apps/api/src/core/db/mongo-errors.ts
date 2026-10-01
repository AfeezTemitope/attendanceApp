export interface DuplicateKeyError {
  code: 11000;
  keyValue?: Record<string, unknown>;
}

/** MongoDB E11000: a unique index rejected the write. */
export function isDuplicateKeyError(error: unknown): error is DuplicateKeyError {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === 11000;
}
