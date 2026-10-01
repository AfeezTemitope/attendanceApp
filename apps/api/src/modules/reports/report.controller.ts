import type { RequestHandler } from 'express';
import { authOf } from '../../core/auth/context.js';
import { NotFoundError } from '../../core/errors/index.js';
import { parse } from '../../core/http/parse.js';
import { sendData } from '../../core/http/respond.js';
import { idParamsSchema } from '../../core/http/schemas.js';
import type { CalendarService } from '../calendar/calendar.service.js';
import type { ReportExporterRegistry } from './exporters/index.js';
import { attendanceReportQuerySchema, memberReportQuerySchema } from './report.schemas.js';
import type { ReportService } from './report.service.js';

export class ReportController {
  constructor(
    private readonly reports: ReportService,
    private readonly calendar: CalendarService,
    private readonly exporters: ReportExporterRegistry,
  ) {}

  /** GET /reports/attendance?periodId=…|from=…&to=…&format=json|xlsx|csv&group=… */
  attendance: RequestHandler = async (req, res) => {
    const { orgId } = authOf(req);
    const query = parse(attendanceReportQuerySchema, req.query);

    const range = query.periodId
      ? await this.calendar.getPeriod(orgId, query.periodId).then((period) => ({
          from: period.startsOn,
          to: period.endsOn,
          label: period.name,
        }))
      : { from: query.from as string, to: query.to as string, label: null };

    const report = await this.reports.build(orgId, { ...range, group: query.group });
    await this.exporters.get(query.format).send(res, report);
  };

  /** GET /reports/members/:id?from=…&to=… – one person's history with day marks and totals. */
  member: RequestHandler = async (req, res) => {
    const { orgId } = authOf(req);
    const { id } = parse(idParamsSchema, req.params);
    const { from, to } = parse(memberReportQuerySchema, req.query);

    const report = await this.reports.build(orgId, { from, to, memberId: id });
    const row = report.rows[0];
    if (!row) throw new NotFoundError('Member attendance in this range');
    sendData(res, {
      range: report.range,
      dates: report.dates,
      holidays: report.holidays,
      summary: row,
      log: report.log,
    });
  };
}
