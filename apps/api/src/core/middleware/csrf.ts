import type { RequestHandler } from 'express';
import { ForbiddenError } from '../errors/index.js';

/**
 * Cookie-authenticated endpoints (refresh, logout) require a custom header.
 * Browsers cannot send custom headers cross-origin without a CORS preflight, which our allowlist rejects.
 */
export const requireAjaxHeader: RequestHandler = (req, _res, next) => {
  if (req.get('x-requested-with') !== 'XMLHttpRequest') {
    throw new ForbiddenError('Missing X-Requested-With header');
  }
  next();
};
