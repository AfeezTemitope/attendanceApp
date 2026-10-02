import { api } from './client';
import type {
  AttendanceReport,
  AttendanceStatus,
  DailyView,
  Holiday,
  ImportResult,
  Kiosk,
  Member,
  MemberHistory,
  MemberStatus,
  Organization,
  OrganizationType,
  PageMeta,
  Period,
  PeriodType,
  Policy,
  Profile,
  Role,
  Session,
  Teammate,
} from './types';

const AJAX = { 'X-Requested-With': 'XMLHttpRequest' };

export const authApi = {
  login: (body: { email: string; password: string }) => api.post<Session>('/auth/login', body, { skipRefresh: true }),
  register: (body: {
    organization: { name: string; type: OrganizationType; timezone: string };
    user: { name: string; email: string; password: string };
  }) => api.post<Session>('/auth/register', body, { skipRefresh: true }),
  logout: () => api.post<void>('/auth/logout', undefined, { skipRefresh: true, headers: AJAX }),
  me: () => api.get<Profile>('/auth/me'),
};

export interface MemberQuery {
  search?: string;
  group?: string;
  status?: MemberStatus | 'ALL';
  page?: number;
  limit?: number;
}

export interface MemberInput {
  fullName: string;
  code?: string;
  group?: string | null;
  pin?: string | null;
  joinedOn?: string;
  status?: MemberStatus;
}

export const membersApi = {
  list: (query: MemberQuery) => api.envelope<Member[], PageMeta>('/members', { query: { ...query } }),
  groups: () => api.get<string[]>('/members/groups'),
  get: (id: string) => api.get<Member>(`/members/${id}`),
  create: (body: MemberInput) => api.post<Member>('/members', body),
  update: (id: string, body: Partial<MemberInput>) => api.patch<Member>(`/members/${id}`, body),
  archive: (id: string) => api.delete<Member>(`/members/${id}`),
  issueQrToken: (id: string) => api.post<{ member: Member; qrToken: string }>(`/members/${id}/qr-token`),
  import: (members: Array<{ fullName: string; code?: string; group?: string; joinedOn?: string }>) =>
    api.post<ImportResult>('/members/import', { members }),
};

export const attendanceApi = {
  daily: (date?: string) => api.get<DailyView>('/attendance/daily', { date }),
  recordManually: (body: { memberId: string; date: string; status: AttendanceStatus; time?: string; note?: string }) =>
    api.post<{ id: string }>('/attendance/manual', body),
  deleteRecord: (id: string) => api.delete(`/attendance/${id}`),
};

export type ReportRange = { periodId: string } | { from: string; to: string };
export type ReportQuery = ReportRange & { group?: string };

export const reportsApi = {
  attendance: (query: ReportQuery) => api.get<AttendanceReport>('/reports/attendance', { ...query }),
  download: (query: ReportQuery, format: 'xlsx' | 'csv') => api.download('/reports/attendance', { ...query, format }),
  member: (id: string, from: string, to: string) => api.get<MemberHistory>(`/reports/members/${id}`, { from, to }),
};

export const organizationApi = {
  get: () => api.get<Organization>('/organization'),
  update: (body: { name?: string; timezone?: string }) => api.patch<Organization>('/organization', body),
  updatePolicy: (policy: Policy) => api.put<Organization>('/organization/policy', policy),
};

export const calendarApi = {
  holidays: (from: string, to: string) => api.get<Holiday[]>('/holidays', { from, to }),
  addHoliday: (body: { date: string; name: string }) => api.post<Holiday>('/holidays', body),
  removeHoliday: (id: string) => api.delete(`/holidays/${id}`),
  periods: () => api.get<Period[]>('/periods'),
  createPeriod: (body: { name: string; type: PeriodType; startsOn: string; endsOn: string }) =>
    api.post<Period>('/periods', body),
  updatePeriod: (id: string, body: Partial<{ name: string; type: PeriodType; startsOn: string; endsOn: string }>) =>
    api.patch<Period>(`/periods/${id}`, body),
  deletePeriod: (id: string) => api.delete(`/periods/${id}`),
};

export const kiosksApi = {
  list: () => api.get<Kiosk[]>('/kiosks'),
  create: (name: string) => api.post<{ kiosk: Kiosk; token: string }>('/kiosks', { name }),
  revoke: (id: string) => api.delete(`/kiosks/${id}`),
};

export const teamApi = {
  list: () => api.get<Teammate[]>('/team'),
  add: (body: { email: string; role: Role; name?: string; temporaryPassword?: string }) =>
    api.post<Teammate>('/team', body),
  changeRole: (userId: string, role: Role) => api.patch(`/team/${userId}`, { role }),
  remove: (userId: string) => api.delete(`/team/${userId}`),
};

/** Query keys in one place so invalidation never misses a cache entry. */
export const queryKeys = {
  daily: (date?: string) => ['attendance', 'daily', date ?? 'today'] as const,
  attendance: ['attendance'] as const,
  members: (query?: MemberQuery) => (query ? (['members', query] as const) : (['members'] as const)),
  member: (id: string) => ['members', 'detail', id] as const,
  groups: ['members', 'groups'] as const,
  memberHistory: (id: string, from: string, to: string) => ['reports', 'member', id, from, to] as const,
  report: (query: ReportQuery) => ['reports', 'attendance', query] as const,
  organization: ['organization'] as const,
  holidays: (from: string, to: string) => ['holidays', from, to] as const,
  periods: ['periods'] as const,
  kiosks: ['kiosks'] as const,
  team: ['team'] as const,
};
