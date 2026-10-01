import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import { requireAjaxHeader } from '../../core/middleware/csrf.js';
import type { RateLimiters } from '../../core/middleware/rate-limit.js';
import type { AuthController } from './auth.controller.js';

export function authRoutes(controller: AuthController, guards: Guards, limiters: RateLimiters): Router {
  const router = Router();
  router.post('/register', limiters.auth, controller.register);
  router.post('/login', limiters.auth, controller.login);
  router.post('/refresh', requireAjaxHeader, controller.refresh);
  router.post('/logout', requireAjaxHeader, controller.logout);
  router.get('/me', guards.authenticate, controller.me);
  return router;
}
