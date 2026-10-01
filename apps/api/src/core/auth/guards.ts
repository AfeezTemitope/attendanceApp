import type { RequestHandler } from 'express';
import { ForbiddenError, UnauthorizedError } from '../errors/index.js';
import type { AccessTokenService } from './access-token.service.js';
import type { KioskContext } from './context.js';
import { authOf } from './context.js';
import { hasRole, type Role } from './roles.js';

export interface KioskAuthenticator {
  authenticate(token: string): Promise<KioskContext>;
}

function readAuthorization(header: string | undefined, scheme: string): string | null {
  if (!header) return null;
  const [actualScheme, value] = header.split(' ');
  return actualScheme?.toLowerCase() === scheme.toLowerCase() && value ? value.trim() : null;
}

export function createGuards(tokens: AccessTokenService, kiosks: KioskAuthenticator) {
  /** Requires `Authorization: Bearer <accessToken>`. */
  const authenticate: RequestHandler = (req, _res, next) => {
    const token = readAuthorization(req.get('authorization'), 'Bearer');
    if (!token) throw new UnauthorizedError();
    req.auth = tokens.verify(token);
    next();
  };

  /** Requires at least the given role in the current organisation. Use after `authenticate`. */
  const requireRole =
    (role: Role): RequestHandler =>
    (req, _res, next) => {
      if (!hasRole(authOf(req).role, role)) throw new ForbiddenError();
      next();
    };

  /** Requires `Authorization: Kiosk <deviceToken>`. */
  const authenticateKiosk: RequestHandler = async (req, _res, next) => {
    const token = readAuthorization(req.get('authorization'), 'Kiosk');
    if (!token) throw new UnauthorizedError('Kiosk authentication required');
    req.kiosk = await kiosks.authenticate(token);
    next();
  };

  return { authenticate, requireRole, authenticateKiosk };
}

export type Guards = ReturnType<typeof createGuards>;
