import type { ErrorRequestHandler, RequestHandler } from 'express';
import mongoose from 'mongoose';
import { isDuplicateKeyError } from '../db/mongo-errors.js';
import { AppError, NotFoundError, type ErrorBody } from '../errors/index.js';
import type { Logger } from '../logger.js';

interface MappedError {
  statusCode: number;
  body: ErrorBody;
}

function hasType(error: unknown, type: string): boolean {
  return typeof error === 'object' && error !== null && 'type' in error && error.type === type;
}

/** Translates any thrown value into a safe HTTP response. Internal details never leak to clients. */
export function mapError(error: unknown): MappedError {
  if (error instanceof AppError) {
    return { statusCode: error.statusCode, body: error.toJSON() };
  }
  if (isDuplicateKeyError(error)) {
    return {
      statusCode: 409,
      body: {
        code: 'CONFLICT',
        message: 'A record with the same unique value already exists',
        details: { fields: Object.keys(error.keyValue ?? {}) },
      },
    };
  }
  if (error instanceof mongoose.Error.CastError) {
    return { statusCode: 400, body: { code: 'VALIDATION_ERROR', message: `Invalid value for ${error.path}` } };
  }
  if (error instanceof mongoose.Error.ValidationError) {
    return {
      statusCode: 400,
      body: {
        code: 'VALIDATION_ERROR',
        message: 'Request validation failed',
        details: Object.values(error.errors).map((issue) => ({ path: issue.path, message: issue.message })),
      },
    };
  }
  if (hasType(error, 'entity.parse.failed')) {
    return { statusCode: 400, body: { code: 'MALFORMED_JSON', message: 'Request body is not valid JSON' } };
  }
  if (hasType(error, 'entity.too.large')) {
    return { statusCode: 413, body: { code: 'PAYLOAD_TOO_LARGE', message: 'Request body is too large' } };
  }
  return { statusCode: 500, body: { code: 'INTERNAL_ERROR', message: 'Something went wrong. Please try again.' } };
}

export function errorHandler(logger: Logger): ErrorRequestHandler {
  return (error: unknown, req, res, _next) => {
    const { statusCode, body } = mapError(error);
    if (statusCode >= 500) {
      (req.log ?? logger).error({ err: error }, 'Unhandled error');
    }
    if (res.headersSent) {
      res.end();
      return;
    }
    res.status(statusCode).json({ error: body });
  };
}

export const notFoundHandler: RequestHandler = (req, _res, next) => {
  next(new NotFoundError('Route', { method: req.method, path: req.path }));
};
