import type { LocalDate } from '../../core/time/local-date.js';
import type { CheckInMethod } from '../attendance/attendance-record.model.js';
import type { AttendanceStatus } from '../attendance/policies/attendance-policy.js';
import type { MemberStatus } from '../members/member.model.js';
import type { OrganizationType } from '../organizations/organization.model.js';

/**
 * P present · L late · A absent · H holiday · W non-working day
 * - not applicable (before joining, after archiving, in the future, or today before the member checked in)
 */
export type DayMark = 'P' | 'L' | 'A' | 'H' | 'W' | '-';

export const DAY_MARK_LEGEND: Record<DayMark, string> = {
  P: 'Present',
  L: 'Late',
  A: 'Absent',
  H: 'Holiday',
  W: 'Non-working day',
  '-': 'Not applicable',
};

export interface ReportRow {
  memberId: string;
  fullName: string;
  code: string;
  group: string | null;
  status: MemberStatus;
  /** One mark per entry in `AttendanceReport.dates`, same order. */
  marks: DayMark[];
  /** Days attendance was expected. */
  expected: number;
  /** On time. */
  present: number;
  late: number;
  /** present + late */
  attended: number;
  absent: number;
  /** attended / expected × 100, one decimal. Null when nothing was expected yet. */
  attendanceRate: number | null;
}

export interface ReportLogEntry {
  date: LocalDate;
  memberId: string;
  fullName: string;
  code: string;
  status: AttendanceStatus;
  checkInAt: Date;
  checkOutAt: Date | null;
  method: CheckInMethod;
}

export interface AttendanceReport {
  organization: { id: string; name: string; slug: string; type: OrganizationType; timezone: string };
  range: { from: LocalDate; to: LocalDate; label: string | null };
  generatedAt: Date;
  dates: LocalDate[];
  holidays: Array<{ date: LocalDate; name: string }>;
  rows: ReportRow[];
  totals: {
    members: number;
    expected: number;
    present: number;
    late: number;
    attended: number;
    absent: number;
    attendanceRate: number | null;
  };
  log: ReportLogEntry[];
}

export const REPORT_FORMATS = ['json', 'xlsx', 'csv'] as const;
export type ReportFormat = (typeof REPORT_FORMATS)[number];
