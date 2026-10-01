import type { Response } from 'express';
import type { Writable } from 'node:stream';
import type { AttendanceReport } from '../report.types.js';
import { ReportExporter } from './report-exporter.js';

/** Inline JSON for the dashboard; overrides `send` because it is a normal API response, not a download. */
export class JsonReportExporter extends ReportExporter {
  readonly format = 'json';
  readonly contentType = 'application/json; charset=utf-8';
  readonly extension = 'json';

  override async send(res: Response, report: AttendanceReport): Promise<void> {
    res.status(200).json({ data: report });
  }

  async write(report: AttendanceReport, out: Writable): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      out.end(JSON.stringify(report), (error?: Error | null) => (error ? reject(error) : resolve()));
    });
  }
}
