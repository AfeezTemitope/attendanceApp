import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { CalendarController } from './calendar.controller.js';

/** Mounted at /holidays */
export function holidayRoutes(controller: CalendarController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/', controller.listHolidays);
  router.post('/', guards.requireRole('ADMIN'), controller.addHoliday);
  router.delete('/:id', guards.requireRole('ADMIN'), controller.removeHoliday);
  return router;
}

/** Mounted at /periods – terms, sessions, months used for reports. */
export function periodRoutes(controller: CalendarController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/', controller.listPeriods);
  router.post('/', guards.requireRole('ADMIN'), controller.createPeriod);
  router.patch('/:id', guards.requireRole('ADMIN'), controller.updatePeriod);
  router.delete('/:id', guards.requireRole('ADMIN'), controller.deletePeriod);
  return router;
}
