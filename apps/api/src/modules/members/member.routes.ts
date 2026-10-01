import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { MemberController } from './member.controller.js';

export function memberRoutes(controller: MemberController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);

  router.get('/', controller.list);
  router.get('/groups', controller.groups);
  router.post('/', guards.requireRole('ADMIN'), controller.create);
  router.post('/import', guards.requireRole('ADMIN'), controller.import);
  router.get('/:id', controller.get);
  router.patch('/:id', guards.requireRole('ADMIN'), controller.update);
  router.delete('/:id', guards.requireRole('ADMIN'), controller.archive);
  router.post('/:id/qr-token', guards.requireRole('ADMIN'), controller.rotateQrToken);
  return router;
}
