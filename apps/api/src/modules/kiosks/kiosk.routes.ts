import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { KioskController } from './kiosk.controller.js';

export function kioskRoutes(controller: KioskController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate, guards.requireRole('ADMIN'));
  router.get('/', controller.list);
  router.post('/', controller.create);
  router.delete('/:id', controller.revoke);
  return router;
}
