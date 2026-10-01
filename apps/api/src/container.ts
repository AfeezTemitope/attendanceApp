import type { AppConfig } from './config/app-config.js';
import { AccessTokenService } from './core/auth/access-token.service.js';
import { createGuards } from './core/auth/guards.js';
import type { Logger } from './core/logger.js';
import { createRateLimiters } from './core/middleware/rate-limit.js';
import { PasswordHasher } from './core/security/password-hasher.js';
import { systemClock, type Clock } from './core/time/clock.js';
import { AttendanceController, KioskDeviceController } from './modules/attendance/attendance.controller.js';
import { AttendanceRepository } from './modules/attendance/attendance.repository.js';
import { AttendanceService } from './modules/attendance/attendance.service.js';
import { CodePinResolver } from './modules/attendance/check-in/code-pin.resolver.js';
import { MemberResolverRegistry } from './modules/attendance/check-in/member-resolver.js';
import { QrTokenResolver } from './modules/attendance/check-in/qr-token.resolver.js';
import { AuthController } from './modules/auth/auth.controller.js';
import { AuthService } from './modules/auth/auth.service.js';
import { SessionService } from './modules/auth/session.service.js';
import { CalendarController } from './modules/calendar/calendar.controller.js';
import { HolidayRepository, PeriodRepository } from './modules/calendar/calendar.repositories.js';
import { CalendarService } from './modules/calendar/calendar.service.js';
import { KioskController } from './modules/kiosks/kiosk.controller.js';
import { KioskRepository, KioskService } from './modules/kiosks/kiosk.service.js';
import { MemberCodeGenerator } from './modules/members/member-code.generator.js';
import { MemberController } from './modules/members/member.controller.js';
import { MemberRepository } from './modules/members/member.repository.js';
import { MemberService } from './modules/members/member.service.js';
import { OrganizationController } from './modules/organizations/organization.controller.js';
import { OrganizationService } from './modules/organizations/organization.service.js';
import { TeamService } from './modules/organizations/team.service.js';
import { ReportExporterRegistry } from './modules/reports/exporters/index.js';
import { ReportController } from './modules/reports/report.controller.js';
import { ReportService } from './modules/reports/report.service.js';

export interface ContainerOptions {
  logger: Logger;
  clock?: Clock;
  /** Tests disable rate limiting so they can hammer endpoints. */
  rateLimiting?: boolean;
}

/** Composition root: the only place that knows which concrete class implements what. */
export function createContainer(config: AppConfig, options: ContainerOptions) {
  const clock = options.clock ?? systemClock;

  // Infrastructure
  const passwordHasher = new PasswordHasher(config.auth.bcryptRounds);
  const pinHasher = new PasswordHasher(Math.min(config.auth.bcryptRounds, 10));
  const accessTokens = new AccessTokenService(config.auth.jwtAccessSecret, config.auth.accessTokenTtlSeconds);

  // Repositories
  const memberRepository = new MemberRepository();
  const attendanceRepository = new AttendanceRepository();
  const kioskRepository = new KioskRepository();
  const holidayRepository = new HolidayRepository();
  const periodRepository = new PeriodRepository();

  // Services
  const organizations = new OrganizationService();
  const sessions = new SessionService(config.auth.refreshTokenTtlDays, clock);
  const auth = new AuthService(organizations, sessions, passwordHasher, accessTokens, clock);
  const team = new TeamService(passwordHasher, sessions);
  const calendar = new CalendarService(holidayRepository, periodRepository);
  const kiosks = new KioskService(kioskRepository, clock);
  const members = new MemberService(
    memberRepository,
    organizations,
    new MemberCodeGenerator(memberRepository),
    pinHasher,
    clock,
  );
  const resolvers = new MemberResolverRegistry([
    new CodePinResolver(memberRepository, pinHasher),
    new QrTokenResolver(memberRepository),
  ]);
  const attendance = new AttendanceService(
    organizations,
    calendar,
    memberRepository,
    attendanceRepository,
    resolvers,
    clock,
  );
  const reports = new ReportService(organizations, calendar, memberRepository, attendanceRepository, clock);

  // HTTP
  const guards = createGuards(accessTokens, kiosks);
  const limiters = createRateLimiters(options.rateLimiting === false ? { skip: () => true } : {});

  return {
    config,
    logger: options.logger,
    clock,
    guards,
    limiters,
    services: { auth, organizations, team, members, calendar, kiosks, attendance, reports },
    controllers: {
      auth: new AuthController(auth, config),
      organization: new OrganizationController(organizations, team),
      members: new MemberController(members),
      calendar: new CalendarController(calendar),
      kiosks: new KioskController(kiosks),
      attendance: new AttendanceController(attendance),
      kioskDevice: new KioskDeviceController(attendance),
      reports: new ReportController(reports, calendar, new ReportExporterRegistry()),
    },
  };
}

export type Container = ReturnType<typeof createContainer>;
