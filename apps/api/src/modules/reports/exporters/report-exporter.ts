import type { Response } from 'express';
import type { Writable } from 'node:stream';
import type { AttendanceReport, ReportFormat } from '../report.types.js';

/**
 * Template for every report format. `send` owns the HTTP concerns (headers, file name);
 * subclasses only implement `write`, which renders the same report data into their format.
 */
export abstract class ReportExporter {
  abstract readonly format: ReportFormat;
  abstract readonly contentType: string;
  abstract readonly extension: string;

  async send(res: Response, report: AttendanceReport): Promise<void> {
    res.status(200);
    res.setHeader('Content-Type', this.contentType);
    res.setHeader('Content-Disposition', `attachment; filename="${this.fileName(report)}"`);
    res.setHeader('Cache-Control', 'no-store');
    await this.write(report, res);
  }

  fileName(report: AttendanceReport): string {
    return `attendance_${report.organization.slug}_${report.range.from}_to_${report.range.to}.${this.extension}`;
  }

  abstract write(report: AttendanceReport, out: Writable): Promise<void>;
}
