import ExcelJS from 'exceljs';
import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import {
  CsvReportExporter,
  ReportExporterRegistry,
  XlsxReportExporter,
} from '../../src/modules/reports/exporters/index.js';
import type { AttendanceReport } from '../../src/modules/reports/report.types.js';
import { loadWorkbook } from '../support/harness.js';

const report: AttendanceReport = {
  organization: {
    id: 'org1',
    name: 'Tenderville School',
    slug: 'tenderville-school',
    type: 'SCHOOL',
    timezone: 'Africa/Lagos',
  },
  range: { from: '2026-09-14', to: '2026-09-16', label: '1st Term' },
  generatedAt: new Date('2026-09-21T09:00:00Z'),
  dates: ['2026-09-14', '2026-09-15', '2026-09-16'],
  holidays: [{ date: '2026-09-16', name: 'Founders Day' }],
  rows: [
    {
      memberId: 'm1',
      fullName: 'Adaeze "Ada" Okafor',
      code: '100001',
      group: 'JSS1, Gold',
      status: 'ACTIVE',
      marks: ['P', 'L', 'H'],
      expected: 2,
      present: 1,
      late: 1,
      attended: 2,
      absent: 0,
      attendanceRate: 100,
    },
    {
      memberId: 'm2',
      fullName: '=HYPERLINK("http://evil.example","click")',
      code: '100002',
      group: null,
      status: 'ACTIVE',
      marks: ['A', 'P', 'H'],
      expected: 2,
      present: 1,
      late: 0,
      attended: 1,
      absent: 1,
      attendanceRate: 50,
    },
  ],
  totals: { members: 2, expected: 4, present: 2, late: 1, attended: 3, absent: 1, attendanceRate: 75 },
  log: [
    {
      date: '2026-09-14',
      memberId: 'm1',
      fullName: 'Adaeze "Ada" Okafor',
      code: '100001',
      status: 'PRESENT',
      checkInAt: new Date('2026-09-14T06:40:00Z'),
      checkOutAt: null,
      method: 'CODE',
    },
  ],
};

async function render(exporter: { write(r: AttendanceReport, out: PassThrough): Promise<void> }): Promise<Buffer> {
  const out = new PassThrough();
  const chunks: Buffer[] = [];
  out.on('data', (chunk: Buffer) => chunks.push(chunk));
  await exporter.write(report, out);
  return Buffer.concat(chunks);
}

describe('CsvReportExporter', () => {
  it('writes a BOM, a header and one quoted line per member', async () => {
    const csv = (await render(new CsvReportExporter())).toString('utf8');
    expect(csv.startsWith('\uFEFF')).toBe(true);
    const lines = csv.slice(1).trim().split('\r\n');
    expect(lines[0]).toBe(
      'Name,Code,Group,Expected days,Present,Late,Absent,Attendance %,2026-09-14,2026-09-15,2026-09-16',
    );
    expect(lines[1]).toBe('"Adaeze ""Ada"" Okafor",100001,"JSS1, Gold",2,1,1,0,100,P,L,H');
  });

  it('neutralises spreadsheet formula injection in user-entered text', async () => {
    const csv = (await render(new CsvReportExporter())).toString('utf8');
    expect(csv).toContain(`"'=HYPERLINK(""http://evil.example"",""click"")"`);
  });
});

describe('XlsxReportExporter', () => {
  it('produces a valid workbook with Summary, Daily grid and Check-in log sheets', async () => {
    const workbook = await loadWorkbook(await render(new XlsxReportExporter()));

    expect(workbook.worksheets.map((sheet) => sheet.name)).toEqual(['Summary', 'Daily grid', 'Check-in log']);

    const summary = workbook.getWorksheet('Summary')!;
    expect(summary.getCell('A1').value).toBe('Tenderville School');
    expect(summary.getCell('A6').value).toBe('Adaeze "Ada" Okafor');
    expect(summary.getCell('H6').value).toBe(1); // 100% stored as a fraction, formatted as %
    expect(summary.getCell('H7').value).toBe(0.5);

    const grid = workbook.getWorksheet('Daily grid')!;
    expect(grid.getRow(2).values).toEqual([undefined, 'Adaeze "Ada" Okafor', '100001', 'P', 'L', 'H']);

    const log = workbook.getWorksheet('Check-in log')!;
    expect(log.getCell('E2').value).toBe('07:40'); // rendered in the organisation's timezone
  });

  it('stores user text as plain strings, never formulas', async () => {
    const workbook = await loadWorkbook(await render(new XlsxReportExporter()));
    const cell = workbook.getWorksheet('Summary')!.getCell('A7');
    expect(cell.type).toBe(ExcelJS.ValueType.String);
  });
});

describe('ReportExporterRegistry', () => {
  it('resolves each format to its exporter', () => {
    const registry = new ReportExporterRegistry();
    expect(registry.get('xlsx')).toBeInstanceOf(XlsxReportExporter);
    expect(registry.get('csv').fileName(report)).toBe('attendance_tenderville-school_2026-09-14_to_2026-09-16.csv');
  });
});
