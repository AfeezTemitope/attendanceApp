#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
#  Attendance Platform v2 · Phase 2 (web app "Rollcall") installer
#
#  Requires Phase 1 (apps/api) to be installed already.
#
#  What it does
#    1. Removes the legacy client/ folder (it stays in git history)
#    2. Writes apps/web (React + Vite + TypeScript web app, tests, Vercel config)
#    3. Updates root files: package.json, package-lock.json, eslint.config.js,
#       .prettierignore, README.md, .github/workflows/ci.yml
#    4. Runs npm install
#
#  It does NOT touch apps/api or your apps/api/.env.
#  Idempotent: safe to re-run. It overwrites only the files listed above.
#
#  Usage (from the repo root, in Git Bash):
#    bash install-phase2-web.sh                # normal run
#    bash install-phase2-web.sh --skip-install # write files only
#    bash install-phase2-web.sh --force        # allow running with uncommitted changes
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

FILE_COUNT=89
SKIP_INSTALL=0
FORCE=0

say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --skip-install) SKIP_INSTALL=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) die "Unknown option: $arg (use --help)" ;;
  esac
done

# ── 1. Preconditions ─────────────────────────────────────────────────────────
[ -f package.json ] || die "Run this from the repo root (the folder that contains package.json)."
[ -f apps/api/package.json ] || die "Phase 1 is not installed here (no apps/api). Run install-phase1-api.sh first."
command -v node >/dev/null 2>&1 || die "Node.js not found. Install Node 24 LTS (or 22.22+)."
command -v npm >/dev/null 2>&1 || die "npm not found."
node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=22)?0:1)' \
  || die "Node $(node -v) is too old for the web app (React Router 8 needs 22.22+). Install Node 24 LTS: https://nodejs.org"

IN_GIT=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then IN_GIT=1; fi

# Only guard the first run; re-runs are expected to find the files this script wrote.
FIRST_RUN=0
if [ -d client ] || [ ! -d apps/web ]; then FIRST_RUN=1; fi
if [ "$FIRST_RUN" = 1 ] && [ "$IN_GIT" = 1 ] && [ "$FORCE" = 0 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  die "You have uncommitted changes. Commit Phase 1 first (or re-run with --force).
  Tip:  git add -A && git commit -m \"feat(api): v2 rebuild – phase 1\""
fi

# ── 2. Legacy cleanup ────────────────────────────────────────────────────────
if [ -d client ]; then
  if [ "$IN_GIT" = 1 ]; then
    rm -rf client
    ok "Removed legacy client/ (recoverable from git history)"
  else
    tar -czf legacy-client-v1.tgz client && rm -rf client
    ok "Not a git repo: archived legacy client/ to legacy-client-v1.tgz, then removed it"
  fi
fi

# ── 3. Project files ─────────────────────────────────────────────────────────
say "Writing $FILE_COUNT files (83 in apps/web, 6 at the root)…"
write() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

write 'apps/web/.env.example' <<'__ATTENDANCE_EOF__'
# Only needed if the API does not run on http://localhost:5000 during development.
API_PROXY_TARGET=http://localhost:5000

# Leave unset to call the API on the same origin (/api/v1) – recommended, see README "Deployment".
# VITE_API_URL=https://api.example.com/api/v1
__ATTENDANCE_EOF__

write 'apps/web/index.html' <<'__ATTENDANCE_EOF__'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="theme-color" content="#1d2b6b" />
    <meta name="description" content="Daily attendance for schools and companies." />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <title>Rollcall</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
__ATTENDANCE_EOF__

write 'apps/web/package.json' <<'__ATTENDANCE_EOF__'
{
  "name": "@attendance/web",
  "version": "2.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "npm run typecheck && vite build",
    "preview": "vite preview",
    "typecheck": "tsc -p tsconfig.json && tsc -p tsconfig.node.json",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@fontsource-variable/bricolage-grotesque": "^5.3.0",
    "@fontsource-variable/hanken-grotesk": "^5.3.0",
    "@hookform/resolvers": "^5.9.1",
    "@tanstack/react-query": "^5.104.1",
    "barcode-detector": "^3.2.2",
    "clsx": "^2.1.1",
    "lucide-react": "^1.50.0",
    "papaparse": "^5.7.0",
    "qrcode": "^1.5.4",
    "react": "^19.3.0",
    "react-dom": "^19.3.0",
    "react-hook-form": "^7.89.0",
    "react-router": "^8.4.0",
    "sonner": "^2.0.8",
    "tailwind-merge": "^3.7.0",
    "zod": "^4.6.5",
    "zxing-wasm": "3.1.3"
  },
  "devDependencies": {
    "@tailwindcss/vite": "^4.3.3",
    "@testing-library/jest-dom": "^7.0.1",
    "@testing-library/react": "^16.3.3",
    "@testing-library/user-event": "^14.6.7",
    "@types/papaparse": "^5.5.2",
    "@types/qrcode": "^1.5.6",
    "@types/react": "^19.3.0",
    "@types/react-dom": "^19.3.0",
    "@vitejs/plugin-react": "^6.1.1",
    "jsdom": "^30.1.1",
    "tailwindcss": "^4.3.3",
    "vite": "^8.3.2",
    "vitest": "^5.0.2"
  }
}
__ATTENDANCE_EOF__

write 'apps/web/public/favicon.svg' <<'__ATTENDANCE_EOF__'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="7" fill="#1d2b6b"/><path d="M6 11h20M6 21h20" stroke="#3a4785" stroke-width="1.5"/><path d="M9.5 16.5l4.5 4.5 9-11" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>
__ATTENDANCE_EOF__

write 'apps/web/src/api/client.ts' <<'__ATTENDANCE_EOF__'
import { SessionHttpClient } from '@/lib/http';
import type { Session } from './types';

/** Same-origin by default: Vite proxies /api in development and the host rewrites it in production. */
export const API_BASE_URL: string = import.meta.env.VITE_API_URL ?? '/api/v1';

/** The dashboard's single API client. Auth state is wired up by AuthProvider. */
export const api = new SessionHttpClient<Session>(API_BASE_URL);
__ATTENDANCE_EOF__

write 'apps/web/src/api/endpoints.ts' <<'__ATTENDANCE_EOF__'
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
__ATTENDANCE_EOF__

write 'apps/web/src/api/types.ts' <<'__ATTENDANCE_EOF__'
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
__ATTENDANCE_EOF__

write 'apps/web/src/app/brand.ts' <<'__ATTENDANCE_EOF__'
export const APP_NAME = 'Rollcall';
__ATTENDANCE_EOF__

write 'apps/web/src/app/providers.tsx' <<'__ATTENDANCE_EOF__'
import { QueryClientProvider } from '@tanstack/react-query';
import { useState, type ReactNode } from 'react';
import { Toaster } from 'sonner';
import { createQueryClient } from './query-client';

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(createQueryClient);
  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <Toaster position="top-center" toastOptions={{ classNames: { toast: 'font-sans' } }} />
    </QueryClientProvider>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/app/query-client.ts' <<'__ATTENDANCE_EOF__'
import { QueryClient } from '@tanstack/react-query';
import { ApiError } from '@/lib/api-error';

export function createQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        // Retry network blips and 5xx; a 4xx will not fix itself.
        retry: (failureCount, error) =>
          failureCount < 2 && !(error instanceof ApiError && error.status >= 400 && error.status < 500),
      },
      mutations: { retry: false },
    },
  });
}
__ATTENDANCE_EOF__

write 'apps/web/src/app/route-error.tsx' <<'__ATTENDANCE_EOF__'
import { isRouteErrorResponse, Link, useRouteError } from 'react-router';
import { APP_NAME } from './brand';

export function RouteError() {
  const error = useRouteError();
  const notFound = isRouteErrorResponse(error) && error.status === 404;
  return (
    <ErrorScreen
      title={notFound ? 'Page not found' : 'This page failed to load'}
      detail={
        notFound ? 'The link may be out of date.' : 'Reload the page. If it keeps happening, sign out and back in.'
      }
    />
  );
}

export function NotFound() {
  return <ErrorScreen title="Page not found" detail="The link may be out of date." />;
}

function ErrorScreen({ title, detail }: { title: string; detail: string }) {
  return (
    <main className="flex min-h-screen flex-col items-start justify-center gap-3 px-8 sm:px-16">
      <p className="font-display text-xl font-semibold text-ink">{APP_NAME}</p>
      <h1 className="text-4xl font-semibold">{title}</h1>
      <p className="text-muted">{detail}</p>
      <Link to="/" className="mt-2 font-semibold text-ink underline underline-offset-4">
        Go to today’s register
      </Link>
    </main>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/app/router.tsx' <<'__ATTENDANCE_EOF__'
import type { RouteObject } from 'react-router';
import { AppShell } from '@/components/layout/app-shell';
import { SessionRoot } from '@/features/auth/auth-context';
import { GuestOnly, RequireAuth } from '@/features/auth/guards';
import { TodayPage } from '@/features/today/today-page';
import { NotFound, RouteError } from './route-error';

export const routes: RouteObject[] = [
  {
    element: <SessionRoot />,
    errorElement: <RouteError />,
    children: [
      {
        // Form pages carry zod and react-hook-form; signed-in users never download them.
        path: '/login',
        lazy: () =>
          import('@/features/auth/login-page').then(({ LoginPage }) => ({
            element: (
              <GuestOnly>
                <LoginPage />
              </GuestOnly>
            ),
          })),
      },
      {
        path: '/register',
        lazy: () =>
          import('@/features/auth/register-page').then(({ RegisterPage }) => ({
            element: (
              <GuestOnly>
                <RegisterPage />
              </GuestOnly>
            ),
          })),
      },
      {
        path: '/',
        element: (
          <RequireAuth>
            <AppShell />
          </RequireAuth>
        ),
        children: [
          { index: true, element: <TodayPage /> },
          {
            path: 'people',
            lazy: () => import('@/features/people/people-page').then((m) => ({ Component: m.PeoplePage })),
          },
          {
            path: 'people/:id',
            lazy: () => import('@/features/people/person-page').then((m) => ({ Component: m.PersonPage })),
          },
          {
            path: 'reports',
            lazy: () => import('@/features/reports/reports-page').then((m) => ({ Component: m.ReportsPage })),
          },
          {
            path: 'settings',
            lazy: () => import('@/features/settings/settings-page').then((m) => ({ Component: m.SettingsPage })),
          },
        ],
      },
    ],
  },
  // The kiosk bundle (camera + QR decoder) only loads on check-in devices.
  {
    path: '/kiosk',
    errorElement: <RouteError />,
    lazy: () => import('@/features/kiosk/kiosk-page').then((m) => ({ Component: m.KioskPage })),
  },
  {
    path: '/kiosk/pair',
    errorElement: <RouteError />,
    lazy: () => import('@/features/kiosk/pair-page').then((m) => ({ Component: m.PairPage })),
  },
  { path: '*', element: <NotFound /> },
];
__ATTENDANCE_EOF__

write 'apps/web/src/components/layout/app-shell.tsx' <<'__ATTENDANCE_EOF__'
import { CalendarCheck, FileSpreadsheet, LogOut, Settings, Users } from 'lucide-react';
import { NavLink, Outlet } from 'react-router';
import { APP_NAME } from '@/app/brand';
import { useAuth, useProfile } from '@/features/auth/use-auth';
import { ROLE_LABEL } from '@/features/auth/roles';
import { cn } from '@/lib/cn';

const NAV = [
  { to: '/', label: 'Today', icon: CalendarCheck, end: true },
  { to: '/people', label: 'People', icon: Users, end: false },
  { to: '/reports', label: 'Reports', icon: FileSpreadsheet, end: false },
  { to: '/settings', label: 'Settings', icon: Settings, end: false },
] as const;

export function AppShell() {
  const profile = useProfile();
  const { logout } = useAuth();

  return (
    <div className="min-h-screen md:grid md:grid-cols-[15rem_1fr]">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:rounded-lg focus:bg-paper focus:px-3 focus:py-2"
      >
        Skip to content
      </a>

      {/* Sidebar (tablet and up) */}
      <aside className="sticky top-0 hidden h-screen flex-col border-r border-rule bg-paper md:flex">
        <div className="px-5 pt-6 pb-5">
          <p className="font-display text-2xl font-semibold text-ink">{APP_NAME}</p>
          <p className="mt-0.5 truncate text-sm text-muted" title={profile.organization.name}>
            {profile.organization.name}
          </p>
        </div>
        <nav aria-label="Main" className="flex flex-col gap-0.5 px-3">
          {NAV.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                cn(
                  'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                  isActive ? 'bg-ink text-white' : 'text-muted hover:bg-ink-wash hover:text-ink',
                )
              }
            >
              <Icon className="size-4.5" aria-hidden />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="mt-auto border-t border-rule px-5 py-4">
          <p className="truncate text-sm font-semibold">{profile.user.name}</p>
          <p className="text-xs text-muted">{ROLE_LABEL[profile.role]}</p>
          <button
            type="button"
            onClick={() => void logout()}
            className="mt-3 inline-flex items-center gap-2 text-sm text-muted hover:text-ink"
          >
            <LogOut className="size-4" aria-hidden />
            Sign out
          </button>
        </div>
      </aside>

      {/* Top bar (phones) */}
      <header className="flex items-center justify-between border-b border-rule bg-paper px-4 py-3 md:hidden">
        <div className="min-w-0">
          <p className="font-display text-xl font-semibold text-ink">{APP_NAME}</p>
          <p className="truncate text-xs text-muted">{profile.organization.name}</p>
        </div>
        <button
          type="button"
          onClick={() => void logout()}
          className="rounded-lg p-2 text-muted hover:bg-ink-wash"
          aria-label="Sign out"
        >
          <LogOut className="size-5" />
        </button>
      </header>

      <main id="main" className="mx-auto w-full max-w-6xl px-4 pt-6 pb-24 sm:px-8 md:pt-10 md:pb-12">
        <Outlet />
      </main>

      {/* Bottom tabs (phones) */}
      <nav
        aria-label="Main"
        className="fixed inset-x-0 bottom-0 z-10 grid grid-cols-4 border-t border-rule bg-paper md:hidden"
      >
        {NAV.map(({ to, label, icon: Icon, end }) => (
          <NavLink
            key={to}
            to={to}
            end={end}
            className={({ isActive }) =>
              cn('flex flex-col items-center gap-0.5 py-2 text-xs font-medium', isActive ? 'text-ink' : 'text-muted')
            }
          >
            <Icon className="size-5" aria-hidden />
            {label}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/components/layout/page-header.tsx' <<'__ATTENDANCE_EOF__'
import type { ReactNode } from 'react';

export function PageHeader({ title, children, actions }: { title: string; children?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div className="min-w-0">
        <h1 className="text-3xl font-semibold sm:text-4xl">{title}</h1>
        {children && <div className="mt-1.5 text-muted">{children}</div>}
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </header>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/components/ui/button.tsx' <<'__ATTENDANCE_EOF__'
import { Loader2 } from 'lucide-react';
import type { ButtonHTMLAttributes } from 'react';
import { cn } from '@/lib/cn';

const VARIANTS = {
  primary: 'bg-ink text-white hover:bg-ink-hover disabled:bg-ink/50',
  secondary: 'border border-rule bg-paper text-ink hover:border-ink-soft hover:bg-ink-wash disabled:text-muted',
  ghost: 'text-ink hover:bg-ink-wash disabled:text-muted',
  danger: 'bg-absent text-white hover:bg-absent/90 disabled:bg-absent/50',
} as const;

const SIZES = {
  sm: 'h-8 gap-1.5 px-3 text-sm',
  md: 'h-10 gap-2 px-4 text-sm',
  lg: 'h-12 gap-2 px-6 text-base',
} as const;

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: keyof typeof VARIANTS;
  size?: keyof typeof SIZES;
  loading?: boolean;
}

export function Button({
  variant = 'primary',
  size = 'md',
  loading = false,
  disabled,
  className,
  children,
  type = 'button',
  ...props
}: ButtonProps) {
  return (
    <button
      type={type}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      className={cn(
        'inline-flex shrink-0 items-center justify-center rounded-lg font-medium whitespace-nowrap transition-colors disabled:cursor-not-allowed',
        VARIANTS[variant],
        SIZES[size],
        className,
      )}
      {...props}
    >
      {loading && <Loader2 className="size-4 animate-spin" aria-hidden />}
      {children}
    </button>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/components/ui/confirm-dialog.tsx' <<'__ATTENDANCE_EOF__'
import type { ReactNode } from 'react';
import { Button } from './button';
import { Dialog } from './dialog';

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  children: ReactNode;
  confirmLabel: string;
  destructive?: boolean;
  loading?: boolean;
  onConfirm: () => void;
  onClose: () => void;
}

export function ConfirmDialog({
  open,
  title,
  children,
  confirmLabel,
  destructive,
  loading,
  onConfirm,
  onClose,
}: ConfirmDialogProps) {
  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={title}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button variant={destructive ? 'danger' : 'primary'} loading={loading} onClick={onConfirm}>
            {confirmLabel}
          </Button>
        </>
      }
    >
      <div className="text-sm text-muted">{children}</div>
    </Dialog>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/components/ui/dialog.tsx' <<'__ATTENDANCE_EOF__'
import { X } from 'lucide-react';
import { useEffect, useRef, type ReactNode } from 'react';
import { cn } from '@/lib/cn';

interface DialogProps {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: ReactNode;
  children: ReactNode;
  footer?: ReactNode;
  size?: 'md' | 'lg';
}

/**
 * Native <dialog> as a modal: the browser handles focus trapping, Escape and inert background.
 */
export function Dialog({ open, onClose, title, description, children, footer, size = 'md' }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
      aria-labelledby="dialog-title"
      className={cn(
        'm-auto w-[calc(100%-2rem)] rounded-2xl bg-paper p-0 text-text shadow-[0_24px_60px_-20px_rgb(29_43_107/0.45)]',
        size === 'lg' ? 'max-w-2xl' : 'max-w-md',
      )}
    >
      {open && (
        <div className="flex max-h-[85vh] flex-col">
          <header className="flex items-start justify-between gap-4 border-b border-rule px-6 pt-5 pb-4">
            <div>
              <h2 id="dialog-title" className="text-xl font-semibold">
                {title}
              </h2>
              {description && <p className="mt-1 text-sm text-muted">{description}</p>}
            </div>
            <button
              type="button"
              onClick={onClose}
              className="-mr-2 rounded-lg p-2 text-muted hover:bg-ink-wash hover:text-ink"
              aria-label="Close"
            >
              <X className="size-5" />
            </button>
          </header>
          <div className="overflow-y-auto px-6 py-5">{children}</div>
          {footer && <footer className="flex justify-end gap-2 border-t border-rule px-6 py-4">{footer}</footer>}
        </div>
      )}
    </dialog>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/components/ui/feedback.tsx' <<'__ATTENDANCE_EOF__'
import { Loader2 } from 'lucide-react';
import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

export function Spinner({ label = 'Loading', className }: { label?: string; className?: string }) {
  return (
    <div role="status" className={cn('flex items-center justify-center gap-2 py-12 text-muted', className)}>
      <Loader2 className="size-5 animate-spin" aria-hidden />
      <span className="text-sm">{label}…</span>
    </div>
  );
}

export function EmptyState({ title, children, action }: { title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-start gap-3 rounded-xl border border-dashed border-rule bg-paper px-6 py-10">
      <h3 className="text-lg font-semibold">{title}</h3>
      {children && <div className="max-w-prose text-sm text-muted">{children}</div>}
      {action}
    </div>
  );
}

export function ErrorNotice({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const message = error instanceof Error ? error.message : 'Something went wrong.';
  return (
    <div
      role="alert"
      className="flex flex-wrap items-center gap-3 rounded-xl border border-absent/30 bg-absent-wash px-4 py-3 text-sm text-absent"
    >
      <span>{message}</span>
      {onRetry && (
        <button type="button" onClick={onRetry} className="font-semibold underline underline-offset-2">
          Try again
        </button>
      )}
    </div>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/components/ui/field.tsx' <<'__ATTENDANCE_EOF__'
import { cloneElement, isValidElement, useId, type ReactElement, type ReactNode } from 'react';
import { cn } from '@/lib/cn';

interface FieldProps {
  label: string;
  hint?: ReactNode;
  error?: string;
  className?: string;
  children: ReactElement<{ id?: string; 'aria-invalid'?: boolean; 'aria-describedby'?: string }>;
}

/** Label + control + hint/error, wired together for screen readers. */
export function Field({ label, hint, error, className, children }: FieldProps) {
  const id = useId();
  const messageId = `${id}-message`;
  const control = isValidElement(children)
    ? cloneElement(children, {
        id,
        'aria-invalid': error ? true : undefined,
        'aria-describedby': error || hint ? messageId : undefined,
      })
    : children;

  return (
    <div className={cn('flex flex-col gap-1.5', className)}>
      <label htmlFor={id} className="text-sm font-medium text-text">
        {label}
      </label>
      {control}
      {(error || hint) && (
        <p id={messageId} className={cn('text-sm', error ? 'text-absent' : 'text-muted')}>
          {error ?? hint}
        </p>
      )}
    </div>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/components/ui/input.tsx' <<'__ATTENDANCE_EOF__'
import { forwardRef, type InputHTMLAttributes, type SelectHTMLAttributes } from 'react';
import { cn } from '@/lib/cn';

const control =
  'h-10 w-full rounded-lg border border-rule bg-paper px-3 text-sm text-text placeholder:text-muted/70 transition-colors hover:border-ink-soft/60 focus:border-ink focus:outline-none aria-[invalid=true]:border-absent disabled:bg-desk disabled:text-muted';

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(function Input(
  { className, ...props },
  ref,
) {
  return <input ref={ref} className={cn(control, className)} {...props} />;
});

export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(function Select(
  { className, children, ...props },
  ref,
) {
  return (
    <select ref={ref} className={cn(control, 'pr-8', className)} {...props}>
      {children}
    </select>
  );
});
__ATTENDANCE_EOF__

write 'apps/web/src/components/ui/register-mark.tsx' <<'__ATTENDANCE_EOF__'
import type { DayMark } from '@/api/types';
import { cn } from '@/lib/cn';

const LABEL: Record<DayMark, string> = {
  P: 'Present',
  L: 'Late',
  A: 'Absent',
  H: 'Holiday',
  W: 'Not a working day',
  '-': 'Not applicable',
};

/** One cell of a register: a tick, a late tick, a red-pen cross, H, or a shaded non-working day. */
export function RegisterMark({ mark, className }: { mark: DayMark; className?: string }) {
  return (
    <span
      role="img"
      aria-label={LABEL[mark]}
      title={LABEL[mark]}
      className={cn(
        'inline-flex size-7 items-center justify-center rounded-md text-xs font-semibold',
        mark === 'P' && 'text-present',
        mark === 'L' && 'bg-late-wash text-late',
        mark === 'A' && 'text-absent',
        mark === 'H' && 'bg-holiday-wash text-holiday',
        mark === 'W' && 'bg-[repeating-linear-gradient(135deg,var(--color-rule)_0_1px,transparent_1px_5px)]',
        mark === '-' && 'text-rule',
        className,
      )}
    >
      {(mark === 'P' || mark === 'L') && <Tick />}
      {mark === 'A' && <Cross />}
      {mark === 'H' && 'H'}
      {mark === '-' && '·'}
    </span>
  );
}

function Tick() {
  return (
    <svg viewBox="0 0 16 16" className="size-4" aria-hidden>
      <path
        d="M3 8.5l3.2 3.2L13 4.5"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function Cross() {
  return (
    <svg viewBox="0 0 16 16" className="size-3.5" aria-hidden>
      <path d="M4 4l8 8M12 4l-8 8" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
    </svg>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/components/ui/status-pill.tsx' <<'__ATTENDANCE_EOF__'
import type { DailyStatus } from '@/api/types';
import { cn } from '@/lib/cn';

const STYLE: Record<DailyStatus, { label: string; className: string }> = {
  PRESENT: { label: 'On time', className: 'bg-present-wash text-present' },
  LATE: { label: 'Late', className: 'bg-late-wash text-late' },
  ABSENT: { label: 'Absent', className: 'bg-absent-wash text-absent' },
  NOT_CHECKED_IN: { label: 'Not in yet', className: 'border border-dashed border-rule text-muted' },
  HOLIDAY: { label: 'Holiday', className: 'bg-holiday-wash text-holiday' },
  NON_WORKDAY: { label: 'Day off', className: 'bg-desk text-muted' },
};

export function StatusPill({ status, time }: { status: DailyStatus; time?: string | null }) {
  const { label, className } = STYLE[status];
  return (
    <span className={cn('inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-sm font-medium', className)}>
      {label}
      {time && <span className="tabular opacity-80">{time}</span>}
    </span>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/components/ui/tabs.tsx' <<'__ATTENDANCE_EOF__'
import { useRef, type KeyboardEvent } from 'react';
import { cn } from '@/lib/cn';

interface TabsProps<T extends string> {
  tabs: ReadonlyArray<{ id: T; label: string }>;
  value: T;
  onChange: (id: T) => void;
  label: string;
}

/** ARIA tablist with arrow-key navigation. Panels use id `panel-<tab id>`. */
export function Tabs<T extends string>({ tabs, value, onChange, label }: TabsProps<T>) {
  const refs = useRef<Array<HTMLButtonElement | null>>([]);

  const onKeyDown = (event: KeyboardEvent, index: number) => {
    const step = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
    if (!step) return;
    event.preventDefault();
    const next = (index + step + tabs.length) % tabs.length;
    const tab = tabs[next];
    if (tab) {
      onChange(tab.id);
      refs.current[next]?.focus();
    }
  };

  return (
    <div role="tablist" aria-label={label} className="flex gap-1 overflow-x-auto border-b border-rule">
      {tabs.map((tab, index) => {
        const selected = tab.id === value;
        return (
          <button
            key={tab.id}
            ref={(element) => {
              refs.current[index] = element;
            }}
            type="button"
            role="tab"
            id={`tab-${tab.id}`}
            aria-selected={selected}
            aria-controls={`panel-${tab.id}`}
            tabIndex={selected ? 0 : -1}
            onClick={() => onChange(tab.id)}
            onKeyDown={(event) => onKeyDown(event, index)}
            className={cn(
              '-mb-px border-b-2 px-3 py-2.5 text-sm font-medium whitespace-nowrap transition-colors',
              selected ? 'border-ink text-ink' : 'border-transparent text-muted hover:text-ink',
            )}
          >
            {tab.label}
          </button>
        );
      })}
    </div>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/auth/auth-context.tsx' <<'__ATTENDANCE_EOF__'
import { useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Outlet } from 'react-router';
import { api } from '@/api/client';
import { authApi } from '@/api/endpoints';
import type { Profile, Session } from '@/api/types';
import { AuthContext, type AuthContextValue, type AuthState } from './context';

const toProfile = ({ accessToken: _token, expiresIn: _ttl, ...profile }: Session): Profile => profile;

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [state, setState] = useState<AuthState>({ status: 'loading' });

  useEffect(() => {
    api.onSessionRefreshed = (session) => setState({ status: 'authenticated', profile: toProfile(session) });
    api.onSessionExpired = () => {
      queryClient.clear();
      setState({ status: 'anonymous', expired: true });
    };

    // Restore the session from the httpOnly refresh cookie, if there is one.
    let active = true;
    void api.refresh().then((session) => {
      if (active && !session) setState({ status: 'anonymous' });
    });
    return () => {
      active = false;
      api.onSessionRefreshed = null;
      api.onSessionExpired = null;
    };
  }, [queryClient]);

  const startSession = useCallback((session: Session) => {
    api.setAccessToken(session.accessToken);
    setState({ status: 'authenticated', profile: toProfile(session) });
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      login: async (email, password) => startSession(await authApi.login({ email, password })),
      register: async (input) => startSession(await authApi.register(input)),
      logout: async () => {
        try {
          await authApi.logout();
        } finally {
          api.setAccessToken(null);
          queryClient.clear();
          setState({ status: 'anonymous' });
        }
      },
      reloadProfile: async () => {
        const profile = await authApi.me();
        setState({ status: 'authenticated', profile });
      },
    }),
    [state, startSession, queryClient],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

/** Layout route for everything that uses the dashboard session. Kiosk routes deliberately sit outside it. */
export function SessionRoot() {
  return (
    <AuthProvider>
      <Outlet />
    </AuthProvider>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/auth/auth-layout.tsx' <<'__ATTENDANCE_EOF__'
import type { ReactNode } from 'react';
import { APP_NAME } from '@/app/brand';

/** Sign-in pages: a single sheet of ruled register paper on the desk. */
export function AuthLayout({
  title,
  intro,
  children,
  footer,
}: {
  title: string;
  intro: ReactNode;
  children: ReactNode;
  footer: ReactNode;
}) {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-4 py-10">
      <p className="mb-6 font-display text-2xl font-semibold text-ink">{APP_NAME}</p>
      <div className="w-full max-w-md overflow-hidden rounded-2xl border border-rule bg-paper shadow-[0_20px_50px_-30px_rgb(29_43_107/0.5)]">
        <div className="border-l-4 border-absent/70 px-8 py-8">
          <h1 className="text-3xl font-semibold">{title}</h1>
          <p className="mt-2 text-muted">{intro}</p>
          <div className="mt-6">{children}</div>
        </div>
      </div>
      <div className="mt-6 text-sm text-muted">{footer}</div>
    </main>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/auth/context.ts' <<'__ATTENDANCE_EOF__'
import { createContext } from 'react';
import type { OrganizationType, Profile } from '@/api/types';

export type AuthState =
  { status: 'loading' } | { status: 'anonymous'; expired?: boolean } | { status: 'authenticated'; profile: Profile };

export interface RegisterInput {
  organization: { name: string; type: OrganizationType; timezone: string };
  user: { name: string; email: string; password: string };
}

export interface AuthContextValue {
  state: AuthState;
  login(email: string, password: string): Promise<void>;
  register(input: RegisterInput): Promise<void>;
  logout(): Promise<void>;
  /** Re-reads the profile, e.g. after renaming the organisation. */
  reloadProfile(): Promise<void>;
}

export const AuthContext = createContext<AuthContextValue | null>(null);
__ATTENDANCE_EOF__

write 'apps/web/src/features/auth/guards.tsx' <<'__ATTENDANCE_EOF__'
import type { ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router';
import { Spinner } from '@/components/ui/feedback';
import { useAuth } from './use-auth';

export function RequireAuth({ children }: { children: ReactNode }) {
  const { state } = useAuth();
  const location = useLocation();
  if (state.status === 'loading') return <Spinner label="Opening your register" className="min-h-screen" />;
  if (state.status === 'anonymous') return <Navigate to="/login" replace state={{ from: location }} />;
  return children;
}

/** Login and sign-up pages: send signed-in users straight to the app. */
export function GuestOnly({ children }: { children: ReactNode }) {
  const { state } = useAuth();
  if (state.status === 'loading') return <Spinner className="min-h-screen" />;
  if (state.status === 'authenticated') return <Navigate to="/" replace />;
  return children;
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/auth/login-page.tsx' <<'__ATTENDANCE_EOF__'
import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { Link, useLocation, useNavigate } from 'react-router';
import { z } from 'zod';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input } from '@/components/ui/input';
import { useAuth } from './use-auth';
import { AuthLayout } from './auth-layout';

const schema = z.object({
  email: z.email('Enter a valid email address'),
  password: z.string().min(1, 'Enter your password'),
});
type Values = z.infer<typeof schema>;

export function LoginPage() {
  const { login, state } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [error, setError] = useState<unknown>(null);
  const { register, handleSubmit, formState } = useForm<Values>({ resolver: zodResolver(schema) });

  const from = (location.state as { from?: { pathname: string } } | null)?.from?.pathname ?? '/';

  const onSubmit = handleSubmit(async ({ email, password }) => {
    setError(null);
    try {
      await login(email, password);
      navigate(from, { replace: true });
    } catch (caught) {
      setError(caught);
    }
  });

  return (
    <AuthLayout
      title="Sign in"
      intro={
        state.status === 'anonymous' && state.expired
          ? 'Your session ended. Sign in again to continue.'
          : 'Open your organisation’s register.'
      }
      footer={
        <>
          New here?{' '}
          <Link to="/register" className="font-semibold text-ink underline-offset-2 hover:underline">
            Set up your school or company
          </Link>
        </>
      }
    >
      <form onSubmit={onSubmit} noValidate className="flex flex-col gap-4">
        {error !== null && <ErrorNotice error={error} />}
        <Field label="Email" error={formState.errors.email?.message}>
          <Input type="email" autoComplete="email" autoFocus {...register('email')} />
        </Field>
        <Field label="Password" error={formState.errors.password?.message}>
          <Input type="password" autoComplete="current-password" {...register('password')} />
        </Field>
        <Button type="submit" size="lg" loading={formState.isSubmitting} className="mt-2">
          Sign in
        </Button>
      </form>
    </AuthLayout>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/auth/register-page.tsx' <<'__ATTENDANCE_EOF__'
import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { useForm, useWatch } from 'react-hook-form';
import { Link, useNavigate } from 'react-router';
import { z } from 'zod';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { ApiError } from '@/lib/api-error';
import { cn } from '@/lib/cn';
import { timeZones } from '@/lib/time-zones';
import { useAuth } from './use-auth';
import { AuthLayout } from './auth-layout';

const schema = z.object({
  organizationName: z.string().trim().min(2, 'Enter at least 2 characters'),
  type: z.enum(['SCHOOL', 'COMPANY']),
  timezone: z.string().min(1),
  name: z.string().trim().min(2, 'Enter your full name'),
  email: z.email('Enter a valid email address'),
  password: z.string().min(8, 'Use at least 8 characters'),
});
type Values = z.infer<typeof schema>;

const FIELD_FROM_API: Record<string, keyof Values> = {
  'organization.name': 'organizationName',
  'organization.timezone': 'timezone',
  'user.name': 'name',
  'user.email': 'email',
  'user.password': 'password',
};

const TYPES = [
  { value: 'SCHOOL', title: 'School', detail: 'Check-in closes at a set time, e.g. 7:00–8:30.' },
  { value: 'COMPANY', title: 'Company', detail: 'Flexible arrival, late after a set time.' },
] as const;

export function RegisterPage() {
  const { register: signUp } = useAuth();
  const navigate = useNavigate();
  const [error, setError] = useState<unknown>(null);
  const {
    register,
    handleSubmit,
    formState,
    setError: setFieldError,
    control,
  } = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: { type: 'SCHOOL', timezone: 'Africa/Lagos' },
  });
  const type = useWatch({ control, name: 'type' });

  const onSubmit = handleSubmit(async (values) => {
    setError(null);
    try {
      await signUp({
        organization: { name: values.organizationName, type: values.type, timezone: values.timezone },
        user: { name: values.name, email: values.email, password: values.password },
      });
      navigate('/', { replace: true });
    } catch (caught) {
      if (caught instanceof ApiError && caught.code === 'VALIDATION_ERROR') {
        for (const [path, message] of Object.entries(caught.fieldErrors)) {
          const field = FIELD_FROM_API[path];
          if (field) setFieldError(field, { message });
        }
      } else {
        setError(caught);
      }
    }
  });

  return (
    <AuthLayout
      title="Set up your register"
      intro="Create your organisation. You can add people and devices next."
      footer={
        <>
          Already set up?{' '}
          <Link to="/login" className="font-semibold text-ink underline-offset-2 hover:underline">
            Sign in
          </Link>
        </>
      }
    >
      <form onSubmit={onSubmit} noValidate className="flex flex-col gap-4">
        {error !== null && <ErrorNotice error={error} />}
        <Field label="School or company name" error={formState.errors.organizationName?.message}>
          <Input autoFocus autoComplete="organization" {...register('organizationName')} />
        </Field>

        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1.5 text-sm font-medium">This is a</legend>
          <div className="grid grid-cols-2 gap-2">
            {TYPES.map((option) => (
              <label
                key={option.value}
                className={cn(
                  'cursor-pointer rounded-lg border px-3 py-2.5 transition-colors has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink',
                  type === option.value ? 'border-ink bg-ink-wash' : 'border-rule hover:border-ink-soft/60',
                )}
              >
                <input type="radio" value={option.value} className="sr-only" {...register('type')} />
                <span className="block font-semibold text-ink">{option.title}</span>
                <span className="block text-xs text-muted">{option.detail}</span>
              </label>
            ))}
          </div>
        </fieldset>

        <Field label="Timezone" error={formState.errors.timezone?.message}>
          <Select {...register('timezone')}>
            {timeZones().map((zone) => (
              <option key={zone} value={zone}>
                {zone.replaceAll('_', ' ')}
              </option>
            ))}
          </Select>
        </Field>

        <div className="my-1 border-t border-rule" />

        <Field label="Your full name" error={formState.errors.name?.message}>
          <Input autoComplete="name" {...register('name')} />
        </Field>
        <Field label="Email" error={formState.errors.email?.message}>
          <Input type="email" autoComplete="email" {...register('email')} />
        </Field>
        <Field label="Password" hint="At least 8 characters." error={formState.errors.password?.message}>
          <Input type="password" autoComplete="new-password" {...register('password')} />
        </Field>
        <Button type="submit" size="lg" loading={formState.isSubmitting} className="mt-2">
          Create organisation
        </Button>
      </form>
    </AuthLayout>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/auth/roles.ts' <<'__ATTENDANCE_EOF__'
import type { Role } from '@/api/types';

const RANK: Record<Role, number> = { VIEWER: 1, ADMIN: 2, OWNER: 3 };

/** Mirrors the API: OWNER ⊃ ADMIN ⊃ VIEWER. The API enforces this; the UI only hides what would fail. */
export const hasRole = (actual: Role, required: Role): boolean => RANK[actual] >= RANK[required];

export const ROLE_LABEL: Record<Role, string> = { OWNER: 'Owner', ADMIN: 'Admin', VIEWER: 'Viewer' };
__ATTENDANCE_EOF__

write 'apps/web/src/features/auth/sign-in-flow.test.tsx' <<'__ATTENDANCE_EOF__'
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '@/api/client';
import { routes } from '@/app/router';
import { fakeFetch, json } from '@/test/fake-fetch';
import { renderRoutes } from '@/test/render';
import { todayIn } from '@/lib/format';

const session = {
  accessToken: 'access-1',
  expiresIn: 900,
  user: { id: 'u1', name: 'Ada Obi', email: 'ada@school.ng' },
  role: 'OWNER',
  organizations: [{ id: 'o1', name: 'Grace High School', role: 'OWNER' }],
  organization: {
    id: 'o1',
    name: 'Grace High School',
    slug: 'grace-high-school',
    type: 'SCHOOL',
    timezone: 'Africa/Lagos',
    createdAt: '2026-09-01T00:00:00.000Z',
    policy: {
      kind: 'FIXED_WINDOW',
      workDays: [1, 2, 3, 4, 5],
      opensAt: '07:00',
      lateAfter: '08:00',
      closesAt: '08:30',
      allowCheckOut: false,
    },
  },
};

const daily = {
  date: todayIn('Africa/Lagos'),
  isToday: true,
  isWorkday: true,
  holiday: null,
  totals: { expected: 2, present: 1, late: 0, absent: 0, notCheckedIn: 1 },
  rows: [
    {
      member: { id: 'm1', fullName: 'Chidi Okeke', code: '4821', group: 'JSS 1' },
      status: 'PRESENT',
      recordId: 'r1',
      checkInAt: '2026-09-28T06:45:00.000Z',
      checkOutAt: null,
      method: 'CODE',
    },
    {
      member: { id: 'm2', fullName: 'Bola Ade', code: '7310', group: 'JSS 1' },
      status: 'NOT_CHECKED_IN',
      recordId: null,
      checkInAt: null,
      checkOutAt: null,
      method: null,
    },
  ],
};

describe('signing in', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'fetch',
      fakeFetch({
        'POST /auth/refresh': () => json(401, { error: { code: 'UNAUTHORIZED', message: 'No session' } }),
        'POST /auth/login': [
          () => json(401, { error: { code: 'UNAUTHORIZED', message: 'Invalid email or password' } }),
          () => json(200, { data: session }),
        ],
        'GET /attendance/daily': (init) =>
          (init.headers as Record<string, string>).Authorization === 'Bearer access-1'
            ? json(200, { data: daily })
            : json(401, { error: { code: 'UNAUTHORIZED', message: 'nope' } }),
      }),
    );
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    api.setAccessToken(null);
  });

  it('sends visitors to sign in, shows a wrong password, then opens today’s register', async () => {
    const user = userEvent.setup();
    renderRoutes(routes, '/');

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByText('Enter a valid email address')).toBeInTheDocument();

    await user.type(screen.getByLabelText('Email'), 'ada@school.ng');
    await user.type(screen.getByLabelText('Password'), 'wrong-password');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Invalid email or password');

    await user.clear(screen.getByLabelText('Password'));
    await user.type(screen.getByLabelText('Password'), 'correct-password');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(await screen.findByText('1 of 2 in. 1 not in yet.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Chidi Okeke' })).toHaveAttribute('href', '/people/m1');
    expect(within(screen.getByRole('table')).getByText('On time').parentElement).toHaveTextContent('07:45');
    expect(screen.getAllByText('Grace High School').length).toBeGreaterThan(0);
  });
});
__ATTENDANCE_EOF__

write 'apps/web/src/features/auth/use-auth.ts' <<'__ATTENDANCE_EOF__'
import { useContext } from 'react';
import type { Profile, Role } from '@/api/types';
import { AuthContext, type AuthContextValue } from './context';
import { hasRole } from './roles';

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used inside <AuthProvider>');
  return context;
}

/** The signed-in profile. Only use below <RequireAuth>. */
export function useProfile(): Profile {
  const { state } = useAuth();
  if (state.status !== 'authenticated') throw new Error('useProfile used outside an authenticated route');
  return state.profile;
}

export function useCan(required: Role): boolean {
  return hasRole(useProfile().role, required);
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/kiosk-client.ts' <<'__ATTENDANCE_EOF__'
import { API_BASE_URL } from '@/api/client';
import type { CheckInCredentials, CheckInResult, CheckOutResult, KioskSession } from '@/api/types';
import { KioskHttpClient } from '@/lib/http';

const STORAGE_KEY = 'rollcall.kioskToken';

/**
 * The device token lives in localStorage on purpose: it identifies the device, not a person,
 * it can only check people in or out, and an admin can revoke it at any time.
 */
export const kioskTokens = {
  get(): string | null {
    try {
      return localStorage.getItem(STORAGE_KEY);
    } catch {
      return null;
    }
  },
  set(token: string): void {
    localStorage.setItem(STORAGE_KEY, token);
  },
  clear(): void {
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch {
      // storage unavailable: nothing to clear
    }
  },
};

export const kioskClient = new KioskHttpClient(API_BASE_URL, kioskTokens);

export const kioskApi = {
  session: () => kioskClient.get<KioskSession>('/kiosk/session'),
  checkIn: (credentials: CheckInCredentials) => kioskClient.post<CheckInResult>('/kiosk/check-in', credentials),
  checkOut: (credentials: CheckInCredentials) => kioskClient.post<CheckOutResult>('/kiosk/check-out', credentials),
};
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/kiosk-page.test.tsx' <<'__ATTENDANCE_EOF__'
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { KioskSession } from '@/api/types';
import { ApiError } from '@/lib/api-error';
import { renderRoutes } from '@/test/render';
import { KioskPage } from './kiosk-page';

const mocks = vi.hoisted(() => ({
  token: 'kio_test' as string | null,
  session: vi.fn(),
  checkIn: vi.fn(),
  checkOut: vi.fn(),
}));

vi.mock('./kiosk-client', () => ({
  kioskTokens: { get: () => mocks.token, set: vi.fn(), clear: vi.fn() },
  kioskClient: { onUnpaired: null },
  kioskApi: { session: mocks.session, checkIn: mocks.checkIn, checkOut: mocks.checkOut },
}));

const SESSION: KioskSession = {
  kiosk: { id: 'k1', name: 'Main gate' },
  organization: { name: 'Grace High School', timezone: 'Africa/Lagos' },
  today: { date: '2026-09-28', time: '07:40', isWorkday: true, isHoliday: false },
  policy: { kind: 'FIXED_WINDOW', opensAt: '07:00', lateAfter: '08:00', closesAt: '08:30', allowCheckOut: false },
};

const routes = [
  { path: '/kiosk', element: <KioskPage /> },
  { path: '/kiosk/pair', element: <p>Pair this device</p> },
];

describe('kiosk', () => {
  beforeEach(() => {
    mocks.token = 'kio_test';
    mocks.session.mockResolvedValue(SESSION);
  });

  it('checks a person in with the keypad and greets them by first name', async () => {
    mocks.checkIn.mockResolvedValue({
      member: { id: 'm1', fullName: 'Chidi Okeke', group: 'JSS 1' },
      status: 'PRESENT',
      date: '2026-09-28',
      checkInAt: '2026-09-28T06:45:00.000Z',
    });
    const user = userEvent.setup();
    renderRoutes(routes, '/kiosk');

    expect(await screen.findByText('Grace High School')).toBeInTheDocument();
    const checkIn = screen.getByRole('button', { name: 'Check in' });
    expect(checkIn).toBeDisabled();

    for (const digit of ['4', '8', '2', '1']) await user.click(screen.getByRole('button', { name: digit }));
    expect(screen.getByLabelText('Your check-in code')).toHaveValue('4821');
    await user.click(checkIn);

    expect(mocks.checkIn).toHaveBeenCalledWith({ method: 'CODE', code: '4821' });
    expect(await screen.findByText('Welcome, Chidi')).toBeInTheDocument();
    expect(screen.getByText('On time, checked in at 07:45')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Check out' })).not.toBeInTheDocument();
  });

  it('explains a rejected code, sends the PIN when given, and resets when tapped', async () => {
    mocks.checkIn.mockRejectedValue(
      new ApiError(422, 'CHECK_IN_REJECTED', 'Invalid code or PIN', { reason: 'INVALID_CREDENTIALS' }),
    );
    const user = userEvent.setup();
    renderRoutes(routes, '/kiosk');

    await user.type(await screen.findByLabelText('Your check-in code'), 'stf-014');
    await user.click(screen.getByRole('button', { name: 'I have a PIN' }));
    await user.type(screen.getByLabelText('PIN'), '12a34');
    await user.click(screen.getByRole('button', { name: 'Check in' }));

    expect(mocks.checkIn).toHaveBeenCalledWith({ method: 'CODE', code: 'STF-014', pin: '1234' });
    const overlay = await screen.findByText(/don’t recognise that code/);
    await user.click(overlay);
    expect(screen.queryByText(/don’t recognise that code/)).not.toBeInTheDocument();
    expect(screen.getByLabelText('Your check-in code')).toHaveValue('');
  });

  it('sends an unpaired device to the pairing screen', async () => {
    mocks.token = null;
    renderRoutes(routes, '/kiosk');
    expect(await screen.findByText('Pair this device')).toBeInTheDocument();
    expect(mocks.session).not.toHaveBeenCalled();
  });
});
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/kiosk-page.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation, useQuery } from '@tanstack/react-query';
import { Delete, ScanLine, Settings } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import type { ButtonHTMLAttributes } from 'react';
import { Navigate, useNavigate } from 'react-router';
import type { CheckInCredentials } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { ErrorNotice, Spinner } from '@/components/ui/feedback';
import { cn } from '@/lib/cn';
import { formatLongDate, timeIn, todayIn } from '@/lib/format';
import { kioskApi, kioskClient, kioskTokens } from './kiosk-client';
import { checkInOutcome, checkOutOutcome, errorOutcome, type Outcome } from './outcome';
import { QrScanner } from './qr-scanner';
import { ResultOverlay } from './result-overlay';
import { useNow } from './use-now';
import { windowStatus } from './window-status';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9'] as const;
type Action = 'in' | 'out';

export function KioskPage() {
  const navigate = useNavigate();
  const hasToken = kioskTokens.get() !== null;
  const now = useNow();
  const codeRef = useRef<HTMLInputElement>(null);

  const [code, setCode] = useState('');
  const [pin, setPin] = useState('');
  const [showPin, setShowPin] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [scanning, setScanning] = useState<Action | null>(null);
  const [unpairing, setUnpairing] = useState(false);

  useEffect(() => {
    kioskClient.onUnpaired = () => navigate('/kiosk/pair?removed=1', { replace: true });
    return () => {
      kioskClient.onUnpaired = null;
    };
  }, [navigate]);

  // Re-read the session when the local date changes (new day, holiday) and every few minutes (policy edits).
  const session = useQuery({
    queryKey: ['kiosk-session', now.toISOString().slice(0, 10)],
    queryFn: kioskApi.session,
    enabled: hasToken,
    refetchInterval: 5 * 60_000,
    retry: 1,
  });
  const timeZone = session.data?.organization.timezone ?? 'Africa/Lagos';

  const submit = useMutation({
    mutationFn: ({ action, credentials }: { action: Action; credentials: CheckInCredentials }) =>
      action === 'in'
        ? kioskApi.checkIn(credentials).then((result) => checkInOutcome(result, timeZone))
        : kioskApi.checkOut(credentials).then((result) => checkOutOutcome(result, timeZone)),
    onSuccess: setOutcome,
    onError: (error) => setOutcome(errorOutcome(error, timeZone)),
  });

  const reset = useCallback(() => {
    setOutcome(null);
    setCode('');
    setPin('');
    setShowPin(false);
    codeRef.current?.focus();
  }, []);

  const onScanned = useCallback(
    (token: string) => {
      const action = scanning ?? 'in';
      setScanning(null);
      submit.mutate({ action, credentials: { method: 'QR', token } });
    },
    [scanning, submit],
  );

  if (!hasToken) return <Navigate to="/kiosk/pair" replace />;
  if (session.isPending) return <Spinner label="Starting check-in" className="min-h-screen" />;
  if (session.isError) {
    return (
      <main className="flex min-h-screen items-center justify-center p-8">
        <ErrorNotice error={session.error} onRetry={() => void session.refetch()} />
      </main>
    );
  }

  const info = session.data;
  const localTime = timeIn(timeZone, now);
  const status = windowStatus(info, localTime);
  const normalized = code.trim().toUpperCase();
  const canSubmit = normalized.length >= 3 && (!showPin || /^\d{4,6}$/.test(pin)) && !submit.isPending;

  const send = (action: Action) => {
    if (!canSubmit) return;
    submit.mutate({ action, credentials: { method: 'CODE', code: normalized, ...(showPin && pin ? { pin } : {}) } });
  };

  const press = (key: string) => {
    setCode((current) => (current + key).slice(0, 20));
    codeRef.current?.focus();
  };

  return (
    <main className="grid min-h-screen bg-paper lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)]">
      {/* The clock: the one bold thing on this screen. */}
      <section className="flex flex-col justify-between bg-ink px-8 py-8 text-white sm:px-12 sm:py-10">
        <div>
          <p className="font-display text-2xl font-semibold sm:text-3xl">{info.organization.name}</p>
          <p className="mt-1 text-white/70">{formatLongDate(todayIn(timeZone, now))}</p>
        </div>
        <p
          className="my-8 font-display text-[clamp(6rem,18vw,12rem)] leading-none font-semibold tabular"
          aria-label={`Time ${localTime}`}
        >
          {localTime}
        </p>
        <p
          className={cn(
            'inline-flex items-center gap-3 self-start rounded-full px-4 py-2 text-lg font-medium',
            status.tone === 'open' && 'bg-present text-white',
            status.tone === 'late' && 'bg-late text-white',
            status.tone === 'closed' && 'bg-white/15 text-white',
          )}
        >
          {status.message}
        </p>
      </section>

      <section className="flex flex-col justify-center gap-6 px-6 py-8 sm:px-12">
        <div className="flex items-center justify-between gap-4">
          <h1 className="text-4xl font-semibold">Check in</h1>
          <Button variant="secondary" size="lg" onClick={() => setScanning('in')}>
            <ScanLine className="size-5" aria-hidden />
            Scan ID card
          </Button>
        </div>

        <form
          onSubmit={(event) => {
            event.preventDefault();
            send('in');
          }}
          className="flex flex-col gap-4"
        >
          <label className="flex flex-col gap-2">
            <span className="text-lg text-muted">Your check-in code</span>
            <input
              ref={codeRef}
              autoFocus
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
              inputMode="text"
              value={code}
              onChange={(event) => setCode(event.target.value.toUpperCase().slice(0, 20))}
              className="h-20 rounded-2xl border-2 border-rule bg-desk px-6 font-display text-5xl tracking-[0.15em] text-ink tabular focus:border-ink focus:outline-none"
            />
          </label>

          {showPin ? (
            <label className="flex flex-col gap-2">
              <span className="text-lg text-muted">PIN</span>
              <input
                type="password"
                inputMode="numeric"
                autoComplete="off"
                maxLength={6}
                value={pin}
                onChange={(event) => setPin(event.target.value.replace(/\D/g, ''))}
                className="h-16 rounded-2xl border-2 border-rule bg-desk px-6 text-3xl tracking-[0.4em] focus:border-ink focus:outline-none"
              />
            </label>
          ) : (
            <button
              type="button"
              onClick={() => setShowPin(true)}
              className="self-start text-lg font-medium text-ink underline underline-offset-4"
            >
              I have a PIN
            </button>
          )}

          <div className="grid grid-cols-3 gap-3" aria-label="Number pad">
            {KEYS.map((key) => (
              <KeypadButton key={key} onClick={() => press(key)}>
                {key}
              </KeypadButton>
            ))}
            <KeypadButton onClick={() => setCode('')} aria-label="Clear">
              <span className="text-xl">Clear</span>
            </KeypadButton>
            <KeypadButton onClick={() => press('0')}>0</KeypadButton>
            <KeypadButton onClick={() => setCode((current) => current.slice(0, -1))} aria-label="Delete last digit">
              <Delete className="size-8" aria-hidden />
            </KeypadButton>
          </div>

          <div className="flex gap-3">
            <Button
              type="submit"
              size="lg"
              disabled={!canSubmit}
              loading={submit.isPending && submit.variables?.action === 'in'}
              className="h-16 flex-1 text-xl"
            >
              Check in
            </Button>
            {info.policy.allowCheckOut && (
              <Button
                variant="secondary"
                size="lg"
                disabled={!canSubmit}
                loading={submit.isPending && submit.variables?.action === 'out'}
                onClick={() => send('out')}
                className="h-16 flex-1 text-xl"
              >
                Check out
              </Button>
            )}
          </div>
        </form>

        <button
          type="button"
          onClick={() => setUnpairing(true)}
          className="inline-flex items-center gap-2 self-end text-sm text-muted hover:text-ink"
        >
          <Settings className="size-4" aria-hidden />
          {info.kiosk.name}
        </button>
      </section>

      {outcome && <ResultOverlay outcome={outcome} onDone={reset} />}
      {scanning && <QrScanner onToken={onScanned} onClose={() => setScanning(null)} />}
      <ConfirmDialog
        open={unpairing}
        title="Unpair this device?"
        confirmLabel="Unpair device"
        destructive
        onConfirm={() => {
          kioskTokens.clear();
          navigate('/kiosk/pair', { replace: true });
        }}
        onClose={() => setUnpairing(false)}
      >
        This device will stop taking check-ins until it is paired again with a new link from Settings, Check-in devices.
      </ConfirmDialog>
    </main>
  );
}

function KeypadButton({ className, ...props }: ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      className={cn(
        'flex h-16 items-center justify-center rounded-2xl border border-rule bg-paper font-display text-3xl font-medium text-ink transition-colors active:bg-ink-wash sm:h-20',
        className,
      )}
      {...props}
    />
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/outcome.test.ts' <<'__ATTENDANCE_EOF__'
import { describe, expect, it } from 'vitest';
import { ApiError } from '@/lib/api-error';
import { checkInOutcome, errorOutcome } from './outcome';

const LAGOS = 'Africa/Lagos';

describe('kiosk outcomes', () => {
  it('greets by first name with the local arrival time', () => {
    const outcome = checkInOutcome(
      {
        member: { id: '1', fullName: 'Chidi Okeke', group: null },
        status: 'LATE',
        date: '2026-09-28',
        checkInAt: '2026-09-28T07:12:00.000Z',
      },
      LAGOS,
    );
    expect(outcome).toEqual({ kind: 'in', late: true, name: 'Chidi', detail: 'Late, checked in at 08:12' });
  });

  it.each([
    [new ApiError(422, 'CHECK_IN_REJECTED', 'x', { reason: 'INVALID_CREDENTIALS' }), /don’t recognise that code/],
    [
      new ApiError(422, 'CHECK_IN_REJECTED', 'Check-in closed at 08:30', { reason: 'WINDOW_CLOSED' }),
      /^Check-in closed at 08:30$/,
    ],
    [
      new ApiError(409, 'CONFLICT', 'Chidi Okeke already checked in today', {
        reason: 'ALREADY_CHECKED_IN',
        checkInAt: '2026-09-28T06:45:00.000Z',
      }),
      /^Chidi Okeke already checked in today at 07:45\.$/,
    ],
    [new ApiError(429, 'TOO_MANY_REQUESTS', 'x'), /Wait a few minutes/],
    [new ApiError(0, 'NETWORK_ERROR', 'x'), /No internet connection/],
  ])('explains %s plainly', (error, expected) => {
    const outcome = errorOutcome(error, LAGOS);
    expect(outcome.kind).toBe('error');
    expect(outcome.kind === 'error' && outcome.message).toMatch(expected);
  });
});
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/outcome.ts' <<'__ATTENDANCE_EOF__'
import type { CheckInResult, CheckOutResult } from '@/api/types';
import { ApiError } from '@/lib/api-error';
import { timeIn } from '@/lib/format';

export type Outcome =
  | { kind: 'in'; late: boolean; name: string; detail: string }
  | { kind: 'out'; name: string; detail: string }
  | { kind: 'error'; message: string };

const firstName = (fullName: string) => fullName.split(/\s+/)[0] ?? fullName;

export function checkInOutcome(result: CheckInResult, timeZone: string): Outcome {
  const time = timeIn(timeZone, result.checkInAt);
  return {
    kind: 'in',
    late: result.status === 'LATE',
    name: firstName(result.member.fullName),
    detail: result.status === 'LATE' ? `Late, checked in at ${time}` : `On time, checked in at ${time}`,
  };
}

export function checkOutOutcome(result: CheckOutResult, timeZone: string): Outcome {
  return {
    kind: 'out',
    name: firstName(result.member.fullName),
    detail: `Checked out at ${timeIn(timeZone, result.checkOutAt)}`,
  };
}

/** Turns an API failure into one clear instruction for the person at the device. */
export function errorOutcome(error: unknown, timeZone: string): Outcome {
  if (!(error instanceof ApiError)) return { kind: 'error', message: 'Something went wrong. Try again.' };
  if (error.code === 'NETWORK_ERROR')
    return { kind: 'error', message: 'No internet connection. Try again in a moment.' };
  if (error.status === 429)
    return { kind: 'error', message: 'Too many wrong tries on this device. Wait a few minutes.' };
  if (error.status === 400) return { kind: 'error', message: 'That code doesn’t look right. Check it and try again.' };
  if (error.reason === 'INVALID_CREDENTIALS') {
    return { kind: 'error', message: 'We don’t recognise that code. Check it, and add your PIN if you have one.' };
  }
  if (error.reason === 'ALREADY_CHECKED_IN') {
    const at = (error.details as { checkInAt?: string | null } | undefined)?.checkInAt;
    return { kind: 'error', message: at ? `${error.message} at ${timeIn(timeZone, at)}.` : `${error.message}.` };
  }
  return { kind: 'error', message: error.message };
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/pair-page.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { APP_NAME } from '@/app/brand';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input } from '@/components/ui/input';
import { ApiError } from '@/lib/api-error';
import { kioskApi, kioskTokens } from './kiosk-client';

/**
 * Pairs this browser as a check-in device. The token arrives in the URL fragment (#token=…),
 * which browsers never send to any server, then moves into storage and out of the address bar.
 */
export function PairPage() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [token, setToken] = useState('');

  const pair = useMutation({
    mutationFn: async (value: string) => {
      kioskTokens.set(value.trim());
      try {
        return await kioskApi.session();
      } catch (error) {
        kioskTokens.clear();
        throw error;
      }
    },
    onSuccess: () => navigate('/kiosk', { replace: true }),
  });

  useEffect(() => {
    const fromLink = new URLSearchParams(window.location.hash.slice(1)).get('token');
    if (fromLink) {
      window.history.replaceState(null, '', window.location.pathname);
      pair.mutate(fromLink);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- run once on load
  }, []);

  const invalid = pair.error instanceof ApiError && pair.error.status === 401;

  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-6 py-10">
      <p className="mb-6 font-display text-2xl font-semibold text-ink">{APP_NAME}</p>
      <div className="w-full max-w-lg rounded-2xl border border-rule bg-paper px-8 py-8">
        <h1 className="text-3xl font-semibold">Set up this check-in device</h1>
        <p className="mt-2 text-muted">
          An admin creates a pairing link in Settings, under Check-in devices. Open the link on this device, or paste it
          below.
        </p>
        {params.get('removed') && (
          <p className="mt-4 rounded-lg bg-late-wash px-3 py-2 text-sm text-late">
            This device was removed by an admin. Pair it again to keep using it.
          </p>
        )}
        <form
          onSubmit={(event) => {
            event.preventDefault();
            const value = token.includes('#token=') ? decodeURIComponent(token.split('#token=')[1] ?? '') : token;
            if (value) pair.mutate(value);
          }}
          className="mt-6 flex flex-col gap-4"
        >
          {pair.isError && (
            <ErrorNotice
              error={
                invalid
                  ? new Error('That link has expired or the device was removed. Ask an admin for a new one.')
                  : pair.error
              }
            />
          )}
          <Field label="Pairing link or device key">
            <Input
              value={token}
              onChange={(event) => setToken(event.target.value)}
              autoComplete="off"
              spellCheck={false}
            />
          </Field>
          <Button type="submit" size="lg" loading={pair.isPending} disabled={!token.trim()}>
            Pair device
          </Button>
        </form>
      </div>
    </main>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/qr-scanner.tsx' <<'__ATTENDANCE_EOF__'
import { RefreshCw, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';

interface Detector {
  detect(source: HTMLVideoElement): Promise<Array<{ rawValue: string }>>;
}

/**
 * Uses the browser's native BarcodeDetector when available (Chrome/Android), otherwise a WebAssembly
 * polyfill. The WASM file is bundled with the app, so scanning works without reaching a CDN.
 */
async function createDetector(): Promise<Detector> {
  const native = (globalThis as { BarcodeDetector?: new (options: { formats: string[] }) => Detector }).BarcodeDetector;
  if (native) return new native({ formats: ['qr_code'] });

  const [{ BarcodeDetector, prepareZXingModule }, { default: wasmUrl }] = await Promise.all([
    import('barcode-detector/ponyfill'),
    import('zxing-wasm/reader/zxing_reader.wasm?url'),
  ]);
  prepareZXingModule({
    overrides: { locateFile: (path: string, prefix: string) => (path.endsWith('.wasm') ? wasmUrl : prefix + path) },
  });
  return new BarcodeDetector({ formats: ['qr_code'] });
}

export function QrScanner({ onToken, onClose }: { onToken: (token: string) => void; onClose: () => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [facing, setFacing] = useState<'user' | 'environment'>('user'); // kiosks usually face the person
  const [problem, setProblem] = useState<string | null>(null);

  useEffect(() => {
    let stream: MediaStream | null = null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let stopped = false;

    const scan = async (detector: Detector) => {
      const video = videoRef.current;
      if (stopped || !video) return;
      try {
        if (video.readyState >= 2) {
          const codes = await detector.detect(video);
          const token = codes.map((code) => code.rawValue).find((value) => value.startsWith('qr_'));
          if (token && !stopped) {
            stopped = true;
            onToken(token);
            return;
          }
        }
      } catch {
        // a dropped frame is not an error worth showing
      }
      timer = setTimeout(() => void scan(detector), 200);
    };

    void (async () => {
      if (!navigator.mediaDevices?.getUserMedia) {
        setProblem('This browser cannot use the camera. Open the check-in page over HTTPS in Chrome or Safari.');
        return;
      }
      try {
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: facing } }, audio: false });
        if (stopped) return;
        const video = videoRef.current;
        if (!video) return;
        video.srcObject = stream;
        await video.play();
        void scan(await createDetector());
      } catch (error) {
        setProblem(
          error instanceof DOMException && error.name === 'NotAllowedError'
            ? 'Camera access is blocked. Allow the camera for this site in the browser settings.'
            : 'The camera could not start. Use the check-in code instead.',
        );
      }
    })();

    return () => {
      stopped = true;
      clearTimeout(timer);
      stream?.getTracks().forEach((track) => track.stop());
    };
  }, [facing, onToken]);

  return (
    <div
      className="fixed inset-0 z-30 flex flex-col items-center justify-center gap-5 bg-ink p-6 text-white"
      role="dialog"
      aria-label="Scan ID card"
    >
      <p className="font-display text-3xl font-semibold">Hold your ID card up to the camera</p>
      <div className="relative aspect-square w-full max-w-md overflow-hidden rounded-3xl bg-black/40">
        <video
          ref={videoRef}
          muted
          playsInline
          className={facing === 'user' ? 'size-full -scale-x-100 object-cover' : 'size-full object-cover'}
        />
        <div className="pointer-events-none absolute inset-10 rounded-2xl border-4 border-white/80" aria-hidden />
      </div>
      {problem && <p className="max-w-md text-center text-lg">{problem}</p>}
      <div className="flex gap-3">
        <Button variant="secondary" size="lg" onClick={() => setFacing(facing === 'user' ? 'environment' : 'user')}>
          <RefreshCw className="size-5" aria-hidden />
          Switch camera
        </Button>
        <Button variant="secondary" size="lg" onClick={onClose}>
          <X className="size-5" aria-hidden />
          Use code instead
        </Button>
      </div>
    </div>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/result-overlay.tsx' <<'__ATTENDANCE_EOF__'
import { useEffect } from 'react';
import { cn } from '@/lib/cn';
import type { Outcome } from './outcome';

const DISMISS_MS = { success: 3_500, error: 6_000 };

/** Full-screen answer to "did it work?", readable from across the gate. Tap anywhere to dismiss. */
export function ResultOverlay({ outcome, onDone }: { outcome: Outcome; onDone: () => void }) {
  useEffect(() => {
    const timer = setTimeout(onDone, outcome.kind === 'error' ? DISMISS_MS.error : DISMISS_MS.success);
    return () => clearTimeout(timer);
  }, [outcome, onDone]);

  const success = outcome.kind !== 'error';
  return (
    <button
      type="button"
      onClick={onDone}
      aria-live="assertive"
      className={cn(
        'fixed inset-0 z-20 flex flex-col items-center justify-center gap-6 px-8 text-center',
        outcome.kind === 'in' && !outcome.late && 'bg-present text-white',
        outcome.kind === 'in' && outcome.late && 'bg-late text-white',
        outcome.kind === 'out' && 'bg-ink text-white',
        outcome.kind === 'error' && 'border-l-[12px] border-absent bg-paper text-text',
      )}
    >
      {success ? (
        <svg viewBox="0 0 64 64" className="size-40 sm:size-56" aria-hidden>
          <path
            d="M14 34l12 12L50 18"
            pathLength={1}
            fill="none"
            stroke="currentColor"
            strokeWidth="7"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="animate-draw"
          />
        </svg>
      ) : (
        <svg viewBox="0 0 64 64" className="size-28 text-absent sm:size-36" aria-hidden>
          <path d="M18 18l28 28M46 18L18 46" fill="none" stroke="currentColor" strokeWidth="7" strokeLinecap="round" />
        </svg>
      )}
      {outcome.kind === 'error' ? (
        <p className="max-w-2xl font-display text-3xl font-semibold text-balance sm:text-5xl">{outcome.message}</p>
      ) : (
        <>
          <p className="font-display text-5xl font-semibold sm:text-7xl">
            {outcome.kind === 'in' ? `Welcome, ${outcome.name}` : `Goodbye, ${outcome.name}`}
          </p>
          <p className="text-2xl opacity-90 sm:text-3xl">{outcome.detail}</p>
        </>
      )}
      <span className="sr-only">Tap to continue</span>
    </button>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/use-now.ts' <<'__ATTENDANCE_EOF__'
import { useEffect, useState } from 'react';

/** Current time, re-rendering at the start of every second. */
export function useNow(): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const tick = () => {
      setNow(new Date());
      timer = setTimeout(tick, 1_000 - (Date.now() % 1_000));
    };
    timer = setTimeout(tick, 1_000 - (Date.now() % 1_000));
    return () => clearTimeout(timer);
  }, []);
  return now;
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/window-status.test.ts' <<'__ATTENDANCE_EOF__'
import { describe, expect, it } from 'vitest';
import type { KioskSession } from '@/api/types';
import { windowStatus } from './window-status';

const school: Pick<KioskSession, 'policy' | 'today'> = {
  policy: { kind: 'FIXED_WINDOW', opensAt: '07:00', lateAfter: '08:00', closesAt: '08:30', allowCheckOut: false },
  today: { date: '2026-09-28', time: '07:30', isWorkday: true, isHoliday: false },
};
const office: Pick<KioskSession, 'policy' | 'today'> = {
  ...school,
  policy: { kind: 'FLEXIBLE_HOURS', opensAt: '06:00', lateAfter: '09:00', closesAt: null, allowCheckOut: true },
};

describe('windowStatus', () => {
  it.each([
    ['06:59', 'closed', 'Check-in opens at 07:00.'],
    ['07:00', 'open', 'On time until 08:00.'],
    ['08:00', 'open', 'On time until 08:00.'],
    ['08:01', 'late', 'Arrivals now count as late. Check-in closes at 08:30.'],
    ['08:30', 'late', 'Arrivals now count as late. Check-in closes at 08:30.'],
    ['08:31', 'closed', 'Check-in closed at 08:30.'],
  ])('fixed window at %s is %s', (time, tone, message) => {
    expect(windowStatus(school, time)).toEqual({ tone, message });
  });

  it('flexible hours never close, and mention check-out after a fixed window closes when allowed', () => {
    expect(windowStatus(office, '15:00')).toEqual({ tone: 'late', message: 'Arrivals now count as late.' });
    const withCheckOut = { ...school, policy: { ...school.policy, allowCheckOut: true } };
    expect(windowStatus(withCheckOut, '16:00').message).toBe('Check-in closed at 08:30. You can still check out.');
  });

  it('is closed on holidays and non-working days', () => {
    expect(windowStatus({ ...school, today: { ...school.today, isHoliday: true } }, '07:30').message).toMatch(
      /holiday/,
    );
    expect(windowStatus({ ...school, today: { ...school.today, isWorkday: false } }, '07:30')).toEqual({
      tone: 'closed',
      message: 'No check-in today.',
    });
  });
});
__ATTENDANCE_EOF__

write 'apps/web/src/features/kiosk/window-status.ts' <<'__ATTENDANCE_EOF__'
import type { KioskSession } from '@/api/types';

export interface WindowStatus {
  tone: 'open' | 'late' | 'closed';
  message: string;
}

/** What the kiosk tells people walking up, at a given wall-clock time (HH:mm, org timezone). */
export function windowStatus(session: Pick<KioskSession, 'policy' | 'today'>, time: string): WindowStatus {
  const { policy, today } = session;
  if (today.isHoliday) return { tone: 'closed', message: 'Today is a holiday. Check-in is closed.' };
  if (!today.isWorkday) return { tone: 'closed', message: 'No check-in today.' };
  if (time < policy.opensAt) return { tone: 'closed', message: `Check-in opens at ${policy.opensAt}.` };
  if (time <= policy.lateAfter) return { tone: 'open', message: `On time until ${policy.lateAfter}.` };
  if (policy.kind === 'FIXED_WINDOW' && policy.closesAt) {
    if (time <= policy.closesAt)
      return { tone: 'late', message: `Arrivals now count as late. Check-in closes at ${policy.closesAt}.` };
    return {
      tone: 'closed',
      message: `Check-in closed at ${policy.closesAt}.${policy.allowCheckOut ? ' You can still check out.' : ''}`,
    };
  }
  return { tone: 'late', message: 'Arrivals now count as late.' };
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/people/id-card-dialog.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation, useQueryClient } from '@tanstack/react-query';
import QRCode from 'qrcode';
import { useState } from 'react';
import { membersApi, queryKeys } from '@/api/endpoints';
import type { Member } from '@/api/types';
import { Button } from '@/components/ui/button';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice } from '@/components/ui/feedback';
import { useProfile } from '@/features/auth/use-auth';
import { formatShortDate } from '@/lib/format';

/** Issues a QR ID card. The token is shown once; issuing again makes the previous card stop working. */
export function IdCardDialog({ member, onClose }: { member: Member | null; onClose: () => void }) {
  const { organization } = useProfile();
  const queryClient = useQueryClient();
  const [qrImage, setQrImage] = useState<string | null>(null);

  const issue = useMutation({
    mutationFn: async (id: string) => {
      const { qrToken } = await membersApi.issueQrToken(id);
      return QRCode.toDataURL(qrToken, { margin: 1, width: 360, color: { dark: '#1d2b6b', light: '#ffffff' } });
    },
    onSuccess: async (image) => {
      setQrImage(image);
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
    },
  });

  const close = () => {
    setQrImage(null);
    issue.reset();
    onClose();
  };

  return (
    <Dialog
      open={member !== null}
      onClose={close}
      title="ID card"
      description={member?.fullName}
      footer={
        qrImage ? (
          <>
            <Button variant="secondary" onClick={close}>
              Close
            </Button>
            <Button onClick={() => window.print()}>Print card</Button>
          </>
        ) : (
          <>
            <Button variant="secondary" onClick={close}>
              Cancel
            </Button>
            <Button onClick={() => member && issue.mutate(member.id)} loading={issue.isPending}>
              {member?.qrIssuedAt ? 'Issue a new card' : 'Issue card'}
            </Button>
          </>
        )
      }
    >
      {issue.isError && <ErrorNotice error={issue.error} />}
      {!qrImage && member && (
        <div className="flex flex-col gap-2 text-sm text-muted">
          <p>The card’s QR code lets {member.fullName} check in by scanning it at a check-in device.</p>
          <p>For security the code is shown only once, so print the card straight away.</p>
          {member.qrIssuedAt && (
            <p className="font-medium text-late">
              A card was issued on {formatShortDate(member.qrIssuedAt.slice(0, 10))}. Issuing a new one stops the old
              card from working.
            </p>
          )}
        </div>
      )}
      {qrImage && member && (
        <div className="print-area mx-auto flex w-72 flex-col items-center rounded-2xl border border-rule bg-paper p-5 text-center">
          <p className="font-display text-sm font-semibold text-ink">{organization.name}</p>
          <img src={qrImage} alt={`QR code for ${member.fullName}`} className="my-3 size-48" />
          <p className="font-display text-xl font-semibold text-ink">{member.fullName}</p>
          <p className="text-sm text-muted">
            {member.group ? `${member.group}, ` : ''}code <span className="tabular">{member.code}</span>
          </p>
        </div>
      )}
    </Dialog>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/people/import-csv.test.ts' <<'__ATTENDANCE_EOF__'
import { describe, expect, it } from 'vitest';
import { normalizeDate, parsePeopleCsv, TEMPLATE_CSV } from './import-csv';

describe('normalizeDate', () => {
  it.each([
    ['2026-09-14', '2026-09-14'],
    ['14/09/2026', '2026-09-14'],
    ['4-9-2026', '2026-09-04'],
    [' 01/10/2026 ', '2026-10-01'],
  ])('reads %s as %s', (input, expected) => expect(normalizeDate(input)).toBe(expected));

  it.each(['31/02/2026', '2026-13-01', '09/14', 'yesterday', '14.09.2026'])('rejects %s', (input) =>
    expect(normalizeDate(input)).toBeNull(),
  );
});

describe('parsePeopleCsv', () => {
  it('parses the template and generates no issues', () => {
    const result = parsePeopleCsv(TEMPLATE_CSV);
    expect(result.issues).toEqual([]);
    expect(result.rows).toEqual([
      { line: 2, fullName: 'Adaeze Okafor', group: 'JSS 1', joinedOn: '2026-09-14' },
      { line: 3, fullName: 'Tunde Bello', code: 'STF-014', group: 'Teachers' },
    ]);
  });

  it('understands school-list headers: Surname / First name / Other names, Class, Admission No', () => {
    const csv =
      '\uFEFFS/N,Surname,First Name,Other Names,Class,Admission No.\n1,OKAFOR,Adaeze,Chioma,JSS 1A,adm-0042\n';
    const result = parsePeopleCsv(csv);
    expect(result.rows).toEqual([{ line: 2, fullName: 'OKAFOR Adaeze Chioma', code: 'ADM-0042', group: 'JSS 1A' }]);
    expect(result.columns).toMatchObject({ code: 'Admission No.', group: 'Class' });
  });

  it('reports bad rows by spreadsheet line and keeps the good ones', () => {
    const csv = [
      'Name,Code,Joined',
      'Ada Obi,ABC-1,14/09/2026',
      ',XYZ,',
      'Bola Ade,AB,',
      'Chi Eze,abc-1,',
      'Dayo Ojo,,31/02/2026',
      '',
      'Efe Uche,,',
    ].join('\n');
    const result = parsePeopleCsv(csv);
    expect(result.rows.map((row) => row.fullName)).toEqual(['Ada Obi', 'Efe Uche']);
    expect(result.issues).toEqual([
      { line: 3, message: 'name is missing' },
      { line: 4, message: 'code "AB" must be 3–20 letters, digits or dashes' },
      { line: 5, message: 'code ABC-1 is also on line 2' },
      { line: 6, message: '"31/02/2026" is not a date (use DD/MM/YYYY)' },
    ]);
  });

  it('explains what is missing when there is no name column', () => {
    const result = parsePeopleCsv('Code,Group\nA1B,JSS1\n');
    expect(result.rows).toEqual([]);
    expect(result.issues[0]?.message).toMatch(/No name column/);
  });
});
__ATTENDANCE_EOF__

write 'apps/web/src/features/people/import-csv.ts' <<'__ATTENDANCE_EOF__'
import Papa from 'papaparse';

export interface ImportRow {
  line: number;
  fullName: string;
  code?: string;
  group?: string;
  joinedOn?: string;
}

export interface ImportIssue {
  line: number;
  message: string;
}

export interface ParsedImport {
  rows: ImportRow[];
  issues: ImportIssue[];
  /** Which spreadsheet column fed each field (null when absent). */
  columns: { fullName: string | null; code: string | null; group: string | null; joinedOn: string | null };
}

const ALIASES = {
  fullName: ['name', 'full name', 'fullname', 'student name', 'staff name', 'employee name', 'pupil name'],
  surname: ['surname', 'last name', 'lastname', 'family name'],
  firstName: ['first name', 'firstname', 'given name'],
  otherNames: ['other names', 'other name', 'middle name', 'middle names'],
  code: [
    'code',
    'id',
    'staff id',
    'student id',
    'employee id',
    'admission no',
    'admission number',
    'reg no',
    'staff no',
  ],
  group: ['group', 'class', 'department', 'dept', 'arm', 'team', 'unit'],
  joinedOn: ['joined', 'joined on', 'date joined', 'start date', 'resumption date'],
} as const;

const CODE_PATTERN = /^[A-Z0-9-]{3,20}$/;

const normalizeHeader = (header: string) => header.toLowerCase().replace(/[._]/g, ' ').replace(/\s+/g, ' ').trim();

/** Accepts 2026-09-14, 14/09/2026 and 14-9-2026; returns YYYY-MM-DD or null. */
export function normalizeDate(value: string): string | null {
  const trimmed = value.trim();
  let year: number, month: number, day: number;
  const iso = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(trimmed);
  const dmy = /^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/.exec(trimmed);
  if (iso) [year, month, day] = [Number(iso[1]), Number(iso[2]), Number(iso[3])];
  else if (dmy) [day, month, year] = [Number(dmy[1]), Number(dmy[2]), Number(dmy[3])];
  else return null;

  const date = new Date(Date.UTC(year, month - 1, day));
  const valid = date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
  return valid ? date.toISOString().slice(0, 10) : null;
}

/** Parses a people CSV exported from Excel / Google Sheets into import rows plus row-level problems. */
export function parsePeopleCsv(text: string): ParsedImport {
  const parsed = Papa.parse<Record<string, string>>(text.replace(/^\uFEFF/, ''), {
    header: true,
    skipEmptyLines: 'greedy',
  });
  const headers = parsed.meta.fields ?? [];
  const find = (aliases: readonly string[]) =>
    headers.find((header) => aliases.includes(normalizeHeader(header))) ?? null;

  const column = {
    fullName: find(ALIASES.fullName),
    surname: find(ALIASES.surname),
    firstName: find(ALIASES.firstName),
    otherNames: find(ALIASES.otherNames),
    code: find(ALIASES.code),
    group: find(ALIASES.group),
    joinedOn: find(ALIASES.joinedOn),
  };

  const issues: ImportIssue[] = [];
  const rows: ImportRow[] = [];
  const hasNames = column.fullName || column.surname || column.firstName;
  if (!hasNames) {
    issues.push({
      line: 1,
      message: 'No name column found. Add a column called "Full name" (or "Surname" and "First name").',
    });
    return {
      rows,
      issues,
      columns: { fullName: null, code: column.code, group: column.group, joinedOn: column.joinedOn },
    };
  }

  const seenCodes = new Map<string, number>();
  parsed.data.forEach((record, index) => {
    const line = index + 2; // line 1 is the header
    const cell = (name: string | null) => (name ? (record[name] ?? '').trim() : '');

    const fullName = column.fullName
      ? cell(column.fullName)
      : [cell(column.surname), cell(column.firstName), cell(column.otherNames)].filter(Boolean).join(' ');
    const code = cell(column.code).toUpperCase();
    const group = cell(column.group);
    const joinedRaw = cell(column.joinedOn);

    const problems: string[] = [];
    if (fullName.length < 2) problems.push('name is missing');
    if (fullName.length > 120) problems.push('name is longer than 120 characters');
    if (code && !CODE_PATTERN.test(code)) problems.push(`code "${code}" must be 3–20 letters, digits or dashes`);
    if (code && seenCodes.has(code)) problems.push(`code ${code} is also on line ${seenCodes.get(code)}`);
    if (group.length > 60) problems.push('group is longer than 60 characters');
    const joinedOn = joinedRaw ? normalizeDate(joinedRaw) : null;
    if (joinedRaw && !joinedOn) problems.push(`"${joinedRaw}" is not a date (use DD/MM/YYYY)`);

    if (problems.length > 0) {
      issues.push({ line, message: problems.join('; ') });
      return;
    }
    if (code) seenCodes.set(code, line);
    rows.push({
      line,
      fullName,
      ...(code ? { code } : {}),
      ...(group ? { group } : {}),
      ...(joinedOn ? { joinedOn } : {}),
    });
  });

  return {
    rows,
    issues,
    columns: {
      fullName: column.fullName ?? [column.surname, column.firstName, column.otherNames].filter(Boolean).join(' + '),
      code: column.code,
      group: column.group,
      joinedOn: column.joinedOn,
    },
  };
}

export const TEMPLATE_CSV =
  'Full name,Code,Group,Joined on\r\nAdaeze Okafor,,JSS 1,14/09/2026\r\nTunde Bello,STF-014,Teachers,\r\n';
__ATTENDANCE_EOF__

write 'apps/web/src/features/people/import-dialog.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { FileUp } from 'lucide-react';
import { useState, type ChangeEvent } from 'react';
import { toast } from 'sonner';
import { membersApi, queryKeys } from '@/api/endpoints';
import type { ImportResult } from '@/api/types';
import { Button } from '@/components/ui/button';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice } from '@/components/ui/feedback';
import { saveText } from '@/lib/download';
import { parsePeopleCsv, TEMPLATE_CSV, type ParsedImport } from './import-csv';

const BATCH = 1_000; // the API accepts up to 1,000 people per request

export function ImportDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const queryClient = useQueryClient();
  const [fileName, setFileName] = useState('');
  const [parsed, setParsed] = useState<ParsedImport | null>(null);
  const [result, setResult] = useState<ImportResult | null>(null);

  const reset = () => {
    setFileName('');
    setParsed(null);
    setResult(null);
    importRows.reset();
  };
  const close = () => {
    reset();
    onClose();
  };

  const importRows = useMutation({
    mutationFn: async (rows: ParsedImport['rows']) => {
      const total: ImportResult = { created: 0, skipped: [] };
      for (let start = 0; start < rows.length; start += BATCH) {
        const batch = rows.slice(start, start + BATCH);
        const outcome = await membersApi.import(batch.map(({ line: _line, ...row }) => row));
        total.created += outcome.created;
        // The API numbers rows within the batch; translate back to spreadsheet lines.
        total.skipped.push(...outcome.skipped.map((skip) => ({ ...skip, row: batch[skip.row - 1]?.line ?? skip.row })));
      }
      return total;
    },
    onSuccess: async (outcome) => {
      setResult(outcome);
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      toast.success(`Imported ${outcome.created} ${outcome.created === 1 ? 'person' : 'people'}`);
    },
  });

  const onFile = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;
    setFileName(file.name);
    setResult(null);
    setParsed(parsePeopleCsv(await file.text()));
  };

  const ready = parsed?.rows.length ?? 0;

  return (
    <Dialog
      open={open}
      onClose={close}
      size="lg"
      title="Import people"
      description="Upload a CSV from Excel or Google Sheets (File → Save as / Download → CSV)."
      footer={
        result ? (
          <Button onClick={close}>Done</Button>
        ) : (
          <>
            <Button variant="secondary" onClick={close}>
              Cancel
            </Button>
            <Button
              disabled={ready === 0}
              loading={importRows.isPending}
              onClick={() => parsed && importRows.mutate(parsed.rows)}
            >
              Import {ready > 0 ? `${ready} ${ready === 1 ? 'person' : 'people'}` : ''}
            </Button>
          </>
        )
      }
    >
      {result ? (
        <div className="flex flex-col gap-3">
          <p className="font-display text-xl text-ink">
            Imported {result.created} {result.created === 1 ? 'person' : 'people'}.
          </p>
          {result.skipped.length > 0 && (
            <>
              <p className="text-sm text-muted">These rows were skipped:</p>
              <ul className="max-h-48 overflow-y-auto rounded-lg border border-rule text-sm">
                {result.skipped.map((skip) => (
                  <li key={`${skip.row}-${skip.fullName}`} className="border-b border-rule px-3 py-2 last:border-0">
                    Line {skip.row}, {skip.fullName}: {skip.reason}
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          {importRows.isError && <ErrorNotice error={importRows.error} />}
          <label className="flex cursor-pointer flex-col items-center gap-2 rounded-xl border-2 border-dashed border-rule px-6 py-8 text-center hover:border-ink-soft has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink">
            <FileUp className="size-6 text-ink" aria-hidden />
            <span className="font-medium text-ink">{fileName || 'Choose a CSV file'}</span>
            <span className="text-sm text-muted">
              Columns: Full name (or Surname + First name), Code, Group, Joined on. Only the name is required.
            </span>
            <input type="file" accept=".csv,text/csv" className="sr-only" onChange={(event) => void onFile(event)} />
          </label>
          <button
            type="button"
            onClick={() => saveText(TEMPLATE_CSV, 'people-template.csv')}
            className="self-start text-sm font-semibold text-ink underline underline-offset-2"
          >
            Download a template
          </button>

          {parsed && (
            <div className="flex flex-col gap-3">
              <p className="text-sm">
                <strong className="tabular">{ready}</strong> ready to import.{' '}
                {parsed.issues.length > 0 && (
                  <span className="text-absent">
                    {parsed.issues.length} {parsed.issues.length === 1 ? 'row needs' : 'rows need'} fixing in the file
                    first.
                  </span>
                )}{' '}
                Codes are generated for anyone without one.
              </p>
              {parsed.issues.length > 0 && (
                <ul className="max-h-36 overflow-y-auto rounded-lg border border-absent/30 bg-absent-wash text-sm text-absent">
                  {parsed.issues.map((issue) => (
                    <li key={issue.line} className="px-3 py-1.5">
                      Line {issue.line}: {issue.message}
                    </li>
                  ))}
                </ul>
              )}
              {ready > 0 && (
                <div className="overflow-x-auto rounded-lg border border-rule">
                  <table className="w-full text-left text-sm">
                    <thead className="bg-desk text-muted">
                      <tr>
                        <th className="px-3 py-2 font-medium">Name</th>
                        <th className="px-3 py-2 font-medium">Code</th>
                        <th className="px-3 py-2 font-medium">Group</th>
                        <th className="px-3 py-2 font-medium">Joined</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-rule">
                      {parsed.rows.slice(0, 6).map((row) => (
                        <tr key={row.line}>
                          <td className="px-3 py-2">{row.fullName}</td>
                          <td className="px-3 py-2 tabular text-muted">{row.code ?? 'auto'}</td>
                          <td className="px-3 py-2 text-muted">{row.group ?? '–'}</td>
                          <td className="px-3 py-2 tabular text-muted">{row.joinedOn ?? 'today'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {ready > 6 && <p className="px-3 py-2 text-xs text-muted">…and {ready - 6} more</p>}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </Dialog>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/people/people-page.tsx' <<'__ATTENDANCE_EOF__'
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { KeyRound, QrCode, Search, Upload, UserPlus } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { toast } from 'sonner';
import { membersApi, queryKeys, type MemberQuery } from '@/api/endpoints';
import type { Member, MemberStatus } from '@/api/types';
import { PageHeader } from '@/components/layout/page-header';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Input, Select } from '@/components/ui/input';
import { useCan } from '@/features/auth/use-auth';
import { errorMessage } from '@/lib/api-error';
import { formatShortDate } from '@/lib/format';
import { IdCardDialog } from './id-card-dialog';
import { ImportDialog } from './import-dialog';
import { PersonFormDialog } from './person-form-dialog';

const PAGE_SIZE = 50;

export function PeoplePage() {
  const canEdit = useCan('ADMIN');
  const queryClient = useQueryClient();
  const [params, setParams] = useSearchParams();
  const query: MemberQuery = {
    search: params.get('search') ?? undefined,
    group: params.get('group') ?? undefined,
    status: (params.get('status') as MemberStatus | 'ALL' | null) ?? 'ACTIVE',
    page: Number(params.get('page') ?? 1),
    limit: PAGE_SIZE,
  };

  const [searchDraft, setSearchDraft] = useState(query.search ?? '');
  const [editing, setEditing] = useState<Member | 'new' | null>(null);
  const [carding, setCarding] = useState<Member | null>(null);
  const [importing, setImporting] = useState(false);

  const update = (changes: Record<string, string | undefined>) => {
    const next = new URLSearchParams(params);
    for (const [key, value] of Object.entries(changes)) {
      if (value) next.set(key, value);
      else next.delete(key);
    }
    if (!('page' in changes)) next.delete('page');
    setParams(next, { replace: true });
  };

  // Debounce typing so the list is not re-queried on every keystroke.
  useEffect(() => {
    const timer = setTimeout(() => {
      if ((query.search ?? '') !== searchDraft.trim()) update({ search: searchDraft.trim() || undefined });
    }, 300);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only react to typing
  }, [searchDraft]);

  const list = useQuery({
    queryKey: queryKeys.members(query),
    queryFn: () => membersApi.list(query),
    placeholderData: keepPreviousData,
  });
  const groups = useQuery({ queryKey: queryKeys.groups, queryFn: membersApi.groups });

  const toggleArchive = useMutation({
    mutationFn: (member: Member) =>
      member.status === 'ACTIVE' ? membersApi.archive(member.id) : membersApi.update(member.id, { status: 'ACTIVE' }),
    onSuccess: async (member) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      toast.success(
        member.status === 'ARCHIVED'
          ? `Archived ${member.fullName}. Their history is kept.`
          : `Restored ${member.fullName}`,
      );
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const meta = list.data?.meta;
  const people = list.data?.data ?? [];
  const firstShown = meta ? (meta.page - 1) * meta.limit + 1 : 0;

  return (
    <>
      <PageHeader
        title="People"
        actions={
          canEdit && (
            <>
              <Button variant="secondary" onClick={() => setImporting(true)}>
                <Upload className="size-4" aria-hidden />
                Import CSV
              </Button>
              <Button onClick={() => setEditing('new')}>
                <UserPlus className="size-4" aria-hidden />
                Add person
              </Button>
            </>
          )
        }
      >
        Everyone whose attendance you take: students, teachers, staff.
      </PageHeader>

      <div className="mb-3 flex flex-wrap gap-2">
        <div className="relative min-w-48 flex-1">
          <Search
            className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted"
            aria-hidden
          />
          <Input
            type="search"
            placeholder="Search name or code"
            aria-label="Search name or code"
            value={searchDraft}
            onChange={(event) => setSearchDraft(event.target.value)}
            className="pl-9"
          />
        </div>
        <Select
          aria-label="Group"
          value={query.group ?? ''}
          onChange={(event) => update({ group: event.target.value || undefined })}
          className="w-auto"
        >
          <option value="">All groups</option>
          {groups.data?.map((group) => (
            <option key={group}>{group}</option>
          ))}
        </Select>
        <Select
          aria-label="Status"
          value={query.status}
          onChange={(event) => update({ status: event.target.value === 'ACTIVE' ? undefined : event.target.value })}
          className="w-auto"
        >
          <option value="ACTIVE">Active</option>
          <option value="ARCHIVED">Archived</option>
          <option value="ALL">Everyone</option>
        </Select>
      </div>

      {list.isPending && <Spinner label="Loading people" />}
      {list.isError && <ErrorNotice error={list.error} onRetry={() => void list.refetch()} />}

      {list.data &&
        people.length === 0 &&
        (query.search || query.group || query.status !== 'ACTIVE' ? (
          <EmptyState title="Nobody matches these filters" />
        ) : (
          <EmptyState
            title="Add the people you take attendance for"
            action={
              canEdit && (
                <div className="flex gap-2">
                  <Button onClick={() => setImporting(true)}>Import a CSV</Button>
                  <Button variant="secondary" onClick={() => setEditing('new')}>
                    Add one person
                  </Button>
                </div>
              )
            }
          >
            Import your class lists or staff list from Excel, or add people one at a time. Everyone gets a check-in
            code.
          </EmptyState>
        ))}

      {people.length > 0 && (
        <div className="overflow-hidden rounded-2xl border border-rule bg-paper">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-rule text-muted">
              <tr>
                <th scope="col" className="px-4 py-3 font-medium">
                  Name
                </th>
                <th scope="col" className="px-4 py-3 font-medium">
                  Code
                </th>
                <th scope="col" className="hidden px-4 py-3 font-medium sm:table-cell">
                  Group
                </th>
                <th scope="col" className="hidden px-4 py-3 font-medium md:table-cell">
                  Expected from
                </th>
                {canEdit && (
                  <th scope="col" className="w-0 px-4 py-3">
                    <span className="sr-only">Actions</span>
                  </th>
                )}
              </tr>
            </thead>
            <tbody className="divide-y divide-rule">
              {people.map((member) => (
                <tr key={member.id} className={member.status === 'ARCHIVED' ? 'text-muted' : undefined}>
                  <td className="px-4 py-3">
                    <Link to={`/people/${member.id}`} className="font-medium hover:text-ink hover:underline">
                      {member.fullName}
                    </Link>
                    {member.status === 'ARCHIVED' && <span className="ml-2 text-xs">archived</span>}
                    <span className="ml-2 inline-flex gap-1 align-middle text-muted">
                      {member.pinSet && <KeyRound className="size-3.5" aria-label="Has a PIN" />}
                      {member.qrIssuedAt && <QrCode className="size-3.5" aria-label="Has an ID card" />}
                    </span>
                  </td>
                  <td className="px-4 py-3 tabular">{member.code}</td>
                  <td className="hidden px-4 py-3 text-muted sm:table-cell">{member.group ?? '–'}</td>
                  <td className="hidden px-4 py-3 text-muted md:table-cell">{formatShortDate(member.joinedOn)}</td>
                  {canEdit && (
                    <td className="px-2 py-2">
                      <div className="flex justify-end">
                        <Button variant="ghost" size="sm" onClick={() => setEditing(member)}>
                          Edit<span className="sr-only"> {member.fullName}</span>
                        </Button>
                        {member.status === 'ACTIVE' && (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="hidden sm:inline-flex"
                            onClick={() => setCarding(member)}
                          >
                            ID card<span className="sr-only"> for {member.fullName}</span>
                          </Button>
                        )}
                        <Button
                          variant="ghost"
                          size="sm"
                          className="hidden sm:inline-flex"
                          onClick={() => toggleArchive.mutate(member)}
                        >
                          {member.status === 'ACTIVE' ? 'Archive' : 'Restore'}
                          <span className="sr-only"> {member.fullName}</span>
                        </Button>
                      </div>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
          {meta && meta.totalPages > 1 && (
            <nav
              aria-label="Pages"
              className="flex items-center justify-between border-t border-rule px-4 py-3 text-sm text-muted"
            >
              <span className="tabular">
                {firstShown}–{firstShown + people.length - 1} of {meta.total}
              </span>
              <div className="flex gap-2">
                <Button
                  variant="secondary"
                  size="sm"
                  disabled={meta.page <= 1}
                  onClick={() => update({ page: String(meta.page - 1) })}
                >
                  Previous
                </Button>
                <Button
                  variant="secondary"
                  size="sm"
                  disabled={meta.page >= meta.totalPages}
                  onClick={() => update({ page: String(meta.page + 1) })}
                >
                  Next
                </Button>
              </div>
            </nav>
          )}
        </div>
      )}

      {editing && (
        <PersonFormDialog
          key={editing === 'new' ? 'new' : editing.id}
          open
          member={editing === 'new' ? undefined : editing}
          onClose={() => setEditing(null)}
        />
      )}
      <IdCardDialog member={carding} onClose={() => setCarding(null)} />
      <ImportDialog open={importing} onClose={() => setImporting(false)} />
    </>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/people/person-form-dialog.tsx' <<'__ATTENDANCE_EOF__'
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useForm, useWatch } from 'react-hook-form';
import { toast } from 'sonner';
import { z } from 'zod';
import { membersApi, queryKeys, type MemberInput } from '@/api/endpoints';
import type { Member } from '@/api/types';
import { Button } from '@/components/ui/button';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { ApiError } from '@/lib/api-error';

const schema = z
  .object({
    fullName: z.string().trim().min(2, 'Enter at least 2 characters').max(120),
    code: z
      .string()
      .trim()
      .toUpperCase()
      .refine((value) => value === '' || /^[A-Z0-9-]{3,20}$/.test(value), '3–20 letters, digits or dashes'),
    group: z.string().trim().max(60),
    joinedOn: z.string(),
    pinAction: z.enum(['KEEP', 'SET', 'REMOVE']),
    pin: z.string(),
  })
  .refine((values) => values.pinAction !== 'SET' || /^\d{4,6}$/.test(values.pin), {
    path: ['pin'],
    message: 'PIN must be 4–6 digits',
  });
type Values = z.infer<typeof schema>;

interface Props {
  open: boolean;
  member?: Member;
  onClose: () => void;
}

export function PersonFormDialog({ open, member, onClose }: Props) {
  const queryClient = useQueryClient();
  const groups = useQuery({ queryKey: queryKeys.groups, queryFn: membersApi.groups, enabled: open });
  const { register, handleSubmit, formState, control, setError, reset } = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: {
      fullName: member?.fullName ?? '',
      code: member?.code ?? '',
      group: member?.group ?? '',
      joinedOn: member?.joinedOn ?? '',
      pinAction: member?.pinSet ? 'KEEP' : 'KEEP',
      pin: '',
    },
  });
  const pinAction = useWatch({ control, name: 'pinAction' });

  const save = useMutation({
    mutationFn: (values: Values) => {
      const body: Partial<MemberInput> = {
        fullName: values.fullName,
        group: values.group || (member ? null : undefined),
        ...(values.code ? { code: values.code } : {}),
        ...(values.joinedOn ? { joinedOn: values.joinedOn } : {}),
        ...(values.pinAction === 'SET' ? { pin: values.pin } : {}),
        ...(values.pinAction === 'REMOVE' ? { pin: null } : {}),
      };
      return member ? membersApi.update(member.id, body) : membersApi.create(body as MemberInput);
    },
    onSuccess: async (saved) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      toast.success(member ? `Saved ${saved.fullName}` : `Added ${saved.fullName} with code ${saved.code}`);
      reset();
      onClose();
    },
    onError: (error) => {
      if (error instanceof ApiError && error.status === 409) setError('code', { message: error.message });
      if (error instanceof ApiError && error.code === 'VALIDATION_ERROR') {
        for (const [path, message] of Object.entries(error.fieldErrors)) {
          if (path in schema.shape) setError(path as keyof Values, { message });
        }
      }
    },
  });

  const onSubmit = handleSubmit((values) => save.mutate(values));
  const showError =
    save.isError &&
    !(save.error instanceof ApiError && (save.error.status === 409 || save.error.code === 'VALIDATION_ERROR'));

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={member ? `Edit ${member.fullName}` : 'Add a person'}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" form="person-form" loading={save.isPending}>
            {member ? 'Save changes' : 'Add person'}
          </Button>
        </>
      }
    >
      <form id="person-form" onSubmit={onSubmit} noValidate className="flex flex-col gap-4">
        {showError && <ErrorNotice error={save.error} />}
        <Field label="Full name" error={formState.errors.fullName?.message}>
          <Input autoFocus {...register('fullName')} />
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Check-in code"
            hint={member ? undefined : 'Leave blank to generate one.'}
            error={formState.errors.code?.message}
          >
            <Input className="tabular uppercase" autoComplete="off" {...register('code')} />
          </Field>
          <Field label="Group" hint="Class, department or team." error={formState.errors.group?.message}>
            <Input list="group-options" autoComplete="off" {...register('group')} />
          </Field>
        </div>
        <datalist id="group-options">
          {groups.data?.map((group) => (
            <option key={group} value={group} />
          ))}
        </datalist>
        <Field
          label="Expected from"
          hint="No absences are counted before this date. Defaults to today."
          error={formState.errors.joinedOn?.message}
        >
          <Input type="date" {...register('joinedOn')} />
        </Field>
        <Field label="PIN" hint="Optional. A PIN stops others from checking in with this person’s code.">
          <Select {...register('pinAction')}>
            <option value="KEEP">{member?.pinSet ? 'Keep current PIN' : 'No PIN'}</option>
            <option value="SET">{member?.pinSet ? 'Set a new PIN' : 'Set a PIN'}</option>
            {member?.pinSet && <option value="REMOVE">Remove PIN</option>}
          </Select>
        </Field>
        {pinAction === 'SET' && (
          <Field label="New PIN" error={formState.errors.pin?.message}>
            <Input type="password" inputMode="numeric" autoComplete="new-password" maxLength={6} {...register('pin')} />
          </Field>
        )}
      </form>
    </Dialog>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/people/person-page.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { ArrowLeft } from 'lucide-react';
import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { calendarApi, membersApi, queryKeys, reportsApi } from '@/api/endpoints';
import { PageHeader } from '@/components/layout/page-header';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Input, Select } from '@/components/ui/input';
import { RegisterMark } from '@/components/ui/register-mark';
import { useCan, useProfile } from '@/features/auth/use-auth';
import { ApiError, errorMessage } from '@/lib/api-error';
import {
  addDays,
  formatDayLabel,
  formatPercent,
  formatShortDate,
  plural,
  startOfMonth,
  timeIn,
  todayIn,
} from '@/lib/format';
import { IdCardDialog } from './id-card-dialog';
import { PersonFormDialog } from './person-form-dialog';

type Preset = 'month' | '30' | 'custom' | `period:${string}`;

export function PersonPage() {
  const { id = '' } = useParams();
  const { organization } = useProfile();
  const canEdit = useCan('ADMIN');
  const today = todayIn(organization.timezone);

  const [preset, setPreset] = useState<Preset>('month');
  const [custom, setCustom] = useState({ from: startOfMonth(today), to: today });
  const [editing, setEditing] = useState(false);
  const [carding, setCarding] = useState(false);
  const queryClient = useQueryClient();

  const member = useQuery({ queryKey: queryKeys.member(id), queryFn: () => membersApi.get(id) });
  const toggleArchive = useMutation({
    mutationFn: (archive: boolean) => (archive ? membersApi.archive(id) : membersApi.update(id, { status: 'ACTIVE' })),
    onSuccess: async (saved) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      toast.success(
        saved.status === 'ARCHIVED'
          ? `Archived ${saved.fullName}. Their history is kept.`
          : `Restored ${saved.fullName}`,
      );
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const periods = useQuery({ queryKey: queryKeys.periods, queryFn: calendarApi.periods });

  const range = (() => {
    if (preset === 'month') return { from: startOfMonth(today), to: today };
    if (preset === '30') return { from: addDays(today, -29), to: today };
    if (preset.startsWith('period:')) {
      const period = periods.data?.find((p) => `period:${p.id}` === preset);
      if (period) return { from: period.startsOn, to: period.endsOn < today ? period.endsOn : today };
    }
    return custom;
  })();

  const history = useQuery({
    queryKey: queryKeys.memberHistory(id, range.from, range.to),
    queryFn: () => reportsApi.member(id, range.from, range.to),
    enabled: range.from <= range.to,
    retry: false,
  });

  if (member.isPending) return <Spinner />;
  if (member.isError) return <ErrorNotice error={member.error} />;
  const person = member.data;
  const summary = history.data?.summary;

  return (
    <>
      <Link to="/people" className="mb-4 inline-flex items-center gap-1.5 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> People
      </Link>
      <PageHeader
        title={person.fullName}
        actions={
          canEdit && (
            <>
              <Button variant="secondary" onClick={() => setEditing(true)}>
                Edit
              </Button>
              {person.status === 'ACTIVE' && (
                <Button variant="secondary" onClick={() => setCarding(true)}>
                  ID card
                </Button>
              )}
              <Button
                variant="secondary"
                loading={toggleArchive.isPending}
                onClick={() => toggleArchive.mutate(person.status === 'ACTIVE')}
              >
                {person.status === 'ACTIVE' ? 'Archive' : 'Restore'}
              </Button>
            </>
          )
        }
      >
        Code <span className="tabular font-medium text-text">{person.code}</span>
        {person.group && <>, {person.group}</>}
        {person.status === 'ARCHIVED' && <>, archived {person.archivedOn && formatShortDate(person.archivedOn)}</>}
      </PageHeader>

      <div className="mb-5 flex flex-wrap items-end gap-2">
        <Select
          aria-label="Period"
          value={preset}
          onChange={(event) => setPreset(event.target.value as Preset)}
          className="w-auto"
        >
          <option value="month">This month</option>
          <option value="30">Last 30 days</option>
          {periods.data?.map((period) => (
            <option key={period.id} value={`period:${period.id}`}>
              {period.name}
            </option>
          ))}
          <option value="custom">Choose dates</option>
        </Select>
        {preset === 'custom' && (
          <>
            <Input
              type="date"
              aria-label="From"
              value={custom.from}
              max={today}
              onChange={(e) => setCustom({ ...custom, from: e.target.value })}
              className="w-40"
            />
            <Input
              type="date"
              aria-label="To"
              value={custom.to}
              max={today}
              onChange={(e) => setCustom({ ...custom, to: e.target.value })}
              className="w-40"
            />
          </>
        )}
      </div>

      {history.isPending && history.fetchStatus !== 'idle' && <Spinner label="Loading attendance" />}
      {history.isError &&
        (history.error instanceof ApiError && history.error.status === 404 ? (
          <EmptyState title="No attendance expected in this period">
            {person.fullName} was not on the register for these dates. They are expected from{' '}
            {formatShortDate(person.joinedOn)}.
          </EmptyState>
        ) : (
          <ErrorNotice error={history.error} onRetry={() => void history.refetch()} />
        ))}

      {history.data && summary && (
        <>
          <section className="mb-6 rounded-2xl border border-rule bg-paper px-6 py-5">
            <p className="font-display text-xl font-medium text-ink sm:text-2xl">
              {summary.expected === 0
                ? 'No working days in this period yet.'
                : `Attended ${summary.attended} of ${plural(summary.expected, 'day')} (${formatPercent(summary.attendanceRate)}).`}
            </p>
            {summary.expected > 0 && (
              <p className="mt-1 text-muted">
                {summary.late} late, {summary.absent} absent.
              </p>
            )}
            <div className="mt-5 flex flex-wrap gap-1" aria-label="Day by day">
              {history.data.dates.map((date, index) => {
                const label = formatDayLabel(date);
                return (
                  <div key={date} className="flex flex-col items-center gap-0.5" title={formatShortDate(date)}>
                    <span className="text-[10px] text-muted">{label.weekday}</span>
                    <RegisterMark mark={summary.marks[index] ?? '-'} />
                    <span className="tabular text-[10px] text-muted">{label.day}</span>
                  </div>
                );
              })}
            </div>
          </section>

          <h2 className="mb-3 text-xl font-semibold">Check-ins</h2>
          {history.data.log.length === 0 ? (
            <p className="text-sm text-muted">No check-ins in this period.</p>
          ) : (
            <div className="overflow-hidden rounded-2xl border border-rule bg-paper">
              <table className="w-full text-left text-sm">
                <thead className="border-b border-rule text-muted">
                  <tr>
                    <th scope="col" className="px-4 py-3 font-medium">
                      Date
                    </th>
                    <th scope="col" className="px-4 py-3 font-medium">
                      Arrived
                    </th>
                    <th scope="col" className="px-4 py-3 font-medium">
                      Left
                    </th>
                    <th scope="col" className="hidden px-4 py-3 font-medium sm:table-cell">
                      How
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-rule">
                  {[...history.data.log].reverse().map((entry) => (
                    <tr key={entry.date}>
                      <td className="px-4 py-3">{formatShortDate(entry.date)}</td>
                      <td className="px-4 py-3 tabular">
                        {timeIn(organization.timezone, entry.checkInAt)}
                        {entry.status === 'LATE' && <span className="ml-2 font-medium text-late">late</span>}
                      </td>
                      <td className="px-4 py-3 tabular text-muted">
                        {entry.checkOutAt ? timeIn(organization.timezone, entry.checkOutAt) : '–'}
                      </td>
                      <td className="hidden px-4 py-3 text-muted sm:table-cell">
                        {entry.method === 'MANUAL' ? 'Corrected by admin' : entry.method === 'QR' ? 'ID card' : 'Code'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}

      {editing && <PersonFormDialog open member={person} onClose={() => setEditing(false)} />}
      <IdCardDialog member={carding ? person : null} onClose={() => setCarding(false)} />
    </>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/reports/register-grid.tsx' <<'__ATTENDANCE_EOF__'
import type { AttendanceReport, DayMark } from '@/api/types';
import { RegisterMark } from '@/components/ui/register-mark';
import { cn } from '@/lib/cn';
import { formatDayLabel, formatShortDate } from '@/lib/format';

export const MAX_GRID_DAYS = 62;

const LEGEND: Array<[DayMark, string]> = [
  ['P', 'On time'],
  ['L', 'Late'],
  ['A', 'Absent'],
  ['H', 'Holiday'],
  ['W', 'Not a working day'],
];

/** The report as a class register: one row per person, one column per day. */
export function RegisterGrid({ report }: { report: AttendanceReport }) {
  const holidays = new Set(report.holidays.map((holiday) => holiday.date));
  return (
    <div>
      <div className="overflow-x-auto rounded-2xl border border-rule bg-paper">
        <table className="border-separate border-spacing-0 text-sm">
          <thead>
            <tr>
              <th
                scope="col"
                className="sticky left-0 z-10 min-w-48 border-r border-b border-rule bg-paper px-4 py-2 text-left font-medium text-muted"
              >
                Name
              </th>
              {report.dates.map((date) => {
                const label = formatDayLabel(date);
                return (
                  <th
                    key={date}
                    scope="col"
                    title={formatShortDate(date)}
                    className={cn(
                      'border-b border-rule px-0.5 py-1 text-center font-normal text-muted',
                      holidays.has(date) && 'bg-holiday-wash',
                    )}
                  >
                    <span className="block text-[10px]">{label.weekday}</span>
                    <span className="tabular block text-xs">{label.day}</span>
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody>
            {report.rows.map((row) => (
              <tr key={row.memberId} className="group">
                <th
                  scope="row"
                  className="sticky left-0 z-10 border-r border-b border-rule bg-paper px-4 py-1 text-left font-medium group-hover:bg-desk"
                >
                  <span className="block max-w-56 truncate">{row.fullName}</span>
                </th>
                {row.marks.map((mark, index) => (
                  <td
                    key={report.dates[index]}
                    className="border-b border-rule px-0.5 py-0.5 text-center group-hover:bg-desk/60"
                  >
                    <RegisterMark mark={mark} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted" aria-label="Key">
        {LEGEND.map(([mark, label]) => (
          <li key={mark} className="inline-flex items-center gap-1">
            <RegisterMark mark={mark} className="size-6" />
            {label}
          </li>
        ))}
      </ul>
    </div>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/reports/reports-page.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation, useQuery } from '@tanstack/react-query';
import { Download } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router';
import { toast } from 'sonner';
import { calendarApi, membersApi, queryKeys, reportsApi, type ReportQuery } from '@/api/endpoints';
import { PageHeader } from '@/components/layout/page-header';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Input, Select } from '@/components/ui/input';
import { useProfile } from '@/features/auth/use-auth';
import { errorMessage } from '@/lib/api-error';
import { cn } from '@/lib/cn';
import { saveDownload } from '@/lib/download';
import { formatPercent, formatShortDate, plural, startOfMonth, todayIn } from '@/lib/format';
import { MAX_GRID_DAYS, RegisterGrid } from './register-grid';

const LOW_ATTENDANCE = 75;

export function ReportsPage() {
  const { organization } = useProfile();
  const today = todayIn(organization.timezone);
  const [source, setSource] = useState<string>('month'); // 'month' | 'custom' | period id
  const [custom, setCustom] = useState({ from: startOfMonth(today), to: today });
  const [group, setGroup] = useState('');

  const periods = useQuery({ queryKey: queryKeys.periods, queryFn: calendarApi.periods });
  const groups = useQuery({ queryKey: queryKeys.groups, queryFn: membersApi.groups });

  const range: ReportQuery =
    source === 'month' ? { from: startOfMonth(today), to: today } : source === 'custom' ? custom : { periodId: source };
  const query: ReportQuery = { ...range, ...(group ? { group } : {}) };
  const valid = !('from' in query) || (query.from !== '' && query.to !== '' && query.from <= query.to);

  const report = useQuery({
    queryKey: queryKeys.report(query),
    queryFn: () => reportsApi.attendance(query),
    enabled: valid,
  });

  const download = useMutation({
    mutationFn: (format: 'xlsx' | 'csv') => reportsApi.download(query, format),
    onSuccess: saveDownload,
    onError: (error) => toast.error(errorMessage(error)),
  });

  const data = report.data;

  return (
    <>
      <PageHeader
        title="Reports"
        actions={
          <>
            <Button
              variant="secondary"
              disabled={!data}
              loading={download.isPending && download.variables === 'csv'}
              onClick={() => download.mutate('csv')}
            >
              CSV
            </Button>
            <Button
              disabled={!data}
              loading={download.isPending && download.variables === 'xlsx'}
              onClick={() => download.mutate('xlsx')}
            >
              <Download className="size-4" aria-hidden />
              Download Excel
            </Button>
          </>
        }
      >
        Attendance for a month, term or session, ready to share.
      </PageHeader>

      <div className="mb-6 flex flex-wrap items-end gap-2">
        <Select
          aria-label="Period"
          value={source}
          onChange={(event) => setSource(event.target.value)}
          className="w-auto"
        >
          <option value="month">This month</option>
          {periods.data?.map((period) => (
            <option key={period.id} value={period.id}>
              {period.name}
            </option>
          ))}
          <option value="custom">Choose dates</option>
        </Select>
        {source === 'custom' && (
          <>
            <Input
              type="date"
              aria-label="From"
              value={custom.from}
              onChange={(e) => setCustom({ ...custom, from: e.target.value })}
              className="w-40"
            />
            <Input
              type="date"
              aria-label="To"
              value={custom.to}
              onChange={(e) => setCustom({ ...custom, to: e.target.value })}
              className="w-40"
            />
          </>
        )}
        {(groups.data?.length ?? 0) > 0 && (
          <Select
            aria-label="Group"
            value={group}
            onChange={(event) => setGroup(event.target.value)}
            className="w-auto"
          >
            <option value="">All groups</option>
            {groups.data?.map((name) => (
              <option key={name}>{name}</option>
            ))}
          </Select>
        )}
        {periods.data?.length === 0 && (
          <p className="text-sm text-muted">
            Add your terms and sessions in{' '}
            <Link to="/settings?tab=periods" className="font-medium text-ink underline underline-offset-2">
              Settings
            </Link>{' '}
            to report on them in one click.
          </p>
        )}
      </div>

      {!valid && <ErrorNotice error={new Error('Choose a start date on or before the end date.')} />}
      {report.isPending && valid && <Spinner label="Building the report" />}
      {report.isError && <ErrorNotice error={report.error} onRetry={() => void report.refetch()} />}

      {data && data.rows.length === 0 && <EmptyState title="Nobody was expected in this period" />}

      {data && data.rows.length > 0 && (
        <>
          <section className="mb-6 rounded-2xl border border-rule bg-paper px-6 py-5">
            <p className="text-sm text-muted">
              {data.range.label ? `${data.range.label}, ` : ''}
              {formatShortDate(data.range.from)} to {formatShortDate(data.range.to)}
            </p>
            <p className="mt-1 font-display text-xl font-medium text-ink sm:text-2xl">
              {formatPercent(data.totals.attendanceRate)} attendance across{' '}
              {plural(data.totals.members, 'person', 'people')}.
            </p>
            <p className="mt-1 text-muted">
              {plural(data.totals.late, 'late arrival')} and {plural(data.totals.absent, 'absence')} in{' '}
              {plural(data.totals.expected, 'expected day')}.
            </p>
          </section>

          <h2 className="mb-3 text-xl font-semibold">By person</h2>
          <div className="mb-8 overflow-x-auto rounded-2xl border border-rule bg-paper">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-rule text-muted">
                <tr>
                  <th scope="col" className="px-4 py-3 font-medium">
                    Name
                  </th>
                  <th scope="col" className="hidden px-4 py-3 font-medium sm:table-cell">
                    Group
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    Expected
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    On time
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    Late
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    Absent
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    Attendance
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-rule tabular">
                {data.rows.map((row) => (
                  <tr key={row.memberId}>
                    <td className="px-4 py-2.5">
                      <Link to={`/people/${row.memberId}`} className="font-medium hover:text-ink hover:underline">
                        {row.fullName}
                      </Link>
                    </td>
                    <td className="hidden px-4 py-2.5 text-muted sm:table-cell">{row.group ?? '–'}</td>
                    <td className="px-4 py-2.5 text-right">{row.expected}</td>
                    <td className="px-4 py-2.5 text-right">{row.present}</td>
                    <td className="px-4 py-2.5 text-right">{row.late}</td>
                    <td className={cn('px-4 py-2.5 text-right', row.absent > 0 && 'text-absent')}>{row.absent}</td>
                    <td
                      className={cn(
                        'px-4 py-2.5 text-right font-semibold',
                        row.attendanceRate !== null && row.attendanceRate < LOW_ATTENDANCE && 'text-absent',
                      )}
                    >
                      {formatPercent(row.attendanceRate)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <h2 className="mb-3 text-xl font-semibold">Register</h2>
          {data.dates.length <= MAX_GRID_DAYS ? (
            <RegisterGrid report={data} />
          ) : (
            <p className="text-sm text-muted">
              The on-screen register shows up to {MAX_GRID_DAYS} days. Download Excel for the full {data.dates.length}
              -day grid.
            </p>
          )}
        </>
      )}
    </>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/settings/access-sections.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import QRCode from 'qrcode';
import { useState } from 'react';
import { toast } from 'sonner';
import { kiosksApi, queryKeys, teamApi } from '@/api/endpoints';
import type { Kiosk, Role, Teammate } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { useCan, useProfile } from '@/features/auth/use-auth';
import { ROLE_LABEL } from '@/features/auth/roles';
import { ApiError, errorMessage } from '@/lib/api-error';
import { formatShortDate, relativeTime } from '@/lib/format';
import { pairingLink } from './pairing';
import { SettingsBlock } from './settings-block';

export function DevicesSection() {
  const queryClient = useQueryClient();
  const kiosks = useQuery({ queryKey: queryKeys.kiosks, queryFn: kiosksApi.list });
  const [name, setName] = useState('');
  const [paired, setPaired] = useState<{ name: string; link: string; qr: string } | null>(null);
  const [revoking, setRevoking] = useState<Kiosk | null>(null);

  const create = useMutation({
    mutationFn: async () => {
      const { kiosk, token } = await kiosksApi.create(name.trim());
      const link = pairingLink(token);
      return {
        name: kiosk.name,
        link,
        qr: await QRCode.toDataURL(link, { margin: 1, width: 320, color: { dark: '#1d2b6b' } }),
      };
    },
    onSuccess: async (result) => {
      setName('');
      setPaired(result);
      await queryClient.invalidateQueries({ queryKey: queryKeys.kiosks });
    },
  });

  const revoke = useMutation({
    mutationFn: (kiosk: Kiosk) => kiosksApi.revoke(kiosk.id),
    onSuccess: async () => {
      setRevoking(null);
      await queryClient.invalidateQueries({ queryKey: queryKeys.kiosks });
      toast.success('Device removed. It can no longer check people in.');
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const active = kiosks.data?.filter((kiosk) => !kiosk.revokedAt) ?? [];

  return (
    <SettingsBlock
      title="Check-in devices"
      description="A tablet or phone at the gate or reception where people check in. Each device can only check people in, nothing else."
    >
      {kiosks.isPending && <Spinner />}
      {kiosks.isError && <ErrorNotice error={kiosks.error} />}
      {kiosks.data && (
        <ul className="mb-5 divide-y divide-rule rounded-lg border border-rule">
          {active.length === 0 && <li className="px-4 py-3 text-sm text-muted">No devices yet.</li>}
          {active.map((kiosk) => (
            <li key={kiosk.id} className="flex items-center justify-between gap-3 px-4 py-2.5 text-sm">
              <span>
                <span className="font-medium">{kiosk.name}</span>
                <span className="ml-2 text-muted">Last used {relativeTime(kiosk.lastSeenAt).toLowerCase()}</span>
              </span>
              <Button variant="ghost" size="sm" onClick={() => setRevoking(kiosk)}>
                Remove<span className="sr-only"> {kiosk.name}</span>
              </Button>
            </li>
          ))}
        </ul>
      )}

      <form
        onSubmit={(event) => {
          event.preventDefault();
          create.mutate();
        }}
        className="flex flex-col gap-3"
      >
        {create.isError && <ErrorNotice error={create.error} />}
        <div className="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end">
          <Field label="Device name">
            <Input
              placeholder="e.g. Main gate tablet"
              minLength={2}
              maxLength={80}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </Field>
          <Button type="submit" loading={create.isPending} disabled={name.trim().length < 2}>
            Add device
          </Button>
        </div>
      </form>

      <Dialog
        open={paired !== null}
        onClose={() => setPaired(null)}
        title={`Pair ${paired?.name ?? 'device'}`}
        description="Open this link on the device, or scan the code with its camera. It is shown only once."
        footer={<Button onClick={() => setPaired(null)}>Done</Button>}
      >
        {paired && (
          <div className="flex flex-col items-center gap-4">
            <img src={paired.qr} alt="Pairing QR code" className="size-56" />
            <div className="flex w-full gap-2">
              <Input readOnly value={paired.link} aria-label="Pairing link" onFocus={(e) => e.target.select()} />
              <Button
                variant="secondary"
                onClick={() =>
                  void navigator.clipboard
                    .writeText(paired.link)
                    .then(() => toast.success('Copied pairing link'))
                    .catch(() => toast.error('Copy failed. Select the link and copy it manually.'))
                }
              >
                Copy
              </Button>
            </div>
            <p className="text-sm text-muted">
              Anyone with this link can check people in for your organisation. Share it only with the device.
            </p>
          </div>
        )}
      </Dialog>

      <ConfirmDialog
        open={revoking !== null}
        title={`Remove ${revoking?.name ?? 'device'}?`}
        confirmLabel="Remove device"
        destructive
        loading={revoke.isPending}
        onConfirm={() => revoking && revoke.mutate(revoking)}
        onClose={() => setRevoking(null)}
      >
        The device stops working immediately. Check-ins it already recorded are kept.
      </ConfirmDialog>
    </SettingsBlock>
  );
}

const ROLE_HELP: Record<Role, string> = {
  OWNER: 'Everything, including managing the team',
  ADMIN: 'Manage people, attendance, devices and settings',
  VIEWER: 'See attendance and download reports',
};

export function TeamSection() {
  const { user } = useProfile();
  const isOwner = useCan('OWNER');
  const queryClient = useQueryClient();
  const team = useQuery({ queryKey: queryKeys.team, queryFn: teamApi.list });
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState<Teammate | null>(null);

  const changeRole = useMutation({
    mutationFn: ({ userId, role }: { userId: string; role: Role }) => teamApi.changeRole(userId, role),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.team });
      toast.success('Role updated. It applies within 15 minutes.');
    },
    onError: async (error) => {
      toast.error(errorMessage(error));
      await queryClient.invalidateQueries({ queryKey: queryKeys.team });
    },
  });

  const remove = useMutation({
    mutationFn: (mate: Teammate) => teamApi.remove(mate.userId),
    onSuccess: async () => {
      setRemoving(null);
      await queryClient.invalidateQueries({ queryKey: queryKeys.team });
      toast.success('Removed from the team');
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <SettingsBlock title="Team" description="People who can sign in to this dashboard.">
      {team.isPending && <Spinner />}
      {team.isError && <ErrorNotice error={team.error} />}
      {team.data && (
        <ul className="mb-5 divide-y divide-rule rounded-lg border border-rule">
          {team.data.map((mate) => (
            <li key={mate.userId} className="flex flex-wrap items-center justify-between gap-3 px-4 py-3 text-sm">
              <span className="min-w-0">
                <span className="block font-medium">
                  {mate.name}
                  {mate.userId === user.id && <span className="ml-1 text-muted">(you)</span>}
                </span>
                <span className="block truncate text-muted">
                  {mate.email}, added {formatShortDate(mate.addedAt.slice(0, 10))}
                </span>
              </span>
              <span className="flex items-center gap-1">
                {isOwner ? (
                  <Select
                    aria-label={`Role for ${mate.name}`}
                    value={mate.role}
                    onChange={(e) => changeRole.mutate({ userId: mate.userId, role: e.target.value as Role })}
                    className="h-8 w-auto"
                  >
                    {(Object.keys(ROLE_LABEL) as Role[]).map((role) => (
                      <option key={role} value={role}>
                        {ROLE_LABEL[role]}
                      </option>
                    ))}
                  </Select>
                ) : (
                  <span className="text-muted">{ROLE_LABEL[mate.role]}</span>
                )}
                {isOwner && mate.userId !== user.id && (
                  <Button variant="ghost" size="sm" onClick={() => setRemoving(mate)}>
                    Remove<span className="sr-only"> {mate.name}</span>
                  </Button>
                )}
              </span>
            </li>
          ))}
        </ul>
      )}
      <Button onClick={() => setAdding(true)}>Add a teammate</Button>

      {adding && <AddTeammateDialog canAddOwner={isOwner} onClose={() => setAdding(false)} />}
      <ConfirmDialog
        open={removing !== null}
        title={`Remove ${removing?.name ?? 'teammate'}?`}
        confirmLabel="Remove"
        destructive
        loading={remove.isPending}
        onConfirm={() => removing && remove.mutate(removing)}
        onClose={() => setRemoving(null)}
      >
        They are signed out and can no longer open this organisation’s register.
      </ConfirmDialog>
    </SettingsBlock>
  );
}

function AddTeammateDialog({ canAddOwner, onClose }: { canAddOwner: boolean; onClose: () => void }) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState({ email: '', role: 'ADMIN' as Role, name: '', temporaryPassword: '' });
  const [needsAccount, setNeedsAccount] = useState(false);

  const add = useMutation({
    mutationFn: () =>
      teamApi.add({
        email: form.email.trim(),
        role: form.role,
        ...(form.name.trim() ? { name: form.name.trim() } : {}),
        ...(form.temporaryPassword ? { temporaryPassword: form.temporaryPassword } : {}),
      }),
    onSuccess: async (mate) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.team });
      toast.success(`Added ${mate.name} as ${ROLE_LABEL[mate.role].toLowerCase()}`);
      onClose();
    },
    onError: (error) => {
      // The API asks for a name and password only when the email has no account yet.
      if (error instanceof ApiError && error.code === 'VALIDATION_ERROR' && !Array.isArray(error.details))
        setNeedsAccount(true);
    },
  });

  return (
    <Dialog
      open
      onClose={onClose}
      title="Add a teammate"
      description="They sign in with their email. Share any temporary password privately."
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" form="teammate-form" loading={add.isPending} disabled={!form.email.includes('@')}>
            Add teammate
          </Button>
        </>
      }
    >
      <form
        id="teammate-form"
        onSubmit={(event) => {
          event.preventDefault();
          add.mutate();
        }}
        className="flex flex-col gap-4"
      >
        {add.isError && !needsAccount && <ErrorNotice error={add.error} />}
        <Field label="Email">
          <Input
            type="email"
            autoFocus
            value={form.email}
            onChange={(e) => setForm({ ...form, email: e.target.value })}
          />
        </Field>
        <Field label="Role" hint={ROLE_HELP[form.role]}>
          <Select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value as Role })}>
            {canAddOwner && <option value="OWNER">Owner</option>}
            <option value="ADMIN">Admin</option>
            <option value="VIEWER">Viewer</option>
          </Select>
        </Field>
        {needsAccount && (
          <>
            <p className="rounded-lg bg-late-wash px-3 py-2 text-sm text-late">
              This email has no account yet. Add their name and a temporary password.
            </p>
            <Field label="Their full name">
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            </Field>
            <Field label="Temporary password" hint="At least 8 characters.">
              <Input
                type="text"
                autoComplete="off"
                value={form.temporaryPassword}
                onChange={(e) => setForm({ ...form, temporaryPassword: e.target.value })}
              />
            </Field>
          </>
        )}
      </form>
    </Dialog>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/settings/calendar-sections.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Trash2 } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { calendarApi, queryKeys } from '@/api/endpoints';
import type { Holiday, Period, PeriodType } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { useCan, useProfile } from '@/features/auth/use-auth';
import { errorMessage } from '@/lib/api-error';
import { formatLongDate, formatShortDate, todayIn } from '@/lib/format';
import { NIGERIAN_FIXED_HOLIDAYS } from './holidays';
import { SettingsBlock } from './settings-block';

export function HolidaysSection() {
  const { organization } = useProfile();
  const canEdit = useCan('ADMIN');
  const queryClient = useQueryClient();
  const thisYear = Number(todayIn(organization.timezone).slice(0, 4));
  const [year, setYear] = useState(thisYear);
  const [date, setDate] = useState('');
  const [name, setName] = useState('');
  const [removing, setRemoving] = useState<Holiday | null>(null);

  const from = `${year}-01-01`;
  const to = `${year}-12-31`;
  const holidays = useQuery({ queryKey: queryKeys.holidays(from, to), queryFn: () => calendarApi.holidays(from, to) });
  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['holidays'] });
    await queryClient.invalidateQueries({ queryKey: ['attendance'] });
    await queryClient.invalidateQueries({ queryKey: ['reports'] });
  };

  const add = useMutation({
    mutationFn: () => calendarApi.addHoliday({ date, name: name.trim() }),
    onSuccess: async (holiday) => {
      setDate('');
      setName('');
      await refresh();
      toast.success(`Added ${holiday.name}`);
    },
  });

  const addNigerian = useMutation({
    mutationFn: async () => {
      const existing = new Set(holidays.data?.map((holiday) => holiday.date));
      const missing = NIGERIAN_FIXED_HOLIDAYS.filter(([day]) => !existing.has(`${year}-${day}`));
      for (const [day, holidayName] of missing)
        await calendarApi.addHoliday({ date: `${year}-${day}`, name: holidayName });
      return missing.length;
    },
    onSuccess: async (count) => {
      await refresh();
      toast.success(count === 0 ? 'All fixed public holidays are already added' : `Added ${count} public holidays`);
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const remove = useMutation({
    mutationFn: (holiday: Holiday) => calendarApi.removeHoliday(holiday.id),
    onSuccess: async () => {
      setRemoving(null);
      await refresh();
      toast.success('Removed holiday');
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const onSubmit = (event: FormEvent) => {
    event.preventDefault();
    add.mutate();
  };

  return (
    <SettingsBlock title="Holidays" description="Nobody is marked absent on a holiday, and check-in is closed.">
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Select aria-label="Year" value={year} onChange={(e) => setYear(Number(e.target.value))} className="w-28">
          {[thisYear - 1, thisYear, thisYear + 1].map((y) => (
            <option key={y} value={y}>
              {y}
            </option>
          ))}
        </Select>
        {canEdit && organization.timezone === 'Africa/Lagos' && (
          <Button variant="secondary" size="sm" loading={addNigerian.isPending} onClick={() => addNigerian.mutate()}>
            Add Nigeria’s fixed public holidays
          </Button>
        )}
      </div>

      {holidays.isPending && <Spinner />}
      {holidays.isError && <ErrorNotice error={holidays.error} />}
      {holidays.data && (
        <ul className="mb-5 divide-y divide-rule rounded-lg border border-rule">
          {holidays.data.length === 0 && <li className="px-4 py-3 text-sm text-muted">No holidays in {year} yet.</li>}
          {holidays.data.map((holiday) => (
            <li key={holiday.id} className="flex items-center justify-between gap-3 px-4 py-2.5 text-sm">
              <span>
                <span className="font-medium">{holiday.name}</span>
                <span className="ml-2 text-muted">{formatLongDate(holiday.date)}</span>
              </span>
              {canEdit && (
                <Button
                  variant="ghost"
                  size="sm"
                  aria-label={`Remove ${holiday.name}`}
                  onClick={() => setRemoving(holiday)}
                >
                  <Trash2 className="size-4" />
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}

      {canEdit && (
        <form onSubmit={onSubmit} className="flex flex-col gap-3">
          {add.isError && <ErrorNotice error={add.error} />}
          <div className="grid gap-3 sm:grid-cols-[10rem_1fr_auto] sm:items-end">
            <Field label="Date">
              <Input type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
            </Field>
            <Field label="Name">
              <Input
                required
                minLength={2}
                maxLength={80}
                placeholder="e.g. Mid-term break"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </Field>
            <Button type="submit" loading={add.isPending} disabled={!date || name.trim().length < 2}>
              Add holiday
            </Button>
          </div>
        </form>
      )}

      <ConfirmDialog
        open={removing !== null}
        title="Remove this holiday?"
        confirmLabel="Remove holiday"
        destructive
        loading={remove.isPending}
        onConfirm={() => removing && remove.mutate(removing)}
        onClose={() => setRemoving(null)}
      >
        {removing &&
          `${removing.name} on ${formatLongDate(removing.date)} becomes a normal working day again. Anyone who did not check in will count as absent.`}
      </ConfirmDialog>
    </SettingsBlock>
  );
}

const PERIOD_TYPES: Array<{ value: PeriodType; label: string }> = [
  { value: 'TERM', label: 'Term' },
  { value: 'SESSION', label: 'Session' },
  { value: 'MONTH', label: 'Month' },
  { value: 'CUSTOM', label: 'Other' },
];

export function PeriodsSection() {
  const canEdit = useCan('ADMIN');
  const queryClient = useQueryClient();
  const periods = useQuery({ queryKey: queryKeys.periods, queryFn: calendarApi.periods });
  const [editing, setEditing] = useState<Period | 'new' | null>(null);
  const [removing, setRemoving] = useState<Period | null>(null);

  const remove = useMutation({
    mutationFn: (period: Period) => calendarApi.deletePeriod(period.id),
    onSuccess: async () => {
      setRemoving(null);
      await queryClient.invalidateQueries({ queryKey: queryKeys.periods });
      toast.success('Deleted period');
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <SettingsBlock
      title="Terms & periods"
      description="Name your terms, sessions or months once, then report on them in one click."
    >
      {periods.isPending && <Spinner />}
      {periods.isError && <ErrorNotice error={periods.error} />}
      {periods.data && (
        <ul className="mb-5 divide-y divide-rule rounded-lg border border-rule">
          {periods.data.length === 0 && (
            <li className="px-4 py-3 text-sm text-muted">No periods yet, e.g. “1st Term 2026/27”.</li>
          )}
          {periods.data.map((period) => (
            <li key={period.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5 text-sm">
              <span>
                <span className="font-medium">{period.name}</span>
                <span className="ml-2 text-muted">
                  {formatShortDate(period.startsOn)} to {formatShortDate(period.endsOn)}
                </span>
              </span>
              {canEdit && (
                <span className="flex gap-1">
                  <Button variant="ghost" size="sm" onClick={() => setEditing(period)}>
                    Edit<span className="sr-only"> {period.name}</span>
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    aria-label={`Delete ${period.name}`}
                    onClick={() => setRemoving(period)}
                  >
                    <Trash2 className="size-4" />
                  </Button>
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
      {canEdit && <Button onClick={() => setEditing('new')}>Add a period</Button>}

      {editing && <PeriodDialog period={editing === 'new' ? undefined : editing} onClose={() => setEditing(null)} />}
      <ConfirmDialog
        open={removing !== null}
        title="Delete this period?"
        confirmLabel="Delete period"
        destructive
        loading={remove.isPending}
        onConfirm={() => removing && remove.mutate(removing)}
        onClose={() => setRemoving(null)}
      >
        Attendance records are not affected; only the shortcut for reports is removed.
      </ConfirmDialog>
    </SettingsBlock>
  );
}

function PeriodDialog({ period, onClose }: { period?: Period; onClose: () => void }) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState({
    name: period?.name ?? '',
    type: period?.type ?? ('TERM' as PeriodType),
    startsOn: period?.startsOn ?? '',
    endsOn: period?.endsOn ?? '',
  });
  const invalidRange = form.startsOn && form.endsOn && form.startsOn > form.endsOn;

  const save = useMutation({
    mutationFn: () => (period ? calendarApi.updatePeriod(period.id, form) : calendarApi.createPeriod(form)),
    onSuccess: async (saved) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.periods });
      toast.success(`Saved ${saved.name}`);
      onClose();
    },
  });

  return (
    <Dialog
      open
      onClose={onClose}
      title={period ? `Edit ${period.name}` : 'Add a period'}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="period-form"
            loading={save.isPending}
            disabled={form.name.trim().length < 2 || !form.startsOn || !form.endsOn || Boolean(invalidRange)}
          >
            Save period
          </Button>
        </>
      }
    >
      <form
        id="period-form"
        onSubmit={(event) => {
          event.preventDefault();
          save.mutate();
        }}
        className="flex flex-col gap-4"
      >
        {save.isError && <ErrorNotice error={save.error} />}
        <Field label="Name">
          <Input
            autoFocus
            placeholder="1st Term 2026/27"
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
          />
        </Field>
        <Field label="Type">
          <Select value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value as PeriodType })}>
            {PERIOD_TYPES.map((type) => (
              <option key={type.value} value={type.value}>
                {type.label}
              </option>
            ))}
          </Select>
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Starts">
            <Input type="date" value={form.startsOn} onChange={(e) => setForm({ ...form, startsOn: e.target.value })} />
          </Field>
          <Field label="Ends" error={invalidRange ? 'Must be on or after the start date' : undefined}>
            <Input type="date" value={form.endsOn} onChange={(e) => setForm({ ...form, endsOn: e.target.value })} />
          </Field>
        </div>
      </form>
    </Dialog>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/settings/holidays.ts' <<'__ATTENDANCE_EOF__'
/** Fixed-date public holidays in Nigeria. Movable ones (Easter, Eid) change yearly: add those by hand. */
export const NIGERIAN_FIXED_HOLIDAYS = [
  ['01-01', "New Year's Day"],
  ['05-01', "Workers' Day"],
  ['06-12', 'Democracy Day'],
  ['10-01', 'Independence Day'],
  ['12-25', 'Christmas Day'],
  ['12-26', 'Boxing Day'],
] as const;
__ATTENDANCE_EOF__

write 'apps/web/src/features/settings/organization-sections.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { organizationApi } from '@/api/endpoints';
import type { Policy, PolicyKind } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { useAuth, useCan, useProfile } from '@/features/auth/use-auth';
import { cn } from '@/lib/cn';
import { WEEKDAYS } from '@/lib/format';
import { timeZones } from '@/lib/time-zones';
import { validatePolicy } from './policy';
import { SettingsBlock } from './settings-block';

export function OrganizationSection() {
  const { organization } = useProfile();
  const { reloadProfile } = useAuth();
  const canEdit = useCan('ADMIN');
  const [name, setName] = useState(organization.name);
  const [timezone, setTimezone] = useState(organization.timezone);

  const save = useMutation({
    mutationFn: () => organizationApi.update({ name: name.trim(), timezone }),
    onSuccess: async () => {
      await reloadProfile();
      toast.success('Saved organisation details');
    },
  });

  const onSubmit = (event: FormEvent) => {
    event.preventDefault();
    save.mutate();
  };

  return (
    <SettingsBlock
      title="Organisation"
      description={`Registered as a ${organization.type === 'SCHOOL' ? 'school' : 'company'}.`}
    >
      <form onSubmit={onSubmit} className="flex flex-col gap-4">
        {save.isError && <ErrorNotice error={save.error} />}
        <Field label="Name">
          <Input
            value={name}
            disabled={!canEdit}
            minLength={2}
            maxLength={120}
            onChange={(e) => setName(e.target.value)}
          />
        </Field>
        <Field label="Timezone" hint="Check-in times, late marks and dates all use this timezone.">
          <Select value={timezone} disabled={!canEdit} onChange={(e) => setTimezone(e.target.value)}>
            {timeZones().map((zone) => (
              <option key={zone} value={zone}>
                {zone.replaceAll('_', ' ')}
              </option>
            ))}
          </Select>
        </Field>
        {canEdit && (
          <Button type="submit" className="self-start" loading={save.isPending} disabled={name.trim().length < 2}>
            Save changes
          </Button>
        )}
      </form>
    </SettingsBlock>
  );
}

const KINDS: Array<{ value: PolicyKind; title: string; detail: string }> = [
  { value: 'FIXED_WINDOW', title: 'Fixed window', detail: 'Check-in closes at a set time. Suits schools and shifts.' },
  { value: 'FLEXIBLE_HOURS', title: 'Flexible hours', detail: 'Check in any time after opening. Suits offices.' },
];

export function PolicySection() {
  const { organization } = useProfile();
  const { reloadProfile } = useAuth();
  const queryClient = useQueryClient();
  const canEdit = useCan('ADMIN');
  const [policy, setPolicy] = useState<Policy>({
    ...organization.policy,
    closesAt: organization.policy.closesAt ?? '08:30',
  });
  const problem = validatePolicy(policy);

  const save = useMutation({
    mutationFn: () => {
      const { closesAt, ...rest } = policy;
      return organizationApi.updatePolicy(policy.kind === 'FIXED_WINDOW' ? { ...rest, closesAt } : rest);
    },
    onSuccess: async () => {
      await reloadProfile();
      await queryClient.invalidateQueries({ queryKey: ['attendance'] });
      await queryClient.invalidateQueries({ queryKey: ['reports'] });
      toast.success('Saved attendance rules');
    },
  });

  const set = <K extends keyof Policy>(key: K, value: Policy[K]) =>
    setPolicy((current) => ({ ...current, [key]: value }));
  const toggleDay = (day: number) =>
    set(
      'workDays',
      policy.workDays.includes(day) ? policy.workDays.filter((d) => d !== day) : [...policy.workDays, day].sort(),
    );

  return (
    <SettingsBlock
      title="Attendance rules"
      description={`All times are in ${organization.timezone.replaceAll('_', ' ')}.`}
    >
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (!problem) save.mutate();
        }}
        className="flex flex-col gap-5"
      >
        {save.isError && <ErrorNotice error={save.error} />}
        <fieldset disabled={!canEdit} className="grid gap-2 sm:grid-cols-2">
          <legend className="mb-2 text-sm font-medium">How check-in works</legend>
          {KINDS.map((kind) => (
            <label
              key={kind.value}
              className={cn(
                'cursor-pointer rounded-lg border px-3 py-2.5 has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink',
                policy.kind === kind.value ? 'border-ink bg-ink-wash' : 'border-rule',
              )}
            >
              <input
                type="radio"
                name="kind"
                className="sr-only"
                checked={policy.kind === kind.value}
                onChange={() => set('kind', kind.value)}
              />
              <span className="block font-semibold text-ink">{kind.title}</span>
              <span className="block text-xs text-muted">{kind.detail}</span>
            </label>
          ))}
        </fieldset>

        <fieldset disabled={!canEdit}>
          <legend className="mb-2 text-sm font-medium">Working days</legend>
          <div className="flex flex-wrap gap-1.5">
            {WEEKDAYS.map((day) => {
              const on = policy.workDays.includes(day.value);
              return (
                <label
                  key={day.value}
                  className={cn(
                    'cursor-pointer rounded-lg border px-3 py-1.5 text-sm font-medium has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink',
                    on ? 'border-ink bg-ink text-white' : 'border-rule text-muted',
                  )}
                >
                  <input
                    type="checkbox"
                    className="sr-only"
                    checked={on}
                    onChange={() => toggleDay(day.value)}
                    aria-label={day.long}
                  />
                  {day.short}
                </label>
              );
            })}
          </div>
        </fieldset>

        <div className="grid gap-4 sm:grid-cols-3">
          <Field label="Opens at">
            <Input
              type="time"
              disabled={!canEdit}
              value={policy.opensAt}
              onChange={(e) => set('opensAt', e.target.value)}
            />
          </Field>
          <Field label="Late after" hint="On time up to this minute.">
            <Input
              type="time"
              disabled={!canEdit}
              value={policy.lateAfter}
              onChange={(e) => set('lateAfter', e.target.value)}
            />
          </Field>
          {policy.kind === 'FIXED_WINDOW' && (
            <Field label="Closes at" hint="No check-ins after this.">
              <Input
                type="time"
                disabled={!canEdit}
                value={policy.closesAt ?? ''}
                onChange={(e) => set('closesAt', e.target.value)}
              />
            </Field>
          )}
        </div>

        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            disabled={!canEdit}
            checked={policy.allowCheckOut}
            onChange={(e) => set('allowCheckOut', e.target.checked)}
            className="size-4 accent-[var(--color-ink)]"
          />
          Record check-out times too
        </label>

        {problem && <p className="text-sm text-absent">{problem}</p>}
        {canEdit && (
          <Button type="submit" className="self-start" loading={save.isPending} disabled={problem !== null}>
            Save rules
          </Button>
        )}
      </form>
    </SettingsBlock>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/settings/pairing.ts' <<'__ATTENDANCE_EOF__'
/** The fragment (#token=…) is never sent to any server, including our own. */
export const pairingLink = (token: string) => `${window.location.origin}/kiosk/pair#token=${encodeURIComponent(token)}`;
__ATTENDANCE_EOF__

write 'apps/web/src/features/settings/policy.ts' <<'__ATTENDANCE_EOF__'
import type { Policy } from '@/api/types';

/** Mirrors the API rule set so mistakes are caught before saving. */
export function validatePolicy(policy: Policy): string | null {
  if (policy.workDays.length === 0) return 'Choose at least one working day.';
  if (policy.lateAfter < policy.opensAt) return '“Late after” must be at or after the opening time.';
  if (policy.kind === 'FIXED_WINDOW' && (!policy.closesAt || policy.closesAt < policy.lateAfter)) {
    return '“Closes at” must be at or after “Late after”.';
  }
  return null;
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/settings/settings-block.tsx' <<'__ATTENDANCE_EOF__'
import type { ReactNode } from 'react';

/** Consistent block for one settings form. */
export function SettingsBlock({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: ReactNode;
}) {
  return (
    <section className="max-w-2xl rounded-2xl border border-rule bg-paper px-6 py-5">
      <h2 className="text-xl font-semibold">{title}</h2>
      {description && <p className="mt-1 text-sm text-muted">{description}</p>}
      <div className="mt-5">{children}</div>
    </section>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/settings/settings-page.tsx' <<'__ATTENDANCE_EOF__'
import { useSearchParams } from 'react-router';
import { PageHeader } from '@/components/layout/page-header';
import { Tabs } from '@/components/ui/tabs';
import { useCan } from '@/features/auth/use-auth';
import { DevicesSection, TeamSection } from './access-sections';
import { HolidaysSection, PeriodsSection } from './calendar-sections';
import { OrganizationSection, PolicySection } from './organization-sections';

const ALL_TABS = [
  { id: 'organization', label: 'Organisation', adminOnly: false },
  { id: 'rules', label: 'Attendance rules', adminOnly: false },
  { id: 'holidays', label: 'Holidays', adminOnly: false },
  { id: 'periods', label: 'Terms & periods', adminOnly: false },
  { id: 'devices', label: 'Check-in devices', adminOnly: true },
  { id: 'team', label: 'Team', adminOnly: true },
] as const;
type TabId = (typeof ALL_TABS)[number]['id'];

export function SettingsPage() {
  const isAdmin = useCan('ADMIN');
  const [params, setParams] = useSearchParams();
  const tabs = ALL_TABS.filter((tab) => isAdmin || !tab.adminOnly);
  const requested = params.get('tab');
  const active: TabId = tabs.find((tab) => tab.id === requested)?.id ?? 'organization';

  return (
    <>
      <PageHeader title="Settings">
        {isAdmin ? null : 'You can view these settings. Ask an admin to change them.'}
      </PageHeader>
      <Tabs
        label="Settings sections"
        tabs={tabs}
        value={active}
        onChange={(id) => setParams({ tab: id }, { replace: true })}
      />
      <div role="tabpanel" id={`panel-${active}`} aria-labelledby={`tab-${active}`} className="pt-6">
        {active === 'organization' && <OrganizationSection />}
        {active === 'rules' && <PolicySection />}
        {active === 'holidays' && <HolidaysSection />}
        {active === 'periods' && <PeriodsSection />}
        {active === 'devices' && <DevicesSection />}
        {active === 'team' && <TeamSection />}
      </div>
    </>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/today/correct-dialog.tsx' <<'__ATTENDANCE_EOF__'
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { toast } from 'sonner';
import { attendanceApi, queryKeys } from '@/api/endpoints';
import type { AttendanceStatus, DailyRow } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Dialog } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/cn';

type Choice = AttendanceStatus | 'CLEAR';

const CHOICES: Array<{ value: Choice; label: string }> = [
  { value: 'PRESENT', label: 'On time' },
  { value: 'LATE', label: 'Late' },
  { value: 'CLEAR', label: 'No record' },
];

/** Admin correction for one person on one day: forgot to check in, device was offline, wrong mark. */
export function CorrectDialog({ row, date, onClose }: { row: DailyRow | null; date: string; onClose: () => void }) {
  const queryClient = useQueryClient();
  const current: Choice = row?.status === 'PRESENT' || row?.status === 'LATE' ? row.status : 'CLEAR';
  const [choice, setChoice] = useState<Choice>(current);
  const [time, setTime] = useState('');
  const [note, setNote] = useState('');

  const save = useMutation({
    mutationFn: async () => {
      if (!row) return;
      if (choice === 'CLEAR') {
        if (row.recordId) await attendanceApi.deleteRecord(row.recordId);
        return;
      }
      await attendanceApi.recordManually({
        memberId: row.member.id,
        date,
        status: choice,
        ...(time ? { time } : {}),
        ...(note.trim() ? { note: note.trim() } : {}),
      });
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      await queryClient.invalidateQueries({ queryKey: ['reports'] });
      toast.success(`Saved ${row?.member.fullName}’s attendance`);
      onClose();
    },
  });

  return (
    <Dialog
      open={row !== null}
      onClose={onClose}
      title={row ? `Correct ${row.member.fullName}` : ''}
      description="Changes are recorded as a manual correction."
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={() => save.mutate()} loading={save.isPending}>
            Save correction
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        {save.isError && <ErrorNotice error={save.error} />}
        <fieldset>
          <legend className="mb-2 text-sm font-medium">Mark as</legend>
          <div className="grid grid-cols-3 gap-2">
            {CHOICES.map((option) => (
              <label
                key={option.value}
                className={cn(
                  'cursor-pointer rounded-lg border px-3 py-2 text-center text-sm font-medium has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink',
                  choice === option.value ? 'border-ink bg-ink-wash text-ink' : 'border-rule text-muted',
                )}
              >
                <input
                  type="radio"
                  name="mark"
                  value={option.value}
                  checked={choice === option.value}
                  onChange={() => setChoice(option.value)}
                  className="sr-only"
                />
                {option.label}
              </label>
            ))}
          </div>
        </fieldset>
        {choice !== 'CLEAR' && (
          <>
            <Field label="Arrival time" hint="Optional. Defaults to the opening or late time.">
              <Input type="time" value={time} onChange={(event) => setTime(event.target.value)} />
            </Field>
            <Field label="Note" hint="Optional, e.g. “Signed the paper register”.">
              <Input value={note} maxLength={200} onChange={(event) => setNote(event.target.value)} />
            </Field>
          </>
        )}
      </div>
    </Dialog>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/today/segment-bar.tsx' <<'__ATTENDANCE_EOF__'
import type { DailyView } from '@/api/types';

/** One bar, four segments: on time, late, absent, not in yet. */
export function SegmentBar({ totals }: { totals: DailyView['totals'] }) {
  const segments = [
    { key: 'present', value: totals.present, className: 'bg-present', label: 'On time' },
    { key: 'late', value: totals.late, className: 'bg-late', label: 'Late' },
    { key: 'absent', value: totals.absent, className: 'bg-absent', label: 'Absent' },
    { key: 'pending', value: totals.notCheckedIn, className: 'bg-rule', label: 'Not in yet' },
  ].filter((segment) => segment.value > 0);
  const total = segments.reduce((sum, segment) => sum + segment.value, 0);
  if (total === 0) return null;

  return (
    <div>
      <div className="flex h-2.5 overflow-hidden rounded-full bg-desk" aria-hidden>
        {segments.map((segment) => (
          <div key={segment.key} className={segment.className} style={{ width: `${(segment.value / total) * 100}%` }} />
        ))}
      </div>
      <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted">
        {segments.map((segment) => (
          <li key={segment.key} className="inline-flex items-center gap-1.5">
            <span className={`size-2 rounded-full ${segment.className}`} aria-hidden />
            {segment.label} <span className="tabular font-semibold text-text">{segment.value}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/today/today-page.tsx' <<'__ATTENDANCE_EOF__'
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, ChevronRight, Search } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { attendanceApi, queryKeys } from '@/api/endpoints';
import type { DailyRow, DailyStatus } from '@/api/types';
import { PageHeader } from '@/components/layout/page-header';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Input, Select } from '@/components/ui/input';
import { StatusPill } from '@/components/ui/status-pill';
import { useCan, useProfile } from '@/features/auth/use-auth';
import { addDays, formatLongDate, timeIn, todayIn } from '@/lib/format';
import { CorrectDialog } from './correct-dialog';
import { SegmentBar } from './segment-bar';
import { summarizeDay } from './today-summary';

type Filter = 'ALL' | 'IN' | 'LATE' | 'OUT';

const FILTERS: Record<Filter, (status: DailyStatus) => boolean> = {
  ALL: () => true,
  IN: (status) => status === 'PRESENT' || status === 'LATE',
  LATE: (status) => status === 'LATE',
  OUT: (status) => status === 'ABSENT' || status === 'NOT_CHECKED_IN',
};

export function TodayPage() {
  const { organization } = useProfile();
  const canCorrect = useCan('ADMIN');
  const showLeft = organization.policy.allowCheckOut;
  const today = todayIn(organization.timezone);
  const [params, setParams] = useSearchParams();
  const date = params.get('date') ?? today;

  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<Filter>('ALL');
  const [group, setGroup] = useState('');
  const [correcting, setCorrecting] = useState<DailyRow | null>(null);

  const daily = useQuery({
    queryKey: queryKeys.daily(date),
    queryFn: () => attendanceApi.daily(date === today ? undefined : date),
    refetchInterval: date === today ? 30_000 : false, // live board while the day is in progress
  });

  const goTo = (next: string) => setParams(next === today ? {} : { date: next }, { replace: true });

  const groups = useMemo(
    () =>
      [
        ...new Set((daily.data?.rows ?? []).map((row) => row.member.group).filter((g): g is string => Boolean(g))),
      ].sort(),
    [daily.data],
  );

  const rows = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return (daily.data?.rows ?? []).filter(
      (row) =>
        FILTERS[filter](row.status) &&
        (!group || row.member.group === group) &&
        (!needle ||
          row.member.fullName.toLowerCase().includes(needle) ||
          row.member.code.toLowerCase().includes(needle)),
    );
  }, [daily.data, search, filter, group]);

  return (
    <>
      <PageHeader
        title={date === today ? 'Today' : 'Register'}
        actions={
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="sm" aria-label="Previous day" onClick={() => goTo(addDays(date, -1))}>
              <ChevronLeft className="size-4" />
            </Button>
            <Input
              type="date"
              aria-label="Choose a date"
              value={date}
              max={today}
              onChange={(event) => event.target.value && goTo(event.target.value)}
              className="h-8 w-40"
            />
            <Button
              variant="ghost"
              size="sm"
              aria-label="Next day"
              disabled={date >= today}
              onClick={() => goTo(addDays(date, 1))}
            >
              <ChevronRight className="size-4" />
            </Button>
            {date !== today && (
              <Button variant="secondary" size="sm" onClick={() => goTo(today)}>
                Back to today
              </Button>
            )}
          </div>
        }
      >
        {formatLongDate(date)}
      </PageHeader>

      {daily.isPending && <Spinner label="Loading the register" />}
      {daily.isError && <ErrorNotice error={daily.error} onRetry={() => void daily.refetch()} />}

      {daily.data && (
        <>
          <section aria-label="Summary" className="mb-6 rounded-2xl border border-rule bg-paper px-6 py-5">
            <p className="font-display text-xl font-medium text-ink sm:text-2xl">{summarizeDay(daily.data)}</p>
            <div className="mt-4">
              <SegmentBar totals={daily.data.totals} />
            </div>
          </section>

          {daily.data.rows.length === 0 ? (
            <EmptyState
              title="No one on the register yet"
              action={
                <Link to="/people" className="font-semibold text-ink underline underline-offset-4">
                  Add people
                </Link>
              }
            >
              People you add appear here every working day.
            </EmptyState>
          ) : (
            <section aria-label="Register">
              <div className="mb-3 flex flex-wrap gap-2">
                <div className="relative min-w-48 flex-1">
                  <Search
                    className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted"
                    aria-hidden
                  />
                  <Input
                    type="search"
                    placeholder="Search name or code"
                    aria-label="Search name or code"
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    className="pl-9"
                  />
                </div>
                <Select
                  aria-label="Show"
                  value={filter}
                  onChange={(event) => setFilter(event.target.value as Filter)}
                  className="w-auto"
                >
                  <option value="ALL">Everyone</option>
                  <option value="IN">Checked in</option>
                  <option value="LATE">Late</option>
                  <option value="OUT">{daily.data.isToday ? 'Not in yet' : 'Absent'}</option>
                </Select>
                {groups.length > 0 && (
                  <Select
                    aria-label="Group"
                    value={group}
                    onChange={(event) => setGroup(event.target.value)}
                    className="w-auto"
                  >
                    <option value="">All groups</option>
                    {groups.map((name) => (
                      <option key={name}>{name}</option>
                    ))}
                  </Select>
                )}
              </div>

              <div className="overflow-hidden rounded-2xl border border-rule bg-paper">
                <table className="w-full text-left text-sm">
                  <thead className="border-b border-rule text-muted">
                    <tr>
                      <th scope="col" className="px-4 py-3 font-medium">
                        Name
                      </th>
                      <th scope="col" className="hidden px-4 py-3 font-medium sm:table-cell">
                        Group
                      </th>
                      <th scope="col" className="px-4 py-3 font-medium">
                        Status
                      </th>
                      {showLeft && (
                        <th scope="col" className="hidden px-4 py-3 font-medium md:table-cell">
                          Left
                        </th>
                      )}
                      {canCorrect && (
                        <th scope="col" className="w-0 px-4 py-3">
                          <span className="sr-only">Actions</span>
                        </th>
                      )}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-rule">
                    {rows.map((row) => (
                      <tr key={row.member.id} className="hover:bg-desk/60">
                        <td className="px-4 py-3">
                          <Link
                            to={`/people/${row.member.id}`}
                            className="font-medium text-text hover:text-ink hover:underline"
                          >
                            {row.member.fullName}
                          </Link>
                          <span className="ml-2 tabular text-xs text-muted">{row.member.code}</span>
                        </td>
                        <td className="hidden px-4 py-3 text-muted sm:table-cell">{row.member.group ?? '–'}</td>
                        <td className="px-4 py-3">
                          <StatusPill
                            status={row.status}
                            time={row.checkInAt ? timeIn(organization.timezone, row.checkInAt) : null}
                          />
                        </td>
                        {showLeft && (
                          <td className="hidden px-4 py-3 tabular text-muted md:table-cell">
                            {row.checkOutAt ? timeIn(organization.timezone, row.checkOutAt) : '–'}
                          </td>
                        )}
                        {canCorrect && (
                          <td className="px-4 py-3 text-right">
                            {row.status !== 'HOLIDAY' && row.status !== 'NON_WORKDAY' && (
                              <Button variant="ghost" size="sm" onClick={() => setCorrecting(row)}>
                                Correct<span className="sr-only"> {row.member.fullName}</span>
                              </Button>
                            )}
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
                {rows.length === 0 && <p className="px-4 py-6 text-sm text-muted">Nobody matches these filters.</p>}
              </div>
            </section>
          )}
        </>
      )}

      {correcting && (
        <CorrectDialog key={correcting.member.id} row={correcting} date={date} onClose={() => setCorrecting(null)} />
      )}
    </>
  );
}
__ATTENDANCE_EOF__

write 'apps/web/src/features/today/today-summary.test.ts' <<'__ATTENDANCE_EOF__'
import { describe, expect, it } from 'vitest';
import type { DailyView } from '@/api/types';
import { summarizeDay } from './today-summary';

const day = (overrides: Partial<DailyView>, totals: Partial<DailyView['totals']> = {}): DailyView => ({
  date: '2026-09-28',
  isToday: true,
  isWorkday: true,
  holiday: null,
  rows: [],
  ...overrides,
  totals: { expected: 24, present: 15, late: 3, absent: 0, notCheckedIn: 6, ...totals },
});

describe('summarizeDay', () => {
  it('reads like a sentence during the day', () => {
    expect(summarizeDay(day({}))).toBe('18 of 24 in. 3 late. 6 not in yet.');
  });

  it('switches to past tense with absences for past days', () => {
    expect(summarizeDay(day({ isToday: false }, { notCheckedIn: 0, absent: 6 }))).toBe(
      '18 of 24 attended. 3 late. 6 absent.',
    );
  });

  it('celebrates a full register, and handles holidays and empty registers', () => {
    expect(summarizeDay(day({}, { present: 24, late: 0, notCheckedIn: 0 }))).toBe(
      '24 of 24 in. Everyone is accounted for.',
    );
    expect(summarizeDay(day({ holiday: 'Independence Day' }))).toBe('Holiday: Independence Day. Nobody is expected.');
    expect(summarizeDay(day({}, { expected: 0 }))).toMatch(/Add people/);
  });
});
__ATTENDANCE_EOF__

write 'apps/web/src/features/today/today-summary.ts' <<'__ATTENDANCE_EOF__'
import type { DailyView } from '@/api/types';

/** The day's register in one plain sentence, e.g. "18 of 24 in. 3 late. 6 not in yet." */
export function summarizeDay(day: DailyView): string {
  if (day.holiday) return `Holiday: ${day.holiday}. Nobody is expected.`;
  if (!day.isWorkday) return 'Not a working day. Nobody is expected.';
  const { expected, present, late, absent, notCheckedIn } = day.totals;
  if (expected === 0) return 'Nobody is expected yet. Add people to start taking attendance.';

  const attended = present + late;
  const parts = [day.isToday ? `${attended} of ${expected} in.` : `${attended} of ${expected} attended.`];
  if (late > 0) parts.push(`${late} late.`);
  if (day.isToday && notCheckedIn > 0) parts.push(`${notCheckedIn} not in yet.`);
  if (absent > 0) parts.push(`${absent} absent.`);
  if (attended === expected) parts.push('Everyone is accounted for.');
  return parts.join(' ');
}
__ATTENDANCE_EOF__

write 'apps/web/src/lib/api-error.ts' <<'__ATTENDANCE_EOF__'
/** Shape of every API error body: `{ error: { code, message, details? } }` */
interface ErrorBody {
  error?: { code?: string; message?: string; details?: unknown };
}

/** A failed API call. `code` and `reason` are stable and safe to branch on; `message` is user-facing. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = 'ApiError';
  }

  /** `details.reason` when the API supplied one (e.g. WINDOW_CLOSED, TOKEN_EXPIRED). */
  get reason(): string | undefined {
    const details = this.details;
    if (details && typeof details === 'object' && 'reason' in details && typeof details.reason === 'string') {
      return details.reason;
    }
    return undefined;
  }

  /** Field-level validation issues keyed by dotted path, e.g. { "user.email": "must be a valid email address" }. */
  get fieldErrors(): Record<string, string> {
    if (!Array.isArray(this.details)) return {};
    return Object.fromEntries(
      this.details
        .filter((issue): issue is { path: string; message: string } => typeof issue?.path === 'string')
        .map((issue) => [issue.path, issue.message]),
    );
  }

  static async fromResponse(response: Response): Promise<ApiError> {
    let body: ErrorBody = {};
    try {
      body = (await response.json()) as ErrorBody;
    } catch {
      // Non-JSON error (proxy page, captive portal…): fall back to a generic message.
    }
    return new ApiError(
      response.status,
      body.error?.code ?? `HTTP_${response.status}`,
      body.error?.message ?? defaultMessage(response.status),
      body.error?.details,
    );
  }

  static network(cause: unknown): ApiError {
    const error = new ApiError(0, 'NETWORK_ERROR', 'Cannot reach the server. Check your internet connection.');
    error.cause = cause;
    return error;
  }
}

function defaultMessage(status: number): string {
  if (status === 429) return 'Too many attempts. Wait a few minutes and try again.';
  if (status >= 500) return 'The server had a problem. Try again in a moment.';
  return 'The request could not be completed.';
}

export function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return 'Something went wrong.';
}
__ATTENDANCE_EOF__

write 'apps/web/src/lib/cn.ts' <<'__ATTENDANCE_EOF__'
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/** Joins class names; later Tailwind utilities override earlier ones. */
export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));
__ATTENDANCE_EOF__

write 'apps/web/src/lib/download.ts' <<'__ATTENDANCE_EOF__'
import type { Download } from './http';

/** Saves a Blob through a temporary link. */
export function saveDownload({ blob, fileName }: Download): void {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1_000);
}

export function saveText(text: string, fileName: string, type = 'text/csv;charset=utf-8'): void {
  saveDownload({ blob: new Blob([text], { type }), fileName });
}
__ATTENDANCE_EOF__

write 'apps/web/src/lib/format.test.ts' <<'__ATTENDANCE_EOF__'
import { describe, expect, it } from 'vitest';
import { addDays, formatPercent, plural, timeIn, todayIn } from './format';

describe('format', () => {
  it('uses the organisation timezone, not the browser’s', () => {
    const lateEvening = new Date('2026-09-30T23:30:00.000Z'); // already 1 Oct in Lagos (UTC+1)
    expect(todayIn('Africa/Lagos', lateEvening)).toBe('2026-10-01');
    expect(todayIn('UTC', lateEvening)).toBe('2026-09-30');
    expect(timeIn('Africa/Lagos', '2026-09-28T06:45:00.000Z')).toBe('07:45');
  });

  it('does calendar arithmetic without timezone drift', () => {
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
  });

  it('writes counts and rates the way people read them', () => {
    expect(plural(1, 'absence')).toBe('1 absence');
    expect(plural(4, 'absence')).toBe('4 absences');
    expect(plural(1, 'person', 'people')).toBe('1 person');
    expect(plural(24, 'person', 'people')).toBe('24 people');
    expect(formatPercent(null)).toBe('–');
    expect(formatPercent(90)).toBe('90%');
    expect(formatPercent(83.333)).toBe('83.3%');
  });
});
__ATTENDANCE_EOF__

write 'apps/web/src/lib/format.ts' <<'__ATTENDANCE_EOF__'
/** API dates come in two shapes: org-local calendar dates ("2026-09-28") and absolute ISO instants. */

const LOCALE = 'en-NG';

/** Calendar date in a timezone, as YYYY-MM-DD. */
export function todayIn(timeZone: string, now: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

/** Wall-clock HH:mm in a timezone. */
export function timeIn(timeZone: string, instant: Date | string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', minute: '2-digit', hour12: false }).format(
    new Date(instant),
  );
}

/** Calendar dates are formatted in UTC so the viewer's own timezone can never shift them by a day. */
function calendar(date: string): Date {
  return new Date(`${date}T00:00:00Z`);
}

export function formatLongDate(date: string): string {
  return new Intl.DateTimeFormat(LOCALE, {
    timeZone: 'UTC',
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(calendar(date));
}

export function formatShortDate(date: string): string {
  return new Intl.DateTimeFormat(LOCALE, { timeZone: 'UTC', day: 'numeric', month: 'short', year: 'numeric' }).format(
    calendar(date),
  );
}

export function formatDayLabel(date: string): { weekday: string; day: string } {
  const d = calendar(date);
  return {
    weekday: new Intl.DateTimeFormat(LOCALE, { timeZone: 'UTC', weekday: 'narrow' }).format(d),
    day: String(d.getUTCDate()),
  };
}

export function addDays(date: string, days: number): string {
  const d = calendar(date);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

export function startOfMonth(date: string): string {
  return `${date.slice(0, 7)}-01`;
}

export function formatPercent(rate: number | null): string {
  if (rate === null) return '–';
  return `${Number.isInteger(rate) ? rate : rate.toFixed(1)}%`;
}

export function relativeTime(instant: string | null, now: Date = new Date()): string {
  if (!instant) return 'Never';
  const minutes = Math.round((now.getTime() - new Date(instant).getTime()) / 60_000);
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} h ago`;
  return `${Math.round(hours / 24)} days ago`;
}

export const WEEKDAYS = [
  { value: 1, short: 'Mon', long: 'Monday' },
  { value: 2, short: 'Tue', long: 'Tuesday' },
  { value: 3, short: 'Wed', long: 'Wednesday' },
  { value: 4, short: 'Thu', long: 'Thursday' },
  { value: 5, short: 'Fri', long: 'Friday' },
  { value: 6, short: 'Sat', long: 'Saturday' },
  { value: 7, short: 'Sun', long: 'Sunday' },
] as const;

/** "1 day", "2 days", "1 person", "3 people". */
export function plural(count: number, one: string, many = `${one}s`): string {
  return `${count} ${count === 1 ? one : many}`;
}
__ATTENDANCE_EOF__

write 'apps/web/src/lib/http.test.ts' <<'__ATTENDANCE_EOF__'
import { describe, expect, it, vi } from 'vitest';
import { fakeFetch, json } from '@/test/fake-fetch';
import { ApiError } from './api-error';
import { HttpClient, KioskHttpClient, SessionHttpClient } from './http';

type Session = { accessToken: string; user: string };
const session = (token: string): Session => ({ accessToken: token, user: 'ada' });
const authOf = (init: RequestInit) => (init.headers as Record<string, string>).Authorization;

describe('HttpClient', () => {
  it('unwraps the data envelope, builds query strings and skips empty params', async () => {
    const fetch = fakeFetch({ 'GET /members': () => json(200, { data: [{ id: 1 }], meta: { total: 1 } }) });
    const client = new HttpClient('/api/v1', fetch);

    await expect(client.get('/members', { search: 'ada', group: '', page: 2, status: undefined })).resolves.toEqual([
      { id: 1 },
    ]);
    expect(fetch.mock.calls[0]?.[0]).toBe('/api/v1/members?search=ada&page=2');
  });

  it('maps error bodies to ApiError with code, reason and field errors', async () => {
    const client = new HttpClient(
      '',
      fakeFetch({
        'POST /kiosk/check-in': () =>
          json(422, {
            error: {
              code: 'CHECK_IN_REJECTED',
              message: 'Check-in closed at 08:30',
              details: { reason: 'WINDOW_CLOSED' },
            },
          }),
        'POST /auth/register': () =>
          json(400, {
            error: {
              code: 'VALIDATION_ERROR',
              message: 'Invalid',
              details: [{ path: 'user.email', message: 'bad email' }],
            },
          }),
      }),
    );

    const rejected = await client.post('/kiosk/check-in', {}).catch((error: unknown) => error);
    expect(rejected).toBeInstanceOf(ApiError);
    expect(rejected).toMatchObject({
      status: 422,
      code: 'CHECK_IN_REJECTED',
      message: 'Check-in closed at 08:30',
      reason: 'WINDOW_CLOSED',
    });

    const invalid = (await client.post('/auth/register', {}).catch((error: unknown) => error)) as ApiError;
    expect(invalid.fieldErrors).toEqual({ 'user.email': 'bad email' });
  });

  it('turns fetch failures into a NETWORK_ERROR and non-JSON errors into a generic message', async () => {
    const offline = new HttpClient('', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));
    await expect(offline.get('/x')).rejects.toMatchObject({ code: 'NETWORK_ERROR', status: 0 });

    const proxyPage = new HttpClient(
      '',
      vi.fn().mockResolvedValue(new Response('<html>Bad gateway</html>', { status: 502 })),
    );
    await expect(proxyPage.get('/x')).rejects.toMatchObject({
      code: 'HTTP_502',
      message: 'The server had a problem. Try again in a moment.',
    });
  });

  it('reads the file name of downloads from Content-Disposition', async () => {
    const client = new HttpClient(
      '',
      fakeFetch({
        'GET /reports/attendance': () =>
          new Response('a,b', {
            status: 200,
            headers: { 'Content-Disposition': 'attachment; filename="attendance-2026-09.csv"' },
          }),
      }),
    );
    const file = await client.download('/reports/attendance', { format: 'csv' });
    expect(file.fileName).toBe('attendance-2026-09.csv');
    expect(await file.blob.text()).toBe('a,b');
  });
});

describe('SessionHttpClient', () => {
  it('sends the bearer token and retries once after refreshing an expired one', async () => {
    const fetch = fakeFetch({
      'GET /attendance/daily': [
        (init) =>
          authOf(init) === 'Bearer old'
            ? json(401, { error: { code: 'UNAUTHORIZED', message: 'expired' } })
            : json(500, {}),
        (init) => (authOf(init) === 'Bearer new' ? json(200, { data: { ok: true } }) : json(500, {})),
      ],
      'POST /auth/refresh': (init) => {
        expect((init.headers as Record<string, string>)['X-Requested-With']).toBe('XMLHttpRequest');
        return json(200, { data: session('new') });
      },
    });
    const client = new SessionHttpClient<Session>('', fetch);
    const refreshed = vi.fn();
    client.onSessionRefreshed = refreshed;
    client.setAccessToken('old');

    await expect(client.get('/attendance/daily')).resolves.toEqual({ ok: true });
    expect(refreshed).toHaveBeenCalledWith(session('new'));
    expect(fetch).toHaveBeenCalledTimes(3);
  });

  it('shares a single refresh between concurrent 401s (the server rotates refresh tokens)', async () => {
    let refreshes = 0;
    const fetch = fakeFetch({
      'GET /a': (init) => (authOf(init) === 'Bearer new' ? json(200, { data: 'a' }) : json(401, {})),
      'GET /b': (init) => (authOf(init) === 'Bearer new' ? json(200, { data: 'b' }) : json(401, {})),
      'GET /c': (init) => (authOf(init) === 'Bearer new' ? json(200, { data: 'c' }) : json(401, {})),
      'POST /auth/refresh': async () => {
        refreshes += 1;
        await new Promise((resolve) => setTimeout(resolve, 10));
        return json(200, { data: session('new') });
      },
    });
    const client = new SessionHttpClient<Session>('', fetch);
    client.setAccessToken('old');

    await expect(Promise.all([client.get('/a'), client.get('/b'), client.get('/c')])).resolves.toEqual(['a', 'b', 'c']);
    expect(refreshes).toBe(1);
  });

  it('reports an expired session when the refresh is rejected, without retrying', async () => {
    const fetch = fakeFetch({
      'GET /members': () => json(401, { error: { code: 'UNAUTHORIZED', message: 'Sign in again' } }),
      'POST /auth/refresh': () => json(401, { error: { code: 'UNAUTHORIZED', message: 'No session' } }),
    });
    const client = new SessionHttpClient<Session>('', fetch);
    const expired = vi.fn();
    client.onSessionExpired = expired;
    client.setAccessToken('old');

    await expect(client.get('/members')).rejects.toMatchObject({ status: 401 });
    expect(expired).toHaveBeenCalledOnce();
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it('never refreshes for auth endpoints: a wrong password is just a wrong password', async () => {
    const fetch = fakeFetch({
      'POST /auth/login': () => json(401, { error: { code: 'UNAUTHORIZED', message: 'Invalid email or password' } }),
    });
    const client = new SessionHttpClient<Session>('', fetch);

    await expect(client.post('/auth/login', {}, { skipRefresh: true })).rejects.toMatchObject({
      message: 'Invalid email or password',
    });
    expect(fetch).toHaveBeenCalledOnce();
  });
});

describe('KioskHttpClient', () => {
  it('authenticates with the device token and unpairs when the device is revoked', async () => {
    let token: string | null = 'kio_123';
    const tokens = { get: () => token, clear: () => (token = null) };
    const fetch = fakeFetch({
      'GET /kiosk/session': [
        (init) => (authOf(init) === 'Kiosk kio_123' ? json(200, { data: { ok: true } }) : json(500, {})),
        () => json(401, { error: { code: 'UNAUTHORIZED', message: 'Device revoked' } }),
      ],
    });
    const client = new KioskHttpClient('', tokens, fetch);
    const unpaired = vi.fn();
    client.onUnpaired = unpaired;

    await expect(client.get('/kiosk/session')).resolves.toEqual({ ok: true });
    await expect(client.get('/kiosk/session')).rejects.toMatchObject({ status: 401 });
    expect(token).toBeNull();
    expect(unpaired).toHaveBeenCalledOnce();
  });
});
__ATTENDANCE_EOF__

write 'apps/web/src/lib/http.ts' <<'__ATTENDANCE_EOF__'
import { ApiError } from './api-error';

export type Query = Record<string, string | number | boolean | null | undefined>;

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: unknown;
  query?: Query;
  headers?: Record<string, string>;
  signal?: AbortSignal;
  /** Auth endpoints must not trigger a token refresh when they return 401. */
  skipRefresh?: boolean;
}

export interface Envelope<T, M = undefined> {
  data: T;
  meta: M;
}

export interface Download {
  blob: Blob;
  fileName: string;
}

export type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

/**
 * Base API client: URL building, JSON encoding, envelope unwrapping and error mapping.
 * Subclasses only decide how a request is authenticated (SessionHttpClient, KioskHttpClient).
 */
export class HttpClient {
  constructor(
    protected readonly baseUrl: string,
    protected readonly fetchImpl: FetchLike = (input, init) => fetch(input, init),
  ) {}

  get<T>(path: string, query?: Query, signal?: AbortSignal): Promise<T> {
    return this.request<T>(path, { query, signal });
  }

  post<T>(path: string, body?: unknown, options: RequestOptions = {}): Promise<T> {
    return this.request<T>(path, { ...options, method: 'POST', body });
  }

  put<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>(path, { method: 'PUT', body });
  }

  patch<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>(path, { method: 'PATCH', body });
  }

  delete<T = void>(path: string): Promise<T> {
    return this.request<T>(path, { method: 'DELETE' });
  }

  /** Returns `data` from the `{ data }` envelope. */
  async request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    return (await this.envelope<T>(path, options)).data;
  }

  /** Returns the whole envelope, for paginated lists that carry `meta`. */
  async envelope<T, M = undefined>(path: string, options: RequestOptions = {}): Promise<Envelope<T, M>> {
    const response = await this.execute(path, options);
    if (response.status === 204) return { data: undefined as T, meta: undefined as M };
    return (await response.json()) as Envelope<T, M>;
  }

  /** Binary download (Excel/CSV). The file name comes from Content-Disposition. */
  async download(path: string, query?: Query): Promise<Download> {
    const response = await this.execute(path, { query });
    const disposition = response.headers.get('content-disposition') ?? '';
    const fileName = /filename="([^"]+)"/.exec(disposition)?.[1] ?? 'download';
    return { blob: await response.blob(), fileName };
  }

  /** Sends the request and throws ApiError for any non-2xx response. */
  protected async execute(path: string, options: RequestOptions): Promise<Response> {
    const response = await this.send(path, options);
    if (!response.ok) throw await ApiError.fromResponse(response);
    return response;
  }

  /** One HTTP round trip. Subclasses override this to add authentication behaviour. */
  protected async send(path: string, options: RequestOptions): Promise<Response> {
    const headers: Record<string, string> = { Accept: 'application/json', ...this.authHeaders(), ...options.headers };
    let body: string | undefined;
    if (options.body !== undefined) {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify(options.body);
    }
    try {
      return await this.fetchImpl(this.url(path, options.query), {
        method: options.method ?? 'GET',
        headers,
        body,
        credentials: 'include',
        signal: options.signal,
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') throw error;
      throw ApiError.network(error);
    }
  }

  protected authHeaders(): Record<string, string> {
    return {};
  }

  protected url(path: string, query?: Query): string {
    const search = new URLSearchParams();
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value !== undefined && value !== null && value !== '') search.set(key, String(value));
    }
    const qs = search.toString();
    return `${this.baseUrl}${path}${qs ? `?${qs}` : ''}`;
  }
}

/**
 * Dashboard client. Keeps the short-lived access token in memory only (never localStorage) and
 * transparently refreshes it with the httpOnly cookie when a request comes back 401.
 * Concurrent 401s share one refresh, because the server rotates the refresh token on every use.
 */
export class SessionHttpClient<TSession extends { accessToken: string }> extends HttpClient {
  private accessToken: string | null = null;
  private inflightRefresh: Promise<TSession | null> | null = null;

  /** Called when a refresh fails: the user must sign in again. */
  onSessionExpired: (() => void) | null = null;
  /** Called after every successful refresh with the fresh profile (roles can change). */
  onSessionRefreshed: ((session: TSession) => void) | null = null;

  setAccessToken(token: string | null): void {
    this.accessToken = token;
  }

  /** Exchanges the refresh cookie for a new access token. Safe to call from many places at once. */
  refresh(): Promise<TSession | null> {
    this.inflightRefresh ??= this.performRefresh().finally(() => {
      this.inflightRefresh = null;
    });
    return this.inflightRefresh;
  }

  protected override authHeaders(): Record<string, string> {
    return this.accessToken ? { Authorization: `Bearer ${this.accessToken}` } : {};
  }

  protected override async send(path: string, options: RequestOptions): Promise<Response> {
    const response = await super.send(path, options);
    if (response.status !== 401 || options.skipRefresh) return response;

    const session = await this.refresh();
    if (!session) {
      this.onSessionExpired?.();
      return response;
    }
    return super.send(path, options);
  }

  private async performRefresh(): Promise<TSession | null> {
    try {
      const response = await super.send('/auth/refresh', {
        method: 'POST',
        headers: { 'X-Requested-With': 'XMLHttpRequest' },
        skipRefresh: true,
      });
      if (!response.ok) {
        this.accessToken = null;
        return null;
      }
      const { data } = (await response.json()) as Envelope<TSession>;
      this.accessToken = data.accessToken;
      this.onSessionRefreshed?.(data);
      return data;
    } catch {
      return null; // offline: keep the current state; the next request tries again
    }
  }
}

/**
 * Check-in device client. Authenticates with the device token from pairing.
 * A 401 means an admin revoked the device: the token is dropped and the device must be paired again.
 */
export class KioskHttpClient extends HttpClient {
  onUnpaired: (() => void) | null = null;

  constructor(
    baseUrl: string,
    private readonly tokens: { get(): string | null; clear(): void },
    fetchImpl?: FetchLike,
  ) {
    super(baseUrl, fetchImpl);
  }

  protected override authHeaders(): Record<string, string> {
    const token = this.tokens.get();
    return token ? { Authorization: `Kiosk ${token}` } : {};
  }

  protected override async send(path: string, options: RequestOptions): Promise<Response> {
    const response = await super.send(path, options);
    if (response.status === 401) {
      this.tokens.clear();
      this.onUnpaired?.();
    }
    return response;
  }
}
__ATTENDANCE_EOF__

write 'apps/web/src/lib/time-zones.ts' <<'__ATTENDANCE_EOF__'
const FALLBACK = [
  'Africa/Lagos',
  'Africa/Accra',
  'Africa/Nairobi',
  'Africa/Johannesburg',
  'Africa/Cairo',
  'Europe/London',
  'UTC',
];

/** All IANA zones the browser knows, African zones first. */
export function timeZones(): string[] {
  const all = typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : FALLBACK;
  const african = all.filter((zone) => zone.startsWith('Africa/'));
  return [...african, ...all.filter((zone) => !zone.startsWith('Africa/'))];
}
__ATTENDANCE_EOF__

write 'apps/web/src/main.tsx' <<'__ATTENDANCE_EOF__'
import '@fontsource-variable/bricolage-grotesque';
import '@fontsource-variable/hanken-grotesk';
import './styles.css';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { createBrowserRouter } from 'react-router';
import { RouterProvider } from 'react-router/dom';
import { Providers } from './app/providers';
import { routes } from './app/router';

const root = document.getElementById('root');
if (!root) throw new Error('Missing #root element');

const router = createBrowserRouter(routes);

createRoot(root).render(
  <StrictMode>
    <Providers>
      <RouterProvider router={router} />
    </Providers>
  </StrictMode>,
);
__ATTENDANCE_EOF__

write 'apps/web/src/styles.css' <<'__ATTENDANCE_EOF__'
@import 'tailwindcss';

/*
 * Visual identity: the class register. Royal "register ink" blue on white, ruled lines where data lives,
 * red-pen red only for absences and destructive actions, tick-green for present.
 */
@theme {
  --font-sans: 'Hanken Grotesk Variable', ui-sans-serif, system-ui, sans-serif;
  --font-display: 'Bricolage Grotesque Variable', 'Hanken Grotesk Variable', ui-sans-serif, sans-serif;

  --color-ink: #1d2b6b;
  --color-ink-hover: #16225a;
  --color-ink-soft: #3a4785;
  --color-ink-wash: #e8ebf5;
  --color-text: #1f2747;
  --color-muted: #5b6480;
  --color-paper: #ffffff;
  --color-desk: #f3f5f9;
  --color-rule: #dde2ec;

  --color-present: #1e7a4c;
  --color-present-wash: #e3f3ea;
  --color-late: #9a5f0c;
  --color-late-wash: #fbf0dc;
  --color-absent: #c8312b;
  --color-absent-wash: #fbe6e4;
  --color-holiday: #5f6e8f;
  --color-holiday-wash: #eceff5;
}

@layer base {
  html {
    color: var(--color-text);
    background: var(--color-desk);
    font-family: var(--font-sans);
    -webkit-font-smoothing: antialiased;
    font-feature-settings: 'tnum' 0;
  }

  h1,
  h2,
  h3 {
    font-family: var(--font-display);
    color: var(--color-ink);
    letter-spacing: -0.015em;
    text-wrap: balance;
  }

  :focus-visible {
    outline: 2px solid var(--color-ink);
    outline-offset: 2px;
    border-radius: 4px;
  }

  dialog::backdrop {
    background: rgb(29 43 107 / 0.35);
  }

  @media (prefers-reduced-motion: reduce) {
    *,
    *::before,
    *::after {
      animation-duration: 0.01ms !important;
      transition-duration: 0.01ms !important;
    }
  }
}

@utility tabular {
  font-variant-numeric: tabular-nums;
}

/* Ruled paper: thin horizontal rules every row height, like a register page. */
@utility ruled {
  background-image: linear-gradient(to bottom, transparent calc(100% - 1px), var(--color-rule) calc(100% - 1px));
  background-size: 100% 2.75rem;
}

/* The kiosk's success tick draws itself once. */
@keyframes draw-tick {
  from {
    stroke-dashoffset: 1;
  }
  to {
    stroke-dashoffset: 0;
  }
}

@utility animate-draw {
  stroke-dasharray: 1;
  stroke-dashoffset: 1;
  animation: draw-tick 520ms cubic-bezier(0.65, 0, 0.35, 1) 120ms forwards;
}

@media print {
  body * {
    visibility: hidden;
  }
  .print-area,
  .print-area * {
    visibility: visible;
  }
  .print-area {
    position: absolute;
    inset: 0 auto auto 0;
  }
}
__ATTENDANCE_EOF__

write 'apps/web/src/test/fake-fetch.ts' <<'__ATTENDANCE_EOF__'
import { vi } from 'vitest';

type Handler = (init: RequestInit & { url: string }) => Response | Promise<Response>;

export const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });

/** Minimal fetch double: route by "METHOD /path" (query string ignored). Unmatched calls return 404. */
export function fakeFetch(routes: Record<string, Handler | Handler[]>) {
  const queues = new Map(
    Object.entries(routes).map(([key, value]) => [key, Array.isArray(value) ? [...value] : value]),
  );
  return vi.fn(async (input: string, init: RequestInit = {}) => {
    const path = new URL(input, 'http://test').pathname.replace(/^\/api\/v1/, '');
    const key = `${init.method ?? 'GET'} ${path}`;
    const entry = queues.get(key);
    const handler = Array.isArray(entry) ? (entry.length > 1 ? entry.shift() : entry[0]) : entry;
    if (!handler) return json(404, { error: { code: 'NOT_FOUND', message: `No fake route for ${key}` } });
    return handler({ ...init, url: input });
  });
}
__ATTENDANCE_EOF__

write 'apps/web/src/test/render.tsx' <<'__ATTENDANCE_EOF__'
import { QueryClientProvider } from '@tanstack/react-query';
import { render } from '@testing-library/react';
import { createMemoryRouter, RouterProvider, type RouteObject } from 'react-router';
import { createQueryClient } from '@/app/query-client';

/** Renders routes in memory with a fresh, non-retrying query client. */
export function renderRoutes(routes: RouteObject[], initialPath: string) {
  const queryClient = createQueryClient();
  queryClient.setDefaultOptions({ queries: { retry: false, staleTime: 0 }, mutations: { retry: false } });
  const router = createMemoryRouter(routes, { initialEntries: [initialPath] });
  const view = render(
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>,
  );
  return { ...view, router };
}
__ATTENDANCE_EOF__

write 'apps/web/src/test/setup.ts' <<'__ATTENDANCE_EOF__'
import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

afterEach(() => cleanup());

// jsdom does not implement modal dialogs yet.
if (typeof HTMLDialogElement !== 'undefined' && !HTMLDialogElement.prototype.showModal) {
  HTMLDialogElement.prototype.showModal = function showModal(this: HTMLDialogElement) {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close(this: HTMLDialogElement) {
    this.removeAttribute('open');
    this.dispatchEvent(new Event('close'));
  };
}
__ATTENDANCE_EOF__

write 'apps/web/tsconfig.json' <<'__ATTENDANCE_EOF__'
{
  "compilerOptions": {
    "target": "ES2023",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "types": ["vite/client"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "useDefineForClassFields": true,
    "skipLibCheck": true,
    "noEmit": true,
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["src"]
}
__ATTENDANCE_EOF__

write 'apps/web/tsconfig.node.json' <<'__ATTENDANCE_EOF__'
{
  "compilerOptions": {
    "target": "ES2023",
    "lib": ["ES2023"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "types": ["node"],
    "strict": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "skipLibCheck": true,
    "noEmit": true
  },
  "include": ["vite.config.ts", "vitest.config.ts"]
}
__ATTENDANCE_EOF__

write 'apps/web/vercel.json' <<'__ATTENDANCE_EOF__'
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "rewrites": [
    { "source": "/api/:path*", "destination": "https://YOUR-API-HOST.onrender.com/api/:path*" },
    { "source": "/((?!assets/).*)", "destination": "/index.html" }
  ],
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
        { "key": "X-Frame-Options", "value": "DENY" },
        { "key": "Permissions-Policy", "value": "camera=(self), microphone=(), geolocation=()" }
      ]
    },
    {
      "source": "/assets/(.*)",
      "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
    }
  ]
}
__ATTENDANCE_EOF__

write 'apps/web/vite.config.ts' <<'__ATTENDANCE_EOF__'
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';
import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  // In development the API is proxied, so the refresh cookie stays first-party (same origin as the app).
  const proxy = { '/api': { target: env.API_PROXY_TARGET || 'http://localhost:5000', changeOrigin: false } };

  return {
    plugins: [react(), tailwindcss()],
    resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
    server: { port: 5173, proxy },
    preview: { port: 4173, proxy },
    build: { sourcemap: true },
  };
});
__ATTENDANCE_EOF__

write 'apps/web/vitest.config.ts' <<'__ATTENDANCE_EOF__'
import { defineConfig, mergeConfig } from 'vitest/config';
import viteConfig from './vite.config';

export default defineConfig((env) =>
  mergeConfig(viteConfig(env), {
    test: {
      environment: 'jsdom',
      include: ['src/**/*.test.{ts,tsx}'],
      setupFiles: ['./src/test/setup.ts'],
      css: false,
      restoreMocks: true,
    },
  }),
);
__ATTENDANCE_EOF__

write 'package.json' <<'__ATTENDANCE_EOF__'
{
  "name": "attendance-platform",
  "version": "2.0.0",
  "private": true,
  "description": "Multi-tenant attendance platform for schools and companies",
  "type": "module",
  "workspaces": [
    "apps/*"
  ],
  "engines": {
    "node": ">=22.22"
  },
  "scripts": {
    "dev": "concurrently --kill-others-on-fail --names api,web --prefix-colors blue,magenta \"npm:dev:api\" \"npm:dev:web\"",
    "dev:api": "npm run dev --workspace=@attendance/api",
    "dev:web": "npm run dev --workspace=@attendance/web",
    "build": "npm run build --workspaces --if-present",
    "start": "npm run start --workspace=@attendance/api",
    "seed": "npm run seed --workspace=@attendance/api",
    "test": "npm run test --workspaces --if-present",
    "typecheck": "npm run typecheck --workspaces --if-present",
    "lint": "eslint .",
    "lint:fix": "eslint . --fix",
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  },
  "devDependencies": {
    "@eslint/js": "^10.0.1",
    "concurrently": "^10.0.5",
    "eslint": "^10.11.0",
    "eslint-plugin-react-hooks": "^7.1.1",
    "eslint-plugin-react-refresh": "^0.5.7",
    "globals": "^17.0.0",
    "prettier": "^3.9.9",
    "typescript": "~6.0.3",
    "typescript-eslint": "^8.71.0"
  },
  "overrides": {
    "exceljs": {
      "uuid": "^11.1.1"
    }
  }
}
__ATTENDANCE_EOF__

write 'package-lock.json' <<'__ATTENDANCE_EOF__'
{
  "name": "attendance-platform",
  "version": "2.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "attendance-platform",
      "version": "2.0.0",
      "workspaces": [
        "apps/*"
      ],
      "devDependencies": {
        "@eslint/js": "^10.0.1",
        "concurrently": "^10.0.5",
        "eslint": "^10.11.0",
        "eslint-plugin-react-hooks": "^7.1.1",
        "eslint-plugin-react-refresh": "^0.5.7",
        "globals": "^17.0.0",
        "prettier": "^3.9.9",
        "typescript": "~6.0.3",
        "typescript-eslint": "^8.71.0"
      },
      "engines": {
        "node": ">=22.22"
      }
    },
    "apps/api": {
      "name": "@attendance/api",
      "version": "2.0.0",
      "dependencies": {
        "bcryptjs": "^3.0.3",
        "cookie-parser": "^1.4.7",
        "cors": "^2.8.5",
        "exceljs": "^4.4.0",
        "express": "^5.2.1",
        "express-rate-limit": "^8.7.0",
        "helmet": "^8.3.0",
        "jsonwebtoken": "^9.0.3",
        "luxon": "^3.7.2",
        "mongoose": "^9.10.2",
        "pino": "^10.3.1",
        "pino-http": "^11.0.0",
        "zod": "^4.6.5"
      },
      "devDependencies": {
        "@types/cookie-parser": "^1.4.9",
        "@types/cors": "^2.8.19",
        "@types/express": "^5.0.6",
        "@types/jsonwebtoken": "^9.0.10",
        "@types/luxon": "^3.7.6",
        "@types/node": "^22.19.0",
        "@types/supertest": "^7.2.1",
        "mongodb-memory-server": "^11.3.0",
        "pino-pretty": "^13.1.3",
        "supertest": "^7.3.0",
        "tsx": "^4.23.15",
        "vitest": "^5.0.2"
      },
      "engines": {
        "node": ">=22.12"
      }
    },
    "apps/web": {
      "name": "@attendance/web",
      "version": "2.0.0",
      "dependencies": {
        "@fontsource-variable/bricolage-grotesque": "^5.3.0",
        "@fontsource-variable/hanken-grotesk": "^5.3.0",
        "@hookform/resolvers": "^5.9.1",
        "@tanstack/react-query": "^5.104.1",
        "barcode-detector": "^3.2.2",
        "clsx": "^2.1.1",
        "lucide-react": "^1.50.0",
        "papaparse": "^5.7.0",
        "qrcode": "^1.5.4",
        "react": "^19.3.0",
        "react-dom": "^19.3.0",
        "react-hook-form": "^7.89.0",
        "react-router": "^8.4.0",
        "sonner": "^2.0.8",
        "tailwind-merge": "^3.7.0",
        "zod": "^4.6.5",
        "zxing-wasm": "3.1.3"
      },
      "devDependencies": {
        "@tailwindcss/vite": "^4.3.3",
        "@testing-library/jest-dom": "^7.0.1",
        "@testing-library/react": "^16.3.3",
        "@testing-library/user-event": "^14.6.7",
        "@types/papaparse": "^5.5.2",
        "@types/qrcode": "^1.5.6",
        "@types/react": "^19.3.0",
        "@types/react-dom": "^19.3.0",
        "@vitejs/plugin-react": "^6.1.1",
        "jsdom": "^30.1.1",
        "tailwindcss": "^4.3.3",
        "vite": "^8.3.2",
        "vitest": "^5.0.2"
      }
    },
    "apps/web/node_modules/@hookform/resolvers": {
      "version": "5.9.1",
      "resolved": "https://registry.npmjs.org/@hookform/resolvers/-/resolvers-5.9.1.tgz",
      "integrity": "sha512-7b7vsbraJxKgjVSA1Nur9tLwj539WGJUBLA7QNvXnFoT2pM5Z7G+6rlukk4B2/QrTZy6huRtH6wKeESPKuIr6w==",
      "license": "MIT",
      "dependencies": {
        "@standard-schema/utils": "^0.3.0"
      },
      "peerDependencies": {
        "@sinclair/typebox": ">=0.25.24",
        "@standard-schema/spec": "^1.0.0",
        "@typeschema/main": ">=0.13.7",
        "@vinejs/vine": "^2.0.0 || ^3.0.0 || ^4.0.0",
        "ajv": "^8.12.0",
        "ajv-errors": "^3.0.0",
        "ajv-formats": "^2.1.1",
        "arktype": "^2.0.0",
        "ata-validator": "^1.2.0",
        "class-transformer": ">=0.4.0",
        "class-validator": ">=0.12.0",
        "computed-types": "^1.0.0",
        "effect": "^3.10.3",
        "fluentvalidation-ts": "^3.0.0",
        "fp-ts": "^2.7.0",
        "io-ts": "^2.0.0",
        "joi": "^17.0.0 || ^18.0.0",
        "nope-validator": ">=0.12.0",
        "react-hook-form": "^7.55.0",
        "superstruct": ">=0.12.0",
        "typanion": "^3.3.2",
        "valibot": ">=0.31.0 || ^1.0.0-beta.4 || ^1.0.0-rc",
        "vest": ">=6.0.0",
        "yup": "^1.0.0",
        "zod": "^3.25.0 || ^4.0.0"
      },
      "peerDependenciesMeta": {
        "@sinclair/typebox": {
          "optional": true
        },
        "@standard-schema/spec": {
          "optional": true
        },
        "@typeschema/main": {
          "optional": true
        },
        "@vinejs/vine": {
          "optional": true
        },
        "ajv": {
          "optional": true
        },
        "ajv-errors": {
          "optional": true
        },
        "ajv-formats": {
          "optional": true
        },
        "arktype": {
          "optional": true
        },
        "ata-validator": {
          "optional": true
        },
        "class-transformer": {
          "optional": true
        },
        "class-validator": {
          "optional": true
        },
        "computed-types": {
          "optional": true
        },
        "effect": {
          "optional": true
        },
        "fluentvalidation-ts": {
          "optional": true
        },
        "fp-ts": {
          "optional": true
        },
        "io-ts": {
          "optional": true
        },
        "joi": {
          "optional": true
        },
        "nope-validator": {
          "optional": true
        },
        "superstruct": {
          "optional": true
        },
        "typanion": {
          "optional": true
        },
        "valibot": {
          "optional": true
        },
        "vest": {
          "optional": true
        },
        "yup": {
          "optional": true
        },
        "zod": {
          "optional": true
        }
      }
    },
    "apps/web/node_modules/@vitejs/plugin-react": {
      "version": "6.1.1",
      "resolved": "https://registry.npmjs.org/@vitejs/plugin-react/-/plugin-react-6.1.1.tgz",
      "integrity": "sha512-yxLaQV9gkhS8ezJqCM6+ndU7mDY6gqAg75NQ+0IjwEI8IYOmQCgkRwHKVSfWXW076DsqMo0Dk+0FK1U+M5RgFw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@rolldown/pluginutils": "^1.0.1"
      },
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      },
      "peerDependencies": {
        "@rolldown/plugin-babel": "^0.1.7 || ^0.2.0",
        "babel-plugin-react-compiler": "^1.0.0",
        "oxc-transform-react": "^0.145.0",
        "vite": "^8.0.0"
      },
      "peerDependenciesMeta": {
        "@rolldown/plugin-babel": {
          "optional": true
        },
        "babel-plugin-react-compiler": {
          "optional": true
        },
        "oxc-transform-react": {
          "optional": true
        }
      }
    },
    "apps/web/node_modules/ajv": {
      "version": "8.20.0",
      "resolved": "https://registry.npmjs.org/ajv/-/ajv-8.20.0.tgz",
      "integrity": "sha512-Thbli+OlOj+iMPYFBVBfJ3OmCAnaSyNn4M1vz9T6Gka5Jt9ba/HIR56joy65tY6kx/FCF5VXNB819Y7/GUrBGA==",
      "license": "MIT",
      "optional": true,
      "peer": true,
      "dependencies": {
        "fast-deep-equal": "^3.1.3",
        "fast-uri": "^3.0.1",
        "json-schema-traverse": "^1.0.0",
        "require-from-string": "^2.0.2"
      },
      "funding": {
        "type": "github",
        "url": "https://github.com/sponsors/epoberezkin"
      }
    },
    "apps/web/node_modules/json-schema-traverse": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/json-schema-traverse/-/json-schema-traverse-1.0.0.tgz",
      "integrity": "sha512-NM8/P9n3XjXhIZn1lLhkFaACTOURQXjWhV4BA/RnOv8xvgqtqpAX9IO4mRQxSx1Rlo4tqzeqb0sOlruaOy3dug==",
      "license": "MIT",
      "optional": true,
      "peer": true
    },
    "apps/web/node_modules/vite": {
      "version": "8.3.2",
      "resolved": "https://registry.npmjs.org/vite/-/vite-8.3.2.tgz",
      "integrity": "sha512-SQr1x6W5vVSbROg7vsyXIaxK9b0G7zsT68acdWWRmnBUsgDieLCRG+Rep9WdZgcposvv/GSnr4GUUBqB3vXq6w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "lightningcss": "^1.33.0",
        "picomatch": "^4.0.7",
        "postcss": "^8.5.28",
        "rolldown": "~1.2.11",
        "tinyglobby": "^0.2.17"
      },
      "bin": {
        "vite": "bin/vite.js"
      },
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      },
      "funding": {
        "url": "https://github.com/vitejs/vite?sponsor=1"
      },
      "optionalDependencies": {
        "fsevents": "~2.3.3"
      },
      "peerDependencies": {
        "@types/node": "^20.19.0 || >=22.12.0",
        "@vitejs/devtools": "^0.7.1",
        "esbuild": "^0.27.0 || ^0.28.0",
        "jiti": ">=1.21.0",
        "less": "^4.0.0",
        "sass": "^1.70.0",
        "sass-embedded": "^1.70.0",
        "stylus": ">=0.54.8",
        "sugarss": "^5.0.0",
        "terser": "^5.16.0",
        "tsx": "^4.8.1",
        "yaml": "^2.4.2"
      },
      "peerDependenciesMeta": {
        "@types/node": {
          "optional": true
        },
        "@vitejs/devtools": {
          "optional": true
        },
        "esbuild": {
          "optional": true
        },
        "jiti": {
          "optional": true
        },
        "less": {
          "optional": true
        },
        "sass": {
          "optional": true
        },
        "sass-embedded": {
          "optional": true
        },
        "stylus": {
          "optional": true
        },
        "sugarss": {
          "optional": true
        },
        "terser": {
          "optional": true
        },
        "tsx": {
          "optional": true
        },
        "yaml": {
          "optional": true
        }
      }
    },
    "node_modules/@adobe/css-tools": {
      "version": "4.5.0",
      "resolved": "https://registry.npmjs.org/@adobe/css-tools/-/css-tools-4.5.0.tgz",
      "integrity": "sha512-6OzddxPio9UiWTCemp4N8cYLV2ZN1ncRnV1cVGtve7dhPOtRkleRyx32GQCYSwDYgaHU3USMm84tNsvKzRCa1Q==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@asamuzakjp/css-color": {
      "version": "7.1.2",
      "resolved": "https://registry.npmjs.org/@asamuzakjp/css-color/-/css-color-7.1.2.tgz",
      "integrity": "sha512-99DHAnXDB5z6EEK+9GMpVI7Mw4oxj97dY5bpOzMnjADQWxI8rN6TvTduuFLUhUMlS7/CfVZ06tcZsus6cltnNw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@csstools/css-calc": "^3.4.1",
        "@csstools/css-color-parser": "^4.2.4",
        "@csstools/css-parser-algorithms": "^4.0.1",
        "@csstools/css-tokenizer": "^4.0.2",
        "lru-cache": "^11.5.3"
      },
      "engines": {
        "node": "^22.22.2 || ^24.15.0 || >=26.0.0"
      }
    },
    "node_modules/@asamuzakjp/css-color/node_modules/lru-cache": {
      "version": "11.5.3",
      "resolved": "https://registry.npmjs.org/lru-cache/-/lru-cache-11.5.3.tgz",
      "integrity": "sha512-U4N8FgzmWxc8k1VH8Kr6lQg18U7Fjvby6wXHVRX/ZZ7IwWbRMgrRbP0Wrb5q5NVinryp4SQampHKdvtecItxUg==",
      "dev": true,
      "license": "BlueOak-1.0.0",
      "engines": {
        "node": "20 || >=22"
      }
    },
    "node_modules/@asamuzakjp/dom-selector": {
      "version": "9.2.3",
      "resolved": "https://registry.npmjs.org/@asamuzakjp/dom-selector/-/dom-selector-9.2.3.tgz",
      "integrity": "sha512-MDKmPBa6CfNN1zAJroTl7Uc+nBbcNtfE/F24iROfZAtcLffEeY3IbHR8XeHH5dJBspMYTpAsjEYmnp3tAmoVxw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "bidi-js": "^1.1.0",
        "css-tree": "^3.2.1",
        "is-potential-custom-element-name": "^1.0.1",
        "lru-cache": "^11.5.3"
      },
      "engines": {
        "node": "^22.22.2 || ^24.15.0 || >=26.0.0"
      }
    },
    "node_modules/@asamuzakjp/dom-selector/node_modules/lru-cache": {
      "version": "11.5.3",
      "resolved": "https://registry.npmjs.org/lru-cache/-/lru-cache-11.5.3.tgz",
      "integrity": "sha512-U4N8FgzmWxc8k1VH8Kr6lQg18U7Fjvby6wXHVRX/ZZ7IwWbRMgrRbP0Wrb5q5NVinryp4SQampHKdvtecItxUg==",
      "dev": true,
      "license": "BlueOak-1.0.0",
      "engines": {
        "node": "20 || >=22"
      }
    },
    "node_modules/@attendance/api": {
      "resolved": "apps/api",
      "link": true
    },
    "node_modules/@attendance/web": {
      "resolved": "apps/web",
      "link": true
    },
    "node_modules/@babel/code-frame": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/code-frame/-/code-frame-7.29.7.tgz",
      "integrity": "sha512-Aup7aUOfpbAUg2ROOJN6Iw5f9DMBlzu0mIkm/malLQFN/YQgO48wCj0Kxa3sEHJvPVFg7siR+qRInwXd2qhQKw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/helper-validator-identifier": "^7.29.7",
        "js-tokens": "^4.0.0",
        "picocolors": "^1.1.1"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/compat-data": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/compat-data/-/compat-data-7.29.7.tgz",
      "integrity": "sha512-locTkQyKvwIEgBzVrn8693ebc97F2U8ZHjbXwDXJ5Fn2TCpNwTlKcaKLkdHop5c/icOFE7qt7Q9JC5hnKNa6Gg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/core": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/core/-/core-7.29.7.tgz",
      "integrity": "sha512-RgHBCvtjbOK2gXSNBNIkNoEc9qoVEtau3hj8gEqKQuL3HZAibKarWFEI3Lfm6EYKkLalOh8eSrj9b+ch9H/VBA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/code-frame": "^7.29.7",
        "@babel/generator": "^7.29.7",
        "@babel/helper-compilation-targets": "^7.29.7",
        "@babel/helper-module-transforms": "^7.29.7",
        "@babel/helpers": "^7.29.7",
        "@babel/parser": "^7.29.7",
        "@babel/template": "^7.29.7",
        "@babel/traverse": "^7.29.7",
        "@babel/types": "^7.29.7",
        "@jridgewell/remapping": "^2.3.5",
        "convert-source-map": "^2.0.0",
        "debug": "^4.1.0",
        "gensync": "^1.0.0-beta.2",
        "json5": "^2.2.3",
        "semver": "^6.3.1"
      },
      "engines": {
        "node": ">=6.9.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/babel"
      }
    },
    "node_modules/@babel/core/node_modules/semver": {
      "version": "6.3.1",
      "resolved": "https://registry.npmjs.org/semver/-/semver-6.3.1.tgz",
      "integrity": "sha512-BR7VvDCVHO+q2xBEWskxS6DJE1qRnb7DxzUrogb71CWoSficBxYsiAGd+Kl0mmq/MprG9yArRkyrQxTO6XjMzA==",
      "dev": true,
      "license": "ISC",
      "bin": {
        "semver": "bin/semver.js"
      }
    },
    "node_modules/@babel/generator": {
      "version": "7.29.8",
      "resolved": "https://registry.npmjs.org/@babel/generator/-/generator-7.29.8.tgz",
      "integrity": "sha512-gZbepsdh3WDtgZKWL+vTPh71LSBrm/Y4/QDZBVCcYfmeTEEuoOYwlSy+G1StfJg+/Zy550u/3TATbm7qDbbMtg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/parser": "^7.29.8",
        "@babel/types": "^7.29.8",
        "@jridgewell/gen-mapping": "^0.3.12",
        "@jridgewell/trace-mapping": "^0.3.28",
        "jsesc": "^3.0.2"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-compilation-targets": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-compilation-targets/-/helper-compilation-targets-7.29.7.tgz",
      "integrity": "sha512-wem6WaBj4NaVYVdNhLPPVacES6ZJ+KBBfSkTMD3YZxbP3rm3Di85tJU5ljaUNhaOynt+Aj0xruhYuzQBt8n71g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/compat-data": "^7.29.7",
        "@babel/helper-validator-option": "^7.29.7",
        "browserslist": "^4.24.0",
        "lru-cache": "^5.1.1",
        "semver": "^6.3.1"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-compilation-targets/node_modules/semver": {
      "version": "6.3.1",
      "resolved": "https://registry.npmjs.org/semver/-/semver-6.3.1.tgz",
      "integrity": "sha512-BR7VvDCVHO+q2xBEWskxS6DJE1qRnb7DxzUrogb71CWoSficBxYsiAGd+Kl0mmq/MprG9yArRkyrQxTO6XjMzA==",
      "dev": true,
      "license": "ISC",
      "bin": {
        "semver": "bin/semver.js"
      }
    },
    "node_modules/@babel/helper-globals": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-globals/-/helper-globals-7.29.7.tgz",
      "integrity": "sha512-3nQVUAtvkKH9zahfWgw96Jc/uFOmjACE1kQz82E2lqWmHBgjzbNlsC22nuQTfahmWeQtTq5nQ/4Nnd2A1wj4zA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-module-imports": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-module-imports/-/helper-module-imports-7.29.7.tgz",
      "integrity": "sha512-ejHwrQQYcm9xnTivShn2IDOlIzInN34AXskvq9QicvCtEzq1Vzclu/tKF8Jq1Cg8JG2GL6/EmjgsCT7lXepE3g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/traverse": "^7.29.7",
        "@babel/types": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-module-transforms": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-module-transforms/-/helper-module-transforms-7.29.7.tgz",
      "integrity": "sha512-UPUVSyXbOh627KiCIGQSgwWzGeBKLkaJ9PJEdrngIwMSzxLR4jS4+f1f1jb7VzBbg8nFLaYotvVPFCTqdrmTAg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/helper-module-imports": "^7.29.7",
        "@babel/helper-validator-identifier": "^7.29.7",
        "@babel/traverse": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      },
      "peerDependencies": {
        "@babel/core": "^7.0.0"
      }
    },
    "node_modules/@babel/helper-string-parser": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-string-parser/-/helper-string-parser-7.29.7.tgz",
      "integrity": "sha512-Pb5ijPrZ89GDH8223L4UP8i6QApWxs04RbPQJTeWDV0/keR2E36MeKnyr6LYmUUvqRRI+Iv87SuF1W6ErINzYw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-validator-identifier": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-validator-identifier/-/helper-validator-identifier-7.29.7.tgz",
      "integrity": "sha512-qehxGkRj55h/ff8EMaJ+cYhyaKlHIxqYDn682wQD7RNp9UujOQsHog2uS0r2vzr4pW+sXf90NeeayjcNaX3fFg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helper-validator-option": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helper-validator-option/-/helper-validator-option-7.29.7.tgz",
      "integrity": "sha512-N9ZErrD+yW5geCDtBqnOoxmR8+tNKiGuxKlDpuJxfsqpa2dFcexaziGAE/qoHLiDDreVNMupxGmSoNlyvsA3gw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/helpers": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/helpers/-/helpers-7.29.7.tgz",
      "integrity": "sha512-1k2lAGRMfHTcwuNYcCNUmaUffmQv8KWMfh2iJUUeRlwlwH4FdNG7mfPI10NPfLHJFThE4Tyr4mv7kTNZOiPuBg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/template": "^7.29.7",
        "@babel/types": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/parser": {
      "version": "7.29.9",
      "resolved": "https://registry.npmjs.org/@babel/parser/-/parser-7.29.9.tgz",
      "integrity": "sha512-CjXrNHTnvqBVqHgdBysY3vk2T8tpJHb5/RMeHJBTyVa9xgugCB0CJTx/3oO8RV2QRQP391RWpB7D6hLjm8V9uA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/types": "^7.29.8"
      },
      "bin": {
        "parser": "bin/babel-parser.js"
      },
      "engines": {
        "node": ">=6.0.0"
      }
    },
    "node_modules/@babel/runtime": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/runtime/-/runtime-7.29.7.tgz",
      "integrity": "sha512-Nq8OhGWiZIZGV6hLHoyAKLLcJihP/xFeBMGJoUrxTX2psI8dCifzLhZISFb+VWS3wFMRDmCGw5R+dOySCqPLhw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/template": {
      "version": "7.29.7",
      "resolved": "https://registry.npmjs.org/@babel/template/-/template-7.29.7.tgz",
      "integrity": "sha512-puq+Gf35oI24FeN11LkoUQFqv9uwNeWpxXZi/Ji3rRIoKAzKnxRaZ+Gkj0vKS9ZCiTESfng1N9LyOyXvo+m+Gg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/code-frame": "^7.29.7",
        "@babel/parser": "^7.29.7",
        "@babel/types": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/traverse": {
      "version": "7.29.8",
      "resolved": "https://registry.npmjs.org/@babel/traverse/-/traverse-7.29.8.tgz",
      "integrity": "sha512-I5z7H3bf/41ktsNVLtpN0wAa336HkqIHQ5BuPLEhTkt1jVSyZpeNKIzTgEWmlxjdg81R0IgUCcaE+Ok3NvrfZg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/code-frame": "^7.29.7",
        "@babel/generator": "^7.29.8",
        "@babel/helper-globals": "^7.29.7",
        "@babel/parser": "^7.29.8",
        "@babel/template": "^7.29.7",
        "@babel/types": "^7.29.8",
        "debug": "^4.3.1"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@babel/types": {
      "version": "7.29.8",
      "resolved": "https://registry.npmjs.org/@babel/types/-/types-7.29.8.tgz",
      "integrity": "sha512-Vj1jF3cPfxg7OAfoI7QnVKLoILlm2JF9pnVHrX8qx7AHMiYWT+NDAA7jChlNgRS4WTLc/fD1lXLmPixluj+3Gg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/helper-string-parser": "^7.29.7",
        "@babel/helper-validator-identifier": "^7.29.7"
      },
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/@bramus/specificity": {
      "version": "2.4.2",
      "resolved": "https://registry.npmjs.org/@bramus/specificity/-/specificity-2.4.2.tgz",
      "integrity": "sha512-ctxtJ/eA+t+6q2++vj5j7FYX3nRu311q1wfYH3xjlLOsczhlhxAg2FWNUXhpGvAw3BWo1xBcvOV6/YLc2r5FJw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "css-tree": "^3.0.0"
      },
      "bin": {
        "specificity": "bin/cli.js"
      }
    },
    "node_modules/@cacheable/memory": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/@cacheable/memory/-/memory-2.2.0.tgz",
      "integrity": "sha512-CTLKqLItRCEixEAewD3/j9DB3/o96gpTPD4eJ1v+DGOlxZRZncRQkGYqqnAGCscYd6RNeXfGeiuCphsPtqyIfQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@cacheable/utils": "^2.5.0",
        "@keyv/bigmap": "^1.3.1",
        "hookified": "^1.15.1",
        "keyv": "^5.6.0"
      }
    },
    "node_modules/@cacheable/utils": {
      "version": "2.5.0",
      "resolved": "https://registry.npmjs.org/@cacheable/utils/-/utils-2.5.0.tgz",
      "integrity": "sha512-buipgOVDkkPXNR5+xBpDw7Zk2n1EvU7qBJCNUcL7rhQ//kfpOXPAvQ511Os0vpLYJ1pZnvudNytkQt2hst3wqA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "hashery": "^1.5.1",
        "keyv": "^5.6.0"
      }
    },
    "node_modules/@csstools/color-helpers": {
      "version": "6.1.2",
      "resolved": "https://registry.npmjs.org/@csstools/color-helpers/-/color-helpers-6.1.2.tgz",
      "integrity": "sha512-grhRy3OKmniaAEKXMjua5z/EODX0MSqBGjunw8+j/3HQjOnahs2AGhvEOIYVUWcU6ScApbhLhVrQTX8XqrMrow==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/csstools"
        },
        {
          "type": "opencollective",
          "url": "https://opencollective.com/csstools"
        }
      ],
      "license": "MIT-0",
      "engines": {
        "node": ">=20.19.0"
      }
    },
    "node_modules/@csstools/css-calc": {
      "version": "3.4.2",
      "resolved": "https://registry.npmjs.org/@csstools/css-calc/-/css-calc-3.4.2.tgz",
      "integrity": "sha512-tL6LRF844sHjAKO7jt2w+uHo8Tocqpb9+KPUvIQETpR4RU87IaUzDuOV0QyzuQ37jmzFgwPHLLtLu/PDuH5qgg==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/csstools"
        },
        {
          "type": "opencollective",
          "url": "https://opencollective.com/csstools"
        }
      ],
      "license": "MIT",
      "engines": {
        "node": ">=20.19.0"
      },
      "peerDependencies": {
        "@csstools/css-parser-algorithms": "^4.0.2",
        "@csstools/css-tokenizer": "^4.0.2"
      }
    },
    "node_modules/@csstools/css-color-parser": {
      "version": "4.2.5",
      "resolved": "https://registry.npmjs.org/@csstools/css-color-parser/-/css-color-parser-4.2.5.tgz",
      "integrity": "sha512-Qqbp5pjbMwoaErP2t5qne5QDVDr3G5243oNW8ev5zfyyoqbzrQKbYDpKP/cuo3xBkzwqZqpP/rChrJhBdyTX7g==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/csstools"
        },
        {
          "type": "opencollective",
          "url": "https://opencollective.com/csstools"
        }
      ],
      "license": "MIT",
      "dependencies": {
        "@csstools/color-helpers": "^6.1.2",
        "@csstools/css-calc": "^3.4.2"
      },
      "engines": {
        "node": ">=20.19.0"
      },
      "peerDependencies": {
        "@csstools/css-parser-algorithms": "^4.0.2",
        "@csstools/css-tokenizer": "^4.0.2"
      }
    },
    "node_modules/@csstools/css-parser-algorithms": {
      "version": "4.0.2",
      "resolved": "https://registry.npmjs.org/@csstools/css-parser-algorithms/-/css-parser-algorithms-4.0.2.tgz",
      "integrity": "sha512-40cSKyMvK+tq4qz6Awrlye2WGuOKt3FwPgtGg6KTfbHOWNw+Rk1rzbAtZnZ6IBhsY491HLRnDXwoyBAijmmILA==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/csstools"
        },
        {
          "type": "opencollective",
          "url": "https://opencollective.com/csstools"
        }
      ],
      "license": "MIT",
      "engines": {
        "node": ">=20.19.0"
      },
      "peerDependencies": {
        "@csstools/css-tokenizer": "^4.0.2"
      }
    },
    "node_modules/@csstools/css-syntax-patches-for-csstree": {
      "version": "1.1.15",
      "resolved": "https://registry.npmjs.org/@csstools/css-syntax-patches-for-csstree/-/css-syntax-patches-for-csstree-1.1.15.tgz",
      "integrity": "sha512-J0u7HkVl2nzSlhsiTOp4AmwcUQ3D+mGEEKfBy/7To5/y7F2OHwyLrXfrhR0SMgr4p5Lo+eaMVSeai24zUcBIxA==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/csstools"
        },
        {
          "type": "opencollective",
          "url": "https://opencollective.com/csstools"
        }
      ],
      "license": "MIT-0",
      "peerDependencies": {
        "css-tree": "^3.2.1"
      },
      "peerDependenciesMeta": {
        "css-tree": {
          "optional": true
        }
      }
    },
    "node_modules/@csstools/css-tokenizer": {
      "version": "4.0.2",
      "resolved": "https://registry.npmjs.org/@csstools/css-tokenizer/-/css-tokenizer-4.0.2.tgz",
      "integrity": "sha512-OoKoR0f76dCY666JlcbhmVTs2drYj1GUXZTYTcbUgJjh9Nv41aFfZ21bPQTERm5+L5cBDo466NltB2lplS5GBw==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/csstools"
        },
        {
          "type": "opencollective",
          "url": "https://opencollective.com/csstools"
        }
      ],
      "license": "MIT",
      "engines": {
        "node": ">=20.19.0"
      }
    },
    "node_modules/@esbuild/aix-ppc64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/aix-ppc64/-/aix-ppc64-0.28.2.tgz",
      "integrity": "sha512-XExcO+dvLKvVtNTibSTBej1NCAbaGhWn9Ww1ZPx80qsahhPFe/8jgWP0IchNe0F3HwkU7n8ejhH8bjonqht8mQ==",
      "cpu": [
        "ppc64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "aix"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/android-arm": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/android-arm/-/android-arm-0.28.2.tgz",
      "integrity": "sha512-kXXoiPVVGQcnIYGOeaovwOURpniDBpSq4A03qkQ+BMQqtGG6HYap3xne9C1O1yo4TR3qxlCX5IqqmX6fFo2Lqg==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/android-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/android-arm64/-/android-arm64-0.28.2.tgz",
      "integrity": "sha512-5YfKeeI8qWfBZIX+u2xZC3Zlb3Os/gLS2sbEKM+I4ZOcsWmHS2WLysCcQZDAFRslDUU5Oiq44gf6PYN1vGwG5A==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/android-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/android-x64/-/android-x64-0.28.2.tgz",
      "integrity": "sha512-O387ite7SzUyCcy3JQX4P4bLtEA7bLLkx+esve5JHnyYfNTxcVpXZo9jhdB0lTKN44gztELTdU7nS8Nr16Fs1Q==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/darwin-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/darwin-arm64/-/darwin-arm64-0.28.2.tgz",
      "integrity": "sha512-n4KqkOQrraxHJcgjM1RvwbigfQKIKJVpM7xp+KsxiyUSrRdIXnt73VhrPAx0fV44hgfmIVKjxMN9J1t5jySVkw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/darwin-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/darwin-x64/-/darwin-x64-0.28.2.tgz",
      "integrity": "sha512-uq6suIWYP37qzGddBKPw5QEQPi6HiLGsO7UmkpfyaYNQ3D+rN6w6WfwH+nuqcGXWvawGwxOEroO4YGnFh95azw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/freebsd-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/freebsd-arm64/-/freebsd-arm64-0.28.2.tgz",
      "integrity": "sha512-n+I0BTSRIoy+d6RPKnEVwql5UwBJolytvY4mAOIEJorKlqgPII8ix6slVVrfZ5Tnj7glIZvloylbB/EJPMWEXw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/freebsd-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/freebsd-x64/-/freebsd-x64-0.28.2.tgz",
      "integrity": "sha512-78XJTJkvPs0kz2w61301PJjXl4g7q3JqiYMZ/M/yVI73EHBrCRTgkhu9oqG7vPqq+a/yadEW8aD+agKlk5xrmg==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-arm": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-arm/-/linux-arm-0.28.2.tgz",
      "integrity": "sha512-XlDnu2q5yoqems+xay6wSAcg9DDD7K9RLKZEBOMZm3ckNpJBvOX20tSfby8KfrrhINDyv9V2YVZKY/SpoGJI8w==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-arm64/-/linux-arm64-0.28.2.tgz",
      "integrity": "sha512-pW4AC0P3it8c7do9MVM4p51FzHzdM/TZrerurgRcHJ2WTa1VQ1CIq18xncfpBJw4ojkiZZrKW2yIBWBP92j6Ug==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-ia32": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-ia32/-/linux-ia32-0.28.2.tgz",
      "integrity": "sha512-CYbnj78HsIeA+DhgUKgFCfvNsTHFhMMrinUrMZpDXJXKN8T3XViTZ/+wtHeVxEWY8ewSzTFN+nRmSwO2tZaLUQ==",
      "cpu": [
        "ia32"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-loong64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-loong64/-/linux-loong64-0.28.2.tgz",
      "integrity": "sha512-buwkd8nsph4R+ajRvw0qM5Hja/TXQow3ptzWO2EbG/cqcIkHloRrdlBtQlshyYGTNFvfkfJ5tpPLVkY4DtsPfQ==",
      "cpu": [
        "loong64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-mips64el": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-mips64el/-/linux-mips64el-0.28.2.tgz",
      "integrity": "sha512-ZVykbDyk7519VwiNb9Lcj9m8XM6v5V9uKPvrEMkkEedVewf+0itkhahp4HDpgERXhwLRpWFypsGbG/J8s0QjJA==",
      "cpu": [
        "mips64el"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-ppc64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-ppc64/-/linux-ppc64-0.28.2.tgz",
      "integrity": "sha512-CAXl+Dtd9UUuJd8pKKdwh6MLm3MUMiqMPmhZ3tTSXPqfyQ3vDl6R5hZdZ/kYojK4ofXtdfSv1tFq8XzWx3heNQ==",
      "cpu": [
        "ppc64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-riscv64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-riscv64/-/linux-riscv64-0.28.2.tgz",
      "integrity": "sha512-GeXCej4IQtU1B+QlDV8W/RRvbzI3O/Stss+/bCXv4lZls5WGRtu2a+3JkA3i4qIUlMXpcHebWpF8AkJhATowuA==",
      "cpu": [
        "riscv64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-s390x": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-s390x/-/linux-s390x-0.28.2.tgz",
      "integrity": "sha512-3H1weTYZPxt/WOhByszQZybS9w5lKzUn1FDMsgEChbHWQwHYQQRfBxgCcZvPhjHfKyJjIievvMmEUawJrdY9Dg==",
      "cpu": [
        "s390x"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/linux-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-x64/-/linux-x64-0.28.2.tgz",
      "integrity": "sha512-4xTZr1FUmSoQW4XIWmit3tzQrUTZM+N3P0XV8xROKYF50XfI7xeO90+1bZvNwxIufQ9hDQVRJH5YhgPVF8A/HQ==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/netbsd-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/netbsd-arm64/-/netbsd-arm64-0.28.2.tgz",
      "integrity": "sha512-sSATRjPeDBg3pdgHoQfoYBob11Kk1FGa9lui5RIHZCoCkJa9QKlvl3/vKz2usCmYYjs7ymJR/2Nnsqe+Hjt5nw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "netbsd"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/netbsd-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/netbsd-x64/-/netbsd-x64-0.28.2.tgz",
      "integrity": "sha512-lqnzCV+mM0gIADaKihiCg6ifgfU2L3h5E33rNQBN1Y4MaVGnzryzmvvf7UHxprpQdE8hpqLolJ9Rl+SkIRDpyw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "netbsd"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/openbsd-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/openbsd-arm64/-/openbsd-arm64-0.28.2.tgz",
      "integrity": "sha512-AL2qJILH7lNjrDmCQDvdxMfAUIv8KMNZOvrwAQ8i8//ntL9FflhOyMJ8OZSMBb8/AWXe3/5v5S20y3zCoZWKoQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "openbsd"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/openbsd-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/openbsd-x64/-/openbsd-x64-0.28.2.tgz",
      "integrity": "sha512-QtiuPytchRyC4rwUKhexJdQKvDuZ6hWloi3igqPQNUJCS1/v9EiO3UTOXR6A3FoMo4fnAKbWJdqaIwhOzh8qEw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "openbsd"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/openharmony-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/openharmony-arm64/-/openharmony-arm64-0.28.2.tgz",
      "integrity": "sha512-WkhYDmpTjLvGlScA1rwjRUmhl4k8oXR3cIbtqWmELgU/dFeHHlEllxDvdWcNJV9rbzCexB5vz8gtNewWLgCT7Q==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "openharmony"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/sunos-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/sunos-x64/-/sunos-x64-0.28.2.tgz",
      "integrity": "sha512-GPMSkTOtMnv2U2F8gxe4Io6qmVs+YKyp832Etqqxr0hFngmXQ3rzwytelm3GIn7T4VviRUlf3sOgBOiTdvaf7g==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "sunos"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/win32-arm64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/win32-arm64/-/win32-arm64-0.28.2.tgz",
      "integrity": "sha512-PIhhEkE9uPBleRBrQEJpUn7MBnibZzbGzYWPmY3x+YoVg/95zbjB4CxPPOQ8l5tYYM4mMaCthF8/1DIfBQQyWQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/win32-ia32": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/win32-ia32/-/win32-ia32-0.28.2.tgz",
      "integrity": "sha512-YmJbfTlvU7Sdn9BB+4PRES4oB6pxgS37MAONj+hBr/cpXS1aBPKXxNnDbu+QCWPj0o9dgyxeq79g6c5P8KeuYA==",
      "cpu": [
        "ia32"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@esbuild/win32-x64": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/@esbuild/win32-x64/-/win32-x64-0.28.2.tgz",
      "integrity": "sha512-5ebpxr3nWMzrL/rnUI755Jkuee0bHL/Gq0WTF9lvcpv73wAp5eu8MfBUgWK9bhWvZjj7yX8etf/8tI8Ney695g==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "peer": true,
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@eslint-community/eslint-utils": {
      "version": "4.10.1",
      "resolved": "https://registry.npmjs.org/@eslint-community/eslint-utils/-/eslint-utils-4.10.1.tgz",
      "integrity": "sha512-cuadcxVFE8sDK6iWJbs8Sn0av2Nrh2QSGQhVlBW9AaAHqHwjWsZHT8LJ4hFGPh7ASBV2deFdM7H/DPjulmh8rg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "eslint-visitor-keys": "^3.4.3"
      },
      "engines": {
        "node": "^12.22.0 || ^14.17.0 || >=16.0.0"
      },
      "funding": {
        "url": "https://opencollective.com/eslint"
      },
      "peerDependencies": {
        "eslint": "^6.0.0 || ^7.0.0 || >=8.0.0"
      }
    },
    "node_modules/@eslint-community/eslint-utils/node_modules/eslint-visitor-keys": {
      "version": "3.4.3",
      "resolved": "https://registry.npmjs.org/eslint-visitor-keys/-/eslint-visitor-keys-3.4.3.tgz",
      "integrity": "sha512-wpc+LXeiyiisxPlEkUzU6svyS1frIO3Mgxj1fdy7Pm8Ygzguax2N3Fa/D/ag1WqbOprdI+uY6wMUl8/a2G+iag==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": "^12.22.0 || ^14.17.0 || >=16.0.0"
      },
      "funding": {
        "url": "https://opencollective.com/eslint"
      }
    },
    "node_modules/@eslint-community/regexpp": {
      "version": "4.12.2",
      "resolved": "https://registry.npmjs.org/@eslint-community/regexpp/-/regexpp-4.12.2.tgz",
      "integrity": "sha512-EriSTlt5OC9/7SXkRSCAhfSxxoSUgBm33OH+IkwbdpgoqsSsUg7y3uh+IICI/Qg4BBWr3U2i39RpmycbxMq4ew==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "^12.0.0 || ^14.0.0 || >=16.0.0"
      }
    },
    "node_modules/@eslint/config-array": {
      "version": "0.23.5",
      "resolved": "https://registry.npmjs.org/@eslint/config-array/-/config-array-0.23.5.tgz",
      "integrity": "sha512-Y3kKLvC1dvTOT+oGlqNQ1XLqK6D1HU2YXPc52NmAlJZbMMWDzGYXMiPRJ8TYD39muD/OTjlZmNJ4ib7dvSrMBA==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "@eslint/object-schema": "^3.0.5",
        "debug": "^4.3.1",
        "minimatch": "^10.2.4"
      },
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      }
    },
    "node_modules/@eslint/config-helpers": {
      "version": "0.7.0",
      "resolved": "https://registry.npmjs.org/@eslint/config-helpers/-/config-helpers-0.7.0.tgz",
      "integrity": "sha512-DObd/KKUsU+FaFv4PLxSRenpXfQWmPXXP3pPZ6/K1PCrMu2vQpMDMuQe/BqYeoLcz8ro0bVDF1RxOJgfVEdhUw==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "@eslint/core": "^1.2.1"
      },
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      }
    },
    "node_modules/@eslint/core": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/@eslint/core/-/core-1.2.1.tgz",
      "integrity": "sha512-MwcE1P+AZ4C6DWlpin/OmOA54mmIZ/+xZuJiQd4SyB29oAJjN30UW9wkKNptW2ctp4cEsvhlLY/CsQ1uoHDloQ==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "@types/json-schema": "^7.0.15"
      },
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      }
    },
    "node_modules/@eslint/js": {
      "version": "10.0.1",
      "resolved": "https://registry.npmjs.org/@eslint/js/-/js-10.0.1.tgz",
      "integrity": "sha512-zeR9k5pd4gxjZ0abRoIaxdc7I3nDktoXZk2qOv9gCNWx3mVwEn32VRhyLaRsDiJjTs0xq/T8mfPtyuXu7GWBcA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      },
      "funding": {
        "url": "https://eslint.org/donate"
      },
      "peerDependencies": {
        "eslint": "^10.0.0"
      },
      "peerDependenciesMeta": {
        "eslint": {
          "optional": true
        }
      }
    },
    "node_modules/@eslint/object-schema": {
      "version": "3.0.5",
      "resolved": "https://registry.npmjs.org/@eslint/object-schema/-/object-schema-3.0.5.tgz",
      "integrity": "sha512-vqTaUEgxzm+YDSdElad6PiRoX4t8VGDjCtt05zn4nU810UIx/uNEV7/lZJ6KwFThKZOzOxzXy48da+No7HZaMw==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      }
    },
    "node_modules/@eslint/plugin-kit": {
      "version": "0.7.3",
      "resolved": "https://registry.npmjs.org/@eslint/plugin-kit/-/plugin-kit-0.7.3.tgz",
      "integrity": "sha512-IkO+/KEUvwbVpiURZg+P7zF74z5Jxe0UgJxVni+RtoHQ6IZieXaO02kmadomap/q+l6bc/jdPGGqTjhuZnuz1Q==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "@eslint/core": "^1.2.1",
        "levn": "^0.4.1"
      },
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      }
    },
    "node_modules/@exodus/bytes": {
      "version": "1.16.0",
      "resolved": "https://registry.npmjs.org/@exodus/bytes/-/bytes-1.16.0.tgz",
      "integrity": "sha512-IcpW84uEn3N7ETtNZMlxKhfl6Pec8rUNGOTBtWbK1FKhJxIFAptZyVrvVRVBimAJxJCgc3PxepxkdWWG4DVzfA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "^20.19.0 || ^22.12.0 || >=24.0.0"
      },
      "peerDependencies": {
        "@noble/hashes": "^1.8.0 || ^2.0.0"
      },
      "peerDependenciesMeta": {
        "@noble/hashes": {
          "optional": true
        }
      }
    },
    "node_modules/@fast-csv/format": {
      "version": "4.3.5",
      "resolved": "https://registry.npmjs.org/@fast-csv/format/-/format-4.3.5.tgz",
      "integrity": "sha512-8iRn6QF3I8Ak78lNAa+Gdl5MJJBM5vRHivFtMRUWINdevNo00K7OXxS2PshawLKTejVwieIlPmK5YlLu6w4u8A==",
      "license": "MIT",
      "dependencies": {
        "@types/node": "^14.0.1",
        "lodash.escaperegexp": "^4.1.2",
        "lodash.isboolean": "^3.0.3",
        "lodash.isequal": "^4.5.0",
        "lodash.isfunction": "^3.0.9",
        "lodash.isnil": "^4.0.0"
      }
    },
    "node_modules/@fast-csv/format/node_modules/@types/node": {
      "version": "14.18.63",
      "resolved": "https://registry.npmjs.org/@types/node/-/node-14.18.63.tgz",
      "integrity": "sha512-fAtCfv4jJg+ExtXhvCkCqUKZ+4ok/JQk01qDKhL5BDDoS3AxKXhV5/MAVUZyQnSEd2GT92fkgZl0pz0Q0AzcIQ==",
      "license": "MIT"
    },
    "node_modules/@fast-csv/parse": {
      "version": "4.3.6",
      "resolved": "https://registry.npmjs.org/@fast-csv/parse/-/parse-4.3.6.tgz",
      "integrity": "sha512-uRsLYksqpbDmWaSmzvJcuApSEe38+6NQZBUsuAyMZKqHxH0g1wcJgsKUvN3WC8tewaqFjBMMGrkHmC+T7k8LvA==",
      "license": "MIT",
      "dependencies": {
        "@types/node": "^14.0.1",
        "lodash.escaperegexp": "^4.1.2",
        "lodash.groupby": "^4.6.0",
        "lodash.isfunction": "^3.0.9",
        "lodash.isnil": "^4.0.0",
        "lodash.isundefined": "^3.0.1",
        "lodash.uniq": "^4.5.0"
      }
    },
    "node_modules/@fast-csv/parse/node_modules/@types/node": {
      "version": "14.18.63",
      "resolved": "https://registry.npmjs.org/@types/node/-/node-14.18.63.tgz",
      "integrity": "sha512-fAtCfv4jJg+ExtXhvCkCqUKZ+4ok/JQk01qDKhL5BDDoS3AxKXhV5/MAVUZyQnSEd2GT92fkgZl0pz0Q0AzcIQ==",
      "license": "MIT"
    },
    "node_modules/@fontsource-variable/bricolage-grotesque": {
      "version": "5.3.0",
      "resolved": "https://registry.npmjs.org/@fontsource-variable/bricolage-grotesque/-/bricolage-grotesque-5.3.0.tgz",
      "integrity": "sha512-TLi9Q4hJjS2UvoTMRSS2nHu6c4R56lAw60NR9QYtVRCHn0XtsFpiEhNffZ8Glsoxu6wEEwLKBP8lb94J52PNBA==",
      "license": "OFL-1.1",
      "funding": {
        "url": "https://github.com/sponsors/ayuhito"
      }
    },
    "node_modules/@fontsource-variable/hanken-grotesk": {
      "version": "5.3.0",
      "resolved": "https://registry.npmjs.org/@fontsource-variable/hanken-grotesk/-/hanken-grotesk-5.3.0.tgz",
      "integrity": "sha512-DOd0FqL+3cH2dfNy0JtSq9tUfxBz5mLmHMjTU0DOr3E9Zo6wxuatCl53DIPNrSPgCsnuKyM739BTIG5glCLirw==",
      "license": "OFL-1.1",
      "funding": {
        "url": "https://github.com/sponsors/ayuhito"
      }
    },
    "node_modules/@humanfs/core": {
      "version": "0.19.2",
      "resolved": "https://registry.npmjs.org/@humanfs/core/-/core-0.19.2.tgz",
      "integrity": "sha512-UhXNm+CFMWcbChXywFwkmhqjs3PRCmcSa/hfBgLIb7oQ5HNb1wS0icWsGtSAUNgefHeI+eBrA8I1fxmbHsGdvA==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "@humanfs/types": "^0.15.0"
      },
      "engines": {
        "node": ">=18.18.0"
      }
    },
    "node_modules/@humanfs/node": {
      "version": "0.16.8",
      "resolved": "https://registry.npmjs.org/@humanfs/node/-/node-0.16.8.tgz",
      "integrity": "sha512-gE1eQNZ3R++kTzFUpdGlpmy8kDZD/MLyHqDwqjkVQI0JMdI1D51sy1H958PNXYkM2rAac7e5/CnIKZrHtPh3BQ==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "@humanfs/core": "^0.19.2",
        "@humanfs/types": "^0.15.0",
        "@humanwhocodes/retry": "^0.4.0"
      },
      "engines": {
        "node": ">=18.18.0"
      }
    },
    "node_modules/@humanfs/types": {
      "version": "0.15.0",
      "resolved": "https://registry.npmjs.org/@humanfs/types/-/types-0.15.0.tgz",
      "integrity": "sha512-ZZ1w0aoQkwuUuC7Yf+7sdeaNfqQiiLcSRbfI08oAxqLtpXQr9AIVX7Ay7HLDuiLYAaFPu8oBYNq/QIi9URHJ3Q==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": ">=18.18.0"
      }
    },
    "node_modules/@humanwhocodes/module-importer": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/@humanwhocodes/module-importer/-/module-importer-1.0.1.tgz",
      "integrity": "sha512-bxveV4V8v5Yb4ncFTT3rPSgZBOpCkjfK0y4oVVVJwIuDVBRMDXrPyXRL988i5ap9m9bnyEEjWfm5WkBmtffLfA==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": ">=12.22"
      },
      "funding": {
        "type": "github",
        "url": "https://github.com/sponsors/nzakas"
      }
    },
    "node_modules/@humanwhocodes/retry": {
      "version": "0.4.3",
      "resolved": "https://registry.npmjs.org/@humanwhocodes/retry/-/retry-0.4.3.tgz",
      "integrity": "sha512-bV0Tgo9K4hfPCek+aMAn81RppFKv2ySDQeMoSZuvTASywNTnVJCArCZE2FWqpvIatKu7VMRLWlR1EazvVhDyhQ==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": ">=18.18"
      },
      "funding": {
        "type": "github",
        "url": "https://github.com/sponsors/nzakas"
      }
    },
    "node_modules/@jridgewell/gen-mapping": {
      "version": "0.3.13",
      "resolved": "https://registry.npmjs.org/@jridgewell/gen-mapping/-/gen-mapping-0.3.13.tgz",
      "integrity": "sha512-2kkt/7niJ6MgEPxF0bYdQ6etZaA+fQvDcLKckhy1yIQOzaoKjBBjSj63/aLVjYE3qhRt5dvM+uUyfCg6UKCBbA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@jridgewell/sourcemap-codec": "^1.5.0",
        "@jridgewell/trace-mapping": "^0.3.24"
      }
    },
    "node_modules/@jridgewell/remapping": {
      "version": "2.3.5",
      "resolved": "https://registry.npmjs.org/@jridgewell/remapping/-/remapping-2.3.5.tgz",
      "integrity": "sha512-LI9u/+laYG4Ds1TDKSJW2YPrIlcVYOwi2fUC6xB43lueCjgxV4lffOCZCtYFiH6TNOX+tQKXx97T4IKHbhyHEQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@jridgewell/gen-mapping": "^0.3.5",
        "@jridgewell/trace-mapping": "^0.3.24"
      }
    },
    "node_modules/@jridgewell/resolve-uri": {
      "version": "3.1.2",
      "resolved": "https://registry.npmjs.org/@jridgewell/resolve-uri/-/resolve-uri-3.1.2.tgz",
      "integrity": "sha512-bRISgCIjP20/tbWSPWMEi54QVPRZExkuD9lJL+UIxUKtwVJA8wW1Trb1jMs1RFXo1CBTNZ/5hpC9QvmKWdopKw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6.0.0"
      }
    },
    "node_modules/@jridgewell/sourcemap-codec": {
      "version": "1.6.0",
      "resolved": "https://registry.npmjs.org/@jridgewell/sourcemap-codec/-/sourcemap-codec-1.6.0.tgz",
      "integrity": "sha512-T7jf+5zgsZHwNJ4lvQ7/aezbyk0nNX+zJVWpmHA7VYsEx7a7qr5Rg5IbtJFqkgze5Y2sruq1RUY8Q837Od7iFw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@jridgewell/trace-mapping": {
      "version": "0.3.31",
      "resolved": "https://registry.npmjs.org/@jridgewell/trace-mapping/-/trace-mapping-0.3.31.tgz",
      "integrity": "sha512-zzNR+SdQSDJzc8joaeP8QQoCQr8NuYx2dIIytl1QeBEZHJ9uW6hebsrYgbz8hJwUQao3TWCMtmfV8Nu1twOLAw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@jridgewell/resolve-uri": "^3.1.0",
        "@jridgewell/sourcemap-codec": "^1.4.14"
      }
    },
    "node_modules/@keyv/bigmap": {
      "version": "1.3.1",
      "resolved": "https://registry.npmjs.org/@keyv/bigmap/-/bigmap-1.3.1.tgz",
      "integrity": "sha512-WbzE9sdmQtKy8vrNPa9BRnwZh5UF4s1KTmSK0KUVLo3eff5BlQNNWDnFOouNpKfPKDnms9xynJjsMYjMaT/aFQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "hashery": "^1.4.0",
        "hookified": "^1.15.0"
      },
      "engines": {
        "node": ">= 18"
      },
      "peerDependencies": {
        "keyv": "^5.6.0"
      }
    },
    "node_modules/@keyv/serialize": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/@keyv/serialize/-/serialize-1.1.1.tgz",
      "integrity": "sha512-dXn3FZhPv0US+7dtJsIi2R+c7qWYiReoEh5zUntWCf4oSpMNib8FDhSoed6m3QyZdx5hK7iLFkYk3rNxwt8vTA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@mongodb-js/saslprep": {
      "version": "1.5.4",
      "resolved": "https://registry.npmjs.org/@mongodb-js/saslprep/-/saslprep-1.5.4.tgz",
      "integrity": "sha512-05UC0jQsjKAOuXQ0H9Ud9vUTJpZIg+n/FinpR30tI5I8pY2inTfPOZ5OF/cg3Ce/N9MoD1xhRCeOsJtuTbFYlw==",
      "license": "MIT",
      "dependencies": {
        "sparse-bitfield": "^3.0.3"
      }
    },
    "node_modules/@noble/hashes": {
      "version": "1.8.0",
      "resolved": "https://registry.npmjs.org/@noble/hashes/-/hashes-1.8.0.tgz",
      "integrity": "sha512-jCs9ldd7NwzpgXDIf6P3+NrHh9/sD6CQdxHyjQI+h/6rDNo88ypBxxz45UDuZHz9r3tNz7N/VInSVoVdtXEI4A==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "^14.21.3 || >=16"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/@oxc-project/types": {
      "version": "0.151.0",
      "resolved": "https://registry.npmjs.org/@oxc-project/types/-/types-0.151.0.tgz",
      "integrity": "sha512-J1yXrIlNDZVzE3ada310xeAw7nH8yCAyLPuUIsjKatFPmfn5bS1oW+cM+QsGOtVWd5nhSpbwZWx/rue+r5Z+PA==",
      "dev": true,
      "license": "MIT",
      "funding": {
        "url": "https://github.com/sponsors/oxc-project"
      }
    },
    "node_modules/@paralleldrive/cuid2": {
      "version": "2.3.1",
      "resolved": "https://registry.npmjs.org/@paralleldrive/cuid2/-/cuid2-2.3.1.tgz",
      "integrity": "sha512-XO7cAxhnTZl0Yggq6jOgjiOHhbgcO4NqFqwSmQpjK3b6TEE6Uj/jfSk6wzYyemh3+I0sHirKSetjQwn5cZktFw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@noble/hashes": "^1.1.5"
      }
    },
    "node_modules/@pinojs/redact": {
      "version": "0.4.0",
      "resolved": "https://registry.npmjs.org/@pinojs/redact/-/redact-0.4.0.tgz",
      "integrity": "sha512-k2ENnmBugE/rzQfEcdWHcCY+/FM3VLzH9cYEsbdsoqrvzAKRhUZeRNhAZvB8OitQJ1TBed3yqWtdjzS6wJKBwg==",
      "license": "MIT"
    },
    "node_modules/@remix-run/route-pattern": {
      "version": "0.22.1",
      "resolved": "https://registry.npmjs.org/@remix-run/route-pattern/-/route-pattern-0.22.1.tgz",
      "integrity": "sha512-czdGJWh09Lapvcqt7Vb09KlrU2PhRJ8xQaI+AItTuD9aDJ5MAgxnS38lnys6Ll+6RJEqPiaUqTwIQhVLwFvv+w==",
      "license": "MIT"
    },
    "node_modules/@rolldown/binding-android-arm-eabi": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-android-arm-eabi/-/binding-android-arm-eabi-1.2.11.tgz",
      "integrity": "sha512-A5kXfGKvKWWZE0TtPrfsvT+q4Y5d1QG8gGUzpYjGydM+fARM9MuX90PrXYXe0XbsDVgyxxNzHo6giCj90bsFNw==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-android-arm64": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-android-arm64/-/binding-android-arm64-1.2.11.tgz",
      "integrity": "sha512-z6cTycz+iJ4PVkuL4HHW4DfTfoeU/2nqYYuSOrTmH7yHK5Y0LCOnA03V4ZNxavyVaU1oOqUgIg2klN/s+USGOA==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-darwin-arm64": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-darwin-arm64/-/binding-darwin-arm64-1.2.11.tgz",
      "integrity": "sha512-jShvqNtP6vDC6/A5JOAzbVV+DkgHqhl/ScVCJEbt+TUY6QYz7YnXcrg3sLtFBniro0f/Ld50ZwCWA6f7KYD1nQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-darwin-x64": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-darwin-x64/-/binding-darwin-x64-1.2.11.tgz",
      "integrity": "sha512-f2i2xiNWq1Z1l2++q2fuhZRdLAT3aqxD6vRNm1RAxpUoBcdqNB3C0s1Bt+K+PbEx2F5F4gQp6hqKkphCY/xF9w==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-freebsd-x64": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-freebsd-x64/-/binding-freebsd-x64-1.2.11.tgz",
      "integrity": "sha512-4Ir5FSOKIAMr4r0kExpt1s3bMgzJU3rA45AYOHtQpls0oNeqcYBKrWMlckrYH4KCfGLfkfn1tN1dmZPMVsdXow==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-arm-gnueabihf": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-arm-gnueabihf/-/binding-linux-arm-gnueabihf-1.2.11.tgz",
      "integrity": "sha512-/gnRDM+39BROzAN/k1OZjDPnDMcZxB/0EUxKjONO5yVkNEvlsoMDrxGNKgZi/ttFriS2gwlDNzB65pvNbFOXIQ==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-arm64-gnu": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-arm64-gnu/-/binding-linux-arm64-gnu-1.2.11.tgz",
      "integrity": "sha512-PFaK8HwvAHbaKbBcDNQihjMKYvFnA5hiENx/l5tphTDz1E0WFp32l0A7aq7lyUwGsRw/xSrNIy/gIK4thrSCrw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-arm64-musl": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-arm64-musl/-/binding-linux-arm64-musl-1.2.11.tgz",
      "integrity": "sha512-AskzJUIKRLPxkruR1wLKewGbOw+EYfU/9lOrBFj4AFrEA8hPpKFnODWNu2WLaNs0QNkEb9QIJufmVZZIL/bJlg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-ppc64-gnu": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-ppc64-gnu/-/binding-linux-ppc64-gnu-1.2.11.tgz",
      "integrity": "sha512-qlUGAheh2yh8afH7QBgx0PrRHN85hKnNd78x8MeMhXivuevgd8vgf6/CstOzmNKY/lLTHvNTrPy98cLnAugzJw==",
      "cpu": [
        "ppc64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-s390x-gnu": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-s390x-gnu/-/binding-linux-s390x-gnu-1.2.11.tgz",
      "integrity": "sha512-secpEad+0vCbSfn8upFySkDskv+bGPk3THSDS9Y89yc4rb4kzqHp8Dmyd9BkQW4SnhNXBZCl/6CrO//hZahNJQ==",
      "cpu": [
        "s390x"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-x64-gnu": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-x64-gnu/-/binding-linux-x64-gnu-1.2.11.tgz",
      "integrity": "sha512-mOVBT3dPpkWm8XBWPmU4bf+U6dYDLeMo/9ojUmis4N0L5uu10qra5vOyngZ7/PSdoE4G9KvRt4bloRxNjLas7A==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-linux-x64-musl": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-linux-x64-musl/-/binding-linux-x64-musl-1.2.11.tgz",
      "integrity": "sha512-Is78i9A8Ui4SqcxUwFJ9uMmjDn58IbVTjFWYdQestFEgeuEmHMLGNriXnVJKkwG2YiZjw8cP0zCTyDMdDGtOOg==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-openharmony-arm64": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-openharmony-arm64/-/binding-openharmony-arm64-1.2.11.tgz",
      "integrity": "sha512-dUCXneZ87INUMyQ0D+C0HrEBNUPNXHaPmU5GTjyKTJEiussw9Kaj5Ln8UztPe4epV/ffvgNBEadksdYhmW6xJA==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "openharmony"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-win32-arm64-msvc": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-win32-arm64-msvc/-/binding-win32-arm64-msvc-1.2.11.tgz",
      "integrity": "sha512-jByxb6qfd+bH1xUd0qnfFnb17i9sWBPY2tOavJ0l3tdr3OTu+Kvtm8cd/JV5nFt657b1VqGltxg9olOEfofXWw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/binding-win32-x64-msvc": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/@rolldown/binding-win32-x64-msvc/-/binding-win32-x64-msvc-1.2.11.tgz",
      "integrity": "sha512-/PzKqzAJ03i19oy2ItPvyvaVjOjBCNnfaJs8yvUdGBKmiESgnrJSQ2awd81QzFbbnAmu7YO9ZnJrDCb9VSJPRA==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/pluginutils": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/@rolldown/pluginutils/-/pluginutils-1.0.1.tgz",
      "integrity": "sha512-2j9bGt5Jh8hj+vPtgzPtl72j0yRxHAyumoo6TNfAjsLB04UtpSvPbPcDcBMxz7n+9CYB0c1GxQFxYRg2jimqGw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@standard-schema/spec": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/@standard-schema/spec/-/spec-1.1.0.tgz",
      "integrity": "sha512-l2aFy5jALhniG5HgqrD6jXLi/rUWrKvqN/qJx6yoJsgKhblVd+iqqU4RCXavm/jPityDo5TCvKMnpjKnOriy0w==",
      "license": "MIT"
    },
    "node_modules/@standard-schema/utils": {
      "version": "0.3.0",
      "resolved": "https://registry.npmjs.org/@standard-schema/utils/-/utils-0.3.0.tgz",
      "integrity": "sha512-e7Mew686owMaPJVNNLs55PUvgz371nKgwsc4vxE49zsODpJEnxgxRo2y/OKrqueavXgZNMDVj3DdHFlaSAeU8g==",
      "license": "MIT"
    },
    "node_modules/@tailwindcss/node": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/node/-/node-4.3.3.tgz",
      "integrity": "sha512-/T8IKEsf9VTU6tLjgC7+sv2mOPtQxzE2jMw7u4Tt40Tx+QSZxpzh95/H6cMKoja9XuW7iMdLJYBB0o9G1CaAgg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@jridgewell/remapping": "^2.3.5",
        "enhanced-resolve": "^5.24.1",
        "jiti": "^2.7.0",
        "lightningcss": "1.32.0",
        "magic-string": "^0.30.21",
        "source-map-js": "^1.2.1",
        "tailwindcss": "4.3.3"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss/-/lightningcss-1.32.0.tgz",
      "integrity": "sha512-NXYBzinNrblfraPGyrbPoD19C1h9lfI/1mzgWYvXUTe414Gz/X1FD2XBZSZM7rRTrMA8JL3OtAaGifrIKhQ5yQ==",
      "dev": true,
      "license": "MPL-2.0",
      "dependencies": {
        "detect-libc": "^2.0.3"
      },
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      },
      "optionalDependencies": {
        "lightningcss-android-arm64": "1.32.0",
        "lightningcss-darwin-arm64": "1.32.0",
        "lightningcss-darwin-x64": "1.32.0",
        "lightningcss-freebsd-x64": "1.32.0",
        "lightningcss-linux-arm-gnueabihf": "1.32.0",
        "lightningcss-linux-arm64-gnu": "1.32.0",
        "lightningcss-linux-arm64-musl": "1.32.0",
        "lightningcss-linux-x64-gnu": "1.32.0",
        "lightningcss-linux-x64-musl": "1.32.0",
        "lightningcss-win32-arm64-msvc": "1.32.0",
        "lightningcss-win32-x64-msvc": "1.32.0"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-android-arm64": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-android-arm64/-/lightningcss-android-arm64-1.32.0.tgz",
      "integrity": "sha512-YK7/ClTt4kAK0vo6w3X+Pnm0D2cf2vPHbhOXdoNti1Ga0al1P4TBZhwjATvjNwLEBCnKvjJc2jQgHXH0NEwlAg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-darwin-arm64": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-darwin-arm64/-/lightningcss-darwin-arm64-1.32.0.tgz",
      "integrity": "sha512-RzeG9Ju5bag2Bv1/lwlVJvBE3q6TtXskdZLLCyfg5pt+HLz9BqlICO7LZM7VHNTTn/5PRhHFBSjk5lc4cmscPQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-darwin-x64": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-darwin-x64/-/lightningcss-darwin-x64-1.32.0.tgz",
      "integrity": "sha512-U+QsBp2m/s2wqpUYT/6wnlagdZbtZdndSmut/NJqlCcMLTWp5muCrID+K5UJ6jqD2BFshejCYXniPDbNh73V8w==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-freebsd-x64": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-freebsd-x64/-/lightningcss-freebsd-x64-1.32.0.tgz",
      "integrity": "sha512-JCTigedEksZk3tHTTthnMdVfGf61Fky8Ji2E4YjUTEQX14xiy/lTzXnu1vwiZe3bYe0q+SpsSH/CTeDXK6WHig==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-linux-arm-gnueabihf": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-arm-gnueabihf/-/lightningcss-linux-arm-gnueabihf-1.32.0.tgz",
      "integrity": "sha512-x6rnnpRa2GL0zQOkt6rts3YDPzduLpWvwAF6EMhXFVZXD4tPrBkEFqzGowzCsIWsPjqSK+tyNEODUBXeeVHSkw==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-linux-arm64-gnu": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-arm64-gnu/-/lightningcss-linux-arm64-gnu-1.32.0.tgz",
      "integrity": "sha512-0nnMyoyOLRJXfbMOilaSRcLH3Jw5z9HDNGfT/gwCPgaDjnx0i8w7vBzFLFR1f6CMLKF8gVbebmkUN3fa/kQJpQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-linux-arm64-musl": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-arm64-musl/-/lightningcss-linux-arm64-musl-1.32.0.tgz",
      "integrity": "sha512-UpQkoenr4UJEzgVIYpI80lDFvRmPVg6oqboNHfoH4CQIfNA+HOrZ7Mo7KZP02dC6LjghPQJeBsvXhJod/wnIBg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-linux-x64-gnu": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-x64-gnu/-/lightningcss-linux-x64-gnu-1.32.0.tgz",
      "integrity": "sha512-V7Qr52IhZmdKPVr+Vtw8o+WLsQJYCTd8loIfpDaMRWGUZfBOYEJeyJIkqGIDMZPwPx24pUMfwSxxI8phr/MbOA==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-linux-x64-musl": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-x64-musl/-/lightningcss-linux-x64-musl-1.32.0.tgz",
      "integrity": "sha512-bYcLp+Vb0awsiXg/80uCRezCYHNg1/l3mt0gzHnWV9XP1W5sKa5/TCdGWaR/zBM2PeF/HbsQv/j2URNOiVuxWg==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-win32-arm64-msvc": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-win32-arm64-msvc/-/lightningcss-win32-arm64-msvc-1.32.0.tgz",
      "integrity": "sha512-8SbC8BR40pS6baCM8sbtYDSwEVQd4JlFTOlaD3gWGHfThTcABnNDBda6eTZeqbofalIJhFx0qKzgHJmcPTnGdw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/lightningcss-win32-x64-msvc": {
      "version": "1.32.0",
      "resolved": "https://registry.npmjs.org/lightningcss-win32-x64-msvc/-/lightningcss-win32-x64-msvc-1.32.0.tgz",
      "integrity": "sha512-Amq9B/SoZYdDi1kFrojnoqPLxYhQ4Wo5XiL8EVJrVsB8ARoC1PWW6VGtT0WKCemjy8aC+louJnjS7U18x3b06Q==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/@tailwindcss/node/node_modules/magic-string": {
      "version": "0.30.21",
      "resolved": "https://registry.npmjs.org/magic-string/-/magic-string-0.30.21.tgz",
      "integrity": "sha512-vd2F4YUyEXKGcLHoq+TEyCjxueSeHnFxyyjNp80yg0XV4vUhnDer/lvvlqM/arB5bXQN5K2/3oinyCRyx8T2CQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@jridgewell/sourcemap-codec": "^1.5.5"
      }
    },
    "node_modules/@tailwindcss/oxide": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide/-/oxide-4.3.3.tgz",
      "integrity": "sha512-krXjAikiaFSPaK/FkAQT5UTx3VormQaiZ5hBFlJZ9UFQGB/rwg1MZIhHAG9smMQRTdyJxP6Qt5MwMtdyU5FWrA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 20"
      },
      "optionalDependencies": {
        "@tailwindcss/oxide-android-arm64": "4.3.3",
        "@tailwindcss/oxide-darwin-arm64": "4.3.3",
        "@tailwindcss/oxide-darwin-x64": "4.3.3",
        "@tailwindcss/oxide-freebsd-x64": "4.3.3",
        "@tailwindcss/oxide-linux-arm-gnueabihf": "4.3.3",
        "@tailwindcss/oxide-linux-arm64-gnu": "4.3.3",
        "@tailwindcss/oxide-linux-arm64-musl": "4.3.3",
        "@tailwindcss/oxide-linux-x64-gnu": "4.3.3",
        "@tailwindcss/oxide-linux-x64-musl": "4.3.3",
        "@tailwindcss/oxide-wasm32-wasi": "4.3.3",
        "@tailwindcss/oxide-win32-arm64-msvc": "4.3.3",
        "@tailwindcss/oxide-win32-x64-msvc": "4.3.3"
      }
    },
    "node_modules/@tailwindcss/oxide-android-arm64": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-android-arm64/-/oxide-android-arm64-4.3.3.tgz",
      "integrity": "sha512-Y85A2gmPSkl5Ve5qR86GL4HT509cFqQh1aes9p3sSkyTPwt0Pppf3GkwGe4JPACcRYjgJIEhQgM6dBClnr0NYw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-darwin-arm64": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-darwin-arm64/-/oxide-darwin-arm64-4.3.3.tgz",
      "integrity": "sha512-BiaWatpBcERQFDlOjRDpIVXuFK5PJez5SA4JMg6VYZdBYU+qKfV/vqjcIs+IYmtitf1xYQZTwXvU/8y4lfZUGw==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-darwin-x64": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-darwin-x64/-/oxide-darwin-x64-4.3.3.tgz",
      "integrity": "sha512-fAeUqfV5ndhxRwai8cXGzdLvul9utWOmeTkv69unv4ZXixjn61Z+p9lCWdwOwA3TYboG3BwdVuN/RDjhBRl0mw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-freebsd-x64": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-freebsd-x64/-/oxide-freebsd-x64-4.3.3.tgz",
      "integrity": "sha512-iyf5bV6+wnAlflVeEy7R25dupxTNECZN5QMI0qNT6eT+EgaGdZcKhGkr5SdoaWiLJ3spLqIY9VCeSGrwmtg4kw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-linux-arm-gnueabihf": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-linux-arm-gnueabihf/-/oxide-linux-arm-gnueabihf-4.3.3.tgz",
      "integrity": "sha512-aAYUprJAJQWWbRrPvtjdroZ56Md+JM8pMiopS6xGEwDfLhqj+2ver2p4nU4Mb3CRqcMmNBjo8KkUgcxhkzVQGQ==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-linux-arm64-gnu": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-linux-arm64-gnu/-/oxide-linux-arm64-gnu-4.3.3.tgz",
      "integrity": "sha512-nDxldcEENOxZRzC2uu9jrutZdAAQtb+8WWDCSnWL1zvBk1+FN+x6MtDViPB5AJMfttVCUhehGWus3XBPgatM/w==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-linux-arm64-musl": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-linux-arm64-musl/-/oxide-linux-arm64-musl-4.3.3.tgz",
      "integrity": "sha512-Md44bD6veX/PC5iyF8cDVnw4HBIANZepRZZ7a8DQOvkfo5WUBwcp6iAuCUz23u+4SUkhJlD3eL7hNdW8ezd/kA==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-linux-x64-gnu": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-linux-x64-gnu/-/oxide-linux-x64-gnu-4.3.3.tgz",
      "integrity": "sha512-tx7us1muwOKAKWao2v/GaafFeQboE6aj88vC6ziN2NCGcRm8gWUhwjzg+YdVB1e4boAtdtma4L43onunI6NS4w==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-linux-x64-musl": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-linux-x64-musl/-/oxide-linux-x64-musl-4.3.3.tgz",
      "integrity": "sha512-SJxX60smvHgasZoBy11dX6YRjXJFovwWBoedhbQPOBzgFWBHGB+TVPWB9BxzR7TTxU8FQZAI2AyiNCMzFm8Img==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-wasm32-wasi": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-wasm32-wasi/-/oxide-wasm32-wasi-4.3.3.tgz",
      "integrity": "sha512-jx1+rPhY/5Ympkktd656HBWEBLxP7dH06losBLjjf5vgCODXvi9KhtftWcMIwTFIDqBr7cRnQkdLnAG+IOlGvQ==",
      "bundleDependencies": [
        "@napi-rs/wasm-runtime",
        "@emnapi/core",
        "@emnapi/runtime",
        "@tybys/wasm-util",
        "@emnapi/wasi-threads",
        "tslib"
      ],
      "cpu": [
        "wasm32"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "dependencies": {
        "@emnapi/core": "^1.11.1",
        "@emnapi/runtime": "^1.11.1",
        "@emnapi/wasi-threads": "^1.2.2",
        "@napi-rs/wasm-runtime": "^1.1.4",
        "@tybys/wasm-util": "^0.10.2",
        "tslib": "^2.8.1"
      },
      "engines": {
        "node": ">=14.0.0"
      }
    },
    "node_modules/@tailwindcss/oxide-win32-arm64-msvc": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-win32-arm64-msvc/-/oxide-win32-arm64-msvc-4.3.3.tgz",
      "integrity": "sha512-3rc292Ca2ceK6Ulcc/bAVnTs/3nDtoPhyEKlgPv+yQJQi/JS/AMJlqzxvlDacL1nekbrcf6bTqp/jV4qgnPxNQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/oxide-win32-x64-msvc": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/oxide-win32-x64-msvc/-/oxide-win32-x64-msvc-4.3.3.tgz",
      "integrity": "sha512-yJ0pwIVc/nYeGoV02WtsN8KYyLQv7kyI2wDnkezyJlGGjkd4QLwDGAwl47YpPJeuI0M0ObaXGSPjvWDPeTPggw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">= 20"
      }
    },
    "node_modules/@tailwindcss/vite": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/@tailwindcss/vite/-/vite-4.3.3.tgz",
      "integrity": "sha512-yYU8cogLeSh/ms2jh8Fj7jaba/EWa7Ja6GoUqYZaraEuCI5YS6ms6ObZgjjedm+jm6XZjdNRWBpPP6Z86oOxcw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@tailwindcss/node": "4.3.3",
        "@tailwindcss/oxide": "4.3.3",
        "tailwindcss": "4.3.3"
      },
      "peerDependencies": {
        "vite": "^5.2.0 || ^6 || ^7 || ^8"
      }
    },
    "node_modules/@tanstack/query-core": {
      "version": "5.104.1",
      "resolved": "https://registry.npmjs.org/@tanstack/query-core/-/query-core-5.104.1.tgz",
      "integrity": "sha512-TiRghcrGkUTE+M4JBxvpPSpBhxvIzQairw+cksrHYGr+2uwC77yW1SY9nYxnYRYOppvucf8rEg6b5byoz4rTpw==",
      "license": "MIT",
      "funding": {
        "type": "github",
        "url": "https://github.com/sponsors/tannerlinsley"
      }
    },
    "node_modules/@tanstack/react-query": {
      "version": "5.104.1",
      "resolved": "https://registry.npmjs.org/@tanstack/react-query/-/react-query-5.104.1.tgz",
      "integrity": "sha512-Zz70EgjahNI7aCz8BZxM3vUGU44ycxEAzMuCUjLeA7SVhhOkg3ZgPjPJPvHjs6Rmky/dtmnu1WzjGHNHmhCoZQ==",
      "license": "MIT",
      "dependencies": {
        "@tanstack/query-core": "5.104.1"
      },
      "funding": {
        "type": "github",
        "url": "https://github.com/sponsors/tannerlinsley"
      },
      "peerDependencies": {
        "react": "^18 || ^19"
      }
    },
    "node_modules/@testing-library/dom": {
      "version": "10.4.2",
      "resolved": "https://registry.npmjs.org/@testing-library/dom/-/dom-10.4.2.tgz",
      "integrity": "sha512-yzr2S9HyAIdhz2/6qHgbs665Q7PKVcDF05vsOlHPxG1mo36gKVesdYVeDLnXgfjJ03CrKRk08knc6+E/9m8v2Q==",
      "dev": true,
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "@babel/code-frame": "^7.10.4",
        "@babel/runtime": "^7.12.5",
        "@types/aria-query": "^5.0.1",
        "aria-query": "5.3.0",
        "dom-accessibility-api": "^0.5.9",
        "lz-string": "^1.5.0",
        "picocolors": "1.1.1",
        "pretty-format": "^27.0.2"
      },
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/@testing-library/jest-dom": {
      "version": "7.0.1",
      "resolved": "https://registry.npmjs.org/@testing-library/jest-dom/-/jest-dom-7.0.1.tgz",
      "integrity": "sha512-oMDTC3oA+6CXSO2JZnvOI7CA6oVub6kij5ggk9ohwye5slmkwxYDXcPOVxgMw/RQlticjtO0C1RZkR97HgrWMw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@adobe/css-tools": "^4.4.0",
        "aria-query": "^5.0.0",
        "css.escape": "^1.5.1",
        "dom-accessibility-api": "^0.6.3",
        "picocolors": "^1.1.1",
        "redent": "^3.0.0"
      },
      "engines": {
        "node": ">=22",
        "npm": ">=6",
        "yarn": ">=1"
      },
      "peerDependencies": {
        "@testing-library/dom": ">=10 <11",
        "vitest": ">= 0.32"
      },
      "peerDependenciesMeta": {
        "vitest": {
          "optional": true
        }
      }
    },
    "node_modules/@testing-library/jest-dom/node_modules/dom-accessibility-api": {
      "version": "0.6.3",
      "resolved": "https://registry.npmjs.org/dom-accessibility-api/-/dom-accessibility-api-0.6.3.tgz",
      "integrity": "sha512-7ZgogeTnjuHbo+ct10G9Ffp0mif17idi0IyWNVA/wcwcm7NPOD/WEHVP3n7n3MhXqxoIYm8d6MuZohYWIZ4T3w==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@testing-library/react": {
      "version": "16.3.3",
      "resolved": "https://registry.npmjs.org/@testing-library/react/-/react-16.3.3.tgz",
      "integrity": "sha512-Uo193NgQbPMz6lrrhtRQQFcMC6Re/ELLFbbuVL30WDlZxlpZf9/lMHTAVxPRLw1q1iu9OJmR1c2BLiENRstdBg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/runtime": "^7.12.5"
      },
      "engines": {
        "node": ">=18"
      },
      "peerDependencies": {
        "@testing-library/dom": "^10.0.0",
        "@types/react": "^18.0.0 || ^19.0.0",
        "@types/react-dom": "^18.0.0 || ^19.0.0",
        "react": "^18.0.0 || ^19.0.0",
        "react-dom": "^18.0.0 || ^19.0.0"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        },
        "@types/react-dom": {
          "optional": true
        }
      }
    },
    "node_modules/@testing-library/user-event": {
      "version": "14.6.7",
      "resolved": "https://registry.npmjs.org/@testing-library/user-event/-/user-event-14.6.7.tgz",
      "integrity": "sha512-MPCpX8bxe8zS+JmmTwLp8jd0dy1rAm60Te/SL8JrQM3qvQJcBOs1d7IefJMyZzqM3EWBrDn/LWDt1BCGu4ASfg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12",
        "npm": ">=6"
      },
      "peerDependencies": {
        "@testing-library/dom": ">=7.21.4"
      }
    },
    "node_modules/@types/aria-query": {
      "version": "5.0.4",
      "resolved": "https://registry.npmjs.org/@types/aria-query/-/aria-query-5.0.4.tgz",
      "integrity": "sha512-rfT93uj5s0PRL7EzccGMs3brplhcrghnDoV26NqKhCAS1hVo+WdNsPvE/yb6ilfr5hi2MEk6d5EWJTKdxg8jVw==",
      "dev": true,
      "license": "MIT",
      "peer": true
    },
    "node_modules/@types/body-parser": {
      "version": "1.19.6",
      "resolved": "https://registry.npmjs.org/@types/body-parser/-/body-parser-1.19.6.tgz",
      "integrity": "sha512-HLFeCYgz89uk22N5Qg3dvGvsv46B8GLvKKo1zKG4NybA8U2DiEO3w9lqGg29t/tfLRJpJ6iQxnVw4OnB7MoM9g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/connect": "*",
        "@types/node": "*"
      }
    },
    "node_modules/@types/chai": {
      "version": "5.2.3",
      "resolved": "https://registry.npmjs.org/@types/chai/-/chai-5.2.3.tgz",
      "integrity": "sha512-Mw558oeA9fFbv65/y4mHtXDs9bPnFMZAL/jxdPFUpOHHIXX91mcgEHbS5Lahr+pwZFR8A7GQleRWeI6cGFC2UA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/deep-eql": "*",
        "assertion-error": "^2.0.1"
      }
    },
    "node_modules/@types/connect": {
      "version": "3.4.38",
      "resolved": "https://registry.npmjs.org/@types/connect/-/connect-3.4.38.tgz",
      "integrity": "sha512-K6uROf1LD88uDQqJCktA4yzL1YYAK6NgfsI0v/mTgyPKWsX1CnJ0XPSDhViejru1GcRkLWb8RlzFYJRqGUbaug==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/node": "*"
      }
    },
    "node_modules/@types/cookie-parser": {
      "version": "1.4.10",
      "resolved": "https://registry.npmjs.org/@types/cookie-parser/-/cookie-parser-1.4.10.tgz",
      "integrity": "sha512-B4xqkqfZ8Wek+rCOeRxsjMS9OgvzebEzzLYw7NHYuvzb7IdxOkI0ZHGgeEBX4PUM7QGVvNSK60T3OvWj3YfBRg==",
      "dev": true,
      "license": "MIT",
      "peerDependencies": {
        "@types/express": "*"
      }
    },
    "node_modules/@types/cookiejar": {
      "version": "2.1.5",
      "resolved": "https://registry.npmjs.org/@types/cookiejar/-/cookiejar-2.1.5.tgz",
      "integrity": "sha512-he+DHOWReW0nghN24E1WUqM0efK4kI9oTqDm6XmK8ZPe2djZ90BSNdGnIyCLzCPw7/pogPlGbzI2wHGGmi4O/Q==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/cors": {
      "version": "2.8.19",
      "resolved": "https://registry.npmjs.org/@types/cors/-/cors-2.8.19.tgz",
      "integrity": "sha512-mFNylyeyqN93lfe/9CSxOGREz8cpzAhH+E93xJ4xWQf62V8sQ/24reV2nyzUWM6H6Xji+GGHpkbLe7pVoUEskg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/node": "*"
      }
    },
    "node_modules/@types/deep-eql": {
      "version": "4.0.2",
      "resolved": "https://registry.npmjs.org/@types/deep-eql/-/deep-eql-4.0.2.tgz",
      "integrity": "sha512-c9h9dVVMigMPc4bwTvC5dxqtqJZwQPePsWjPlpSOnojbor6pGqdk541lfA7AqFQr5pB1BRdq0juY9db81BwyFw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/emscripten": {
      "version": "1.41.6",
      "resolved": "https://registry.npmjs.org/@types/emscripten/-/emscripten-1.41.6.tgz",
      "integrity": "sha512-uN+9i8bFT5CUcZfyIEYDrSueACEyKGbUs5kC/72DGlZZoinh84sJfVV0i8UOJD1asdzkvLPBRrKs41kZ8MdEXg==",
      "license": "MIT"
    },
    "node_modules/@types/esrecurse": {
      "version": "4.3.1",
      "resolved": "https://registry.npmjs.org/@types/esrecurse/-/esrecurse-4.3.1.tgz",
      "integrity": "sha512-xJBAbDifo5hpffDBuHl0Y8ywswbiAp/Wi7Y/GtAgSlZyIABppyurxVueOPE8LUQOxdlgi6Zqce7uoEpqNTeiUw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/estree": {
      "version": "1.0.9",
      "resolved": "https://registry.npmjs.org/@types/estree/-/estree-1.0.9.tgz",
      "integrity": "sha512-GhdPgy1el4/ImP05X05Uw4cw2/M93BCUmnEvWZNStlCzEKME4Fkk+YpoA5OiHNQmoS7Cafb8Xa3Pya8m1Qrzeg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/express": {
      "version": "5.0.6",
      "resolved": "https://registry.npmjs.org/@types/express/-/express-5.0.6.tgz",
      "integrity": "sha512-sKYVuV7Sv9fbPIt/442koC7+IIwK5olP1KWeD88e/idgoJqDm3JV/YUiPwkoKK92ylff2MGxSz1CSjsXelx0YA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/body-parser": "*",
        "@types/express-serve-static-core": "^5.0.0",
        "@types/serve-static": "^2"
      }
    },
    "node_modules/@types/express-serve-static-core": {
      "version": "5.1.3",
      "resolved": "https://registry.npmjs.org/@types/express-serve-static-core/-/express-serve-static-core-5.1.3.tgz",
      "integrity": "sha512-dPfW8NFiOF4wOHc7+N/QSxlY9cfSsenewGbAz8C8U/MULPd/YZ27LvJUIlzaXie7e6Ove9YunJGgC9tbHD2cKw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/node": "*",
        "@types/qs": "*",
        "@types/range-parser": "*",
        "@types/send": "*"
      }
    },
    "node_modules/@types/http-errors": {
      "version": "2.0.5",
      "resolved": "https://registry.npmjs.org/@types/http-errors/-/http-errors-2.0.5.tgz",
      "integrity": "sha512-r8Tayk8HJnX0FztbZN7oVqGccWgw98T/0neJphO91KkmOzug1KkofZURD4UaD5uH8AqcFLfdPErnBod0u71/qg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/json-schema": {
      "version": "7.0.15",
      "resolved": "https://registry.npmjs.org/@types/json-schema/-/json-schema-7.0.15.tgz",
      "integrity": "sha512-5+fP8P8MFNC+AyZCDxrB2pkZFPGzqQWUzpSeuuVLvm8VMcorNYavBqoFcxK8bQz4Qsbn4oUEEem4wDLfcysGHA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/jsonwebtoken": {
      "version": "9.0.10",
      "resolved": "https://registry.npmjs.org/@types/jsonwebtoken/-/jsonwebtoken-9.0.10.tgz",
      "integrity": "sha512-asx5hIG9Qmf/1oStypjanR7iKTv0gXQ1Ov/jfrX6kS/EO0OFni8orbmGCn0672NHR3kXHwpAwR+B368ZGN/2rA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/ms": "*",
        "@types/node": "*"
      }
    },
    "node_modules/@types/luxon": {
      "version": "3.7.6",
      "resolved": "https://registry.npmjs.org/@types/luxon/-/luxon-3.7.6.tgz",
      "integrity": "sha512-6KSjliQAXK8ZLgFQO4B7iE4Rpf/B3rItzCFuXezBY/XIAGxOdLd7vRNK9/StRPwiS/yJsVbB7HKpW46B8tcEuQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/methods": {
      "version": "1.1.4",
      "resolved": "https://registry.npmjs.org/@types/methods/-/methods-1.1.4.tgz",
      "integrity": "sha512-ymXWVrDiCxTBE3+RIrrP533E70eA+9qu7zdWoHuOmGujkYtzf4HQF96b8nwHLqhuf4ykX61IGRIB38CC6/sImQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/ms": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/@types/ms/-/ms-2.1.0.tgz",
      "integrity": "sha512-GsCCIZDE/p3i96vtEqx+7dBUGXrc7zeSK3wwPHIaRThS+9OhWIXRqzs4d6k1SVU8g91DrNRWxWUGhp5KXQb2VA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/node": {
      "version": "22.20.4",
      "resolved": "https://registry.npmjs.org/@types/node/-/node-22.20.4.tgz",
      "integrity": "sha512-zJRE40jpHtKqE/C4fgHrAKQLJuSpzEnP9ff9Y7YtoR3Wd2pwqzlekDeEuUQXjRd+QCYnVnNwuJYmhdk9XV8gvA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "undici-types": "~6.21.0"
      }
    },
    "node_modules/@types/papaparse": {
      "version": "5.5.2",
      "resolved": "https://registry.npmjs.org/@types/papaparse/-/papaparse-5.5.2.tgz",
      "integrity": "sha512-gFnFp/JMzLHCwRf7tQHrNnfhN4eYBVYYI897CGX4MY1tzY9l2aLkVyx2IlKZ/SAqDbB3I1AOZW5gTMGGsqWliA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/node": "*"
      }
    },
    "node_modules/@types/qrcode": {
      "version": "1.5.6",
      "resolved": "https://registry.npmjs.org/@types/qrcode/-/qrcode-1.5.6.tgz",
      "integrity": "sha512-te7NQcV2BOvdj2b1hCAHzAoMNuj65kNBMz0KBaxM6c3VGBOhU0dURQKOtH8CFNI/dsKkwlv32p26qYQTWoB5bw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/node": "*"
      }
    },
    "node_modules/@types/qs": {
      "version": "6.15.1",
      "resolved": "https://registry.npmjs.org/@types/qs/-/qs-6.15.1.tgz",
      "integrity": "sha512-GZHUBZR9hckSUhrxmp1nG6NwdpM9fCunJwyThLW1X3AyHgd9IlHb6VANpQQqDr2o/qQp6McZ3y/IA2rVzKzSbw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/range-parser": {
      "version": "1.2.7",
      "resolved": "https://registry.npmjs.org/@types/range-parser/-/range-parser-1.2.7.tgz",
      "integrity": "sha512-hKormJbkJqzQGhziax5PItDUTMAM9uE2XXQmM37dyd4hVM+5aVl7oVxMVUiVQn2oCQFN/LKCZdvSM0pFRqbSmQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/@types/react": {
      "version": "19.3.0",
      "resolved": "https://registry.npmjs.org/@types/react/-/react-19.3.0.tgz",
      "integrity": "sha512-N0rFCuH9YoxG9/m61l9MfpJKfmLOVU0em7ipIz6TRgSSkvReLB9vL85GB+yr8Bs5leqpvg96JSwF4ZS1s4viQg==",
      "devOptional": true,
      "license": "MIT",
      "dependencies": {
        "csstype": "^3.2.2"
      }
    },
    "node_modules/@types/react-dom": {
      "version": "19.3.0",
      "resolved": "https://registry.npmjs.org/@types/react-dom/-/react-dom-19.3.0.tgz",
      "integrity": "sha512-ZI7bU42mZXXKHn/qNLEw2IrbiINU7X5+vfgdixBHkCNpYWXjKgfQ/P+uyGb5CjOLB9UcnTeg3rylQtV2hym44Q==",
      "dev": true,
      "license": "MIT",
      "peerDependencies": {
        "@types/react": "^19.3.0"
      }
    },
    "node_modules/@types/send": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/@types/send/-/send-1.2.1.tgz",
      "integrity": "sha512-arsCikDvlU99zl1g69TcAB3mzZPpxgw0UQnaHeC1Nwb015xp8bknZv5rIfri9xTOcMuaVgvabfIRA7PSZVuZIQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/node": "*"
      }
    },
    "node_modules/@types/serve-static": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/@types/serve-static/-/serve-static-2.2.0.tgz",
      "integrity": "sha512-8mam4H1NHLtu7nmtalF7eyBH14QyOASmcxHhSfEoRyr0nP/YdoesEtU+uSRvMe96TW/HPTtkoKqQLl53N7UXMQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/http-errors": "*",
        "@types/node": "*"
      }
    },
    "node_modules/@types/superagent": {
      "version": "8.1.11",
      "resolved": "https://registry.npmjs.org/@types/superagent/-/superagent-8.1.11.tgz",
      "integrity": "sha512-KA7srSW/HENDtOw9DOqaFLgWuMqN9WgjEw62lh9dpvRaZDkhdOkazASd7X7i2eMUYLHa1U37ZttnePsH5zTDHw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/cookiejar": "^2.1.5",
        "@types/methods": "^1.1.4",
        "@types/node": "*",
        "form-data": "^4.0.0"
      }
    },
    "node_modules/@types/supertest": {
      "version": "7.2.1",
      "resolved": "https://registry.npmjs.org/@types/supertest/-/supertest-7.2.1.tgz",
      "integrity": "sha512-4CbBvoYVLHL7+yhbYrZET0vsvuyXTC05aRe7dNQkwMzm56auceoy6Yu3K50uZmwfHna1os3CMSgM/3QVkUtPTw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/methods": "^1.1.4",
        "@types/superagent": "^8.1.0"
      }
    },
    "node_modules/@types/webidl-conversions": {
      "version": "7.0.3",
      "resolved": "https://registry.npmjs.org/@types/webidl-conversions/-/webidl-conversions-7.0.3.tgz",
      "integrity": "sha512-CiJJvcRtIgzadHCYXw7dqEnMNRjhGZlYK05Mj9OyktqV8uVT8fD2BFOB7S1uwBE3Kj2Z+4UyPmFw/Ixgw/LAlA==",
      "license": "MIT"
    },
    "node_modules/@types/whatwg-url": {
      "version": "13.0.0",
      "resolved": "https://registry.npmjs.org/@types/whatwg-url/-/whatwg-url-13.0.0.tgz",
      "integrity": "sha512-N8WXpbE6Wgri7KUSvrmQcqrMllKZ9uxkYWMt+mCSGwNc0Hsw9VQTW7ApqI4XNrx6/SaM2QQJCzMPDEXE058s+Q==",
      "license": "MIT",
      "dependencies": {
        "@types/webidl-conversions": "*"
      }
    },
    "node_modules/@typescript-eslint/eslint-plugin": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/eslint-plugin/-/eslint-plugin-8.71.0.tgz",
      "integrity": "sha512-pqcS9c1HxZTHt7End4nXqd0s5lJrrFzrgCkKFJrsbUnaL6M3+6oBFZaslg6Gjsl3argl2DDRFROnXARaZ2e4Nw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@eslint-community/regexpp": "^4.12.2",
        "@typescript-eslint/scope-manager": "8.71.0",
        "@typescript-eslint/type-utils": "8.71.0",
        "@typescript-eslint/utils": "8.71.0",
        "@typescript-eslint/visitor-keys": "8.71.0",
        "ignore": "^7.0.5",
        "natural-compare": "^1.4.0",
        "ts-api-utils": "^2.5.0"
      },
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      },
      "peerDependencies": {
        "@typescript-eslint/parser": "^8.71.0",
        "eslint": "^8.57.0 || ^9.0.0 || ^10.0.0",
        "typescript": ">=4.8.4 <6.1.0"
      }
    },
    "node_modules/@typescript-eslint/eslint-plugin/node_modules/ignore": {
      "version": "7.0.10",
      "resolved": "https://registry.npmjs.org/ignore/-/ignore-7.0.10.tgz",
      "integrity": "sha512-HpbUakT7xp5miBUywCHf36ZEuAJNklBJDDsGpUIjMzOSmM8ELSfA9Sa/QDPeNeqeoN31u+UTCkL4klCOVvRm4Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 4"
      }
    },
    "node_modules/@typescript-eslint/parser": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/parser/-/parser-8.71.0.tgz",
      "integrity": "sha512-CG4nPk1f2zc8yw4pALqHsFYH2hdo+h1T9daSp21+Hnxi9LOE3GT9hAfTKJCBXVNM2GmYs1eMEP615wPoeOgk3A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@typescript-eslint/scope-manager": "8.71.0",
        "@typescript-eslint/types": "8.71.0",
        "@typescript-eslint/typescript-estree": "8.71.0",
        "@typescript-eslint/visitor-keys": "8.71.0",
        "debug": "^4.4.3"
      },
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      },
      "peerDependencies": {
        "eslint": "^8.57.0 || ^9.0.0 || ^10.0.0",
        "typescript": ">=4.8.4 <6.1.0"
      }
    },
    "node_modules/@typescript-eslint/project-service": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/project-service/-/project-service-8.71.0.tgz",
      "integrity": "sha512-aABjw5rjBacYONVPaPiWOCjJu0vEF4a25iQuodlmQYL1trtLZ0X/y+2Vzl3BKI1odM4LnwLE1oUDXYp1wzx1TQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@typescript-eslint/tsconfig-utils": "^8.71.0",
        "@typescript-eslint/types": "^8.71.0",
        "debug": "^4.4.3"
      },
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      },
      "peerDependencies": {
        "typescript": ">=4.8.4 <6.1.0"
      }
    },
    "node_modules/@typescript-eslint/scope-manager": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/scope-manager/-/scope-manager-8.71.0.tgz",
      "integrity": "sha512-gWF0BhUcnjZxSpLE8ngS/59n2SB0J3YqRxvX1+2aoRJk9hNtHSLOV+TcarFiOr5ipXm3yc1QrI4c9YZc8zyCxw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@typescript-eslint/types": "8.71.0",
        "@typescript-eslint/visitor-keys": "8.71.0"
      },
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      }
    },
    "node_modules/@typescript-eslint/tsconfig-utils": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/tsconfig-utils/-/tsconfig-utils-8.71.0.tgz",
      "integrity": "sha512-Z1UlWHADEK2Mlb9NpWfDeSjqoZ5EyrOv4R3eQpbkzqn/EwaIdOpXXupEA1+0ZIOSJSZZDBHG0BrQyN8zUG6Pwg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      },
      "peerDependencies": {
        "typescript": ">=4.8.4 <6.1.0"
      }
    },
    "node_modules/@typescript-eslint/type-utils": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/type-utils/-/type-utils-8.71.0.tgz",
      "integrity": "sha512-i8uO1qbdxeKgRnS5sCRt6On3/nfo2d2DwQe3Yvjx543zLy7r8ySqRuPPiIIXAhS03U0v5NfAFx+rUgxFzKKwNw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@typescript-eslint/types": "8.71.0",
        "@typescript-eslint/typescript-estree": "8.71.0",
        "@typescript-eslint/utils": "8.71.0",
        "debug": "^4.4.3",
        "ts-api-utils": "^2.5.0"
      },
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      },
      "peerDependencies": {
        "eslint": "^8.57.0 || ^9.0.0 || ^10.0.0",
        "typescript": ">=4.8.4 <6.1.0"
      }
    },
    "node_modules/@typescript-eslint/types": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/types/-/types-8.71.0.tgz",
      "integrity": "sha512-cJ4OoxPGWvFnBTnSZyaU+qJzGTqPTGJY+gDchj6cRyLRdmIdt4rcsE4twj+zPfrNiWuVi38wijHzShL++Z9atQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      }
    },
    "node_modules/@typescript-eslint/typescript-estree": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/typescript-estree/-/typescript-estree-8.71.0.tgz",
      "integrity": "sha512-PEEF4G5sLLWAS5BpPrUvms4ySZkiBQQZM4z+3ReI46axK5Vqr/vXBQatJQIZZOYdGyPUAKTtsrWzpqKuU+3DEw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@typescript-eslint/project-service": "8.71.0",
        "@typescript-eslint/tsconfig-utils": "8.71.0",
        "@typescript-eslint/types": "8.71.0",
        "@typescript-eslint/visitor-keys": "8.71.0",
        "debug": "^4.4.3",
        "minimatch": "^10.2.2",
        "semver": "^7.7.3",
        "tinyglobby": "^0.2.15",
        "ts-api-utils": "^2.5.0"
      },
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      },
      "peerDependencies": {
        "typescript": ">=4.8.4 <6.1.0"
      }
    },
    "node_modules/@typescript-eslint/utils": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/utils/-/utils-8.71.0.tgz",
      "integrity": "sha512-pKR/tEMVrXZG23UFKUn5BQf3zfmfk7KQceI2cGzywZ5nxM5Eu3hEJU1utjWzydtzBbcJAQhHN8iPCxobHpPcZQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@eslint-community/eslint-utils": "^4.9.1",
        "@typescript-eslint/scope-manager": "8.71.0",
        "@typescript-eslint/types": "8.71.0",
        "@typescript-eslint/typescript-estree": "8.71.0"
      },
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      },
      "peerDependencies": {
        "eslint": "^8.57.0 || ^9.0.0 || ^10.0.0",
        "typescript": ">=4.8.4 <6.1.0"
      }
    },
    "node_modules/@typescript-eslint/visitor-keys": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/@typescript-eslint/visitor-keys/-/visitor-keys-8.71.0.tgz",
      "integrity": "sha512-8eQ9R218XORK+KLosnf4bu/QsUXvUyVwTbArg7/0NMB1Pu87OJKvj4nhFblkYE8gQV73mW1dx1ptlPCkwRGa7A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@typescript-eslint/types": "8.71.0",
        "eslint-visitor-keys": "^5.0.0"
      },
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      }
    },
    "node_modules/@vitest/mocker": {
      "version": "5.0.2",
      "resolved": "https://registry.npmjs.org/@vitest/mocker/-/mocker-5.0.2.tgz",
      "integrity": "sha512-Z5FS00Q1SJHkB35xATsmWGdQ5WA1/0MV3CDjqyv7GavHv1OfOj145MNfHOlHk7QLes21dKFDHr8EO2zvL+9WGA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@jridgewell/trace-mapping": "0.3.31",
        "@vitest/spy": "5.0.2",
        "estree-walker": "^3.0.3",
        "magic-string": "^1.2.3"
      },
      "funding": {
        "url": "https://opencollective.com/vitest"
      },
      "peerDependencies": {
        "msw": "^2.4.9",
        "vite": "^6.0.0 || ^7.0.0 || ^8.0.0"
      },
      "peerDependenciesMeta": {
        "msw": {
          "optional": true
        },
        "vite": {
          "optional": true
        }
      }
    },
    "node_modules/@vitest/spy": {
      "version": "5.0.2",
      "resolved": "https://registry.npmjs.org/@vitest/spy/-/spy-5.0.2.tgz",
      "integrity": "sha512-Ijc7T1nT9efNb5LxvjaBrEqw3f/QwUv5EE0nKqZxgqsaV/FxAAZ8baGylA8X/Z2oS4Lp+K74Jr6dTJsDKxJDeg==",
      "dev": true,
      "license": "MIT",
      "funding": {
        "url": "https://opencollective.com/vitest"
      }
    },
    "node_modules/accepts": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/accepts/-/accepts-2.0.0.tgz",
      "integrity": "sha512-5cvg6CtKwfgdmVqY1WIiXKc3Q1bkRqGLi+2W/6ao+6Y7gu/RCwRuAhGEzh5B4KlszSuTLgZYuqFqo5bImjNKng==",
      "license": "MIT",
      "dependencies": {
        "mime-types": "^3.0.0",
        "negotiator": "^1.0.0"
      },
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/acorn": {
      "version": "8.18.0",
      "resolved": "https://registry.npmjs.org/acorn/-/acorn-8.18.0.tgz",
      "integrity": "sha512-lGq+9yr1/GuAWaVYIHRjvvySG5/4VfKIvC8EWxStPdcDh/Ka7FG3twP6v4d5BkravUilhIAsG4Qj83t02LWUPQ==",
      "dev": true,
      "license": "MIT",
      "bin": {
        "acorn": "bin/acorn"
      },
      "engines": {
        "node": ">=0.4.0"
      }
    },
    "node_modules/acorn-jsx": {
      "version": "5.3.2",
      "resolved": "https://registry.npmjs.org/acorn-jsx/-/acorn-jsx-5.3.2.tgz",
      "integrity": "sha512-rq9s+JNhf0IChjtDXxllJ7g41oZk5SlXtp0LHwyA5cejwn7vKmKp4pPri6YEePv2PU65sAsegbXtIinmDFDXgQ==",
      "dev": true,
      "license": "MIT",
      "peerDependencies": {
        "acorn": "^6.0.0 || ^7.0.0 || ^8.0.0"
      }
    },
    "node_modules/agent-base": {
      "version": "7.1.4",
      "resolved": "https://registry.npmjs.org/agent-base/-/agent-base-7.1.4.tgz",
      "integrity": "sha512-MnA+YT8fwfJPgBx3m60MNqakm30XOkyIoH1y6huTQvC0PwZG7ki8NacLBcrPbNoo8vEZy7Jpuk7+jMO+CUovTQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 14"
      }
    },
    "node_modules/ajv": {
      "version": "6.15.0",
      "resolved": "https://registry.npmjs.org/ajv/-/ajv-6.15.0.tgz",
      "integrity": "sha512-fgFx7Hfoq60ytK2c7DhnF8jIvzYgOMxfugjLOSMHjLIPgenqa7S7oaagATUq99mV6IYvN2tRmC0wnTYX6iPbMw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "fast-deep-equal": "^3.1.1",
        "fast-json-stable-stringify": "^2.0.0",
        "json-schema-traverse": "^0.4.1",
        "uri-js": "^4.2.2"
      },
      "funding": {
        "type": "github",
        "url": "https://github.com/sponsors/epoberezkin"
      }
    },
    "node_modules/ansi-regex": {
      "version": "6.4.0",
      "resolved": "https://registry.npmjs.org/ansi-regex/-/ansi-regex-6.4.0.tgz",
      "integrity": "sha512-KzTVk2tCWAHtYrvvvaP8bJKJq2pVinhLcGEQdtLIYPbmNGNyYe8QwNaTUYQp2J7/vIsUKt5QCqAfUkYyG9DkOw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12"
      },
      "funding": {
        "url": "https://github.com/chalk/ansi-regex?sponsor=1"
      }
    },
    "node_modules/ansi-styles": {
      "version": "6.2.3",
      "resolved": "https://registry.npmjs.org/ansi-styles/-/ansi-styles-6.2.3.tgz",
      "integrity": "sha512-4Dj6M28JB+oAH8kFkTLUo+a2jwOFkuqb3yucU0CANcRRUbxS0cP0nZYCGjcc3BNXwRIsUVmDGgzawme7zvJHvg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12"
      },
      "funding": {
        "url": "https://github.com/chalk/ansi-styles?sponsor=1"
      }
    },
    "node_modules/archiver": {
      "version": "5.3.2",
      "resolved": "https://registry.npmjs.org/archiver/-/archiver-5.3.2.tgz",
      "integrity": "sha512-+25nxyyznAXF7Nef3y0EbBeqmGZgeN/BxHX29Rs39djAfaFalmQ89SE6CWyDCHzGL0yt/ycBtNOmGTW0FyGWNw==",
      "license": "MIT",
      "dependencies": {
        "archiver-utils": "^2.1.0",
        "async": "^3.2.4",
        "buffer-crc32": "^0.2.1",
        "readable-stream": "^3.6.0",
        "readdir-glob": "^1.1.2",
        "tar-stream": "^2.2.0",
        "zip-stream": "^4.1.0"
      },
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/archiver-utils": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/archiver-utils/-/archiver-utils-2.1.0.tgz",
      "integrity": "sha512-bEL/yUb/fNNiNTuUz979Z0Yg5L+LzLxGJz8x79lYmR54fmTIb6ob/hNQgkQnIUDWIFjZVQwl9Xs356I6BAMHfw==",
      "license": "MIT",
      "dependencies": {
        "glob": "^7.1.4",
        "graceful-fs": "^4.2.0",
        "lazystream": "^1.0.0",
        "lodash.defaults": "^4.2.0",
        "lodash.difference": "^4.5.0",
        "lodash.flatten": "^4.4.0",
        "lodash.isplainobject": "^4.0.6",
        "lodash.union": "^4.6.0",
        "normalize-path": "^3.0.0",
        "readable-stream": "^2.0.0"
      },
      "engines": {
        "node": ">= 6"
      }
    },
    "node_modules/archiver-utils/node_modules/readable-stream": {
      "version": "2.3.8",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-2.3.8.tgz",
      "integrity": "sha512-8p0AUk4XODgIewSi0l8Epjs+EVnWiK7NoDIEGU0HhE7+ZyY8D1IMY7odu5lRrFXGg71L15KG8QrPmum45RTtdA==",
      "license": "MIT",
      "dependencies": {
        "core-util-is": "~1.0.0",
        "inherits": "~2.0.3",
        "isarray": "~1.0.0",
        "process-nextick-args": "~2.0.0",
        "safe-buffer": "~5.1.1",
        "string_decoder": "~1.1.1",
        "util-deprecate": "~1.0.1"
      }
    },
    "node_modules/archiver-utils/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "license": "MIT"
    },
    "node_modules/archiver-utils/node_modules/string_decoder": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.1.1.tgz",
      "integrity": "sha512-n/ShnvDi6FHbbVfviro+WojiFzv+s8MPMHBczVePfUpDJLwoLT0ht1l4YwBCbi8pJAveEEdnkHyPyTP/mzRfwg==",
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.1.0"
      }
    },
    "node_modules/aria-query": {
      "version": "5.3.0",
      "resolved": "https://registry.npmjs.org/aria-query/-/aria-query-5.3.0.tgz",
      "integrity": "sha512-b0P0sZPKtyu8HkeRAfCq0IfURZK+SuwMjY1UXGBU27wpAiTwQAIlq56IbIO+ytk/JjS1fMR14ee5WBBfKi5J6A==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "dequal": "^2.0.3"
      }
    },
    "node_modules/asap": {
      "version": "2.0.6",
      "resolved": "https://registry.npmjs.org/asap/-/asap-2.0.6.tgz",
      "integrity": "sha512-BSHWgDSAiKs50o2Re8ppvp3seVHXSRM44cdSsT9FfNEUUZLOGWVCsiWaRPWM1Znn+mqZ1OfVZ3z3DWEzSp7hRA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/assertion-error": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/assertion-error/-/assertion-error-2.0.1.tgz",
      "integrity": "sha512-Izi8RQcffqCeNVgFigKli1ssklIbpHnCYc6AknXGYoB6grJqyeby7jv12JUQgmTAnIDnbck1uxksT4dzN3PWBA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/async": {
      "version": "3.2.6",
      "resolved": "https://registry.npmjs.org/async/-/async-3.2.6.tgz",
      "integrity": "sha512-htCUDlxyyCLMgaM3xXg0C0LW2xqfuQ6p05pCEIsXuyQ+a1koYKTuBMzRNwmybfLgvJDMd0r1LTn4+E0Ti6C2AA==",
      "license": "MIT"
    },
    "node_modules/async-mutex": {
      "version": "0.5.0",
      "resolved": "https://registry.npmjs.org/async-mutex/-/async-mutex-0.5.0.tgz",
      "integrity": "sha512-1A94B18jkJ3DYq284ohPxoXbfTA5HsQ7/Mf4DEhcyLx3Bz27Rh59iScbB6EPiP+B+joue6YCxcMXSbFC1tZKwA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "tslib": "^2.4.0"
      }
    },
    "node_modules/asynckit": {
      "version": "0.4.0",
      "resolved": "https://registry.npmjs.org/asynckit/-/asynckit-0.4.0.tgz",
      "integrity": "sha512-Oei9OH4tRh0YqU3GxhX79dM/mwVgvbZJaSNaRk+bshkj0S5cfHcgYakreBjrHwatXKbz+IoIdYLxrKim2MjW0Q==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/atomic-sleep": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/atomic-sleep/-/atomic-sleep-1.0.0.tgz",
      "integrity": "sha512-kNOjDqAh7px0XWNI+4QbzoiR/nTkHAWNud2uvnJquD1/x5a7EQZMJT0AczqK0Qn67oY/TTQ1LbUKajZpp3I9tQ==",
      "license": "MIT",
      "engines": {
        "node": ">=8.0.0"
      }
    },
    "node_modules/b4a": {
      "version": "1.9.0",
      "resolved": "https://registry.npmjs.org/b4a/-/b4a-1.9.0.tgz",
      "integrity": "sha512-dpfcF9fDNR6++cthXR67iyhgqWy9CBouAvIWhIntzBG6cvK/cnIPiZQjBwi/ZqjjBEDGfoNDtmB0kTjroOJ3pQ==",
      "dev": true,
      "license": "Apache-2.0",
      "peerDependencies": {
        "react-native-b4a": "*"
      },
      "peerDependenciesMeta": {
        "react-native-b4a": {
          "optional": true
        }
      }
    },
    "node_modules/balanced-match": {
      "version": "4.0.4",
      "resolved": "https://registry.npmjs.org/balanced-match/-/balanced-match-4.0.4.tgz",
      "integrity": "sha512-BLrgEcRTwX2o6gGxGOCNyMvGSp35YofuYzw9h1IMTRmKqttAZZVU67bdb9Pr2vUHA8+j3i2tJfjO6C6+4myGTA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "18 || 20 || >=22"
      }
    },
    "node_modules/barcode-detector": {
      "version": "3.2.2",
      "resolved": "https://registry.npmjs.org/barcode-detector/-/barcode-detector-3.2.2.tgz",
      "integrity": "sha512-/4QOrrNrCRmDSBWiiP4aC72dnkuXUEdcFRidHgbPRXUpy82XcCMvJssI6fEs6JT42LS7DvBVZO70qasJbYKyrA==",
      "license": "MIT",
      "dependencies": {
        "zxing-wasm": "3.1.3"
      }
    },
    "node_modules/bare-events": {
      "version": "2.9.2",
      "resolved": "https://registry.npmjs.org/bare-events/-/bare-events-2.9.2.tgz",
      "integrity": "sha512-AIPKioV7/Y/8KfZ3AAhjPJxLLbY49S64Ym5DakZlUg75qQiTgUq9hEJoEwa4eUezPUlXRy/i5NpsKvo9jgKmoA==",
      "dev": true,
      "license": "Apache-2.0",
      "peerDependencies": {
        "bare-abort-controller": "*"
      },
      "peerDependenciesMeta": {
        "bare-abort-controller": {
          "optional": true
        }
      }
    },
    "node_modules/bare-fs": {
      "version": "4.8.2",
      "resolved": "https://registry.npmjs.org/bare-fs/-/bare-fs-4.8.2.tgz",
      "integrity": "sha512-+ZI68KHMUvosXfKbg/UOHK0tbCdRnegbvPEdEcZ3Nd6TetieQsJPRXBRXPdLyy8+3VSEbPXtsumTpEtt78xv9w==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "bare-events": "^2.5.4",
        "bare-path": "^3.0.0",
        "bare-stream": "^2.6.4",
        "bare-url": "^2.2.2",
        "fast-fifo": "^1.3.2"
      },
      "engines": {
        "bare": ">=1.28.0"
      },
      "peerDependencies": {
        "bare-buffer": "*"
      },
      "peerDependenciesMeta": {
        "bare-buffer": {
          "optional": true
        }
      }
    },
    "node_modules/bare-path": {
      "version": "3.1.2",
      "resolved": "https://registry.npmjs.org/bare-path/-/bare-path-3.1.2.tgz",
      "integrity": "sha512-ZyKbsuuqK6Ag0K8pX6V5Txq6XeJRvY+wXucnFGRjiyVYP9YWDpIQugk/b+enRYrEYBJaqLzghRQpXPMR7341Nw==",
      "dev": true,
      "license": "Apache-2.0"
    },
    "node_modules/bare-stream": {
      "version": "2.13.4",
      "resolved": "https://registry.npmjs.org/bare-stream/-/bare-stream-2.13.4.tgz",
      "integrity": "sha512-PcrQ8lVLbiJscNm1Kez+Yp4Gy4AHGcN1lzwjvf5NybWen7VvEgUfyfnXYJ2zNqWnzOfCb1Abq6lH8ti0syQszA==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "b4a": "^1.8.1",
        "streamx": "^2.25.0",
        "teex": "^1.0.1"
      },
      "peerDependencies": {
        "bare-abort-controller": "*",
        "bare-buffer": "*",
        "bare-events": "*"
      },
      "peerDependenciesMeta": {
        "bare-abort-controller": {
          "optional": true
        },
        "bare-buffer": {
          "optional": true
        },
        "bare-events": {
          "optional": true
        }
      }
    },
    "node_modules/bare-url": {
      "version": "2.5.4",
      "resolved": "https://registry.npmjs.org/bare-url/-/bare-url-2.5.4.tgz",
      "integrity": "sha512-Gxa7UVWBr0/edU1b+TJhn/AZvMQUj9OGspvYsaTYQrAbZA4BOTZGL3LiZxvD+CeMlDH4juwD84+eTAp/bLYW5g==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "bare-path": "^3.0.0"
      }
    },
    "node_modules/base64-js": {
      "version": "1.5.1",
      "resolved": "https://registry.npmjs.org/base64-js/-/base64-js-1.5.1.tgz",
      "integrity": "sha512-AKpaYlHn8t4SVbOHCy+b5+KKgvR4vrsD8vbvrbiQJps7fKDTkjkDry6ji0rUJjC0kzbNePLwzxq8iypo41qeWA==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "MIT"
    },
    "node_modules/baseline-browser-mapping": {
      "version": "2.11.27",
      "resolved": "https://registry.npmjs.org/baseline-browser-mapping/-/baseline-browser-mapping-2.11.27.tgz",
      "integrity": "sha512-ElY12DaROGuan+lMmZ8Cvo/ZUbXPe7Enc/9VU/b1T3Kp4dwytRcNdR8DoSJN5SNJT/CuvcCA0DHDVmMOCePdRQ==",
      "dev": true,
      "license": "Apache-2.0",
      "bin": {
        "baseline-browser-mapping": "dist/cli.cjs"
      },
      "engines": {
        "node": ">=6.0.0"
      }
    },
    "node_modules/bcryptjs": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/bcryptjs/-/bcryptjs-3.0.3.tgz",
      "integrity": "sha512-GlF5wPWnSa/X5LKM1o0wz0suXIINz1iHRLvTS+sLyi7XPbe5ycmYI3DlZqVGZZtDgl4DmasFg7gOB3JYbphV5g==",
      "license": "BSD-3-Clause",
      "bin": {
        "bcrypt": "bin/bcrypt"
      }
    },
    "node_modules/bidi-js": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/bidi-js/-/bidi-js-1.1.0.tgz",
      "integrity": "sha512-fX1Onk0tdVPC7obPWB5EbJ1z7NVhLq4m2xZLq2YXBkxzMXIGRpNMU88n0EPgWseKl12J7zXs7qrDxPK4sRs2fg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "require-from-string": "^2.0.2"
      }
    },
    "node_modules/big-integer": {
      "version": "1.6.52",
      "resolved": "https://registry.npmjs.org/big-integer/-/big-integer-1.6.52.tgz",
      "integrity": "sha512-QxD8cf2eVqJOOz63z6JIN9BzvVs/dlySa5HGSBH5xtR8dPteIRQnBxxKqkNTiT6jbDTF6jAfrd4oMcND9RGbQg==",
      "license": "Unlicense",
      "engines": {
        "node": ">=0.6"
      }
    },
    "node_modules/binary": {
      "version": "0.3.0",
      "resolved": "https://registry.npmjs.org/binary/-/binary-0.3.0.tgz",
      "integrity": "sha512-D4H1y5KYwpJgK8wk1Cue5LLPgmwHKYSChkbspQg5JtVuR5ulGckxfR62H3AE9UDkdMC8yyXlqYihuz3Aqg2XZg==",
      "license": "MIT",
      "dependencies": {
        "buffers": "~0.1.1",
        "chainsaw": "~0.1.0"
      },
      "engines": {
        "node": "*"
      }
    },
    "node_modules/bl": {
      "version": "4.1.0",
      "resolved": "https://registry.npmjs.org/bl/-/bl-4.1.0.tgz",
      "integrity": "sha512-1W07cM9gS6DcLperZfFSj+bWLtaPGSOHWhPiGzXmvVJbRLdG82sH/Kn8EtW1VqWVA54AKf2h5k5BbnIbwF3h6w==",
      "license": "MIT",
      "dependencies": {
        "buffer": "^5.5.0",
        "inherits": "^2.0.4",
        "readable-stream": "^3.4.0"
      }
    },
    "node_modules/bluebird": {
      "version": "3.4.7",
      "resolved": "https://registry.npmjs.org/bluebird/-/bluebird-3.4.7.tgz",
      "integrity": "sha512-iD3898SR7sWVRHbiQv+sHUtHnMvC1o3nW5rAcqnq3uOn07DSAppZYUkIGslDz6gXC7HfunPe7YVBgoEJASPcHA==",
      "license": "MIT"
    },
    "node_modules/body-parser": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/body-parser/-/body-parser-2.3.0.tgz",
      "integrity": "sha512-2cGmJupaNgg+QUwVLAucDuWuoMZ6EX9iHDRswZ5lsNYEmwPaRknMPCLZz07yTzVq/83p4o/wzbDZbBrTvGGTIw==",
      "license": "MIT",
      "dependencies": {
        "bytes": "^3.1.2",
        "content-type": "^2.0.0",
        "debug": "^4.4.3",
        "http-errors": "^2.0.1",
        "iconv-lite": "^0.7.2",
        "on-finished": "^2.4.1",
        "qs": "^6.15.2",
        "raw-body": "^3.0.2",
        "type-is": "^2.1.0"
      },
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/body-parser/node_modules/content-type": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/content-type/-/content-type-2.1.0.tgz",
      "integrity": "sha512-mj7UPXE0jaqaOsukNZRUEfEi2AcL7C/vwmwcHV0O97eO1E1pxBZuyjlZrx5seTaNBg1U6+o35wpa35Qfcc+7ag==",
      "license": "MIT",
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/brace-expansion": {
      "version": "5.0.12",
      "resolved": "https://registry.npmjs.org/brace-expansion/-/brace-expansion-5.0.12.tgz",
      "integrity": "sha512-YovQ3rzhaLMIrDjNDMkNS01tea93qhEhG5xy8f6+R0l+dw3Ki+5sCoIoI942iuLZTHWogWktgwVDhU09iNEimQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "balanced-match": "^4.0.2"
      },
      "engines": {
        "node": "20 || >=22"
      }
    },
    "node_modules/browserslist": {
      "version": "4.29.3",
      "resolved": "https://registry.npmjs.org/browserslist/-/browserslist-4.29.3.tgz",
      "integrity": "sha512-1R4kiYKXGViqEN0CnoDrXc1StD9niAwu+j2dukWzrD4bJgsD4lDmEp0CRbc6E/vYJIfTHwPmwyaKtVSudICdPA==",
      "dev": true,
      "funding": [
        {
          "type": "opencollective",
          "url": "https://opencollective.com/browserslist"
        },
        {
          "type": "tidelift",
          "url": "https://tidelift.com/funding/github/npm/browserslist"
        },
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "MIT",
      "dependencies": {
        "baseline-browser-mapping": "^2.11.26",
        "caniuse-lite": "^1.0.30001813",
        "electron-to-chromium": "^1.5.439",
        "node-releases": "^2.0.57",
        "update-browserslist-db": "^1.3.3"
      },
      "bin": {
        "browserslist": "cli.js"
      },
      "engines": {
        "node": "^6 || ^7 || ^8 || ^9 || ^10 || ^11 || ^12 || >=13.7"
      }
    },
    "node_modules/bson": {
      "version": "7.3.3",
      "resolved": "https://registry.npmjs.org/bson/-/bson-7.3.3.tgz",
      "integrity": "sha512-oz3LwE3qGEhTCSyhzQRLY3Bj1NLOsjFMf6tcmY5J8M+3R7EVcmoBfSHWvjUK3yXCLDUsGpIuB3aQL4nDZ1EV/g==",
      "license": "Apache-2.0",
      "engines": {
        "node": ">=20.19.0"
      }
    },
    "node_modules/buffer": {
      "version": "5.7.1",
      "resolved": "https://registry.npmjs.org/buffer/-/buffer-5.7.1.tgz",
      "integrity": "sha512-EHcyIPBQ4BSGlvjB16k5KgAJ27CIsHY/2JBmCRReo48y9rQ3MaUzWX3KVlBa4U7MyX02HdVj0K7C3WaB3ju7FQ==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "MIT",
      "dependencies": {
        "base64-js": "^1.3.1",
        "ieee754": "^1.1.13"
      }
    },
    "node_modules/buffer-crc32": {
      "version": "0.2.13",
      "resolved": "https://registry.npmjs.org/buffer-crc32/-/buffer-crc32-0.2.13.tgz",
      "integrity": "sha512-VO9Ht/+p3SN7SKWqcrgEzjGbRSJYTx+Q1pTQC0wrWqHx0vpJraQ6GtHx8tvcg1rlK1byhU5gccxgOgj7B0TDkQ==",
      "license": "MIT",
      "engines": {
        "node": "*"
      }
    },
    "node_modules/buffer-equal-constant-time": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/buffer-equal-constant-time/-/buffer-equal-constant-time-1.0.1.tgz",
      "integrity": "sha512-zRpUiDwd/xk6ADqPMATG8vc9VPrkck7T07OIx0gnjmJAnHnTVXNQG3vfvWNuiZIkwu9KrKdA1iJKfsfTVxE6NA==",
      "license": "BSD-3-Clause"
    },
    "node_modules/buffer-indexof-polyfill": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/buffer-indexof-polyfill/-/buffer-indexof-polyfill-1.0.2.tgz",
      "integrity": "sha512-I7wzHwA3t1/lwXQh+A5PbNvJxgfo5r3xulgpYDB5zckTu/Z9oUK9biouBKQUjEqzaz3HnAT6TYoovmE+GqSf7A==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10"
      }
    },
    "node_modules/buffers": {
      "version": "0.1.1",
      "resolved": "https://registry.npmjs.org/buffers/-/buffers-0.1.1.tgz",
      "integrity": "sha512-9q/rDEGSb/Qsvv2qvzIzdluL5k7AaJOTrw23z9reQthrbF7is4CtlT0DXyO1oei2DCp4uojjzQ7igaSHp1kAEQ==",
      "engines": {
        "node": ">=0.2.0"
      }
    },
    "node_modules/bytes": {
      "version": "3.1.2",
      "resolved": "https://registry.npmjs.org/bytes/-/bytes-3.1.2.tgz",
      "integrity": "sha512-/Nf7TyzTx6S3yRJObOAV7956r8cr2+Oj8AC5dt8wSP3BQAoeX58NoHyCU8P8zGkNXStjTSi6fzO6F0pBdcYbEg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/cacheable": {
      "version": "2.5.0",
      "resolved": "https://registry.npmjs.org/cacheable/-/cacheable-2.5.0.tgz",
      "integrity": "sha512-60cyAOytib/OzBw1JNSoSV/boK1AtHryDIjvVBk7XbN4ugfkM3+Sry7fEjNgPMGgOjuaZPAp8ruZ0Cxafwyq9g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@cacheable/memory": "^2.2.0",
        "@cacheable/utils": "^2.5.0",
        "hookified": "^1.15.0",
        "keyv": "^5.6.0",
        "qified": "^0.10.1"
      }
    },
    "node_modules/call-bind-apply-helpers": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/call-bind-apply-helpers/-/call-bind-apply-helpers-1.0.2.tgz",
      "integrity": "sha512-Sp1ablJ0ivDkSzjcaJdxEunN5/XvksFJ2sMBFfq6x0ryhQV/2b/KwFe21cMpmHtPOSij8K99/wSfoEuTObmuMQ==",
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "function-bind": "^1.1.2"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/call-bound": {
      "version": "1.0.4",
      "resolved": "https://registry.npmjs.org/call-bound/-/call-bound-1.0.4.tgz",
      "integrity": "sha512-+ys997U96po4Kx/ABpBCqhA9EuxJaQWDQg7295H4hBphv3IZg0boBKuwYpt4YXp6MZ5AmZQnU/tyMTlRpaSejg==",
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.2",
        "get-intrinsic": "^1.3.0"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/camelcase": {
      "version": "6.3.0",
      "resolved": "https://registry.npmjs.org/camelcase/-/camelcase-6.3.0.tgz",
      "integrity": "sha512-Gmy6FhYlCY7uOElZUSbxo2UCDH8owEk996gkbrpsgGtrJLM3J7jGxl9Ic7Qwwj4ivOE5AWZWRMecDdF7hqGjFA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/caniuse-lite": {
      "version": "1.0.30001814",
      "resolved": "https://registry.npmjs.org/caniuse-lite/-/caniuse-lite-1.0.30001814.tgz",
      "integrity": "sha512-/Uaf1lAzr59XcMpW0o96WoEfr+VXK2OX4U9AgFoiSHsVJ4HppnIFUjtYzsyDH2+tgANaQb2/oxYGwCPapN1FpA==",
      "dev": true,
      "funding": [
        {
          "type": "opencollective",
          "url": "https://opencollective.com/browserslist"
        },
        {
          "type": "tidelift",
          "url": "https://tidelift.com/funding/github/npm/caniuse-lite"
        },
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "CC-BY-4.0"
    },
    "node_modules/chai": {
      "version": "6.2.2",
      "resolved": "https://registry.npmjs.org/chai/-/chai-6.2.2.tgz",
      "integrity": "sha512-NUPRluOfOiTKBKvWPtSD4PhFvWCqOi0BGStNWs57X9js7XGTprSmFoz5F0tWhR4WPjNeR9jXqdC7/UpSJTnlRg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/chainsaw": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/chainsaw/-/chainsaw-0.1.0.tgz",
      "integrity": "sha512-75kWfWt6MEKNC8xYXIdRpDehRYY/tNSgwKaJq+dbbDcxORuVrrQ+SEHoWsniVn9XPYfP4gmdWIeDk/4YNp1rNQ==",
      "license": "MIT/X11",
      "dependencies": {
        "traverse": ">=0.3.0 <0.4"
      },
      "engines": {
        "node": "*"
      }
    },
    "node_modules/chalk": {
      "version": "5.6.2",
      "resolved": "https://registry.npmjs.org/chalk/-/chalk-5.6.2.tgz",
      "integrity": "sha512-7NzBL0rN6fMUW+f7A6Io4h40qQlG+xGmtMxfbnH/K7TAtt8JQWVQK+6g0UXKMeVJoyV5EkkNsErQ8pVD3bLHbA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "^12.17.0 || ^14.13 || >=16.0.0"
      },
      "funding": {
        "url": "https://github.com/chalk/chalk?sponsor=1"
      }
    },
    "node_modules/cliui": {
      "version": "9.0.1",
      "resolved": "https://registry.npmjs.org/cliui/-/cliui-9.0.1.tgz",
      "integrity": "sha512-k7ndgKhwoQveBL+/1tqGJYNz097I7WOvwbmmU2AR5+magtbjPWQTS1C5vzGkBC8Ym8UWRzfKUzUUqFLypY4Q+w==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "string-width": "^7.2.0",
        "strip-ansi": "^7.1.0",
        "wrap-ansi": "^9.0.0"
      },
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/clsx": {
      "version": "2.1.1",
      "resolved": "https://registry.npmjs.org/clsx/-/clsx-2.1.1.tgz",
      "integrity": "sha512-eYm0QWBtUrBWZWG0d386OGAw16Z995PiOVo2B7bjWSbHedGl5e0ZWaq65kOGgUSNesEIDkB9ISbTg/JK9dhCZA==",
      "license": "MIT",
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/color-convert": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/color-convert/-/color-convert-2.0.1.tgz",
      "integrity": "sha512-RRECPsj7iu/xb5oKYcsFHSppFNnsj/52OVTRKb4zP5onXwVF3zVmmToNcOfGC+CRDpfK/U584fMg38ZHCaElKQ==",
      "license": "MIT",
      "dependencies": {
        "color-name": "~1.1.4"
      },
      "engines": {
        "node": ">=7.0.0"
      }
    },
    "node_modules/color-name": {
      "version": "1.1.4",
      "resolved": "https://registry.npmjs.org/color-name/-/color-name-1.1.4.tgz",
      "integrity": "sha512-dOy+3AuW3a2wNbZHIuMZpTcgjGuLU/uBL/ubcZF9OXbDo8ff4O8yVp5Bf0efS8uEoYo5q4Fx7dY9OgQGXgAsQA==",
      "license": "MIT"
    },
    "node_modules/colorette": {
      "version": "2.0.20",
      "resolved": "https://registry.npmjs.org/colorette/-/colorette-2.0.20.tgz",
      "integrity": "sha512-IfEDxwoWIjkeXL1eXcDiow4UbKjhLdq6/EuSVR9GMN7KVH3r9gQ83e73hsz1Nd1T3ijd5xv1wcWRYO+D6kCI2w==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/combined-stream": {
      "version": "1.0.8",
      "resolved": "https://registry.npmjs.org/combined-stream/-/combined-stream-1.0.8.tgz",
      "integrity": "sha512-FQN4MRfuJeHf7cBbBMJFXhKSDq+2kAArBlmRBvcvFE5BB1HZKXtSFASDhdlz9zOYwxh8lDdnvmMOe/+5cdoEdg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "delayed-stream": "~1.0.0"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/commondir": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/commondir/-/commondir-1.0.1.tgz",
      "integrity": "sha512-W9pAhw0ja1Edb5GVdIF1mjZw/ASI0AlShXM83UUGe2DVr5TdAPEA1OA8m/g8zWp9x6On7gqufY+FatDbC3MDQg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/component-emitter": {
      "version": "1.3.1",
      "resolved": "https://registry.npmjs.org/component-emitter/-/component-emitter-1.3.1.tgz",
      "integrity": "sha512-T0+barUSQRTUQASh8bx02dl+DhF54GtIDY13Y3m9oWTklKbb3Wv974meRpeZ3lp1JpLVECWWNHC4vaG2XHXouQ==",
      "dev": true,
      "license": "MIT",
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/compress-commons": {
      "version": "4.1.2",
      "resolved": "https://registry.npmjs.org/compress-commons/-/compress-commons-4.1.2.tgz",
      "integrity": "sha512-D3uMHtGc/fcO1Gt1/L7i1e33VOvD4A9hfQLP+6ewd+BvG/gQ84Yh4oftEhAdjSMgBgwGL+jsppT7JYNpo6MHHg==",
      "license": "MIT",
      "dependencies": {
        "buffer-crc32": "^0.2.13",
        "crc32-stream": "^4.0.2",
        "normalize-path": "^3.0.0",
        "readable-stream": "^3.6.0"
      },
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/concat-map": {
      "version": "0.0.1",
      "resolved": "https://registry.npmjs.org/concat-map/-/concat-map-0.0.1.tgz",
      "integrity": "sha512-/Srv4dswyQNBfohGpz9o6Yb3Gz3SrUDqBH5rTuhGR7ahtlbYKnVxw2bCFMRljaA7EXHaXZ8wsHdodFvbkhKmqg==",
      "license": "MIT"
    },
    "node_modules/concurrently": {
      "version": "10.0.5",
      "resolved": "https://registry.npmjs.org/concurrently/-/concurrently-10.0.5.tgz",
      "integrity": "sha512-JaP/CoftUrCcAFW/g//RbgEGwlelnEae6cfBLgH6ZdO6s8jPkn6p9SB9u6pdVxYXoiSnFqseOlHfrEfF82TVOg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "chalk": "5.6.2",
        "rxjs": "7.8.2",
        "shell-quote": "1.9.0",
        "supports-color": "10.2.2",
        "tree-kill": "1.2.2",
        "yargs": "18.0.0"
      },
      "bin": {
        "conc": "dist/bin/index.js",
        "concurrently": "dist/bin/index.js"
      },
      "engines": {
        "node": ">=22"
      },
      "funding": {
        "url": "https://github.com/open-cli-tools/concurrently?sponsor=1"
      }
    },
    "node_modules/content-disposition": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/content-disposition/-/content-disposition-1.1.0.tgz",
      "integrity": "sha512-5jRCH9Z/+DRP7rkvY83B+yGIGX96OYdJmzngqnw2SBSxqCFPd0w2km3s5iawpGX8krnwSGmF0FW5Nhr0Hfai3g==",
      "license": "MIT",
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/content-type": {
      "version": "1.0.5",
      "resolved": "https://registry.npmjs.org/content-type/-/content-type-1.0.5.tgz",
      "integrity": "sha512-nTjqfcBFEipKdXCv4YDQWCfmcLZKm81ldF0pAopTvyrFGVbcR6P/VAAd5G7N+0tTr8QqiU0tFadD6FK4NtJwOA==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/convert-source-map": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/convert-source-map/-/convert-source-map-2.0.0.tgz",
      "integrity": "sha512-Kvp459HrV2FEJ1CAsi1Ku+MY3kasH19TFykTz2xWmMeq6bk2NU3XXvfJ+Q61m0xktWwt+1HSYf3JZsTms3aRJg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/cookie": {
      "version": "0.7.2",
      "resolved": "https://registry.npmjs.org/cookie/-/cookie-0.7.2.tgz",
      "integrity": "sha512-yki5XnKuf750l50uGTllt6kKILY4nQ1eNIQatoXEByZ5dWgnKqbnqmTrBE5B4N7lrMJKQ2ytWMiTO2o0v6Ew/w==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/cookie-es": {
      "version": "3.1.1",
      "resolved": "https://registry.npmjs.org/cookie-es/-/cookie-es-3.1.1.tgz",
      "integrity": "sha512-UaXxwISYJPTr9hwQxMFYZ7kNhSXboMXP+Z3TRX6f1/NyaGPfuNUZOWP1pUEb75B2HjfklIYLVRfWiFZJyC6Npg==",
      "license": "MIT"
    },
    "node_modules/cookie-parser": {
      "version": "1.4.7",
      "resolved": "https://registry.npmjs.org/cookie-parser/-/cookie-parser-1.4.7.tgz",
      "integrity": "sha512-nGUvgXnotP3BsjiLX2ypbQnWoGUPIIfHQNZkkC668ntrzGWEZVW70HDEB1qnNGMicPje6EttlIgzo51YSwNQGw==",
      "license": "MIT",
      "dependencies": {
        "cookie": "0.7.2",
        "cookie-signature": "1.0.6"
      },
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/cookie-signature": {
      "version": "1.0.6",
      "resolved": "https://registry.npmjs.org/cookie-signature/-/cookie-signature-1.0.6.tgz",
      "integrity": "sha512-QADzlaHc8icV8I7vbaJXJwod9HWYp8uCqf1xa4OfNu1T7JVxQIrUgOWtHdNDtPiywmFbiS12VjotIXLrKM3orQ==",
      "license": "MIT"
    },
    "node_modules/cookiejar": {
      "version": "2.1.4",
      "resolved": "https://registry.npmjs.org/cookiejar/-/cookiejar-2.1.4.tgz",
      "integrity": "sha512-LDx6oHrK+PhzLKJU9j5S7/Y3jM/mUHvD/DeI1WQmJn652iPC5Y4TBzC9l+5OMOXlyTTA+SmVUPm0HQUwpD5Jqw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/core-util-is": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/core-util-is/-/core-util-is-1.0.3.tgz",
      "integrity": "sha512-ZQBvi1DcpJ4GDqanjucZ2Hj3wEO5pZDS89BWbkcrvdxksJorwUDDZamX9ldFkp9aw2lmBDLgkObEA4DWNJ9FYQ==",
      "license": "MIT"
    },
    "node_modules/cors": {
      "version": "2.8.6",
      "resolved": "https://registry.npmjs.org/cors/-/cors-2.8.6.tgz",
      "integrity": "sha512-tJtZBBHA6vjIAaF6EnIaq6laBBP9aq/Y3ouVJjEfoHbRBcHBAHYcMh/w8LDrk2PvIMMq8gmopa5D4V8RmbrxGw==",
      "license": "MIT",
      "dependencies": {
        "object-assign": "^4",
        "vary": "^1"
      },
      "engines": {
        "node": ">= 0.10"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/crc-32": {
      "version": "1.2.2",
      "resolved": "https://registry.npmjs.org/crc-32/-/crc-32-1.2.2.tgz",
      "integrity": "sha512-ROmzCKrTnOwybPcJApAA6WBWij23HVfGVNKqqrZpuyZOHqK2CwHSvpGuyt/UNNvaIjEd8X5IFGp4Mh+Ie1IHJQ==",
      "license": "Apache-2.0",
      "bin": {
        "crc32": "bin/crc32.njs"
      },
      "engines": {
        "node": ">=0.8"
      }
    },
    "node_modules/crc32-stream": {
      "version": "4.0.3",
      "resolved": "https://registry.npmjs.org/crc32-stream/-/crc32-stream-4.0.3.tgz",
      "integrity": "sha512-NT7w2JVU7DFroFdYkeq8cywxrgjPHWkdX1wjpRQXPX5Asews3tA+Ght6lddQO5Mkumffp3X7GEqku3epj2toIw==",
      "license": "MIT",
      "dependencies": {
        "crc-32": "^1.2.0",
        "readable-stream": "^3.4.0"
      },
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/cross-spawn": {
      "version": "7.0.6",
      "resolved": "https://registry.npmjs.org/cross-spawn/-/cross-spawn-7.0.6.tgz",
      "integrity": "sha512-uV2QOWP2nWzsy2aMp8aRibhi9dlzF5Hgh5SHaB9OiTGEyDTiJJyx0uy51QXdyWbtAHNua4XJzUKca3OzKUd3vA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "path-key": "^3.1.0",
        "shebang-command": "^2.0.0",
        "which": "^2.0.1"
      },
      "engines": {
        "node": ">= 8"
      }
    },
    "node_modules/css-tree": {
      "version": "3.2.1",
      "resolved": "https://registry.npmjs.org/css-tree/-/css-tree-3.2.1.tgz",
      "integrity": "sha512-X7sjQzceUhu1u7Y/ylrRZFU2FS6LRiFVp6rKLPg23y3x3c3DOKAwuXGDp+PAGjh6CSnCjYeAul8pcT8bAl+lSA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "mdn-data": "2.27.1",
        "source-map-js": "^1.2.1"
      },
      "engines": {
        "node": "^10 || ^12.20.0 || ^14.13.0 || >=15.0.0"
      }
    },
    "node_modules/css.escape": {
      "version": "1.5.1",
      "resolved": "https://registry.npmjs.org/css.escape/-/css.escape-1.5.1.tgz",
      "integrity": "sha512-YUifsXXuknHlUsmlgyY0PKzgPOr7/FjCePfHNt0jxm83wHZi44VDMQ7/fGNkjY3/jV1MC+1CmZbaHzugyeRtpg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/csstype": {
      "version": "3.2.3",
      "resolved": "https://registry.npmjs.org/csstype/-/csstype-3.2.3.tgz",
      "integrity": "sha512-z1HGKcYy2xA8AGQfwrn0PAy+PB7X/GSj3UVJW9qKyn43xWa+gl5nXmU4qqLMRzWVLFC8KusUX8T/0kCiOYpAIQ==",
      "devOptional": true,
      "license": "MIT"
    },
    "node_modules/data-urls": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/data-urls/-/data-urls-7.0.0.tgz",
      "integrity": "sha512-23XHcCF+coGYevirZceTVD7NdJOqVn+49IHyxgszm+JIiHLoB2TkmPtsYkNWT1pvRSGkc35L6NHs0yHkN2SumA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "whatwg-mimetype": "^5.0.0",
        "whatwg-url": "^16.0.0"
      },
      "engines": {
        "node": "^20.19.0 || ^22.12.0 || >=24.0.0"
      }
    },
    "node_modules/data-urls/node_modules/tr46": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/tr46/-/tr46-6.0.0.tgz",
      "integrity": "sha512-bLVMLPtstlZ4iMQHpFHTR7GAGj2jxi8Dg0s2h2MafAE4uSWF98FC/3MomU51iQAMf8/qDUbKWf5GxuvvVcXEhw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "punycode": "^2.3.1"
      },
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/data-urls/node_modules/webidl-conversions": {
      "version": "8.0.1",
      "resolved": "https://registry.npmjs.org/webidl-conversions/-/webidl-conversions-8.0.1.tgz",
      "integrity": "sha512-BMhLD/Sw+GbJC21C/UgyaZX41nPt8bUTg+jWyDeg7e7YN4xOM05YPSIXceACnXVtqyEw/LMClUQMtMZ+PGGpqQ==",
      "dev": true,
      "license": "BSD-2-Clause",
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/data-urls/node_modules/whatwg-url": {
      "version": "16.0.1",
      "resolved": "https://registry.npmjs.org/whatwg-url/-/whatwg-url-16.0.1.tgz",
      "integrity": "sha512-1to4zXBxmXHV3IiSSEInrreIlu02vUOvrhxJJH5vcxYTBDAx51cqZiKdyTxlecdKNSjj8EcxGBxNf6Vg+945gw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@exodus/bytes": "^1.11.0",
        "tr46": "^6.0.0",
        "webidl-conversions": "^8.0.1"
      },
      "engines": {
        "node": "^20.19.0 || ^22.12.0 || >=24.0.0"
      }
    },
    "node_modules/dateformat": {
      "version": "4.6.3",
      "resolved": "https://registry.npmjs.org/dateformat/-/dateformat-4.6.3.tgz",
      "integrity": "sha512-2P0p0pFGzHS5EMnhdxQi7aJN+iMheud0UhG4dlE1DLAlvL8JHjJJTX/CSm4JXwV0Ka5nGk3zC5mcb5bUQUxxMA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "*"
      }
    },
    "node_modules/dayjs": {
      "version": "1.11.23",
      "resolved": "https://registry.npmjs.org/dayjs/-/dayjs-1.11.23.tgz",
      "integrity": "sha512-QDTCU0M0MxR3hQfnlDJfwekQiaanm1ubOD231u73WBckQ/fsamwRLiE2GBz6D3a/xF1NgfiDLJjXBa1hYOYTtQ==",
      "license": "MIT"
    },
    "node_modules/debug": {
      "version": "4.4.3",
      "resolved": "https://registry.npmjs.org/debug/-/debug-4.4.3.tgz",
      "integrity": "sha512-RGwwWnwQvkVfavKVt22FGLw+xYSdzARwm0ru6DhTVA3umU5hZc28V3kO4stgYryrTlLpuvgI9GiijltAjNbcqA==",
      "license": "MIT",
      "dependencies": {
        "ms": "^2.1.3"
      },
      "engines": {
        "node": ">=6.0"
      },
      "peerDependenciesMeta": {
        "supports-color": {
          "optional": true
        }
      }
    },
    "node_modules/decamelize": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/decamelize/-/decamelize-1.2.0.tgz",
      "integrity": "sha512-z2S+W9X73hAUUki+N+9Za2lBlun89zigOyGrsax+KUQ6wKW4ZoWpEYBkGhQjwAjjDCkWxhY0VKEhk8wzY7F5cA==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/decimal.js": {
      "version": "10.6.0",
      "resolved": "https://registry.npmjs.org/decimal.js/-/decimal.js-10.6.0.tgz",
      "integrity": "sha512-YpgQiITW3JXGntzdUmyUR1V812Hn8T1YVXhCu+wO3OpS4eU9l4YdD3qjyiKdV6mvV29zapkMeD390UVEf2lkUg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/deep-is": {
      "version": "0.1.4",
      "resolved": "https://registry.npmjs.org/deep-is/-/deep-is-0.1.4.tgz",
      "integrity": "sha512-oIPzksmTg4/MriiaYGO+okXDT7ztn/w3Eptv/+gSIdMdKsJo0u4CfYNFJPy+4SKMuCqGw2wxnA+URMg3t8a/bQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/delayed-stream": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/delayed-stream/-/delayed-stream-1.0.0.tgz",
      "integrity": "sha512-ZySD7Nf91aLB0RxL4KGrKHBXl7Eds1DAmEdcoVawXnLD7SDhpNgtuII2aAkg7a7QS41jxPSZ17p4VdGnMHk3MQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.4.0"
      }
    },
    "node_modules/depd": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/depd/-/depd-2.0.0.tgz",
      "integrity": "sha512-g7nH6P6dyDioJogAAGprGpCtVImJhpPk/roCzdb3fIh61/s/nPsfR6onyMwkCAR/OlC3yBC0lESvUoQEAssIrw==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/dequal": {
      "version": "2.0.3",
      "resolved": "https://registry.npmjs.org/dequal/-/dequal-2.0.3.tgz",
      "integrity": "sha512-0je+qPKHEMohvfRTCEo3CrPG6cAzAYgmzKyxRiYSSDkS6eGJdyVJm7WaYA5ECaAD9wLB2T4EEeymA5aFVcYXCA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/detect-libc": {
      "version": "2.1.2",
      "resolved": "https://registry.npmjs.org/detect-libc/-/detect-libc-2.1.2.tgz",
      "integrity": "sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/dezalgo": {
      "version": "1.0.4",
      "resolved": "https://registry.npmjs.org/dezalgo/-/dezalgo-1.0.4.tgz",
      "integrity": "sha512-rXSP0bf+5n0Qonsb+SVVfNfIsimO4HEtmnIpPHY8Q1UCzKlQrDMfdobr8nJOOsRgWCyMRqeSBQzmWUMq7zvVig==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "asap": "^2.0.0",
        "wrappy": "1"
      }
    },
    "node_modules/dijkstrajs": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/dijkstrajs/-/dijkstrajs-1.0.3.tgz",
      "integrity": "sha512-qiSlmBq9+BCdCA/L46dw8Uy93mloxsPSbwnm5yrKn2vMPiy8KyAskTF6zuV/j5BMsmOGZDPs7KjU+mjb670kfA==",
      "license": "MIT"
    },
    "node_modules/dom-accessibility-api": {
      "version": "0.5.16",
      "resolved": "https://registry.npmjs.org/dom-accessibility-api/-/dom-accessibility-api-0.5.16.tgz",
      "integrity": "sha512-X7BJ2yElsnOJ30pZF4uIIDfBEVgF4XEBxL9Bxhy6dnrm5hkzqmsWHGTiHqRiITNhMyFLyAiWndIJP7Z1NTteDg==",
      "dev": true,
      "license": "MIT",
      "peer": true
    },
    "node_modules/dunder-proto": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/dunder-proto/-/dunder-proto-1.0.1.tgz",
      "integrity": "sha512-KIN/nDJBQRcXw0MLVhZE9iQHmG68qAVIBg9CqmUYjmQIhgij9U5MFvrqkUL5FbtyyzZuOeOt0zdeRe4UY7ct+A==",
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.1",
        "es-errors": "^1.3.0",
        "gopd": "^1.2.0"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/duplexer2": {
      "version": "0.1.4",
      "resolved": "https://registry.npmjs.org/duplexer2/-/duplexer2-0.1.4.tgz",
      "integrity": "sha512-asLFVfWWtJ90ZyOUHMqk7/S2w2guQKxUI2itj3d92ADHhxUSbCMGi1f1cBcJ7xM1To+pE/Khbwo1yuNbMEPKeA==",
      "license": "BSD-3-Clause",
      "dependencies": {
        "readable-stream": "^2.0.2"
      }
    },
    "node_modules/duplexer2/node_modules/readable-stream": {
      "version": "2.3.8",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-2.3.8.tgz",
      "integrity": "sha512-8p0AUk4XODgIewSi0l8Epjs+EVnWiK7NoDIEGU0HhE7+ZyY8D1IMY7odu5lRrFXGg71L15KG8QrPmum45RTtdA==",
      "license": "MIT",
      "dependencies": {
        "core-util-is": "~1.0.0",
        "inherits": "~2.0.3",
        "isarray": "~1.0.0",
        "process-nextick-args": "~2.0.0",
        "safe-buffer": "~5.1.1",
        "string_decoder": "~1.1.1",
        "util-deprecate": "~1.0.1"
      }
    },
    "node_modules/duplexer2/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "license": "MIT"
    },
    "node_modules/duplexer2/node_modules/string_decoder": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.1.1.tgz",
      "integrity": "sha512-n/ShnvDi6FHbbVfviro+WojiFzv+s8MPMHBczVePfUpDJLwoLT0ht1l4YwBCbi8pJAveEEdnkHyPyTP/mzRfwg==",
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.1.0"
      }
    },
    "node_modules/ecdsa-sig-formatter": {
      "version": "1.0.11",
      "resolved": "https://registry.npmjs.org/ecdsa-sig-formatter/-/ecdsa-sig-formatter-1.0.11.tgz",
      "integrity": "sha512-nagl3RYrbNv6kQkeJIpt6NJZy8twLB/2vtz6yN9Z4vRKHN4/QZJIEbqohALSgwKdnksuY3k5Addp5lg8sVoVcQ==",
      "license": "Apache-2.0",
      "dependencies": {
        "safe-buffer": "^5.0.1"
      }
    },
    "node_modules/ee-first": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/ee-first/-/ee-first-1.1.1.tgz",
      "integrity": "sha512-WMwm9LhRUo+WUaRN+vRuETqG89IgZphVSNkdFgeb6sS/E4OrDIN7t48CAewSHXc6C8lefD8KKfr5vY61brQlow==",
      "license": "MIT"
    },
    "node_modules/electron-to-chromium": {
      "version": "1.5.444",
      "resolved": "https://registry.npmjs.org/electron-to-chromium/-/electron-to-chromium-1.5.444.tgz",
      "integrity": "sha512-5ss/uJfoDYDHT0lfJzT6FbcskIzROIOPf0BbbFkGcvDzoJU7i//9GDrwwIHQVmIsrAGiF3ihpADBRIsrEFt1rQ==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/emoji-regex": {
      "version": "10.6.0",
      "resolved": "https://registry.npmjs.org/emoji-regex/-/emoji-regex-10.6.0.tgz",
      "integrity": "sha512-toUI84YS5YmxW219erniWD0CIVOo46xGKColeNQRgOzDorgBi1v4D71/OFzgD9GO2UGKIv1C3Sp8DAn0+j5w7A==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/encodeurl": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/encodeurl/-/encodeurl-2.0.0.tgz",
      "integrity": "sha512-Q0n9HRi4m6JuGIV1eFlmvJB7ZEVxu93IrMyiMsGC0lrMJMWzRgx6WGquyfQgZVb31vhGgXnfmPNNXmxnOkRBrg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/end-of-stream": {
      "version": "1.4.5",
      "resolved": "https://registry.npmjs.org/end-of-stream/-/end-of-stream-1.4.5.tgz",
      "integrity": "sha512-ooEGc6HP26xXq/N+GCGOT0JKCLDGrq2bQUZrQ7gyrJiZANJ/8YDTxTpQBXGMn+WbIQXNVpyWymm7KYVICQnyOg==",
      "license": "MIT",
      "dependencies": {
        "once": "^1.4.0"
      }
    },
    "node_modules/enhanced-resolve": {
      "version": "5.26.0",
      "resolved": "https://registry.npmjs.org/enhanced-resolve/-/enhanced-resolve-5.26.0.tgz",
      "integrity": "sha512-9vhedylFonb2YGogzUKX6+Ja72gOJbN1QHAqdrvqLwhdl/QWbKopzoUC9EbQNVsAns/bx/4uyqalrQAoy1IByw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "graceful-fs": "^4.2.4",
        "tapable": "^2.3.3"
      },
      "engines": {
        "node": ">=10.13.0"
      }
    },
    "node_modules/entities": {
      "version": "8.1.0",
      "resolved": "https://registry.npmjs.org/entities/-/entities-8.1.0.tgz",
      "integrity": "sha512-kxL7msIffSuh9aaFAMD7rxAIuTRMAHMeBtgHW2yUdWw732ZNh4MehkF2gdjvtdmikkaIP9bFDDJOPlsvm7avrA==",
      "dev": true,
      "license": "BSD-2-Clause",
      "engines": {
        "node": ">=20.19.0"
      },
      "funding": {
        "url": "https://github.com/fb55/entities?sponsor=1"
      }
    },
    "node_modules/es-define-property": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/es-define-property/-/es-define-property-1.0.1.tgz",
      "integrity": "sha512-e3nRfgfUZ4rNGL232gUgX06QNyyez04KdjFrF+LTRoOXmrOgFKDg4BCdsjW8EnT69eqdYGmRpJwiPVYNrCaW3g==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/es-errors": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/es-errors/-/es-errors-1.3.0.tgz",
      "integrity": "sha512-Zf5H2Kxt2xjTvbJvP2ZWLEICxA6j+hAmMzIlypy4xcBg1vKVnx89Wy0GbS+kf5cwCVFFzdCFh2XSCFNULS6csw==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/es-module-lexer": {
      "version": "2.3.2",
      "resolved": "https://registry.npmjs.org/es-module-lexer/-/es-module-lexer-2.3.2.tgz",
      "integrity": "sha512-poHGpORABojJJucnV9KbOavETW8lBVnphkW77ER5/BQ5Fz7oXSoCNek7IH3vR5nRjdsEz926ibFYX8KtLQmdyw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/es-object-atoms": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/es-object-atoms/-/es-object-atoms-1.1.2.tgz",
      "integrity": "sha512-HWcBoN6NileqtSydK2FqHbS/LoDd2pqrnQHLyJzBj4kOp/ky2MWMN694xOfkK8/SnUsW2DH7EfyVlydKCsm1Zw==",
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/es-set-tostringtag": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/es-set-tostringtag/-/es-set-tostringtag-2.1.0.tgz",
      "integrity": "sha512-j6vWzfrGVfyXxge+O0x5sh6cvxAog0a/4Rdd2K36zCMV5eJ+/+tOAngRO8cODMNWbVRdVlmGZQL2YS3yR8bIUA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "get-intrinsic": "^1.2.6",
        "has-tostringtag": "^1.0.2",
        "hasown": "^2.0.2"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/esbuild": {
      "version": "0.28.2",
      "resolved": "https://registry.npmjs.org/esbuild/-/esbuild-0.28.2.tgz",
      "integrity": "sha512-HKVLS8dvII+xoKW9kmqxbRKrnWEXfJJr/FZhhJmiqIB0e053QNYFqOBouTMO/k5sID4MvCiUCvv8b9M4h32wIA==",
      "dev": true,
      "hasInstallScript": true,
      "license": "MIT",
      "bin": {
        "esbuild": "bin/esbuild"
      },
      "engines": {
        "node": ">=18"
      },
      "optionalDependencies": {
        "@esbuild/aix-ppc64": "0.28.2",
        "@esbuild/android-arm": "0.28.2",
        "@esbuild/android-arm64": "0.28.2",
        "@esbuild/android-x64": "0.28.2",
        "@esbuild/darwin-arm64": "0.28.2",
        "@esbuild/darwin-x64": "0.28.2",
        "@esbuild/freebsd-arm64": "0.28.2",
        "@esbuild/freebsd-x64": "0.28.2",
        "@esbuild/linux-arm": "0.28.2",
        "@esbuild/linux-arm64": "0.28.2",
        "@esbuild/linux-ia32": "0.28.2",
        "@esbuild/linux-loong64": "0.28.2",
        "@esbuild/linux-mips64el": "0.28.2",
        "@esbuild/linux-ppc64": "0.28.2",
        "@esbuild/linux-riscv64": "0.28.2",
        "@esbuild/linux-s390x": "0.28.2",
        "@esbuild/linux-x64": "0.28.2",
        "@esbuild/netbsd-arm64": "0.28.2",
        "@esbuild/netbsd-x64": "0.28.2",
        "@esbuild/openbsd-arm64": "0.28.2",
        "@esbuild/openbsd-x64": "0.28.2",
        "@esbuild/openharmony-arm64": "0.28.2",
        "@esbuild/sunos-x64": "0.28.2",
        "@esbuild/win32-arm64": "0.28.2",
        "@esbuild/win32-ia32": "0.28.2",
        "@esbuild/win32-x64": "0.28.2"
      }
    },
    "node_modules/escalade": {
      "version": "3.2.0",
      "resolved": "https://registry.npmjs.org/escalade/-/escalade-3.2.0.tgz",
      "integrity": "sha512-WUj2qlxaQtO4g6Pq5c29GTcWGDyd8itL8zTlipgECz3JesAiiOKotd8JU6otB3PACgG6xkJUyVhboMS+bje/jA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/escape-html": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/escape-html/-/escape-html-1.0.3.tgz",
      "integrity": "sha512-NiSupZ4OeuGwr68lGIeym/ksIZMJodUGOSCZ/FSnTxcrekbvqrgdUxlJOMpijaKZVjAJrWrGs/6Jy8OMuyj9ow==",
      "license": "MIT"
    },
    "node_modules/escape-string-regexp": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/escape-string-regexp/-/escape-string-regexp-4.0.0.tgz",
      "integrity": "sha512-TtpcNJ3XAzx3Gq8sWRzJaVajRs0uVxA2YAkdb1jm2YkPz4G6egUFAyA3n5vtEIZefPk5Wa4UXbKuS5fKkJWdgA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/eslint": {
      "version": "10.11.0",
      "resolved": "https://registry.npmjs.org/eslint/-/eslint-10.11.0.tgz",
      "integrity": "sha512-P7a6UEEqb9G95MYAtqkmsTbVXIYyzIfl6NGOIJk162PaahFxFyeGcrlXYFSiagECg4sEm8IseJdZBKR3rx6MsQ==",
      "dev": true,
      "license": "MIT",
      "workspaces": [
        "packages/*"
      ],
      "dependencies": {
        "@eslint-community/eslint-utils": "^4.8.0",
        "@eslint-community/regexpp": "^4.12.2",
        "@eslint/config-array": "^0.23.5",
        "@eslint/config-helpers": "^0.7.0",
        "@eslint/core": "^1.2.1",
        "@eslint/plugin-kit": "^0.7.3",
        "@humanfs/node": "^0.16.6",
        "@humanwhocodes/module-importer": "^1.0.1",
        "@humanwhocodes/retry": "^0.4.2",
        "@types/estree": "^1.0.6",
        "ajv": "^6.14.0",
        "cross-spawn": "^7.0.6",
        "debug": "^4.3.2",
        "escape-string-regexp": "^4.0.0",
        "eslint-scope": "^9.1.2",
        "eslint-visitor-keys": "^5.0.1",
        "espree": "^11.2.0",
        "esquery": "^1.7.0",
        "esutils": "^2.0.2",
        "fast-deep-equal": "^3.1.3",
        "file-entry-cache": "11.1.5 || >11.1.6 <12",
        "find-up": "^5.0.0",
        "glob-parent": "^6.0.2",
        "ignore": "^5.2.0",
        "imurmurhash": "^0.1.4",
        "is-glob": "^4.0.0",
        "json-stable-stringify-without-jsonify": "^1.0.1",
        "minimatch": "^10.2.5",
        "natural-compare": "^1.4.0",
        "optionator": "^0.9.3"
      },
      "bin": {
        "eslint": "bin/eslint.js"
      },
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      },
      "funding": {
        "url": "https://eslint.org/donate"
      },
      "peerDependencies": {
        "jiti": "*"
      },
      "peerDependenciesMeta": {
        "jiti": {
          "optional": true
        }
      }
    },
    "node_modules/eslint-plugin-react-hooks": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/eslint-plugin-react-hooks/-/eslint-plugin-react-hooks-7.1.1.tgz",
      "integrity": "sha512-f2I7Gw6JbvCexzIInuSbZpfdQ44D7iqdWX01FKLvrPgqxoE7oMj8clOfto8U6vYiz4yd5oKu39rRSVOe1zRu0g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@babel/core": "^7.24.4",
        "@babel/parser": "^7.24.4",
        "hermes-parser": "^0.25.1",
        "zod": "^3.25.0 || ^4.0.0",
        "zod-validation-error": "^3.5.0 || ^4.0.0"
      },
      "engines": {
        "node": ">=18"
      },
      "peerDependencies": {
        "eslint": "^3.0.0 || ^4.0.0 || ^5.0.0 || ^6.0.0 || ^7.0.0 || ^8.0.0-0 || ^9.0.0 || ^10.0.0"
      }
    },
    "node_modules/eslint-plugin-react-refresh": {
      "version": "0.5.7",
      "resolved": "https://registry.npmjs.org/eslint-plugin-react-refresh/-/eslint-plugin-react-refresh-0.5.7.tgz",
      "integrity": "sha512-XhJSzLljuYD4UjNuFGJu2v7aD3sqNVK12w5/DCUfrNfHWegZo2+TsavNx8MuxMwEquuFAzNbNfXKU0WoZ+YUIg==",
      "dev": true,
      "license": "MIT",
      "peerDependencies": {
        "eslint": "^9 || ^10"
      }
    },
    "node_modules/eslint-scope": {
      "version": "9.1.2",
      "resolved": "https://registry.npmjs.org/eslint-scope/-/eslint-scope-9.1.2.tgz",
      "integrity": "sha512-xS90H51cKw0jltxmvmHy2Iai1LIqrfbw57b79w/J7MfvDfkIkFZ+kj6zC3BjtUwh150HsSSdxXZcsuv72miDFQ==",
      "dev": true,
      "license": "BSD-2-Clause",
      "dependencies": {
        "@types/esrecurse": "^4.3.1",
        "@types/estree": "^1.0.8",
        "esrecurse": "^4.3.0",
        "estraverse": "^5.2.0"
      },
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      },
      "funding": {
        "url": "https://opencollective.com/eslint"
      }
    },
    "node_modules/eslint-visitor-keys": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/eslint-visitor-keys/-/eslint-visitor-keys-5.0.1.tgz",
      "integrity": "sha512-tD40eHxA35h0PEIZNeIjkHoDR4YjjJp34biM0mDvplBe//mB+IHCqHDGV7pxF+7MklTvighcCPPZC7ynWyjdTA==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      },
      "funding": {
        "url": "https://opencollective.com/eslint"
      }
    },
    "node_modules/espree": {
      "version": "11.2.0",
      "resolved": "https://registry.npmjs.org/espree/-/espree-11.2.0.tgz",
      "integrity": "sha512-7p3DrVEIopW1B1avAGLuCSh1jubc01H2JHc8B4qqGblmg5gI9yumBgACjWo4JlIc04ufug4xJ3SQI8HkS/Rgzw==",
      "dev": true,
      "license": "BSD-2-Clause",
      "dependencies": {
        "acorn": "^8.16.0",
        "acorn-jsx": "^5.3.2",
        "eslint-visitor-keys": "^5.0.1"
      },
      "engines": {
        "node": "^20.19.0 || ^22.13.0 || >=24"
      },
      "funding": {
        "url": "https://opencollective.com/eslint"
      }
    },
    "node_modules/esquery": {
      "version": "1.7.0",
      "resolved": "https://registry.npmjs.org/esquery/-/esquery-1.7.0.tgz",
      "integrity": "sha512-Ap6G0WQwcU/LHsvLwON1fAQX9Zp0A2Y6Y/cJBl9r/JbW90Zyg4/zbG6zzKa2OTALELarYHmKu0GhpM5EO+7T0g==",
      "dev": true,
      "license": "BSD-3-Clause",
      "dependencies": {
        "estraverse": "^5.1.0"
      },
      "engines": {
        "node": ">=0.10"
      }
    },
    "node_modules/esrecurse": {
      "version": "4.3.0",
      "resolved": "https://registry.npmjs.org/esrecurse/-/esrecurse-4.3.0.tgz",
      "integrity": "sha512-KmfKL3b6G+RXvP8N1vr3Tq1kL/oCFgn2NYXEtqP8/L3pKapUA4G8cFVaoF3SU323CD4XypR/ffioHmkti6/Tag==",
      "dev": true,
      "license": "BSD-2-Clause",
      "dependencies": {
        "estraverse": "^5.2.0"
      },
      "engines": {
        "node": ">=4.0"
      }
    },
    "node_modules/estraverse": {
      "version": "5.3.0",
      "resolved": "https://registry.npmjs.org/estraverse/-/estraverse-5.3.0.tgz",
      "integrity": "sha512-MMdARuVEQziNTeJD8DgMqmhwR11BRQ/cBP+pLtYdSTnf3MIO8fFeiINEbX36ZdNlfU/7A9f3gUw49B3oQsvwBA==",
      "dev": true,
      "license": "BSD-2-Clause",
      "engines": {
        "node": ">=4.0"
      }
    },
    "node_modules/estree-walker": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/estree-walker/-/estree-walker-3.0.3.tgz",
      "integrity": "sha512-7RUKfXgSMMkzt6ZuXmqapOurLGPPfgj6l9uRZ7lRGolvk0y2yocc35LdcxKC5PQZdn2DMqioAQ2NoWcrTKmm6g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/estree": "^1.0.0"
      }
    },
    "node_modules/esutils": {
      "version": "2.0.3",
      "resolved": "https://registry.npmjs.org/esutils/-/esutils-2.0.3.tgz",
      "integrity": "sha512-kVscqXk4OCp68SZ0dkgEKVi6/8ij300KBWTJq32P/dYeWTSwK41WyTxalN1eRmA5Z9UU/LX9D7FWSmV9SAYx6g==",
      "dev": true,
      "license": "BSD-2-Clause",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/etag": {
      "version": "1.8.1",
      "resolved": "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
      "integrity": "sha512-aIL5Fx7mawVa300al2BnEE4iNvo1qETxLrPI/o05L7z6go7fCw1J6EQmbK4FmJ2AS7kgVF/KEZWufBfdClMcPg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/events-universal": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/events-universal/-/events-universal-1.0.1.tgz",
      "integrity": "sha512-LUd5euvbMLpwOF8m6ivPCbhQeSiYVNb8Vs0fQ8QjXo0JTkEHpz8pxdQf0gStltaPpw0Cca8b39KxvK9cfKRiAw==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "bare-events": "^2.7.0"
      }
    },
    "node_modules/exceljs": {
      "version": "4.4.0",
      "resolved": "https://registry.npmjs.org/exceljs/-/exceljs-4.4.0.tgz",
      "integrity": "sha512-XctvKaEMaj1Ii9oDOqbW/6e1gXknSY4g/aLCDicOXqBE4M0nRWkUu0PTp++UPNzoFY12BNHMfs/VadKIS6llvg==",
      "license": "MIT",
      "dependencies": {
        "archiver": "^5.0.0",
        "dayjs": "^1.8.34",
        "fast-csv": "^4.3.1",
        "jszip": "^3.10.1",
        "readable-stream": "^3.6.0",
        "saxes": "^5.0.1",
        "tmp": "^0.2.0",
        "unzipper": "^0.10.11",
        "uuid": "^8.3.0"
      },
      "engines": {
        "node": ">=8.3.0"
      }
    },
    "node_modules/expect-type": {
      "version": "1.4.0",
      "resolved": "https://registry.npmjs.org/expect-type/-/expect-type-1.4.0.tgz",
      "integrity": "sha512-KfYbmpRm0VbLjEvVa9yGwCi9GI34xvi7A/HXYWQO65CSD2u3MczUJSuwXKFIxlGsgBQizV9q5J9NHj4VG0n+pA==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": ">=12.0.0"
      }
    },
    "node_modules/express": {
      "version": "5.2.1",
      "resolved": "https://registry.npmjs.org/express/-/express-5.2.1.tgz",
      "integrity": "sha512-hIS4idWWai69NezIdRt2xFVofaF4j+6INOpJlVOLDO8zXGpUVEVzIYk12UUi2JzjEzWL3IOAxcTubgz9Po0yXw==",
      "license": "MIT",
      "dependencies": {
        "accepts": "^2.0.0",
        "body-parser": "^2.2.1",
        "content-disposition": "^1.0.0",
        "content-type": "^1.0.5",
        "cookie": "^0.7.1",
        "cookie-signature": "^1.2.1",
        "debug": "^4.4.0",
        "depd": "^2.0.0",
        "encodeurl": "^2.0.0",
        "escape-html": "^1.0.3",
        "etag": "^1.8.1",
        "finalhandler": "^2.1.0",
        "fresh": "^2.0.0",
        "http-errors": "^2.0.0",
        "merge-descriptors": "^2.0.0",
        "mime-types": "^3.0.0",
        "on-finished": "^2.4.1",
        "once": "^1.4.0",
        "parseurl": "^1.3.3",
        "proxy-addr": "^2.0.7",
        "qs": "^6.14.0",
        "range-parser": "^1.2.1",
        "router": "^2.2.0",
        "send": "^1.1.0",
        "serve-static": "^2.2.0",
        "statuses": "^2.0.1",
        "type-is": "^2.0.1",
        "vary": "^1.1.2"
      },
      "engines": {
        "node": ">= 18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/express-rate-limit": {
      "version": "8.7.0",
      "resolved": "https://registry.npmjs.org/express-rate-limit/-/express-rate-limit-8.7.0.tgz",
      "integrity": "sha512-hOwV7WOxXfjRpAM1DSJWZDXx3GhplwD8IfwuwvogD8i1Qnkgosw/H45s4ZnFAUHDAhPjlY9hLBvJhKmGMyY26g==",
      "license": "MIT",
      "dependencies": {
        "debug": "^4.4.3",
        "ip-address": "^10.2.0"
      },
      "engines": {
        "node": ">= 16"
      },
      "funding": {
        "url": "https://github.com/sponsors/express-rate-limit"
      },
      "peerDependencies": {
        "express": ">= 4.11"
      }
    },
    "node_modules/express/node_modules/cookie-signature": {
      "version": "1.2.2",
      "resolved": "https://registry.npmjs.org/cookie-signature/-/cookie-signature-1.2.2.tgz",
      "integrity": "sha512-D76uU73ulSXrD1UXF4KE2TMxVVwhsnCgfAyTg9k8P6KGZjlXKrOLe4dJQKI3Bxi5wjesZoFXJWElNWBjPZMbhg==",
      "license": "MIT",
      "engines": {
        "node": ">=6.6.0"
      }
    },
    "node_modules/fast-copy": {
      "version": "4.1.1",
      "resolved": "https://registry.npmjs.org/fast-copy/-/fast-copy-4.1.1.tgz",
      "integrity": "sha512-A4QTJmuiztpGtr6AMeJts9R4hbj2ZBUwtOaKrG6rw2y7t6+IaJKjz5M3XDs8BUznxDH43FVc6A0y/gWlMl4UtA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/fast-csv": {
      "version": "4.3.6",
      "resolved": "https://registry.npmjs.org/fast-csv/-/fast-csv-4.3.6.tgz",
      "integrity": "sha512-2RNSpuwwsJGP0frGsOmTb9oUF+VkFSM4SyLTDgwf2ciHWTarN0lQTC+F2f/t5J9QjW+c65VFIAAu85GsvMIusw==",
      "license": "MIT",
      "dependencies": {
        "@fast-csv/format": "4.3.5",
        "@fast-csv/parse": "4.3.6"
      },
      "engines": {
        "node": ">=10.0.0"
      }
    },
    "node_modules/fast-deep-equal": {
      "version": "3.1.3",
      "resolved": "https://registry.npmjs.org/fast-deep-equal/-/fast-deep-equal-3.1.3.tgz",
      "integrity": "sha512-f3qQ9oQy9j2AhBe/H9VC91wLmKBCCU/gDOnKNAYG5hswO7BLKj09Hc5HYNz9cGI++xlpDCIgDaitVs03ATR84Q==",
      "devOptional": true,
      "license": "MIT"
    },
    "node_modules/fast-fifo": {
      "version": "1.3.2",
      "resolved": "https://registry.npmjs.org/fast-fifo/-/fast-fifo-1.3.2.tgz",
      "integrity": "sha512-/d9sfos4yxzpwkDkuN7k2SqFKtYNmCTzgfEpz82x34IM9/zc8KGxQoXg1liNC/izpRM/MBdt44Nmx41ZWqk+FQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/fast-json-stable-stringify": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/fast-json-stable-stringify/-/fast-json-stable-stringify-2.1.0.tgz",
      "integrity": "sha512-lhd/wF+Lk98HZoTCtlVraHtfh5XYijIjalXck7saUtuanSDyLMxnHhSXEDJqHxD7msR8D0uCmqlkwjCV8xvwHw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/fast-levenshtein": {
      "version": "2.0.6",
      "resolved": "https://registry.npmjs.org/fast-levenshtein/-/fast-levenshtein-2.0.6.tgz",
      "integrity": "sha512-DCXu6Ifhqcks7TZKY3Hxp3y6qphY5SJZmrWMDrKcERSOXWQdMhU9Ig/PYrzyw/ul9jOIyh0N4M0tbC5hodg8dw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/fast-safe-stringify": {
      "version": "2.1.1",
      "resolved": "https://registry.npmjs.org/fast-safe-stringify/-/fast-safe-stringify-2.1.1.tgz",
      "integrity": "sha512-W+KJc2dmILlPplD/H4K9l9LcAHAfPtP6BY84uVLXQ6Evcz9Lcg33Y2z1IVblT6xdY54PXYVHEv+0Wpq8Io6zkA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/fast-uri": {
      "version": "3.1.8",
      "resolved": "https://registry.npmjs.org/fast-uri/-/fast-uri-3.1.8.tgz",
      "integrity": "sha512-GZMtZUTNRpOVIECoXwLNZS5xUGE+mVNbTB8h/7Rwh2TFWcBQiPzTgyZi05BF9UMZKkLJv8XBRJTlU7zg8+ZfMg==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/fastify"
        },
        {
          "type": "opencollective",
          "url": "https://opencollective.com/fastify"
        }
      ],
      "license": "BSD-3-Clause",
      "optional": true,
      "peer": true
    },
    "node_modules/fdir": {
      "version": "6.5.0",
      "resolved": "https://registry.npmjs.org/fdir/-/fdir-6.5.0.tgz",
      "integrity": "sha512-tIbYtZbucOs0BRGqPJkshJUYdL+SDH7dVM8gjy+ERp3WAUjLEFJE+02kanyHtwjWOnwrKYBiwAmM0p4kLJAnXg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12.0.0"
      },
      "peerDependencies": {
        "picomatch": "^3 || ^4"
      },
      "peerDependenciesMeta": {
        "picomatch": {
          "optional": true
        }
      }
    },
    "node_modules/file-entry-cache": {
      "version": "11.1.5",
      "resolved": "https://registry.npmjs.org/file-entry-cache/-/file-entry-cache-11.1.5.tgz",
      "integrity": "sha512-+PFTHITI08JIGhnNpGNI8T8inUpgZfk3GNEqfT9R2zZV2iFXg3CvqzSl/uEhs7TSGujYRELEANyDvS8Fj7+S7Q==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "flat-cache": "^6.1.23"
      }
    },
    "node_modules/finalhandler": {
      "version": "2.1.1",
      "resolved": "https://registry.npmjs.org/finalhandler/-/finalhandler-2.1.1.tgz",
      "integrity": "sha512-S8KoZgRZN+a5rNwqTxlZZePjT/4cnm0ROV70LedRHZ0p8u9fRID0hJUZQpkKLzro8LfmC8sx23bY6tVNxv8pQA==",
      "license": "MIT",
      "dependencies": {
        "debug": "^4.4.0",
        "encodeurl": "^2.0.0",
        "escape-html": "^1.0.3",
        "on-finished": "^2.4.1",
        "parseurl": "^1.3.3",
        "statuses": "^2.0.1"
      },
      "engines": {
        "node": ">= 18.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/find-cache-dir": {
      "version": "3.3.2",
      "resolved": "https://registry.npmjs.org/find-cache-dir/-/find-cache-dir-3.3.2.tgz",
      "integrity": "sha512-wXZV5emFEjrridIgED11OoUKLxiYjAcqot/NJdAkOhlJ+vGzwhOAfcG5OX1jP+S0PcjEn8bdMJv+g2jwQ3Onig==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "commondir": "^1.0.1",
        "make-dir": "^3.0.2",
        "pkg-dir": "^4.1.0"
      },
      "engines": {
        "node": ">=8"
      },
      "funding": {
        "url": "https://github.com/avajs/find-cache-dir?sponsor=1"
      }
    },
    "node_modules/find-up": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/find-up/-/find-up-5.0.0.tgz",
      "integrity": "sha512-78/PXT1wlLLDgTzDs7sjq9hzz0vXD+zn+7wypEe4fXQxCmdmqfGsEPQxmiCSQI3ajFV91bVSsvNtrJRiW6nGng==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "locate-path": "^6.0.0",
        "path-exists": "^4.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/flat-cache": {
      "version": "6.1.23",
      "resolved": "https://registry.npmjs.org/flat-cache/-/flat-cache-6.1.23.tgz",
      "integrity": "sha512-f++BY9pTk+983xK1FLzlLpmM0i0z+jHmx3QESGkURMXujQZz1k5wzwX6hjnQ8goaD0B+sYnDK1yZ6MTyZfUaqA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "cacheable": "^2.5.0",
        "flatted": "^3.4.2",
        "hookified": "^1.15.0"
      }
    },
    "node_modules/flatted": {
      "version": "3.4.4",
      "resolved": "https://registry.npmjs.org/flatted/-/flatted-3.4.4.tgz",
      "integrity": "sha512-5+ybhBZANEJxaH3X5evAFatUxLfEHSr7n6kYJ+1Qd0mUqr4eu9gIf6GDbWHf8RJijHrjjO8G+la14SlL2SeS1Q==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/follow-redirects": {
      "version": "1.16.0",
      "resolved": "https://registry.npmjs.org/follow-redirects/-/follow-redirects-1.16.0.tgz",
      "integrity": "sha512-y5rN/uOsadFT/JfYwhxRS5R7Qce+g3zG97+JrtFZlC9klX/W5hD7iiLzScI4nZqUS7DNUdhPgw4xI8W2LuXlUw==",
      "dev": true,
      "funding": [
        {
          "type": "individual",
          "url": "https://github.com/sponsors/RubenVerborgh"
        }
      ],
      "license": "MIT",
      "engines": {
        "node": ">=4.0"
      },
      "peerDependenciesMeta": {
        "debug": {
          "optional": true
        }
      }
    },
    "node_modules/form-data": {
      "version": "4.0.6",
      "resolved": "https://registry.npmjs.org/form-data/-/form-data-4.0.6.tgz",
      "integrity": "sha512-vKatAh4SlVfgbv+YtmhiRjhEMJsYpsG1Y2rMQtR+SVSbytsSD1YGzDIcrAJmdFec88u/+VoGmxnl+80gL1tRCQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "asynckit": "^0.4.0",
        "combined-stream": "^1.0.8",
        "es-set-tostringtag": "^2.1.0",
        "hasown": "^2.0.4",
        "mime-types": "^2.1.35"
      },
      "engines": {
        "node": ">= 6"
      }
    },
    "node_modules/form-data/node_modules/mime-db": {
      "version": "1.52.0",
      "resolved": "https://registry.npmjs.org/mime-db/-/mime-db-1.52.0.tgz",
      "integrity": "sha512-sPU4uV7dYlvtWJxwwxHD0PuihVNiE7TyAbQ5SWxDCB9mUYvOgroQOwYQQOKPJ8CIbE+1ETVlOoK1UC2nU3gYvg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/form-data/node_modules/mime-types": {
      "version": "2.1.35",
      "resolved": "https://registry.npmjs.org/mime-types/-/mime-types-2.1.35.tgz",
      "integrity": "sha512-ZDY+bPm5zTTF+YpCrAU9nK0UgICYPT0QtT1NZWFv4s++TNkcgVaT0g6+4R2uI4MjQjzysHB1zxuWL50hzaeXiw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "mime-db": "1.52.0"
      },
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/formidable": {
      "version": "3.5.4",
      "resolved": "https://registry.npmjs.org/formidable/-/formidable-3.5.4.tgz",
      "integrity": "sha512-YikH+7CUTOtP44ZTnUhR7Ic2UASBPOqmaRkRKxRbywPTe5VxF7RRCck4af9wutiZ/QKM5nME9Bie2fFaPz5Gug==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@paralleldrive/cuid2": "^2.2.2",
        "dezalgo": "^1.0.4",
        "once": "^1.4.0"
      },
      "engines": {
        "node": ">=14.0.0"
      },
      "funding": {
        "url": "https://ko-fi.com/tunnckoCore/commissions"
      }
    },
    "node_modules/forwarded": {
      "version": "0.2.0",
      "resolved": "https://registry.npmjs.org/forwarded/-/forwarded-0.2.0.tgz",
      "integrity": "sha512-buRG0fpBtRHSTCOASe6hD258tEubFoRLb4ZNA6NxMVHNw2gOcwHo9wyablzMzOA5z9xA9L1KNjk/Nt6MT9aYow==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/fresh": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/fresh/-/fresh-2.0.0.tgz",
      "integrity": "sha512-Rx/WycZ60HOaqLKAi6cHRKKI7zxWbJ31MhntmtwMoaTeF7XFH9hhBp8vITaMidfljRQ6eYWCKkaTK+ykVJHP2A==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/fs-constants": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/fs-constants/-/fs-constants-1.0.0.tgz",
      "integrity": "sha512-y6OAwoSIf7FyjMIv94u+b5rdheZEjzR63GTyZJm5qh4Bi+2YgwLCcI/fPFZkL5PSixOt6ZNKm+w+Hfp/Bciwow==",
      "license": "MIT"
    },
    "node_modules/fs.realpath": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/fs.realpath/-/fs.realpath-1.0.0.tgz",
      "integrity": "sha512-OO0pH2lK6a0hZnAdau5ItzHPI6pUlvI7jMVnxUQRtw4owF2wk8lOSabtGDCTP4Ggrg2MbGnWO9X8K1t4+fGMDw==",
      "license": "ISC"
    },
    "node_modules/fsevents": {
      "version": "2.3.3",
      "resolved": "https://registry.npmjs.org/fsevents/-/fsevents-2.3.3.tgz",
      "integrity": "sha512-5xoDfX+fL7faATnagmWPpbFtwh/R77WmMMqqHGS65C3vvB0YHrgF+B1YmZ3441tMj5n63k0212XNoJwzlhffQw==",
      "dev": true,
      "hasInstallScript": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": "^8.16.0 || ^10.6.0 || >=11.0.0"
      }
    },
    "node_modules/fstream": {
      "version": "1.0.12",
      "resolved": "https://registry.npmjs.org/fstream/-/fstream-1.0.12.tgz",
      "integrity": "sha512-WvJ193OHa0GHPEL+AycEJgxvBEwyfRkN1vhjca23OaPVMCaLCXTd5qAu82AjTcgP1UJmytkOKb63Ypde7raDIg==",
      "deprecated": "This package is no longer supported.",
      "license": "ISC",
      "dependencies": {
        "graceful-fs": "^4.1.2",
        "inherits": "~2.0.0",
        "mkdirp": ">=0.5 0",
        "rimraf": "2"
      },
      "engines": {
        "node": ">=0.6"
      }
    },
    "node_modules/function-bind": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/function-bind/-/function-bind-1.1.2.tgz",
      "integrity": "sha512-7XHNxH7qX9xG5mIwxkhumTox/MIRNcOgDrxWsMt2pAr23WHp6MrRlN7FBSFpCpr+oVO0F744iUgR82nJMfG2SA==",
      "license": "MIT",
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/gensync": {
      "version": "1.0.0-beta.2",
      "resolved": "https://registry.npmjs.org/gensync/-/gensync-1.0.0-beta.2.tgz",
      "integrity": "sha512-3hN7NaskYvMDLQY55gnW3NQ+mesEAepTqlg+VEbj7zzqEMBVNhzcGYYeqFo/TlYz6eQiFcp1HcsCZO+nGgS8zg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6.9.0"
      }
    },
    "node_modules/get-caller-file": {
      "version": "2.0.5",
      "resolved": "https://registry.npmjs.org/get-caller-file/-/get-caller-file-2.0.5.tgz",
      "integrity": "sha512-DyFP3BM/3YHTQOCUL/w0OZHR0lpKeGrxotcHWcqNEdnltqFwXVfhEBQ94eIo34AfQpo0rGki4cyIiftY06h2Fg==",
      "license": "ISC",
      "engines": {
        "node": "6.* || 8.* || >= 10.*"
      }
    },
    "node_modules/get-east-asian-width": {
      "version": "1.7.0",
      "resolved": "https://registry.npmjs.org/get-east-asian-width/-/get-east-asian-width-1.7.0.tgz",
      "integrity": "sha512-XjH1AECxf0giL2V1aU8vKyRR2ppRUb5c0EvT7zuJTokQ74bNo52zOtghqdWIqrhUD79fo3x0WfKZdOqxF6LG1Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/get-intrinsic": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/get-intrinsic/-/get-intrinsic-1.3.0.tgz",
      "integrity": "sha512-9fSjSaos/fRIVIp+xSJlE6lfwhES7LNtKaCBIamHsjr2na1BiABJPo0mOjjz8GJDURarmCPGqaiVg5mfjb98CQ==",
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.2",
        "es-define-property": "^1.0.1",
        "es-errors": "^1.3.0",
        "es-object-atoms": "^1.1.1",
        "function-bind": "^1.1.2",
        "get-proto": "^1.0.1",
        "gopd": "^1.2.0",
        "has-symbols": "^1.1.0",
        "hasown": "^2.0.2",
        "math-intrinsics": "^1.1.0"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/get-proto": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/get-proto/-/get-proto-1.0.1.tgz",
      "integrity": "sha512-sTSfBjoXBp89JvIKIefqw7U2CCebsc74kiY6awiGogKtoSGbgjYE/G/+l9sF3MWFPNc9IcoOC4ODfKHfxFmp0g==",
      "license": "MIT",
      "dependencies": {
        "dunder-proto": "^1.0.1",
        "es-object-atoms": "^1.0.0"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/glob": {
      "version": "7.2.3",
      "resolved": "https://registry.npmjs.org/glob/-/glob-7.2.3.tgz",
      "integrity": "sha512-nFR0zLpU2YCaRxwoCJvL6UvCH2JFyFVIvwTLsIf21AuHlMskA1hhTdk+LlYJtOlYt9v6dvszD2BGRqBL+iQK9Q==",
      "deprecated": "Old versions of glob are not supported, and contain widely publicized security vulnerabilities, which have been fixed in the current version. Please update. Support for old versions may be purchased (at exorbitant rates) by contacting i@izs.me",
      "license": "ISC",
      "dependencies": {
        "fs.realpath": "^1.0.0",
        "inflight": "^1.0.4",
        "inherits": "2",
        "minimatch": "^3.1.1",
        "once": "^1.3.0",
        "path-is-absolute": "^1.0.0"
      },
      "engines": {
        "node": "*"
      },
      "funding": {
        "url": "https://github.com/sponsors/isaacs"
      }
    },
    "node_modules/glob-parent": {
      "version": "6.0.2",
      "resolved": "https://registry.npmjs.org/glob-parent/-/glob-parent-6.0.2.tgz",
      "integrity": "sha512-XxwI8EOhVQgWp6iDL+3b0r86f4d6AX6zSU55HfB4ydCEuXLXc5FcYeOu+nnGftS4TEju/11rt4KJPTMgbfmv4A==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "is-glob": "^4.0.3"
      },
      "engines": {
        "node": ">=10.13.0"
      }
    },
    "node_modules/glob/node_modules/balanced-match": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/balanced-match/-/balanced-match-1.0.2.tgz",
      "integrity": "sha512-3oSeUO0TMV67hN1AmbXsK4yaqU7tjiHlbxRDZOpH0KW9+CeX4bRAaX0Anxt0tx2MrpRpWwQaPwIlISEJhYU5Pw==",
      "license": "MIT"
    },
    "node_modules/glob/node_modules/brace-expansion": {
      "version": "1.1.21",
      "resolved": "https://registry.npmjs.org/brace-expansion/-/brace-expansion-1.1.21.tgz",
      "integrity": "sha512-9zeA+KLZNNzglF2TPKRQEDyx6Yby7daAkuy8MiPzpXPsYDWi/DRM8jmwUDxokQjYqBpv5DgPiwD4h4ZZSy1Ujw==",
      "license": "MIT",
      "dependencies": {
        "balanced-match": "^1.0.0",
        "concat-map": "0.0.1"
      }
    },
    "node_modules/glob/node_modules/minimatch": {
      "version": "3.1.5",
      "resolved": "https://registry.npmjs.org/minimatch/-/minimatch-3.1.5.tgz",
      "integrity": "sha512-VgjWUsnnT6n+NUk6eZq77zeFdpW2LWDzP6zFGrCbHXiYNul5Dzqk2HHQ5uFH2DNW5Xbp8+jVzaeNt94ssEEl4w==",
      "license": "ISC",
      "dependencies": {
        "brace-expansion": "^1.1.7"
      },
      "engines": {
        "node": "*"
      }
    },
    "node_modules/globals": {
      "version": "17.12.0",
      "resolved": "https://registry.npmjs.org/globals/-/globals-17.12.0.tgz",
      "integrity": "sha512-cezEd/DTyyht9cvSSURyygXPfy04GtWO/5e6ZPvH7fCtjKz9PYOmuawphw1Ctd1f6C+5JypXfGD7ahNMXvevBA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/gopd": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/gopd/-/gopd-1.2.0.tgz",
      "integrity": "sha512-ZUKRh6/kUFoAiTAtTYPZJ3hw9wNxx+BIBOijnlG9PnrJsCcSjs1wyyD6vJpaYtgnzDrKYRSqf3OO6Rfa93xsRg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/graceful-fs": {
      "version": "4.2.11",
      "resolved": "https://registry.npmjs.org/graceful-fs/-/graceful-fs-4.2.11.tgz",
      "integrity": "sha512-RbJ5/jmFcNNCcDV5o9eTnBLJ/HszWV0P73bc+Ff4nS/rJj+YaS6IGyiOL0VoBYX+l1Wrl3k63h/KrH+nhJ0XvQ==",
      "license": "ISC"
    },
    "node_modules/has-symbols": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/has-symbols/-/has-symbols-1.1.0.tgz",
      "integrity": "sha512-1cDNdwJ2Jaohmb3sg4OmKaMBwuC48sYni5HUw2DvsC8LjGTLK9h+eb1X6RyuOHe4hT0ULCW68iomhjUoKUqlPQ==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/has-tostringtag": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/has-tostringtag/-/has-tostringtag-1.0.2.tgz",
      "integrity": "sha512-NqADB8VjPFLM2V0VvHUewwwsw0ZWBaIdgo+ieHtK3hasLz4qeCRjYcqfB6AQrBggRKppKF8L52/VqdVsO47Dlw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "has-symbols": "^1.0.3"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/hashery": {
      "version": "1.5.1",
      "resolved": "https://registry.npmjs.org/hashery/-/hashery-1.5.1.tgz",
      "integrity": "sha512-iZyKG96/JwPz1N55vj2Ie2vXbhu440zfUfJvSwEqEbeLluk7NnapfGqa7LH0mOsnDxTF85Mx8/dyR6HfqcbmbQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "hookified": "^1.15.0"
      },
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/hasown": {
      "version": "2.0.4",
      "resolved": "https://registry.npmjs.org/hasown/-/hasown-2.0.4.tgz",
      "integrity": "sha512-T2UbfbBEF32wiepXIsMlTW9+dDYC6wMh/t/vYA4tuOMKqWz/n3vr1NFSxQiyP+zk2mXsoMA/i/7qV6LKut1t1A==",
      "license": "MIT",
      "dependencies": {
        "function-bind": "^1.1.2"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/helmet": {
      "version": "8.3.0",
      "resolved": "https://registry.npmjs.org/helmet/-/helmet-8.3.0.tgz",
      "integrity": "sha512-Qgpiaws3Sm30Av8Eah6sjMCZZwjlBu+E68rhpCWBshY1lb09HtLwj5GviX0OyQIn+ulUS0iX0AxN5n3tLZzz1w==",
      "license": "MIT",
      "engines": {
        "node": ">=18.0.0"
      },
      "funding": {
        "url": "https://github.com/sponsors/EvanHahn"
      }
    },
    "node_modules/help-me": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/help-me/-/help-me-5.0.0.tgz",
      "integrity": "sha512-7xgomUX6ADmcYzFik0HzAxh/73YlKR9bmFzf51CZwR+b6YtzU2m0u49hQCqV6SvlqIqsaxovfwdvbnsw3b/zpg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/hermes-estree": {
      "version": "0.25.1",
      "resolved": "https://registry.npmjs.org/hermes-estree/-/hermes-estree-0.25.1.tgz",
      "integrity": "sha512-0wUoCcLp+5Ev5pDW2OriHC2MJCbwLwuRx+gAqMTOkGKJJiBCLjtrvy4PWUGn6MIVefecRpzoOZ/UV6iGdOr+Cw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/hermes-parser": {
      "version": "0.25.1",
      "resolved": "https://registry.npmjs.org/hermes-parser/-/hermes-parser-0.25.1.tgz",
      "integrity": "sha512-6pEjquH3rqaI6cYAXYPcz9MS4rY6R4ngRgrgfDshRptUZIc3lw0MCIJIGDj9++mfySOuPTHB4nrSW99BCvOPIA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "hermes-estree": "0.25.1"
      }
    },
    "node_modules/hookified": {
      "version": "1.15.1",
      "resolved": "https://registry.npmjs.org/hookified/-/hookified-1.15.1.tgz",
      "integrity": "sha512-MvG/clsADq1GPM2KGo2nyfaWVyn9naPiXrqIe4jYjXNZQt238kWyOGrsyc/DmRAQ+Re6yeo6yX/yoNCG5KAEVg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/html-encoding-sniffer": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/html-encoding-sniffer/-/html-encoding-sniffer-7.0.0.tgz",
      "integrity": "sha512-UikN5yr7xsCDAq87Or5or0PAlD3HJJOKVzM05az588WnpDJ4Ux7a2A53Qi6gofGg2/EtvF/H4hCi/TXfCW4Y6w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@exodus/bytes": "^1.15.1"
      },
      "engines": {
        "node": "^22.13.0 || >=24.0.0"
      }
    },
    "node_modules/http-errors": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/http-errors/-/http-errors-2.0.1.tgz",
      "integrity": "sha512-4FbRdAX+bSdmo4AUFuS0WNiPz8NgFt+r8ThgNWmlrjQjt1Q7ZR9+zTlce2859x4KSXrwIsaeTqDoKQmtP8pLmQ==",
      "license": "MIT",
      "dependencies": {
        "depd": "~2.0.0",
        "inherits": "~2.0.4",
        "setprototypeof": "~1.2.0",
        "statuses": "~2.0.2",
        "toidentifier": "~1.0.1"
      },
      "engines": {
        "node": ">= 0.8"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/https-proxy-agent": {
      "version": "7.0.6",
      "resolved": "https://registry.npmjs.org/https-proxy-agent/-/https-proxy-agent-7.0.6.tgz",
      "integrity": "sha512-vK9P5/iUfdl95AI+JVyUuIcVtd4ofvtrOr3HNtM2yxC9bnMbEdp3x01OhQNnjb8IJYi38VlTE3mBXwcfvywuSw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "agent-base": "^7.1.2",
        "debug": "4"
      },
      "engines": {
        "node": ">= 14"
      }
    },
    "node_modules/iconv-lite": {
      "version": "0.7.3",
      "resolved": "https://registry.npmjs.org/iconv-lite/-/iconv-lite-0.7.3.tgz",
      "integrity": "sha512-IKXpvIzjnC9XTAUbVBcMfGS0EPaIXtW6v+zr+RRp+hqULEpo0owZax6wyRwPOJbWbzjYspQwusTsfVr0ifh4uQ==",
      "license": "MIT",
      "dependencies": {
        "safer-buffer": ">= 2.1.2 < 3.0.0"
      },
      "engines": {
        "node": ">=0.10.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/ieee754": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/ieee754/-/ieee754-1.2.1.tgz",
      "integrity": "sha512-dcyqhDvX1C46lXZcVqCpK+FtMRQVdIMN6/Df5js2zouUsqG7I6sFxitIC+7KYK29KdXOLHdu9zL4sFnoVQnqaA==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "BSD-3-Clause"
    },
    "node_modules/ignore": {
      "version": "5.3.2",
      "resolved": "https://registry.npmjs.org/ignore/-/ignore-5.3.2.tgz",
      "integrity": "sha512-hsBTNUqQTDwkWtcdYI2i06Y/nUBEsNEDJKjWdigLvegy8kDuJAS8uRlpkkcQpyEXL0Z/pjDy5HBmMjRCJ2gq+g==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 4"
      }
    },
    "node_modules/immediate": {
      "version": "3.0.6",
      "resolved": "https://registry.npmjs.org/immediate/-/immediate-3.0.6.tgz",
      "integrity": "sha512-XXOFtyqDjNDAQxVfYxuF7g9Il/IbWmmlQg2MYKOH8ExIT1qg6xc4zyS3HaEEATgs1btfzxq15ciUiY7gjSXRGQ==",
      "license": "MIT"
    },
    "node_modules/imurmurhash": {
      "version": "0.1.4",
      "resolved": "https://registry.npmjs.org/imurmurhash/-/imurmurhash-0.1.4.tgz",
      "integrity": "sha512-JmXMZ6wuvDmLiHEml9ykzqO6lwFbof0GG4IkcGaENdCRDDmMVnny7s5HsIgHCbaq0w2MyPhDqkhTUgS2LU2PHA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.8.19"
      }
    },
    "node_modules/indent-string": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/indent-string/-/indent-string-4.0.0.tgz",
      "integrity": "sha512-EdDDZu4A2OyIK7Lr/2zG+w5jmbuk1DVBnEwREQvBzspBJkCEbRa8GxU1lghYcaGJCnRWibjDXlq779X1/y5xwg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/inflight": {
      "version": "1.0.6",
      "resolved": "https://registry.npmjs.org/inflight/-/inflight-1.0.6.tgz",
      "integrity": "sha512-k92I/b08q4wvFscXCLvqfsHCrjrF7yiXsQuIVvVE7N82W3+aqpzuUdBbfhWcy/FZR3/4IgflMgKLOsvPDrGCJA==",
      "deprecated": "This module is not supported, and leaks memory. Do not use it. Check out lru-cache if you want a good and tested way to coalesce async requests by a key value, which is much more comprehensive and powerful.",
      "license": "ISC",
      "dependencies": {
        "once": "^1.3.0",
        "wrappy": "1"
      }
    },
    "node_modules/inherits": {
      "version": "2.0.4",
      "resolved": "https://registry.npmjs.org/inherits/-/inherits-2.0.4.tgz",
      "integrity": "sha512-k/vGaX4/Yla3WzyMCvTQOXYeIHvqOKtnqBduzTHpzpQZzAskKMhZ2K+EnBiSM9zGSoIFeMpXKxa4dYeZIQqewQ==",
      "license": "ISC"
    },
    "node_modules/ip-address": {
      "version": "10.7.2",
      "resolved": "https://registry.npmjs.org/ip-address/-/ip-address-10.7.2.tgz",
      "integrity": "sha512-7H/2gFSIitxc0hG3nOI1glS8QLo/EHBFFLk8vEUjXY/xu0AdL8jZ9U1IzO2PUm0d2D/ofQcAifb0g6OBkt8U7w==",
      "license": "MIT",
      "engines": {
        "node": ">= 12"
      }
    },
    "node_modules/ipaddr.js": {
      "version": "1.9.1",
      "resolved": "https://registry.npmjs.org/ipaddr.js/-/ipaddr.js-1.9.1.tgz",
      "integrity": "sha512-0KI/607xoxSToH7GjN1FfSbLoU0+btTicjsQSWQlh/hZykN8KpmMf7uYwPW3R+akZ6R/w18ZlXSHBYXiYUPO3g==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/is-extglob": {
      "version": "2.1.1",
      "resolved": "https://registry.npmjs.org/is-extglob/-/is-extglob-2.1.1.tgz",
      "integrity": "sha512-SbKbANkN603Vi4jEZv49LeVJMn4yGwsbzZworEoyEiutsN3nJYdbO36zfhGJ6QEDpOZIFkDtnq5JRxmvl3jsoQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/is-fullwidth-code-point": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/is-fullwidth-code-point/-/is-fullwidth-code-point-3.0.0.tgz",
      "integrity": "sha512-zymm5+u+sCsSWyD9qNaejV3DFvhCKclKdizYaJUuHA83RLjb7nSuGnddCHGv0hk+KY7BMAlsWeK4Ueg6EV6XQg==",
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/is-glob": {
      "version": "4.0.3",
      "resolved": "https://registry.npmjs.org/is-glob/-/is-glob-4.0.3.tgz",
      "integrity": "sha512-xelSayHH36ZgE7ZWhli7pW34hNbNl8Ojv5KVmkJD4hBdD3th8Tfk9vYasLM+mXWOZhFkgZfxhLSnrwRr4elSSg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "is-extglob": "^2.1.1"
      },
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/is-potential-custom-element-name": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/is-potential-custom-element-name/-/is-potential-custom-element-name-1.0.1.tgz",
      "integrity": "sha512-bCYeRA2rVibKZd+s2625gGnGF/t7DSqDs4dP7CrLA1m7jKWz6pps0LpYLJN8Q64HtmPKJ1hrN3nzPNKFEKOUiQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/is-promise": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/is-promise/-/is-promise-4.0.0.tgz",
      "integrity": "sha512-hvpoI6korhJMnej285dSg6nu1+e6uxs7zG3BYAm5byqDsgJNWwxzM6z6iZiAgQR4TJ30JmBTOwqZUw3WlyH3AQ==",
      "license": "MIT"
    },
    "node_modules/isarray": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/isarray/-/isarray-1.0.0.tgz",
      "integrity": "sha512-VLghIWNM6ELQzo7zwmcg0NmTVyWKYjvIeM83yjp0wRDTmUnrM678fQbcKBo6n2CJEF0szoG//ytg+TKla89ALQ==",
      "license": "MIT"
    },
    "node_modules/isexe": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/isexe/-/isexe-2.0.0.tgz",
      "integrity": "sha512-RHxMLp9lnKHGHRng9QFhRCMbYAcVpn69smSGcq3f36xjgVVWThj4qqLbTLlq7Ssj8B+fIQ1EuCEGI2lKsyQeIw==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/jiti": {
      "version": "2.7.0",
      "resolved": "https://registry.npmjs.org/jiti/-/jiti-2.7.0.tgz",
      "integrity": "sha512-AC/7JofJvZGrrneWNaEnJeOLUx+JlGt7tNa0wZiRPT4MY1wmfKjt2+6O2p2uz2+skll8OZZmJMNqeke7kKbNgQ==",
      "dev": true,
      "license": "MIT",
      "bin": {
        "jiti": "lib/jiti-cli.mjs"
      }
    },
    "node_modules/joycon": {
      "version": "3.1.1",
      "resolved": "https://registry.npmjs.org/joycon/-/joycon-3.1.1.tgz",
      "integrity": "sha512-34wB/Y7MW7bzjKRjUKTa46I2Z7eV62Rkhva+KkopW7Qvv/OSWBqvkSY7vusOPrNuZcUG3tApvdVgNB8POj3SPw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/js-tokens": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/js-tokens/-/js-tokens-4.0.0.tgz",
      "integrity": "sha512-RdJUflcE3cUzKiMqQgsCu06FPu9UdIJO0beYbPhHN4k6apgJtifcoCtT9bcxOpYBtpD2kCM6Sbzg4CausW/PKQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/jsdom": {
      "version": "30.1.1",
      "resolved": "https://registry.npmjs.org/jsdom/-/jsdom-30.1.1.tgz",
      "integrity": "sha512-FahmoPK5vbPc+jxV1iErMHmAZypCZ942NHF4+qqaWAuvaKKTBZxawnmAtrbGWLU7MtlxfqIP0qw6aSI+aWGtLg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@asamuzakjp/css-color": "^7.0.0",
        "@asamuzakjp/dom-selector": "^9.2.1",
        "@bramus/specificity": "^2.4.2",
        "@csstools/css-syntax-patches-for-csstree": "^1.1.13",
        "@exodus/bytes": "^1.15.1",
        "css-tree": "^3.2.1",
        "data-urls": "^7.0.0",
        "decimal.js": "^10.6.0",
        "html-encoding-sniffer": "^7.0.0",
        "is-potential-custom-element-name": "^1.0.1",
        "lru-cache": "^11.5.2",
        "parse5": "^8.0.1",
        "saxes": "^6.0.0",
        "tough-cookie": "^6.0.2",
        "undici": "^8.10.2",
        "w3c-xmlserializer": "^6.0.0",
        "webidl-conversions": "^8.0.1",
        "whatwg-mimetype": "^5.0.0",
        "whatwg-url": "^17.1.1",
        "xml-name-validator": "^5.0.0"
      },
      "engines": {
        "node": "^22.22.2 || ^24.15.0 || >=26.0.0"
      },
      "peerDependencies": {
        "canvas": "^3.2.3"
      },
      "peerDependenciesMeta": {
        "canvas": {
          "optional": true
        }
      }
    },
    "node_modules/jsdom/node_modules/lru-cache": {
      "version": "11.5.3",
      "resolved": "https://registry.npmjs.org/lru-cache/-/lru-cache-11.5.3.tgz",
      "integrity": "sha512-U4N8FgzmWxc8k1VH8Kr6lQg18U7Fjvby6wXHVRX/ZZ7IwWbRMgrRbP0Wrb5q5NVinryp4SQampHKdvtecItxUg==",
      "dev": true,
      "license": "BlueOak-1.0.0",
      "engines": {
        "node": "20 || >=22"
      }
    },
    "node_modules/jsdom/node_modules/saxes": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/saxes/-/saxes-6.0.0.tgz",
      "integrity": "sha512-xAg7SOnEhrm5zI3puOOKyy1OMcMlIJZYNJY7xLBwSze0UjhPLnWfj2GF2EpT0jmzaJKIWKHLsaSSajf35bcYnA==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "xmlchars": "^2.2.0"
      },
      "engines": {
        "node": ">=v12.22.7"
      }
    },
    "node_modules/jsdom/node_modules/tr46": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/tr46/-/tr46-6.0.0.tgz",
      "integrity": "sha512-bLVMLPtstlZ4iMQHpFHTR7GAGj2jxi8Dg0s2h2MafAE4uSWF98FC/3MomU51iQAMf8/qDUbKWf5GxuvvVcXEhw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "punycode": "^2.3.1"
      },
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/jsdom/node_modules/webidl-conversions": {
      "version": "8.0.1",
      "resolved": "https://registry.npmjs.org/webidl-conversions/-/webidl-conversions-8.0.1.tgz",
      "integrity": "sha512-BMhLD/Sw+GbJC21C/UgyaZX41nPt8bUTg+jWyDeg7e7YN4xOM05YPSIXceACnXVtqyEw/LMClUQMtMZ+PGGpqQ==",
      "dev": true,
      "license": "BSD-2-Clause",
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/jsdom/node_modules/whatwg-url": {
      "version": "17.1.2",
      "resolved": "https://registry.npmjs.org/whatwg-url/-/whatwg-url-17.1.2.tgz",
      "integrity": "sha512-TEZA+Zqxin7Jjsm2cjRohCmen5awh+hT6Zi3VZdqZlNRk7zvOI/9WpBFg/DWlA56bWnzwm6DuB8NS0EsxQH9uQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@exodus/bytes": "^1.15.1",
        "tr46": "^6.0.0",
        "webidl-conversions": "^8.0.1"
      },
      "engines": {
        "node": "^22.14.0 || >=24.0.0"
      }
    },
    "node_modules/jsesc": {
      "version": "3.1.0",
      "resolved": "https://registry.npmjs.org/jsesc/-/jsesc-3.1.0.tgz",
      "integrity": "sha512-/sM3dO2FOzXjKQhJuo0Q173wf2KOo8t4I8vHy6lF9poUp7bKT0/NHE8fPX23PwfhnykfqnC2xRxOnVw5XuGIaA==",
      "dev": true,
      "license": "MIT",
      "bin": {
        "jsesc": "bin/jsesc"
      },
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/json-schema-traverse": {
      "version": "0.4.1",
      "resolved": "https://registry.npmjs.org/json-schema-traverse/-/json-schema-traverse-0.4.1.tgz",
      "integrity": "sha512-xbbCH5dCYU5T8LcEhhuh7HJ88HXuW3qsI3Y0zOZFKfZEHcpWiHU/Jxzk629Brsab/mMiHQti9wMP+845RPe3Vg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/json-stable-stringify-without-jsonify": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/json-stable-stringify-without-jsonify/-/json-stable-stringify-without-jsonify-1.0.1.tgz",
      "integrity": "sha512-Bdboy+l7tA3OGW6FjyFHWkP5LuByj1Tk33Ljyq0axyzdk9//JSi2u3fP1QSmd1KNwq6VOKYGlAu87CisVir6Pw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/json5": {
      "version": "2.2.3",
      "resolved": "https://registry.npmjs.org/json5/-/json5-2.2.3.tgz",
      "integrity": "sha512-XmOWe7eyHYH14cLdVPoyg+GOH3rYX++KpzrylJwSW98t3Nk+U8XOl8FWKOgwtzdb8lXGf6zYwDUzeHMWfxasyg==",
      "dev": true,
      "license": "MIT",
      "bin": {
        "json5": "lib/cli.js"
      },
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/jsonwebtoken": {
      "version": "9.0.3",
      "resolved": "https://registry.npmjs.org/jsonwebtoken/-/jsonwebtoken-9.0.3.tgz",
      "integrity": "sha512-MT/xP0CrubFRNLNKvxJ2BYfy53Zkm++5bX9dtuPbqAeQpTVe0MQTFhao8+Cp//EmJp244xt6Drw/GVEGCUj40g==",
      "license": "MIT",
      "dependencies": {
        "jws": "^4.0.1",
        "lodash.includes": "^4.3.0",
        "lodash.isboolean": "^3.0.3",
        "lodash.isinteger": "^4.0.4",
        "lodash.isnumber": "^3.0.3",
        "lodash.isplainobject": "^4.0.6",
        "lodash.isstring": "^4.0.1",
        "lodash.once": "^4.0.0",
        "ms": "^2.1.1",
        "semver": "^7.5.4"
      },
      "engines": {
        "node": ">=12",
        "npm": ">=6"
      }
    },
    "node_modules/jszip": {
      "version": "3.10.2",
      "resolved": "https://registry.npmjs.org/jszip/-/jszip-3.10.2.tgz",
      "integrity": "sha512-3l+rb15IOWtUhU0H5MFqES/T6Kh7abYwjosBey/vD6hDt8zoEffkSC5Ws5SGtgVw3gBx2NEbhTeSW1+kWkpyTQ==",
      "license": "(MIT OR GPL-3.0-or-later)",
      "dependencies": {
        "lie": "~3.3.0",
        "pako": "~1.0.2",
        "readable-stream": "~2.3.6",
        "setimmediate": "^1.0.5"
      }
    },
    "node_modules/jszip/node_modules/readable-stream": {
      "version": "2.3.8",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-2.3.8.tgz",
      "integrity": "sha512-8p0AUk4XODgIewSi0l8Epjs+EVnWiK7NoDIEGU0HhE7+ZyY8D1IMY7odu5lRrFXGg71L15KG8QrPmum45RTtdA==",
      "license": "MIT",
      "dependencies": {
        "core-util-is": "~1.0.0",
        "inherits": "~2.0.3",
        "isarray": "~1.0.0",
        "process-nextick-args": "~2.0.0",
        "safe-buffer": "~5.1.1",
        "string_decoder": "~1.1.1",
        "util-deprecate": "~1.0.1"
      }
    },
    "node_modules/jszip/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "license": "MIT"
    },
    "node_modules/jszip/node_modules/string_decoder": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.1.1.tgz",
      "integrity": "sha512-n/ShnvDi6FHbbVfviro+WojiFzv+s8MPMHBczVePfUpDJLwoLT0ht1l4YwBCbi8pJAveEEdnkHyPyTP/mzRfwg==",
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.1.0"
      }
    },
    "node_modules/jwa": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/jwa/-/jwa-2.0.1.tgz",
      "integrity": "sha512-hRF04fqJIP8Abbkq5NKGN0Bbr3JxlQ+qhZufXVr0DvujKy93ZCbXZMHDL4EOtodSbCWxOqR8MS1tXA5hwqCXDg==",
      "license": "MIT",
      "dependencies": {
        "buffer-equal-constant-time": "^1.0.1",
        "ecdsa-sig-formatter": "1.0.11",
        "safe-buffer": "^5.0.1"
      }
    },
    "node_modules/jws": {
      "version": "4.0.1",
      "resolved": "https://registry.npmjs.org/jws/-/jws-4.0.1.tgz",
      "integrity": "sha512-EKI/M/yqPncGUUh44xz0PxSidXFr/+r0pA70+gIYhjv+et7yxM+s29Y+VGDkovRofQem0fs7Uvf4+YmAdyRduA==",
      "license": "MIT",
      "dependencies": {
        "jwa": "^2.0.1",
        "safe-buffer": "^5.0.1"
      }
    },
    "node_modules/kareem": {
      "version": "3.4.0",
      "resolved": "https://registry.npmjs.org/kareem/-/kareem-3.4.0.tgz",
      "integrity": "sha512-JAKhnR4S027v/8949QXNInRskgETCg9rFUMi1VjhGbjX+XltCAAEFcXykkSocNkom1kc66EMJfjWvhj87BDQKg==",
      "license": "Apache-2.0",
      "engines": {
        "node": ">=18.0.0"
      }
    },
    "node_modules/keyv": {
      "version": "5.6.0",
      "resolved": "https://registry.npmjs.org/keyv/-/keyv-5.6.0.tgz",
      "integrity": "sha512-CYDD3SOtsHtyXeEORYRx2qBtpDJFjRTGXUtmNEMGyzYOKj1TE3tycdlho7kA1Ufx9OYWZzg52QFBGALTirzDSw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@keyv/serialize": "^1.1.1"
      }
    },
    "node_modules/lazystream": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/lazystream/-/lazystream-1.0.1.tgz",
      "integrity": "sha512-b94GiNHQNy6JNTrt5w6zNyffMrNkXZb3KTkCZJb2V1xaEGCk093vkZ2jk3tpaeP33/OiXC+WvK9AxUebnf5nbw==",
      "license": "MIT",
      "dependencies": {
        "readable-stream": "^2.0.5"
      },
      "engines": {
        "node": ">= 0.6.3"
      }
    },
    "node_modules/lazystream/node_modules/readable-stream": {
      "version": "2.3.8",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-2.3.8.tgz",
      "integrity": "sha512-8p0AUk4XODgIewSi0l8Epjs+EVnWiK7NoDIEGU0HhE7+ZyY8D1IMY7odu5lRrFXGg71L15KG8QrPmum45RTtdA==",
      "license": "MIT",
      "dependencies": {
        "core-util-is": "~1.0.0",
        "inherits": "~2.0.3",
        "isarray": "~1.0.0",
        "process-nextick-args": "~2.0.0",
        "safe-buffer": "~5.1.1",
        "string_decoder": "~1.1.1",
        "util-deprecate": "~1.0.1"
      }
    },
    "node_modules/lazystream/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "license": "MIT"
    },
    "node_modules/lazystream/node_modules/string_decoder": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.1.1.tgz",
      "integrity": "sha512-n/ShnvDi6FHbbVfviro+WojiFzv+s8MPMHBczVePfUpDJLwoLT0ht1l4YwBCbi8pJAveEEdnkHyPyTP/mzRfwg==",
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.1.0"
      }
    },
    "node_modules/levn": {
      "version": "0.4.1",
      "resolved": "https://registry.npmjs.org/levn/-/levn-0.4.1.tgz",
      "integrity": "sha512-+bT2uH4E5LGE7h/n3evcS/sQlJXCpIp6ym8OWJ5eV6+67Dsql/LaaT7qJBAt2rzfoa/5QBGBhxDix1dMt2kQKQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "prelude-ls": "^1.2.1",
        "type-check": "~0.4.0"
      },
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/lie": {
      "version": "3.3.0",
      "resolved": "https://registry.npmjs.org/lie/-/lie-3.3.0.tgz",
      "integrity": "sha512-UaiMJzeWRlEujzAuw5LokY1L5ecNQYZKfmyZ9L7wDHb/p5etKaxXhohBcrw0EYby+G/NA52vRSN4N39dxHAIwQ==",
      "license": "MIT",
      "dependencies": {
        "immediate": "~3.0.5"
      }
    },
    "node_modules/lightningcss": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss/-/lightningcss-1.33.0.tgz",
      "integrity": "sha512-WkUDrojuJs0xkgGf2udWxa3yGBRxPtxUkB79i6aCZLRgc7PM8fZe9TosfPDcvEpQZbuFASnHYmRLBLUbmLOIIA==",
      "dev": true,
      "license": "MPL-2.0",
      "dependencies": {
        "detect-libc": "^2.0.3"
      },
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      },
      "optionalDependencies": {
        "lightningcss-android-arm64": "1.33.0",
        "lightningcss-darwin-arm64": "1.33.0",
        "lightningcss-darwin-x64": "1.33.0",
        "lightningcss-freebsd-x64": "1.33.0",
        "lightningcss-linux-arm-gnueabihf": "1.33.0",
        "lightningcss-linux-arm64-gnu": "1.33.0",
        "lightningcss-linux-arm64-musl": "1.33.0",
        "lightningcss-linux-x64-gnu": "1.33.0",
        "lightningcss-linux-x64-musl": "1.33.0",
        "lightningcss-win32-arm64-msvc": "1.33.0",
        "lightningcss-win32-x64-msvc": "1.33.0"
      }
    },
    "node_modules/lightningcss-android-arm64": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-android-arm64/-/lightningcss-android-arm64-1.33.0.tgz",
      "integrity": "sha512-gEpRTalKdosp4Bb8qWtc2iOgE5SeIHlpS1up9bFq2wAyYhl1UdTObYiHe98zEM9SQvSoqQZ1IQD0JNpg3Ml5pg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "android"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-darwin-arm64": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-darwin-arm64/-/lightningcss-darwin-arm64-1.33.0.tgz",
      "integrity": "sha512-Sciaz8eenNTKn9b3t7+xr0ipTp9YxKQY4npwQ3mrRuL0BAVHBLyZxofhaKBAVtzmtRZ/zTyo0/to4B1uWG/Djg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-darwin-x64": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-darwin-x64/-/lightningcss-darwin-x64-1.33.0.tgz",
      "integrity": "sha512-Z5UPAxzrjlWNNyGy6i65cJzzvgJ5D3T6wMvs+gWpY9d7qRhANrxqAp6LhxIgZhWEw18RfJTGcRxjuLIBr+m8XQ==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-freebsd-x64": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-freebsd-x64/-/lightningcss-freebsd-x64-1.33.0.tgz",
      "integrity": "sha512-QQM/Ti/hQajJwCY+RiWuCZ9sdtI/XQk7nDK5vC8kkdwixezOlDgvDx7+RT+QjK6FcFT4MpsuoBnHIo/O3StRRg==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "freebsd"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-arm-gnueabihf": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-arm-gnueabihf/-/lightningcss-linux-arm-gnueabihf-1.33.0.tgz",
      "integrity": "sha512-N7FVBe6iS24MlM6R/4RBTxGhQheZGs7tiQ9U32UtF75NzP5Q7xWPRqLBCKxlRQRk3rY1jCIPLzx7WzOhuUIRLQ==",
      "cpu": [
        "arm"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-arm64-gnu": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-arm64-gnu/-/lightningcss-linux-arm64-gnu-1.33.0.tgz",
      "integrity": "sha512-j2v/itmy4HlNxlc6voKXYgBqNi0Ng2LShg4z7GufpEgs05P+2suBVyi9I6YHq5uoVFx9ETin3eCEhLVyXGQnKg==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-arm64-musl": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-arm64-musl/-/lightningcss-linux-arm64-musl-1.33.0.tgz",
      "integrity": "sha512-yiO5ROMuYQgXbC60yjZU5CYSFZGKXL0HFATXt9mHJn1+zW55oCtMI9NfcVhYLMFDL7gV7oBPon/EmMMGg2OvtQ==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-x64-gnu": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-x64-gnu/-/lightningcss-linux-x64-gnu-1.33.0.tgz",
      "integrity": "sha512-ar+Ju7LmcN0Jo4FpL4hpFybwNG9/3A/Br5KW2n2jyODg3MEZXaDYADdemoNS+BDNfMgKvylJLj4S5tyRActuAg==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-linux-x64-musl": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-linux-x64-musl/-/lightningcss-linux-x64-musl-1.33.0.tgz",
      "integrity": "sha512-RYiYbkokw0trfKqqzfF55lginwEPrD3OJDfTuJzFs1MK6iFnDenaz1fqLLtX4ITG3OktJQXOeTaw1awrBAlZPw==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-win32-arm64-msvc": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-win32-arm64-msvc/-/lightningcss-win32-arm64-msvc-1.33.0.tgz",
      "integrity": "sha512-1K+MPfLSFVpphzpdbfkhlWk6wBrTObBzS2T6db10PNOZgR9GoVsAWzwNyuhUYYbTp23j+4RrncfujZ4uAzXvwA==",
      "cpu": [
        "arm64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/lightningcss-win32-x64-msvc": {
      "version": "1.33.0",
      "resolved": "https://registry.npmjs.org/lightningcss-win32-x64-msvc/-/lightningcss-win32-x64-msvc-1.33.0.tgz",
      "integrity": "sha512-OlEICDx/Xl0FqSp4bry8zFnCvGpig3Gl4gCquvYwHuqJKEC1+n9NgDniFvqHGmMv1ZkqDJrDqKKSykTDX+ehuA==",
      "cpu": [
        "x64"
      ],
      "dev": true,
      "license": "MPL-2.0",
      "optional": true,
      "os": [
        "win32"
      ],
      "engines": {
        "node": ">= 12.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/parcel"
      }
    },
    "node_modules/listenercount": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/listenercount/-/listenercount-1.0.1.tgz",
      "integrity": "sha512-3mk/Zag0+IJxeDrxSgaDPy4zZ3w05PRZeJNnlWhzFz5OkX49J4krc+A8X2d2M69vGMBEX0uyl8M+W+8gH+kBqQ==",
      "license": "ISC"
    },
    "node_modules/locate-path": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/locate-path/-/locate-path-6.0.0.tgz",
      "integrity": "sha512-iPZK6eYjbxRu3uB4/WZ3EsEIMJFMqAoopl3R+zuq0UjcAm/MO6KCweDgPfP3elTztoKP3KtnVHxTn2NHBSDVUw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "p-locate": "^5.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/lodash.defaults": {
      "version": "4.2.0",
      "resolved": "https://registry.npmjs.org/lodash.defaults/-/lodash.defaults-4.2.0.tgz",
      "integrity": "sha512-qjxPLHd3r5DnsdGacqOMU6pb/avJzdh9tFX2ymgoZE27BmjXrNy/y4LoaiTeAb+O3gL8AfpJGtqfX/ae2leYYQ==",
      "license": "MIT"
    },
    "node_modules/lodash.difference": {
      "version": "4.5.0",
      "resolved": "https://registry.npmjs.org/lodash.difference/-/lodash.difference-4.5.0.tgz",
      "integrity": "sha512-dS2j+W26TQ7taQBGN8Lbbq04ssV3emRw4NY58WErlTO29pIqS0HmoT5aJ9+TUQ1N3G+JOZSji4eugsWwGp9yPA==",
      "license": "MIT"
    },
    "node_modules/lodash.escaperegexp": {
      "version": "4.1.2",
      "resolved": "https://registry.npmjs.org/lodash.escaperegexp/-/lodash.escaperegexp-4.1.2.tgz",
      "integrity": "sha512-TM9YBvyC84ZxE3rgfefxUWiQKLilstD6k7PTGt6wfbtXF8ixIJLOL3VYyV/z+ZiPLsVxAsKAFVwWlWeb2Y8Yyw==",
      "license": "MIT"
    },
    "node_modules/lodash.flatten": {
      "version": "4.4.0",
      "resolved": "https://registry.npmjs.org/lodash.flatten/-/lodash.flatten-4.4.0.tgz",
      "integrity": "sha512-C5N2Z3DgnnKr0LOpv/hKCgKdb7ZZwafIrsesve6lmzvZIRZRGaZ/l6Q8+2W7NaT+ZwO3fFlSCzCzrDCFdJfZ4g==",
      "license": "MIT"
    },
    "node_modules/lodash.groupby": {
      "version": "4.6.0",
      "resolved": "https://registry.npmjs.org/lodash.groupby/-/lodash.groupby-4.6.0.tgz",
      "integrity": "sha512-5dcWxm23+VAoz+awKmBaiBvzox8+RqMgFhi7UvX9DHZr2HdxHXM/Wrf8cfKpsW37RNrvtPn6hSwNqurSILbmJw==",
      "license": "MIT"
    },
    "node_modules/lodash.includes": {
      "version": "4.3.0",
      "resolved": "https://registry.npmjs.org/lodash.includes/-/lodash.includes-4.3.0.tgz",
      "integrity": "sha512-W3Bx6mdkRTGtlJISOvVD/lbqjTlPPUDTMnlXZFnVwi9NKJ6tiAk6LVdlhZMm17VZisqhKcgzpO5Wz91PCt5b0w==",
      "license": "MIT"
    },
    "node_modules/lodash.isboolean": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/lodash.isboolean/-/lodash.isboolean-3.0.3.tgz",
      "integrity": "sha512-Bz5mupy2SVbPHURB98VAcw+aHh4vRV5IPNhILUCsOzRmsTmSQ17jIuqopAentWoehktxGd9e/hbIXq980/1QJg==",
      "license": "MIT"
    },
    "node_modules/lodash.isequal": {
      "version": "4.5.0",
      "resolved": "https://registry.npmjs.org/lodash.isequal/-/lodash.isequal-4.5.0.tgz",
      "integrity": "sha512-pDo3lu8Jhfjqls6GkMgpahsF9kCyayhgykjyLMNFTKWrpVdAQtYyB4muAMWozBB4ig/dtWAmsMxLEI8wuz+DYQ==",
      "deprecated": "This package is deprecated. Use require('node:util').isDeepStrictEqual instead.",
      "license": "MIT"
    },
    "node_modules/lodash.isfunction": {
      "version": "3.0.9",
      "resolved": "https://registry.npmjs.org/lodash.isfunction/-/lodash.isfunction-3.0.9.tgz",
      "integrity": "sha512-AirXNj15uRIMMPihnkInB4i3NHeb4iBtNg9WRWuK2o31S+ePwwNmDPaTL3o7dTJ+VXNZim7rFs4rxN4YU1oUJw==",
      "license": "MIT"
    },
    "node_modules/lodash.isinteger": {
      "version": "4.0.4",
      "resolved": "https://registry.npmjs.org/lodash.isinteger/-/lodash.isinteger-4.0.4.tgz",
      "integrity": "sha512-DBwtEWN2caHQ9/imiNeEA5ys1JoRtRfY3d7V9wkqtbycnAmTvRRmbHKDV4a0EYc678/dia0jrte4tjYwVBaZUA==",
      "license": "MIT"
    },
    "node_modules/lodash.isnil": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/lodash.isnil/-/lodash.isnil-4.0.0.tgz",
      "integrity": "sha512-up2Mzq3545mwVnMhTDMdfoG1OurpA/s5t88JmQX809eH3C8491iu2sfKhTfhQtKY78oPNhiaHJUpT/dUDAAtng==",
      "license": "MIT"
    },
    "node_modules/lodash.isnumber": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/lodash.isnumber/-/lodash.isnumber-3.0.3.tgz",
      "integrity": "sha512-QYqzpfwO3/CWf3XP+Z+tkQsfaLL/EnUlXWVkIk5FUPc4sBdTehEqZONuyRt2P67PXAk+NXmTBcc97zw9t1FQrw==",
      "license": "MIT"
    },
    "node_modules/lodash.isplainobject": {
      "version": "4.0.6",
      "resolved": "https://registry.npmjs.org/lodash.isplainobject/-/lodash.isplainobject-4.0.6.tgz",
      "integrity": "sha512-oSXzaWypCMHkPC3NvBEaPHf0KsA5mvPrOPgQWDsbg8n7orZ290M0BmC/jgRZ4vcJ6DTAhjrsSYgdsW/F+MFOBA==",
      "license": "MIT"
    },
    "node_modules/lodash.isstring": {
      "version": "4.0.1",
      "resolved": "https://registry.npmjs.org/lodash.isstring/-/lodash.isstring-4.0.1.tgz",
      "integrity": "sha512-0wJxfxH1wgO3GrbuP+dTTk7op+6L41QCXbGINEmD+ny/G/eCqGzxyCsh7159S+mgDDcoarnBw6PC1PS5+wUGgw==",
      "license": "MIT"
    },
    "node_modules/lodash.isundefined": {
      "version": "3.0.1",
      "resolved": "https://registry.npmjs.org/lodash.isundefined/-/lodash.isundefined-3.0.1.tgz",
      "integrity": "sha512-MXB1is3s899/cD8jheYYE2V9qTHwKvt+npCwpD+1Sxm3Q3cECXCiYHjeHWXNwr6Q0SOBPrYUDxendrO6goVTEA==",
      "license": "MIT"
    },
    "node_modules/lodash.once": {
      "version": "4.1.1",
      "resolved": "https://registry.npmjs.org/lodash.once/-/lodash.once-4.1.1.tgz",
      "integrity": "sha512-Sb487aTOCr9drQVL8pIxOzVhafOjZN9UU54hiN8PU3uAiSV7lx1yYNpbNmex2PK6dSJoNTSJUUswT651yww3Mg==",
      "license": "MIT"
    },
    "node_modules/lodash.union": {
      "version": "4.6.0",
      "resolved": "https://registry.npmjs.org/lodash.union/-/lodash.union-4.6.0.tgz",
      "integrity": "sha512-c4pB2CdGrGdjMKYLA+XiRDO7Y0PRQbm/Gzg8qMj+QH+pFVAoTp5sBpO0odL3FjoPCGjK96p6qsP+yQoiLoOBcw==",
      "license": "MIT"
    },
    "node_modules/lodash.uniq": {
      "version": "4.5.0",
      "resolved": "https://registry.npmjs.org/lodash.uniq/-/lodash.uniq-4.5.0.tgz",
      "integrity": "sha512-xfBaXQd9ryd9dlSDvnvI0lvxfLJlYAZzXomUYzLKtUeOQvOP5piqAWuGtrhWeqaXK9hhoM/iyJc5AV+XfsX3HQ==",
      "license": "MIT"
    },
    "node_modules/lru-cache": {
      "version": "5.1.1",
      "resolved": "https://registry.npmjs.org/lru-cache/-/lru-cache-5.1.1.tgz",
      "integrity": "sha512-KpNARQA3Iwv+jTA0utUVVbrh+Jlrr1Fv0e56GGzAFOXN7dk/FviaDW8LHmK52DlcH4WP2n6gI8vN1aesBFgo9w==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "yallist": "^3.0.2"
      }
    },
    "node_modules/lucide-react": {
      "version": "1.50.0",
      "resolved": "https://registry.npmjs.org/lucide-react/-/lucide-react-1.50.0.tgz",
      "integrity": "sha512-RqHPQtKX6S9IE1xOL4oTHHsVQbcwJWTnmlxI6AdI9IpOwKiy7q+COPCQyMepI/Qu1x3h7sunpyEMvqtgFbgNiQ==",
      "license": "ISC",
      "peerDependencies": {
        "@types/react": "*",
        "react": "^16.5.1 || ^17.0.0 || ^18.0.0 || ^19.0.0"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        }
      }
    },
    "node_modules/luxon": {
      "version": "3.7.2",
      "resolved": "https://registry.npmjs.org/luxon/-/luxon-3.7.2.tgz",
      "integrity": "sha512-vtEhXh/gNjI9Yg1u4jX/0YVPMvxzHuGgCm6tC5kZyb08yjGWGnqAjGJvcXbqQR2P3MyMEFnRbpcdFS6PBcLqew==",
      "license": "MIT",
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/lz-string": {
      "version": "1.5.0",
      "resolved": "https://registry.npmjs.org/lz-string/-/lz-string-1.5.0.tgz",
      "integrity": "sha512-h5bgJWpxJNswbU7qCrV0tIKQCaS3blPDrqKWx+QxzuzL1zGUzij9XCWLrSLsJPu5t+eWA/ycetzYAO5IOMcWAQ==",
      "dev": true,
      "license": "MIT",
      "peer": true,
      "bin": {
        "lz-string": "bin/bin.js"
      }
    },
    "node_modules/magic-string": {
      "version": "1.4.2",
      "resolved": "https://registry.npmjs.org/magic-string/-/magic-string-1.4.2.tgz",
      "integrity": "sha512-vG+rjFRj1PqdIBozIxAGMjPlOhaVe+GXpbttY/iSK7rGcJRMlwNJO7dcUwmUqkymsFLJiNGI06t4D7Fr7yRC9g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@jridgewell/sourcemap-codec": "^1.6.0"
      }
    },
    "node_modules/make-dir": {
      "version": "3.1.0",
      "resolved": "https://registry.npmjs.org/make-dir/-/make-dir-3.1.0.tgz",
      "integrity": "sha512-g3FeP20LNwhALb/6Cz6Dd4F2ngze0jz7tbzrD2wAV+o9FeNHe4rL+yK2md0J/fiSf1sa1ADhXqi5+oVwOM/eGw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "semver": "^6.0.0"
      },
      "engines": {
        "node": ">=8"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/make-dir/node_modules/semver": {
      "version": "6.3.1",
      "resolved": "https://registry.npmjs.org/semver/-/semver-6.3.1.tgz",
      "integrity": "sha512-BR7VvDCVHO+q2xBEWskxS6DJE1qRnb7DxzUrogb71CWoSficBxYsiAGd+Kl0mmq/MprG9yArRkyrQxTO6XjMzA==",
      "dev": true,
      "license": "ISC",
      "bin": {
        "semver": "bin/semver.js"
      }
    },
    "node_modules/math-intrinsics": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/math-intrinsics/-/math-intrinsics-1.1.0.tgz",
      "integrity": "sha512-/IXtbwEk5HTPyEwyKX6hGkYXxM9nbj64B+ilVJnC/R6B0pH5G4V3b0pVbL7DBj4tkhBAppbQUlf6F6Xl9LHu1g==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/mdn-data": {
      "version": "2.27.1",
      "resolved": "https://registry.npmjs.org/mdn-data/-/mdn-data-2.27.1.tgz",
      "integrity": "sha512-9Yubnt3e8A0OKwxYSXyhLymGW4sCufcLG6VdiDdUGVkPhpqLxlvP5vl1983gQjJl3tqbrM731mjaZaP68AgosQ==",
      "dev": true,
      "license": "CC0-1.0"
    },
    "node_modules/media-typer": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/media-typer/-/media-typer-1.1.1.tgz",
      "integrity": "sha512-yz3xRaG20c6/BOzvYoDaGtPmGscs7YivItZEEqe6GbwNfHuxu9YNmvnEkMzKldAGY4/80pRcQRZSEnhquk9XuQ==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/memory-pager": {
      "version": "1.5.0",
      "resolved": "https://registry.npmjs.org/memory-pager/-/memory-pager-1.5.0.tgz",
      "integrity": "sha512-ZS4Bp4r/Zoeq6+NLJpP+0Zzm0pR8whtGPf1XExKLJBAczGMnSi3It14OiNCStjQjM6NU1okjQGSxgEZN8eBYKg==",
      "license": "MIT"
    },
    "node_modules/merge-descriptors": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/merge-descriptors/-/merge-descriptors-2.0.0.tgz",
      "integrity": "sha512-Snk314V5ayFLhp3fkUREub6WtjBfPdCPY1Ln8/8munuLuiYhsABgBVWsozAG+MWMbVEvcdcpbi9R7ww22l9Q3g==",
      "license": "MIT",
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/methods": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/methods/-/methods-1.1.2.tgz",
      "integrity": "sha512-iclAHeNqNm68zFtnZ0e+1L2yUIdvzNoauKU4WBA3VvH/vPFieF7qfRlwUZU+DA9P9bPXIS90ulxoUoCH23sV2w==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/mime": {
      "version": "2.6.0",
      "resolved": "https://registry.npmjs.org/mime/-/mime-2.6.0.tgz",
      "integrity": "sha512-USPkMeET31rOMiarsBNIHZKLGgvKc/LrjofAnBlOttf5ajRvqiRA8QsenbcooctK6d6Ts6aqZXBA+XbkKthiQg==",
      "dev": true,
      "license": "MIT",
      "bin": {
        "mime": "cli.js"
      },
      "engines": {
        "node": ">=4.0.0"
      }
    },
    "node_modules/mime-db": {
      "version": "1.54.0",
      "resolved": "https://registry.npmjs.org/mime-db/-/mime-db-1.54.0.tgz",
      "integrity": "sha512-aU5EJuIN2WDemCcAp2vFBfp/m4EAhWJnUNSSw0ixs7/kXbd6Pg64EmwJkNdFhB8aWt1sH2CTXrLxo/iAGV3oPQ==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/mime-types": {
      "version": "3.0.2",
      "resolved": "https://registry.npmjs.org/mime-types/-/mime-types-3.0.2.tgz",
      "integrity": "sha512-Lbgzdk0h4juoQ9fCKXW4by0UJqj+nOOrI9MJ1sSj4nI8aI2eo1qmvQEie4VD1glsS250n15LsWsYtCugiStS5A==",
      "license": "MIT",
      "dependencies": {
        "mime-db": "^1.54.0"
      },
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/min-indent": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/min-indent/-/min-indent-1.0.1.tgz",
      "integrity": "sha512-I9jwMn07Sy/IwOj3zVkVik2JTvgpaykDZEigL6Rx6N9LbMywwUSMtxET+7lVoDLLd3O3IXwJwvuuns8UB/HeAg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=4"
      }
    },
    "node_modules/minimatch": {
      "version": "10.2.6",
      "resolved": "https://registry.npmjs.org/minimatch/-/minimatch-10.2.6.tgz",
      "integrity": "sha512-vpLQEs+VLCr1nU0BXS07maYoFwlDAH0gngQuuttxIwutDFEMHq2blX+8vpgxDdK3J1PwjCJiep77OitTZ4Ll1A==",
      "dev": true,
      "license": "BlueOak-1.0.0",
      "dependencies": {
        "brace-expansion": "^5.0.8"
      },
      "engines": {
        "node": "18 || 20 || >=22"
      },
      "funding": {
        "url": "https://github.com/sponsors/isaacs"
      }
    },
    "node_modules/minimist": {
      "version": "1.2.8",
      "resolved": "https://registry.npmjs.org/minimist/-/minimist-1.2.8.tgz",
      "integrity": "sha512-2yyAR8qBkN3YuheJanUpWC5U3bb5osDywNB8RzDVlDwDHbocAJveqqj1u8+SVD7jkWT4yvsHCpWqqWqAxb0zCA==",
      "license": "MIT",
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/mkdirp": {
      "version": "0.5.6",
      "resolved": "https://registry.npmjs.org/mkdirp/-/mkdirp-0.5.6.tgz",
      "integrity": "sha512-FP+p8RB8OWpF3YZBCrP5gtADmtXApB5AMLn+vdyA+PyxCjrCs00mjyUozssO33cwDeT3wNGdLxJ5M//YqtHAJw==",
      "license": "MIT",
      "dependencies": {
        "minimist": "^1.2.6"
      },
      "bin": {
        "mkdirp": "bin/cmd.js"
      }
    },
    "node_modules/mongodb": {
      "version": "7.5.0",
      "resolved": "https://registry.npmjs.org/mongodb/-/mongodb-7.5.0.tgz",
      "integrity": "sha512-5FnrEDLnvp6ycUOGLNLLU33BfCx2qmp2mJjGPDwKLruYsVzXVSK5fsGpoDXvsXJwBfBsD7ebMRdawbDxC2814g==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "@mongodb-js/saslprep": "^1.4.11",
        "bson": "^7.2.0",
        "mongodb-connection-string-url": "^7.0.1"
      },
      "engines": {
        "node": ">=20.19.0"
      },
      "peerDependencies": {
        "@aws-sdk/credential-providers": "^3.806.0",
        "@mongodb-js/zstd": "^7.0.0",
        "gcp-metadata": "^7.0.1",
        "kerberos": "^7.0.0",
        "mongodb-client-encryption": "^7.2.0",
        "snappy": "^7.3.2",
        "socks": "^2.8.6"
      },
      "peerDependenciesMeta": {
        "@aws-sdk/credential-providers": {
          "optional": true
        },
        "@mongodb-js/zstd": {
          "optional": true
        },
        "gcp-metadata": {
          "optional": true
        },
        "kerberos": {
          "optional": true
        },
        "mongodb-client-encryption": {
          "optional": true
        },
        "snappy": {
          "optional": true
        },
        "socks": {
          "optional": true
        }
      }
    },
    "node_modules/mongodb-connection-string-url": {
      "version": "7.0.2",
      "resolved": "https://registry.npmjs.org/mongodb-connection-string-url/-/mongodb-connection-string-url-7.0.2.tgz",
      "integrity": "sha512-ZoS07RoFqpKYQwAk59qmrx8+jJHNHU30UjlU96QktiGn1ltvDr+vCznLX5DiUBLEpMAHatHNWV1nM/74ul66kA==",
      "license": "Apache-2.0",
      "dependencies": {
        "@types/whatwg-url": "^13.0.0",
        "whatwg-url": "^14.1.0"
      },
      "engines": {
        "node": ">=20.19.0"
      }
    },
    "node_modules/mongodb-memory-server": {
      "version": "11.3.0",
      "resolved": "https://registry.npmjs.org/mongodb-memory-server/-/mongodb-memory-server-11.3.0.tgz",
      "integrity": "sha512-8ZCDrraqKqmAikoeKuEq+16jeWdVKwjtEAuMxxeQctHiGSGYt17W9LmoRzV1Nwnz7owyxwDKMhow4IVkNYYRKw==",
      "dev": true,
      "hasInstallScript": true,
      "license": "MIT",
      "dependencies": {
        "mongodb-memory-server-core": "11.3.0",
        "tslib": "^2.8.1"
      },
      "engines": {
        "node": ">=20.19.0"
      }
    },
    "node_modules/mongodb-memory-server-core": {
      "version": "11.3.0",
      "resolved": "https://registry.npmjs.org/mongodb-memory-server-core/-/mongodb-memory-server-core-11.3.0.tgz",
      "integrity": "sha512-QBu/RsRpBfcNd5CrBDfCzqcaFPaYpivUzGYUy9YgVc3up78ff0gIHQVD9PLmBLOOxFX6BM9hU6YT0HocZH+s1g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "async-mutex": "^0.5.0",
        "camelcase": "^6.3.0",
        "debug": "^4.4.3",
        "find-cache-dir": "^3.3.2",
        "follow-redirects": "^1.16.0",
        "https-proxy-agent": "^7.0.6",
        "mongodb": "~7.5.0",
        "new-find-package-json": "^2.0.0",
        "semver": "^7.8.5",
        "tar-stream": "^3.2.1",
        "tslib": "^2.8.1",
        "yauzl": "^3.4.0"
      },
      "engines": {
        "node": ">=20.19.0"
      }
    },
    "node_modules/mongodb-memory-server-core/node_modules/tar-stream": {
      "version": "3.2.1",
      "resolved": "https://registry.npmjs.org/tar-stream/-/tar-stream-3.2.1.tgz",
      "integrity": "sha512-nqsEO8zLZJvrOMdEwkA0QdCLFbetHMn95Zqu4fKwX+hkaTWJPZZOrxx/PwtxoK0MMGQmBQNRW3CPs8IFYQz4cQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "b4a": "^1.6.4",
        "bare-fs": "^4.5.5",
        "fast-fifo": "^1.2.0",
        "streamx": "^2.15.0"
      }
    },
    "node_modules/mongoose": {
      "version": "9.10.2",
      "resolved": "https://registry.npmjs.org/mongoose/-/mongoose-9.10.2.tgz",
      "integrity": "sha512-oFcFL3dsX5tDzMwBD+GGoDqKIj6RNG3bu3oqlvcUIgPulHP14/6N7c07j3s0XgbrlT7U/lbiXOD89hmPtEXnfQ==",
      "license": "MIT",
      "dependencies": {
        "@standard-schema/spec": "^1.1.0",
        "kareem": "3.4.0",
        "mongodb": "~7.6",
        "mpath": "0.9.0",
        "mquery": "6.0.0",
        "ms": "2.1.3",
        "sift": "17.1.3"
      },
      "engines": {
        "node": ">=20.19.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/mongoose"
      }
    },
    "node_modules/mongoose/node_modules/mongodb": {
      "version": "7.6.0",
      "resolved": "https://registry.npmjs.org/mongodb/-/mongodb-7.6.0.tgz",
      "integrity": "sha512-WbZ6OCjYw2c53LOjfkQa+reXr7kIiOVpXXglnASFuiMtif0BvsMwHe3ClJHLm1/r7wJFwaasfFtD6iYIktB01g==",
      "license": "Apache-2.0",
      "dependencies": {
        "@mongodb-js/saslprep": "^1.4.11",
        "bson": "^7.2.0",
        "mongodb-connection-string-url": "^7.0.1"
      },
      "engines": {
        "node": ">=20.19.0"
      },
      "peerDependencies": {
        "@aws-sdk/credential-providers": "^3.806.0",
        "@mongodb-js/zstd": "^7.0.0",
        "gcp-metadata": "^7.0.1",
        "kerberos": "^7.0.0",
        "mongodb-client-encryption": "^7.2.0",
        "snappy": "^7.3.2",
        "socks": "^2.8.6"
      },
      "peerDependenciesMeta": {
        "@aws-sdk/credential-providers": {
          "optional": true
        },
        "@mongodb-js/zstd": {
          "optional": true
        },
        "gcp-metadata": {
          "optional": true
        },
        "kerberos": {
          "optional": true
        },
        "mongodb-client-encryption": {
          "optional": true
        },
        "snappy": {
          "optional": true
        },
        "socks": {
          "optional": true
        }
      }
    },
    "node_modules/mpath": {
      "version": "0.9.0",
      "resolved": "https://registry.npmjs.org/mpath/-/mpath-0.9.0.tgz",
      "integrity": "sha512-ikJRQTk8hw5DEoFVxHG1Gn9T/xcjtdnOKIU1JTmGjZZlg9LST2mBLmcX3/ICIbgJydT2GOc15RnNy5mHmzfSew==",
      "license": "MIT",
      "engines": {
        "node": ">=4.0.0"
      }
    },
    "node_modules/mquery": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/mquery/-/mquery-6.0.0.tgz",
      "integrity": "sha512-b2KQNsmgtkscfeDgkYMcWGn9vZI9YoXh802VDEwE6qc50zxBFQ0Oo8ROkawbPAsXCY1/Z1yp0MagqsZStPWJjw==",
      "license": "MIT",
      "engines": {
        "node": ">=20.19.0"
      }
    },
    "node_modules/ms": {
      "version": "2.1.3",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.1.3.tgz",
      "integrity": "sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==",
      "license": "MIT"
    },
    "node_modules/nanoid": {
      "version": "3.3.19",
      "resolved": "https://registry.npmjs.org/nanoid/-/nanoid-3.3.19.tgz",
      "integrity": "sha512-Y2tUNy4ouw6tq5oDSKeQYGOyhkUBhNOcGV/02KC+6kd9eDGqdZd++mjMiIDilrBYvjEnCYvVtsuHCuP+okSfug==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "MIT",
      "bin": {
        "nanoid": "bin/nanoid.cjs"
      },
      "engines": {
        "node": "^10 || ^12 || ^13.7 || ^14 || >=15.0.1"
      }
    },
    "node_modules/natural-compare": {
      "version": "1.4.0",
      "resolved": "https://registry.npmjs.org/natural-compare/-/natural-compare-1.4.0.tgz",
      "integrity": "sha512-OWND8ei3VtNC9h7V60qff3SVobHr996CTwgxubgyQYEpg290h9J0buyECNNJexkFm5sOajh5G116RYA1c8ZMSw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/negotiator": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/negotiator/-/negotiator-1.1.0.tgz",
      "integrity": "sha512-NMPBRMJgiQHjbd8phG3Vebdx4kZ1H121rbl5IkMqeOsahptB9BKo/d7oJ3zTXqTgagn2bWlNSXkh0QUGM31RYg==",
      "license": "MIT",
      "dependencies": {
        "content-type": "^2.1.0"
      },
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/negotiator/node_modules/content-type": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/content-type/-/content-type-2.1.0.tgz",
      "integrity": "sha512-mj7UPXE0jaqaOsukNZRUEfEi2AcL7C/vwmwcHV0O97eO1E1pxBZuyjlZrx5seTaNBg1U6+o35wpa35Qfcc+7ag==",
      "license": "MIT",
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/new-find-package-json": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/new-find-package-json/-/new-find-package-json-2.0.0.tgz",
      "integrity": "sha512-lDcBsjBSMlj3LXH2v/FW3txlh2pYTjmbOXPYJD93HI5EwuLzI11tdHSIpUMmfq/IOsldj4Ps8M8flhm+pCK4Ew==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "debug": "^4.3.4"
      },
      "engines": {
        "node": ">=12.22.0"
      }
    },
    "node_modules/node-releases": {
      "version": "2.0.57",
      "resolved": "https://registry.npmjs.org/node-releases/-/node-releases-2.0.57.tgz",
      "integrity": "sha512-kQK9LGGFiHtrWiNhZtA7Qbw17AQz+dmsEKODRIVTXA9+e5MS/2gZEBhYJt13GrAz5/IOZKddH/0Z3TP/Zgo+yw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/normalize-path": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/normalize-path/-/normalize-path-3.0.0.tgz",
      "integrity": "sha512-6eZs5Ls3WtCisHWp9S2GUy8dqkpGi4BVSz3GaqiE6ezub0512ESztXUwUB6C6IKbQkY2Pnb/mD4WYojCRwcwLA==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/object-assign": {
      "version": "4.1.1",
      "resolved": "https://registry.npmjs.org/object-assign/-/object-assign-4.1.1.tgz",
      "integrity": "sha512-rJgTQnkUnH1sFw8yT6VSU3zD3sWmu6sZhIseY8VX+GRu3P6F7Fu+JNDoXfklElbLJSnc3FUQHVe4cU5hj+BcUg==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/object-inspect": {
      "version": "1.13.4",
      "resolved": "https://registry.npmjs.org/object-inspect/-/object-inspect-1.13.4.tgz",
      "integrity": "sha512-W67iLl4J2EXEGTbfeHCffrjDfitvLANg0UlX3wFUUSTx92KXRFegMHUVgSqE+wvhAbi4WqjGg9czysTV2Epbew==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/obug": {
      "version": "2.2.1",
      "resolved": "https://registry.npmjs.org/obug/-/obug-2.2.1.tgz",
      "integrity": "sha512-XrsrhT5sybtKI6wakr2SPOlGZWWYbUXZ7a0jT8/QOeAPau+1X/bSegNe5YR75oJmEZQbKningirmGOEJCIk61Q==",
      "dev": true,
      "funding": [
        "https://github.com/sponsors/sxzz",
        "https://opencollective.com/debug"
      ],
      "license": "MIT",
      "engines": {
        "node": ">=12.20.0"
      }
    },
    "node_modules/on-exit-leak-free": {
      "version": "2.1.2",
      "resolved": "https://registry.npmjs.org/on-exit-leak-free/-/on-exit-leak-free-2.1.2.tgz",
      "integrity": "sha512-0eJJY6hXLGf1udHwfNftBqH+g73EU4B504nZeKpz1sYRKafAghwxEJunB2O7rDZkL4PGfsMVnTXZ2EjibbqcsA==",
      "license": "MIT",
      "engines": {
        "node": ">=14.0.0"
      }
    },
    "node_modules/on-finished": {
      "version": "2.4.1",
      "resolved": "https://registry.npmjs.org/on-finished/-/on-finished-2.4.1.tgz",
      "integrity": "sha512-oVlzkg3ENAhCk2zdv7IJwd/QUD4z2RxRwpkcGY8psCVcCYZNq4wYnVWALHM+brtuJjePWiYF/ClmuDr8Ch5+kg==",
      "license": "MIT",
      "dependencies": {
        "ee-first": "1.1.1"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/once": {
      "version": "1.4.0",
      "resolved": "https://registry.npmjs.org/once/-/once-1.4.0.tgz",
      "integrity": "sha512-lNaJgI+2Q5URQBkccEKHTQOPaXdUxnZZElQTZY0MFUAuaEqe1E+Nyvgdz/aIyNi6Z9MzO5dv1H8n58/GELp3+w==",
      "license": "ISC",
      "dependencies": {
        "wrappy": "1"
      }
    },
    "node_modules/optionator": {
      "version": "0.9.4",
      "resolved": "https://registry.npmjs.org/optionator/-/optionator-0.9.4.tgz",
      "integrity": "sha512-6IpQ7mKUxRcZNLIObR0hz7lxsapSSIYNZJwXPGeF0mTVqGKFIXj1DQcMoT22S3ROcLyY/rz0PWaWZ9ayWmad9g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "deep-is": "^0.1.3",
        "fast-levenshtein": "^2.0.6",
        "levn": "^0.4.1",
        "prelude-ls": "^1.2.1",
        "type-check": "^0.4.0",
        "word-wrap": "^1.2.5"
      },
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/p-limit": {
      "version": "3.1.0",
      "resolved": "https://registry.npmjs.org/p-limit/-/p-limit-3.1.0.tgz",
      "integrity": "sha512-TYOanM3wGwNGsZN2cVTYPArw454xnXj5qmWF1bEoAc4+cU/ol7GVh7odevjp1FNHduHc3KZMcFduxU5Xc6uJRQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "yocto-queue": "^0.1.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/p-locate": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/p-locate/-/p-locate-5.0.0.tgz",
      "integrity": "sha512-LaNjtRWUBY++zB5nE/NwcaoMylSPk+S+ZHNB1TzdbMJMny6dynpAGt7X/tl/QYq3TIeE6nxHppbo2LGymrG5Pw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "p-limit": "^3.0.2"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/p-try": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/p-try/-/p-try-2.2.0.tgz",
      "integrity": "sha512-R4nPAVTAU0B9D35/Gk3uJf/7XYbQcyohSKdvAxIRSNghFl4e71hVoGnBNQz9cWaXxO2I10KTC+3jMdvvoKw6dQ==",
      "license": "MIT",
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/pako": {
      "version": "1.0.11",
      "resolved": "https://registry.npmjs.org/pako/-/pako-1.0.11.tgz",
      "integrity": "sha512-4hLB8Py4zZce5s4yd9XzopqwVv/yGNhV1Bl8NTmCq1763HeK2+EwVTv+leGeL13Dnh2wfbqowVPXCIO0z4taYw==",
      "license": "(MIT AND Zlib)"
    },
    "node_modules/papaparse": {
      "version": "5.7.0",
      "resolved": "https://registry.npmjs.org/papaparse/-/papaparse-5.7.0.tgz",
      "integrity": "sha512-qBGxg/7Q3Kl9Wfhrz2Z74UnvnHTXLNG6jmKJFeBvP2+y4lV7So+7SR62+Zd47JvdrCkX+nDcnr0ObPzek/+6RA==",
      "license": "MIT"
    },
    "node_modules/parse5": {
      "version": "8.0.1",
      "resolved": "https://registry.npmjs.org/parse5/-/parse5-8.0.1.tgz",
      "integrity": "sha512-z1e/HMG90obSGeidlli3hj7cbocou0/wa5HacvI3ASx34PecNjNQeaHNo5WIZpWofN9kgkqV1q5YvXe3F0FoPw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "entities": "^8.0.0"
      },
      "funding": {
        "url": "https://github.com/inikulin/parse5?sponsor=1"
      }
    },
    "node_modules/parseurl": {
      "version": "1.3.3",
      "resolved": "https://registry.npmjs.org/parseurl/-/parseurl-1.3.3.tgz",
      "integrity": "sha512-CiyeOxFT/JZyN5m0z9PfXw4SCBJ6Sygz1Dpl0wqjlhDEGGBP1GnsUVEL0p63hoG1fcj3fHynXi9NYO4nWOL+qQ==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/path-exists": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/path-exists/-/path-exists-4.0.0.tgz",
      "integrity": "sha512-ak9Qy5Q7jYb2Wwcey5Fpvg2KoAc/ZIhLSLOSBmRmygPsGwkVVt0fZa0qrtMz+m6tJTAHfZQ8FnmB4MG4LWy7/w==",
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/path-is-absolute": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/path-is-absolute/-/path-is-absolute-1.0.1.tgz",
      "integrity": "sha512-AVbw3UJ2e9bq64vSaS9Am0fje1Pa8pbGqTTsmXfaIiMpnr5DlDhfJOuLj9Sf95ZPVDAUerDfEk88MPmPe7UCQg==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/path-key": {
      "version": "3.1.1",
      "resolved": "https://registry.npmjs.org/path-key/-/path-key-3.1.1.tgz",
      "integrity": "sha512-ojmeN0qd+y0jszEtoY48r0Peq5dwMEkIlCOu6Q5f41lfkswXuKtYrhgoTpLnyIcHm24Uhqx+5Tqm2InSwLhE6Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/path-to-regexp": {
      "version": "8.4.2",
      "resolved": "https://registry.npmjs.org/path-to-regexp/-/path-to-regexp-8.4.2.tgz",
      "integrity": "sha512-qRcuIdP69NPm4qbACK+aDogI5CBDMi1jKe0ry5rSQJz8JVLsC7jV8XpiJjGRLLol3N+R5ihGYcrPLTno6pAdBA==",
      "license": "MIT",
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/pend": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/pend/-/pend-1.2.0.tgz",
      "integrity": "sha512-F3asv42UuXchdzt+xXqfW1OGlVBe+mxa2mqI0pg5yAHZPvFmY3Y6drSf/GQ1A86WgWEN9Kzh/WrgKa6iGcHXLg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/picocolors": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/picocolors/-/picocolors-1.1.1.tgz",
      "integrity": "sha512-xceH2snhtb5M9liqDsmEw56le376mTZkEX/jEb/RxNFyegNul7eNslCXP9FDj/Lcu0X8KEyMceP2ntpaHrDEVA==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/picomatch": {
      "version": "4.0.7",
      "resolved": "https://registry.npmjs.org/picomatch/-/picomatch-4.0.7.tgz",
      "integrity": "sha512-qcJu88Q2IWqJsDD529JKMdwGm/dvInW4HvQnRwiH9JtihJvzGOscDtHE3x1pBKeUOTysQ8kVmLnJ2kJu7yhcGA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12"
      },
      "funding": {
        "url": "https://github.com/sponsors/jonschlinkert"
      }
    },
    "node_modules/pino": {
      "version": "10.3.1",
      "resolved": "https://registry.npmjs.org/pino/-/pino-10.3.1.tgz",
      "integrity": "sha512-r34yH/GlQpKZbU1BvFFqOjhISRo1MNx1tWYsYvmj6KIRHSPMT2+yHOEb1SG6NMvRoHRF0a07kCOox/9yakl1vg==",
      "license": "MIT",
      "dependencies": {
        "@pinojs/redact": "^0.4.0",
        "atomic-sleep": "^1.0.0",
        "on-exit-leak-free": "^2.1.0",
        "pino-abstract-transport": "^3.0.0",
        "pino-std-serializers": "^7.0.0",
        "process-warning": "^5.0.0",
        "quick-format-unescaped": "^4.0.3",
        "real-require": "^0.2.0",
        "safe-stable-stringify": "^2.3.1",
        "sonic-boom": "^4.0.1",
        "thread-stream": "^4.0.0"
      },
      "bin": {
        "pino": "bin.js"
      }
    },
    "node_modules/pino-abstract-transport": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/pino-abstract-transport/-/pino-abstract-transport-3.0.0.tgz",
      "integrity": "sha512-wlfUczU+n7Hy/Ha5j9a/gZNy7We5+cXp8YL+X+PG8S0KXxw7n/JXA3c46Y0zQznIJ83URJiwy7Lh56WLokNuxg==",
      "license": "MIT",
      "dependencies": {
        "split2": "^4.0.0"
      }
    },
    "node_modules/pino-http": {
      "version": "11.0.0",
      "resolved": "https://registry.npmjs.org/pino-http/-/pino-http-11.0.0.tgz",
      "integrity": "sha512-wqg5XIAGRRIWtTk8qPGxkbrfiwEWz1lgedVLvhLALudKXvg1/L2lTFgTGPJ4Z2e3qcRmxoFxDuSdMdMGNM6I1g==",
      "license": "MIT",
      "dependencies": {
        "get-caller-file": "^2.0.5",
        "pino": "^10.0.0",
        "pino-std-serializers": "^7.0.0",
        "process-warning": "^5.0.0"
      }
    },
    "node_modules/pino-pretty": {
      "version": "13.1.3",
      "resolved": "https://registry.npmjs.org/pino-pretty/-/pino-pretty-13.1.3.tgz",
      "integrity": "sha512-ttXRkkOz6WWC95KeY9+xxWL6AtImwbyMHrL1mSwqwW9u+vLp/WIElvHvCSDg0xO/Dzrggz1zv3rN5ovTRVowKg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "colorette": "^2.0.7",
        "dateformat": "^4.6.3",
        "fast-copy": "^4.0.0",
        "fast-safe-stringify": "^2.1.1",
        "help-me": "^5.0.0",
        "joycon": "^3.1.1",
        "minimist": "^1.2.6",
        "on-exit-leak-free": "^2.1.0",
        "pino-abstract-transport": "^3.0.0",
        "pump": "^3.0.0",
        "secure-json-parse": "^4.0.0",
        "sonic-boom": "^4.0.1",
        "strip-json-comments": "^5.0.2"
      },
      "bin": {
        "pino-pretty": "bin.js"
      }
    },
    "node_modules/pino-std-serializers": {
      "version": "7.1.0",
      "resolved": "https://registry.npmjs.org/pino-std-serializers/-/pino-std-serializers-7.1.0.tgz",
      "integrity": "sha512-BndPH67/JxGExRgiX1dX0w1FvZck5Wa4aal9198SrRhZjH3GxKQUKIBnYJTdj2HDN3UQAS06HlfcSbQj2OHmaw==",
      "license": "MIT"
    },
    "node_modules/pkg-dir": {
      "version": "4.2.0",
      "resolved": "https://registry.npmjs.org/pkg-dir/-/pkg-dir-4.2.0.tgz",
      "integrity": "sha512-HRDzbaKjC+AOWVXxAU/x54COGeIv9eb+6CkDSQoNTt4XyWoIJvuPsXizxu/Fr23EiekbtZwmh1IcIG/l/a10GQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "find-up": "^4.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/pkg-dir/node_modules/find-up": {
      "version": "4.1.0",
      "resolved": "https://registry.npmjs.org/find-up/-/find-up-4.1.0.tgz",
      "integrity": "sha512-PpOwAdQ/YlXQ2vj8a3h8IipDuYRi3wceVQQGYWxNINccq40Anw7BlsEXCMbt1Zt+OLA6Fq9suIpIWD0OsnISlw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "locate-path": "^5.0.0",
        "path-exists": "^4.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/pkg-dir/node_modules/locate-path": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/locate-path/-/locate-path-5.0.0.tgz",
      "integrity": "sha512-t7hw9pI+WvuwNJXwk5zVHpyhIqzg2qTlklJOf0mVxGSbe3Fp2VieZcduNYjaLDoy6p9uGpQEGWG87WpMKlNq8g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "p-locate": "^4.1.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/pkg-dir/node_modules/p-limit": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/p-limit/-/p-limit-2.3.0.tgz",
      "integrity": "sha512-//88mFWSJx8lxCzwdAABTJL2MyWB12+eIY7MDL2SqLmAkeKU9qxRvWuSyTjm3FUmpBEMuFfckAIqEaVGUDxb6w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "p-try": "^2.0.0"
      },
      "engines": {
        "node": ">=6"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/pkg-dir/node_modules/p-locate": {
      "version": "4.1.0",
      "resolved": "https://registry.npmjs.org/p-locate/-/p-locate-4.1.0.tgz",
      "integrity": "sha512-R79ZZ/0wAxKGu3oYMlz8jy/kbhsNrS7SKZ7PxEHBgJ5+F2mtFW2fK2cOtBh1cHYkQsbzFV7I+EoRKe6Yt0oK7A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "p-limit": "^2.2.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/pngjs": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/pngjs/-/pngjs-5.0.0.tgz",
      "integrity": "sha512-40QW5YalBNfQo5yRYmiw7Yz6TKKVr3h6970B2YE+3fQpsWcrbj1PzJgxeJ19DRQjhMbKPIuMY8rFaXc8moolVw==",
      "license": "MIT",
      "engines": {
        "node": ">=10.13.0"
      }
    },
    "node_modules/postcss": {
      "version": "8.5.28",
      "resolved": "https://registry.npmjs.org/postcss/-/postcss-8.5.28.tgz",
      "integrity": "sha512-RRuzqDtt5Y9h3quz5hWhK+TPnsmVs6WwSU6LkJMeY4HstUEDuYTG8UJSdawMRzmzAtV+KEoG8N3Qg2qLy5vM/A==",
      "dev": true,
      "funding": [
        {
          "type": "opencollective",
          "url": "https://opencollective.com/postcss/"
        },
        {
          "type": "tidelift",
          "url": "https://tidelift.com/funding/github/npm/postcss"
        },
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "MIT",
      "dependencies": {
        "nanoid": "^3.3.18",
        "picocolors": "^1.1.1",
        "source-map-js": "^1.2.1"
      },
      "engines": {
        "node": "^10 || ^12 || >=14"
      }
    },
    "node_modules/prelude-ls": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/prelude-ls/-/prelude-ls-1.2.1.tgz",
      "integrity": "sha512-vkcDPrRZo1QZLbn5RLGPpg/WmIQ65qoWWhcGKf/b5eplkkarX0m9z8ppCat4mlOqUsWpyNuYgO3VRyrYHSzX5g==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/prettier": {
      "version": "3.9.9",
      "resolved": "https://registry.npmjs.org/prettier/-/prettier-3.9.9.tgz",
      "integrity": "sha512-Z/CJHIkdujO/OtN7nXUii0Rf3VT5SRuhjBA82Xvu2XhBUgX3nhP67T0LHceBdQLex7OOFGTox+Q5Yg8Jk2Qivg==",
      "dev": true,
      "license": "MIT",
      "bin": {
        "prettier": "bin/prettier.cjs"
      },
      "engines": {
        "node": ">=14"
      },
      "funding": {
        "url": "https://github.com/prettier/prettier?sponsor=1"
      }
    },
    "node_modules/pretty-format": {
      "version": "27.5.1",
      "resolved": "https://registry.npmjs.org/pretty-format/-/pretty-format-27.5.1.tgz",
      "integrity": "sha512-Qb1gy5OrP5+zDf2Bvnzdl3jsTf1qXVMazbvCoKhtKqVs4/YK4ozX4gKQJJVyNe+cajNPn0KoC0MC3FUmaHWEmQ==",
      "dev": true,
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "ansi-regex": "^5.0.1",
        "ansi-styles": "^5.0.0",
        "react-is": "^17.0.1"
      },
      "engines": {
        "node": "^10.13.0 || ^12.13.0 || ^14.15.0 || >=15.0.0"
      }
    },
    "node_modules/pretty-format/node_modules/ansi-regex": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/ansi-regex/-/ansi-regex-5.0.1.tgz",
      "integrity": "sha512-quJQXlTSUGL2LH9SUXo8VwsY4soanhgo6LNSm84E1LBcE8s3O0wpdiRzyR9z/ZZJMlMWv37qOOb9pdJlMUEKFQ==",
      "dev": true,
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/pretty-format/node_modules/ansi-styles": {
      "version": "5.2.0",
      "resolved": "https://registry.npmjs.org/ansi-styles/-/ansi-styles-5.2.0.tgz",
      "integrity": "sha512-Cxwpt2SfTzTtXcfOlzGEee8O+c+MmUgGrNiBcXnuWxuFJHe6a5Hz7qwhwe5OgaSYI0IJvkLqWX1ASG+cJOkEiA==",
      "dev": true,
      "license": "MIT",
      "peer": true,
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/ansi-styles?sponsor=1"
      }
    },
    "node_modules/process-nextick-args": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/process-nextick-args/-/process-nextick-args-2.0.1.tgz",
      "integrity": "sha512-3ouUOpQhtgrbOa17J7+uxOTpITYWaGP7/AhoR3+A+/1e9skrzelGi/dXzEYyvbxubEF6Wn2ypscTKiKJFFn1ag==",
      "license": "MIT"
    },
    "node_modules/process-warning": {
      "version": "5.1.0",
      "resolved": "https://registry.npmjs.org/process-warning/-/process-warning-5.1.0.tgz",
      "integrity": "sha512-jQSaVHsPgtyw60e1rQ/A+/ArPEj/S8pS/vFnyGa/gYFXrKk/6RuDkoqVDQ5NI5MmS01698ltlAk0NoDBNLujRw==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/fastify"
        },
        {
          "type": "opencollective",
          "url": "https://opencollective.com/fastify"
        }
      ],
      "license": "MIT"
    },
    "node_modules/proxy-addr": {
      "version": "2.0.8",
      "resolved": "https://registry.npmjs.org/proxy-addr/-/proxy-addr-2.0.8.tgz",
      "integrity": "sha512-5nnx0yGyVUcY6t9RnWcARWtwT9F1D8O9rt08htPvnd49W1IgZtmLkhu9WfMzQj1cFxjHIO6connUNVW5k7AVyQ==",
      "license": "MIT",
      "dependencies": {
        "forwarded": "0.2.0",
        "ipaddr.js": "1.9.1"
      },
      "engines": {
        "node": ">= 0.10"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/pump": {
      "version": "3.0.4",
      "resolved": "https://registry.npmjs.org/pump/-/pump-3.0.4.tgz",
      "integrity": "sha512-VS7sjc6KR7e1ukRFhQSY5LM2uBWAUPiOPa/A3mkKmiMwSmRFUITt0xuj+/lesgnCv+dPIEYlkzrcyXgquIHMcA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "end-of-stream": "^1.1.0",
        "once": "^1.3.1"
      }
    },
    "node_modules/punycode": {
      "version": "2.3.1",
      "resolved": "https://registry.npmjs.org/punycode/-/punycode-2.3.1.tgz",
      "integrity": "sha512-vYt7UD1U9Wg6138shLtLOvdAu+8DsC/ilFtEVHcH+wydcSpNE20AfSOduf6MkRFahL5FY7X1oU7nKVZFtfq8Fg==",
      "license": "MIT",
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/qified": {
      "version": "0.10.1",
      "resolved": "https://registry.npmjs.org/qified/-/qified-0.10.1.tgz",
      "integrity": "sha512-+Owyggi9IxT1ePKGafcI87ubSmxol6smwJ+RAHDQlx9+9cPwFWDiKFFCPuWhr9ignlGpZ9vDQLw67N4dcTVFEA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "hookified": "^2.1.1"
      },
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/qified/node_modules/hookified": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/hookified/-/hookified-2.2.0.tgz",
      "integrity": "sha512-p/LgFzRN5FeoD3DLS6bkUapeye6E4SI6yJs6KetENd18S+FBthqYq2amJUWpt5z0EQwwHemidjY5OqJGEKm5uA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/qrcode": {
      "version": "1.5.4",
      "resolved": "https://registry.npmjs.org/qrcode/-/qrcode-1.5.4.tgz",
      "integrity": "sha512-1ca71Zgiu6ORjHqFBDpnSMTR2ReToX4l1Au1VFLyVeBTFavzQnv5JxMFr3ukHVKpSrSA2MCk0lNJSykjUfz7Zg==",
      "license": "MIT",
      "dependencies": {
        "dijkstrajs": "^1.0.1",
        "pngjs": "^5.0.0",
        "yargs": "^15.3.1"
      },
      "bin": {
        "qrcode": "bin/qrcode"
      },
      "engines": {
        "node": ">=10.13.0"
      }
    },
    "node_modules/qrcode/node_modules/ansi-regex": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/ansi-regex/-/ansi-regex-5.0.1.tgz",
      "integrity": "sha512-quJQXlTSUGL2LH9SUXo8VwsY4soanhgo6LNSm84E1LBcE8s3O0wpdiRzyR9z/ZZJMlMWv37qOOb9pdJlMUEKFQ==",
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/qrcode/node_modules/ansi-styles": {
      "version": "4.3.0",
      "resolved": "https://registry.npmjs.org/ansi-styles/-/ansi-styles-4.3.0.tgz",
      "integrity": "sha512-zbB9rCJAT1rbjiVDb2hqKFHNYLxgtk8NURxZ3IZwD3F6NtxbXZQCnnSi1Lkx+IDohdPlFp222wVALIheZJQSEg==",
      "license": "MIT",
      "dependencies": {
        "color-convert": "^2.0.1"
      },
      "engines": {
        "node": ">=8"
      },
      "funding": {
        "url": "https://github.com/chalk/ansi-styles?sponsor=1"
      }
    },
    "node_modules/qrcode/node_modules/camelcase": {
      "version": "5.3.1",
      "resolved": "https://registry.npmjs.org/camelcase/-/camelcase-5.3.1.tgz",
      "integrity": "sha512-L28STB170nwWS63UjtlEOE3dldQApaJXZkOI1uMFfzf3rRuPegHaHesyee+YxQ+W6SvRDQV6UrdOdRiR153wJg==",
      "license": "MIT",
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/qrcode/node_modules/cliui": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/cliui/-/cliui-6.0.0.tgz",
      "integrity": "sha512-t6wbgtoCXvAzst7QgXxJYqPt0usEfbgQdftEPbLL/cvv6HPE5VgvqCuAIDR0NgU52ds6rFwqrgakNLrHEjCbrQ==",
      "license": "ISC",
      "dependencies": {
        "string-width": "^4.2.0",
        "strip-ansi": "^6.0.0",
        "wrap-ansi": "^6.2.0"
      }
    },
    "node_modules/qrcode/node_modules/emoji-regex": {
      "version": "8.0.0",
      "resolved": "https://registry.npmjs.org/emoji-regex/-/emoji-regex-8.0.0.tgz",
      "integrity": "sha512-MSjYzcWNOA0ewAHpz0MxpYFvwg6yjy1NG3xteoqz644VCo/RPgnr1/GGt+ic3iJTzQ8Eu3TdM14SawnVUmGE6A==",
      "license": "MIT"
    },
    "node_modules/qrcode/node_modules/find-up": {
      "version": "4.1.0",
      "resolved": "https://registry.npmjs.org/find-up/-/find-up-4.1.0.tgz",
      "integrity": "sha512-PpOwAdQ/YlXQ2vj8a3h8IipDuYRi3wceVQQGYWxNINccq40Anw7BlsEXCMbt1Zt+OLA6Fq9suIpIWD0OsnISlw==",
      "license": "MIT",
      "dependencies": {
        "locate-path": "^5.0.0",
        "path-exists": "^4.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/qrcode/node_modules/locate-path": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/locate-path/-/locate-path-5.0.0.tgz",
      "integrity": "sha512-t7hw9pI+WvuwNJXwk5zVHpyhIqzg2qTlklJOf0mVxGSbe3Fp2VieZcduNYjaLDoy6p9uGpQEGWG87WpMKlNq8g==",
      "license": "MIT",
      "dependencies": {
        "p-locate": "^4.1.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/qrcode/node_modules/p-limit": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/p-limit/-/p-limit-2.3.0.tgz",
      "integrity": "sha512-//88mFWSJx8lxCzwdAABTJL2MyWB12+eIY7MDL2SqLmAkeKU9qxRvWuSyTjm3FUmpBEMuFfckAIqEaVGUDxb6w==",
      "license": "MIT",
      "dependencies": {
        "p-try": "^2.0.0"
      },
      "engines": {
        "node": ">=6"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/qrcode/node_modules/p-locate": {
      "version": "4.1.0",
      "resolved": "https://registry.npmjs.org/p-locate/-/p-locate-4.1.0.tgz",
      "integrity": "sha512-R79ZZ/0wAxKGu3oYMlz8jy/kbhsNrS7SKZ7PxEHBgJ5+F2mtFW2fK2cOtBh1cHYkQsbzFV7I+EoRKe6Yt0oK7A==",
      "license": "MIT",
      "dependencies": {
        "p-limit": "^2.2.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/qrcode/node_modules/string-width": {
      "version": "4.2.3",
      "resolved": "https://registry.npmjs.org/string-width/-/string-width-4.2.3.tgz",
      "integrity": "sha512-wKyQRQpjJ0sIp62ErSZdGsjMJWsap5oRNihHhu6G7JVO/9jIB6UyevL+tXuOqrng8j/cxKTWyWUwvSTriiZz/g==",
      "license": "MIT",
      "dependencies": {
        "emoji-regex": "^8.0.0",
        "is-fullwidth-code-point": "^3.0.0",
        "strip-ansi": "^6.0.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/qrcode/node_modules/strip-ansi": {
      "version": "6.0.1",
      "resolved": "https://registry.npmjs.org/strip-ansi/-/strip-ansi-6.0.1.tgz",
      "integrity": "sha512-Y38VPSHcqkFrCpFnQ9vuSXmquuv5oXOKpGeT6aGrr3o3Gc9AlVa6JBfUSOCnbxGGZF+/0ooI7KrPuUSztUdU5A==",
      "license": "MIT",
      "dependencies": {
        "ansi-regex": "^5.0.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/qrcode/node_modules/wrap-ansi": {
      "version": "6.2.0",
      "resolved": "https://registry.npmjs.org/wrap-ansi/-/wrap-ansi-6.2.0.tgz",
      "integrity": "sha512-r6lPcBGxZXlIcymEu7InxDMhdW0KDxpLgoFLcguasxCaJ/SOIZwINatK9KY/tf+ZrlywOKU0UDj3ATXUBfxJXA==",
      "license": "MIT",
      "dependencies": {
        "ansi-styles": "^4.0.0",
        "string-width": "^4.1.0",
        "strip-ansi": "^6.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/qrcode/node_modules/y18n": {
      "version": "4.0.3",
      "resolved": "https://registry.npmjs.org/y18n/-/y18n-4.0.3.tgz",
      "integrity": "sha512-JKhqTOwSrqNA1NY5lSztJ1GrBiUodLMmIZuLiDaMRJ+itFd+ABVE8XBjOvIWL+rSqNDC74LCSFmlb/U4UZ4hJQ==",
      "license": "ISC"
    },
    "node_modules/qrcode/node_modules/yargs": {
      "version": "15.4.1",
      "resolved": "https://registry.npmjs.org/yargs/-/yargs-15.4.1.tgz",
      "integrity": "sha512-aePbxDmcYW++PaqBsJ+HYUFwCdv4LVvdnhBy78E57PIor8/OVvhMrADFFEDh8DHDFRv/O9i3lPhsENjO7QX0+A==",
      "license": "MIT",
      "dependencies": {
        "cliui": "^6.0.0",
        "decamelize": "^1.2.0",
        "find-up": "^4.1.0",
        "get-caller-file": "^2.0.1",
        "require-directory": "^2.1.1",
        "require-main-filename": "^2.0.0",
        "set-blocking": "^2.0.0",
        "string-width": "^4.2.0",
        "which-module": "^2.0.0",
        "y18n": "^4.0.0",
        "yargs-parser": "^18.1.2"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/qrcode/node_modules/yargs-parser": {
      "version": "18.1.3",
      "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-18.1.3.tgz",
      "integrity": "sha512-o50j0JeToy/4K6OZcaQmW6lyXXKhq7csREXcDwk2omFPJEwUNOVtJKvmDr9EI1fAJZUyZcRF7kxGBWmRXudrCQ==",
      "license": "ISC",
      "dependencies": {
        "camelcase": "^5.0.0",
        "decamelize": "^1.2.0"
      },
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/qs": {
      "version": "6.16.0",
      "resolved": "https://registry.npmjs.org/qs/-/qs-6.16.0.tgz",
      "integrity": "sha512-h6fhOIaRrID2CbEY2fqs+7t+UXZo+MLAnU5gRIq85uFtdiUPCdsApMlHhXogKVM4HM2DVbIjGNTTYH2OcmP1vA==",
      "license": "BSD-3-Clause",
      "dependencies": {
        "es-define-property": "^1.0.1",
        "side-channel": "^1.1.1"
      },
      "engines": {
        "node": ">=0.6"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/quick-format-unescaped": {
      "version": "4.0.4",
      "resolved": "https://registry.npmjs.org/quick-format-unescaped/-/quick-format-unescaped-4.0.4.tgz",
      "integrity": "sha512-tYC1Q1hgyRuHgloV/YXs2w15unPVh8qfu/qCTfhTYamaw7fyhumKa2yGpdSo87vY32rIclj+4fWYQXUMs9EHvg==",
      "license": "MIT"
    },
    "node_modules/range-parser": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/range-parser/-/range-parser-1.3.0.tgz",
      "integrity": "sha512-hek2mFQpPuI4E1BBKrSto+BU3e3x4xuarsbiwr3+lf7p44juvFMV0XFWQAP3xUyqXA4RrXLIoaSUGbSt056ZMw==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/raw-body": {
      "version": "3.0.2",
      "resolved": "https://registry.npmjs.org/raw-body/-/raw-body-3.0.2.tgz",
      "integrity": "sha512-K5zQjDllxWkf7Z5xJdV0/B0WTNqx6vxG70zJE4N0kBs4LovmEYWJzQGxC9bS9RAKu3bgM40lrd5zoLJ12MQ5BA==",
      "license": "MIT",
      "dependencies": {
        "bytes": "~3.1.2",
        "http-errors": "~2.0.1",
        "iconv-lite": "~0.7.0",
        "unpipe": "~1.0.0"
      },
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/react": {
      "version": "19.3.0",
      "resolved": "https://registry.npmjs.org/react/-/react-19.3.0.tgz",
      "integrity": "sha512-E8LUcbtBWt20bbl2YoHfx4ZDBdxVTfOKtCZn9cDSJ4l6/nuoApcpIBcj47t2wZoVX8g2ZHuMHbiShgCR1T5Sog==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/react-dom": {
      "version": "19.3.0",
      "resolved": "https://registry.npmjs.org/react-dom/-/react-dom-19.3.0.tgz",
      "integrity": "sha512-JDk8dgif51OjFoDE70+OT9ICyYr+69HlmihNwp1+Nsfbna3t5sIiCa9ZJktDmQ4/1b/rn26hIAR2uYXDMr5r0Q==",
      "license": "MIT",
      "dependencies": {
        "scheduler": "^0.28.0"
      },
      "peerDependencies": {
        "react": "^19.3.0"
      }
    },
    "node_modules/react-hook-form": {
      "version": "7.89.0",
      "resolved": "https://registry.npmjs.org/react-hook-form/-/react-hook-form-7.89.0.tgz",
      "integrity": "sha512-vKcoCfy8RKZDrhSdqsRFp0uEOdS1AhLjOL6hR7Wmfzg1akNxEhaPf5WORx8SgEQPVXakdDyDkqQp+KNxVnnPHg==",
      "license": "MIT",
      "engines": {
        "node": ">=18.0.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/react-hook-form"
      },
      "peerDependencies": {
        "@types/react": "*",
        "react": "^16.8.0 || ^17 || ^18 || ^19"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        }
      }
    },
    "node_modules/react-is": {
      "version": "17.0.2",
      "resolved": "https://registry.npmjs.org/react-is/-/react-is-17.0.2.tgz",
      "integrity": "sha512-w2GsyukL62IJnlaff/nRegPQR94C/XXamvMWmSHRJ4y7Ts/4ocGRmTHvOs8PSE6pB3dWOrD/nueuU5sduBsQ4w==",
      "dev": true,
      "license": "MIT",
      "peer": true
    },
    "node_modules/react-router": {
      "version": "8.4.0",
      "resolved": "https://registry.npmjs.org/react-router/-/react-router-8.4.0.tgz",
      "integrity": "sha512-JtydAkBvU9UTEe5qNC+POhu+ZBNM7rlKY2IegwXc7Idj7xfRG16x5RZrw3mju+XlqBxfvb2ky9P3jUp9WyWC1g==",
      "license": "MIT",
      "dependencies": {
        "@remix-run/route-pattern": "^0.22.1",
        "cookie-es": "^3.1.1"
      },
      "engines": {
        "node": ">=22.22.0"
      },
      "peerDependencies": {
        "react": ">=19.2.7",
        "react-dom": ">=19.2.7"
      },
      "peerDependenciesMeta": {
        "react-dom": {
          "optional": true
        }
      }
    },
    "node_modules/readable-stream": {
      "version": "3.6.2",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-3.6.2.tgz",
      "integrity": "sha512-9u/sniCrY3D5WdsERHzHE4G2YCXqoG5FTHUiCC4SIbr6XcLZBY05ya9EKjYek9O5xOAwjGq+1JdGBAS7Q9ScoA==",
      "license": "MIT",
      "dependencies": {
        "inherits": "^2.0.3",
        "string_decoder": "^1.1.1",
        "util-deprecate": "^1.0.1"
      },
      "engines": {
        "node": ">= 6"
      }
    },
    "node_modules/readdir-glob": {
      "version": "1.1.3",
      "resolved": "https://registry.npmjs.org/readdir-glob/-/readdir-glob-1.1.3.tgz",
      "integrity": "sha512-v05I2k7xN8zXvPD9N+z/uhXPaj0sUFCe2rcWZIpBsqxfP7xXFQ0tipAd/wjj1YxWyWtUS5IDJpOG82JKt2EAVA==",
      "license": "Apache-2.0",
      "dependencies": {
        "minimatch": "^5.1.0"
      }
    },
    "node_modules/readdir-glob/node_modules/balanced-match": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/balanced-match/-/balanced-match-1.0.2.tgz",
      "integrity": "sha512-3oSeUO0TMV67hN1AmbXsK4yaqU7tjiHlbxRDZOpH0KW9+CeX4bRAaX0Anxt0tx2MrpRpWwQaPwIlISEJhYU5Pw==",
      "license": "MIT"
    },
    "node_modules/readdir-glob/node_modules/brace-expansion": {
      "version": "2.1.7",
      "resolved": "https://registry.npmjs.org/brace-expansion/-/brace-expansion-2.1.7.tgz",
      "integrity": "sha512-uZbew1NqdmPDTMJ8ah1y+b+9QEJrfkXFk3RcTQw3X0jW/xRUvFKsg1CfQdSYGdTbXZWExtU3J3ccxtnfw1Fi0g==",
      "license": "MIT",
      "dependencies": {
        "balanced-match": "^1.0.0"
      }
    },
    "node_modules/readdir-glob/node_modules/minimatch": {
      "version": "5.1.9",
      "resolved": "https://registry.npmjs.org/minimatch/-/minimatch-5.1.9.tgz",
      "integrity": "sha512-7o1wEA2RyMP7Iu7GNba9vc0RWWGACJOCZBJX2GJWip0ikV+wcOsgVuY9uE8CPiyQhkGFSlhuSkZPavN7u1c2Fw==",
      "license": "ISC",
      "dependencies": {
        "brace-expansion": "^2.0.1"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/real-require": {
      "version": "0.2.0",
      "resolved": "https://registry.npmjs.org/real-require/-/real-require-0.2.0.tgz",
      "integrity": "sha512-57frrGM/OCTLqLOAh0mhVA9VBMHd+9U7Zb2THMGdBUoZVOtGbJzjxsYGDJ3A9AYYCP4hn6y1TVbaOfzWtm5GFg==",
      "license": "MIT",
      "engines": {
        "node": ">= 12.13.0"
      }
    },
    "node_modules/redent": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/redent/-/redent-3.0.0.tgz",
      "integrity": "sha512-6tDA8g98We0zd0GvVeMT9arEOnTw9qM03L9cJXaCjrip1OO764RDBLBfrB4cwzNGDj5OA5ioymC9GkizgWJDUg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "indent-string": "^4.0.0",
        "strip-indent": "^3.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/require-directory": {
      "version": "2.1.1",
      "resolved": "https://registry.npmjs.org/require-directory/-/require-directory-2.1.1.tgz",
      "integrity": "sha512-fGxEI7+wsG9xrvdjsrlmL22OMTTiHRwAMroiEeMgq8gzoLC/PQr7RsRDSTLUg/bZAZtF+TVIkHc6/4RIKrui+Q==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/require-from-string": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/require-from-string/-/require-from-string-2.0.2.tgz",
      "integrity": "sha512-Xf0nWe6RseziFMu+Ap9biiUbmplq6S9/p+7w7YXP/JBHhrUDDUhwa+vANyubuqfZWTveU//DYVGsDG7RKL/vEw==",
      "devOptional": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/require-main-filename": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/require-main-filename/-/require-main-filename-2.0.0.tgz",
      "integrity": "sha512-NKN5kMDylKuldxYLSUfrbo5Tuzh4hd+2E8NPPX02mZtn1VuREQToYe/ZdlJy+J3uCpfaiGF05e7B8W0iXbQHmg==",
      "license": "ISC"
    },
    "node_modules/rimraf": {
      "version": "2.7.1",
      "resolved": "https://registry.npmjs.org/rimraf/-/rimraf-2.7.1.tgz",
      "integrity": "sha512-uWjbaKIK3T1OSVptzX7Nl6PvQ3qAGtKEtVRjRuazjfL3Bx5eI409VZSqgND+4UNnmzLVdPj9FqFJNPqBZFve4w==",
      "deprecated": "Rimraf versions prior to v4 are no longer supported",
      "license": "ISC",
      "dependencies": {
        "glob": "^7.1.3"
      },
      "bin": {
        "rimraf": "bin.js"
      }
    },
    "node_modules/rolldown": {
      "version": "1.2.11",
      "resolved": "https://registry.npmjs.org/rolldown/-/rolldown-1.2.11.tgz",
      "integrity": "sha512-qpSwIyz0jHQq5qXBTNxFmE6664rJ7O+4TvPFOiOaBSrz8IOHc1koKKSqTM2H6u1UG1+TveuC6vaDHKXFOvb1Kw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@oxc-project/types": "=0.151.0",
        "@rolldown/pluginutils": "^1.0.0"
      },
      "bin": {
        "rolldown": "bin/cli.mjs"
      },
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      },
      "optionalDependencies": {
        "@rolldown/binding-android-arm-eabi": "1.2.11",
        "@rolldown/binding-android-arm64": "1.2.11",
        "@rolldown/binding-darwin-arm64": "1.2.11",
        "@rolldown/binding-darwin-x64": "1.2.11",
        "@rolldown/binding-freebsd-x64": "1.2.11",
        "@rolldown/binding-linux-arm-gnueabihf": "1.2.11",
        "@rolldown/binding-linux-arm64-gnu": "1.2.11",
        "@rolldown/binding-linux-arm64-musl": "1.2.11",
        "@rolldown/binding-linux-ppc64-gnu": "1.2.11",
        "@rolldown/binding-linux-s390x-gnu": "1.2.11",
        "@rolldown/binding-linux-x64-gnu": "1.2.11",
        "@rolldown/binding-linux-x64-musl": "1.2.11",
        "@rolldown/binding-openharmony-arm64": "1.2.11",
        "@rolldown/binding-win32-arm64-msvc": "1.2.11",
        "@rolldown/binding-win32-x64-msvc": "1.2.11"
      }
    },
    "node_modules/router": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/router/-/router-2.2.0.tgz",
      "integrity": "sha512-nLTrUKm2UyiL7rlhapu/Zl45FwNgkZGaCpZbIHajDYgwlJCOzLSk+cIPAnsEqV955GjILJnKbdQC1nVPz+gAYQ==",
      "license": "MIT",
      "dependencies": {
        "debug": "^4.4.0",
        "depd": "^2.0.0",
        "is-promise": "^4.0.0",
        "parseurl": "^1.3.3",
        "path-to-regexp": "^8.0.0"
      },
      "engines": {
        "node": ">= 18"
      }
    },
    "node_modules/rxjs": {
      "version": "7.8.2",
      "resolved": "https://registry.npmjs.org/rxjs/-/rxjs-7.8.2.tgz",
      "integrity": "sha512-dhKf903U/PQZY6boNNtAGdWbG85WAbjT/1xYoZIC7FAY0yWapOBQVsVrDl58W86//e1VpMNBtRV4MaXfdMySFA==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "tslib": "^2.1.0"
      }
    },
    "node_modules/safe-buffer": {
      "version": "5.2.1",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.2.1.tgz",
      "integrity": "sha512-rp3So07KcdmmKbGvgaNxQSJr7bGVSVk5S9Eq1F+ppbRo70+YeaDxkw5Dd8NPN+GD6bjnYm2VuPuCXmpuYvmCXQ==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "MIT"
    },
    "node_modules/safe-stable-stringify": {
      "version": "2.5.0",
      "resolved": "https://registry.npmjs.org/safe-stable-stringify/-/safe-stable-stringify-2.5.0.tgz",
      "integrity": "sha512-b3rppTKm9T+PsVCBEOUR46GWI7fdOs00VKZ1+9c1EWDaDMvjQc6tUwuFyIprgGgTcWoVHSKrU8H31ZHA2e0RHA==",
      "license": "MIT",
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/safer-buffer": {
      "version": "2.1.2",
      "resolved": "https://registry.npmjs.org/safer-buffer/-/safer-buffer-2.1.2.tgz",
      "integrity": "sha512-YZo3K82SD7Riyi0E1EQPojLz7kpepnSQI9IyPbHHg1XXXevb5dJI7tpyN2ADxGcQbHG7vcyRHk0cbwqcQriUtg==",
      "license": "MIT"
    },
    "node_modules/saxes": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/saxes/-/saxes-5.0.1.tgz",
      "integrity": "sha512-5LBh1Tls8c9xgGjw3QrMwETmTMVk0oFgvrFSvWx62llR2hcEInrKNZ2GZCCuuy2lvWrdl5jhbpeqc5hRYKFOcw==",
      "license": "ISC",
      "dependencies": {
        "xmlchars": "^2.2.0"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/scheduler": {
      "version": "0.28.0",
      "resolved": "https://registry.npmjs.org/scheduler/-/scheduler-0.28.0.tgz",
      "integrity": "sha512-juorfCmIkIw8tT+p5BXSm6PJjQF/ycEYmKyzURCIt/RaZIhL+PulbQ9Yu2z1HdOJDdqDTlxA1+xKBmHXJsczAw==",
      "license": "MIT"
    },
    "node_modules/secure-json-parse": {
      "version": "4.1.0",
      "resolved": "https://registry.npmjs.org/secure-json-parse/-/secure-json-parse-4.1.0.tgz",
      "integrity": "sha512-l4KnYfEyqYJxDwlNVyRfO2E4NTHfMKAWdUuA8J0yve2Dz/E/PdBepY03RvyJpssIpRFwJoCD55wA+mEDs6ByWA==",
      "dev": true,
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/fastify"
        },
        {
          "type": "opencollective",
          "url": "https://opencollective.com/fastify"
        }
      ],
      "license": "BSD-3-Clause"
    },
    "node_modules/semver": {
      "version": "7.8.5",
      "resolved": "https://registry.npmjs.org/semver/-/semver-7.8.5.tgz",
      "integrity": "sha512-Y7/KDsb8LjooZpwaqGyulO6DQlksgCncchHGk+sZIY4SBvUocMBEFH5Ur1fI4dV+Jvl0w6cjvucaIi40puRioA==",
      "license": "ISC",
      "bin": {
        "semver": "bin/semver.js"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/send": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/send/-/send-1.2.1.tgz",
      "integrity": "sha512-1gnZf7DFcoIcajTjTwjwuDjzuz4PPcY2StKPlsGAQ1+YH20IRVrBaXSWmdjowTJ6u8Rc01PoYOGHXfP1mYcZNQ==",
      "license": "MIT",
      "dependencies": {
        "debug": "^4.4.3",
        "encodeurl": "^2.0.0",
        "escape-html": "^1.0.3",
        "etag": "^1.8.1",
        "fresh": "^2.0.0",
        "http-errors": "^2.0.1",
        "mime-types": "^3.0.2",
        "ms": "^2.1.3",
        "on-finished": "^2.4.1",
        "range-parser": "^1.2.1",
        "statuses": "^2.0.2"
      },
      "engines": {
        "node": ">= 18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/serve-static": {
      "version": "2.2.1",
      "resolved": "https://registry.npmjs.org/serve-static/-/serve-static-2.2.1.tgz",
      "integrity": "sha512-xRXBn0pPqQTVQiC8wyQrKs2MOlX24zQ0POGaj0kultvoOCstBQM5yvOhAVSUwOMjQtTvsPWoNCHfPGwaaQJhTw==",
      "license": "MIT",
      "dependencies": {
        "encodeurl": "^2.0.0",
        "escape-html": "^1.0.3",
        "parseurl": "^1.3.3",
        "send": "^1.2.0"
      },
      "engines": {
        "node": ">= 18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/set-blocking": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/set-blocking/-/set-blocking-2.0.0.tgz",
      "integrity": "sha512-KiKBS8AnWGEyLzofFfmvKwpdPzqiy16LvQfK3yv/fVH7Bj13/wl3JSR1J+rfgRE9q7xUJK4qvgS8raSOeLUehw==",
      "license": "ISC"
    },
    "node_modules/setimmediate": {
      "version": "1.0.5",
      "resolved": "https://registry.npmjs.org/setimmediate/-/setimmediate-1.0.5.tgz",
      "integrity": "sha512-MATJdZp8sLqDl/68LfQmbP8zKPLQNV6BIZoIgrscFDQ+RsvK/BxeDQOgyxKKoh0y/8h3BqVFnCqQ/gd+reiIXA==",
      "license": "MIT"
    },
    "node_modules/setprototypeof": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/setprototypeof/-/setprototypeof-1.2.0.tgz",
      "integrity": "sha512-E5LDX7Wrp85Kil5bhZv46j8jOeboKq5JMmYM3gVGdGH8xFpPWXUMsNrlODCrkoxMEeNi/XZIwuRvY4XNwYMJpw==",
      "license": "ISC"
    },
    "node_modules/shebang-command": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/shebang-command/-/shebang-command-2.0.0.tgz",
      "integrity": "sha512-kHxr2zZpYtdmrN1qDjrrX/Z1rR1kG8Dx+gkpK1G4eXmvXswmcE1hTWBWYUzlraYw1/yZp6YuDY77YtvbN0dmDA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "shebang-regex": "^3.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/shebang-regex": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/shebang-regex/-/shebang-regex-3.0.0.tgz",
      "integrity": "sha512-7++dFhtcx3353uBaq8DDR4NuxBetBzC7ZQOhmTQInHEd6bSrXdiEyzCvG07Z44UYdLShWUyXt5M/yhz8ekcb1A==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/shell-quote": {
      "version": "1.9.0",
      "resolved": "https://registry.npmjs.org/shell-quote/-/shell-quote-1.9.0.tgz",
      "integrity": "sha512-Iov+JwFv/2HcTpcwNMKd8+IWNb8tboQJNQTkAY/LLVK7gGH9jy+LGkVqPxfekHl+yMmiqXszdGWXgkfml7hjqA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/side-channel/-/side-channel-1.1.1.tgz",
      "integrity": "sha512-6x6dK6zJdpTzF4sQeNYxwtvBzf6Eg4GtlesS94HOvTudUeyK2WXAaIfmDgsyslYrRBeFIlsi54AYsFGUuhmvrQ==",
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "object-inspect": "^1.13.4",
        "side-channel-list": "^1.0.1",
        "side-channel-map": "^1.0.1",
        "side-channel-weakmap": "^1.0.2"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel-list": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/side-channel-list/-/side-channel-list-1.0.1.tgz",
      "integrity": "sha512-mjn/0bi/oUURjc5Xl7IaWi/OJJJumuoJFQJfDDyO46+hBWsfaVM65TBHq2eoZBhzl9EchxOijpkbRC8SVBQU0w==",
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "object-inspect": "^1.13.4"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel-map": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/side-channel-map/-/side-channel-map-1.0.1.tgz",
      "integrity": "sha512-VCjCNfgMsby3tTdo02nbjtM/ewra6jPHmpThenkTYh8pG9ucZ/1P8So4u4FGBek/BjpOVsDCMoLA/iuBKIFXRA==",
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.2",
        "es-errors": "^1.3.0",
        "get-intrinsic": "^1.2.5",
        "object-inspect": "^1.13.3"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel-weakmap": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/side-channel-weakmap/-/side-channel-weakmap-1.0.2.tgz",
      "integrity": "sha512-WPS/HvHQTYnHisLo9McqBHOJk2FkHO/tlpvldyrnem4aeQp4hai3gythswg6p01oSoTl58rcpiFAjF2br2Ak2A==",
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.2",
        "es-errors": "^1.3.0",
        "get-intrinsic": "^1.2.5",
        "object-inspect": "^1.13.3",
        "side-channel-map": "^1.0.1"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/sift": {
      "version": "17.1.3",
      "resolved": "https://registry.npmjs.org/sift/-/sift-17.1.3.tgz",
      "integrity": "sha512-Rtlj66/b0ICeFzYTuNvX/EF1igRbbnGSvEyT79McoZa/DeGhMyC5pWKOEsZKnpkqtSeovd5FL/bjHWC3CIIvCQ==",
      "license": "MIT"
    },
    "node_modules/sonic-boom": {
      "version": "4.2.1",
      "resolved": "https://registry.npmjs.org/sonic-boom/-/sonic-boom-4.2.1.tgz",
      "integrity": "sha512-w6AxtubXa2wTXAUsZMMWERrsIRAdrK0Sc+FUytWvYAhBJLyuI4llrMIC1DtlNSdI99EI86KZum2MMq3EAZlF9Q==",
      "license": "MIT",
      "dependencies": {
        "atomic-sleep": "^1.0.0"
      }
    },
    "node_modules/sonner": {
      "version": "2.0.8",
      "resolved": "https://registry.npmjs.org/sonner/-/sonner-2.0.8.tgz",
      "integrity": "sha512-UM/ByIoFra8yzV75n1o0Puu0bw5U/9UNnDacrJNspekBewIfsQ3D6ez1nvlWpt7aTsO6rujQtifBpycwIivqlg==",
      "license": "MIT",
      "peerDependencies": {
        "@types/react": "^18.0.0 || ^19.0.0",
        "react": "^18.0.0 || ^19.0.0 || ^19.0.0-rc",
        "react-dom": "^18.0.0 || ^19.0.0 || ^19.0.0-rc"
      },
      "peerDependenciesMeta": {
        "@types/react": {
          "optional": true
        }
      }
    },
    "node_modules/source-map-js": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/source-map-js/-/source-map-js-1.2.1.tgz",
      "integrity": "sha512-UXWMKhLOwVKb728IUtQPXxfYU+usdybtUrK/8uGE8CQMvrhOpwvzDBwj0QhSL7MQc7vIsISBG8VQ8+IDQxpfQA==",
      "dev": true,
      "license": "BSD-3-Clause",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/sparse-bitfield": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/sparse-bitfield/-/sparse-bitfield-3.0.3.tgz",
      "integrity": "sha512-kvzhi7vqKTfkh0PZU+2D2PIllw2ymqJKujUcyPMd9Y75Nv4nPbGJZXNhxsgdQab2BmlDct1YnfQCguEvHr7VsQ==",
      "license": "MIT",
      "dependencies": {
        "memory-pager": "^1.0.2"
      }
    },
    "node_modules/split2": {
      "version": "4.2.0",
      "resolved": "https://registry.npmjs.org/split2/-/split2-4.2.0.tgz",
      "integrity": "sha512-UcjcJOWknrNkF6PLX83qcHM6KHgVKNkV62Y8a5uYDVv9ydGQVwAHMKqHdJje1VTWpljG0WYpCDhrCdAOYH4TWg==",
      "license": "ISC",
      "engines": {
        "node": ">= 10.x"
      }
    },
    "node_modules/statuses": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/statuses/-/statuses-2.0.2.tgz",
      "integrity": "sha512-DvEy55V3DB7uknRo+4iOGT5fP1slR8wQohVdknigZPMpMstaKJQWhwiYBACJE3Ul2pTnATihhBYnRhZQHGBiRw==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/std-env": {
      "version": "4.2.0",
      "resolved": "https://registry.npmjs.org/std-env/-/std-env-4.2.0.tgz",
      "integrity": "sha512-oCUKSupKTHX53EyjDtuZQ64pjLJ6yYCtpmEw0goYxtjG9KpbRe8KAsl2tBUGU9DyMcJ0RwJ8GqJAFzMXcXW1Rw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/streamx": {
      "version": "2.28.1",
      "resolved": "https://registry.npmjs.org/streamx/-/streamx-2.28.1.tgz",
      "integrity": "sha512-zEzXb0s5Cds7tqMH6rhZ05lcJydCWiQPEwiNngVqzsxCc962vLY4Uw+mW7od8kDH258k2Uz/JrOkdIAAhSh9VA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "events-universal": "^1.0.0",
        "fast-fifo": "^1.3.2",
        "text-decoder": "^1.1.0"
      }
    },
    "node_modules/string_decoder": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.3.0.tgz",
      "integrity": "sha512-hkRX8U1WjJFd8LsDJ2yQ/wWWxaopEsABU1XfkM8A+j0+85JAGppt16cr1Whg6KIbb4okU6Mql6BOj+uup/wKeA==",
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.2.0"
      }
    },
    "node_modules/string-width": {
      "version": "7.2.0",
      "resolved": "https://registry.npmjs.org/string-width/-/string-width-7.2.0.tgz",
      "integrity": "sha512-tsaTIkKW9b4N+AEj+SVA+WhJzV7/zMhcSu78mLKWSk7cXMOSHsBKFWUs0fWwq8QyK3MgJBQRX6Gbi4kYbdvGkQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "emoji-regex": "^10.3.0",
        "get-east-asian-width": "^1.0.0",
        "strip-ansi": "^7.1.0"
      },
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/strip-ansi": {
      "version": "7.2.0",
      "resolved": "https://registry.npmjs.org/strip-ansi/-/strip-ansi-7.2.0.tgz",
      "integrity": "sha512-yDPMNjp4WyfYBkHnjIRLfca1i6KMyGCtsVgoKe/z1+6vukgaENdgGBZt+ZmKPc4gavvEZ5OgHfHdrazhgNyG7w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "ansi-regex": "^6.2.2"
      },
      "engines": {
        "node": ">=12"
      },
      "funding": {
        "url": "https://github.com/chalk/strip-ansi?sponsor=1"
      }
    },
    "node_modules/strip-indent": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/strip-indent/-/strip-indent-3.0.0.tgz",
      "integrity": "sha512-laJTa3Jb+VQpaC6DseHhF7dXVqHTfJPCRDaEbid/drOhgitgYku/letMUqOXFoWV0zIIUbjpdH2t+tYj4bQMRQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "min-indent": "^1.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/strip-json-comments": {
      "version": "5.0.3",
      "resolved": "https://registry.npmjs.org/strip-json-comments/-/strip-json-comments-5.0.3.tgz",
      "integrity": "sha512-1tB5mhVo7U+ETBKNf92xT4hrQa3pm0MZ0PQvuDnWgAAGHDsfp4lPSpiS6psrSiet87wyGPh9ft6wmhOMQ0hDiw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=14.16"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/superagent": {
      "version": "10.4.1",
      "resolved": "https://registry.npmjs.org/superagent/-/superagent-10.4.1.tgz",
      "integrity": "sha512-PVMkMrhKrSTtFhUU8jiWuGh/gyRMKiyCTCmm0+qVzRNxlfntmRKJkDhlEXN62x3HIb33sQ4kmL8lcSdccWAchQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "component-emitter": "^1.3.1",
        "cookiejar": "^2.1.4",
        "debug": "^4.3.7",
        "fast-safe-stringify": "^2.1.1",
        "form-data": "^4.0.5",
        "formidable": "^3.5.4",
        "methods": "^1.1.2",
        "mime": "2.6.0",
        "qs": "^6.14.1"
      },
      "engines": {
        "node": ">=14.18.0"
      }
    },
    "node_modules/supertest": {
      "version": "7.3.0",
      "resolved": "https://registry.npmjs.org/supertest/-/supertest-7.3.0.tgz",
      "integrity": "sha512-UwwmWq3xLhyU96c521wYNaBg7IqX78Wpj4FKs6Katp6vdklX42zU5ESvX3KeZRLFyO44RwFp4yvxYMNZzCcX9g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "cookie-signature": "^1.2.2",
        "methods": "^1.1.2",
        "superagent": "^10.3.0"
      },
      "engines": {
        "node": ">=14.18.0"
      }
    },
    "node_modules/supertest/node_modules/cookie-signature": {
      "version": "1.2.2",
      "resolved": "https://registry.npmjs.org/cookie-signature/-/cookie-signature-1.2.2.tgz",
      "integrity": "sha512-D76uU73ulSXrD1UXF4KE2TMxVVwhsnCgfAyTg9k8P6KGZjlXKrOLe4dJQKI3Bxi5wjesZoFXJWElNWBjPZMbhg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6.6.0"
      }
    },
    "node_modules/supports-color": {
      "version": "10.2.2",
      "resolved": "https://registry.npmjs.org/supports-color/-/supports-color-10.2.2.tgz",
      "integrity": "sha512-SS+jx45GF1QjgEXQx4NJZV9ImqmO2NPz5FNsIHrsDjh2YsHnawpan7SNQ1o8NuhrbHZy9AZhIoCUiCeaW/C80g==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "url": "https://github.com/chalk/supports-color?sponsor=1"
      }
    },
    "node_modules/tagged-tag": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/tagged-tag/-/tagged-tag-1.0.0.tgz",
      "integrity": "sha512-yEFYrVhod+hdNyx7g5Bnkkb0G6si8HJurOoOEgC8B/O0uXLHlaey/65KRv6cuWBNhBgHKAROVpc7QyYqE5gFng==",
      "license": "MIT",
      "engines": {
        "node": ">=20"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/tailwind-merge": {
      "version": "3.7.0",
      "resolved": "https://registry.npmjs.org/tailwind-merge/-/tailwind-merge-3.7.0.tgz",
      "integrity": "sha512-XPPUyAc+cvspz3lHTcR/QgPfW2A0lv/xQNIjX3HGhLR+Nq2lHaLq5MtTesHn8GUr3W3DguT2KT5x3NVgRtYwmA==",
      "license": "MIT",
      "funding": {
        "type": "github",
        "url": "https://github.com/sponsors/dcastil"
      }
    },
    "node_modules/tailwindcss": {
      "version": "4.3.3",
      "resolved": "https://registry.npmjs.org/tailwindcss/-/tailwindcss-4.3.3.tgz",
      "integrity": "sha512-gOhV3P7ufE62QDGg1zVaTgCR+EtPv92k2nIhVcVKcLmxT1sUBsQGhnZj175j+MqRt4zLF7ic+sCYjfhxMxj7YQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/tapable": {
      "version": "2.3.3",
      "resolved": "https://registry.npmjs.org/tapable/-/tapable-2.3.3.tgz",
      "integrity": "sha512-uxc/zpqFg6x7C8vOE7lh6Lbda8eEL9zmVm/PLeTPBRhh1xCgdWaQ+J1CUieGpIfm2HdtsUpRv+HshiasBMcc6A==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=6"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/webpack"
      }
    },
    "node_modules/tar-stream": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/tar-stream/-/tar-stream-2.2.0.tgz",
      "integrity": "sha512-ujeqbceABgwMZxEJnk2HDY2DlnUZ+9oEcb1KzTVfYHio0UE6dG71n60d8D2I4qNvleWrrXpmjpt7vZeF1LnMZQ==",
      "license": "MIT",
      "dependencies": {
        "bl": "^4.0.3",
        "end-of-stream": "^1.4.1",
        "fs-constants": "^1.0.0",
        "inherits": "^2.0.3",
        "readable-stream": "^3.1.1"
      },
      "engines": {
        "node": ">=6"
      }
    },
    "node_modules/teex": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/teex/-/teex-1.0.1.tgz",
      "integrity": "sha512-eYE6iEI62Ni1H8oIa7KlDU6uQBtqr4Eajni3wX7rpfXD8ysFx8z0+dri+KWEPWpBsxXfxu58x/0jvTVT1ekOSg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "streamx": "^2.12.5"
      }
    },
    "node_modules/text-decoder": {
      "version": "1.2.7",
      "resolved": "https://registry.npmjs.org/text-decoder/-/text-decoder-1.2.7.tgz",
      "integrity": "sha512-vlLytXkeP4xvEq2otHeJfSQIRyWxo/oZGEbXrtEEF9Hnmrdly59sUbzZ/QgyWuLYHctCHxFF4tRQZNQ9k60ExQ==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "b4a": "^1.6.4"
      }
    },
    "node_modules/thread-stream": {
      "version": "4.2.0",
      "resolved": "https://registry.npmjs.org/thread-stream/-/thread-stream-4.2.0.tgz",
      "integrity": "sha512-e2zZ96wSChazBsbENf/Pcm/4swHt2cEKQ92rhUjkL9GCKiTDJIaTBenjE/m9DXi0QBmTMDkFDdOomUy20A1tDQ==",
      "license": "MIT",
      "dependencies": {
        "real-require": "^1.0.0"
      },
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/thread-stream/node_modules/real-require": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/real-require/-/real-require-1.0.0.tgz",
      "integrity": "sha512-P4nbQYQfePJxRSmY+v/KINxVucm4NF3p3s7pJveMTtom52FR4YGltUQLB8idDXwDDWW+eYrWDFbuzUnjoWHF7g==",
      "license": "MIT"
    },
    "node_modules/tinybench": {
      "version": "6.2.0",
      "resolved": "https://registry.npmjs.org/tinybench/-/tinybench-6.2.0.tgz",
      "integrity": "sha512-78U2TlB2CnVenajOFzf3BKSm0J6oz5L0NV7g32LCPccvYc0lbWvys4d3uUUCS2B1N8PAf2+aekR8i1KbC3HO7Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=20.0.0"
      }
    },
    "node_modules/tinyexec": {
      "version": "1.3.1",
      "resolved": "https://registry.npmjs.org/tinyexec/-/tinyexec-1.3.1.tgz",
      "integrity": "sha512-GCvB3aoys96IuDFBMcTB46JOR6mdMtAToqwiW8JlWhsoh1mhHi/xn9ss/Dg7N555GiJyEt2qzoG/NHCwM6h1EA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/tinyglobby": {
      "version": "0.2.17",
      "resolved": "https://registry.npmjs.org/tinyglobby/-/tinyglobby-0.2.17.tgz",
      "integrity": "sha512-wXR/dYpcqKmfWpEdZjiKJOwCNFndD0DMnrW/cYjVGttEkBfVgcLFHoNrlj47mjOVic9yyNu65alsgF4NQyTa2g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "fdir": "^6.5.0",
        "picomatch": "^4.0.4"
      },
      "engines": {
        "node": ">=12.0.0"
      },
      "funding": {
        "url": "https://github.com/sponsors/SuperchupuDev"
      }
    },
    "node_modules/tldts": {
      "version": "7.4.16",
      "resolved": "https://registry.npmjs.org/tldts/-/tldts-7.4.16.tgz",
      "integrity": "sha512-QwBER5KMR86IIjpIiO7H/Z3IMJPsZ1A6RKPAqzTTgOyUQUSt9FdnKcqhTaJmkY6HVrgouZHZR0ncK5QxvmnQeg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "tldts-core": "^7.4.16"
      },
      "bin": {
        "tldts": "bin/cli.js"
      }
    },
    "node_modules/tldts-core": {
      "version": "7.4.16",
      "resolved": "https://registry.npmjs.org/tldts-core/-/tldts-core-7.4.16.tgz",
      "integrity": "sha512-MDolfaSJtlSK5Y0A1xl3277ekubZwobpBjugknDizI9O5Rm60a1m8k4ICK+MRsCDzPygT81mp3BBf5RKDlFRfA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/tmp": {
      "version": "0.2.7",
      "resolved": "https://registry.npmjs.org/tmp/-/tmp-0.2.7.tgz",
      "integrity": "sha512-e0votIpp4Uo2AJYSzVHV6xCcawuiez3DzqDAbrTc3YxBkplN6e+dM13ZeIcZnDg/QpSuU2zfZ3rzwY8ukEnaXw==",
      "license": "MIT",
      "engines": {
        "node": ">=14.14"
      }
    },
    "node_modules/toidentifier": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/toidentifier/-/toidentifier-1.0.1.tgz",
      "integrity": "sha512-o5sSPKEkg/DIQNmH43V0/uerLrpzVedkUh8tGNvaeXpfpuwjKenlSox/2O/BTlZUtEe+JG7s5YhEz608PlAHRA==",
      "license": "MIT",
      "engines": {
        "node": ">=0.6"
      }
    },
    "node_modules/tough-cookie": {
      "version": "6.0.2",
      "resolved": "https://registry.npmjs.org/tough-cookie/-/tough-cookie-6.0.2.tgz",
      "integrity": "sha512-exgYmnmL/sJpR3upZfXG5PoatXQii55xAiXGXzY+sROLZ/Y+SLcp9PgJNI9Vz37HpQ74WvDcLT8eqm+kV3FzrA==",
      "dev": true,
      "license": "BSD-3-Clause",
      "dependencies": {
        "tldts": "^7.0.5"
      },
      "engines": {
        "node": ">=16"
      }
    },
    "node_modules/tr46": {
      "version": "5.1.1",
      "resolved": "https://registry.npmjs.org/tr46/-/tr46-5.1.1.tgz",
      "integrity": "sha512-hdF5ZgjTqgAntKkklYw0R03MG2x/bSzTtkxmIRw/sTNV8YXsCJ1tfLAX23lhxhHJlEf3CRCOCGGWw3vI3GaSPw==",
      "license": "MIT",
      "dependencies": {
        "punycode": "^2.3.1"
      },
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/traverse": {
      "version": "0.3.9",
      "resolved": "https://registry.npmjs.org/traverse/-/traverse-0.3.9.tgz",
      "integrity": "sha512-iawgk0hLP3SxGKDfnDJf8wTz4p2qImnyihM5Hh/sGvQ3K37dPi/w8sRhdNIxYA1TwFwc5mDhIJq+O0RsvXBKdQ==",
      "license": "MIT/X11",
      "engines": {
        "node": "*"
      }
    },
    "node_modules/tree-kill": {
      "version": "1.2.2",
      "resolved": "https://registry.npmjs.org/tree-kill/-/tree-kill-1.2.2.tgz",
      "integrity": "sha512-L0Orpi8qGpRG//Nd+H90vFB+3iHnue1zSSGmNOOCh1GLJ7rUKVwV2HvijphGQS2UmhUZewS9VgvxYIdgr+fG1A==",
      "dev": true,
      "license": "MIT",
      "bin": {
        "tree-kill": "cli.js"
      }
    },
    "node_modules/ts-api-utils": {
      "version": "2.5.0",
      "resolved": "https://registry.npmjs.org/ts-api-utils/-/ts-api-utils-2.5.0.tgz",
      "integrity": "sha512-OJ/ibxhPlqrMM0UiNHJ/0CKQkoKF243/AEmplt3qpRgkW8VG7IfOS41h7V8TjITqdByHzrjcS/2si+y4lIh8NA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=18.12"
      },
      "peerDependencies": {
        "typescript": ">=4.8.4"
      }
    },
    "node_modules/tslib": {
      "version": "2.8.1",
      "resolved": "https://registry.npmjs.org/tslib/-/tslib-2.8.1.tgz",
      "integrity": "sha512-oJFu94HQb+KVduSUQL7wnpmqnfmLsOA/nAh6b6EH0wCEoK0/mPeXU6c3wKDV83MkOuHPRHtSXKKU99IBazS/2w==",
      "dev": true,
      "license": "0BSD"
    },
    "node_modules/tsx": {
      "version": "4.23.15",
      "resolved": "https://registry.npmjs.org/tsx/-/tsx-4.23.15.tgz",
      "integrity": "sha512-Yiex1Ovn8z2xPpOWckIiysV1SSyRMY9BkLF++q0yKiDxCqRhosKfMg3janKkiLBwZ5c/YryloKwGZcrEmtwxKw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "esbuild": "~0.28.0"
      },
      "bin": {
        "tsx": "dist/cli.mjs"
      },
      "engines": {
        "node": ">=18.0.0"
      },
      "optionalDependencies": {
        "fsevents": "~2.3.3"
      }
    },
    "node_modules/type-check": {
      "version": "0.4.0",
      "resolved": "https://registry.npmjs.org/type-check/-/type-check-0.4.0.tgz",
      "integrity": "sha512-XleUoc9uwGXqjWwXaUTZAmzMcFZ5858QA2vvx1Ur5xIcixXIP+8LnFDgRplU30us6teqdlskFfu+ae4K79Ooew==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "prelude-ls": "^1.2.1"
      },
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/type-fest": {
      "version": "5.10.0",
      "resolved": "https://registry.npmjs.org/type-fest/-/type-fest-5.10.0.tgz",
      "integrity": "sha512-NoSdpq/WEiAg5sjmBkmV/hfxv6HJH4NqPNrqjtSO5CwRmpsDfaf4begxW34KdJykH/l1yHtwBWQkCRdoXO8mPA==",
      "license": "(MIT OR CC0-1.0)",
      "dependencies": {
        "tagged-tag": "^1.0.0"
      },
      "engines": {
        "node": ">=20"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/type-is": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/type-is/-/type-is-2.1.0.tgz",
      "integrity": "sha512-faYHw0anBbc/kWF3zFTEnxSFOAGUX9GFbOBthvDdLsIlEoWOFOtS0zgCiQYwIskL9iGXZL3kAXD8OoZ4GmMATA==",
      "license": "MIT",
      "dependencies": {
        "content-type": "^2.0.0",
        "media-typer": "^1.1.0",
        "mime-types": "^3.0.0"
      },
      "engines": {
        "node": ">= 18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/type-is/node_modules/content-type": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/content-type/-/content-type-2.1.0.tgz",
      "integrity": "sha512-mj7UPXE0jaqaOsukNZRUEfEi2AcL7C/vwmwcHV0O97eO1E1pxBZuyjlZrx5seTaNBg1U6+o35wpa35Qfcc+7ag==",
      "license": "MIT",
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/typescript": {
      "version": "6.0.3",
      "resolved": "https://registry.npmjs.org/typescript/-/typescript-6.0.3.tgz",
      "integrity": "sha512-y2TvuxSZPDyQakkFRPZHKFm+KKVqIisdg9/CZwm9ftvKXLP8NRWj38/ODjNbr43SsoXqNuAisEf1GdCxqWcdBw==",
      "dev": true,
      "license": "Apache-2.0",
      "bin": {
        "tsc": "bin/tsc",
        "tsserver": "bin/tsserver"
      },
      "engines": {
        "node": ">=14.17"
      }
    },
    "node_modules/typescript-eslint": {
      "version": "8.71.0",
      "resolved": "https://registry.npmjs.org/typescript-eslint/-/typescript-eslint-8.71.0.tgz",
      "integrity": "sha512-fBdHYiqQ14RW6mOMXD14Svn82ZsCYAoQSzGRzyEjR59S5A2Krh/l7fGTOQ7iCr8gGy/mHVXtEF7s5fgjEdV0Pw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@typescript-eslint/eslint-plugin": "8.71.0",
        "@typescript-eslint/parser": "8.71.0",
        "@typescript-eslint/typescript-estree": "8.71.0",
        "@typescript-eslint/utils": "8.71.0"
      },
      "engines": {
        "node": "^18.18.0 || ^20.9.0 || >=21.1.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/typescript-eslint"
      },
      "peerDependencies": {
        "eslint": "^8.57.0 || ^9.0.0 || ^10.0.0",
        "typescript": ">=4.8.4 <6.1.0"
      }
    },
    "node_modules/undici": {
      "version": "8.11.2",
      "resolved": "https://registry.npmjs.org/undici/-/undici-8.11.2.tgz",
      "integrity": "sha512-u4UB2/IrKdU6lFxumHmmo1a3fCQO5tzQllRorfoRS63txhrB7xTpSn1PftwC4qEHkOaqP95fCWW4lJzwErwzhQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=22.19.0"
      }
    },
    "node_modules/undici-types": {
      "version": "6.21.0",
      "resolved": "https://registry.npmjs.org/undici-types/-/undici-types-6.21.0.tgz",
      "integrity": "sha512-iwDZqg0QAGrg9Rav5H4n0M64c3mkR59cJ6wQp+7C4nI0gsmExaedaYLNO44eT4AtBBwjbTiGPMlt2Md0T9H9JQ==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/unpipe": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/unpipe/-/unpipe-1.0.0.tgz",
      "integrity": "sha512-pjy2bYhSsufwWlKwPc+l3cN7+wuJlK6uz0YdJEOlQDbl6jo/YlPi4mb8agUkVC8BF7V8NuzeyPNqRksA3hztKQ==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/unzipper": {
      "version": "0.10.14",
      "resolved": "https://registry.npmjs.org/unzipper/-/unzipper-0.10.14.tgz",
      "integrity": "sha512-ti4wZj+0bQTiX2KmKWuwj7lhV+2n//uXEotUmGuQqrbVZSEGFMbI68+c6JCQ8aAmUWYvtHEz2A8K6wXvueR/6g==",
      "license": "MIT",
      "dependencies": {
        "big-integer": "^1.6.17",
        "binary": "~0.3.0",
        "bluebird": "~3.4.1",
        "buffer-indexof-polyfill": "~1.0.0",
        "duplexer2": "~0.1.4",
        "fstream": "^1.0.12",
        "graceful-fs": "^4.2.2",
        "listenercount": "~1.0.1",
        "readable-stream": "~2.3.6",
        "setimmediate": "~1.0.4"
      }
    },
    "node_modules/unzipper/node_modules/readable-stream": {
      "version": "2.3.8",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-2.3.8.tgz",
      "integrity": "sha512-8p0AUk4XODgIewSi0l8Epjs+EVnWiK7NoDIEGU0HhE7+ZyY8D1IMY7odu5lRrFXGg71L15KG8QrPmum45RTtdA==",
      "license": "MIT",
      "dependencies": {
        "core-util-is": "~1.0.0",
        "inherits": "~2.0.3",
        "isarray": "~1.0.0",
        "process-nextick-args": "~2.0.0",
        "safe-buffer": "~5.1.1",
        "string_decoder": "~1.1.1",
        "util-deprecate": "~1.0.1"
      }
    },
    "node_modules/unzipper/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "license": "MIT"
    },
    "node_modules/unzipper/node_modules/string_decoder": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.1.1.tgz",
      "integrity": "sha512-n/ShnvDi6FHbbVfviro+WojiFzv+s8MPMHBczVePfUpDJLwoLT0ht1l4YwBCbi8pJAveEEdnkHyPyTP/mzRfwg==",
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.1.0"
      }
    },
    "node_modules/update-browserslist-db": {
      "version": "1.3.3",
      "resolved": "https://registry.npmjs.org/update-browserslist-db/-/update-browserslist-db-1.3.3.tgz",
      "integrity": "sha512-pJ2sYawQS0R/WI928Gj5GlPhTGzbMelq0+4INtSYNDV9ErKJcX6xjGWkoG/VnB3dpUm00zALaqkrUD77pO5TDQ==",
      "dev": true,
      "funding": [
        {
          "type": "opencollective",
          "url": "https://opencollective.com/browserslist"
        },
        {
          "type": "tidelift",
          "url": "https://tidelift.com/funding/github/npm/browserslist"
        },
        {
          "type": "github",
          "url": "https://github.com/sponsors/ai"
        }
      ],
      "license": "MIT",
      "dependencies": {
        "escalade": "^3.2.0",
        "picocolors": "^1.1.1"
      },
      "bin": {
        "update-browserslist-db": "cli.js"
      },
      "peerDependencies": {
        "browserslist": ">= 4.21.0"
      }
    },
    "node_modules/uri-js": {
      "version": "4.4.1",
      "resolved": "https://registry.npmjs.org/uri-js/-/uri-js-4.4.1.tgz",
      "integrity": "sha512-7rKUyy33Q1yc98pQ1DAmLtwX109F7TIfWlW1Ydo8Wl1ii1SeHieeh0HHfPeL2fMXK6z0s8ecKs9frCuLJvndBg==",
      "dev": true,
      "license": "BSD-2-Clause",
      "dependencies": {
        "punycode": "^2.1.0"
      }
    },
    "node_modules/util-deprecate": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/util-deprecate/-/util-deprecate-1.0.2.tgz",
      "integrity": "sha512-EPD5q1uXyFxJpCrLnCc1nHnq3gOa6DZBocAIiI2TaSCA7VCJ1UJDMagCzIkXNsUYfD1daK//LTEQ8xiIbrHtcw==",
      "license": "MIT"
    },
    "node_modules/uuid": {
      "version": "11.1.1",
      "resolved": "https://registry.npmjs.org/uuid/-/uuid-11.1.1.tgz",
      "integrity": "sha512-vIYxrBCC/N/K+Js3qSN88go7kIfNPssr/hHCesKCQNAjmgvYS2oqr69kIufEG+O4+PfezOH4EbIeHCfFov8ZgQ==",
      "funding": [
        "https://github.com/sponsors/broofa",
        "https://github.com/sponsors/ctavan"
      ],
      "license": "MIT",
      "bin": {
        "uuid": "dist/esm/bin/uuid"
      }
    },
    "node_modules/vary": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/vary/-/vary-1.1.2.tgz",
      "integrity": "sha512-BNGbWLfd0eUPabhkXUVm0j8uuvREyTh5ovRa/dyow/BqAbZJyC+5fU+IzQOzmAKzYqYRAISoRhdQr3eIZ/PXqg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/vite": {
      "version": "8.3.1",
      "resolved": "https://registry.npmjs.org/vite/-/vite-8.3.1.tgz",
      "integrity": "sha512-/bvH9E9tmCXRGp2uXY3WbOldqpTwFkbha/8ANaEQ6VkxhH60KyqLwgZq6lG2y+4uT55x9+9eUHMpQ7uGnOCKjA==",
      "dev": true,
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "lightningcss": "^1.33.0",
        "picomatch": "^4.0.7",
        "postcss": "^8.5.28",
        "rolldown": "~1.2.9",
        "tinyglobby": "^0.2.17"
      },
      "bin": {
        "vite": "bin/vite.js"
      },
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      },
      "funding": {
        "url": "https://github.com/vitejs/vite?sponsor=1"
      },
      "optionalDependencies": {
        "fsevents": "~2.3.3"
      },
      "peerDependencies": {
        "@types/node": "^20.19.0 || >=22.12.0",
        "@vitejs/devtools": "^0.7.1",
        "esbuild": "^0.27.0 || ^0.28.0",
        "jiti": ">=1.21.0",
        "less": "^4.0.0",
        "sass": "^1.70.0",
        "sass-embedded": "^1.70.0",
        "stylus": ">=0.54.8",
        "sugarss": "^5.0.0",
        "terser": "^5.16.0",
        "tsx": "^4.8.1",
        "yaml": "^2.4.2"
      },
      "peerDependenciesMeta": {
        "@types/node": {
          "optional": true
        },
        "@vitejs/devtools": {
          "optional": true
        },
        "esbuild": {
          "optional": true
        },
        "jiti": {
          "optional": true
        },
        "less": {
          "optional": true
        },
        "sass": {
          "optional": true
        },
        "sass-embedded": {
          "optional": true
        },
        "stylus": {
          "optional": true
        },
        "sugarss": {
          "optional": true
        },
        "terser": {
          "optional": true
        },
        "tsx": {
          "optional": true
        },
        "yaml": {
          "optional": true
        }
      }
    },
    "node_modules/vitest": {
      "version": "5.0.2",
      "resolved": "https://registry.npmjs.org/vitest/-/vitest-5.0.2.tgz",
      "integrity": "sha512-7MQrx9pDv5aHiUcovIb/70Ys3tgtkUVgCtledvKdCmEO+/1Dicq5ZqoSxOW034m03oqC+oHOKui2dM6qtMLoJg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@types/chai": "^5.2.2",
        "@vitest/mocker": "5.0.2",
        "chai": "^6.2.2",
        "es-module-lexer": "^2.3.2",
        "expect-type": "^1.4.0",
        "magic-string": "^1.2.3",
        "obug": "^2.1.4",
        "picomatch": "^4.0.7",
        "std-env": "^4.2.0",
        "tinybench": "^6.1.4",
        "tinyexec": "^1.3.0",
        "tinyglobby": "^0.2.17",
        "why-is-node-running": "^3.2.1"
      },
      "bin": {
        "vitest": "vitest.mjs"
      },
      "engines": {
        "node": "^22.12.0 || ^24.0.0 || >=26.0.0"
      },
      "funding": {
        "url": "https://opencollective.com/vitest"
      },
      "peerDependencies": {
        "@edge-runtime/vm": "*",
        "@opentelemetry/api": "^1.9.0",
        "@types/node": "^22.0.0 || >=24.0.0",
        "@vitest/browser-playwright": "5.0.2",
        "@vitest/browser-preview": "5.0.2",
        "@vitest/browser-webdriverio": "^5.0.0-beta.5 || >=5.0.0",
        "@vitest/coverage-istanbul": "5.0.2",
        "@vitest/coverage-v8": "5.0.2",
        "@vitest/ui": "5.0.2",
        "happy-dom": "*",
        "jsdom": "*",
        "vite": "^6.4.0 || ^7.0.0 || ^8.0.0"
      },
      "peerDependenciesMeta": {
        "@edge-runtime/vm": {
          "optional": true
        },
        "@opentelemetry/api": {
          "optional": true
        },
        "@types/node": {
          "optional": true
        },
        "@vitest/browser-playwright": {
          "optional": true
        },
        "@vitest/browser-preview": {
          "optional": true
        },
        "@vitest/browser-webdriverio": {
          "optional": true
        },
        "@vitest/coverage-istanbul": {
          "optional": true
        },
        "@vitest/coverage-v8": {
          "optional": true
        },
        "@vitest/ui": {
          "optional": true
        },
        "happy-dom": {
          "optional": true
        },
        "jsdom": {
          "optional": true
        },
        "vite": {
          "optional": false
        }
      }
    },
    "node_modules/w3c-xmlserializer": {
      "version": "6.0.0",
      "resolved": "https://registry.npmjs.org/w3c-xmlserializer/-/w3c-xmlserializer-6.0.0.tgz",
      "integrity": "sha512-4Nsy8K5Tr6SPDH9jhKJOHf7ChDrc1zufZTVSF7x72hwuEXBqxqk9G6cK+K2NRUtB3iELRJqjXb4JPDMBjMTl2Q==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "xml-name-validator": "^5.0.0"
      },
      "engines": {
        "node": "^22.22.2 || ^24.15.0 || >=26.0.0"
      }
    },
    "node_modules/webidl-conversions": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/webidl-conversions/-/webidl-conversions-7.0.0.tgz",
      "integrity": "sha512-VwddBukDzu71offAQR975unBIGqfKZpM+8ZX6ySk8nYhVoo5CYaZyzt3YBvYtRtO+aoGlqxPg/B87NGVZ/fu6g==",
      "license": "BSD-2-Clause",
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/whatwg-mimetype": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/whatwg-mimetype/-/whatwg-mimetype-5.0.0.tgz",
      "integrity": "sha512-sXcNcHOC51uPGF0P/D4NVtrkjSU2fNsm9iog4ZvZJsL3rjoDAzXZhkm2MWt1y+PUdggKAYVoMAIYcs78wJ51Cw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=20"
      }
    },
    "node_modules/whatwg-url": {
      "version": "14.2.0",
      "resolved": "https://registry.npmjs.org/whatwg-url/-/whatwg-url-14.2.0.tgz",
      "integrity": "sha512-De72GdQZzNTUBBChsXueQUnPKDkg/5A5zp7pFDuQAj5UFoENpiACU0wlCvzpAGnTkj++ihpKwKyYewn/XNUbKw==",
      "license": "MIT",
      "dependencies": {
        "tr46": "^5.1.0",
        "webidl-conversions": "^7.0.0"
      },
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/which": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/which/-/which-2.0.2.tgz",
      "integrity": "sha512-BLI3Tl1TW3Pvl70l3yq3Y64i+awpwXqsGBYWkkqMtnbXgrMD+yj7rhW0kuEDxzJaYXGjEW5ogapKNMEKNMjibA==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "isexe": "^2.0.0"
      },
      "bin": {
        "node-which": "bin/node-which"
      },
      "engines": {
        "node": ">= 8"
      }
    },
    "node_modules/which-module": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/which-module/-/which-module-2.0.1.tgz",
      "integrity": "sha512-iBdZ57RDvnOR9AGBhML2vFZf7h8vmBjhoaZqODJBFWHVtKkDmKuHai3cx5PgVMrX5YDNp27AofYbAwctSS+vhQ==",
      "license": "ISC"
    },
    "node_modules/why-is-node-running": {
      "version": "3.2.2",
      "resolved": "https://registry.npmjs.org/why-is-node-running/-/why-is-node-running-3.2.2.tgz",
      "integrity": "sha512-NKUzAelcoCXhXL4dJzKIwXeR8iEVqsA0Lq6Vnd0UXvgaKbzVo4ZTHROF2Jidrv+SgxOQ03fMinnNhzZATxOD3A==",
      "dev": true,
      "license": "MIT",
      "bin": {
        "why-is-node-running": "cli.js"
      },
      "engines": {
        "node": ">=20.11"
      }
    },
    "node_modules/word-wrap": {
      "version": "1.2.5",
      "resolved": "https://registry.npmjs.org/word-wrap/-/word-wrap-1.2.5.tgz",
      "integrity": "sha512-BN22B5eaMMI9UMtjrGd5g5eCYPpCPDUy0FJXbYsaT5zYxjFOckS53SQDE3pWkVoWpHXVb3BrYcEN4Twa55B5cA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/wrap-ansi": {
      "version": "9.0.2",
      "resolved": "https://registry.npmjs.org/wrap-ansi/-/wrap-ansi-9.0.2.tgz",
      "integrity": "sha512-42AtmgqjV+X1VpdOfyTGOYRi0/zsoLqtXQckTmqTeybT+BDIbM/Guxo7x3pE2vtpr1ok6xRqM9OpBe+Jyoqyww==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "ansi-styles": "^6.2.1",
        "string-width": "^7.0.0",
        "strip-ansi": "^7.1.0"
      },
      "engines": {
        "node": ">=18"
      },
      "funding": {
        "url": "https://github.com/chalk/wrap-ansi?sponsor=1"
      }
    },
    "node_modules/wrappy": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/wrappy/-/wrappy-1.0.2.tgz",
      "integrity": "sha512-l4Sp/DRseor9wL6EvV2+TuQn63dMkPjZ/sp9XkghTEbV9KlPS1xUsZ3u7/IQO4wxtcFB4bgpQPRcR3QCvezPcQ==",
      "license": "ISC"
    },
    "node_modules/xml-name-validator": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/xml-name-validator/-/xml-name-validator-5.0.0.tgz",
      "integrity": "sha512-EvGK8EJ3DhaHfbRlETOWAS5pO9MZITeauHKJyb8wyajUfQUenkIg2MvLDTZ4T/TgIcm3HU0TFBgWWboAZ30UHg==",
      "dev": true,
      "license": "Apache-2.0",
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/xmlchars": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/xmlchars/-/xmlchars-2.2.0.tgz",
      "integrity": "sha512-JZnDKK8B0RCDw84FNdDAIpZK+JuJw+s7Lz8nksI7SIuU3UXJJslUthsi+uWBUYOwPFwW7W7PRLRfUKpxjtjFCw==",
      "license": "MIT"
    },
    "node_modules/y18n": {
      "version": "5.0.8",
      "resolved": "https://registry.npmjs.org/y18n/-/y18n-5.0.8.tgz",
      "integrity": "sha512-0pfFzegeDWJHJIAmTLRP2DwHjdF5s7jo9tuztdQxAhINCdvS+3nGINqPd00AphqJR/0LhANUS6/+7SCb98YOfA==",
      "dev": true,
      "license": "ISC",
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/yallist": {
      "version": "3.1.1",
      "resolved": "https://registry.npmjs.org/yallist/-/yallist-3.1.1.tgz",
      "integrity": "sha512-a4UGQaWPH59mOXUYnAG2ewncQS4i4F43Tv3JoAM+s2VDAmS9NsK8GpDMLrCHPksFT7h3K6TOoUNn2pb7RoXx4g==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/yargs": {
      "version": "18.0.0",
      "resolved": "https://registry.npmjs.org/yargs/-/yargs-18.0.0.tgz",
      "integrity": "sha512-4UEqdc2RYGHZc7Doyqkrqiln3p9X2DZVxaGbwhn2pi7MrRagKaOcIKe8L3OxYcbhXLgLFUS3zAYuQjKBQgmuNg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "cliui": "^9.0.1",
        "escalade": "^3.1.1",
        "get-caller-file": "^2.0.5",
        "string-width": "^7.2.0",
        "y18n": "^5.0.5",
        "yargs-parser": "^22.0.0"
      },
      "engines": {
        "node": "^20.19.0 || ^22.12.0 || >=23"
      }
    },
    "node_modules/yargs-parser": {
      "version": "22.0.0",
      "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-22.0.0.tgz",
      "integrity": "sha512-rwu/ClNdSMpkSrUb+d6BRsSkLUq1fmfsY6TOpYzTwvwkg1/NRG85KBy3kq++A8LKQwX6lsu+aWad+2khvuXrqw==",
      "dev": true,
      "license": "ISC",
      "engines": {
        "node": "^20.19.0 || ^22.12.0 || >=23"
      }
    },
    "node_modules/yauzl": {
      "version": "3.4.0",
      "resolved": "https://registry.npmjs.org/yauzl/-/yauzl-3.4.0.tgz",
      "integrity": "sha512-jIH9yLR9wqr0wOS0TpBvo/g/2UgZH5qePVbjgRliiF0BYvOZyaBknKsF+x9Iht0O6sqgnB93rCICdOZFecJuDw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "pend": "~1.2.0"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/yocto-queue": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/yocto-queue/-/yocto-queue-0.1.0.tgz",
      "integrity": "sha512-rVksvsnNCdJ/ohGc6xgPwyN8eheCxsiLM8mxuE/t/mOVqJewPuO1miLpTHQiRgTKCLexL4MeAFVagts7HmNZ2Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/zip-stream": {
      "version": "4.1.1",
      "resolved": "https://registry.npmjs.org/zip-stream/-/zip-stream-4.1.1.tgz",
      "integrity": "sha512-9qv4rlDiopXg4E69k+vMHjNN63YFMe9sZMrdlvKnCjlCRWeCBswPPMPUfx+ipsAWq1LXHe70RcbaHdJJpS6hyQ==",
      "license": "MIT",
      "dependencies": {
        "archiver-utils": "^3.0.4",
        "compress-commons": "^4.1.2",
        "readable-stream": "^3.6.0"
      },
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/zip-stream/node_modules/archiver-utils": {
      "version": "3.0.4",
      "resolved": "https://registry.npmjs.org/archiver-utils/-/archiver-utils-3.0.4.tgz",
      "integrity": "sha512-KVgf4XQVrTjhyWmx6cte4RxonPLR9onExufI1jhvw/MQ4BB6IsZD5gT8Lq+u/+pRkWna/6JoHpiQioaqFP5Rzw==",
      "license": "MIT",
      "dependencies": {
        "glob": "^7.2.3",
        "graceful-fs": "^4.2.0",
        "lazystream": "^1.0.0",
        "lodash.defaults": "^4.2.0",
        "lodash.difference": "^4.5.0",
        "lodash.flatten": "^4.4.0",
        "lodash.isplainobject": "^4.0.6",
        "lodash.union": "^4.6.0",
        "normalize-path": "^3.0.0",
        "readable-stream": "^3.6.0"
      },
      "engines": {
        "node": ">= 10"
      }
    },
    "node_modules/zod": {
      "version": "4.6.5",
      "resolved": "https://registry.npmjs.org/zod/-/zod-4.6.5.tgz",
      "integrity": "sha512-v5l/aFXZQeai4awLbOpSoHecE9UiMrnfx75tEXLjNonXVARxQ5mOeipTjROUchszUNCqnE+hqAMujRsRHsut2Q==",
      "license": "MIT",
      "funding": {
        "url": "https://github.com/sponsors/colinhacks"
      }
    },
    "node_modules/zod-validation-error": {
      "version": "4.0.2",
      "resolved": "https://registry.npmjs.org/zod-validation-error/-/zod-validation-error-4.0.2.tgz",
      "integrity": "sha512-Q6/nZLe6jxuU80qb/4uJ4t5v2VEZ44lzQjPDhYJNztRQ4wyWc6VF3D3Kb/fAuPetZQnhS3hnajCf9CsWesghLQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=18.0.0"
      },
      "peerDependencies": {
        "zod": "^3.25.0 || ^4.0.0"
      }
    },
    "node_modules/zxing-wasm": {
      "version": "3.1.3",
      "resolved": "https://registry.npmjs.org/zxing-wasm/-/zxing-wasm-3.1.3.tgz",
      "integrity": "sha512-3lC9BJk4fR5ZJxcGjb0hVnDFOW7KpLXHIebiBmVd4FDRQZVeObztoTKxRUPxlWwSgxrMRONK0u50hBD1aTYEKg==",
      "license": "MIT",
      "dependencies": {
        "@types/emscripten": "^1.41.5",
        "type-fest": "^5.8.0"
      },
      "peerDependencies": {
        "@types/emscripten": ">=1.39.6"
      }
    }
  }
}
__ATTENDANCE_EOF__

write 'eslint.config.js' <<'__ATTENDANCE_EOF__'
import js from '@eslint/js';
import { defineConfig, globalIgnores } from 'eslint/config';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default defineConfig([
  globalIgnores(['**/dist/**', '**/coverage/**', '**/node_modules/**', '.idea/**']),
  js.configs.recommended,
  tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    rules: {
      '@typescript-eslint/consistent-type-imports': ['error', { fixStyle: 'inline-type-imports' }],
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', destructuredArrayIgnorePattern: '^_' },
      ],
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      eqeqeq: ['error', 'always'],
    },
  },
  {
    files: ['apps/api/**/*.ts', 'apps/web/*.config.ts', '*.js'],
    languageOptions: { globals: globals.node },
  },
  {
    files: ['apps/web/src/**/*.{ts,tsx}'],
    extends: [reactHooks.configs.flat['recommended-latest'], reactRefresh.configs.vite],
    languageOptions: { globals: globals.browser },
  },
  {
    files: ['**/test/**/*.{ts,tsx}', '**/*.test.{ts,tsx}'],
    rules: { '@typescript-eslint/no-non-null-assertion': 'off' },
  },
]);
__ATTENDANCE_EOF__

write '.prettierignore' <<'__ATTENDANCE_EOF__'
node_modules
dist
coverage
package-lock.json
.idea
__ATTENDANCE_EOF__

write 'README.md' <<'__ATTENDANCE_EOF__'
# Attendance Platform

Multi-tenant attendance for schools and companies. An organisation signs up, adds the people it tracks (students, staff, employees), registers check-in devices, and gets daily dashboards plus monthly / term / session reports as Excel or CSV.

> **Status:** v2. **Phase 1: API** and **Phase 2: web app (Rollcall)** are complete and tested. The legacy `server/` and `client/` folders are gone.

The web app has two faces:

- **Dashboard** for owners, admins and viewers: today's live register, people (with CSV import and QR ID cards), reports with an on-screen register grid and Excel/CSV downloads, and settings.
- **Check-in device** (kiosk) for a tablet or phone at the gate: a big clock, a keypad for codes, and ID-card scanning with the camera.

---

## What changed from v1

| v1 problem                                                                       | v2                                                                                             |
| -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| The 7:00–8:30 check-in window was never enforced (`setHours` mutated `now`)      | Per-organisation attendance policy, evaluated in the organisation's timezone, covered by tests |
| `{"userCode": {"$ne": null}}` checked in a random person (NoSQL injection)       | Every input is validated with Zod; operator objects are rejected with `400`                    |
| Code lookups ignored the organisation, so two orgs with the same code mixed data | Every query is tenant-scoped by a base repository; codes are unique _per organisation_         |
| Check-in device was logged in as a full admin                                    | Kiosk devices get their own token that can only check people in/out                            |
| Attendance was linked to the member's **name** – renaming lost history           | Linked by member id; members are archived, never hard-deleted                                  |
| Two quick taps created two records                                               | A unique database index guarantees one check-in per member per day                             |
| Admin dashboard never showed attendance; Excel export didn't exist               | Daily view, member history, and reports as JSON / **Excel (3 sheets)** / CSV                   |
| Bearer tokens logged on every request; internal errors sent to clients           | Headers and bodies are never logged; errors are mapped to safe responses                       |
| One login per organisation, no roles                                             | Many team members per organisation with `OWNER` / `ADMIN` / `VIEWER` roles                     |
| JWT in localStorage for 1 h, no refresh, no logout                               | 15-min access token + rotating httpOnly refresh cookie with theft detection                    |
| Frontend hardcoded `localhost:5000`, stored the string "undefined" as a token    | Typed API client on a same-origin `/api` path; access token in memory with silent refresh      |

---

## Tech stack

**API:** Node.js 22.22+, TypeScript (strict), Express 5, MongoDB + Mongoose 9, Zod 4, Pino, Helmet, express-rate-limit, Luxon (timezones), ExcelJS.
**Web:** React 19, Vite 8, React Router 8, TanStack Query 5, Tailwind CSS 4, React Hook Form + Zod, Sonner, Lucide icons, `barcode-detector` (QR scanning), `qrcode` (ID cards and pairing codes).
**Quality:** Vitest (Supertest + mongodb-memory-server for the API; jsdom + Testing Library for the web), ESLint (typescript-eslint, React Hooks, React Refresh), Prettier, GitHub Actions.

---

## Getting started

### 1. Prerequisites

- **Node.js 22.22 or newer** (`node -v`). **Node 24 LTS is recommended.** React Router 8 needs 22.22+, so an older Node 22 prints engine warnings.
- **MongoDB**, any of:
  - [MongoDB Atlas](https://www.mongodb.com/atlas) free tier (easiest on Windows),
  - a local MongoDB Community install,
  - Docker: `docker compose up -d` (uses `docker-compose.yml` in this repo).

### 2. Install

```bash
npm install
```

Run this from the **repo root** – it installs every workspace. The first install also downloads a MongoDB binary used only by the test suite (cached afterwards). To skip that download, run `MONGOMS_DISABLE_POSTINSTALL=1 npm install`, and point tests at a real server instead (see [Testing](#testing)).

### 3. Configure the environment

**The env file lives at `apps/api/.env`.** Create it from the example:

```bash
cp apps/api/.env.example apps/api/.env
```

Then set at least:

| Variable            | What to put                                                                                                          |
| ------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `MONGO_URI`         | `mongodb://127.0.0.1:27017/attendance` locally, or your Atlas connection string                                      |
| `JWT_ACCESS_SECRET` | A long random string. Generate one: `node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"` |

`.env` is gitignored. Only `.env.example` is committed. The API validates the environment at startup and exits with a clear message if something is missing.

<details>
<summary>All environment variables</summary>

| Variable                   | Default                 | Purpose                                                     |
| -------------------------- | ----------------------- | ----------------------------------------------------------- |
| `NODE_ENV`                 | `development`           | `development` / `test` / `production`                       |
| `PORT`                     | `5000`                  | HTTP port (hosting platforms inject this)                   |
| `LOG_LEVEL`                | `info`                  | `fatal` … `trace`, or `silent`                              |
| `MONGO_URI`                | –                       | MongoDB connection string (**required**)                    |
| `JWT_ACCESS_SECRET`        | –                       | Access-token signing secret, ≥ 32 chars (**required**)      |
| `ACCESS_TOKEN_TTL_SECONDS` | `900`                   | Access-token lifetime (15 min)                              |
| `REFRESH_TOKEN_TTL_DAYS`   | `30`                    | Session lifetime                                            |
| `BCRYPT_ROUNDS`            | `12`                    | Password hashing cost                                       |
| `CORS_ORIGINS`             | `http://localhost:5173` | Comma-separated web origins allowed to call the API         |
| `COOKIE_SAMESITE`          | `lax`                   | `lax` if web and API share a site, `none` for cross-site    |
| `TRUST_PROXY`              | `0`                     | Number of proxies in front of the API (Render/Railway: `1`) |

</details>

The web app needs **no env file in development**: Vite forwards `/api` to `http://localhost:5000`. Only if your API runs on another port, create `apps/web/.env` from `apps/web/.env.example` and set `API_PROXY_TARGET`.

### 4. Run

```bash
npm run seed     # optional: demo school, 24 students, a kiosk, 4 weeks of history
npm run dev      # API on :5000 and web app on :5173, together
```

Open **http://localhost:5173** and sign in with the login the seed prints (`demo@attendance.local` / `demo-password-123`).

To try the check-in screen with the seeded device, open `http://localhost:5173/kiosk/pair#token=<kiosk token from the seed>`. For a real device:

1. **Settings → Check-in devices → Add device** (e.g. "Main gate tablet").
2. On the tablet, scan the QR code shown, or open the link. The tablet switches to the check-in screen and stays paired.
3. Optional: **People → ID card** prints a card with a QR code. People then scan the card instead of typing their code.

The camera only works on **HTTPS** or `localhost`. On a school gate, lock the tablet to the page: Android "App pinning" or iPad "Guided Access".

The API is also documented request by request in [`docs/api.http`](docs/api.http) (IntelliJ / WebStorm HTTP client; VS Code REST Client works with tokens copied by hand).

---

## Scripts

Run from the repo root.

| Command                           | Does                                                                  |
| --------------------------------- | --------------------------------------------------------------------- |
| `npm run dev`                     | API (hot reload) and web app (Vite) together                          |
| `npm run dev:api` / `dev:web`     | Just one of them                                                      |
| `npm run seed`                    | Create demo data (safe to re-run)                                     |
| `npm test`                        | All tests, both workspaces                                            |
| `npm run typecheck`               | Type-check both workspaces                                            |
| `npm run lint` / `lint:fix`       | ESLint                                                                |
| `npm run format` / `format:check` | Prettier                                                              |
| `npm run build`                   | Compile the API to `apps/api/dist` and the web app to `apps/web/dist` |
| `npm start`                       | Run the compiled API (production)                                     |

---

## Architecture

```
apps/api/src/
├── server.ts            # bootstrap: env → DB → HTTP server → graceful shutdown
├── app.ts               # Express app: middleware, routers, error handling
├── container.ts         # composition root: builds every service with its dependencies
├── config/              # env validation (Zod) and typed app config
├── core/                # framework-level building blocks, no business rules
│   ├── auth/            # JWT service, guards (authenticate, requireRole, authenticateKiosk), roles
│   ├── db/              # connection, TenantRepository base class, Mongo error helpers
│   ├── errors/          # AppError hierarchy
│   ├── http/            # request parsing, response helpers, shared schemas
│   ├── middleware/      # error handler, request logger, rate limits, CSRF header check
│   ├── security/        # password hashing, token generation
│   └── time/            # injectable Clock, timezone-aware date helpers
├── modules/             # one folder per feature
│   ├── auth/            # register, login, refresh rotation, sessions
│   ├── organizations/   # org settings, attendance policy, team & roles
│   ├── members/         # people being tracked, codes, PINs, QR tokens, bulk import
│   ├── attendance/      # check-in/out, daily view, manual corrections
│   │   ├── policies/    # AttendancePolicy → FixedWindowPolicy, FlexibleHoursPolicy
│   │   └── check-in/    # MemberResolver → CodePinResolver, QrTokenResolver
│   ├── calendar/        # holidays, reporting periods (terms, sessions, months)
│   ├── kiosks/          # check-in device registration and authentication
│   └── reports/         # report builder + exporters (JSON, XLSX, CSV)
└── scripts/seed.ts
```

Each module follows the same layering: **routes → controller → service → repository → model**. Controllers only parse input and shape output. Services hold business rules. Repositories are the only code that talks to MongoDB. `container.ts` is the single place that wires concrete classes together, so tests can swap the clock, logger or rate limits.

### Where inheritance and polymorphism are used (and why)

They're used where the domain genuinely has variants. Elsewhere the code uses plain composition.

| Abstraction                          | Variants                                                                                                                                 | Why it is a class hierarchy                                                                                                                                             |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AppError`                           | `ValidationError`, `UnauthorizedError`, `ForbiddenError`, `NotFoundError`, `ConflictError`, `BusinessRuleError` → `CheckInRejectedError` | One error middleware maps every error to its HTTP status. Nothing branches on error type.                                                                               |
| `AttendancePolicy` (template method) | `FixedWindowPolicy` (schools), `FlexibleHoursPolicy` (offices)                                                                           | Shared rules (work days, holidays, opening time) live in the base class. Each subclass only decides the time-of-day outcome. New policy = one class + one factory case. |
| `MemberResolver` (strategy)          | `CodePinResolver`, `QrTokenResolver`                                                                                                     | The check-in service never branches on _how_ someone identified themselves. NFC or geofenced check-in later = one new class.                                            |
| `ReportExporter` (template method)   | `JsonReportExporter`, `XlsxReportExporter`, `CsvReportExporter`                                                                          | Same report data, different renderers. The base class owns HTTP headers. PDF later = one new class.                                                                     |
| `TenantRepository<T>`                | Members, attendance, holidays, periods, kiosks                                                                                           | Every query is stamped with `orgId`. Every public method takes `orgId` first, so the compiler won't let you forget it.                                                  |

### Domain model

| Collection            | Holds                                                                                                                 |
| --------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `organizations`       | Name, slug, type (`SCHOOL` / `COMPANY`), timezone, embedded attendance policy                                         |
| `users`               | People who **log in** to the dashboard (email + password hash)                                                        |
| `memberships`         | User ↔ organisation with a role. One user can belong to several organisations                                         |
| `sessions`            | Refresh-token sessions (hash only, auto-expire via TTL index)                                                         |
| `members`             | People whose **attendance is tracked**. Code is unique per organisation. Optional PIN / QR. `joinedOn` / `archivedOn` |
| `attendancerecords`   | One per member per day attended: local date, check-in/out instants, `PRESENT` / `LATE`, method                        |
| `holidays`, `periods` | Calendar data used to compute expected days and report ranges                                                         |
| `kiosks`              | Registered check-in devices (token hash only)                                                                         |

**Absences are derived, never stored:** expected days = work days − holidays, within the member's active span (from `joinedOn`, until `archivedOn`), up to yesterday. Absences = expected days − attended days. Today is never counted as an absence while it is still in progress.

---

## Web app (`apps/web`)

```
apps/web/src
├── app/          route table, providers, query client, product name (brand.ts)
├── api/          typed endpoints, response types, query keys
├── lib/          HTTP client hierarchy, ApiError, date formatting, downloads
├── components/   ui/ primitives (button, dialog, register mark…) and layout/ (app shell)
├── features/
│   ├── auth/      session provider, route guards, sign in, sign up
│   ├── today/     live daily register and admin corrections
│   ├── people/    list, add/edit, CSV import, QR ID cards, person history
│   ├── reports/   period reports, on-screen register grid, Excel/CSV download
│   ├── settings/  organisation, attendance rules, holidays, terms, devices, team
│   └── kiosk/     check-in device: pairing, clock + keypad, QR scanner
└── test/         jsdom setup, fetch double, render helper
```

Decisions worth knowing:

- **Sessions.** The access token lives in memory only, never in localStorage. When a request returns 401, `SessionHttpClient` refreshes with the httpOnly cookie and retries once. Concurrent 401s share a single refresh, because the API rotates the refresh token on every use and would otherwise treat the second one as theft.
- **One HTTP base class, two subclasses.** `HttpClient` handles URLs, JSON, envelopes and errors. `SessionHttpClient` (dashboard) and `KioskHttpClient` (device) differ only in how they authenticate and how they react to 401: refresh, or unpair the device.
- **Same-origin API.** The browser always calls `/api/v1`. Vite proxies it in development, and Vercel rewrites it in production. The refresh cookie stays first-party and CORS never comes into play.
- **The kiosk is a device, not a user.** It sits outside the dashboard session and holds a revocable device token that can only check people in or out.
  - The pairing link carries the token in the URL fragment (`#token=`), which browsers never send to servers, and the page removes it from the address bar after pairing.
  - When an admin removes the device, its next request gets 401 and it returns to the pairing screen.
- **QR scanning** uses the browser's native `BarcodeDetector` where available, and otherwise a WebAssembly decoder that ships with the app, so scanning does not depend on a CDN.
- **Code splitting.** The forms (Zod, React Hook Form), the people/reports/settings pages and the kiosk with its decoder load on demand. A signed-in admin downloads about 100 KB of JavaScript (gzipped) to see today's register.
- **Design.** The look is modelled on a class register:
  - Ink-blue text on white paper, with ruled rows.
  - Ticks for present, and red-pen red reserved for absences and destructive actions.
  - Typefaces are Bricolage Grotesque and Hanken Grotesk, self-hosted.
  - The product name "Rollcall" is one constant in `src/app/brand.ts`.

---

## API reference

Base URL: `/api/v1`. JSON in and out. Successful responses are `{ "data": … }` (lists add `"meta"`). Errors are `{ "error": { "code", "message", "details?" } }`.

Auth headers:

- **Dashboard:** `Authorization: Bearer <accessToken>`
- **Kiosk device:** `Authorization: Kiosk <kioskToken>`

| Method & path                                                                   | Who                      | Purpose                                                                                |
| ------------------------------------------------------------------------------- | ------------------------ | -------------------------------------------------------------------------------------- |
| `GET /api/health`                                                               | public                   | Liveness + DB status                                                                   |
| `POST /auth/register`                                                           | public                   | Create organisation + owner, start session                                             |
| `POST /auth/login`                                                              | public                   | Start session (optional `organizationId`)                                              |
| `POST /auth/refresh`                                                            | cookie                   | Rotate refresh cookie, get new access token (needs `X-Requested-With: XMLHttpRequest`) |
| `POST /auth/logout`                                                             | cookie                   | End session (needs `X-Requested-With`)                                                 |
| `GET /auth/me`                                                                  | any role                 | Current user, organisation, role, other organisations                                  |
| `GET /organization`                                                             | any role                 | Organisation settings and policy                                                       |
| `PATCH /organization`                                                           | ADMIN                    | Rename, change timezone                                                                |
| `PUT /organization/policy`                                                      | ADMIN                    | Replace the attendance policy                                                          |
| `GET /team` · `POST /team`                                                      | ADMIN                    | List / add dashboard users (only owners can add owners)                                |
| `PATCH /team/:userId` · `DELETE /team/:userId`                                  | OWNER                    | Change role / remove (an org always keeps one owner)                                   |
| `GET /members`                                                                  | any role                 | `?search=&group=&status=ACTIVE\|ARCHIVED\|ALL&page=&limit=`                            |
| `GET /members/groups`                                                           | any role                 | Distinct groups (classes, departments)                                                 |
| `POST /members`                                                                 | ADMIN                    | Create (code auto-generated if omitted; optional `pin`, `group`, `joinedOn`)           |
| `POST /members/import`                                                          | ADMIN                    | Bulk create up to 1,000; returns `created` + `skipped` rows                            |
| `GET /members/:id`                                                              | any role                 | One member                                                                             |
| `PATCH /members/:id`                                                            | ADMIN                    | Update name, code, group, PIN (`null` clears), status                                  |
| `DELETE /members/:id`                                                           | ADMIN                    | Archive (history is kept; restore with `PATCH status=ACTIVE`)                          |
| `POST /members/:id/qr-token`                                                    | ADMIN                    | Issue a new QR token for an ID card (shown once, old one stops working)                |
| `GET /attendance/daily?date=`                                                   | any role                 | Everyone expected that day with status and totals                                      |
| `POST /attendance/manual`                                                       | ADMIN                    | Record or correct a day (`PRESENT` / `LATE`, optional time and note)                   |
| `DELETE /attendance/:id`                                                        | ADMIN                    | Remove a wrong record                                                                  |
| `GET /holidays?from=&to=` · `POST /holidays` · `DELETE /holidays/:id`           | read: any · write: ADMIN | Holidays                                                                               |
| `GET /periods` · `POST /periods` · `PATCH /periods/:id` · `DELETE /periods/:id` | read: any · write: ADMIN | Terms, sessions, months                                                                |
| `GET /reports/attendance`                                                       | any role                 | `?periodId=` **or** `?from=&to=`, plus `&group=` and `&format=json\|xlsx\|csv`         |
| `GET /reports/members/:id?from=&to=`                                            | any role                 | One member's day marks, totals and check-in log                                        |
| `GET /kiosks` · `POST /kiosks` · `DELETE /kiosks/:id`                           | ADMIN                    | Register devices (token shown once) / revoke                                           |
| `GET /kiosk/session`                                                            | kiosk                    | What the check-in screen needs: org name, today, policy                                |
| `POST /kiosk/check-in`                                                          | kiosk                    | `{ "method": "CODE", "code", "pin?" }` or `{ "method": "QR", "token" }`                |
| `POST /kiosk/check-out`                                                         | kiosk                    | Same body; only when the policy allows check-out                                       |

### Check-in outcomes

| Status | `error.code` / `details.reason`                                              | Meaning                                                                              |
| ------ | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `201`  | –                                                                            | Checked in. `status` is `PRESENT` or `LATE`                                          |
| `409`  | `CONFLICT` / `ALREADY_CHECKED_IN`                                            | Already checked in today                                                             |
| `422`  | `CHECK_IN_REJECTED` / `NON_WORKDAY`, `HOLIDAY`, `TOO_EARLY`, `WINDOW_CLOSED` | Not allowed right now                                                                |
| `422`  | `CHECK_IN_REJECTED` / `INVALID_CREDENTIALS`                                  | Unknown code, wrong PIN, or revoked QR (deliberately the same message for all three) |
| `429`  | `TOO_MANY_REQUESTS`                                                          | 15 failed attempts in 5 minutes on this device                                       |

### Attendance policies

| Field           | `FIXED_WINDOW` (school default)                      | `FLEXIBLE_HOURS` (company default) |
| --------------- | ---------------------------------------------------- | ---------------------------------- |
| `workDays`      | ISO weekdays, `1` = Mon … `7` = Sun. Default Mon–Fri | same                               |
| `opensAt`       | Earliest check-in (`07:00`)                          | Earliest check-in (`06:00`)        |
| `lateAfter`     | On time up to and including this minute (`08:00`)    | `09:00`                            |
| `closesAt`      | Last check-in (`08:30`); later is rejected           | – (check-in allowed all day)       |
| `allowCheckOut` | `false`                                              | `true`                             |

All times are wall-clock times in the **organisation's timezone** (default `Africa/Lagos`), never the server's.

### Reports

`format=xlsx` streams a workbook with three sheets:

- **Summary:** per person: expected days, present, late, absent and attendance %, with low attendance (< 75%) highlighted, plus totals and a legend.
- **Daily grid:** person × date, colour-coded `P` / `L` / `A` / `H` / `W` / `-`.
- **Check-in log:** every record with local times and method.

`format=csv` is the summary + grid in one sheet. User-entered text is protected against spreadsheet formula injection. Reports span at most 400 days.

---

## Security model

- **Dashboard sessions:**
  - The access token (15 min) lives in memory on the client.
  - The refresh token is an httpOnly cookie scoped to `/api/v1/auth` and rotated on every use.
  - Replaying an already-rotated refresh token (outside a 30-second multi-tab grace window) revokes **all** of that user's sessions.
- **Roles:** `OWNER` ⊃ `ADMIN` ⊃ `VIEWER`. Role changes and removals take effect at the next refresh (≤ 15 min), and removing a teammate revokes their sessions immediately.
- **Kiosk tokens:** device tokens are random 256-bit values and only their SHA-256 hash is stored. They can't reach dashboard endpoints and can be revoked instantly.
- **Check-in credentials:**
  - Codes are random 6-digit numbers by default, so they can't be guessed from each other.
  - PINs and QR tokens are stored hashed.
  - Failed attempts are rate-limited per device.
- **Login:**
  - Login attempts are rate-limited.
  - Unknown emails take the same time and return the same message as wrong passwords, so the response doesn't reveal which emails are registered.
- **Logs and responses:**
  - Logs never contain headers, bodies, tokens or passwords.
  - Clients never see stack traces or database messages.
- **Validation:** every request body, query and URL parameter is validated by a Zod schema before it reaches a service.

---

## Testing

```bash
npm test
```

**API**

- **Unit tests:** policies, timezone maths, error mapping, exporters.
- **Integration tests:** the real HTTP stack against a real MongoDB. There is a regression test for every v1 bug in the table above.
- **Isolation:** each test file uses its own throw-away database.

By default the API tests start an in-memory MongoDB. To use an existing server instead (faster, and needed if the binary download is blocked on your network):

```bash
MONGO_TEST_URI=mongodb://127.0.0.1:27017 npm test
```

Set `TEST_LOG_LEVEL=error` to see server errors while debugging a test.

**Web**

- **HTTP client:** bearer token, refresh and retry, single-flight refresh under concurrent 401s, session expiry, kiosk unpairing on 401, and error mapping.
- **Pure logic:** CSV import (school-list headers, DD/MM/YYYY dates, duplicate codes), check-in window messages, kiosk outcome messages, timezone-safe formatting, and the day summary sentence.
- **Flows:** sign-in renders the real route table with only `fetch` faked (redirect, wrong password, then today's register). The kiosk test covers a keypad check-in, a rejected code with PIN, and an unpaired device.

Run one workspace with `npm test --workspace=@attendance/web` (or `@attendance/api`).

---

## Deployment (Render for the API, Vercel for the web)

### API on Render

| Setting           | Value                                                                                                         |
| ----------------- | ------------------------------------------------------------------------------------------------------------- |
| Build command     | `npm ci && npm run build --workspace=@attendance/api`                                                         |
| Start command     | `npm start`                                                                                                   |
| Health check path | `/api/health`                                                                                                 |
| Environment       | `NODE_ENV=production`, `MONGO_URI`, `JWT_ACCESS_SECRET`, `CORS_ORIGINS=https://your-web-app`, `TRUST_PROXY=2` |

### Web on Vercel

1. In `apps/web/vercel.json`, replace `YOUR-API-HOST.onrender.com` with your Render hostname and commit.
2. Import the repo in Vercel. Set **Root Directory** to `apps/web`. The Vite preset fills in `npm run build` and the `dist` output; Vercel installs from the repo root because it is an npm workspace.
3. Set Node.js to **24.x** in the project settings.

The rewrite in `vercel.json` serves the API under the web app's own domain (`/api/*`). The refresh cookie is then first-party, `COOKIE_SAMESITE=lax` works, and the kiosk camera gets the HTTPS it needs. The same file adds security headers and allows the camera for this site only.

Notes:

- **`TRUST_PROXY=2`:** requests pass through Vercel's proxy and then Render's load balancer. With `1`, the API would see Vercel's address instead of the visitor's, and everyone would share one login rate limit. Use `1` only if browsers call Render directly.
- **Different sites instead of the rewrite:**
  - Set `VITE_API_URL` on Vercel, `COOKIE_SAMESITE=none` on Render, and `TRUST_PROXY=1`.
  - Expect some browsers to block the cross-site refresh cookie, which shows up as being signed out on reload.
- **Atlas:** allow Render's outbound IPs in Network Access.
- **Several API instances:** rate limits use in-memory counters, so give them a shared store (for example `rate-limit-redis`) before scaling beyond one instance.

---

## Troubleshooting

| Symptom                                      | Fix                                                                                                       |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `Invalid environment configuration` on start | `apps/api/.env` is missing or incomplete. Copy it from `.env.example`                                     |
| `Could not connect to MongoDB`               | Is MongoDB running? Is `MONGO_URI` right? For Atlas, is your IP allowed?                                  |
| Tests hang on first run                      | The MongoDB test binary is downloading. Wait, or use `MONGO_TEST_URI`                                     |
| Line-ending noise in `git diff` on Windows   | `.gitattributes` enforces LF. Run `git add --renormalize .` once                                          |
| `EADDRINUSE :5000`                           | Another process uses the port. Change `PORT` in `apps/api/.env` and `API_PROXY_TARGET` in `apps/web/.env` |
| Web app says "Cannot reach the server"       | Is the API running? `npm run dev` starts both; check the `api` lines in the terminal                      |
| Kiosk camera does not start                  | The page must be on HTTPS (or localhost), with camera permission allowed for the site                     |
| Signed out on every reload in production     | The API is on a different site from the web app. Use the Vercel rewrite (see Deployment)                  |
| `EBADENGINE` warnings on install             | Node is older than 22.22. Install Node 24 LTS                                                             |

---

## Roadmap

1. Notifications: SMS or email to parents or managers when someone is absent.
2. Leave requests, and geofenced check-in from personal phones.
3. Audit log of admin changes (corrections, archives, role changes).
4. Offline kiosk: queue check-ins while the connection is down and sync them later.
__ATTENDANCE_EOF__

write '.github/workflows/ci.yml' <<'__ATTENDANCE_EOF__'
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  checks:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node: [22, 24]
    services:
      mongo:
        image: mongo:8
        ports: ['27017:27017']
    env:
      MONGO_TEST_URI: mongodb://127.0.0.1:27017
      MONGOMS_DISABLE_POSTINSTALL: '1'
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: ${{ matrix.node }}
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm run format:check
      - run: npm run typecheck
      - run: npm test
      - run: npm run build
__ATTENDANCE_EOF__

ok "Wrote $FILE_COUNT files"

if [ "$IN_GIT" = 1 ]; then
  CHANGED=$(git status --porcelain -- package.json package-lock.json eslint.config.js .prettierignore README.md .github/workflows/ci.yml | wc -l | tr -d ' ')
  if [ "$CHANGED" != 0 ]; then
    say "Root files updated (review with: git diff -- package.json eslint.config.js):"
    git status --short -- package.json package-lock.json eslint.config.js .prettierignore README.md .github/workflows/ci.yml
  fi
fi

# ── 4. Dependencies ──────────────────────────────────────────────────────────
if [ "$SKIP_INSTALL" = 0 ]; then
  say "Installing dependencies…"
  npm install --no-fund --no-audit
  ok "Dependencies installed"
else
  warn "Skipped npm install (--skip-install). Run it yourself from the repo root."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
cat <<'NEXT'

  Phase 2 (web app) installed.

  Next:
    1. npm test              (API + web; web tests need no database)
    2. npm run seed          (demo school, if you haven't already)
    3. npm run dev           → API on :5000, web on http://localhost:5173
       Sign in: demo@attendance.local / demo-password-123
    4. Try the check-in screen: Settings → Check-in devices → Add device,
       then open the pairing link (or the seed's kiosk token at
       http://localhost:5173/kiosk/pair#token=<token>)
    5. git add -A && git commit -m "feat(web): v2 rebuild – phase 2"

  Deploying: README → "Deployment (Render for the API, Vercel for the web)".
  Remember to replace YOUR-API-HOST in apps/web/vercel.json.

NEXT
