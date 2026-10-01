import type { Request } from 'express';
import { UnauthorizedError } from '../errors/index.js';
import type { Role } from './roles.js';

/** Identity of a signed-in dashboard user, scoped to one organisation. */
export interface AuthContext {
  userId: string;
  orgId: string;
  role: Role;
}

/** Identity of a registered check-in device. It can only check people in and out. */
export interface KioskContext {
  id: string;
  orgId: string;
  name: string;
}

export function authOf(req: Request): AuthContext {
  if (!req.auth) throw new UnauthorizedError();
  return req.auth;
}

export function kioskOf(req: Request): KioskContext {
  if (!req.kiosk) throw new UnauthorizedError('Kiosk authentication required');
  return req.kiosk;
}
