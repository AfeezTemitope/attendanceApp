import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { RateLimiters } from '../../core/middleware/rate-limit.js';
import type { AttendanceController, KioskDeviceController } from './attendance.controller.js';

export function attendanceRoutes(controller: AttendanceController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/daily', controller.daily);
  router.post('/manual', guards.requireRole('ADMIN'), controller.recordManually);
  router.delete('/:id', guards.requireRole('ADMIN'), controller.deleteRecord);
  return router;
}

export function kioskDeviceRoutes(controller: KioskDeviceController, guards: Guards, limiters: RateLimiters): Router {
  const router = Router();
  router.use(guards.authenticateKiosk);
  router.get('/session', controller.session);
  router.post('/check-in', limiters.checkInFailures, controller.checkIn);
  router.post('/check-out', limiters.checkInFailures, controller.checkOut);
  return router;
}
