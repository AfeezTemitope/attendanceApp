import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { ReportController } from './report.controller.js';

export function reportRoutes(controller: ReportController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/attendance', controller.attendance);
  router.get('/members/:id', controller.member);
  return router;
}
