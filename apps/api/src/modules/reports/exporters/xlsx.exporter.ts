import ExcelJS from 'exceljs';
import type { Writable } from 'node:stream';
import { formatDateTime, formatDayLabel, formatTime } from '../../../core/time/local-date.js';
import { DAY_MARK_LEGEND, type AttendanceReport, type DayMark } from '../report.types.js';
import { ReportExporter } from './report-exporter.js';

const solid = (argb: string): ExcelJS.Fill => ({ type: 'pattern', pattern: 'solid', fgColor: { argb } });

const MARK_FILLS: Partial<Record<DayMark, ExcelJS.Fill>> = {
  P: solid('FFC6EFCE'),
  L: solid('FFFFEB9C'),
  A: solid('FFFFC7CE'),
  H: solid('FFDDEBF7'),
  W: solid('FFEDEDED'),
};
const HEADER_FILL = solid('FF1F2937');
const HEADER_FONT: Partial<ExcelJS.Font> = { bold: true, color: { argb: 'FFFFFFFF' } };
const LOW_ATTENDANCE_FILL = solid('FFFFC7CE');
const LOW_ATTENDANCE_THRESHOLD = 75;
const CENTER: Partial<ExcelJS.Alignment> = { horizontal: 'center', vertical: 'middle' };

/**
 * Three sheets – Summary, Daily grid, Check-in log – streamed straight into the HTTP response,
 * so memory stays flat for large schools.
 */
export class XlsxReportExporter extends ReportExporter {
  readonly format = 'xlsx';
  readonly contentType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  readonly extension = 'xlsx';

  async write(report: AttendanceReport, out: Writable): Promise<void> {
    const workbook = new ExcelJS.stream.xlsx.WorkbookWriter({ stream: out, useStyles: true, useSharedStrings: false });
    workbook.creator = 'Attendance Platform';
    workbook.created = report.generatedAt;

    this.writeSummary(workbook, report);
    this.writeGrid(workbook, report);
    this.writeLog(workbook, report);
    await workbook.commit();
  }

  private writeSummary(workbook: ExcelJS.stream.xlsx.WorkbookWriter, report: AttendanceReport): void {
    const sheet = workbook.addWorksheet('Summary', { views: [{ state: 'frozen', ySplit: 5 }] });
    sheet.columns = [
      { key: 'name', width: 32 },
      { key: 'code', width: 12 },
      { key: 'group', width: 16 },
      { key: 'expected', width: 14 },
      { key: 'present', width: 10 },
      { key: 'late', width: 10 },
      { key: 'absent', width: 10 },
      { key: 'rate', width: 14 },
    ];

    const title = sheet.addRow([report.organization.name]);
    title.font = { bold: true, size: 14 };
    title.commit();
    const label = report.range.label ? `${report.range.label} · ` : '';
    sheet.addRow([`${label}Attendance ${report.range.from} to ${report.range.to}`]).commit();
    sheet
      .addRow([
        `Generated ${formatDateTime(report.generatedAt, report.organization.timezone)} (${report.organization.timezone})`,
      ])
      .commit();
    sheet.addRow([]).commit();

    const header = sheet.addRow(['Name', 'Code', 'Group', 'Expected days', 'Present', 'Late', 'Absent', 'Attendance']);
    header.eachCell((cell) => {
      cell.fill = HEADER_FILL;
      cell.font = HEADER_FONT;
    });
    header.commit();

    for (const row of report.rows) {
      const excelRow = sheet.addRow([
        row.fullName,
        row.code,
        row.group ?? '',
        row.expected,
        row.present,
        row.late,
        row.absent,
        row.attendanceRate === null ? '' : row.attendanceRate / 100,
      ]);
      const rateCell = excelRow.getCell(8);
      rateCell.numFmt = '0.0%';
      if (row.attendanceRate !== null && row.attendanceRate < LOW_ATTENDANCE_THRESHOLD) {
        rateCell.fill = LOW_ATTENDANCE_FILL;
      }
      excelRow.commit();
    }

    const { totals } = report;
    const totalRow = sheet.addRow([
      'TOTAL',
      '',
      `${totals.members} members`,
      totals.expected,
      totals.present,
      totals.late,
      totals.absent,
      totals.attendanceRate === null ? '' : totals.attendanceRate / 100,
    ]);
    totalRow.font = { bold: true };
    totalRow.getCell(8).numFmt = '0.0%';
    totalRow.commit();

    sheet.addRow([]).commit();
    sheet.addRow(['Legend']).commit();
    for (const [mark, meaning] of Object.entries(DAY_MARK_LEGEND)) {
      sheet.addRow([`${mark} = ${meaning}`]).commit();
    }
    sheet.commit();
  }

  private writeGrid(workbook: ExcelJS.stream.xlsx.WorkbookWriter, report: AttendanceReport): void {
    const sheet = workbook.addWorksheet('Daily grid', { views: [{ state: 'frozen', xSplit: 2, ySplit: 1 }] });
    sheet.columns = [{ width: 32 }, { width: 12 }, ...report.dates.map(() => ({ width: 11 }))];

    const header = sheet.addRow(['Name', 'Code', ...report.dates.map(formatDayLabel)]);
    header.eachCell((cell) => {
      cell.fill = HEADER_FILL;
      cell.font = HEADER_FONT;
      cell.alignment = CENTER;
    });
    header.commit();

    for (const row of report.rows) {
      const excelRow = sheet.addRow([row.fullName, row.code, ...row.marks]);
      row.marks.forEach((mark, index) => {
        const cell = excelRow.getCell(index + 3);
        cell.alignment = CENTER;
        const fill = MARK_FILLS[mark];
        if (fill) cell.fill = fill;
      });
      excelRow.commit();
    }
    sheet.commit();
  }

  private writeLog(workbook: ExcelJS.stream.xlsx.WorkbookWriter, report: AttendanceReport): void {
    const sheet = workbook.addWorksheet('Check-in log', { views: [{ state: 'frozen', ySplit: 1 }] });
    sheet.columns = [
      { width: 12 },
      { width: 32 },
      { width: 12 },
      { width: 10 },
      { width: 10 },
      { width: 10 },
      { width: 10 },
    ];
    const header = sheet.addRow(['Date', 'Name', 'Code', 'Status', 'Check-in', 'Check-out', 'Method']);
    header.eachCell((cell) => {
      cell.fill = HEADER_FILL;
      cell.font = HEADER_FONT;
    });
    header.commit();

    const zone = report.organization.timezone;
    for (const entry of report.log) {
      sheet
        .addRow([
          entry.date,
          entry.fullName,
          entry.code,
          entry.status,
          formatTime(entry.checkInAt, zone),
          formatTime(entry.checkOutAt, zone),
          entry.method,
        ])
        .commit();
    }
    sheet.commit();
  }
}
