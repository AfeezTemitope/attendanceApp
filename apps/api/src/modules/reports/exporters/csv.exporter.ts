import { once } from 'node:events';
import type { Writable } from 'node:stream';
import type { AttendanceReport } from '../report.types.js';
import { ReportExporter } from './report-exporter.js';

const FORMULA_TRIGGER = /^[=+\-@\t\r]/;

/** Quotes a CSV field when needed. */
function field(value: string | number | null): string {
  const text = value === null ? '' : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/** User-entered text: neutralise spreadsheet formula injection (=HYPERLINK(...), +cmd…). */
function userText(value: string | null): string {
  const text = value ?? '';
  return field(FORMULA_TRIGGER.test(text) ? `'${text}` : text);
}

/** One sheet: per-member summary followed by one column per day. Opens directly in Excel / Google Sheets. */
export class CsvReportExporter extends ReportExporter {
  readonly format = 'csv';
  readonly contentType = 'text/csv; charset=utf-8';
  readonly extension = 'csv';

  async write(report: AttendanceReport, out: Writable): Promise<void> {
    const writeLine = async (line: string) => {
      if (!out.write(`${line}\r\n`)) await once(out, 'drain');
    };

    out.write('\uFEFF'); // UTF-8 BOM so Excel renders names with accents correctly
    await writeLine(
      ['Name', 'Code', 'Group', 'Expected days', 'Present', 'Late', 'Absent', 'Attendance %', ...report.dates]
        .map(field)
        .join(','),
    );
    for (const row of report.rows) {
      await writeLine(
        [
          userText(row.fullName),
          userText(row.code),
          userText(row.group),
          field(row.expected),
          field(row.present),
          field(row.late),
          field(row.absent),
          field(row.attendanceRate),
          ...row.marks.map(field),
        ].join(','),
      );
    }
    out.end();
    await once(out, 'finish');
  }
}
