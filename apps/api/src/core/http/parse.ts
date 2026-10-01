import type { z } from 'zod';
import { ValidationError } from '../errors/index.js';

/** Validates untrusted input against a schema and returns the typed, sanitised result. */
export function parse<Schema extends z.ZodType>(schema: Schema, input: unknown): z.output<Schema> {
  const result = schema.safeParse(input);
  if (!result.success) {
    throw new ValidationError(
      'Request validation failed',
      result.error.issues.map((issue) => ({
        path: issue.path.join('.'),
        message: issue.message,
      })),
    );
  }
  return result.data;
}
