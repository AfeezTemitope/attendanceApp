import cookieParser from 'cookie-parser';
import cors from 'cors';
import express, { Router, type Express } from 'express';
import helmet from 'helmet';
import type { Container } from './container.js';
import { isDatabaseReady } from './core/db/connect.js';
import { errorHandler, notFoundHandler } from './core/middleware/error-handler.js';
import { requestLogger } from './core/middleware/request-logger.js';
import { attendanceRoutes, kioskDeviceRoutes } from './modules/attendance/attendance.routes.js';
import { authRoutes } from './modules/auth/auth.routes.js';
import { holidayRoutes, periodRoutes } from './modules/calendar/calendar.routes.js';
import { kioskRoutes } from './modules/kiosks/kiosk.routes.js';
import { memberRoutes } from './modules/members/member.routes.js';
import { organizationRoutes, teamRoutes } from './modules/organizations/organization.routes.js';
import { reportRoutes } from './modules/reports/report.routes.js';

export function createApp(container: Container): Express {
  const { config, logger, guards, limiters, controllers } = container;
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);

  app.use(requestLogger(logger));
  app.use(helmet());
  app.use(cors({ origin: config.corsOrigins, credentials: true, maxAge: 600 }));
  app.use(express.json({ limit: '1mb' }));
  app.use(cookieParser());

  app.get('/api/health', (_req, res) => {
    const database = isDatabaseReady();
    res.status(database ? 200 : 503).json({ status: database ? 'ok' : 'degraded', database });
  });

  // Every router owns a distinct prefix, so router-level guards (e.g. `router.use(authenticate)`)
  // can never leak onto another module's routes.
  const v1 = Router();
  v1.use('/auth', authRoutes(controllers.auth, guards, limiters));
  v1.use('/organization', organizationRoutes(controllers.organization, guards));
  v1.use('/team', teamRoutes(controllers.organization, guards));
  v1.use('/members', memberRoutes(controllers.members, guards));
  v1.use('/holidays', holidayRoutes(controllers.calendar, guards));
  v1.use('/periods', periodRoutes(controllers.calendar, guards));
  v1.use('/attendance', attendanceRoutes(controllers.attendance, guards));
  v1.use('/reports', reportRoutes(controllers.reports, guards));
  v1.use('/kiosks', kioskRoutes(controllers.kiosks, guards));
  v1.use('/kiosk', kioskDeviceRoutes(controllers.kioskDevice, guards, limiters));
  app.use('/api/v1', v1);

  app.use('/api', notFoundHandler);
  app.use(errorHandler(logger));
  return app;
}
