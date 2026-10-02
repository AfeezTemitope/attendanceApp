/** Mirrors the API response shapes (the DTOs and services under apps/api/src/modules). */

export type Role = 'OWNER' | 'ADMIN' | 'VIEWER';
export type OrganizationType = 'SCHOOL' | 'COMPANY';
export type PolicyKind = 'FIXED_WINDOW' | 'FLEXIBLE_HOURS';

export interface Policy {
  kind: PolicyKind;
  workDays: number[];
  opensAt: string;
  lateAfter: string;
  closesAt?: string;
  allowCheckOut: boolean;
}

export interface Organization {
  id: string;
  name: string;
  slug: string;
  type: OrganizationType;
  timezone: string;
  policy: Policy;
  createdAt: string;
}

export interface Profile {
  user: { id: string; name: string; email: string };
  organization: Organization;
  role: Role;
  organizations: Array<{ id: string; name: string; role: Role }>;
}

export interface Session extends Profile {
  accessToken: string;
  expiresIn: number;
}

export type MemberStatus = 'ACTIVE' | 'ARCHIVED';

export interface Member {
  id: string;
  fullName: string;
  code: string;
  group: string | null;
  status: MemberStatus;
  joinedOn: string;
  archivedOn: string | null;
  pinSet: boolean;
  qrIssuedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface PageMeta {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

export interface ImportResult {
  created: number;
  skipped: Array<{ row: number; fullName: string; reason: string }>;
}

export type AttendanceStatus = 'PRESENT' | 'LATE';
export type DailyStatus = AttendanceStatus | 'ABSENT' | 'NOT_CHECKED_IN' | 'HOLIDAY' | 'NON_WORKDAY';
export type CheckInMethod = 'CODE' | 'QR' | 'MANUAL';

export interface DailyRow {
  member: { id: string; fullName: string; code: string; group: string | null };
  status: DailyStatus;
  recordId: string | null;
  checkInAt: string | null;
  checkOutAt: string | null;
  method: CheckInMethod | null;
}

export interface DailyView {
  date: string;
  isToday: boolean;
  isWorkday: boolean;
  holiday: string | null;
  totals: { expected: number; present: number; late: number; absent: number; notCheckedIn: number };
  rows: DailyRow[];
}

/** P present · L late · A absent · H holiday · W non-working day · - not applicable */
export type DayMark = 'P' | 'L' | 'A' | 'H' | 'W' | '-';

export interface ReportRow {
  memberId: string;
  fullName: string;
  code: string;
  group: string | null;
  status: MemberStatus;
  marks: DayMark[];
  expected: number;
  present: number;
  late: number;
  attended: number;
  absent: number;
  attendanceRate: number | null;
}

export interface ReportLogEntry {
  date: string;
  memberId: string;
  fullName: string;
  code: string;
  status: AttendanceStatus;
  checkInAt: string;
  checkOutAt: string | null;
  method: CheckInMethod;
}

export interface AttendanceReport {
  organization: { id: string; name: string; slug: string; type: OrganizationType; timezone: string };
  range: { from: string; to: string; label: string | null };
  generatedAt: string;
  dates: string[];
  holidays: Array<{ date: string; name: string }>;
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

export interface MemberHistory {
  range: AttendanceReport['range'];
  dates: string[];
  holidays: AttendanceReport['holidays'];
  summary: ReportRow;
  log: ReportLogEntry[];
}

export interface Holiday {
  id: string;
  date: string;
  name: string;
}

export type PeriodType = 'MONTH' | 'TERM' | 'SESSION' | 'CUSTOM';

export interface Period {
  id: string;
  name: string;
  type: PeriodType;
  startsOn: string;
  endsOn: string;
}

export interface Kiosk {
  id: string;
  name: string;
  tokenHint: string;
  lastSeenAt: string | null;
  revokedAt: string | null;
  createdAt: string;
}

export interface Teammate {
  userId: string;
  name: string;
  email: string;
  role: Role;
  addedAt: string;
}

export interface KioskSession {
  kiosk: { id: string; name: string };
  organization: { name: string; timezone: string };
  today: { date: string; time: string; isWorkday: boolean; isHoliday: boolean };
  policy: { kind: PolicyKind; opensAt: string; lateAfter: string; closesAt: string | null; allowCheckOut: boolean };
}

export type CheckInCredentials = { method: 'CODE'; code: string; pin?: string } | { method: 'QR'; token: string };

export interface CheckInResult {
  member: { id: string; fullName: string; group: string | null };
  status: AttendanceStatus;
  date: string;
  checkInAt: string;
}

export interface CheckOutResult {
  member: { id: string; fullName: string };
  date: string;
  checkInAt: string;
  checkOutAt: string;
}
