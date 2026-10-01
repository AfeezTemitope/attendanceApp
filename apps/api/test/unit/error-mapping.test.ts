import mongoose from 'mongoose';
import { describe, expect, it } from 'vitest';
import {
  BusinessRuleError,
  ConflictError,
  ForbiddenError,
  NotFoundError,
  UnauthorizedError,
  ValidationError,
} from '../../src/core/errors/index.js';
import { mapError } from '../../src/core/middleware/error-handler.js';
import { CheckInRejectedError } from '../../src/modules/attendance/check-in/check-in.errors.js';

describe('mapError', () => {
  it.each([
    [new ValidationError('bad'), 400, 'VALIDATION_ERROR'],
    [new UnauthorizedError(), 401, 'UNAUTHORIZED'],
    [new ForbiddenError(), 403, 'FORBIDDEN'],
    [new NotFoundError('Member'), 404, 'NOT_FOUND'],
    [new ConflictError('dup'), 409, 'CONFLICT'],
    [new BusinessRuleError('nope'), 422, 'RULE_VIOLATION'],
    [new CheckInRejectedError('WINDOW_CLOSED', 'closed'), 422, 'CHECK_IN_REJECTED'],
  ])('maps %s polymorphically', (error, status, code) => {
    const mapped = mapError(error);
    expect(mapped.statusCode).toBe(status);
    expect(mapped.body.code).toBe(code);
  });

  it('keeps structured details', () => {
    expect(mapError(new CheckInRejectedError('HOLIDAY', 'Today is a holiday')).body).toEqual({
      code: 'CHECK_IN_REJECTED',
      message: 'Today is a holiday',
      details: { reason: 'HOLIDAY' },
    });
    expect(new NotFoundError('Member').message).toBe('Member not found');
  });

  it('turns MongoDB duplicate-key errors into 409 without leaking index internals', () => {
    const mapped = mapError({
      code: 11000,
      keyValue: { orgId: 'x', code: '123456' },
      errmsg: 'E11000 index: orgId_1_code_1',
    });
    expect(mapped.statusCode).toBe(409);
    expect(JSON.stringify(mapped.body)).not.toContain('E11000');
    expect(mapped.body.details).toEqual({ fields: ['orgId', 'code'] });
  });

  it('maps Mongoose cast errors to 400', () => {
    const error = new mongoose.Error.CastError('ObjectId', 'not-an-id', '_id');
    expect(mapError(error).statusCode).toBe(400);
  });

  it('never exposes the message of unexpected errors', () => {
    const mapped = mapError(new Error('connection string mongodb://admin:secret@db'));
    expect(mapped.statusCode).toBe(500);
    expect(mapped.body.message).not.toContain('secret');
    expect(mapped.body.code).toBe('INTERNAL_ERROR');
  });

  it('recognises malformed JSON bodies from express.json()', () => {
    expect(mapError(Object.assign(new SyntaxError('Unexpected token'), { type: 'entity.parse.failed' }))).toMatchObject(
      {
        statusCode: 400,
        body: { code: 'MALFORMED_JSON' },
      },
    );
  });
});
