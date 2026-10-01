import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { OrganizationController } from './organization.controller.js';

/** Mounted at /organization */
export function organizationRoutes(controller: OrganizationController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/', controller.get);
  router.patch('/', guards.requireRole('ADMIN'), controller.update);
  router.put('/policy', guards.requireRole('ADMIN'), controller.updatePolicy);
  return router;
}

/** Mounted at /team – dashboard accounts of the organisation. */
export function teamRoutes(controller: OrganizationController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/', guards.requireRole('ADMIN'), controller.listTeam);
  router.post('/', guards.requireRole('ADMIN'), controller.addTeammate);
  router.patch('/:userId', guards.requireRole('OWNER'), controller.changeTeammateRole);
  router.delete('/:userId', guards.requireRole('OWNER'), controller.removeTeammate);
  return router;
}
