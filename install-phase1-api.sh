#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
#  Attendance Platform v2 · Phase 1 (API) installer
#
#  What it does
#    1. Removes the legacy server/ folder (it stays in git history)
#    2. Stops tracking .idea/ in git (kept on disk, ignored from now on)
#    3. Writes the new npm workspace: apps/api (TypeScript API + tests),
#       README, docs/api.http, CI, lint/format config, lockfile
#    4. Creates apps/api/.env from .env.example with a fresh JWT secret (only if missing)
#    5. Runs npm install
#
#  Idempotent: safe to re-run. It overwrites the files it owns and never touches
#  apps/api/.env once it exists, or the legacy client/ folder.
#
#  Usage (from the repo root, in Git Bash):
#    bash install-phase1-api.sh               # normal run
#    bash install-phase1-api.sh --skip-install # write files only
#    bash install-phase1-api.sh --force        # allow running with uncommitted changes
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

FILE_COUNT=116
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
if [ ! -d server ] && [ ! -d apps/api ]; then
  die "This doesn't look like the attendance repo (no server/ or apps/api/ folder here)."
fi
command -v node >/dev/null 2>&1 || die "Node.js not found. Install Node 22.12+ (Node 24 LTS recommended)."
command -v npm >/dev/null 2>&1 || die "npm not found."
node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=12)?0:1)' \
  || die "Node $(node -v) is too old. Install Node 22.12+ (Node 24 LTS recommended)."

IN_GIT=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then IN_GIT=1; fi

# Only guard the first run (legacy server/ still present); re-runs are expected to find a dirty tree.
if [ -d server ] && [ "$IN_GIT" = 1 ] && [ "$FORCE" = 0 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  die "You have uncommitted changes. Commit or stash them first (or re-run with --force).
  Tip: do the upgrade on a branch:  git checkout -b upgrade/v2"
fi

# ── 2. Legacy cleanup ────────────────────────────────────────────────────────
if [ -d server ]; then
  if [ "$IN_GIT" = 1 ]; then
    rm -rf server
    ok "Removed legacy server/ (recoverable from git history)"
  else
    tar -czf legacy-server-v1.tgz server && rm -rf server
    ok "Not a git repo: archived legacy server/ to legacy-server-v1.tgz, then removed it"
  fi
fi

if [ "$IN_GIT" = 1 ] && git ls-files --error-unmatch .idea >/dev/null 2>&1; then
  git rm -r --cached --quiet .idea
  ok "Stopped tracking .idea/ in git (folder kept on disk, now ignored)"
fi

# ── 3. Project files ─────────────────────────────────────────────────────────
say "Writing $FILE_COUNT project files…"
write() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

write '.editorconfig' <<'__ATTENDANCE_EOF__'
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.md]
trim_trailing_whitespace = false
__ATTENDANCE_EOF__

write '.gitattributes' <<'__ATTENDANCE_EOF__'
# Normalise line endings to LF in the repo, whatever the OS (stops CRLF drift on Windows).
* text=auto eol=lf
*.sh text eol=lf

# Binary files
*.png binary
*.jpg binary
*.ico binary
*.xlsx binary
*.pdf binary
__ATTENDANCE_EOF__

write '.github/workflows/ci.yml' <<'__ATTENDANCE_EOF__'
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  api:
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

write '.gitignore' <<'__ATTENDANCE_EOF__'
# Dependencies
node_modules/

# Build output
dist/
coverage/
*.tsbuildinfo

# Environment – commit .env.example files only
.env
.env.*
!.env.example

# Logs
*.log
npm-debug.log*

# Editors / OS
.idea/
.vscode/*
!.vscode/extensions.json
.DS_Store
Thumbs.db

# Files saved by docs/api.http
docs/*.xlsx
__ATTENDANCE_EOF__

write '.nvmrc' <<'__ATTENDANCE_EOF__'
22
__ATTENDANCE_EOF__

write '.prettierignore' <<'__ATTENDANCE_EOF__'
node_modules
dist
coverage
package-lock.json
client
.idea
__ATTENDANCE_EOF__

write '.prettierrc.json' <<'__ATTENDANCE_EOF__'
{
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 120,
  "semi": true,
  "endOfLine": "lf"
}
__ATTENDANCE_EOF__

write 'README.md' <<'__ATTENDANCE_EOF__'
# Attendance Platform

Multi-tenant attendance for schools and companies. An organisation signs up, adds the people it tracks (students, staff, employees), registers check-in devices, and gets daily dashboards plus monthly / term / session reports as Excel or CSV.

> **Status:** v2 rebuild in progress.
> **Phase 1 (this commit): API** – complete and tested.
> **Phase 2: web app** (React + Vite + TypeScript) – replaces the legacy `client/` folder. Until then, use the API directly (see [`docs/api.http`](docs/api.http)).

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

---

## Tech stack

**API:** Node.js 22+, TypeScript (strict), Express 5, MongoDB + Mongoose 9, Zod 4, Pino, Helmet, express-rate-limit, Luxon (timezones), ExcelJS.
**Quality:** Vitest + Supertest + mongodb-memory-server, ESLint (typescript-eslint), Prettier, GitHub Actions.

---

## Getting started

### 1. Prerequisites

- **Node.js 22.12 or newer** (`node -v`). Node 24 LTS works too.
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

### 4. Run

```bash
npm run dev      # API with hot reload → http://localhost:5000/api/health
npm run seed     # optional: demo school, 24 students, a kiosk, 4 weeks of history
```

The seed prints a dashboard login and a kiosk token. Then open [`docs/api.http`](docs/api.http) in IntelliJ / WebStorm and click through the requests (tokens are captured automatically). In VS Code’s REST Client the requests work too, but copy tokens by hand.

---

## Scripts

Run from the repo root.

| Command                           | Does                                      |
| --------------------------------- | ----------------------------------------- |
| `npm run dev`                     | Start the API with hot reload (tsx watch) |
| `npm run seed`                    | Create demo data (safe to re-run)         |
| `npm test`                        | Run all tests                             |
| `npm run typecheck`               | Type-check without emitting               |
| `npm run lint` / `lint:fix`       | ESLint                                    |
| `npm run format` / `format:check` | Prettier                                  |
| `npm run build`                   | Compile the API to `apps/api/dist`        |
| `npm start`                       | Run the compiled API (production)         |

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

- **Unit tests:** policies, timezone maths, error mapping, exporters.
- **Integration tests:** the real HTTP stack against a real MongoDB. There is a regression test for every v1 bug in the table above.
- **Isolation:** each test file uses its own throw-away database.

By default the tests start an in-memory MongoDB. To use an existing server instead (faster, and needed if the binary download is blocked on your network):

```bash
MONGO_TEST_URI=mongodb://127.0.0.1:27017 npm test
```

Set `TEST_LOG_LEVEL=error` to see server errors while debugging a test.

---

## Deployment (Render example)

| Setting           | Value                                                                                                         |
| ----------------- | ------------------------------------------------------------------------------------------------------------- |
| Build command     | `npm ci && npm run build`                                                                                     |
| Start command     | `npm start`                                                                                                   |
| Health check path | `/api/health`                                                                                                 |
| Environment       | `NODE_ENV=production`, `MONGO_URI`, `JWT_ACCESS_SECRET`, `CORS_ORIGINS=https://your-web-app`, `TRUST_PROXY=1` |

Notes:

- **Cookies:** prefer serving the API under the web app's domain (for example a Vercel rewrite from `/api/*` to the Render URL). The refresh cookie then stays first-party and `COOKIE_SAMESITE=lax` works. If web and API must live on different sites, set `COOKIE_SAMESITE=none`. The cookie is then sent cross-site, which some browsers restrict.
- **Atlas:** allow the host's outbound IPs in Network Access.
- **Several API instances:** rate limits use in-memory counters, so give them a shared store (for example `rate-limit-redis`) before scaling beyond one instance.

---

## Troubleshooting

| Symptom                                      | Fix                                                                      |
| -------------------------------------------- | ------------------------------------------------------------------------ |
| `Invalid environment configuration` on start | `apps/api/.env` is missing or incomplete. Copy it from `.env.example`    |
| `Could not connect to MongoDB`               | Is MongoDB running? Is `MONGO_URI` right? For Atlas, is your IP allowed? |
| Tests hang on first run                      | The MongoDB test binary is downloading. Wait, or use `MONGO_TEST_URI`    |
| Line-ending noise in `git diff` on Windows   | `.gitattributes` enforces LF. Run `git add --renormalize .` once         |
| `EADDRINUSE :5000`                           | Another process uses the port. Change `PORT` in `.env`                   |

---

## Roadmap

1. **Web app** (`apps/web`, React + Vite + TypeScript): admin dashboard, daily view, member management with CSV import, reports, and a locked-down kiosk mode with QR scanning. This replaces `client/`.
2. Notifications (SMS/email to parents or managers on absence), leave requests, geofenced mobile check-in.
3. Audit log of admin changes.
__ATTENDANCE_EOF__

write 'apps/api/.env.example' <<'__ATTENDANCE_EOF__'
# ─── Runtime ────────────────────────────────────────────────
NODE_ENV=development
PORT=5000
LOG_LEVEL=info

# ─── Database ───────────────────────────────────────────────
# Local:  mongodb://127.0.0.1:27017/attendance
# Atlas:  mongodb+srv://<user>:<password>@<cluster>.mongodb.net/attendance
MONGO_URI=mongodb://127.0.0.1:27017/attendance

# ─── Auth ───────────────────────────────────────────────────
# Generate with: node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
JWT_ACCESS_SECRET=replace-me-with-a-long-random-string-at-least-32-chars
ACCESS_TOKEN_TTL_SECONDS=900
REFRESH_TOKEN_TTL_DAYS=30
BCRYPT_ROUNDS=12

# ─── HTTP ───────────────────────────────────────────────────
# Comma-separated list of web origins allowed to call the API
CORS_ORIGINS=http://localhost:5173
# lax when web + API share a site (recommended: proxy /api through the web host); none for cross-site
COOKIE_SAMESITE=lax
# Number of reverse proxies in front of the API (Render/Railway/Heroku: 1)
TRUST_PROXY=0
__ATTENDANCE_EOF__

write 'apps/api/package.json' <<'__ATTENDANCE_EOF__'
{
  "name": "@attendance/api",
  "version": "2.0.0",
  "private": true,
  "type": "module",
  "main": "dist/server.js",
  "scripts": {
    "dev": "tsx watch --clear-screen=false src/server.ts",
    "build": "tsc -p tsconfig.build.json",
    "start": "node dist/server.js",
    "seed": "tsx src/scripts/seed.ts",
    "typecheck": "tsc -p tsconfig.json --noEmit",
    "test": "vitest run",
    "test:watch": "vitest"
  },
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
}
__ATTENDANCE_EOF__

write 'apps/api/src/app.ts' <<'__ATTENDANCE_EOF__'
import cookieParser from 'cookie-parser';
import cors from 'cors';
import express, { Router, type Express } from 'express';
import helmet from 'helmet';
import type { Container } from './container.js';
import { isDatabaseReady } from './core/db/connect.js';
import { errorHandler, notFoundHandler } from './core/middleware/error-handler.js';
import { requestLogger } from './core/middleware/request-logger.js';
import { attendanceRoutes, kioskDeviceRoutes } from './modules/attendance/attendance.routes.js';
import { authRoutes } from './modules/auth/auth.routes.js';
import { holidayRoutes, periodRoutes } from './modules/calendar/calendar.routes.js';
import { kioskRoutes } from './modules/kiosks/kiosk.routes.js';
import { memberRoutes } from './modules/members/member.routes.js';
import { organizationRoutes, teamRoutes } from './modules/organizations/organization.routes.js';
import { reportRoutes } from './modules/reports/report.routes.js';

export function createApp(container: Container): Express {
  const { config, logger, guards, limiters, controllers } = container;
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);

  app.use(requestLogger(logger));
  app.use(helmet());
  app.use(cors({ origin: config.corsOrigins, credentials: true, maxAge: 600 }));
  app.use(express.json({ limit: '1mb' }));
  app.use(cookieParser());

  app.get('/api/health', (_req, res) => {
    const database = isDatabaseReady();
    res.status(database ? 200 : 503).json({ status: database ? 'ok' : 'degraded', database });
  });

  // Every router owns a distinct prefix, so router-level guards (e.g. `router.use(authenticate)`)
  // can never leak onto another module's routes.
  const v1 = Router();
  v1.use('/auth', authRoutes(controllers.auth, guards, limiters));
  v1.use('/organization', organizationRoutes(controllers.organization, guards));
  v1.use('/team', teamRoutes(controllers.organization, guards));
  v1.use('/members', memberRoutes(controllers.members, guards));
  v1.use('/holidays', holidayRoutes(controllers.calendar, guards));
  v1.use('/periods', periodRoutes(controllers.calendar, guards));
  v1.use('/attendance', attendanceRoutes(controllers.attendance, guards));
  v1.use('/reports', reportRoutes(controllers.reports, guards));
  v1.use('/kiosks', kioskRoutes(controllers.kiosks, guards));
  v1.use('/kiosk', kioskDeviceRoutes(controllers.kioskDevice, guards, limiters));
  app.use('/api/v1', v1);

  app.use('/api', notFoundHandler);
  app.use(errorHandler(logger));
  return app;
}
__ATTENDANCE_EOF__

write 'apps/api/src/config/app-config.ts' <<'__ATTENDANCE_EOF__'
import type { Env } from './env.js';

/** Runtime configuration consumed by the app. Decoupled from process.env so tests can build it directly. */
export interface AppConfig {
  isProduction: boolean;
  corsOrigins: string[];
  trustProxy: number;
  auth: {
    jwtAccessSecret: string;
    accessTokenTtlSeconds: number;
    refreshTokenTtlDays: number;
    bcryptRounds: number;
  };
  cookie: {
    secure: boolean;
    sameSite: 'lax' | 'strict' | 'none';
  };
}

export function toAppConfig(env: Env): AppConfig {
  const isProduction = env.NODE_ENV === 'production';
  return {
    isProduction,
    corsOrigins: env.CORS_ORIGINS,
    trustProxy: env.TRUST_PROXY,
    auth: {
      jwtAccessSecret: env.JWT_ACCESS_SECRET,
      accessTokenTtlSeconds: env.ACCESS_TOKEN_TTL_SECONDS,
      refreshTokenTtlDays: env.REFRESH_TOKEN_TTL_DAYS,
      bcryptRounds: env.BCRYPT_ROUNDS,
    },
    cookie: {
      // Browsers only honour SameSite=None on Secure cookies.
      secure: isProduction || env.COOKIE_SAMESITE === 'none',
      sameSite: env.COOKIE_SAMESITE,
    },
  };
}
__ATTENDANCE_EOF__

write 'apps/api/src/config/env.ts' <<'__ATTENDANCE_EOF__'
import { existsSync } from 'node:fs';
import { z } from 'zod';

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(5000),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  MONGO_URI: z.string().min(1, 'is required'),
  JWT_ACCESS_SECRET: z.string().min(32, 'must be at least 32 characters'),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(86_400).default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(90).default(30),
  BCRYPT_ROUNDS: z.coerce.number().int().min(4).max(15).default(12),
  CORS_ORIGINS: z
    .string()
    .default('http://localhost:5173')
    .transform((value) =>
      value
        .split(',')
        .map((origin) => origin.trim())
        .filter(Boolean),
    ),
  COOKIE_SAMESITE: z.enum(['lax', 'strict', 'none']).default('lax'),
  TRUST_PROXY: z.coerce.number().int().min(0).default(0),
});

export type Env = z.infer<typeof EnvSchema>;

/** Loads `.env` from the current working directory (apps/api) when present. Real env vars win. */
export function loadDotEnvFile(path = '.env'): void {
  if (existsSync(path)) process.loadEnvFile(path);
}

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const result = EnvSchema.safeParse(source);
  if (!result.success) {
    const issues = result.error.issues.map((issue) => `  - ${issue.path.join('.')}: ${issue.message}`).join('\n');
    throw new Error(`Invalid environment configuration:\n${issues}\nSee apps/api/.env.example`);
  }
  return result.data;
}
__ATTENDANCE_EOF__

write 'apps/api/src/container.ts' <<'__ATTENDANCE_EOF__'
import type { AppConfig } from './config/app-config.js';
import { AccessTokenService } from './core/auth/access-token.service.js';
import { createGuards } from './core/auth/guards.js';
import type { Logger } from './core/logger.js';
import { createRateLimiters } from './core/middleware/rate-limit.js';
import { PasswordHasher } from './core/security/password-hasher.js';
import { systemClock, type Clock } from './core/time/clock.js';
import { AttendanceController, KioskDeviceController } from './modules/attendance/attendance.controller.js';
import { AttendanceRepository } from './modules/attendance/attendance.repository.js';
import { AttendanceService } from './modules/attendance/attendance.service.js';
import { CodePinResolver } from './modules/attendance/check-in/code-pin.resolver.js';
import { MemberResolverRegistry } from './modules/attendance/check-in/member-resolver.js';
import { QrTokenResolver } from './modules/attendance/check-in/qr-token.resolver.js';
import { AuthController } from './modules/auth/auth.controller.js';
import { AuthService } from './modules/auth/auth.service.js';
import { SessionService } from './modules/auth/session.service.js';
import { CalendarController } from './modules/calendar/calendar.controller.js';
import { HolidayRepository, PeriodRepository } from './modules/calendar/calendar.repositories.js';
import { CalendarService } from './modules/calendar/calendar.service.js';
import { KioskController } from './modules/kiosks/kiosk.controller.js';
import { KioskRepository, KioskService } from './modules/kiosks/kiosk.service.js';
import { MemberCodeGenerator } from './modules/members/member-code.generator.js';
import { MemberController } from './modules/members/member.controller.js';
import { MemberRepository } from './modules/members/member.repository.js';
import { MemberService } from './modules/members/member.service.js';
import { OrganizationController } from './modules/organizations/organization.controller.js';
import { OrganizationService } from './modules/organizations/organization.service.js';
import { TeamService } from './modules/organizations/team.service.js';
import { ReportExporterRegistry } from './modules/reports/exporters/index.js';
import { ReportController } from './modules/reports/report.controller.js';
import { ReportService } from './modules/reports/report.service.js';

export interface ContainerOptions {
  logger: Logger;
  clock?: Clock;
  /** Tests disable rate limiting so they can hammer endpoints. */
  rateLimiting?: boolean;
}

/** Composition root: the only place that knows which concrete class implements what. */
export function createContainer(config: AppConfig, options: ContainerOptions) {
  const clock = options.clock ?? systemClock;

  // Infrastructure
  const passwordHasher = new PasswordHasher(config.auth.bcryptRounds);
  const pinHasher = new PasswordHasher(Math.min(config.auth.bcryptRounds, 10));
  const accessTokens = new AccessTokenService(config.auth.jwtAccessSecret, config.auth.accessTokenTtlSeconds);

  // Repositories
  const memberRepository = new MemberRepository();
  const attendanceRepository = new AttendanceRepository();
  const kioskRepository = new KioskRepository();
  const holidayRepository = new HolidayRepository();
  const periodRepository = new PeriodRepository();

  // Services
  const organizations = new OrganizationService();
  const sessions = new SessionService(config.auth.refreshTokenTtlDays, clock);
  const auth = new AuthService(organizations, sessions, passwordHasher, accessTokens, clock);
  const team = new TeamService(passwordHasher, sessions);
  const calendar = new CalendarService(holidayRepository, periodRepository);
  const kiosks = new KioskService(kioskRepository, clock);
  const members = new MemberService(
    memberRepository,
    organizations,
    new MemberCodeGenerator(memberRepository),
    pinHasher,
    clock,
  );
  const resolvers = new MemberResolverRegistry([
    new CodePinResolver(memberRepository, pinHasher),
    new QrTokenResolver(memberRepository),
  ]);
  const attendance = new AttendanceService(
    organizations,
    calendar,
    memberRepository,
    attendanceRepository,
    resolvers,
    clock,
  );
  const reports = new ReportService(organizations, calendar, memberRepository, attendanceRepository, clock);

  // HTTP
  const guards = createGuards(accessTokens, kiosks);
  const limiters = createRateLimiters(options.rateLimiting === false ? { skip: () => true } : {});

  return {
    config,
    logger: options.logger,
    clock,
    guards,
    limiters,
    services: { auth, organizations, team, members, calendar, kiosks, attendance, reports },
    controllers: {
      auth: new AuthController(auth, config),
      organization: new OrganizationController(organizations, team),
      members: new MemberController(members),
      calendar: new CalendarController(calendar),
      kiosks: new KioskController(kiosks),
      attendance: new AttendanceController(attendance),
      kioskDevice: new KioskDeviceController(attendance),
      reports: new ReportController(reports, calendar, new ReportExporterRegistry()),
    },
  };
}

export type Container = ReturnType<typeof createContainer>;
__ATTENDANCE_EOF__

write 'apps/api/src/core/auth/access-token.service.ts' <<'__ATTENDANCE_EOF__'
import jwt from 'jsonwebtoken';
import { UnauthorizedError } from '../errors/index.js';
import type { AuthContext } from './context.js';
import { isRole } from './roles.js';

const ISSUER = 'attendance-api';
const AUDIENCE = 'attendance-web';

export interface SignedAccessToken {
  accessToken: string;
  expiresIn: number;
}

/** Short-lived JWTs for dashboard users. Long-lived sessions live in refresh tokens (see SessionService). */
export class AccessTokenService {
  constructor(
    private readonly secret: string,
    private readonly ttlSeconds: number,
  ) {}

  sign(context: AuthContext): SignedAccessToken {
    const accessToken = jwt.sign({ org: context.orgId, role: context.role }, this.secret, {
      subject: context.userId,
      expiresIn: this.ttlSeconds,
      issuer: ISSUER,
      audience: AUDIENCE,
      algorithm: 'HS256',
    });
    return { accessToken, expiresIn: this.ttlSeconds };
  }

  verify(token: string): AuthContext {
    let payload: string | jwt.JwtPayload;
    try {
      payload = jwt.verify(token, this.secret, { issuer: ISSUER, audience: AUDIENCE, algorithms: ['HS256'] });
    } catch (error) {
      if (error instanceof jwt.TokenExpiredError) {
        throw new UnauthorizedError('Access token expired', { reason: 'TOKEN_EXPIRED' });
      }
      throw new UnauthorizedError('Invalid access token');
    }
    if (typeof payload === 'string' || !payload.sub || typeof payload.org !== 'string' || !isRole(payload.role)) {
      throw new UnauthorizedError('Invalid access token');
    }
    return { userId: payload.sub, orgId: payload.org, role: payload.role };
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/auth/context.ts' <<'__ATTENDANCE_EOF__'
import type { Request } from 'express';
import { UnauthorizedError } from '../errors/index.js';
import type { Role } from './roles.js';

/** Identity of a signed-in dashboard user, scoped to one organisation. */
export interface AuthContext {
  userId: string;
  orgId: string;
  role: Role;
}

/** Identity of a registered check-in device. It can only check people in and out. */
export interface KioskContext {
  id: string;
  orgId: string;
  name: string;
}

export function authOf(req: Request): AuthContext {
  if (!req.auth) throw new UnauthorizedError();
  return req.auth;
}

export function kioskOf(req: Request): KioskContext {
  if (!req.kiosk) throw new UnauthorizedError('Kiosk authentication required');
  return req.kiosk;
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/auth/guards.ts' <<'__ATTENDANCE_EOF__'
import type { RequestHandler } from 'express';
import { ForbiddenError, UnauthorizedError } from '../errors/index.js';
import type { AccessTokenService } from './access-token.service.js';
import type { KioskContext } from './context.js';
import { authOf } from './context.js';
import { hasRole, type Role } from './roles.js';

export interface KioskAuthenticator {
  authenticate(token: string): Promise<KioskContext>;
}

function readAuthorization(header: string | undefined, scheme: string): string | null {
  if (!header) return null;
  const [actualScheme, value] = header.split(' ');
  return actualScheme?.toLowerCase() === scheme.toLowerCase() && value ? value.trim() : null;
}

export function createGuards(tokens: AccessTokenService, kiosks: KioskAuthenticator) {
  /** Requires `Authorization: Bearer <accessToken>`. */
  const authenticate: RequestHandler = (req, _res, next) => {
    const token = readAuthorization(req.get('authorization'), 'Bearer');
    if (!token) throw new UnauthorizedError();
    req.auth = tokens.verify(token);
    next();
  };

  /** Requires at least the given role in the current organisation. Use after `authenticate`. */
  const requireRole =
    (role: Role): RequestHandler =>
    (req, _res, next) => {
      if (!hasRole(authOf(req).role, role)) throw new ForbiddenError();
      next();
    };

  /** Requires `Authorization: Kiosk <deviceToken>`. */
  const authenticateKiosk: RequestHandler = async (req, _res, next) => {
    const token = readAuthorization(req.get('authorization'), 'Kiosk');
    if (!token) throw new UnauthorizedError('Kiosk authentication required');
    req.kiosk = await kiosks.authenticate(token);
    next();
  };

  return { authenticate, requireRole, authenticateKiosk };
}

export type Guards = ReturnType<typeof createGuards>;
__ATTENDANCE_EOF__

write 'apps/api/src/core/auth/roles.ts' <<'__ATTENDANCE_EOF__'
export const ROLES = ['OWNER', 'ADMIN', 'VIEWER'] as const;
export type Role = (typeof ROLES)[number];

const RANK: Record<Role, number> = { VIEWER: 1, ADMIN: 2, OWNER: 3 };

export const isRole = (value: unknown): value is Role => ROLES.includes(value as Role);

/** OWNER ⊃ ADMIN ⊃ VIEWER */
export const hasRole = (actual: Role, required: Role): boolean => RANK[actual] >= RANK[required];
__ATTENDANCE_EOF__

write 'apps/api/src/core/db/connect.ts' <<'__ATTENDANCE_EOF__'
import mongoose from 'mongoose';
import type { Logger } from '../logger.js';

mongoose.set('strictQuery', true);

/** Set during graceful shutdown so an intentional disconnect is not logged as a failure. */
let closing = false;

export async function connectDatabase(uri: string, logger: Logger): Promise<void> {
  mongoose.connection.on('disconnected', () => {
    if (!closing) logger.warn('MongoDB disconnected');
  });
  mongoose.connection.on('reconnected', () => logger.info('MongoDB reconnected'));

  await mongoose.connect(uri, {
    serverSelectionTimeoutMS: 10_000,
    maxPoolSize: 20,
  });
  await ensureIndexes();
  logger.info({ host: mongoose.connection.host, db: mongoose.connection.name }, 'MongoDB connected');
}

/**
 * Builds every declared index before the app accepts traffic.
 * Unique indexes (one check-in per member per day, unique codes per org) are business rules, not optimisations.
 */
export async function ensureIndexes(): Promise<void> {
  await Promise.all(Object.values(mongoose.models).map((model) => model.init()));
}

export async function disconnectDatabase(): Promise<void> {
  closing = true;
  await mongoose.disconnect();
}

export function isDatabaseReady(): boolean {
  return mongoose.connection.readyState === mongoose.ConnectionStates.connected;
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/db/mongo-errors.ts' <<'__ATTENDANCE_EOF__'
export interface DuplicateKeyError {
  code: 11000;
  keyValue?: Record<string, unknown>;
}

/** MongoDB E11000: a unique index rejected the write. */
export function isDuplicateKeyError(error: unknown): error is DuplicateKeyError {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === 11000;
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/db/tenant-repository.ts' <<'__ATTENDANCE_EOF__'
import type { Model, QueryFilter, Types } from 'mongoose';

export type Id = string | Types.ObjectId;

/** Shape of a lean document as it comes back from MongoDB. */
export type Lean<T> = T & { _id: Types.ObjectId; createdAt: Date; updatedAt: Date };

/**
 * Base class for every repository that stores tenant-owned data.
 *
 * Every read and write goes through `scoped()`, which stamps `orgId` onto the filter.
 * Because `orgId` is the first parameter of every public method, the compiler makes it
 * impossible to query another organisation's data by forgetting a filter.
 */
export abstract class TenantRepository<TSchema extends { orgId: Types.ObjectId }> {
  protected constructor(protected readonly model: Model<TSchema>) {}

  protected scoped(orgId: Id, filter: QueryFilter<TSchema> = {}): QueryFilter<TSchema> {
    return { ...filter, orgId } as QueryFilter<TSchema>;
  }

  async findById(orgId: Id, id: Id): Promise<Lean<TSchema> | null> {
    return this.model
      .findOne(this.scoped(orgId, { _id: id } as QueryFilter<TSchema>))
      .lean<Lean<TSchema>>()
      .exec();
  }

  async exists(orgId: Id, filter: QueryFilter<TSchema> = {}): Promise<boolean> {
    return (await this.model.exists(this.scoped(orgId, filter))) !== null;
  }

  async count(orgId: Id, filter: QueryFilter<TSchema> = {}): Promise<number> {
    return this.model.countDocuments(this.scoped(orgId, filter)).exec();
  }

  async deleteById(orgId: Id, id: Id): Promise<boolean> {
    const result = await this.model.deleteOne(this.scoped(orgId, { _id: id } as QueryFilter<TSchema>)).exec();
    return result.deletedCount === 1;
  }
}

/** Converts a freshly created/saved Mongoose document into the same plain shape `.lean()` returns. */
export function toLean<T>(document: { toObject(): unknown }): Lean<T> {
  return document.toObject() as Lean<T>;
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/errors/app-error.ts' <<'__ATTENDANCE_EOF__'
export type ErrorDetails = Record<string, unknown> | readonly unknown[];

export interface ErrorBody {
  code: string;
  message: string;
  details?: ErrorDetails;
}

/**
 * Base class for every error the API raises on purpose.
 * Subclasses only declare their HTTP status and machine-readable code;
 * the error middleware handles all of them the same way (polymorphism over instanceof chains).
 */
export abstract class AppError extends Error {
  abstract readonly statusCode: number;
  abstract readonly code: string;
  readonly details: ErrorDetails | undefined;

  constructor(message: string, details?: ErrorDetails) {
    super(message);
    this.name = new.target.name;
    this.details = details;
  }

  toJSON(): ErrorBody {
    return {
      code: this.code,
      message: this.message,
      ...(this.details === undefined ? {} : { details: this.details }),
    };
  }
}

export class ValidationError extends AppError {
  readonly statusCode = 400;
  readonly code: string = 'VALIDATION_ERROR';
}

export class UnauthorizedError extends AppError {
  readonly statusCode = 401;
  readonly code = 'UNAUTHORIZED';

  constructor(message = 'Authentication required', details?: ErrorDetails) {
    super(message, details);
  }
}

export class ForbiddenError extends AppError {
  readonly statusCode = 403;
  readonly code = 'FORBIDDEN';

  constructor(message = 'You do not have permission to perform this action', details?: ErrorDetails) {
    super(message, details);
  }
}

export class NotFoundError extends AppError {
  readonly statusCode = 404;
  readonly code = 'NOT_FOUND';

  constructor(resource: string, details?: ErrorDetails) {
    super(`${resource} not found`, details);
  }
}

export class ConflictError extends AppError {
  readonly statusCode = 409;
  readonly code = 'CONFLICT';
}

/** The request is well-formed but breaks a domain rule (e.g. check-in window closed). */
export class BusinessRuleError extends AppError {
  readonly statusCode = 422;
  readonly code: string = 'RULE_VIOLATION';
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/errors/index.ts' <<'__ATTENDANCE_EOF__'
export * from './app-error.js';
__ATTENDANCE_EOF__

write 'apps/api/src/core/http/parse.ts' <<'__ATTENDANCE_EOF__'
import type { z } from 'zod';
import { ValidationError } from '../errors/index.js';

/** Validates untrusted input against a schema and returns the typed, sanitised result. */
export function parse<Schema extends z.ZodType>(schema: Schema, input: unknown): z.output<Schema> {
  const result = schema.safeParse(input);
  if (!result.success) {
    throw new ValidationError(
      'Request validation failed',
      result.error.issues.map((issue) => ({
        path: issue.path.join('.'),
        message: issue.message,
      })),
    );
  }
  return result.data;
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/http/respond.ts' <<'__ATTENDANCE_EOF__'
import type { Response } from 'express';

export interface PageMeta {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

export function sendData<T>(res: Response, data: T, status = 200): void {
  res.status(status).json({ data });
}

export function sendPage<T>(res: Response, items: T[], meta: Omit<PageMeta, 'totalPages'>): void {
  res.status(200).json({
    data: items,
    meta: { ...meta, totalPages: Math.max(1, Math.ceil(meta.total / meta.limit)) },
  });
}

export function sendNoContent(res: Response): void {
  res.status(204).end();
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/http/schemas.ts' <<'__ATTENDANCE_EOF__'
import { isValidObjectId } from 'mongoose';
import { z } from 'zod';
import { isValidLocalDate } from '../time/local-date.js';

export const objectIdSchema = z
  .string()
  .refine((value) => isValidObjectId(value) && /^[a-f\d]{24}$/i.test(value), 'must be a valid id');

export const idParamsSchema = z.object({ id: objectIdSchema });

export const localDateSchema = z.string().refine(isValidLocalDate, 'must be a valid date in YYYY-MM-DD format');

export const timeOfDaySchema = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'must be a time in HH:mm (24h) format');

export const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

export const dateRangeSchema = z
  .object({ from: localDateSchema, to: localDateSchema })
  .refine((range) => range.from <= range.to, { message: '"from" must be on or before "to"', path: ['to'] });
__ATTENDANCE_EOF__

write 'apps/api/src/core/logger.ts' <<'__ATTENDANCE_EOF__'
import { pino, type Logger, type LoggerOptions } from 'pino';

export type { Logger };

export function createLogger(level: string, pretty = false): Logger {
  const options: LoggerOptions = {
    level,
    base: undefined,
    redact: {
      paths: ['password', 'pin', 'token', 'refreshToken', 'accessToken', '*.password', '*.pin', '*.token'],
      censor: '[REDACTED]',
    },
  };
  if (pretty) {
    options.transport = {
      target: 'pino-pretty',
      options: { colorize: true, translateTime: 'SYS:HH:MM:ss', ignore: 'pid,hostname' },
    };
  }
  return pino(options);
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/middleware/csrf.ts' <<'__ATTENDANCE_EOF__'
import type { RequestHandler } from 'express';
import { ForbiddenError } from '../errors/index.js';

/**
 * Cookie-authenticated endpoints (refresh, logout) require a custom header.
 * Browsers cannot send custom headers cross-origin without a CORS preflight, which our allowlist rejects.
 */
export const requireAjaxHeader: RequestHandler = (req, _res, next) => {
  if (req.get('x-requested-with') !== 'XMLHttpRequest') {
    throw new ForbiddenError('Missing X-Requested-With header');
  }
  next();
};
__ATTENDANCE_EOF__

write 'apps/api/src/core/middleware/error-handler.ts' <<'__ATTENDANCE_EOF__'
import type { ErrorRequestHandler, RequestHandler } from 'express';
import mongoose from 'mongoose';
import { isDuplicateKeyError } from '../db/mongo-errors.js';
import { AppError, NotFoundError, type ErrorBody } from '../errors/index.js';
import type { Logger } from '../logger.js';

interface MappedError {
  statusCode: number;
  body: ErrorBody;
}

function hasType(error: unknown, type: string): boolean {
  return typeof error === 'object' && error !== null && 'type' in error && error.type === type;
}

/** Translates any thrown value into a safe HTTP response. Internal details never leak to clients. */
export function mapError(error: unknown): MappedError {
  if (error instanceof AppError) {
    return { statusCode: error.statusCode, body: error.toJSON() };
  }
  if (isDuplicateKeyError(error)) {
    return {
      statusCode: 409,
      body: {
        code: 'CONFLICT',
        message: 'A record with the same unique value already exists',
        details: { fields: Object.keys(error.keyValue ?? {}) },
      },
    };
  }
  if (error instanceof mongoose.Error.CastError) {
    return { statusCode: 400, body: { code: 'VALIDATION_ERROR', message: `Invalid value for ${error.path}` } };
  }
  if (error instanceof mongoose.Error.ValidationError) {
    return {
      statusCode: 400,
      body: {
        code: 'VALIDATION_ERROR',
        message: 'Request validation failed',
        details: Object.values(error.errors).map((issue) => ({ path: issue.path, message: issue.message })),
      },
    };
  }
  if (hasType(error, 'entity.parse.failed')) {
    return { statusCode: 400, body: { code: 'MALFORMED_JSON', message: 'Request body is not valid JSON' } };
  }
  if (hasType(error, 'entity.too.large')) {
    return { statusCode: 413, body: { code: 'PAYLOAD_TOO_LARGE', message: 'Request body is too large' } };
  }
  return { statusCode: 500, body: { code: 'INTERNAL_ERROR', message: 'Something went wrong. Please try again.' } };
}

export function errorHandler(logger: Logger): ErrorRequestHandler {
  return (error: unknown, req, res, _next) => {
    const { statusCode, body } = mapError(error);
    if (statusCode >= 500) {
      (req.log ?? logger).error({ err: error }, 'Unhandled error');
    }
    if (res.headersSent) {
      res.end();
      return;
    }
    res.status(statusCode).json({ error: body });
  };
}

export const notFoundHandler: RequestHandler = (req, _res, next) => {
  next(new NotFoundError('Route', { method: req.method, path: req.path }));
};
__ATTENDANCE_EOF__

write 'apps/api/src/core/middleware/rate-limit.ts' <<'__ATTENDANCE_EOF__'
import { rateLimit, type Options } from 'express-rate-limit';

const errorResponse = (code: string, message: string) => ({ error: { code, message } });

/**
 * Rate limiters use the default in-memory store: correct for a single instance.
 * When you run more than one API instance, plug in a shared store (e.g. rate-limit-redis).
 */
export function createRateLimiters(overrides: Partial<Options> = {}) {
  const base: Partial<Options> = {
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    ...overrides,
  };

  return {
    /** Login / register: slows down credential stuffing. */
    auth: rateLimit({
      ...base,
      windowMs: 15 * 60 * 1000,
      limit: 20,
      message: errorResponse('TOO_MANY_REQUESTS', 'Too many attempts. Please try again later.'),
    }),
    /** Check-in: only failed attempts count, per kiosk device, so code guessing gets locked out fast. */
    checkInFailures: rateLimit({
      ...base,
      windowMs: 5 * 60 * 1000,
      limit: 15,
      skipSuccessfulRequests: true,
      keyGenerator: (req) => `kiosk:${req.kiosk?.id ?? 'anonymous'}`,
      message: errorResponse('TOO_MANY_REQUESTS', 'Too many failed check-ins on this device. Wait a few minutes.'),
    }),
  };
}

export type RateLimiters = ReturnType<typeof createRateLimiters>;
__ATTENDANCE_EOF__

write 'apps/api/src/core/middleware/request-logger.ts' <<'__ATTENDANCE_EOF__'
import { randomUUID } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { pinoHttp } from 'pino-http';
import type { Logger } from '../logger.js';

/**
 * Structured access log with a request id.
 * Headers and bodies are deliberately never logged: they carry tokens, cookies, passwords and PINs.
 */
export function requestLogger(logger: Logger) {
  return pinoHttp({
    logger,
    genReqId(req: IncomingMessage, res: ServerResponse) {
      const incoming = req.headers['x-request-id'];
      const id = typeof incoming === 'string' && /^[\w-]{1,100}$/.test(incoming) ? incoming : randomUUID();
      res.setHeader('x-request-id', id);
      return id;
    },
    customLogLevel(_req, res, error) {
      if (error || res.statusCode >= 500) return 'error';
      if (res.statusCode >= 400) return 'warn';
      return 'info';
    },
    autoLogging: { ignore: (req) => req.url === '/api/health' },
    serializers: {
      req: (req: { id: string; method: string; url: string }) => ({ id: req.id, method: req.method, url: req.url }),
      res: (res: { statusCode: number }) => ({ statusCode: res.statusCode }),
    },
  });
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/security/password-hasher.ts' <<'__ATTENDANCE_EOF__'
import bcrypt from 'bcryptjs';

export class PasswordHasher {
  constructor(private readonly rounds: number) {}

  hash(plain: string): Promise<string> {
    return bcrypt.hash(plain, this.rounds);
  }

  verify(plain: string, hash: string): Promise<boolean> {
    return bcrypt.compare(plain, hash);
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/security/tokens.ts' <<'__ATTENDANCE_EOF__'
import { createHash, randomBytes } from 'node:crypto';

export const sha256 = (value: string): string => createHash('sha256').update(value).digest('hex');

/** URL-safe random token. 32 bytes = 256 bits of entropy. */
export const randomToken = (bytes = 32): string => randomBytes(bytes).toString('base64url');
__ATTENDANCE_EOF__

write 'apps/api/src/core/time/clock.ts' <<'__ATTENDANCE_EOF__'
/** Injectable time source. Business rules never call `new Date()` directly, so tests can freeze time. */
export interface Clock {
  now(): Date;
}

export const systemClock: Clock = {
  now: () => new Date(),
};

export class FixedClock implements Clock {
  constructor(private current: Date) {}

  now(): Date {
    return new Date(this.current);
  }

  set(instant: Date | string): void {
    this.current = new Date(instant);
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/core/time/local-date.ts' <<'__ATTENDANCE_EOF__'
import { DateTime, IANAZone } from 'luxon';

/** A calendar date in an organisation's own timezone, formatted YYYY-MM-DD. Sorts lexicographically. */
export type LocalDate = string;

const LOCAL_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

export function isValidLocalDate(value: string): boolean {
  return LOCAL_DATE_PATTERN.test(value) && DateTime.fromISO(value, { zone: 'utc' }).isValid;
}

export function isValidTimeZone(zone: string): boolean {
  return IANAZone.isValidZone(zone);
}

export interface ZonedMoment {
  date: LocalDate;
  /** HH:mm, 24h */
  time: string;
  /** ISO weekday: 1 = Monday … 7 = Sunday */
  weekday: number;
}

/** Converts an absolute instant into the organisation's local calendar date and wall-clock time. */
export function toZonedMoment(instant: Date, zone: string): ZonedMoment {
  const local = DateTime.fromJSDate(instant, { zone });
  return {
    date: local.toFormat('yyyy-MM-dd'),
    time: local.toFormat('HH:mm'),
    weekday: local.weekday,
  };
}

export function toLocalDate(instant: Date, zone: string): LocalDate {
  return toZonedMoment(instant, zone).date;
}

/** Combines a local date and HH:mm in a zone into an absolute instant. */
export function toInstant(date: LocalDate, time: string, zone: string): Date {
  return DateTime.fromISO(`${date}T${time}`, { zone }).toJSDate();
}

export function isoWeekday(date: LocalDate): number {
  return DateTime.fromISO(date, { zone: 'utc' }).weekday;
}

export function minutesOfDay(time: string): number {
  const [hours = 0, minutes = 0] = time.split(':').map(Number);
  return hours * 60 + minutes;
}

export function daysInclusive(from: LocalDate, to: LocalDate): number {
  const start = DateTime.fromISO(from, { zone: 'utc' });
  const end = DateTime.fromISO(to, { zone: 'utc' });
  return Math.floor(end.diff(start, 'days').days) + 1;
}

/** Every calendar date from `from` to `to`, inclusive. */
export function eachDate(from: LocalDate, to: LocalDate): LocalDate[] {
  const dates: LocalDate[] = [];
  let cursor = DateTime.fromISO(from, { zone: 'utc' });
  const end = DateTime.fromISO(to, { zone: 'utc' });
  while (cursor <= end) {
    dates.push(cursor.toFormat('yyyy-MM-dd'));
    cursor = cursor.plus({ days: 1 });
  }
  return dates;
}

export function formatDayLabel(date: LocalDate): string {
  return DateTime.fromISO(date, { zone: 'utc' }).toFormat('ccc dd/MM');
}

export function formatTime(instant: Date | undefined | null, zone: string): string {
  return instant ? DateTime.fromJSDate(instant, { zone }).toFormat('HH:mm') : '';
}

export function formatDateTime(instant: Date, zone: string): string {
  return DateTime.fromJSDate(instant, { zone }).toFormat('yyyy-MM-dd HH:mm');
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/attendance-record.model.ts' <<'__ATTENDANCE_EOF__'
import { Schema, model, type Types } from 'mongoose';
import type { LocalDate } from '../../core/time/local-date.js';
import type { AttendanceStatus } from './policies/attendance-policy.js';

export const ATTENDANCE_STATUSES = ['PRESENT', 'LATE'] as const;
export const CHECK_IN_METHODS = ['CODE', 'QR', 'MANUAL'] as const;
export type CheckInMethod = (typeof CHECK_IN_METHODS)[number];

/**
 * One row per member per day they attended. Absences are derived, never stored:
 * expected days (work days − holidays, within the member's active span) minus attended days.
 */
export interface AttendanceRecord {
  orgId: Types.ObjectId;
  memberId: Types.ObjectId;
  /** Organisation-local calendar date. */
  date: LocalDate;
  checkInAt: Date;
  checkOutAt?: Date | undefined;
  status: AttendanceStatus;
  method: CheckInMethod;
  kioskId?: Types.ObjectId | undefined;
  /** Dashboard user who recorded or corrected it manually. */
  recordedBy?: Types.ObjectId | undefined;
  note?: string | undefined;
}

const attendanceRecordSchema = new Schema<AttendanceRecord>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    memberId: { type: Schema.Types.ObjectId, ref: 'Member', required: true },
    date: { type: String, required: true },
    checkInAt: { type: Date, required: true },
    checkOutAt: { type: Date },
    status: { type: String, enum: ATTENDANCE_STATUSES, required: true },
    method: { type: String, enum: CHECK_IN_METHODS, required: true },
    kioskId: { type: Schema.Types.ObjectId, ref: 'Kiosk' },
    recordedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    note: { type: String, trim: true, maxlength: 200 },
  },
  { timestamps: true },
);

// The database itself guarantees one check-in per member per day, even under concurrent requests.
attendanceRecordSchema.index({ memberId: 1, date: 1 }, { unique: true });
attendanceRecordSchema.index({ orgId: 1, date: 1 });

export const AttendanceRecordModel = model<AttendanceRecord>('AttendanceRecord', attendanceRecordSchema);
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/attendance.controller.ts' <<'__ATTENDANCE_EOF__'
import type { RequestHandler } from 'express';
import { authOf, kioskOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { idParamsSchema } from '../../core/http/schemas.js';
import { checkInSchema, dailyQuerySchema, manualRecordSchema } from './attendance.schemas.js';
import type { AttendanceService } from './attendance.service.js';

/** Dashboard endpoints (signed-in users). */
export class AttendanceController {
  constructor(private readonly attendance: AttendanceService) {}

  daily: RequestHandler = async (req, res) => {
    const { date } = parse(dailyQuerySchema, req.query);
    sendData(res, await this.attendance.daily(authOf(req).orgId, date));
  };

  recordManually: RequestHandler = async (req, res) => {
    const input = parse(manualRecordSchema, req.body);
    const record = await this.attendance.recordManually(authOf(req), input);
    sendData(
      res,
      {
        id: record._id.toString(),
        memberId: record.memberId.toString(),
        date: record.date,
        status: record.status,
        checkInAt: record.checkInAt,
        method: record.method,
        note: record.note ?? null,
      },
      201,
    );
  };

  deleteRecord: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    await this.attendance.deleteRecord(authOf(req).orgId, id);
    sendNoContent(res);
  };
}

/** Endpoints called by a registered check-in device. */
export class KioskDeviceController {
  constructor(private readonly attendance: AttendanceService) {}

  session: RequestHandler = async (req, res) => {
    sendData(res, await this.attendance.kioskSession(kioskOf(req)));
  };

  checkIn: RequestHandler = async (req, res) => {
    const credentials = parse(checkInSchema, req.body);
    sendData(res, await this.attendance.checkIn(kioskOf(req), credentials), 201);
  };

  checkOut: RequestHandler = async (req, res) => {
    const credentials = parse(checkInSchema, req.body);
    sendData(res, await this.attendance.checkOut(kioskOf(req), credentials));
  };
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/attendance.repository.ts' <<'__ATTENDANCE_EOF__'
import type { Types, UpdateQuery } from 'mongoose';
import { TenantRepository, toLean, type Id, type Lean } from '../../core/db/tenant-repository.js';
import type { LocalDate } from '../../core/time/local-date.js';
import { AttendanceRecordModel, type AttendanceRecord } from './attendance-record.model.js';

export type AttendanceRecordRow = Lean<AttendanceRecord>;

export class AttendanceRepository extends TenantRepository<AttendanceRecord> {
  constructor() {
    super(AttendanceRecordModel);
  }

  async create(orgId: Id, data: Omit<AttendanceRecord, 'orgId'>): Promise<AttendanceRecordRow> {
    return toLean<AttendanceRecord>(await AttendanceRecordModel.create({ ...data, orgId }));
  }

  findForMemberOnDate(orgId: Id, memberId: Id, date: LocalDate): Promise<AttendanceRecordRow | null> {
    return AttendanceRecordModel.findOne(this.scoped(orgId, { memberId, date })).lean<AttendanceRecordRow>().exec();
  }

  between(orgId: Id, from: LocalDate, to: LocalDate, memberIds?: Types.ObjectId[]): Promise<AttendanceRecordRow[]> {
    return AttendanceRecordModel.find(
      this.scoped(orgId, {
        date: { $gte: from, $lte: to },
        ...(memberIds ? { memberId: { $in: memberIds } } : {}),
      }),
    )
      .sort({ date: 1, checkInAt: 1 })
      .lean<AttendanceRecordRow[]>()
      .exec();
  }

  /** Sets check-out only if the member checked in and has not checked out yet. */
  recordCheckOut(orgId: Id, memberId: Id, date: LocalDate, at: Date): Promise<AttendanceRecordRow | null> {
    return AttendanceRecordModel.findOneAndUpdate(
      this.scoped(orgId, { memberId, date, checkOutAt: { $exists: false } }),
      { $set: { checkOutAt: at } },
      { returnDocument: 'after' },
    )
      .lean<AttendanceRecordRow>()
      .exec();
  }

  upsertForMemberOnDate(
    orgId: Id,
    memberId: Id,
    date: LocalDate,
    update: UpdateQuery<AttendanceRecord>,
  ): Promise<AttendanceRecordRow | null> {
    return AttendanceRecordModel.findOneAndUpdate(this.scoped(orgId, { memberId, date }), update, {
      returnDocument: 'after',
      upsert: true,
      runValidators: true,
      setDefaultsOnInsert: true,
    })
      .lean<AttendanceRecordRow>()
      .exec();
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/attendance.routes.ts' <<'__ATTENDANCE_EOF__'
import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { RateLimiters } from '../../core/middleware/rate-limit.js';
import type { AttendanceController, KioskDeviceController } from './attendance.controller.js';

export function attendanceRoutes(controller: AttendanceController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/daily', controller.daily);
  router.post('/manual', guards.requireRole('ADMIN'), controller.recordManually);
  router.delete('/:id', guards.requireRole('ADMIN'), controller.deleteRecord);
  return router;
}

export function kioskDeviceRoutes(controller: KioskDeviceController, guards: Guards, limiters: RateLimiters): Router {
  const router = Router();
  router.use(guards.authenticateKiosk);
  router.get('/session', controller.session);
  router.post('/check-in', limiters.checkInFailures, controller.checkIn);
  router.post('/check-out', limiters.checkInFailures, controller.checkOut);
  return router;
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/attendance.schemas.ts' <<'__ATTENDANCE_EOF__'
import { z } from 'zod';
import { localDateSchema, objectIdSchema, timeOfDaySchema } from '../../core/http/schemas.js';
import { memberCodeSchema, pinSchema } from '../members/member.schemas.js';
import { ATTENDANCE_STATUSES } from './attendance-record.model.js';

/** Every field is a string of a fixed shape, so query-operator injection ({"$ne": null}) is rejected with a 400. */
export const checkInSchema = z.discriminatedUnion('method', [
  z.object({ method: z.literal('CODE'), code: memberCodeSchema, pin: pinSchema.optional() }),
  z.object({ method: z.literal('QR'), token: z.string().regex(/^qr_[\w-]{20,64}$/, 'is not a valid QR token') }),
]);

export const dailyQuerySchema = z.object({ date: localDateSchema.optional() });

export const manualRecordSchema = z.object({
  memberId: objectIdSchema,
  date: localDateSchema,
  status: z.enum(ATTENDANCE_STATUSES),
  time: timeOfDaySchema.optional(),
  note: z.string().trim().max(200).optional(),
});

export type ManualRecordInput = z.infer<typeof manualRecordSchema>;
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/attendance.service.ts' <<'__ATTENDANCE_EOF__'
import { Types } from 'mongoose';
import type { AuthContext, KioskContext } from '../../core/auth/context.js';
import { isDuplicateKeyError } from '../../core/db/mongo-errors.js';
import { ConflictError, NotFoundError, ValidationError } from '../../core/errors/index.js';
import type { Clock } from '../../core/time/clock.js';
import { isoWeekday, toInstant, toZonedMoment, type LocalDate } from '../../core/time/local-date.js';
import type { CalendarService } from '../calendar/calendar.service.js';
import type { MemberRepository } from '../members/member.repository.js';
import type { OrganizationService } from '../organizations/organization.service.js';
import type { AttendanceRecordRow, AttendanceRepository } from './attendance.repository.js';
import type { ManualRecordInput } from './attendance.schemas.js';
import { CheckInRejectedError } from './check-in/check-in.errors.js';
import type { CheckInCredentials, MemberResolverRegistry } from './check-in/member-resolver.js';

export type DailyStatus = 'PRESENT' | 'LATE' | 'ABSENT' | 'NOT_CHECKED_IN' | 'HOLIDAY' | 'NON_WORKDAY';

export interface CheckInResult {
  member: { id: string; fullName: string; group: string | null };
  status: 'PRESENT' | 'LATE';
  date: LocalDate;
  checkInAt: Date;
}

export class AttendanceService {
  constructor(
    private readonly organizations: OrganizationService,
    private readonly calendar: CalendarService,
    private readonly members: MemberRepository,
    private readonly records: AttendanceRepository,
    private readonly resolvers: MemberResolverRegistry,
    private readonly clock: Clock,
  ) {}

  /** What a kiosk screen needs to render itself. */
  async kioskSession(kiosk: KioskContext) {
    const { org, policy } = await this.organizations.getWithPolicy(kiosk.orgId);
    const now = this.clock.now();
    const moment = toZonedMoment(now, org.timezone);
    return {
      kiosk: { id: kiosk.id, name: kiosk.name },
      organization: { name: org.name, timezone: org.timezone },
      today: {
        date: moment.date,
        time: moment.time,
        isWorkday: policy.isWorkday(moment.weekday),
        isHoliday: await this.calendar.isHoliday(kiosk.orgId, moment.date),
      },
      policy: {
        kind: org.policy.kind,
        opensAt: org.policy.opensAt,
        lateAfter: org.policy.lateAfter,
        closesAt: org.policy.closesAt ?? null,
        allowCheckOut: org.policy.allowCheckOut,
      },
    };
  }

  async checkIn(kiosk: KioskContext, credentials: CheckInCredentials): Promise<CheckInResult> {
    const { org, policy } = await this.organizations.getWithPolicy(kiosk.orgId);
    const now = this.clock.now();
    const moment = toZonedMoment(now, org.timezone);

    // Time rules first: when check-in is closed nobody can probe codes.
    const decision = policy.evaluateCheckIn({
      localTime: moment.time,
      weekday: moment.weekday,
      isHoliday: await this.calendar.isHoliday(kiosk.orgId, moment.date),
    });
    if (!decision.allowed) throw new CheckInRejectedError(decision.reason, decision.message);

    const member = await this.resolvers.resolve(kiosk.orgId, credentials);

    try {
      const record = await this.records.create(kiosk.orgId, {
        memberId: member._id,
        date: moment.date,
        checkInAt: now,
        status: decision.status,
        method: credentials.method,
        kioskId: toObjectId(kiosk.id),
      });
      return {
        member: { id: member._id.toString(), fullName: member.fullName, group: member.group ?? null },
        status: record.status,
        date: record.date,
        checkInAt: record.checkInAt,
      };
    } catch (error) {
      if (isDuplicateKeyError(error)) {
        const existing = await this.records.findForMemberOnDate(kiosk.orgId, member._id, moment.date);
        throw new ConflictError(`${member.fullName} already checked in today`, {
          reason: 'ALREADY_CHECKED_IN',
          checkInAt: existing?.checkInAt ?? null,
        });
      }
      throw error;
    }
  }

  async checkOut(kiosk: KioskContext, credentials: CheckInCredentials) {
    const { org, policy } = await this.organizations.getWithPolicy(kiosk.orgId);
    if (!policy.allowsCheckOut) {
      throw new CheckInRejectedError('CHECK_OUT_DISABLED', 'Check-out is not enabled for this organization');
    }
    const member = await this.resolvers.resolve(kiosk.orgId, credentials);
    const now = this.clock.now();
    const { date } = toZonedMoment(now, org.timezone);

    const record = await this.records.recordCheckOut(kiosk.orgId, member._id, date, now);
    if (!record) {
      const existing = await this.records.findForMemberOnDate(kiosk.orgId, member._id, date);
      if (!existing) throw new CheckInRejectedError('NOT_CHECKED_IN', `${member.fullName} has not checked in today`);
      throw new ConflictError(`${member.fullName} already checked out today`, { reason: 'ALREADY_CHECKED_OUT' });
    }
    return {
      member: { id: member._id.toString(), fullName: member.fullName },
      date,
      checkInAt: record.checkInAt,
      checkOutAt: record.checkOutAt ?? now,
    };
  }

  /** Admin correction: mark someone present/late for a day (forgot to check in, device offline…). */
  async recordManually(auth: AuthContext, input: ManualRecordInput): Promise<AttendanceRecordRow> {
    const org = await this.organizations.getById(auth.orgId);
    const today = toZonedMoment(this.clock.now(), org.timezone).date;
    if (input.date > today) throw new ValidationError('Cannot record attendance for a future date');

    const member = await this.members.findById(auth.orgId, input.memberId);
    if (!member) throw new NotFoundError('Member');

    const time = input.time ?? (input.status === 'LATE' ? org.policy.lateAfter : org.policy.opensAt);
    const record = await this.records.upsertForMemberOnDate(auth.orgId, member._id, input.date, {
      $set: {
        status: input.status,
        checkInAt: toInstant(input.date, time, org.timezone),
        method: 'MANUAL',
        recordedBy: toObjectId(auth.userId),
        ...(input.note ? { note: input.note } : {}),
      },
    });
    if (!record) throw new Error('Manual attendance upsert returned no document');
    return record;
  }

  async deleteRecord(orgId: string, id: string): Promise<void> {
    if (!(await this.records.deleteById(orgId, id))) throw new NotFoundError('Attendance record');
  }

  /** Everyone expected on a date, with their status. The admin's "who is in today" screen. */
  async daily(orgId: string, requestedDate?: LocalDate) {
    const { org, policy } = await this.organizations.getWithPolicy(orgId);
    const today = toZonedMoment(this.clock.now(), org.timezone).date;
    const date = requestedDate ?? today;
    if (date > today) throw new ValidationError('Cannot view attendance for a future date');

    const [members, records, holidays] = await Promise.all([
      this.members.activeDuring(orgId, date, date),
      this.records.between(orgId, date, date),
      this.calendar.holidayDates(orgId, date, date),
    ]);
    const recordByMember = new Map(records.map((record) => [record.memberId.toString(), record]));
    const holidayName = holidays.get(date) ?? null;
    const isWorkday = policy.isWorkday(isoWeekday(date));
    const isExpectedDay = isWorkday && holidayName === null;

    const statusFor = (record: AttendanceRecordRow | undefined): DailyStatus => {
      if (record) return record.status;
      if (holidayName) return 'HOLIDAY';
      if (!isWorkday) return 'NON_WORKDAY';
      return date === today ? 'NOT_CHECKED_IN' : 'ABSENT';
    };

    const rows = members
      .filter((member) => !member.archivedOn || member.archivedOn > date || recordByMember.has(member._id.toString()))
      .map((member) => {
        const record = recordByMember.get(member._id.toString());
        return {
          member: {
            id: member._id.toString(),
            fullName: member.fullName,
            code: member.code,
            group: member.group ?? null,
          },
          status: statusFor(record),
          recordId: record?._id.toString() ?? null,
          checkInAt: record?.checkInAt ?? null,
          checkOutAt: record?.checkOutAt ?? null,
          method: record?.method ?? null,
        };
      });

    const count = (status: DailyStatus) => rows.filter((row) => row.status === status).length;
    return {
      date,
      isToday: date === today,
      isWorkday,
      holiday: holidayName,
      totals: {
        expected: isExpectedDay ? rows.length : 0,
        present: count('PRESENT'),
        late: count('LATE'),
        absent: count('ABSENT'),
        notCheckedIn: count('NOT_CHECKED_IN'),
      },
      rows,
    };
  }
}

function toObjectId(id: string): Types.ObjectId {
  return new Types.ObjectId(id);
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/check-in/check-in.errors.ts' <<'__ATTENDANCE_EOF__'
import { BusinessRuleError } from '../../../core/errors/index.js';

export type CheckInRejectionReason =
  | 'NON_WORKDAY'
  | 'HOLIDAY'
  | 'TOO_EARLY'
  | 'WINDOW_CLOSED'
  | 'INVALID_CREDENTIALS'
  | 'CHECK_OUT_DISABLED'
  | 'NOT_CHECKED_IN';

/** A kiosk request that is valid but not allowed right now. 422 so kiosk clients never treat it as a logout. */
export class CheckInRejectedError extends BusinessRuleError {
  override readonly code = 'CHECK_IN_REJECTED';

  constructor(
    readonly reason: CheckInRejectionReason,
    message: string,
  ) {
    super(message, { reason });
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/check-in/code-pin.resolver.ts' <<'__ATTENDANCE_EOF__'
import type { PasswordHasher } from '../../../core/security/password-hasher.js';
import type { MemberRecord, MemberRepository } from '../../members/member.repository.js';
import { MemberResolver, type CodeCredentials } from './member-resolver.js';

/** Typed check-in code, plus a PIN when the member has one set. */
export class CodePinResolver extends MemberResolver<CodeCredentials> {
  readonly method = 'CODE';

  constructor(
    private readonly members: MemberRepository,
    private readonly pinHasher: PasswordHasher,
  ) {
    super();
  }

  async resolve(orgId: string, { code, pin }: CodeCredentials): Promise<MemberRecord> {
    const member = await this.members.findActiveByCodeWithPin(orgId, code);
    if (!member) return this.reject();
    if (member.pinHash) {
      if (!pin || !(await this.pinHasher.verify(pin, member.pinHash))) return this.reject();
    }
    const { pinHash: _secret, ...safe } = member;
    return safe as MemberRecord;
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/check-in/member-resolver.ts' <<'__ATTENDANCE_EOF__'
import type { MemberRecord } from '../../members/member.repository.js';
import { CheckInRejectedError } from './check-in.errors.js';

export interface CodeCredentials {
  method: 'CODE';
  code: string;
  pin?: string | undefined;
}

export interface QrCredentials {
  method: 'QR';
  token: string;
}

export type CheckInCredentials = CodeCredentials | QrCredentials;

/**
 * Strategy for identifying who is checking in. Each check-in method (typed code, QR card, and later
 * NFC or geofenced phone check-in) is one subclass; the attendance service never branches on method.
 */
export abstract class MemberResolver<C extends CheckInCredentials = CheckInCredentials> {
  abstract readonly method: C['method'];

  abstract resolve(orgId: string, credentials: C): Promise<MemberRecord>;

  /** One message for "unknown code", "wrong PIN" and "revoked QR", so responses never confirm which part was right. */
  protected reject(): never {
    throw new CheckInRejectedError('INVALID_CREDENTIALS', 'Check-in details not recognised');
  }
}

export class MemberResolverRegistry {
  private readonly byMethod = new Map<CheckInCredentials['method'], MemberResolver>();

  constructor(resolvers: MemberResolver[]) {
    for (const resolver of resolvers) this.byMethod.set(resolver.method, resolver);
  }

  resolve(orgId: string, credentials: CheckInCredentials): Promise<MemberRecord> {
    const resolver = this.byMethod.get(credentials.method);
    if (!resolver) throw new Error(`No resolver registered for check-in method ${credentials.method}`);
    return resolver.resolve(orgId, credentials);
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/check-in/qr-token.resolver.ts' <<'__ATTENDANCE_EOF__'
import { sha256 } from '../../../core/security/tokens.js';
import type { MemberRecord, MemberRepository } from '../../members/member.repository.js';
import { MemberResolver, type QrCredentials } from './member-resolver.js';

/** Scanned QR token from a printed ID card. Rotating the token invalidates the old card. */
export class QrTokenResolver extends MemberResolver<QrCredentials> {
  readonly method = 'QR';

  constructor(private readonly members: MemberRepository) {
    super();
  }

  async resolve(orgId: string, { token }: QrCredentials): Promise<MemberRecord> {
    const member = await this.members.findActiveByQrHash(orgId, sha256(token));
    return member ?? this.reject();
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/policies/attendance-policy.ts' <<'__ATTENDANCE_EOF__'
import { isoWeekday, minutesOfDay, type LocalDate } from '../../../core/time/local-date.js';
import type { AttendancePolicyConfig, PolicyKind } from './policy-config.js';

export type AttendanceStatus = 'PRESENT' | 'LATE';

export type CheckInRejection = 'NON_WORKDAY' | 'HOLIDAY' | 'TOO_EARLY' | 'WINDOW_CLOSED';

export interface CheckInContext {
  /** Wall-clock time in the organisation's timezone, HH:mm */
  localTime: string;
  /** ISO weekday of the organisation's local date */
  weekday: number;
  isHoliday: boolean;
}

export type CheckInDecision =
  { allowed: true; status: AttendanceStatus } | { allowed: false; reason: CheckInRejection; message: string };

const allow = (status: AttendanceStatus): CheckInDecision => ({ allowed: true, status });
const reject = (reason: CheckInRejection, message: string): CheckInDecision => ({ allowed: false, reason, message });

/**
 * Decides whether a check-in is allowed and whether it is on time.
 *
 * Template method: `evaluateCheckIn` applies the rules every organisation shares
 * (work days, holidays, opening time), then hands the time-of-day decision to the subclass.
 * Pure and synchronous – no database, no clock – so it is trivially unit-testable.
 */
export abstract class AttendancePolicy {
  abstract readonly kind: PolicyKind;

  constructor(protected readonly config: AttendancePolicyConfig) {}

  evaluateCheckIn(context: CheckInContext): CheckInDecision {
    if (!this.isWorkday(context.weekday)) {
      return reject('NON_WORKDAY', 'Check-in is not open today');
    }
    if (context.isHoliday) {
      return reject('HOLIDAY', 'Today is a holiday');
    }
    const minute = minutesOfDay(context.localTime);
    if (minute < minutesOfDay(this.config.opensAt)) {
      return reject('TOO_EARLY', `Check-in opens at ${this.config.opensAt}`);
    }
    return this.evaluateTimeOfDay(minute);
  }

  isWorkday(weekday: number): boolean {
    return this.config.workDays.includes(weekday);
  }

  /** A day on which attendance is expected: a work day that is not a holiday. Used to derive absences. */
  isExpectedDay(date: LocalDate, holidays: ReadonlySet<LocalDate>): boolean {
    return this.isWorkday(isoWeekday(date)) && !holidays.has(date);
  }

  get allowsCheckOut(): boolean {
    return this.config.allowCheckOut;
  }

  /** On time up to and including `lateAfter`; late from the next minute. */
  protected statusAt(minute: number): AttendanceStatus {
    return minute > minutesOfDay(this.config.lateAfter) ? 'LATE' : 'PRESENT';
  }

  protected allow(status: AttendanceStatus): CheckInDecision {
    return allow(status);
  }

  protected reject(reason: CheckInRejection, message: string): CheckInDecision {
    return reject(reason, message);
  }

  protected abstract evaluateTimeOfDay(minuteOfDay: number): CheckInDecision;
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/policies/fixed-window.policy.ts' <<'__ATTENDANCE_EOF__'
import { minutesOfDay } from '../../../core/time/local-date.js';
import { AttendancePolicy, type CheckInDecision } from './attendance-policy.js';

/** Schools and shift work: check-in closes at `closesAt`. */
export class FixedWindowPolicy extends AttendancePolicy {
  readonly kind = 'FIXED_WINDOW';

  protected evaluateTimeOfDay(minute: number): CheckInDecision {
    const closesAt = this.config.closesAt ?? this.config.lateAfter;
    if (minute > minutesOfDay(closesAt)) {
      return this.reject('WINDOW_CLOSED', `Check-in closed at ${closesAt}`);
    }
    return this.allow(this.statusAt(minute));
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/policies/flexible-hours.policy.ts' <<'__ATTENDANCE_EOF__'
import { AttendancePolicy, type CheckInDecision } from './attendance-policy.js';

/** Offices: people can check in any time after opening; arriving after `lateAfter` is recorded as late. */
export class FlexibleHoursPolicy extends AttendancePolicy {
  readonly kind = 'FLEXIBLE_HOURS';

  protected evaluateTimeOfDay(minute: number): CheckInDecision {
    return this.allow(this.statusAt(minute));
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/policies/index.ts' <<'__ATTENDANCE_EOF__'
import type { AttendancePolicy } from './attendance-policy.js';
import { FixedWindowPolicy } from './fixed-window.policy.js';
import { FlexibleHoursPolicy } from './flexible-hours.policy.js';
import type { AttendancePolicyConfig } from './policy-config.js';

export * from './attendance-policy.js';
export * from './policy-config.js';
export { FixedWindowPolicy, FlexibleHoursPolicy };

/** Factory: the stored `kind` picks the concrete policy. Adding a policy = one class + one case here. */
export function createAttendancePolicy(config: AttendancePolicyConfig): AttendancePolicy {
  switch (config.kind) {
    case 'FIXED_WINDOW':
      return new FixedWindowPolicy(config);
    case 'FLEXIBLE_HOURS':
      return new FlexibleHoursPolicy(config);
    default: {
      const unreachable: never = config.kind;
      throw new Error(`Unknown attendance policy: ${String(unreachable)}`);
    }
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/attendance/policies/policy-config.ts' <<'__ATTENDANCE_EOF__'
import { z } from 'zod';
import { timeOfDaySchema } from '../../../core/http/schemas.js';
import { minutesOfDay } from '../../../core/time/local-date.js';

export const POLICY_KINDS = ['FIXED_WINDOW', 'FLEXIBLE_HOURS'] as const;
export type PolicyKind = (typeof POLICY_KINDS)[number];

/**
 * FIXED_WINDOW   – check-in only between opensAt and closesAt (schools, shifts).
 * FLEXIBLE_HOURS – check-in any time after opensAt on a work day (offices).
 * Both mark people LATE after `lateAfter`.
 */
export interface AttendancePolicyConfig {
  kind: PolicyKind;
  /** ISO weekdays: 1 = Monday … 7 = Sunday */
  workDays: number[];
  opensAt: string;
  lateAfter: string;
  closesAt?: string | undefined;
  allowCheckOut: boolean;
}

const workDaysSchema = z
  .array(z.number().int().min(1).max(7))
  .min(1, 'at least one work day is required')
  .transform((days) => [...new Set(days)].sort((a, b) => a - b));

const sharedFields = {
  workDays: workDaysSchema,
  opensAt: timeOfDaySchema,
  lateAfter: timeOfDaySchema,
  allowCheckOut: z.boolean(),
};

export const policyConfigSchema = z
  .discriminatedUnion('kind', [
    z.object({ kind: z.literal('FIXED_WINDOW'), ...sharedFields, closesAt: timeOfDaySchema }),
    z.object({ kind: z.literal('FLEXIBLE_HOURS'), ...sharedFields }),
  ])
  .superRefine((policy, ctx) => {
    if (minutesOfDay(policy.lateAfter) < minutesOfDay(policy.opensAt)) {
      ctx.addIssue({ code: 'custom', path: ['lateAfter'], message: 'must be at or after opensAt' });
    }
    if (policy.kind === 'FIXED_WINDOW' && minutesOfDay(policy.closesAt) < minutesOfDay(policy.lateAfter)) {
      ctx.addIssue({ code: 'custom', path: ['closesAt'], message: 'must be at or after lateAfter' });
    }
  });

export const WEEKDAYS: readonly number[] = [1, 2, 3, 4, 5];

export const DEFAULT_POLICIES = {
  SCHOOL: {
    kind: 'FIXED_WINDOW',
    workDays: [...WEEKDAYS],
    opensAt: '07:00',
    lateAfter: '08:00',
    closesAt: '08:30',
    allowCheckOut: false,
  },
  COMPANY: {
    kind: 'FLEXIBLE_HOURS',
    workDays: [...WEEKDAYS],
    opensAt: '06:00',
    lateAfter: '09:00',
    allowCheckOut: true,
  },
} as const satisfies Record<string, AttendancePolicyConfig>;
__ATTENDANCE_EOF__

write 'apps/api/src/modules/auth/auth.controller.ts' <<'__ATTENDANCE_EOF__'
import type { CookieOptions, Request, RequestHandler, Response } from 'express';
import type { AppConfig } from '../../config/app-config.js';
import { authOf } from '../../core/auth/context.js';
import { UnauthorizedError } from '../../core/errors/index.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { loginSchema, registerSchema } from './auth.schemas.js';
import type { AuthResult, AuthService } from './auth.service.js';
import type { ClientMeta } from './session.service.js';

export const REFRESH_COOKIE = 'att_rt';
export const REFRESH_COOKIE_PATH = '/api/v1/auth';

export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly config: AppConfig,
  ) {}

  register: RequestHandler = async (req, res) => {
    const input = parse(registerSchema, req.body);
    this.respondWithSession(res, await this.auth.register(input, clientMeta(req)), 201);
  };

  login: RequestHandler = async (req, res) => {
    const input = parse(loginSchema, req.body);
    this.respondWithSession(res, await this.auth.login(input, clientMeta(req)));
  };

  refresh: RequestHandler = async (req, res) => {
    const token = readRefreshCookie(req);
    if (!token) throw new UnauthorizedError('No active session', { reason: 'SESSION_MISSING' });
    try {
      this.respondWithSession(res, await this.auth.refresh(token, clientMeta(req)));
    } catch (error) {
      res.clearCookie(REFRESH_COOKIE, this.cookieOptions());
      throw error;
    }
  };

  logout: RequestHandler = async (req, res) => {
    await this.auth.logout(readRefreshCookie(req));
    res.clearCookie(REFRESH_COOKIE, this.cookieOptions());
    sendNoContent(res);
  };

  me: RequestHandler = async (req, res) => {
    sendData(res, await this.auth.profile(authOf(req)));
  };

  private respondWithSession(res: Response, result: AuthResult, status = 200): void {
    res.cookie(REFRESH_COOKIE, result.refreshToken, { ...this.cookieOptions(), expires: result.refreshExpiresAt });
    sendData(res, { accessToken: result.accessToken, expiresIn: result.expiresIn, ...result.profile }, status);
  }

  private cookieOptions(): CookieOptions {
    return {
      httpOnly: true,
      secure: this.config.cookie.secure,
      sameSite: this.config.cookie.sameSite,
      path: REFRESH_COOKIE_PATH,
    };
  }
}

function readRefreshCookie(req: Request): string | undefined {
  const value: unknown = req.cookies?.[REFRESH_COOKIE];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function clientMeta(req: Request): ClientMeta {
  return { userAgent: req.get('user-agent'), ip: req.ip };
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/auth/auth.routes.ts' <<'__ATTENDANCE_EOF__'
import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import { requireAjaxHeader } from '../../core/middleware/csrf.js';
import type { RateLimiters } from '../../core/middleware/rate-limit.js';
import type { AuthController } from './auth.controller.js';

export function authRoutes(controller: AuthController, guards: Guards, limiters: RateLimiters): Router {
  const router = Router();
  router.post('/register', limiters.auth, controller.register);
  router.post('/login', limiters.auth, controller.login);
  router.post('/refresh', requireAjaxHeader, controller.refresh);
  router.post('/logout', requireAjaxHeader, controller.logout);
  router.get('/me', guards.authenticate, controller.me);
  return router;
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/auth/auth.schemas.ts' <<'__ATTENDANCE_EOF__'
import { z } from 'zod';
import { objectIdSchema } from '../../core/http/schemas.js';
import { createOrganizationSchema } from '../organizations/organization.schemas.js';

export const emailSchema = z.string().trim().toLowerCase().pipe(z.email('must be a valid email address').max(254));

export const passwordSchema = z
  .string()
  .min(8, 'must be at least 8 characters')
  .max(128, 'must be at most 128 characters');

export const personNameSchema = z.string().trim().min(2).max(120);

export const registerSchema = z.object({
  organization: createOrganizationSchema,
  user: z.object({
    name: personNameSchema,
    email: emailSchema,
    password: passwordSchema,
  }),
});

export const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1).max(128),
  organizationId: objectIdSchema.optional(),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
__ATTENDANCE_EOF__

write 'apps/api/src/modules/auth/auth.service.ts' <<'__ATTENDANCE_EOF__'
import type { AccessTokenService } from '../../core/auth/access-token.service.js';
import type { AuthContext } from '../../core/auth/context.js';
import type { Role } from '../../core/auth/roles.js';
import { ConflictError, ForbiddenError, UnauthorizedError } from '../../core/errors/index.js';
import type { PasswordHasher } from '../../core/security/password-hasher.js';
import type { Clock } from '../../core/time/clock.js';
import { toOrganizationDto, type OrganizationDto } from '../organizations/organization.dto.js';
import type { OrganizationService } from '../organizations/organization.service.js';
import type { LoginInput, RegisterInput } from './auth.schemas.js';
import { MembershipModel } from './membership.model.js';
import type { ClientMeta, SessionService } from './session.service.js';
import { UserModel } from './user.model.js';

export interface Profile {
  user: { id: string; name: string; email: string };
  organization: OrganizationDto;
  role: Role;
  organizations: Array<{ id: string; name: string; role: Role }>;
}

export interface AuthResult {
  accessToken: string;
  expiresIn: number;
  refreshToken: string;
  refreshExpiresAt: Date;
  profile: Profile;
}

const INVALID_LOGIN = 'Invalid email or password';

export class AuthService {
  /** Hash compared against when the email does not exist, so response time does not reveal registered emails. */
  private timingDummyHash: Promise<string> | undefined;

  constructor(
    private readonly organizations: OrganizationService,
    private readonly sessions: SessionService,
    private readonly passwords: PasswordHasher,
    private readonly accessTokens: AccessTokenService,
    private readonly clock: Clock,
  ) {}

  async register(input: RegisterInput, meta: ClientMeta): Promise<AuthResult> {
    if (await UserModel.exists({ email: input.user.email })) {
      throw new ConflictError('An account with this email already exists');
    }

    // No multi-document transaction so this also runs on a standalone local MongoDB.
    // If a later step fails, earlier documents are removed (compensating actions).
    const org = await this.organizations.create(input.organization);
    let userId: string | undefined;
    try {
      const user = await UserModel.create({
        email: input.user.email,
        name: input.user.name,
        passwordHash: await this.passwords.hash(input.user.password),
      });
      userId = user._id.toString();
      await MembershipModel.create({ userId, orgId: org._id, role: 'OWNER' });
    } catch (error) {
      await Promise.all([
        this.organizations.delete(org._id.toString()),
        userId ? UserModel.deleteOne({ _id: userId }).exec() : undefined,
      ]);
      throw error;
    }

    return this.startSession({ userId, orgId: org._id.toString(), role: 'OWNER' }, meta);
  }

  async login(input: LoginInput, meta: ClientMeta): Promise<AuthResult> {
    const user = await UserModel.findOne({ email: input.email }).select('+passwordHash').exec();
    if (!user) {
      await this.passwords.verify(input.password, await this.dummyHash());
      throw new UnauthorizedError(INVALID_LOGIN);
    }
    if (!(await this.passwords.verify(input.password, user.passwordHash))) {
      throw new UnauthorizedError(INVALID_LOGIN);
    }

    const membership = await MembershipModel.findOne({
      userId: user._id,
      ...(input.organizationId ? { orgId: input.organizationId } : {}),
    })
      .sort({ createdAt: 1 })
      .lean()
      .exec();
    if (!membership) throw new ForbiddenError('This account does not have access to an organization');

    user.lastLoginAt = this.clock.now();
    await user.save();

    return this.startSession(
      { userId: user._id.toString(), orgId: membership.orgId.toString(), role: membership.role },
      meta,
    );
  }

  async refresh(refreshToken: string, meta: ClientMeta): Promise<AuthResult> {
    const session = await this.sessions.consume(refreshToken);
    const userId = session.userId.toString();
    const orgId = session.orgId.toString();

    // Role changes and removals take effect here, at most one access-token lifetime later.
    const membership = await MembershipModel.findOne({ userId, orgId }).lean().exec();
    if (!membership) {
      await this.sessions.revokeAllForUser(userId, orgId);
      throw new UnauthorizedError('You no longer have access to this organization');
    }
    return this.startSession({ userId, orgId, role: membership.role }, meta);
  }

  async logout(refreshToken: string | undefined): Promise<void> {
    if (refreshToken) await this.sessions.revoke(refreshToken);
  }

  async profile(auth: AuthContext): Promise<Profile> {
    const [user, memberships] = await Promise.all([
      UserModel.findById(auth.userId).lean().exec(),
      MembershipModel.find({ userId: auth.userId }).sort({ createdAt: 1 }).lean().exec(),
    ]);
    if (!user) throw new UnauthorizedError('Account no longer exists');

    const orgs = await this.organizations.findManyByIds(memberships.map((m) => m.orgId.toString()));
    const current = orgs.find((org) => org._id.toString() === auth.orgId);
    if (!current) throw new UnauthorizedError('You no longer have access to this organization');

    const nameById = new Map(orgs.map((org) => [org._id.toString(), org.name]));
    return {
      user: { id: user._id.toString(), name: user.name, email: user.email },
      organization: toOrganizationDto(current),
      role: auth.role,
      organizations: memberships.map((m) => ({
        id: m.orgId.toString(),
        name: nameById.get(m.orgId.toString()) ?? 'Unknown',
        role: m.role,
      })),
    };
  }

  private async startSession(context: AuthContext, meta: ClientMeta): Promise<AuthResult> {
    const { accessToken, expiresIn } = this.accessTokens.sign(context);
    const [issued, profile] = await Promise.all([
      this.sessions.issue(context.userId, context.orgId, meta),
      this.profile(context),
    ]);
    return { accessToken, expiresIn, refreshToken: issued.refreshToken, refreshExpiresAt: issued.expiresAt, profile };
  }

  private dummyHash(): Promise<string> {
    this.timingDummyHash ??= this.passwords.hash('timing-equaliser-not-a-real-password');
    return this.timingDummyHash;
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/auth/membership.model.ts' <<'__ATTENDANCE_EOF__'
import { Schema, model, type Types } from 'mongoose';
import { ROLES, type Role } from '../../core/auth/roles.js';

/** Links a login (User) to an Organization with a role. One user can belong to several organisations. */
export interface Membership {
  userId: Types.ObjectId;
  orgId: Types.ObjectId;
  role: Role;
  createdAt: Date;
  updatedAt: Date;
}

const membershipSchema = new Schema<Membership>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    role: { type: String, enum: ROLES, required: true },
  },
  { timestamps: true },
);

membershipSchema.index({ userId: 1, orgId: 1 }, { unique: true });
membershipSchema.index({ orgId: 1, role: 1 });

export const MembershipModel = model<Membership>('Membership', membershipSchema);
__ATTENDANCE_EOF__

write 'apps/api/src/modules/auth/session.model.ts' <<'__ATTENDANCE_EOF__'
import { Schema, model, type Types } from 'mongoose';

/** A refresh-token session. Only the SHA-256 of the token is stored. */
export interface Session {
  userId: Types.ObjectId;
  orgId: Types.ObjectId;
  tokenHash: string;
  expiresAt: Date;
  revokedAt?: Date;
  userAgent?: string;
  ip?: string;
}

const sessionSchema = new Schema<Session>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    tokenHash: { type: String, required: true, unique: true },
    expiresAt: { type: Date, required: true },
    revokedAt: { type: Date },
    userAgent: { type: String, maxlength: 300 },
    ip: { type: String, maxlength: 64 },
  },
  { timestamps: true },
);

// MongoDB deletes expired sessions automatically.
sessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export const SessionModel = model<Session>('Session', sessionSchema);
__ATTENDANCE_EOF__

write 'apps/api/src/modules/auth/session.service.ts' <<'__ATTENDANCE_EOF__'
import type { Lean } from '../../core/db/tenant-repository.js';
import { UnauthorizedError } from '../../core/errors/index.js';
import { randomToken, sha256 } from '../../core/security/tokens.js';
import type { Clock } from '../../core/time/clock.js';
import { SessionModel, type Session } from './session.model.js';

export interface ClientMeta {
  userAgent?: string | undefined;
  ip?: string | undefined;
}

export interface IssuedRefreshToken {
  refreshToken: string;
  expiresAt: Date;
}

/** Two tabs refreshing at the same moment is normal; a token replayed long after rotation is theft. */
const REUSE_GRACE_MS = 30_000;
const DAY_MS = 86_400_000;

/**
 * Refresh-token sessions with rotation: every refresh revokes the presented token and issues a new one.
 * Presenting an already-rotated token (outside a short grace window) revokes every session of that user.
 */
export class SessionService {
  constructor(
    private readonly ttlDays: number,
    private readonly clock: Clock,
  ) {}

  async issue(userId: string, orgId: string, meta: ClientMeta): Promise<IssuedRefreshToken> {
    const refreshToken = randomToken(32);
    const expiresAt = new Date(this.clock.now().getTime() + this.ttlDays * DAY_MS);
    await SessionModel.create({
      userId,
      orgId,
      tokenHash: sha256(refreshToken),
      expiresAt,
      userAgent: meta.userAgent?.slice(0, 300),
      ip: meta.ip,
    });
    return { refreshToken, expiresAt };
  }

  /** Validates and consumes a refresh token. Returns the session it belonged to. */
  async consume(refreshToken: string): Promise<Lean<Session>> {
    const now = this.clock.now();
    const session = await SessionModel.findOne({ tokenHash: sha256(refreshToken) })
      .lean<Lean<Session>>()
      .exec();
    if (!session) throw new UnauthorizedError('Session not found', { reason: 'SESSION_INVALID' });

    if (session.revokedAt) {
      if (now.getTime() - session.revokedAt.getTime() > REUSE_GRACE_MS) {
        await this.revokeAllForUser(session.userId.toString());
      }
      throw new UnauthorizedError('Session is no longer valid', { reason: 'SESSION_REVOKED' });
    }
    if (session.expiresAt <= now) {
      throw new UnauthorizedError('Session expired', { reason: 'SESSION_EXPIRED' });
    }

    // Atomic claim: if another request rotated this token first, this one loses.
    const claimed = await SessionModel.updateOne(
      { _id: session._id, revokedAt: { $exists: false } },
      { $set: { revokedAt: now } },
    ).exec();
    if (claimed.modifiedCount !== 1) {
      throw new UnauthorizedError('Session is no longer valid', { reason: 'SESSION_REVOKED' });
    }
    return session;
  }

  async revoke(refreshToken: string): Promise<void> {
    await SessionModel.updateOne(
      { tokenHash: sha256(refreshToken), revokedAt: { $exists: false } },
      { $set: { revokedAt: this.clock.now() } },
    ).exec();
  }

  async revokeAllForUser(userId: string, orgId?: string): Promise<void> {
    await SessionModel.updateMany(
      { userId, ...(orgId ? { orgId } : {}), revokedAt: { $exists: false } },
      { $set: { revokedAt: this.clock.now() } },
    ).exec();
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/auth/user.model.ts' <<'__ATTENDANCE_EOF__'
import { Schema, model } from 'mongoose';

export interface User {
  email: string;
  name: string;
  passwordHash: string;
  lastLoginAt?: Date;
}

const userSchema = new Schema<User>(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true, maxlength: 254 },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    passwordHash: { type: String, required: true, select: false },
    lastLoginAt: { type: Date },
  },
  { timestamps: true },
);

export const UserModel = model<User>('User', userSchema);
__ATTENDANCE_EOF__

write 'apps/api/src/modules/calendar/calendar.controller.ts' <<'__ATTENDANCE_EOF__'
import type { RequestHandler } from 'express';
import { authOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { idParamsSchema } from '../../core/http/schemas.js';
import { createHolidaySchema, createPeriodSchema, holidayQuerySchema, updatePeriodSchema } from './calendar.schemas.js';
import { toHolidayDto, toPeriodDto, type CalendarService } from './calendar.service.js';

export class CalendarController {
  constructor(private readonly calendar: CalendarService) {}

  listHolidays: RequestHandler = async (req, res) => {
    const { from, to } = parse(holidayQuerySchema, req.query);
    sendData(res, (await this.calendar.listHolidays(authOf(req).orgId, from, to)).map(toHolidayDto));
  };

  addHoliday: RequestHandler = async (req, res) => {
    const { date, name } = parse(createHolidaySchema, req.body);
    sendData(res, toHolidayDto(await this.calendar.addHoliday(authOf(req).orgId, date, name)), 201);
  };

  removeHoliday: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    await this.calendar.removeHoliday(authOf(req).orgId, id);
    sendNoContent(res);
  };

  listPeriods: RequestHandler = async (req, res) => {
    sendData(res, (await this.calendar.listPeriods(authOf(req).orgId)).map(toPeriodDto));
  };

  createPeriod: RequestHandler = async (req, res) => {
    const input = parse(createPeriodSchema, req.body);
    sendData(res, toPeriodDto(await this.calendar.createPeriod(authOf(req).orgId, input)), 201);
  };

  updatePeriod: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    const input = parse(updatePeriodSchema, req.body);
    sendData(res, toPeriodDto(await this.calendar.updatePeriod(authOf(req).orgId, id, input)));
  };

  deletePeriod: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    await this.calendar.deletePeriod(authOf(req).orgId, id);
    sendNoContent(res);
  };
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/calendar/calendar.repositories.ts' <<'__ATTENDANCE_EOF__'
import type { UpdateQuery } from 'mongoose';
import { TenantRepository, toLean, type Lean } from '../../core/db/tenant-repository.js';
import type { LocalDate } from '../../core/time/local-date.js';
import { HolidayModel, type Holiday } from './holiday.model.js';
import { PeriodModel, type Period } from './period.model.js';

export type HolidayRecord = Lean<Holiday>;
export type PeriodRecord = Lean<Period>;

export class HolidayRepository extends TenantRepository<Holiday> {
  constructor() {
    super(HolidayModel);
  }

  between(orgId: string, from: LocalDate, to: LocalDate): Promise<HolidayRecord[]> {
    return HolidayModel.find(this.scoped(orgId, { date: { $gte: from, $lte: to } }))
      .sort({ date: 1 })
      .lean<HolidayRecord[]>()
      .exec();
  }

  isHoliday(orgId: string, date: LocalDate): Promise<boolean> {
    return this.exists(orgId, { date });
  }

  async create(orgId: string, data: Omit<Holiday, 'orgId'>): Promise<HolidayRecord> {
    return toLean<Holiday>(await HolidayModel.create({ ...data, orgId }));
  }
}

export class PeriodRepository extends TenantRepository<Period> {
  constructor() {
    super(PeriodModel);
  }

  list(orgId: string): Promise<PeriodRecord[]> {
    return PeriodModel.find(this.scoped(orgId)).sort({ startsOn: -1 }).lean<PeriodRecord[]>().exec();
  }

  async create(orgId: string, data: Omit<Period, 'orgId'>): Promise<PeriodRecord> {
    return toLean<Period>(await PeriodModel.create({ ...data, orgId }));
  }

  update(orgId: string, id: string, update: UpdateQuery<Period>): Promise<PeriodRecord | null> {
    return PeriodModel.findOneAndUpdate(this.scoped(orgId, { _id: id }), update, {
      returnDocument: 'after',
      runValidators: true,
    })
      .lean<PeriodRecord>()
      .exec();
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/calendar/calendar.routes.ts' <<'__ATTENDANCE_EOF__'
import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { CalendarController } from './calendar.controller.js';

/** Mounted at /holidays */
export function holidayRoutes(controller: CalendarController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/', controller.listHolidays);
  router.post('/', guards.requireRole('ADMIN'), controller.addHoliday);
  router.delete('/:id', guards.requireRole('ADMIN'), controller.removeHoliday);
  return router;
}

/** Mounted at /periods – terms, sessions, months used for reports. */
export function periodRoutes(controller: CalendarController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/', controller.listPeriods);
  router.post('/', guards.requireRole('ADMIN'), controller.createPeriod);
  router.patch('/:id', guards.requireRole('ADMIN'), controller.updatePeriod);
  router.delete('/:id', guards.requireRole('ADMIN'), controller.deletePeriod);
  return router;
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/calendar/calendar.schemas.ts' <<'__ATTENDANCE_EOF__'
import { z } from 'zod';
import { dateRangeSchema, localDateSchema } from '../../core/http/schemas.js';
import { daysInclusive } from '../../core/time/local-date.js';
import { PERIOD_TYPES } from './period.model.js';

export const MAX_RANGE_DAYS = 400;

export const createHolidaySchema = z.object({
  date: localDateSchema,
  name: z.string().trim().min(2).max(80),
});

export const holidayQuerySchema = dateRangeSchema;

const periodFields = {
  name: z.string().trim().min(2).max(80),
  type: z.enum(PERIOD_TYPES),
  startsOn: localDateSchema,
  endsOn: localDateSchema,
};

const validRange = (period: { startsOn?: string | undefined; endsOn?: string | undefined }) =>
  !period.startsOn || !period.endsOn || period.startsOn <= period.endsOn;

const withinLimit = (period: { startsOn?: string | undefined; endsOn?: string | undefined }) =>
  !period.startsOn || !period.endsOn || daysInclusive(period.startsOn, period.endsOn) <= MAX_RANGE_DAYS;

export const createPeriodSchema = z
  .object(periodFields)
  .refine(validRange, { message: 'endsOn must be on or after startsOn', path: ['endsOn'] })
  .refine(withinLimit, { message: `a period can span at most ${MAX_RANGE_DAYS} days`, path: ['endsOn'] });

export const updatePeriodSchema = z
  .object({
    name: periodFields.name.optional(),
    type: periodFields.type.optional(),
    startsOn: periodFields.startsOn.optional(),
    endsOn: periodFields.endsOn.optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'provide at least one field to update');

export type CreatePeriodInput = z.infer<typeof createPeriodSchema>;
export type UpdatePeriodInput = z.infer<typeof updatePeriodSchema>;
__ATTENDANCE_EOF__

write 'apps/api/src/modules/calendar/calendar.service.ts' <<'__ATTENDANCE_EOF__'
import { ConflictError, NotFoundError, ValidationError } from '../../core/errors/index.js';
import { daysInclusive, type LocalDate } from '../../core/time/local-date.js';
import type { HolidayRecord, HolidayRepository, PeriodRecord, PeriodRepository } from './calendar.repositories.js';
import { MAX_RANGE_DAYS, type CreatePeriodInput, type UpdatePeriodInput } from './calendar.schemas.js';

export class CalendarService {
  constructor(
    private readonly holidays: HolidayRepository,
    private readonly periods: PeriodRepository,
  ) {}

  listHolidays(orgId: string, from: LocalDate, to: LocalDate): Promise<HolidayRecord[]> {
    return this.holidays.between(orgId, from, to);
  }

  async holidayDates(orgId: string, from: LocalDate, to: LocalDate): Promise<Map<LocalDate, string>> {
    const rows = await this.holidays.between(orgId, from, to);
    return new Map(rows.map((row) => [row.date, row.name]));
  }

  isHoliday(orgId: string, date: LocalDate): Promise<boolean> {
    return this.holidays.isHoliday(orgId, date);
  }

  async addHoliday(orgId: string, date: LocalDate, name: string): Promise<HolidayRecord> {
    if (await this.holidays.isHoliday(orgId, date)) {
      throw new ConflictError(`${date} is already marked as a holiday`);
    }
    return this.holidays.create(orgId, { date, name });
  }

  async removeHoliday(orgId: string, id: string): Promise<void> {
    if (!(await this.holidays.deleteById(orgId, id))) throw new NotFoundError('Holiday');
  }

  listPeriods(orgId: string): Promise<PeriodRecord[]> {
    return this.periods.list(orgId);
  }

  async getPeriod(orgId: string, id: string): Promise<PeriodRecord> {
    const period = await this.periods.findById(orgId, id);
    if (!period) throw new NotFoundError('Period');
    return period;
  }

  createPeriod(orgId: string, input: CreatePeriodInput): Promise<PeriodRecord> {
    return this.periods.create(orgId, input);
  }

  async updatePeriod(orgId: string, id: string, input: UpdatePeriodInput): Promise<PeriodRecord> {
    const current = await this.getPeriod(orgId, id);
    const startsOn = input.startsOn ?? current.startsOn;
    const endsOn = input.endsOn ?? current.endsOn;
    if (startsOn > endsOn) throw new ValidationError('endsOn must be on or after startsOn');
    if (daysInclusive(startsOn, endsOn) > MAX_RANGE_DAYS) {
      throw new ValidationError(`a period can span at most ${MAX_RANGE_DAYS} days`);
    }
    const updated = await this.periods.update(orgId, id, { $set: input });
    if (!updated) throw new NotFoundError('Period');
    return updated;
  }

  async deletePeriod(orgId: string, id: string): Promise<void> {
    if (!(await this.periods.deleteById(orgId, id))) throw new NotFoundError('Period');
  }
}

export const toHolidayDto = (holiday: HolidayRecord) => ({
  id: holiday._id.toString(),
  date: holiday.date,
  name: holiday.name,
});

export const toPeriodDto = (period: PeriodRecord) => ({
  id: period._id.toString(),
  name: period.name,
  type: period.type,
  startsOn: period.startsOn,
  endsOn: period.endsOn,
});
__ATTENDANCE_EOF__

write 'apps/api/src/modules/calendar/holiday.model.ts' <<'__ATTENDANCE_EOF__'
import { Schema, model, type Types } from 'mongoose';
import type { LocalDate } from '../../core/time/local-date.js';

export interface Holiday {
  orgId: Types.ObjectId;
  date: LocalDate;
  name: string;
}

const holidaySchema = new Schema<Holiday>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    date: { type: String, required: true },
    name: { type: String, required: true, trim: true, maxlength: 80 },
  },
  { timestamps: true },
);

holidaySchema.index({ orgId: 1, date: 1 }, { unique: true });

export const HolidayModel = model<Holiday>('Holiday', holidaySchema);
__ATTENDANCE_EOF__

write 'apps/api/src/modules/calendar/period.model.ts' <<'__ATTENDANCE_EOF__'
import { Schema, model, type Types } from 'mongoose';
import type { LocalDate } from '../../core/time/local-date.js';

export const PERIOD_TYPES = ['MONTH', 'TERM', 'SESSION', 'CUSTOM'] as const;
export type PeriodType = (typeof PERIOD_TYPES)[number];

/** A named reporting range: "1st Term 2026/27", "2026/27 Session", "Q3 2026"… */
export interface Period {
  orgId: Types.ObjectId;
  name: string;
  type: PeriodType;
  startsOn: LocalDate;
  endsOn: LocalDate;
}

const periodSchema = new Schema<Period>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    name: { type: String, required: true, trim: true, maxlength: 80 },
    type: { type: String, enum: PERIOD_TYPES, required: true },
    startsOn: { type: String, required: true },
    endsOn: { type: String, required: true },
  },
  { timestamps: true },
);

periodSchema.index({ orgId: 1, startsOn: -1 });

export const PeriodModel = model<Period>('Period', periodSchema);
__ATTENDANCE_EOF__

write 'apps/api/src/modules/kiosks/kiosk.controller.ts' <<'__ATTENDANCE_EOF__'
import type { RequestHandler } from 'express';
import { z } from 'zod';
import { authOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { idParamsSchema } from '../../core/http/schemas.js';
import { toKioskDto, type KioskService } from './kiosk.service.js';

const createKioskSchema = z.object({ name: z.string().trim().min(2).max(80) });

export class KioskController {
  constructor(private readonly kiosks: KioskService) {}

  list: RequestHandler = async (req, res) => {
    sendData(res, (await this.kiosks.list(authOf(req).orgId)).map(toKioskDto));
  };

  create: RequestHandler = async (req, res) => {
    const { name } = parse(createKioskSchema, req.body);
    const { kiosk, token } = await this.kiosks.create(authOf(req).orgId, name);
    sendData(res, { kiosk: toKioskDto(kiosk), token }, 201);
  };

  revoke: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    await this.kiosks.revoke(authOf(req).orgId, id);
    sendNoContent(res);
  };
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/kiosks/kiosk.model.ts' <<'__ATTENDANCE_EOF__'
import { Schema, model, type Types } from 'mongoose';

/** A registered check-in device (tablet at the gate, reception PC). */
export interface Kiosk {
  orgId: Types.ObjectId;
  name: string;
  tokenHash: string;
  /** Last characters of the token, so admins can tell devices apart without seeing the secret. */
  tokenHint: string;
  lastSeenAt?: Date;
  revokedAt?: Date;
}

const kioskSchema = new Schema<Kiosk>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true, index: true },
    name: { type: String, required: true, trim: true, maxlength: 80 },
    tokenHash: { type: String, required: true, unique: true, select: false },
    tokenHint: { type: String, required: true },
    lastSeenAt: { type: Date },
    revokedAt: { type: Date },
  },
  { timestamps: true },
);

export const KioskModel = model<Kiosk>('Kiosk', kioskSchema);
__ATTENDANCE_EOF__

write 'apps/api/src/modules/kiosks/kiosk.routes.ts' <<'__ATTENDANCE_EOF__'
import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { KioskController } from './kiosk.controller.js';

export function kioskRoutes(controller: KioskController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate, guards.requireRole('ADMIN'));
  router.get('/', controller.list);
  router.post('/', controller.create);
  router.delete('/:id', controller.revoke);
  return router;
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/kiosks/kiosk.service.ts' <<'__ATTENDANCE_EOF__'
import type { KioskContext } from '../../core/auth/context.js';
import type { KioskAuthenticator } from '../../core/auth/guards.js';
import { TenantRepository, toLean, type Lean } from '../../core/db/tenant-repository.js';
import { NotFoundError, UnauthorizedError } from '../../core/errors/index.js';
import { randomToken, sha256 } from '../../core/security/tokens.js';
import type { Clock } from '../../core/time/clock.js';
import { KioskModel, type Kiosk } from './kiosk.model.js';

export type KioskRecord = Lean<Kiosk>;

const LAST_SEEN_RESOLUTION_MS = 5 * 60 * 1000;

export class KioskRepository extends TenantRepository<Kiosk> {
  constructor() {
    super(KioskModel);
  }

  list(orgId: string): Promise<KioskRecord[]> {
    return KioskModel.find(this.scoped(orgId)).sort({ createdAt: -1 }).lean<KioskRecord[]>().exec();
  }

  async create(orgId: string, data: Omit<Kiosk, 'orgId'>): Promise<KioskRecord> {
    return toLean<Kiosk>(await KioskModel.create({ ...data, orgId }));
  }

  revoke(orgId: string, id: string, at: Date): Promise<KioskRecord | null> {
    return KioskModel.findOneAndUpdate(
      this.scoped(orgId, { _id: id, revokedAt: { $exists: false } }),
      { $set: { revokedAt: at } },
      { returnDocument: 'after' },
    )
      .lean<KioskRecord>()
      .exec();
  }
}

export class KioskService implements KioskAuthenticator {
  constructor(
    private readonly kiosks: KioskRepository,
    private readonly clock: Clock,
  ) {}

  list(orgId: string): Promise<KioskRecord[]> {
    return this.kiosks.list(orgId);
  }

  /** Registers a device. The token is shown once; only its hash is stored. */
  async create(orgId: string, name: string): Promise<{ kiosk: KioskRecord; token: string }> {
    const token = `kio_${randomToken(32)}`;
    const kiosk = await this.kiosks.create(orgId, { name, tokenHash: sha256(token), tokenHint: token.slice(-4) });
    return { kiosk, token };
  }

  async revoke(orgId: string, id: string): Promise<void> {
    const revoked = await this.kiosks.revoke(orgId, id, this.clock.now());
    if (!revoked) throw new NotFoundError('Active kiosk');
  }

  async authenticate(token: string): Promise<KioskContext> {
    const kiosk = await KioskModel.findOne({ tokenHash: sha256(token), revokedAt: { $exists: false } })
      .lean<KioskRecord>()
      .exec();
    if (!kiosk) throw new UnauthorizedError('Kiosk token is invalid or has been revoked');

    const now = this.clock.now();
    if (!kiosk.lastSeenAt || now.getTime() - kiosk.lastSeenAt.getTime() > LAST_SEEN_RESOLUTION_MS) {
      // Fire-and-forget: a heartbeat must never slow down or fail a check-in.
      void KioskModel.updateOne({ _id: kiosk._id }, { $set: { lastSeenAt: now } })
        .exec()
        .catch(() => undefined);
    }
    return { id: kiosk._id.toString(), orgId: kiosk.orgId.toString(), name: kiosk.name };
  }
}

export function toKioskDto(kiosk: KioskRecord) {
  return {
    id: kiosk._id.toString(),
    name: kiosk.name,
    tokenHint: kiosk.tokenHint,
    lastSeenAt: kiosk.lastSeenAt ?? null,
    revokedAt: kiosk.revokedAt ?? null,
    createdAt: kiosk.createdAt,
  };
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/members/member-code.generator.ts' <<'__ATTENDANCE_EOF__'
import { randomInt } from 'node:crypto';
import type { Id } from '../../core/db/tenant-repository.js';
import type { MemberRepository } from './member.repository.js';

const MAX_ROUNDS = 10;

/**
 * Generates random numeric check-in codes (not sequential, so they are not guessable from each other).
 * Batch-oriented: one database round-trip checks a whole batch of candidates.
 */
export class MemberCodeGenerator {
  constructor(
    private readonly members: MemberRepository,
    private readonly digits = 6,
  ) {}

  async generate(orgId: Id, count: number, reserved: ReadonlySet<string> = new Set()): Promise<string[]> {
    const accepted = new Set<string>();
    for (let round = 0; round < MAX_ROUNDS && accepted.size < count; round += 1) {
      const candidates = new Set<string>();
      while (candidates.size < count - accepted.size) {
        const code = this.randomCode();
        if (!reserved.has(code) && !accepted.has(code)) candidates.add(code);
      }
      const taken = await this.members.takenCodes(orgId, [...candidates]);
      for (const code of candidates) if (!taken.has(code)) accepted.add(code);
    }
    if (accepted.size < count) {
      throw new Error('Could not generate unique member codes; consider increasing code length');
    }
    return [...accepted];
  }

  async generateOne(orgId: Id): Promise<string> {
    const [code] = await this.generate(orgId, 1);
    return code as string;
  }

  private randomCode(): string {
    const max = 10 ** this.digits;
    return randomInt(max / 10, max).toString();
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/members/member.controller.ts' <<'__ATTENDANCE_EOF__'
import type { RequestHandler } from 'express';
import { authOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendPage } from '../../core/http/respond.js';
import { idParamsSchema } from '../../core/http/schemas.js';
import { toMemberDto } from './member.dto.js';
import {
  createMemberSchema,
  importMembersSchema,
  listMembersQuerySchema,
  updateMemberSchema,
} from './member.schemas.js';
import type { MemberService } from './member.service.js';

export class MemberController {
  constructor(private readonly members: MemberService) {}

  list: RequestHandler = async (req, res) => {
    const query = parse(listMembersQuerySchema, req.query);
    const { items, total } = await this.members.list(authOf(req).orgId, query);
    sendPage(res, items.map(toMemberDto), { page: query.page, limit: query.limit, total });
  };

  groups: RequestHandler = async (req, res) => {
    sendData(res, await this.members.groups(authOf(req).orgId));
  };

  get: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    sendData(res, toMemberDto(await this.members.get(authOf(req).orgId, id)));
  };

  create: RequestHandler = async (req, res) => {
    const input = parse(createMemberSchema, req.body);
    sendData(res, toMemberDto(await this.members.create(authOf(req).orgId, input)), 201);
  };

  update: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    const input = parse(updateMemberSchema, req.body);
    sendData(res, toMemberDto(await this.members.update(authOf(req).orgId, id, input)));
  };

  archive: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    sendData(res, toMemberDto(await this.members.archive(authOf(req).orgId, id)));
  };

  rotateQrToken: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    const { member, qrToken } = await this.members.rotateQrToken(authOf(req).orgId, id);
    sendData(res, { member: toMemberDto(member), qrToken });
  };

  import: RequestHandler = async (req, res) => {
    const input = parse(importMembersSchema, req.body);
    sendData(res, await this.members.import(authOf(req).orgId, input), 201);
  };
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/members/member.dto.ts' <<'__ATTENDANCE_EOF__'
import type { MemberRecord } from './member.repository.js';

/** Public shape of a member. PIN and QR hashes never leave the server. */
export function toMemberDto(member: MemberRecord) {
  return {
    id: member._id.toString(),
    fullName: member.fullName,
    code: member.code,
    group: member.group ?? null,
    status: member.status,
    joinedOn: member.joinedOn,
    archivedOn: member.archivedOn ?? null,
    pinSet: member.pinSet,
    qrIssuedAt: member.qrIssuedAt ?? null,
    createdAt: member.createdAt,
    updatedAt: member.updatedAt,
  };
}

export type MemberDto = ReturnType<typeof toMemberDto>;
__ATTENDANCE_EOF__

write 'apps/api/src/modules/members/member.model.ts' <<'__ATTENDANCE_EOF__'
import { Schema, model, type Types } from 'mongoose';
import type { LocalDate } from '../../core/time/local-date.js';

export const MEMBER_STATUSES = ['ACTIVE', 'ARCHIVED'] as const;
export type MemberStatus = (typeof MEMBER_STATUSES)[number];

/**
 * A person whose attendance is tracked (student, teacher, employee).
 * Distinct from User, which is someone who logs into the dashboard.
 */
export interface Member {
  orgId: Types.ObjectId;
  fullName: string;
  /** Check-in code, unique within the organisation. */
  code: string;
  /** Class, department, team… free text used for filtering and reports. */
  group?: string | undefined;
  pinHash?: string | undefined;
  pinSet: boolean;
  qrTokenHash?: string | undefined;
  qrIssuedAt?: Date | undefined;
  status: MemberStatus;
  /** First day attendance is expected (org-local date). No absences are counted before it. */
  joinedOn: LocalDate;
  /** Set when archived. No absences are counted from this date on. History is kept. */
  archivedOn?: LocalDate | undefined;
}

const memberSchema = new Schema<Member>(
  {
    orgId: { type: Schema.Types.ObjectId, ref: 'Organization', required: true },
    fullName: { type: String, required: true, trim: true, maxlength: 120 },
    code: { type: String, required: true, trim: true, uppercase: true, maxlength: 20 },
    group: { type: String, trim: true, maxlength: 60 },
    pinHash: { type: String, select: false },
    pinSet: { type: Boolean, required: true, default: false },
    qrTokenHash: { type: String, select: false },
    qrIssuedAt: { type: Date },
    status: { type: String, enum: MEMBER_STATUSES, required: true, default: 'ACTIVE' },
    joinedOn: { type: String, required: true },
    archivedOn: { type: String },
  },
  { timestamps: true },
);

memberSchema.index({ orgId: 1, code: 1 }, { unique: true });
memberSchema.index({ orgId: 1, status: 1, fullName: 1 });
memberSchema.index({ qrTokenHash: 1 });

export const MemberModel = model<Member>('Member', memberSchema);
__ATTENDANCE_EOF__

write 'apps/api/src/modules/members/member.repository.ts' <<'__ATTENDANCE_EOF__'
import type { QueryFilter, UpdateQuery } from 'mongoose';
import { TenantRepository, toLean, type Id, type Lean } from '../../core/db/tenant-repository.js';
import type { LocalDate } from '../../core/time/local-date.js';
import { MemberModel, type Member, type MemberStatus } from './member.model.js';

export type MemberRecord = Lean<Member>;

export interface MemberListQuery {
  search?: string | undefined;
  status: MemberStatus | 'ALL';
  group?: string | undefined;
  page: number;
  limit: number;
}

const escapeRegex = (value: string) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export class MemberRepository extends TenantRepository<Member> {
  constructor() {
    super(MemberModel);
  }

  async list(orgId: Id, query: MemberListQuery): Promise<{ items: MemberRecord[]; total: number }> {
    const filter: QueryFilter<Member> = {};
    if (query.status !== 'ALL') filter.status = query.status;
    if (query.group) filter.group = query.group;
    if (query.search) {
      const pattern = new RegExp(escapeRegex(query.search), 'i');
      filter.$or = [{ fullName: pattern }, { code: pattern }];
    }
    const scoped = this.scoped(orgId, filter);
    const [items, total] = await Promise.all([
      MemberModel.find(scoped)
        .sort({ fullName: 1, _id: 1 })
        .skip((query.page - 1) * query.limit)
        .limit(query.limit)
        .lean<MemberRecord[]>()
        .exec(),
      MemberModel.countDocuments(scoped).exec(),
    ]);
    return { items, total };
  }

  async findActiveByCodeWithPin(orgId: Id, code: string): Promise<MemberRecord | null> {
    return MemberModel.findOne(this.scoped(orgId, { code, status: 'ACTIVE' }))
      .select('+pinHash')
      .lean<MemberRecord>()
      .exec();
  }

  async findActiveByQrHash(orgId: Id, qrTokenHash: string): Promise<MemberRecord | null> {
    return MemberModel.findOne(this.scoped(orgId, { qrTokenHash, status: 'ACTIVE' }))
      .lean<MemberRecord>()
      .exec();
  }

  async findManyByIds(orgId: Id, ids: Id[]): Promise<MemberRecord[]> {
    return MemberModel.find(this.scoped(orgId, { _id: { $in: ids } }))
      .lean<MemberRecord[]>()
      .exec();
  }

  /** Which of these codes are already taken in the organisation. */
  async takenCodes(orgId: Id, codes: string[]): Promise<Set<string>> {
    if (codes.length === 0) return new Set();
    const rows = await MemberModel.find(this.scoped(orgId, { code: { $in: codes } }))
      .select('code')
      .lean<Array<{ code: string }>>()
      .exec();
    return new Set(rows.map((row) => row.code));
  }

  async create(orgId: Id, data: Omit<Member, 'orgId'>): Promise<MemberRecord> {
    return toLean<Member>(await MemberModel.create({ ...data, orgId }));
  }

  async createMany(orgId: Id, rows: Array<Omit<Member, 'orgId'>>): Promise<number> {
    if (rows.length === 0) return 0;
    const inserted = await MemberModel.insertMany(
      rows.map((row) => ({ ...row, orgId })),
      { ordered: false },
    );
    return inserted.length;
  }

  async update(orgId: Id, id: Id, update: UpdateQuery<Member>): Promise<MemberRecord | null> {
    return MemberModel.findOneAndUpdate(this.scoped(orgId, { _id: id }), update, {
      returnDocument: 'after',
      runValidators: true,
    })
      .lean<MemberRecord>()
      .exec();
  }

  /**
   * Members whose active span overlaps [from, to]: joined on/before `to`
   * and not archived before `from`. Used for daily views and reports.
   */
  async activeDuring(
    orgId: Id,
    from: LocalDate,
    to: LocalDate,
    options: { group?: string | undefined; memberId?: Id | undefined } = {},
  ): Promise<MemberRecord[]> {
    return MemberModel.find(
      this.scoped(orgId, {
        joinedOn: { $lte: to },
        $or: [{ status: 'ACTIVE' }, { archivedOn: { $gt: from } }],
        ...(options.group ? { group: options.group } : {}),
        ...(options.memberId ? { _id: options.memberId } : {}),
      }),
    )
      .sort({ fullName: 1, _id: 1 })
      .lean<MemberRecord[]>()
      .exec();
  }

  async groups(orgId: Id): Promise<string[]> {
    const values = await MemberModel.distinct('group', this.scoped(orgId, { status: 'ACTIVE' })).exec();
    return values.filter((value): value is string => typeof value === 'string' && value.length > 0).sort();
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/members/member.routes.ts' <<'__ATTENDANCE_EOF__'
import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { MemberController } from './member.controller.js';

export function memberRoutes(controller: MemberController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);

  router.get('/', controller.list);
  router.get('/groups', controller.groups);
  router.post('/', guards.requireRole('ADMIN'), controller.create);
  router.post('/import', guards.requireRole('ADMIN'), controller.import);
  router.get('/:id', controller.get);
  router.patch('/:id', guards.requireRole('ADMIN'), controller.update);
  router.delete('/:id', guards.requireRole('ADMIN'), controller.archive);
  router.post('/:id/qr-token', guards.requireRole('ADMIN'), controller.rotateQrToken);
  return router;
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/members/member.schemas.ts' <<'__ATTENDANCE_EOF__'
import { z } from 'zod';
import { localDateSchema, paginationSchema } from '../../core/http/schemas.js';
import { MEMBER_STATUSES } from './member.model.js';

export const memberCodeSchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z0-9-]{3,20}$/, 'must be 3–20 characters: letters, digits or dashes');

export const pinSchema = z.string().regex(/^\d{4,6}$/, 'must be 4–6 digits');

const fullNameSchema = z.string().trim().min(2).max(120);
const groupSchema = z.string().trim().min(1).max(60);

export const createMemberSchema = z.object({
  fullName: fullNameSchema,
  code: memberCodeSchema.optional(),
  group: groupSchema.optional(),
  pin: pinSchema.optional(),
  joinedOn: localDateSchema.optional(),
});

export const updateMemberSchema = z
  .object({
    fullName: fullNameSchema.optional(),
    code: memberCodeSchema.optional(),
    group: groupSchema.nullable().optional(),
    pin: pinSchema.nullable().optional(),
    status: z.enum(MEMBER_STATUSES).optional(),
    joinedOn: localDateSchema.optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'provide at least one field to update');

export const listMembersQuerySchema = paginationSchema.extend({
  search: z.string().trim().max(100).optional(),
  status: z.enum([...MEMBER_STATUSES, 'ALL']).default('ACTIVE'),
  group: groupSchema.optional(),
});

export const importMembersSchema = z.object({
  members: z
    .array(
      z.object({
        fullName: fullNameSchema,
        code: memberCodeSchema.optional(),
        group: groupSchema.optional(),
        joinedOn: localDateSchema.optional(),
      }),
    )
    .min(1)
    .max(1000, 'import at most 1000 members per request'),
});

export type CreateMemberInput = z.infer<typeof createMemberSchema>;
export type UpdateMemberInput = z.infer<typeof updateMemberSchema>;
export type ImportMembersInput = z.infer<typeof importMembersSchema>;
__ATTENDANCE_EOF__

write 'apps/api/src/modules/members/member.service.ts' <<'__ATTENDANCE_EOF__'
import type { UpdateQuery } from 'mongoose';
import { ConflictError, NotFoundError } from '../../core/errors/index.js';
import type { PasswordHasher } from '../../core/security/password-hasher.js';
import { randomToken, sha256 } from '../../core/security/tokens.js';
import type { Clock } from '../../core/time/clock.js';
import { toLocalDate } from '../../core/time/local-date.js';
import type { OrganizationService } from '../organizations/organization.service.js';
import type { MemberCodeGenerator } from './member-code.generator.js';
import type { Member } from './member.model.js';
import type { MemberListQuery, MemberRecord, MemberRepository } from './member.repository.js';
import type { CreateMemberInput, ImportMembersInput, UpdateMemberInput } from './member.schemas.js';

export interface ImportResult {
  created: number;
  skipped: Array<{ row: number; fullName: string; reason: string }>;
}

export class MemberService {
  constructor(
    private readonly members: MemberRepository,
    private readonly organizations: OrganizationService,
    private readonly codes: MemberCodeGenerator,
    private readonly pinHasher: PasswordHasher,
    private readonly clock: Clock,
  ) {}

  list(orgId: string, query: MemberListQuery) {
    return this.members.list(orgId, query);
  }

  groups(orgId: string): Promise<string[]> {
    return this.members.groups(orgId);
  }

  async get(orgId: string, id: string): Promise<MemberRecord> {
    const member = await this.members.findById(orgId, id);
    if (!member) throw new NotFoundError('Member');
    return member;
  }

  async create(orgId: string, input: CreateMemberInput): Promise<MemberRecord> {
    const code = input.code ?? (await this.codes.generateOne(orgId));
    if (input.code && (await this.members.exists(orgId, { code }))) {
      throw new ConflictError(`Code ${code} is already assigned to another member`);
    }
    return this.members.create(orgId, {
      fullName: input.fullName,
      code,
      group: input.group,
      pinHash: input.pin ? await this.pinHasher.hash(input.pin) : undefined,
      pinSet: Boolean(input.pin),
      status: 'ACTIVE',
      joinedOn: input.joinedOn ?? (await this.today(orgId)),
    });
  }

  async update(orgId: string, id: string, input: UpdateMemberInput): Promise<MemberRecord> {
    const current = await this.get(orgId, id);
    const $set: Partial<Member> = {};
    const $unset: Record<string, 1> = {};

    if (input.fullName !== undefined) $set.fullName = input.fullName;
    if (input.joinedOn !== undefined) $set.joinedOn = input.joinedOn;
    if (input.group !== undefined) {
      if (input.group === null) $unset.group = 1;
      else $set.group = input.group;
    }
    if (input.code !== undefined && input.code !== current.code) {
      if (await this.members.exists(orgId, { code: input.code })) {
        throw new ConflictError(`Code ${input.code} is already assigned to another member`);
      }
      $set.code = input.code;
    }
    if (input.pin !== undefined) {
      if (input.pin === null) {
        $unset.pinHash = 1;
        $set.pinSet = false;
      } else {
        $set.pinHash = await this.pinHasher.hash(input.pin);
        $set.pinSet = true;
      }
    }
    if (input.status !== undefined && input.status !== current.status) {
      if (input.status === 'ARCHIVED') $set.archivedOn = await this.today(orgId);
      else $unset.archivedOn = 1;
      $set.status = input.status;
    }

    const update: UpdateQuery<Member> = {};
    if (Object.keys($set).length > 0) update.$set = $set;
    if (Object.keys($unset).length > 0) update.$unset = $unset;
    if (Object.keys(update).length === 0) return current;
    const updated = await this.members.update(orgId, id, update);
    if (!updated) throw new NotFoundError('Member');
    return updated;
  }

  /** Soft delete: the member stops being expected, but their history stays in every report. */
  archive(orgId: string, id: string): Promise<MemberRecord> {
    return this.update(orgId, id, { status: 'ARCHIVED' });
  }

  /** Issues a new QR token (e.g. for an ID card). The raw token is returned once and never stored. */
  async rotateQrToken(orgId: string, id: string): Promise<{ member: MemberRecord; qrToken: string }> {
    const qrToken = `qr_${randomToken(24)}`;
    const member = await this.members.update(orgId, id, {
      $set: { qrTokenHash: sha256(qrToken), qrIssuedAt: this.clock.now() },
    });
    if (!member) throw new NotFoundError('Member');
    return { member, qrToken };
  }

  async import(orgId: string, input: ImportMembersInput): Promise<ImportResult> {
    const today = await this.today(orgId);
    const skipped: ImportResult['skipped'] = [];

    const providedCodes = input.members.flatMap((row) => (row.code ? [row.code] : []));
    const takenInDb = await this.members.takenCodes(orgId, providedCodes);
    const seenInFile = new Set<string>();

    const accepted = input.members.flatMap((row, index) => {
      if (row.code) {
        if (takenInDb.has(row.code)) {
          skipped.push({ row: index + 1, fullName: row.fullName, reason: `Code ${row.code} already exists` });
          return [];
        }
        if (seenInFile.has(row.code)) {
          skipped.push({
            row: index + 1,
            fullName: row.fullName,
            reason: `Code ${row.code} appears twice in the file`,
          });
          return [];
        }
        seenInFile.add(row.code);
      }
      return [row];
    });

    const missing = accepted.filter((row) => !row.code).length;
    const generated = await this.codes.generate(orgId, missing, seenInFile);

    const created = await this.members.createMany(
      orgId,
      accepted.map((row) => ({
        fullName: row.fullName,
        code: row.code ?? (generated.pop() as string),
        group: row.group,
        pinSet: false,
        status: 'ACTIVE' as const,
        joinedOn: row.joinedOn ?? today,
      })),
    );
    return { created, skipped };
  }

  private async today(orgId: string): Promise<string> {
    const org = await this.organizations.getById(orgId);
    return toLocalDate(this.clock.now(), org.timezone);
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/organizations/organization.controller.ts' <<'__ATTENDANCE_EOF__'
import type { RequestHandler } from 'express';
import { authOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { policyConfigSchema } from '../attendance/policies/policy-config.js';
import { toOrganizationDto } from './organization.dto.js';
import { updateOrganizationSchema } from './organization.schemas.js';
import type { OrganizationService } from './organization.service.js';
import { addTeammateSchema, updateTeammateSchema, userIdParamsSchema } from './team.schemas.js';
import type { TeamService } from './team.service.js';

export class OrganizationController {
  constructor(
    private readonly organizations: OrganizationService,
    private readonly team: TeamService,
  ) {}

  get: RequestHandler = async (req, res) => {
    sendData(res, toOrganizationDto(await this.organizations.getById(authOf(req).orgId)));
  };

  update: RequestHandler = async (req, res) => {
    const input = parse(updateOrganizationSchema, req.body);
    sendData(res, toOrganizationDto(await this.organizations.update(authOf(req).orgId, input)));
  };

  updatePolicy: RequestHandler = async (req, res) => {
    const policy = parse(policyConfigSchema, req.body);
    sendData(res, toOrganizationDto(await this.organizations.updatePolicy(authOf(req).orgId, policy)));
  };

  listTeam: RequestHandler = async (req, res) => {
    sendData(res, await this.team.list(authOf(req).orgId));
  };

  addTeammate: RequestHandler = async (req, res) => {
    const input = parse(addTeammateSchema, req.body);
    sendData(res, await this.team.add(authOf(req), input), 201);
  };

  changeTeammateRole: RequestHandler = async (req, res) => {
    const { userId } = parse(userIdParamsSchema, req.params);
    const { role } = parse(updateTeammateSchema, req.body);
    await this.team.changeRole(authOf(req), userId, role);
    sendNoContent(res);
  };

  removeTeammate: RequestHandler = async (req, res) => {
    const { userId } = parse(userIdParamsSchema, req.params);
    await this.team.remove(authOf(req), userId);
    sendNoContent(res);
  };
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/organizations/organization.dto.ts' <<'__ATTENDANCE_EOF__'
import type { Lean } from '../../core/db/tenant-repository.js';
import type { Organization } from './organization.model.js';

export function toOrganizationDto(org: Lean<Organization>) {
  return {
    id: org._id.toString(),
    name: org.name,
    slug: org.slug,
    type: org.type,
    timezone: org.timezone,
    policy: {
      kind: org.policy.kind,
      workDays: org.policy.workDays,
      opensAt: org.policy.opensAt,
      lateAfter: org.policy.lateAfter,
      ...(org.policy.closesAt ? { closesAt: org.policy.closesAt } : {}),
      allowCheckOut: org.policy.allowCheckOut,
    },
    createdAt: org.createdAt,
  };
}

export type OrganizationDto = ReturnType<typeof toOrganizationDto>;
__ATTENDANCE_EOF__

write 'apps/api/src/modules/organizations/organization.model.ts' <<'__ATTENDANCE_EOF__'
import { Schema, model } from 'mongoose';
import { POLICY_KINDS, type AttendancePolicyConfig } from '../attendance/policies/policy-config.js';

export const ORGANIZATION_TYPES = ['SCHOOL', 'COMPANY'] as const;
export type OrganizationType = (typeof ORGANIZATION_TYPES)[number];

export interface Organization {
  name: string;
  slug: string;
  type: OrganizationType;
  timezone: string;
  policy: AttendancePolicyConfig;
}

const policySchema = new Schema<AttendancePolicyConfig>(
  {
    kind: { type: String, enum: POLICY_KINDS, required: true },
    workDays: { type: [Number], required: true },
    opensAt: { type: String, required: true },
    lateAfter: { type: String, required: true },
    closesAt: { type: String },
    allowCheckOut: { type: Boolean, required: true },
  },
  { _id: false },
);

const organizationSchema = new Schema<Organization>(
  {
    name: { type: String, required: true, trim: true, maxlength: 120 },
    slug: { type: String, required: true, unique: true, lowercase: true, trim: true },
    type: { type: String, enum: ORGANIZATION_TYPES, required: true },
    timezone: { type: String, required: true, default: 'Africa/Lagos' },
    policy: { type: policySchema, required: true },
  },
  { timestamps: true },
);

export const OrganizationModel = model<Organization>('Organization', organizationSchema);
__ATTENDANCE_EOF__

write 'apps/api/src/modules/organizations/organization.routes.ts' <<'__ATTENDANCE_EOF__'
import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { OrganizationController } from './organization.controller.js';

/** Mounted at /organization */
export function organizationRoutes(controller: OrganizationController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/', controller.get);
  router.patch('/', guards.requireRole('ADMIN'), controller.update);
  router.put('/policy', guards.requireRole('ADMIN'), controller.updatePolicy);
  return router;
}

/** Mounted at /team – dashboard accounts of the organisation. */
export function teamRoutes(controller: OrganizationController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/', guards.requireRole('ADMIN'), controller.listTeam);
  router.post('/', guards.requireRole('ADMIN'), controller.addTeammate);
  router.patch('/:userId', guards.requireRole('OWNER'), controller.changeTeammateRole);
  router.delete('/:userId', guards.requireRole('OWNER'), controller.removeTeammate);
  return router;
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/organizations/organization.schemas.ts' <<'__ATTENDANCE_EOF__'
import { z } from 'zod';
import { isValidTimeZone } from '../../core/time/local-date.js';
import { ORGANIZATION_TYPES } from './organization.model.js';

export const timezoneSchema = z.string().refine(isValidTimeZone, 'must be a valid IANA timezone, e.g. Africa/Lagos');

export const createOrganizationSchema = z.object({
  name: z.string().trim().min(2).max(120),
  type: z.enum(ORGANIZATION_TYPES),
  timezone: timezoneSchema.default('Africa/Lagos'),
});

export const updateOrganizationSchema = z
  .object({
    name: z.string().trim().min(2).max(120).optional(),
    timezone: timezoneSchema.optional(),
  })
  .refine((body) => Object.keys(body).length > 0, 'provide at least one field to update');

export type CreateOrganizationInput = z.infer<typeof createOrganizationSchema>;
export type UpdateOrganizationInput = z.infer<typeof updateOrganizationSchema>;
__ATTENDANCE_EOF__

write 'apps/api/src/modules/organizations/organization.service.ts' <<'__ATTENDANCE_EOF__'
import { randomBytes } from 'node:crypto';
import { toLean, type Lean } from '../../core/db/tenant-repository.js';
import { NotFoundError } from '../../core/errors/index.js';
import {
  createAttendancePolicy,
  DEFAULT_POLICIES,
  type AttendancePolicy,
  type AttendancePolicyConfig,
} from '../attendance/policies/index.js';
import { OrganizationModel, type Organization } from './organization.model.js';
import type { CreateOrganizationInput, UpdateOrganizationInput } from './organization.schemas.js';

export type OrganizationRecord = Lean<Organization>;

export function slugify(value: string): string {
  return (
    value
      .normalize('NFKD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 48) || 'org'
  );
}

export class OrganizationService {
  async create(input: CreateOrganizationInput): Promise<OrganizationRecord> {
    const slug = await this.uniqueSlug(slugify(input.name));
    const created = await OrganizationModel.create({
      name: input.name,
      slug,
      type: input.type,
      timezone: input.timezone,
      policy: { ...DEFAULT_POLICIES[input.type], workDays: [...DEFAULT_POLICIES[input.type].workDays] },
    });
    return toLean<Organization>(created);
  }

  async getById(id: string): Promise<OrganizationRecord> {
    const org = await OrganizationModel.findById(id).lean<OrganizationRecord>().exec();
    if (!org) throw new NotFoundError('Organization');
    return org;
  }

  async findManyByIds(ids: string[]): Promise<OrganizationRecord[]> {
    return OrganizationModel.find({ _id: { $in: ids } })
      .lean<OrganizationRecord[]>()
      .exec();
  }

  async update(id: string, input: UpdateOrganizationInput): Promise<OrganizationRecord> {
    const org = await OrganizationModel.findByIdAndUpdate(
      id,
      { $set: input },
      { returnDocument: 'after', runValidators: true },
    )
      .lean<OrganizationRecord>()
      .exec();
    if (!org) throw new NotFoundError('Organization');
    return org;
  }

  async updatePolicy(id: string, policy: AttendancePolicyConfig): Promise<OrganizationRecord> {
    const org = await OrganizationModel.findByIdAndUpdate(
      id,
      { $set: { policy } },
      { returnDocument: 'after', runValidators: true },
    )
      .lean<OrganizationRecord>()
      .exec();
    if (!org) throw new NotFoundError('Organization');
    return org;
  }

  /** Loads the organisation together with its attendance policy object. */
  async getWithPolicy(id: string): Promise<{ org: OrganizationRecord; policy: AttendancePolicy }> {
    const org = await this.getById(id);
    return { org, policy: createAttendancePolicy(org.policy) };
  }

  async delete(id: string): Promise<void> {
    await OrganizationModel.deleteOne({ _id: id }).exec();
  }

  private async uniqueSlug(base: string): Promise<string> {
    if (!(await OrganizationModel.exists({ slug: base }))) return base;
    return `${base}-${randomBytes(3).toString('hex')}`;
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/organizations/team.schemas.ts' <<'__ATTENDANCE_EOF__'
import { z } from 'zod';
import { ROLES } from '../../core/auth/roles.js';
import { objectIdSchema } from '../../core/http/schemas.js';
import { emailSchema, passwordSchema, personNameSchema } from '../auth/auth.schemas.js';

export const addTeammateSchema = z.object({
  email: emailSchema,
  role: z.enum(ROLES),
  /** Required only when the email has no account yet. Share it with them privately; they should change it. */
  name: personNameSchema.optional(),
  temporaryPassword: passwordSchema.optional(),
});

export const updateTeammateSchema = z.object({ role: z.enum(ROLES) });

export const userIdParamsSchema = z.object({ userId: objectIdSchema });

export type AddTeammateInput = z.infer<typeof addTeammateSchema>;
__ATTENDANCE_EOF__

write 'apps/api/src/modules/organizations/team.service.ts' <<'__ATTENDANCE_EOF__'
import type { AuthContext } from '../../core/auth/context.js';
import type { Role } from '../../core/auth/roles.js';
import {
  BusinessRuleError,
  ConflictError,
  ForbiddenError,
  NotFoundError,
  ValidationError,
} from '../../core/errors/index.js';
import type { PasswordHasher } from '../../core/security/password-hasher.js';
import { MembershipModel } from '../auth/membership.model.js';
import type { SessionService } from '../auth/session.service.js';
import { UserModel } from '../auth/user.model.js';
import type { AddTeammateInput } from './team.schemas.js';

export interface TeammateDto {
  userId: string;
  name: string;
  email: string;
  role: Role;
  addedAt: Date;
}

/** Dashboard accounts (owners, admins, viewers) of an organisation. */
export class TeamService {
  constructor(
    private readonly passwords: PasswordHasher,
    private readonly sessions: SessionService,
  ) {}

  async list(orgId: string): Promise<TeammateDto[]> {
    const memberships = await MembershipModel.find({ orgId }).sort({ createdAt: 1 }).lean().exec();
    const users = await UserModel.find({ _id: { $in: memberships.map((m) => m.userId) } })
      .lean()
      .exec();
    const userById = new Map(users.map((user) => [user._id.toString(), user]));

    return memberships.flatMap((membership) => {
      const user = userById.get(membership.userId.toString());
      return user
        ? [
            {
              userId: user._id.toString(),
              name: user.name,
              email: user.email,
              role: membership.role,
              addedAt: membership.createdAt,
            },
          ]
        : [];
    });
  }

  async add(actor: AuthContext, input: AddTeammateInput): Promise<TeammateDto> {
    if (input.role === 'OWNER' && actor.role !== 'OWNER') {
      throw new ForbiddenError('Only an owner can add another owner');
    }

    let user = await UserModel.findOne({ email: input.email }).lean().exec();
    if (!user) {
      if (!input.name || !input.temporaryPassword) {
        throw new ValidationError('This email has no account yet. Provide name and temporaryPassword to create one.');
      }
      const created = await UserModel.create({
        email: input.email,
        name: input.name,
        passwordHash: await this.passwords.hash(input.temporaryPassword),
      });
      user = created.toObject();
    }

    if (await MembershipModel.exists({ userId: user._id, orgId: actor.orgId })) {
      throw new ConflictError('This person is already on the team');
    }
    const membership = await MembershipModel.create({ userId: user._id, orgId: actor.orgId, role: input.role });
    return {
      userId: user._id.toString(),
      name: user.name,
      email: user.email,
      role: membership.role,
      addedAt: membership.createdAt,
    };
  }

  async changeRole(actor: AuthContext, userId: string, role: Role): Promise<void> {
    const membership = await this.getMembership(actor.orgId, userId);
    if (membership.role === 'OWNER' && role !== 'OWNER') {
      await this.assertAnotherOwnerExists(actor.orgId, userId);
    }
    await MembershipModel.updateOne({ _id: membership._id }, { $set: { role } }).exec();
  }

  async remove(actor: AuthContext, userId: string): Promise<void> {
    const membership = await this.getMembership(actor.orgId, userId);
    if (membership.role === 'OWNER') {
      await this.assertAnotherOwnerExists(actor.orgId, userId);
    }
    await MembershipModel.deleteOne({ _id: membership._id }).exec();
    await this.sessions.revokeAllForUser(userId, actor.orgId);
  }

  private async getMembership(orgId: string, userId: string) {
    const membership = await MembershipModel.findOne({ orgId, userId }).lean().exec();
    if (!membership) throw new NotFoundError('Team member');
    return membership;
  }

  private async assertAnotherOwnerExists(orgId: string, exceptUserId: string): Promise<void> {
    const otherOwners = await MembershipModel.countDocuments({
      orgId,
      role: 'OWNER',
      userId: { $ne: exceptUserId },
    }).exec();
    if (otherOwners === 0) {
      throw new BusinessRuleError('An organization must keep at least one owner');
    }
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/exporters/csv.exporter.ts' <<'__ATTENDANCE_EOF__'
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
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/exporters/index.ts' <<'__ATTENDANCE_EOF__'
import type { ReportFormat } from '../report.types.js';
import { CsvReportExporter } from './csv.exporter.js';
import { JsonReportExporter } from './json.exporter.js';
import type { ReportExporter } from './report-exporter.js';
import { XlsxReportExporter } from './xlsx.exporter.js';

export { CsvReportExporter, JsonReportExporter, XlsxReportExporter };
export type { ReportExporter };

/** Looks up the exporter for a format. Adding PDF later = one new ReportExporter subclass registered here. */
export class ReportExporterRegistry {
  private readonly byFormat: Map<ReportFormat, ReportExporter>;

  constructor(
    exporters: ReportExporter[] = [new JsonReportExporter(), new XlsxReportExporter(), new CsvReportExporter()],
  ) {
    this.byFormat = new Map(exporters.map((exporter) => [exporter.format, exporter]));
  }

  get(format: ReportFormat): ReportExporter {
    const exporter = this.byFormat.get(format);
    if (!exporter) throw new Error(`No exporter registered for format ${format}`);
    return exporter;
  }
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/exporters/json.exporter.ts' <<'__ATTENDANCE_EOF__'
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
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/exporters/report-exporter.ts' <<'__ATTENDANCE_EOF__'
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
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/exporters/xlsx.exporter.ts' <<'__ATTENDANCE_EOF__'
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
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/report.controller.ts' <<'__ATTENDANCE_EOF__'
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
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/report.routes.ts' <<'__ATTENDANCE_EOF__'
import { Router } from 'express';
import type { Guards } from '../../core/auth/guards.js';
import type { ReportController } from './report.controller.js';

export function reportRoutes(controller: ReportController, guards: Guards): Router {
  const router = Router();
  router.use(guards.authenticate);
  router.get('/attendance', controller.attendance);
  router.get('/members/:id', controller.member);
  return router;
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/report.schemas.ts' <<'__ATTENDANCE_EOF__'
import { z } from 'zod';
import { localDateSchema, objectIdSchema } from '../../core/http/schemas.js';
import { REPORT_FORMATS } from './report.types.js';

/** Either a saved period (term, session…) or an explicit from/to range. */
export const attendanceReportQuerySchema = z
  .object({
    periodId: objectIdSchema.optional(),
    from: localDateSchema.optional(),
    to: localDateSchema.optional(),
    group: z.string().trim().min(1).max(60).optional(),
    format: z.enum(REPORT_FORMATS).default('json'),
  })
  .refine((query) => Boolean(query.periodId) !== Boolean(query.from && query.to), {
    message: 'provide either periodId, or both from and to',
  })
  .refine((query) => !query.from || !query.to || query.from <= query.to, {
    message: '"from" must be on or before "to"',
    path: ['to'],
  });

export const memberReportQuerySchema = z
  .object({ from: localDateSchema, to: localDateSchema })
  .refine((query) => query.from <= query.to, { message: '"from" must be on or before "to"', path: ['to'] });
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/report.service.ts' <<'__ATTENDANCE_EOF__'
import { ValidationError } from '../../core/errors/index.js';
import type { Clock } from '../../core/time/clock.js';
import { daysInclusive, eachDate, toLocalDate, type LocalDate } from '../../core/time/local-date.js';
import type { AttendanceRecordRow, AttendanceRepository } from '../attendance/attendance.repository.js';
import type { AttendancePolicy } from '../attendance/policies/index.js';
import { MAX_RANGE_DAYS } from '../calendar/calendar.schemas.js';
import type { CalendarService } from '../calendar/calendar.service.js';
import type { MemberRecord, MemberRepository } from '../members/member.repository.js';
import type { OrganizationService } from '../organizations/organization.service.js';
import type { AttendanceReport, DayMark, ReportLogEntry, ReportRow } from './report.types.js';

export interface ReportRequest {
  from: LocalDate;
  to: LocalDate;
  label?: string | null | undefined;
  group?: string | undefined;
  memberId?: string | undefined;
}

interface MarkContext {
  today: LocalDate;
  policy: AttendancePolicy;
  holidays: ReadonlySet<LocalDate>;
}

const rate = (attended: number, expected: number): number | null =>
  expected === 0 ? null : Math.round((attended / expected) * 1000) / 10;

/**
 * Builds the attendance matrix for a date range. Absences are derived here, never stored.
 * Three queries regardless of range size: members, records, holidays.
 */
export class ReportService {
  constructor(
    private readonly organizations: OrganizationService,
    private readonly calendar: CalendarService,
    private readonly members: MemberRepository,
    private readonly records: AttendanceRepository,
    private readonly clock: Clock,
  ) {}

  async build(orgId: string, request: ReportRequest): Promise<AttendanceReport> {
    const { from, to } = request;
    if (from > to) throw new ValidationError('"from" must be on or before "to"');
    if (daysInclusive(from, to) > MAX_RANGE_DAYS) {
      throw new ValidationError(`A report can span at most ${MAX_RANGE_DAYS} days`);
    }

    const { org, policy } = await this.organizations.getWithPolicy(orgId);
    const today = toLocalDate(this.clock.now(), org.timezone);

    const members = await this.members.activeDuring(orgId, from, to, {
      group: request.group,
      memberId: request.memberId,
    });

    const [records, holidayNames] = await Promise.all([
      this.records.between(orgId, from, to, request.memberId ? members.map((m) => m._id) : undefined),
      this.calendar.holidayDates(orgId, from, to),
    ]);

    const dates = eachDate(from, to);
    const context: MarkContext = { today, policy, holidays: new Set(holidayNames.keys()) };
    const recordsByMember = groupByMember(records);
    const rows = members.map((member) =>
      this.buildRow(member, dates, recordsByMember.get(member._id.toString()) ?? new Map(), context),
    );

    const memberById = new Map(members.map((member) => [member._id.toString(), member]));
    const log: ReportLogEntry[] = records.flatMap((record) => {
      const member = memberById.get(record.memberId.toString());
      return member
        ? [
            {
              date: record.date,
              memberId: member._id.toString(),
              fullName: member.fullName,
              code: member.code,
              status: record.status,
              checkInAt: record.checkInAt,
              checkOutAt: record.checkOutAt ?? null,
              method: record.method,
            },
          ]
        : [];
    });

    const sum = (key: 'expected' | 'present' | 'late' | 'attended' | 'absent') =>
      rows.reduce((total, row) => total + row[key], 0);
    const expected = sum('expected');
    const attended = sum('attended');

    return {
      organization: {
        id: org._id.toString(),
        name: org.name,
        slug: org.slug,
        type: org.type,
        timezone: org.timezone,
      },
      range: { from, to, label: request.label ?? null },
      generatedAt: this.clock.now(),
      dates,
      holidays: [...holidayNames].map(([date, name]) => ({ date, name })),
      rows,
      totals: {
        members: rows.length,
        expected,
        present: sum('present'),
        late: sum('late'),
        attended,
        absent: sum('absent'),
        attendanceRate: rate(attended, expected),
      },
      log,
    };
  }

  private buildRow(
    member: MemberRecord,
    dates: LocalDate[],
    records: ReadonlyMap<LocalDate, AttendanceRecordRow>,
    context: MarkContext,
  ): ReportRow {
    let expected = 0;
    let present = 0;
    let late = 0;
    let absent = 0;

    const marks = dates.map((date): DayMark => {
      const mark = this.markFor(member, date, records.get(date), context);
      const counts = context.policy.isExpectedDay(date, context.holidays) && mark !== '-';
      if (counts) {
        expected += 1;
        if (mark === 'P') present += 1;
        else if (mark === 'L') late += 1;
        else if (mark === 'A') absent += 1;
      }
      return mark;
    });

    return {
      memberId: member._id.toString(),
      fullName: member.fullName,
      code: member.code,
      group: member.group ?? null,
      status: member.status,
      marks,
      expected,
      present,
      late,
      attended: present + late,
      absent,
      attendanceRate: rate(present + late, expected),
    };
  }

  private markFor(
    member: MemberRecord,
    date: LocalDate,
    record: AttendanceRecordRow | undefined,
    { today, policy, holidays }: MarkContext,
  ): DayMark {
    if (date > today || date < member.joinedOn) return '-';
    if (member.archivedOn && date >= member.archivedOn) return record ? statusMark(record) : '-';
    if (record) return statusMark(record);
    if (holidays.has(date)) return 'H';
    if (!policy.isExpectedDay(date, holidays)) return 'W';
    // Today is still in progress: not checked in yet is not the same as absent.
    return date === today ? '-' : 'A';
  }
}

const statusMark = (record: AttendanceRecordRow): DayMark => (record.status === 'LATE' ? 'L' : 'P');

function groupByMember(records: AttendanceRecordRow[]): Map<string, Map<LocalDate, AttendanceRecordRow>> {
  const grouped = new Map<string, Map<LocalDate, AttendanceRecordRow>>();
  for (const record of records) {
    const key = record.memberId.toString();
    let byDate = grouped.get(key);
    if (!byDate) {
      byDate = new Map();
      grouped.set(key, byDate);
    }
    byDate.set(record.date, record);
  }
  return grouped;
}
__ATTENDANCE_EOF__

write 'apps/api/src/modules/reports/report.types.ts' <<'__ATTENDANCE_EOF__'
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
__ATTENDANCE_EOF__

write 'apps/api/src/scripts/seed.ts' <<'__ATTENDANCE_EOF__'
/**
 * Demo data for local development: a school with 24 students, a kiosk, a term and four weeks of attendance.
 * Usage (from the repo root):  npm run seed
 * Safe to re-run: it does nothing if the demo account already exists.
 */
import { toAppConfig } from '../config/app-config.js';
import { loadDotEnvFile, loadEnv } from '../config/env.js';
import { createContainer } from '../container.js';
import { connectDatabase, disconnectDatabase } from '../core/db/connect.js';
import { createLogger } from '../core/logger.js';
import { eachDate, toInstant, toLocalDate } from '../core/time/local-date.js';
import { AttendanceRecordModel } from '../modules/attendance/attendance-record.model.js';
import { createAttendancePolicy } from '../modules/attendance/policies/index.js';
import { UserModel } from '../modules/auth/user.model.js';
import { MemberModel } from '../modules/members/member.model.js';

const DEMO_EMAIL = 'demo@attendance.local';
const DEMO_PASSWORD = 'demo-password-123';
const TIMEZONE = 'Africa/Lagos';

const STUDENTS = [
  'Adaeze Okafor',
  'Babatunde Adeyemi',
  'Chiamaka Eze',
  'Damilola Bakare',
  'Emeka Nwosu',
  'Fatima Bello',
  'Gbenga Ogunleye',
  'Halima Yusuf',
  'Ifeoma Obi',
  'Jide Akinola',
  'Kemi Adebayo',
  'Lanre Coker',
  'Musa Abdullahi',
  'Nkechi Uche',
  'Olumide Fashola',
  'Precious Etim',
  'Quadri Lawal',
  'Rukayat Salami',
  'Segun Ojo',
  'Temitope Bello',
  'Uchenna Ibe',
  'Victoria Essien',
  'Wale Adeleke',
  'Zainab Garba',
];
const CLASSES = ['JSS 1', 'JSS 2', 'JSS 3'];

/** Small deterministic PRNG so every developer gets the same demo data. */
function mulberry32(seed: number): () => number {
  let state = seed;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

async function main(): Promise<void> {
  loadDotEnvFile();
  const env = loadEnv();
  const logger = createLogger('warn');
  await connectDatabase(env.MONGO_URI, logger);
  const { services } = createContainer(toAppConfig(env), { logger });

  if (await UserModel.exists({ email: DEMO_EMAIL })) {
    console.warn(`Demo data already exists. Log in with ${DEMO_EMAIL} / ${DEMO_PASSWORD}`);
    return;
  }

  const session = await services.auth.register(
    {
      organization: { name: 'Demo Academy', type: 'SCHOOL', timezone: TIMEZONE },
      user: { name: 'Demo Owner', email: DEMO_EMAIL, password: DEMO_PASSWORD },
    },
    { userAgent: 'seed-script' },
  );
  const orgId = session.profile.organization.id;

  const today = toLocalDate(new Date(), TIMEZONE);
  const start = toLocalDate(new Date(Date.now() - 28 * 86_400_000), TIMEZONE);

  await services.members.import(orgId, {
    members: STUDENTS.map((fullName, index) => ({
      fullName,
      group: CLASSES[index % CLASSES.length],
      joinedOn: start,
    })),
  });
  await services.calendar.createPeriod(orgId, { name: 'Demo term', type: 'TERM', startsOn: start, endsOn: today });
  const { token: kioskToken } = await services.kiosks.create(orgId, 'Front gate');

  // Four weeks of history: ~85% on time, ~8% late, the rest absent. Today is left for live check-ins.
  const policy = createAttendancePolicy(session.profile.organization.policy);
  const random = mulberry32(2026);
  const members = await MemberModel.find({ orgId }).lean().exec();
  const days = eachDate(start, today).filter((date) => date < today && policy.isExpectedDay(date, new Set()));

  const records = days.flatMap((date) =>
    members.flatMap((member) => {
      const roll = random();
      if (roll > 0.93) return [];
      const late = roll > 0.85;
      const minute = late ? 1 + Math.floor(random() * 29) : Math.floor(random() * 60);
      const time = late ? `08:${String(minute).padStart(2, '0')}` : `07:${String(minute).padStart(2, '0')}`;
      return [
        {
          orgId: member.orgId,
          memberId: member._id,
          date,
          checkInAt: toInstant(date, time, TIMEZONE),
          status: late ? 'LATE' : 'PRESENT',
          method: 'CODE',
        },
      ];
    }),
  );
  await AttendanceRecordModel.insertMany(records);

  console.warn(
    [
      '',
      'Demo data created',
      `  Dashboard login : ${DEMO_EMAIL} / ${DEMO_PASSWORD}`,
      `  Kiosk token     : ${kioskToken}`,
      `  Students        : ${members.length} (codes are listed in GET /api/v1/members)`,
      `  History         : ${records.length} check-ins over ${days.length} school days`,
      '',
    ].join('\n'),
  );
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => disconnectDatabase());
__ATTENDANCE_EOF__

write 'apps/api/src/server.ts' <<'__ATTENDANCE_EOF__'
import { toAppConfig } from './config/app-config.js';
import { loadDotEnvFile, loadEnv } from './config/env.js';
import { createApp } from './app.js';
import { createContainer } from './container.js';
import { connectDatabase, disconnectDatabase } from './core/db/connect.js';
import { createLogger } from './core/logger.js';

loadDotEnvFile();
const env = loadEnv();
const logger = createLogger(env.LOG_LEVEL, env.NODE_ENV === 'development');

process.on('unhandledRejection', (reason) => {
  logger.fatal({ err: reason }, 'Unhandled promise rejection');
  process.exit(1);
});

try {
  await connectDatabase(env.MONGO_URI, logger);
} catch (error) {
  logger.fatal(
    { reason: error instanceof Error ? error.message : String(error) },
    'Could not connect to MongoDB. Is it running, and is MONGO_URI in apps/api/.env correct?',
  );
  process.exit(1);
}

const app = createApp(createContainer(toAppConfig(env), { logger }));
const server = app.listen(env.PORT, () => {
  logger.info(`API listening on http://localhost:${env.PORT} (${env.NODE_ENV})`);
});

let shuttingDown = false;
async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info({ signal }, 'Shutting down');

  const forceExit = setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10_000);
  forceExit.unref();

  server.close(async () => {
    await disconnectDatabase();
    logger.info('Shutdown complete');
    process.exit(0);
  });
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
__ATTENDANCE_EOF__

write 'apps/api/src/types/express.d.ts' <<'__ATTENDANCE_EOF__'
import type { AuthContext, KioskContext } from '../core/auth/context.js';

declare global {
  namespace Express {
    interface Request {
      auth?: AuthContext;
      kiosk?: KioskContext;
    }
  }
}

export {};
__ATTENDANCE_EOF__

write 'apps/api/test/integration/auth.test.ts' <<'__ATTENDANCE_EOF__'
import jwt from 'jsonwebtoken';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  AJAX,
  bearer,
  buildTestApp,
  clearDatabase,
  connectTestDatabase,
  cookiesOf,
  disconnectTestDatabase,
  registerOrganization,
  TEST_CONFIG,
} from '../support/harness.js';

beforeAll(connectTestDatabase);
afterAll(disconnectTestDatabase);
beforeEach(clearDatabase);

describe('registration and login', () => {
  it('creates an organization, its owner and a session in one call', async () => {
    const { api } = buildTestApp();
    const res = await api()
      .post('/api/v1/auth/register')
      .send({
        organization: { name: 'Tenderville School', type: 'SCHOOL' },
        user: { name: 'Ada Owner', email: 'ADA@Example.com ', password: 'correct-horse-battery' },
      });

    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({
      accessToken: expect.any(String),
      expiresIn: 900,
      user: { name: 'Ada Owner', email: 'ada@example.com' },
      role: 'OWNER',
      organization: {
        name: 'Tenderville School',
        slug: 'tenderville-school',
        type: 'SCHOOL',
        timezone: 'Africa/Lagos',
        policy: {
          kind: 'FIXED_WINDOW',
          opensAt: '07:00',
          lateAfter: '08:00',
          closesAt: '08:30',
          workDays: [1, 2, 3, 4, 5],
        },
      },
    });

    // Refresh token is an httpOnly cookie scoped to the auth routes, never in the JSON body.
    const cookie = String(res.headers['set-cookie']);
    expect(cookie).toMatch(/att_rt=.+; Path=\/api\/v1\/auth; Expires=.+; HttpOnly; SameSite=Lax/);
    expect(JSON.stringify(res.body)).not.toContain('refreshToken');

    const me = await api().get('/api/v1/auth/me').set(bearer(res.body.data.accessToken));
    expect(me.status).toBe(200);
    expect(me.body.data.organizations).toHaveLength(1);
  });

  it('gives a second organization with the same name its own slug', async () => {
    const { app } = buildTestApp();
    await registerOrganization(app, { name: 'Bright Future' });
    const second = await registerOrganization(app, { name: 'Bright Future' });
    const { api } = buildTestApp();
    const me = await api().get('/api/v1/organization').set(bearer(second.token));
    expect(me.body.data.slug).toMatch(/^bright-future-[a-f0-9]{6}$/);
  });

  it('rejects a duplicate email with 409', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    const res = await api()
      .post('/api/v1/auth/register')
      .send({
        organization: { name: 'Another', type: 'COMPANY' },
        user: { name: 'X Y', email: org.email, password: 'whatever-123' },
      });
    expect(res.status).toBe(409);
  });

  it('validates input and reports every problem', async () => {
    const { api } = buildTestApp();
    const res = await api()
      .post('/api/v1/auth/register')
      .send({
        organization: { name: 'A', type: 'HOSPITAL', timezone: 'Mars/Base' },
        user: { email: 'nope', password: 'short' },
      });
    expect(res.status).toBe(400);
    const paths = res.body.error.details.map((issue: { path: string }) => issue.path);
    expect(paths).toEqual(
      expect.arrayContaining([
        'organization.name',
        'organization.type',
        'organization.timezone',
        'user.email',
        'user.password',
        'user.name',
      ]),
    );
  });

  it('logs in, and gives the same answer for a wrong password and an unknown email', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);

    const ok = await api().post('/api/v1/auth/login').send({ email: org.email, password: org.password });
    expect(ok.status).toBe(200);
    expect(ok.body.data.accessToken).toBeTruthy();

    const wrongPassword = await api().post('/api/v1/auth/login').send({ email: org.email, password: 'nope-nope-nope' });
    const unknownEmail = await api()
      .post('/api/v1/auth/login')
      .send({ email: 'ghost@example.com', password: 'nope-nope-nope' });
    expect(wrongPassword.status).toBe(401);
    expect(unknownEmail.status).toBe(401);
    expect(wrongPassword.body).toEqual(unknownEmail.body);
  });
});

describe('access tokens', () => {
  it('rejects missing, malformed and forged tokens', async () => {
    const { api } = buildTestApp();
    expect((await api().get('/api/v1/members')).status).toBe(401);
    expect((await api().get('/api/v1/members').set('Authorization', 'Bearer garbage')).status).toBe(401);
    const forged = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIiwib3JnIjoiMSIsInJvbGUiOiJPV05FUiJ9.c2lnbmF0dXJl';
    expect((await api().get('/api/v1/members').set(bearer(forged))).status).toBe(401);
  });

  it('reports expiry with a distinct reason so the web app knows to refresh', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    const me = await api().get('/api/v1/auth/me').set(bearer(org.token));
    const expired = jwt.sign({ org: org.orgId, role: 'OWNER' }, TEST_CONFIG.auth.jwtAccessSecret, {
      subject: me.body.data.user.id,
      issuer: 'attendance-api',
      audience: 'attendance-web',
      expiresIn: -10,
    });
    const res = await api().get('/api/v1/auth/me').set(bearer(expired));
    expect(res.status).toBe(401);
    expect(res.body.error.details).toEqual({ reason: 'TOKEN_EXPIRED' });
  });
});

describe('refresh-token rotation', () => {
  it('rotates the refresh token on every use', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);

    const first = await api().post('/api/v1/auth/refresh').set(AJAX).set('Cookie', org.cookies);
    expect(first.status).toBe(200);
    expect(first.body.data.accessToken).toBeTruthy();
    const rotated = cookiesOf(first);
    expect(rotated[0]).not.toEqual(org.cookies[0]);

    const second = await api().post('/api/v1/auth/refresh').set(AJAX).set('Cookie', rotated);
    expect(second.status).toBe(200);
  });

  it('treats replay of an old refresh token as theft and revokes every session', async () => {
    const { app, api, clock } = buildTestApp();
    const org = await registerOrganization(app);

    const legit = await api().post('/api/v1/auth/refresh').set(AJAX).set('Cookie', org.cookies);
    const legitCookies = cookiesOf(legit);

    clock.set(new Date(clock.now().getTime() + 60_000)); // well past the 30 s multi-tab grace window
    const replay = await api().post('/api/v1/auth/refresh').set(AJAX).set('Cookie', org.cookies);
    expect(replay.status).toBe(401);
    expect(replay.body.error.details.reason).toBe('SESSION_REVOKED');

    // The legitimate (newer) session was revoked too.
    const afterTheft = await api().post('/api/v1/auth/refresh').set(AJAX).set('Cookie', legitCookies);
    expect(afterTheft.status).toBe(401);
  });

  it('requires the X-Requested-With header (CSRF defence for cookie endpoints)', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    const res = await api().post('/api/v1/auth/refresh').set('Cookie', org.cookies);
    expect(res.status).toBe(403);
  });

  it('logout revokes the session and clears the cookie', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    const logout = await api().post('/api/v1/auth/logout').set(AJAX).set('Cookie', org.cookies);
    expect(logout.status).toBe(204);
    expect(String(logout.headers['set-cookie'])).toContain('att_rt=;');
    const refresh = await api().post('/api/v1/auth/refresh').set(AJAX).set('Cookie', org.cookies);
    expect(refresh.status).toBe(401);
  });
});

describe('team roles', () => {
  async function addTeammate(ownerToken: string, role: string) {
    const { api } = buildTestApp();
    const email = `${role.toLowerCase()}-${Math.random().toString(36).slice(2, 8)}@example.com`;
    const res = await api()
      .post('/api/v1/team')
      .set(bearer(ownerToken))
      .send({ email, role, name: 'Team Mate', temporaryPassword: 'temporary-pass-1' });
    expect(res.status, JSON.stringify(res.body)).toBe(201);
    const login = await api().post('/api/v1/auth/login').send({ email, password: 'temporary-pass-1' });
    return {
      userId: res.body.data.userId as string,
      token: login.body.data.accessToken as string,
      cookies: cookiesOf(login),
    };
  }

  it('lets a VIEWER read but not write', async () => {
    const { app, api } = buildTestApp();
    const owner = await registerOrganization(app);
    const viewer = await addTeammate(owner.token, 'VIEWER');

    expect((await api().get('/api/v1/members').set(bearer(viewer.token))).status).toBe(200);
    const write = await api().post('/api/v1/members').set(bearer(viewer.token)).send({ fullName: 'New Person' });
    expect(write.status).toBe(403);
    expect((await api().get('/api/v1/team').set(bearer(viewer.token))).status).toBe(403);
  });

  it('only owners can create owners', async () => {
    const { app, api } = buildTestApp();
    const owner = await registerOrganization(app);
    const admin = await addTeammate(owner.token, 'ADMIN');
    const res = await api()
      .post('/api/v1/team')
      .set(bearer(admin.token))
      .send({ email: 'boss@example.com', role: 'OWNER', name: 'Wannabe Boss', temporaryPassword: 'temporary-pass-1' });
    expect(res.status).toBe(403);
  });

  it('never leaves an organization without an owner', async () => {
    const { app, api } = buildTestApp();
    const owner = await registerOrganization(app);
    const me = await api().get('/api/v1/auth/me').set(bearer(owner.token));
    const demote = await api()
      .patch(`/api/v1/team/${me.body.data.user.id}`)
      .set(bearer(owner.token))
      .send({ role: 'ADMIN' });
    expect(demote.status).toBe(422);
  });

  it('removing a teammate ends their sessions', async () => {
    const { app, api } = buildTestApp();
    const owner = await registerOrganization(app);
    const admin = await addTeammate(owner.token, 'ADMIN');

    expect((await api().delete(`/api/v1/team/${admin.userId}`).set(bearer(owner.token))).status).toBe(204);
    const refresh = await api().post('/api/v1/auth/refresh').set(AJAX).set('Cookie', admin.cookies);
    expect(refresh.status).toBe(401);
  });
});

describe('HTTP edge cases', () => {
  it('returns JSON 404 for unknown API routes (no SPA fallback with 200)', async () => {
    const { api } = buildTestApp();
    const res = await api().get('/api/v1/does-not-exist');
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns 400 for malformed JSON', async () => {
    const { api } = buildTestApp();
    const res = await api().post('/api/v1/auth/login').set('Content-Type', 'application/json').send('{"email":');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('MALFORMED_JSON');
  });

  it('sets security headers and a request id', async () => {
    const { api } = buildTestApp();
    const res = await api().get('/api/health');
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['x-powered-by']).toBeUndefined();
    expect(res.headers['x-request-id']).toMatch(/^[\w-]+$/);
  });
});
__ATTENDANCE_EOF__

write 'apps/api/test/integration/check-in.test.ts' <<'__ATTENDANCE_EOF__'
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  bearer,
  buildTestApp,
  clearDatabase,
  connectTestDatabase,
  createKiosk,
  createMember,
  disconnectTestDatabase,
  kioskAuth,
  lagos,
  registerOrganization,
} from '../support/harness.js';

beforeAll(connectTestDatabase);
afterAll(disconnectTestDatabase);
beforeEach(clearDatabase);

const MONDAY = '2026-09-28';
const SATURDAY = '2026-10-03';

/** A school with one kiosk and one member, clock frozen at Monday 07:45 Lagos time. */
async function setupSchool() {
  const ctx = buildTestApp({ now: lagos(MONDAY, '07:45') });
  const org = await registerOrganization(ctx.app);
  const kiosk = await createKiosk(ctx.app, org.token);
  const member = await createMember(ctx.app, org.token, { fullName: 'Chidi Okeke', code: 'STF-001' });
  const checkIn = (body: object, token = kiosk.token) =>
    ctx.api().post('/api/v1/kiosk/check-in').set(kioskAuth(token)).send(body);
  return { ...ctx, org, kiosk, member, checkIn };
}

describe('kiosk authentication', () => {
  it('requires a kiosk token – an admin token is not enough', async () => {
    const { api, org } = await setupSchool();
    expect((await api().post('/api/v1/kiosk/check-in').send({ method: 'CODE', code: 'STF-001' })).status).toBe(401);
    const withAdminToken = await api()
      .post('/api/v1/kiosk/check-in')
      .set(bearer(org.token))
      .send({ method: 'CODE', code: 'STF-001' });
    expect(withAdminToken.status).toBe(401);
  });

  it('a kiosk token cannot reach admin endpoints', async () => {
    const { api, kiosk } = await setupSchool();
    expect((await api().get('/api/v1/members').set(kioskAuth(kiosk.token))).status).toBe(401);
    expect((await api().get('/api/v1/members').set(bearer(kiosk.token))).status).toBe(401);
  });

  it('revoking a kiosk locks the device out immediately', async () => {
    const { api, org, kiosk, checkIn } = await setupSchool();
    expect((await api().delete(`/api/v1/kiosks/${kiosk.id}`).set(bearer(org.token))).status).toBe(204);
    expect((await checkIn({ method: 'CODE', code: 'STF-001' })).status).toBe(401);
  });

  it('exposes what the kiosk screen needs and nothing more', async () => {
    const { api, kiosk } = await setupSchool();
    const res = await api().get('/api/v1/kiosk/session').set(kioskAuth(kiosk.token));
    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({
      kiosk: { name: 'Front gate' },
      organization: { name: 'Tenderville School', timezone: 'Africa/Lagos' },
      today: { date: MONDAY, time: '07:45', isWorkday: true, isHoliday: false },
      policy: { kind: 'FIXED_WINDOW', closesAt: '08:30' },
    });
    expect(JSON.stringify(res.body)).not.toContain('STF-001'); // no member codes on a public screen
  });
});

describe('check-in rules (regressions from v1)', () => {
  it('marks on-time arrivals PRESENT and returns only what the screen should show', async () => {
    const { checkIn } = await setupSchool();
    const res = await checkIn({ method: 'CODE', code: 'stf-001' }); // codes are case-insensitive
    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({ member: { fullName: 'Chidi Okeke' }, status: 'PRESENT', date: MONDAY });
    expect(res.body.data.member.code).toBeUndefined();
  });

  it('marks arrivals after lateAfter as LATE', async () => {
    const { clock, checkIn } = await setupSchool();
    clock.set(lagos(MONDAY, '08:15'));
    expect((await checkIn({ method: 'CODE', code: 'STF-001' })).body.data.status).toBe('LATE');
  });

  it('enforces the closing time (v1 accepted check-ins at any hour)', async () => {
    const { clock, checkIn } = await setupSchool();
    for (const time of ['08:31', '12:00', '22:15']) {
      clock.set(lagos(MONDAY, time));
      const res = await checkIn({ method: 'CODE', code: 'STF-001' });
      expect(res.status).toBe(422);
      expect(res.body.error.details.reason).toBe('WINDOW_CLOSED');
    }
    clock.set(lagos(MONDAY, '06:30'));
    expect((await checkIn({ method: 'CODE', code: 'STF-001' })).body.error.details.reason).toBe('TOO_EARLY');
  });

  it('uses the organisation timezone, not the server clock', async () => {
    const { clock, checkIn } = await setupSchool();
    // 06:45 UTC = 07:45 in Lagos → inside the window. A UTC server would wrongly call this 06:45 (too early).
    clock.set(new Date(`${MONDAY}T06:45:00Z`));
    expect((await checkIn({ method: 'CODE', code: 'STF-001' })).status).toBe(201);
  });

  it('rejects non-working days and holidays', async () => {
    const { api, clock, org, checkIn } = await setupSchool();
    clock.set(lagos(SATURDAY, '07:30'));
    expect((await checkIn({ method: 'CODE', code: 'STF-001' })).body.error.details.reason).toBe('NON_WORKDAY');

    await api().post('/api/v1/holidays').set(bearer(org.token)).send({ date: '2026-10-01', name: 'Independence Day' });
    clock.set(lagos('2026-10-01', '07:30'));
    expect((await checkIn({ method: 'CODE', code: 'STF-001' })).body.error.details.reason).toBe('HOLIDAY');
  });

  it('allows one check-in per member per day', async () => {
    const { checkIn } = await setupSchool();
    expect((await checkIn({ method: 'CODE', code: 'STF-001' })).status).toBe(201);
    const again = await checkIn({ method: 'CODE', code: 'STF-001' });
    expect(again.status).toBe(409);
    expect(again.body.error.details.reason).toBe('ALREADY_CHECKED_IN');
  });

  it('holds under concurrent double-taps (v1 had a check-then-insert race)', async () => {
    const { checkIn } = await setupSchool();
    const results = await Promise.all(Array.from({ length: 8 }, () => checkIn({ method: 'CODE', code: 'STF-001' })));
    const statuses = results.map((res) => res.status).sort();
    expect(statuses.filter((status) => status === 201)).toHaveLength(1);
    expect(statuses.filter((status) => status === 409)).toHaveLength(7);
  });

  it('rejects NoSQL operator injection with 400 (v1 checked in a random person)', async () => {
    const { checkIn } = await setupSchool();
    for (const code of [{ $ne: null }, { $regex: '.*' }, { $gt: '' }]) {
      const res = await checkIn({ method: 'CODE', code });
      expect(res.status).toBe(400);
    }
  });

  it('keeps tenants apart even when two organisations use the same code (v1 crossed tenants)', async () => {
    const { app, api, checkIn, org: schoolA } = await setupSchool();
    const schoolB = await registerOrganization(app, { name: 'Other School' });
    const kioskB = await createKiosk(app, schoolB.token);
    await createMember(app, schoolB.token, { fullName: 'Bisi Adeyemi', code: 'STF-001' });

    const inA = await checkIn({ method: 'CODE', code: 'STF-001' });
    const inB = await checkIn({ method: 'CODE', code: 'STF-001' }, kioskB.token);
    expect(inA.body.data.member.fullName).toBe('Chidi Okeke');
    expect(inB.body.data.member.fullName).toBe('Bisi Adeyemi');

    const dailyA = await api().get('/api/v1/attendance/daily').set(bearer(schoolA.token));
    expect(dailyA.body.data.rows.map((row: { member: { fullName: string } }) => row.member.fullName)).toEqual([
      'Chidi Okeke',
    ]);
  });

  it('gives one generic answer for unknown codes and wrong PINs', async () => {
    const { app, org, checkIn } = await setupSchool();
    await createMember(app, org.token, { fullName: 'Pin Person', code: 'PIN-007', pin: '4821' });

    const unknown = await checkIn({ method: 'CODE', code: 'NOPE-999' });
    const missingPin = await checkIn({ method: 'CODE', code: 'PIN-007' });
    const wrongPin = await checkIn({ method: 'CODE', code: 'PIN-007', pin: '0000' });
    for (const res of [unknown, missingPin, wrongPin]) {
      expect(res.status).toBe(422);
      expect(res.body.error).toEqual(unknown.body.error);
    }
    expect((await checkIn({ method: 'CODE', code: 'PIN-007', pin: '4821' })).status).toBe(201);
  });

  it('archived members cannot check in', async () => {
    const { api, org, member, checkIn } = await setupSchool();
    await api().delete(`/api/v1/members/${member.id}`).set(bearer(org.token));
    expect((await checkIn({ method: 'CODE', code: 'STF-001' })).body.error.details.reason).toBe('INVALID_CREDENTIALS');
  });
});

describe('QR check-in', () => {
  it('accepts the current QR token and rejects a rotated one', async () => {
    const { api, org, member, clock, checkIn } = await setupSchool();
    const first = await api().post(`/api/v1/members/${member.id}/qr-token`).set(bearer(org.token));
    expect(first.body.data.qrToken).toMatch(/^qr_/);
    const second = await api().post(`/api/v1/members/${member.id}/qr-token`).set(bearer(org.token));

    expect((await checkIn({ method: 'QR', token: first.body.data.qrToken })).status).toBe(422);
    expect((await checkIn({ method: 'QR', token: second.body.data.qrToken })).status).toBe(201);

    clock.set(lagos('2026-09-29', '07:30'));
    expect((await checkIn({ method: 'QR', token: 'qr_not-a-real-token-at-all-xx' })).status).toBe(422);
  });
});

describe('check-out', () => {
  it('is disabled by default for schools', async () => {
    const { api, kiosk } = await setupSchool();
    const res = await api()
      .post('/api/v1/kiosk/check-out')
      .set(kioskAuth(kiosk.token))
      .send({ method: 'CODE', code: 'STF-001' });
    expect(res.status).toBe(422);
    expect(res.body.error.details.reason).toBe('CHECK_OUT_DISABLED');
  });

  it('works for companies: once, and only after checking in', async () => {
    const { app, api, clock } = buildTestApp({ now: lagos(MONDAY, '08:55') });
    const org = await registerOrganization(app, { type: 'COMPANY', name: 'Acme Ltd' });
    const kiosk = await createKiosk(app, org.token, 'Reception');
    await createMember(app, org.token, { fullName: 'Tunde Bello', code: 'EMP-42' });
    const post = (path: string) =>
      api().post(`/api/v1/kiosk/${path}`).set(kioskAuth(kiosk.token)).send({ method: 'CODE', code: 'EMP-42' });

    expect((await post('check-out')).body.error.details.reason).toBe('NOT_CHECKED_IN');
    expect((await post('check-in')).status).toBe(201);
    clock.set(lagos(MONDAY, '17:30'));
    const out = await post('check-out');
    expect(out.status).toBe(200);
    expect(new Date(out.body.data.checkOutAt).toISOString()).toBe(lagos(MONDAY, '17:30').toISOString());
    expect((await post('check-out')).status).toBe(409);
  });
});

describe('brute-force protection', () => {
  it('locks a kiosk after repeated failed check-ins, without counting successes', async () => {
    const { app, api } = buildTestApp({ now: lagos(MONDAY, '07:45'), rateLimiting: true });
    const org = await registerOrganization(app);
    const kiosk = await createKiosk(app, org.token);
    await createMember(app, org.token, { fullName: 'Real Person', code: 'REAL-01' });
    const attempt = (code: string) =>
      api().post('/api/v1/kiosk/check-in').set(kioskAuth(kiosk.token)).send({ method: 'CODE', code });

    expect((await attempt('REAL-01')).status).toBe(201);
    for (let i = 0; i < 15; i += 1) expect((await attempt(`GUESS-${i}`)).status).toBe(422);
    const blocked = await attempt('GUESS-99');
    expect(blocked.status).toBe(429);
    expect(blocked.body.error.code).toBe('TOO_MANY_REQUESTS');
  });
});
__ATTENDANCE_EOF__

write 'apps/api/test/integration/members.test.ts' <<'__ATTENDANCE_EOF__'
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  bearer,
  buildTestApp,
  clearDatabase,
  connectTestDatabase,
  createMember,
  disconnectTestDatabase,
  registerOrganization,
} from '../support/harness.js';

beforeAll(connectTestDatabase);
afterAll(disconnectTestDatabase);
beforeEach(clearDatabase);

describe('members', () => {
  it('generates a random 6-digit code when none is given and never exposes secrets', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    const res = await api()
      .post('/api/v1/members')
      .set(bearer(org.token))
      .send({ fullName: 'Ngozi Eze', pin: '1234', group: 'JSS 2' });

    expect(res.status).toBe(201);
    expect(res.body.data).toMatchObject({
      fullName: 'Ngozi Eze',
      code: expect.stringMatching(/^\d{6}$/),
      group: 'JSS 2',
      status: 'ACTIVE',
      joinedOn: '2026-09-28',
      pinSet: true,
    });
    const raw = JSON.stringify(res.body);
    expect(raw).not.toContain('pinHash');
    expect(raw).not.toContain('1234');
  });

  it('allows two people with the same name (v1 forbade it) but not the same code', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    await createMember(app, org.token, { fullName: 'Aisha Bello', code: 'A-100' });
    await createMember(app, org.token, { fullName: 'Aisha Bello', code: 'A-101' });

    const duplicate = await api()
      .post('/api/v1/members')
      .set(bearer(org.token))
      .send({ fullName: 'Someone', code: 'a-100' });
    expect(duplicate.status).toBe(409);
  });

  it('isolates tenants: another organisation cannot read, edit or archive your members', async () => {
    const { app, api } = buildTestApp();
    const orgA = await registerOrganization(app, { name: 'School A' });
    const orgB = await registerOrganization(app, { name: 'School B' });
    const member = await createMember(app, orgA.token, { fullName: 'Private Person', code: 'P-001' });

    expect((await api().get(`/api/v1/members/${member.id}`).set(bearer(orgB.token))).status).toBe(404);
    expect(
      (await api().patch(`/api/v1/members/${member.id}`).set(bearer(orgB.token)).send({ fullName: 'Hacked' })).status,
    ).toBe(404);
    expect((await api().delete(`/api/v1/members/${member.id}`).set(bearer(orgB.token))).status).toBe(404);
    const listB = await api().get('/api/v1/members').set(bearer(orgB.token));
    expect(listB.body.data).toEqual([]);

    // Codes are unique per organisation, so B may reuse A's code without learning anything about A.
    expect(
      (await api().post('/api/v1/members').set(bearer(orgB.token)).send({ fullName: 'Other', code: 'P-001' })).status,
    ).toBe(201);
  });

  it('renaming keeps attendance history attached (v1 linked attendance by name)', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    const kiosk = await api().post('/api/v1/kiosks').set(bearer(org.token)).send({ name: 'Gate' });
    const member = await createMember(app, org.token, { fullName: 'Old Name', code: 'REN-01' });
    await api()
      .post('/api/v1/kiosk/check-in')
      .set('Authorization', `Kiosk ${kiosk.body.data.token}`)
      .send({ method: 'CODE', code: 'REN-01' });

    await api().patch(`/api/v1/members/${member.id}`).set(bearer(org.token)).send({ fullName: 'New Name' });
    const daily = await api().get('/api/v1/attendance/daily').set(bearer(org.token));
    expect(daily.body.data.rows).toEqual([
      expect.objectContaining({ member: expect.objectContaining({ fullName: 'New Name' }), status: 'PRESENT' }),
    ]);
  });

  it('archives instead of deleting, and can restore', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    const member = await createMember(app, org.token, { fullName: 'Leaving Soon' });

    const archived = await api().delete(`/api/v1/members/${member.id}`).set(bearer(org.token));
    expect(archived.body.data).toMatchObject({ status: 'ARCHIVED', archivedOn: '2026-09-28' });
    expect((await api().get('/api/v1/members').set(bearer(org.token))).body.data).toHaveLength(0);
    expect((await api().get('/api/v1/members?status=ALL').set(bearer(org.token))).body.data).toHaveLength(1);

    const restored = await api()
      .patch(`/api/v1/members/${member.id}`)
      .set(bearer(org.token))
      .send({ status: 'ACTIVE' });
    expect(restored.body.data).toMatchObject({ status: 'ACTIVE', archivedOn: null });
  });

  it('sets and clears PINs and groups', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    const member = await createMember(app, org.token, { fullName: 'Pin Changer', group: 'Ops' });
    const withPin = await api().patch(`/api/v1/members/${member.id}`).set(bearer(org.token)).send({ pin: '9876' });
    expect(withPin.body.data.pinSet).toBe(true);
    const cleared = await api()
      .patch(`/api/v1/members/${member.id}`)
      .set(bearer(org.token))
      .send({ pin: null, group: null });
    expect(cleared.body.data).toMatchObject({ pinSet: false, group: null });
  });

  it('searches safely, filters by group and paginates', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    for (const [index, name] of ['Amaka', 'Bola', 'Chuka', 'Dayo', 'Efe'].entries()) {
      await createMember(app, org.token, { fullName: `${name} Test`, group: index % 2 === 0 ? 'Red' : 'Blue' });
    }

    const page = await api().get('/api/v1/members?limit=2&page=2').set(bearer(org.token));
    expect(page.body.data.map((m: { fullName: string }) => m.fullName)).toEqual(['Chuka Test', 'Dayo Test']);
    expect(page.body.meta).toEqual({ page: 2, limit: 2, total: 5, totalPages: 3 });

    const search = await api().get('/api/v1/members?search=bola').set(bearer(org.token));
    expect(search.body.data).toHaveLength(1);

    const regexChars = await api().get('/api/v1/members?search=.*(').set(bearer(org.token));
    expect(regexChars.status).toBe(200);
    expect(regexChars.body.data).toHaveLength(0);

    const red = await api().get('/api/v1/members?group=Red').set(bearer(org.token));
    expect(red.body.meta.total).toBe(3);
    expect((await api().get('/api/v1/members/groups').set(bearer(org.token))).body.data).toEqual(['Blue', 'Red']);
  });

  it('bulk-imports, generating codes and reporting rows it skipped', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    await createMember(app, org.token, { fullName: 'Existing', code: 'TAKEN-1' });

    const res = await api()
      .post('/api/v1/members/import')
      .set(bearer(org.token))
      .send({
        members: [
          { fullName: 'Row One', group: 'SS1' },
          { fullName: 'Row Two', code: 'TAKEN-1' },
          { fullName: 'Row Three', code: 'NEW-1' },
          { fullName: 'Row Four', code: 'new-1' },
          { fullName: 'Row Five' },
        ],
      });

    expect(res.status).toBe(201);
    expect(res.body.data.created).toBe(3);
    expect(res.body.data.skipped).toEqual([
      { row: 2, fullName: 'Row Two', reason: 'Code TAKEN-1 already exists' },
      { row: 4, fullName: 'Row Four', reason: 'Code NEW-1 appears twice in the file' },
    ]);
    const all = await api().get('/api/v1/members?limit=10').set(bearer(org.token));
    expect(all.body.meta.total).toBe(4);
  });

  it('rejects malformed ids and unknown fields cleanly', async () => {
    const { app, api } = buildTestApp();
    const org = await registerOrganization(app);
    expect((await api().get('/api/v1/members/not-an-id').set(bearer(org.token))).status).toBe(400);
    expect((await api().get('/api/v1/members/507f1f77bcf86cd799439011').set(bearer(org.token))).status).toBe(404);
    expect(
      (
        await api()
          .post('/api/v1/members')
          .set(bearer(org.token))
          .send({ fullName: { $gt: '' } })
      ).status,
    ).toBe(400);
  });
});
__ATTENDANCE_EOF__

write 'apps/api/test/integration/reports.test.ts' <<'__ATTENDANCE_EOF__'
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  bearer,
  binaryParser,
  buildTestApp,
  clearDatabase,
  connectTestDatabase,
  createMember,
  disconnectTestDatabase,
  lagos,
  loadWorkbook,
  registerOrganization,
} from '../support/harness.js';

beforeAll(connectTestDatabase);
afterAll(disconnectTestDatabase);
beforeEach(clearDatabase);

/**
 * Week of Mon 14 – Sun 20 Sept 2026, school policy (Mon–Fri), Wednesday 16th is a holiday.
 *   Ada   joined 1 Sept : P P H P P W W → expected 4, present 4            → 100%
 *   Bayo  joined 1 Sept : L A H P A W W → expected 4, present 1, late 1     → 50%
 *   Chioma joined Thu 17: - - - P A W W → expected 2, present 1, absent 1   → 50%
 * "Today" is Mon 21 Sept, after the range.
 */
async function seedWeek() {
  const ctx = buildTestApp({ now: lagos('2026-09-21', '10:00') });
  const org = await registerOrganization(ctx.app);
  const auth = bearer(org.token);

  const ada = await createMember(ctx.app, org.token, {
    fullName: 'Ada Obi',
    code: 'ADA-1',
    joinedOn: '2026-09-01',
    group: 'JSS1',
  });
  const bayo = await createMember(ctx.app, org.token, {
    fullName: 'Bayo Ade',
    code: 'BAY-1',
    joinedOn: '2026-09-01',
    group: 'JSS2',
  });
  const chioma = await createMember(ctx.app, org.token, {
    fullName: 'Chioma Nwosu',
    code: 'CHI-1',
    joinedOn: '2026-09-17',
    group: 'JSS1',
  });

  expect(
    (await ctx.api().post('/api/v1/holidays').set(auth).send({ date: '2026-09-16', name: 'Mid-term break' })).status,
  ).toBe(201);

  const mark = async (memberId: string, date: string, status: 'PRESENT' | 'LATE', time?: string) => {
    const res = await ctx.api().post('/api/v1/attendance/manual').set(auth).send({ memberId, date, status, time });
    expect(res.status, JSON.stringify(res.body)).toBe(201);
  };
  for (const date of ['2026-09-14', '2026-09-15', '2026-09-17', '2026-09-18'])
    await mark(ada.id, date, 'PRESENT', '07:40');
  await mark(bayo.id, '2026-09-14', 'LATE', '08:10');
  await mark(bayo.id, '2026-09-17', 'PRESENT');
  await mark(chioma.id, '2026-09-17', 'PRESENT');

  return { ...ctx, org, auth, ada, bayo, chioma };
}

describe('daily view', () => {
  it('derives absences and leaves out people who had not joined yet', async () => {
    const { api, auth } = await seedWeek();
    const res = await api().get('/api/v1/attendance/daily?date=2026-09-15').set(auth);
    expect(res.status).toBe(200);
    expect(res.body.data.totals).toEqual({ expected: 2, present: 1, late: 0, absent: 1, notCheckedIn: 0 });
    expect(
      res.body.data.rows.map((row: { member: { fullName: string }; status: string }) => [
        row.member.fullName,
        row.status,
      ]),
    ).toEqual([
      ['Ada Obi', 'PRESENT'],
      ['Bayo Ade', 'ABSENT'],
    ]);
  });

  it('shows holidays as holidays, and today as "not checked in" rather than absent', async () => {
    const { api, auth } = await seedWeek();
    const holiday = await api().get('/api/v1/attendance/daily?date=2026-09-16').set(auth);
    expect(holiday.body.data.holiday).toBe('Mid-term break');
    expect(new Set(holiday.body.data.rows.map((row: { status: string }) => row.status))).toEqual(new Set(['HOLIDAY']));

    const today = await api().get('/api/v1/attendance/daily').set(auth);
    expect(today.body.data).toMatchObject({ date: '2026-09-21', isToday: true });
    expect(today.body.data.totals.notCheckedIn).toBe(3);
    expect(today.body.data.totals.absent).toBe(0);
  });

  it('refuses future dates', async () => {
    const { api, auth } = await seedWeek();
    expect((await api().get('/api/v1/attendance/daily?date=2026-09-22').set(auth)).status).toBe(400);
  });
});

describe('attendance report (JSON)', () => {
  it('computes expected days, absences and rates per member and in total', async () => {
    const { api, auth } = await seedWeek();
    const res = await api().get('/api/v1/reports/attendance?from=2026-09-14&to=2026-09-20').set(auth);
    expect(res.status).toBe(200);
    const report = res.body.data;

    expect(report.dates).toHaveLength(7);
    expect(report.holidays).toEqual([{ date: '2026-09-16', name: 'Mid-term break' }]);

    const byName = Object.fromEntries(report.rows.map((row: { fullName: string }) => [row.fullName, row]));
    expect(byName['Ada Obi']).toMatchObject({
      marks: ['P', 'P', 'H', 'P', 'P', 'W', 'W'],
      expected: 4,
      present: 4,
      late: 0,
      absent: 0,
      attendanceRate: 100,
    });
    expect(byName['Bayo Ade']).toMatchObject({
      marks: ['L', 'A', 'H', 'P', 'A', 'W', 'W'],
      expected: 4,
      present: 1,
      late: 1,
      absent: 2,
      attendanceRate: 50,
    });
    expect(byName['Chioma Nwosu']).toMatchObject({
      marks: ['-', '-', '-', 'P', 'A', 'W', 'W'],
      expected: 2,
      present: 1,
      absent: 1,
      attendanceRate: 50,
    });

    expect(report.totals).toEqual({
      members: 3,
      expected: 10,
      present: 6,
      late: 1,
      attended: 7,
      absent: 3,
      attendanceRate: 70,
    });
    expect(report.log).toHaveLength(7);
  });

  it('filters by group', async () => {
    const { api, auth } = await seedWeek();
    const res = await api().get('/api/v1/reports/attendance?from=2026-09-14&to=2026-09-20&group=JSS1').set(auth);
    expect(res.body.data.rows.map((row: { fullName: string }) => row.fullName)).toEqual(['Ada Obi', 'Chioma Nwosu']);
  });

  it('reports by saved period (term / session) and labels the range', async () => {
    const { api, auth } = await seedWeek();
    const period = await api()
      .post('/api/v1/periods')
      .set(auth)
      .send({ name: '1st Term 2026/27', type: 'TERM', startsOn: '2026-09-14', endsOn: '2026-12-18' });
    expect(period.status).toBe(201);

    const res = await api().get(`/api/v1/reports/attendance?periodId=${period.body.data.id}`).set(auth);
    expect(res.body.data.range).toEqual({ from: '2026-09-14', to: '2026-12-18', label: '1st Term 2026/27' });
    // Days after "today" are not counted, so the term-to-date numbers match the week above plus Monday 21st (in progress).
    expect(res.body.data.totals.expected).toBe(10);
  });

  it('keeps archived members in reports for the days they were active', async () => {
    const { api, auth, bayo } = await seedWeek();
    await api().delete(`/api/v1/members/${bayo.id}`).set(auth); // archived today (21st)
    const res = await api().get('/api/v1/reports/attendance?from=2026-09-14&to=2026-09-20').set(auth);
    expect(res.body.data.rows.find((row: { fullName: string }) => row.fullName === 'Bayo Ade')).toMatchObject({
      status: 'ARCHIVED',
      expected: 4,
    });
  });

  it('validates the query', async () => {
    const { api, auth } = await seedWeek();
    expect((await api().get('/api/v1/reports/attendance').set(auth)).status).toBe(400);
    expect((await api().get('/api/v1/reports/attendance?from=2026-09-20&to=2026-09-14').set(auth)).status).toBe(400);
    expect((await api().get('/api/v1/reports/attendance?from=2025-01-01&to=2026-09-20').set(auth)).status).toBe(400);
    expect(
      (await api().get('/api/v1/reports/attendance?from=2026-09-14&to=2026-09-20&format=pdf').set(auth)).status,
    ).toBe(400);
  });

  it("returns one member's history", async () => {
    const { api, auth, bayo } = await seedWeek();
    const res = await api().get(`/api/v1/reports/members/${bayo.id}?from=2026-09-14&to=2026-09-20`).set(auth);
    expect(res.status).toBe(200);
    expect(res.body.data.summary).toMatchObject({ fullName: 'Bayo Ade', absent: 2, attendanceRate: 50 });
    expect(res.body.data.log).toHaveLength(2);
  });
});

describe('attendance report downloads', () => {
  it('streams an Excel workbook (the feature v1 promised but never shipped)', async () => {
    const { api, auth } = await seedWeek();
    const res = await api()
      .get('/api/v1/reports/attendance?from=2026-09-14&to=2026-09-20&format=xlsx')
      .set(auth)
      .buffer(true)
      .parse(binaryParser);

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toBe('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    expect(res.headers['content-disposition']).toBe(
      'attachment; filename="attendance_tenderville-school_2026-09-14_to_2026-09-20.xlsx"',
    );

    const workbook = await loadWorkbook(res.body as Buffer);
    const summary = workbook.getWorksheet('Summary')!;
    const rows = new Map<string, unknown[]>();
    summary.eachRow((row) => {
      const values = (row.values as unknown[]).slice(1);
      if (typeof values[0] === 'string') rows.set(values[0], values);
    });
    expect(rows.get('Bayo Ade')).toEqual(['Bayo Ade', 'BAY-1', 'JSS2', 4, 1, 1, 2, 0.5]);
    expect(rows.get('TOTAL')?.[7]).toBe(0.7);
    expect(workbook.getWorksheet('Check-in log')!.rowCount).toBe(8); // header + 7 records
  });

  it('exports CSV', async () => {
    const { api, auth } = await seedWeek();
    const res = await api().get('/api/v1/reports/attendance?from=2026-09-14&to=2026-09-20&format=csv').set(auth);
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('text/csv');
    const lines = res.text.replace('\uFEFF', '').trim().split('\r\n');
    expect(lines).toHaveLength(4);
    expect(lines[1]).toBe('Ada Obi,ADA-1,JSS1,4,4,0,0,100,P,P,H,P,P,W,W');
  });
});

describe('manual corrections', () => {
  it('admins can correct a record; viewers cannot', async () => {
    const { api, auth, bayo } = await seedWeek();
    const corrected = await api()
      .post('/api/v1/attendance/manual')
      .set(auth)
      .send({ memberId: bayo.id, date: '2026-09-15', status: 'PRESENT', note: 'Was on an excursion' });
    expect(corrected.body.data).toMatchObject({ status: 'PRESENT', method: 'MANUAL', note: 'Was on an excursion' });

    const del = await api().delete(`/api/v1/attendance/${corrected.body.data.id}`).set(auth);
    expect(del.status).toBe(204);

    const team = await api()
      .post('/api/v1/team')
      .set(auth)
      .send({ email: 'viewer@example.com', role: 'VIEWER', name: 'View Only', temporaryPassword: 'temporary-pass-1' });
    expect(team.status).toBe(201);
    const viewer = await api()
      .post('/api/v1/auth/login')
      .send({ email: 'viewer@example.com', password: 'temporary-pass-1' });
    const viewerAuth = bearer(viewer.body.data.accessToken);
    expect((await api().get('/api/v1/reports/attendance?from=2026-09-14&to=2026-09-20').set(viewerAuth)).status).toBe(
      200,
    );
    expect(
      (
        await api()
          .post('/api/v1/attendance/manual')
          .set(viewerAuth)
          .send({ memberId: bayo.id, date: '2026-09-15', status: 'PRESENT' })
      ).status,
    ).toBe(403);
  });

  it('refuses future dates and unknown members', async () => {
    const { api, auth, ada } = await seedWeek();
    expect(
      (
        await api()
          .post('/api/v1/attendance/manual')
          .set(auth)
          .send({ memberId: ada.id, date: '2026-09-25', status: 'PRESENT' })
      ).status,
    ).toBe(400);
    expect(
      (
        await api()
          .post('/api/v1/attendance/manual')
          .set(auth)
          .send({ memberId: '507f1f77bcf86cd799439011', date: '2026-09-15', status: 'PRESENT' })
      ).status,
    ).toBe(404);
  });
});

describe('organization settings', () => {
  it('admins can change the attendance policy, and it applies immediately', async () => {
    const { api, auth } = await seedWeek();
    const update = await api()
      .put('/api/v1/organization/policy')
      .set(auth)
      .send({
        kind: 'FLEXIBLE_HOURS',
        workDays: [1, 2, 3, 4, 5, 6],
        opensAt: '06:30',
        lateAfter: '09:00',
        allowCheckOut: true,
      });
    expect(update.status).toBe(200);
    expect(update.body.data.policy).toEqual({
      kind: 'FLEXIBLE_HOURS',
      workDays: [1, 2, 3, 4, 5, 6],
      opensAt: '06:30',
      lateAfter: '09:00',
      allowCheckOut: true,
    });

    // Saturdays are now work days, so Saturday the 19th counts as an absence for everyone who had joined.
    const report = await api().get('/api/v1/reports/attendance?from=2026-09-19&to=2026-09-19').set(auth);
    expect(report.body.data.totals).toMatchObject({ expected: 3, absent: 3 });
  });

  it('validates timezone changes', async () => {
    const { api, auth } = await seedWeek();
    expect((await api().patch('/api/v1/organization').set(auth).send({ timezone: 'Nowhere/Land' })).status).toBe(400);
    const ok = await api()
      .patch('/api/v1/organization')
      .set(auth)
      .send({ timezone: 'Africa/Accra', name: 'Tenderville Intl' });
    expect(ok.body.data).toMatchObject({ timezone: 'Africa/Accra', name: 'Tenderville Intl' });
  });
});
__ATTENDANCE_EOF__

write 'apps/api/test/support/global-setup.ts' <<'__ATTENDANCE_EOF__'
import type { TestProject } from 'vitest/node';

declare module 'vitest' {
  export interface ProvidedContext {
    mongoUri: string;
  }
}

/**
 * Starts one in-memory MongoDB for the whole run. Each test file then uses its own database on it.
 * Set MONGO_TEST_URI to run against an existing server instead (CI service container, local mongod…).
 */
export default async function setup(project: TestProject) {
  const external = process.env.MONGO_TEST_URI;
  if (external) {
    project.provide('mongoUri', external);
    return undefined;
  }

  const { MongoMemoryServer } = await import('mongodb-memory-server');
  const server = await MongoMemoryServer.create();
  project.provide('mongoUri', server.getUri());
  return async () => {
    await server.stop();
  };
}
__ATTENDANCE_EOF__

write 'apps/api/test/support/harness.ts' <<'__ATTENDANCE_EOF__'
import ExcelJS from 'exceljs';
import { randomUUID } from 'node:crypto';
import mongoose from 'mongoose';
import request from 'supertest';
import { expect, inject } from 'vitest';
import { createApp } from '../../src/app.js';
import type { AppConfig } from '../../src/config/app-config.js';
import { createContainer } from '../../src/container.js';
import { ensureIndexes } from '../../src/core/db/connect.js';
import { createLogger } from '../../src/core/logger.js';
import { FixedClock } from '../../src/core/time/clock.js';
import { toInstant } from '../../src/core/time/local-date.js';

export const TIMEZONE = 'Africa/Lagos';

export const TEST_CONFIG: AppConfig = {
  isProduction: false,
  corsOrigins: ['http://localhost:5173'],
  trustProxy: 0,
  auth: {
    jwtAccessSecret: 'test-secret-that-is-definitely-longer-than-32-chars',
    accessTokenTtlSeconds: 900,
    refreshTokenTtlDays: 30,
    bcryptRounds: 4, // fast hashing in tests only
  },
  cookie: { secure: false, sameSite: 'lax' },
};

/** Wall-clock time in Lagos → absolute instant. */
export const lagos = (date: string, time: string): Date => toInstant(date, time, TIMEZONE);

/** Each test file gets its own throw-away database. */
export async function connectTestDatabase(): Promise<void> {
  await mongoose.connect(inject('mongoUri'), { dbName: `attendance_test_${randomUUID().slice(0, 8)}` });
  await ensureIndexes();
}

export async function disconnectTestDatabase(): Promise<void> {
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
}

export async function clearDatabase(): Promise<void> {
  await Promise.all(Object.values(mongoose.connection.collections).map((collection) => collection.deleteMany({})));
}

export function buildTestApp(options: { now?: Date; rateLimiting?: boolean } = {}) {
  const clock = new FixedClock(options.now ?? lagos('2026-09-28', '07:45')); // a Monday
  const container = createContainer(TEST_CONFIG, {
    logger: createLogger(process.env.TEST_LOG_LEVEL ?? 'silent'),
    clock,
    rateLimiting: options.rateLimiting ?? false,
  });
  const app = createApp(container);
  return { app, clock, container, api: () => request(app) };
}

export type TestApp = ReturnType<typeof buildTestApp>['app'];

export const bearer = (token: string) => ({ Authorization: `Bearer ${token}` });
export const kioskAuth = (token: string) => ({ Authorization: `Kiosk ${token}` });
export const AJAX = { 'X-Requested-With': 'XMLHttpRequest' };

export interface RegisteredOrg {
  token: string;
  orgId: string;
  email: string;
  password: string;
  cookies: string[];
}

export async function registerOrganization(
  app: TestApp,
  options: { type?: 'SCHOOL' | 'COMPANY'; name?: string; email?: string } = {},
): Promise<RegisteredOrg> {
  const email = options.email ?? `owner-${randomUUID().slice(0, 8)}@example.com`;
  const password = 'correct-horse-battery';
  const res = await request(app)
    .post('/api/v1/auth/register')
    .send({
      organization: { name: options.name ?? 'Tenderville School', type: options.type ?? 'SCHOOL' },
      user: { name: 'Ada Owner', email, password },
    });
  expect(res.status, JSON.stringify(res.body)).toBe(201);
  return {
    token: res.body.data.accessToken,
    orgId: res.body.data.organization.id,
    email,
    password,
    cookies: cookiesOf(res),
  };
}

export function cookiesOf(res: request.Response): string[] {
  const raw = res.headers['set-cookie'] as unknown;
  if (!raw) return [];
  return (Array.isArray(raw) ? raw : [raw]).map((cookie: string) => cookie.split(';')[0] as string);
}

export async function createKiosk(
  app: TestApp,
  token: string,
  name = 'Front gate',
): Promise<{ id: string; token: string }> {
  const res = await request(app).post('/api/v1/kiosks').set(bearer(token)).send({ name });
  expect(res.status, JSON.stringify(res.body)).toBe(201);
  return { id: res.body.data.kiosk.id, token: res.body.data.token };
}

export async function createMember(
  app: TestApp,
  token: string,
  body: { fullName: string; code?: string; pin?: string; group?: string; joinedOn?: string },
): Promise<{ id: string; code: string }> {
  const res = await request(app).post('/api/v1/members').set(bearer(token)).send(body);
  expect(res.status, JSON.stringify(res.body)).toBe(201);
  return { id: res.body.data.id, code: res.body.data.code };
}

/** Supertest parser that keeps binary bodies (xlsx) as a Buffer. */
export function binaryParser(res: request.Response, callback: (error: Error | null, body: Buffer) => void): void {
  const stream = res as unknown as NodeJS.ReadableStream;
  const chunks: Buffer[] = [];
  stream.on('data', (chunk: Buffer) => chunks.push(chunk));
  stream.on('end', () => callback(null, Buffer.concat(chunks)));
}

/** Loads xlsx bytes into an ExcelJS workbook (bridges Node 22+ Buffer generics and ExcelJS typings). */
export async function loadWorkbook(bytes: Uint8Array): Promise<ExcelJS.Workbook> {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(Buffer.from(bytes) as unknown as Parameters<typeof workbook.xlsx.load>[0]);
  return workbook;
}
__ATTENDANCE_EOF__

write 'apps/api/test/unit/attendance-policy.test.ts' <<'__ATTENDANCE_EOF__'
import { describe, expect, it } from 'vitest';
import {
  createAttendancePolicy,
  DEFAULT_POLICIES,
  FixedWindowPolicy,
  FlexibleHoursPolicy,
  policyConfigSchema,
  type CheckInContext,
} from '../../src/modules/attendance/policies/index.js';

const MONDAY = 1;
const SATURDAY = 6;
const at = (localTime: string, overrides: Partial<CheckInContext> = {}): CheckInContext => ({
  localTime,
  weekday: MONDAY,
  isHoliday: false,
  ...overrides,
});

describe('FixedWindowPolicy (school default: opens 07:00, late after 08:00, closes 08:30)', () => {
  const policy = createAttendancePolicy({ ...DEFAULT_POLICIES.SCHOOL, workDays: [1, 2, 3, 4, 5] });

  it('is selected by the factory for FIXED_WINDOW', () => {
    expect(policy).toBeInstanceOf(FixedWindowPolicy);
  });

  it.each([
    ['06:59', { allowed: false, reason: 'TOO_EARLY' }],
    ['07:00', { allowed: true, status: 'PRESENT' }],
    ['08:00', { allowed: true, status: 'PRESENT' }],
    ['08:01', { allowed: true, status: 'LATE' }],
    ['08:30', { allowed: true, status: 'LATE' }],
    ['08:31', { allowed: false, reason: 'WINDOW_CLOSED' }],
    ['15:00', { allowed: false, reason: 'WINDOW_CLOSED' }],
    ['23:59', { allowed: false, reason: 'WINDOW_CLOSED' }],
  ])('at %s → %o', (time, expected) => {
    expect(policy.evaluateCheckIn(at(time))).toMatchObject(expected);
  });

  it('rejects non-working days before looking at the time', () => {
    expect(policy.evaluateCheckIn(at('07:30', { weekday: SATURDAY }))).toMatchObject({
      allowed: false,
      reason: 'NON_WORKDAY',
    });
  });

  it('rejects holidays', () => {
    expect(policy.evaluateCheckIn(at('07:30', { isHoliday: true }))).toMatchObject({
      allowed: false,
      reason: 'HOLIDAY',
    });
  });
});

describe('FlexibleHoursPolicy (company default: opens 06:00, late after 09:00)', () => {
  const policy = createAttendancePolicy({ ...DEFAULT_POLICIES.COMPANY, workDays: [1, 2, 3, 4, 5] });

  it('is selected by the factory for FLEXIBLE_HOURS', () => {
    expect(policy).toBeInstanceOf(FlexibleHoursPolicy);
    expect(policy.allowsCheckOut).toBe(true);
  });

  it('accepts check-in all day after opening, marking late arrivals', () => {
    expect(policy.evaluateCheckIn(at('05:59'))).toMatchObject({ allowed: false, reason: 'TOO_EARLY' });
    expect(policy.evaluateCheckIn(at('09:00'))).toMatchObject({ allowed: true, status: 'PRESENT' });
    expect(policy.evaluateCheckIn(at('14:30'))).toMatchObject({ allowed: true, status: 'LATE' });
  });
});

describe('isExpectedDay', () => {
  const policy = createAttendancePolicy({ ...DEFAULT_POLICIES.SCHOOL, workDays: [1, 2, 3, 4, 5] });

  it('expects work days that are not holidays', () => {
    const holidays = new Set(['2026-10-01']); // Independence Day, a Thursday
    expect(policy.isExpectedDay('2026-09-28', holidays)).toBe(true); // Monday
    expect(policy.isExpectedDay('2026-10-01', holidays)).toBe(false); // holiday
    expect(policy.isExpectedDay('2026-10-03', holidays)).toBe(false); // Saturday
  });
});

describe('policyConfigSchema', () => {
  const base = { workDays: [1, 2, 3, 4, 5], opensAt: '07:00', lateAfter: '08:00', allowCheckOut: false };

  it('requires closesAt for FIXED_WINDOW', () => {
    expect(policyConfigSchema.safeParse({ kind: 'FIXED_WINDOW', ...base }).success).toBe(false);
    expect(policyConfigSchema.safeParse({ kind: 'FIXED_WINDOW', ...base, closesAt: '08:30' }).success).toBe(true);
  });

  it('rejects times out of order', () => {
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, lateAfter: '06:00' }).success).toBe(false);
    expect(policyConfigSchema.safeParse({ kind: 'FIXED_WINDOW', ...base, closesAt: '07:30' }).success).toBe(false);
  });

  it('normalises work days (dedupe + sort) and rejects invalid ones', () => {
    const parsed = policyConfigSchema.parse({ kind: 'FLEXIBLE_HOURS', ...base, workDays: [5, 1, 1, 3] });
    expect(parsed.workDays).toEqual([1, 3, 5]);
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, workDays: [0] }).success).toBe(false);
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, workDays: [] }).success).toBe(false);
  });

  it('rejects malformed times', () => {
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, opensAt: '7am' }).success).toBe(false);
    expect(policyConfigSchema.safeParse({ kind: 'FLEXIBLE_HOURS', ...base, opensAt: '24:00' }).success).toBe(false);
  });
});
__ATTENDANCE_EOF__

write 'apps/api/test/unit/error-mapping.test.ts' <<'__ATTENDANCE_EOF__'
import mongoose from 'mongoose';
import { describe, expect, it } from 'vitest';
import {
  BusinessRuleError,
  ConflictError,
  ForbiddenError,
  NotFoundError,
  UnauthorizedError,
  ValidationError,
} from '../../src/core/errors/index.js';
import { mapError } from '../../src/core/middleware/error-handler.js';
import { CheckInRejectedError } from '../../src/modules/attendance/check-in/check-in.errors.js';

describe('mapError', () => {
  it.each([
    [new ValidationError('bad'), 400, 'VALIDATION_ERROR'],
    [new UnauthorizedError(), 401, 'UNAUTHORIZED'],
    [new ForbiddenError(), 403, 'FORBIDDEN'],
    [new NotFoundError('Member'), 404, 'NOT_FOUND'],
    [new ConflictError('dup'), 409, 'CONFLICT'],
    [new BusinessRuleError('nope'), 422, 'RULE_VIOLATION'],
    [new CheckInRejectedError('WINDOW_CLOSED', 'closed'), 422, 'CHECK_IN_REJECTED'],
  ])('maps %s polymorphically', (error, status, code) => {
    const mapped = mapError(error);
    expect(mapped.statusCode).toBe(status);
    expect(mapped.body.code).toBe(code);
  });

  it('keeps structured details', () => {
    expect(mapError(new CheckInRejectedError('HOLIDAY', 'Today is a holiday')).body).toEqual({
      code: 'CHECK_IN_REJECTED',
      message: 'Today is a holiday',
      details: { reason: 'HOLIDAY' },
    });
    expect(new NotFoundError('Member').message).toBe('Member not found');
  });

  it('turns MongoDB duplicate-key errors into 409 without leaking index internals', () => {
    const mapped = mapError({
      code: 11000,
      keyValue: { orgId: 'x', code: '123456' },
      errmsg: 'E11000 index: orgId_1_code_1',
    });
    expect(mapped.statusCode).toBe(409);
    expect(JSON.stringify(mapped.body)).not.toContain('E11000');
    expect(mapped.body.details).toEqual({ fields: ['orgId', 'code'] });
  });

  it('maps Mongoose cast errors to 400', () => {
    const error = new mongoose.Error.CastError('ObjectId', 'not-an-id', '_id');
    expect(mapError(error).statusCode).toBe(400);
  });

  it('never exposes the message of unexpected errors', () => {
    const mapped = mapError(new Error('connection string mongodb://admin:secret@db'));
    expect(mapped.statusCode).toBe(500);
    expect(mapped.body.message).not.toContain('secret');
    expect(mapped.body.code).toBe('INTERNAL_ERROR');
  });

  it('recognises malformed JSON bodies from express.json()', () => {
    expect(mapError(Object.assign(new SyntaxError('Unexpected token'), { type: 'entity.parse.failed' }))).toMatchObject(
      {
        statusCode: 400,
        body: { code: 'MALFORMED_JSON' },
      },
    );
  });
});
__ATTENDANCE_EOF__

write 'apps/api/test/unit/local-date.test.ts' <<'__ATTENDANCE_EOF__'
import { describe, expect, it } from 'vitest';
import {
  daysInclusive,
  eachDate,
  isValidLocalDate,
  isValidTimeZone,
  minutesOfDay,
  toInstant,
  toZonedMoment,
} from '../../src/core/time/local-date.js';

describe('timezone handling', () => {
  it('converts UTC instants to the organisation-local date, time and weekday', () => {
    // 23:30 UTC on Monday is 00:30 on Tuesday in Lagos (UTC+1).
    expect(toZonedMoment(new Date('2026-09-28T23:30:00Z'), 'Africa/Lagos')).toEqual({
      date: '2026-09-29',
      time: '00:30',
      weekday: 2,
    });
  });

  it('round-trips a local date and time through an absolute instant', () => {
    const instant = toInstant('2026-09-28', '07:45', 'Africa/Lagos');
    expect(instant.toISOString()).toBe('2026-09-28T06:45:00.000Z');
    expect(toZonedMoment(instant, 'Africa/Lagos')).toMatchObject({ date: '2026-09-28', time: '07:45' });
  });

  it('validates IANA zones', () => {
    expect(isValidTimeZone('Africa/Lagos')).toBe(true);
    expect(isValidTimeZone('Mars/Olympus')).toBe(false);
  });
});

describe('calendar helpers', () => {
  it('lists every date inclusively across month boundaries', () => {
    expect(eachDate('2026-09-29', '2026-10-02')).toEqual(['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02']);
    expect(daysInclusive('2026-09-29', '2026-10-02')).toBe(4);
    expect(eachDate('2026-09-29', '2026-09-29')).toEqual(['2026-09-29']);
  });

  it('rejects impossible or malformed dates', () => {
    expect(isValidLocalDate('2026-02-28')).toBe(true);
    expect(isValidLocalDate('2026-02-30')).toBe(false);
    expect(isValidLocalDate('2026-9-1')).toBe(false);
    expect(isValidLocalDate('2026-09-01T00:00')).toBe(false);
  });

  it('converts HH:mm into minutes since midnight', () => {
    expect(minutesOfDay('00:00')).toBe(0);
    expect(minutesOfDay('08:30')).toBe(510);
    expect(minutesOfDay('23:59')).toBe(1439);
  });
});
__ATTENDANCE_EOF__

write 'apps/api/test/unit/report-exporters.test.ts' <<'__ATTENDANCE_EOF__'
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
__ATTENDANCE_EOF__

write 'apps/api/tsconfig.build.json' <<'__ATTENDANCE_EOF__'
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "rootDir": "src",
    "outDir": "dist",
    "noEmit": false
  },
  "include": ["src"]
}
__ATTENDANCE_EOF__

write 'apps/api/tsconfig.json' <<'__ATTENDANCE_EOF__'
{
  "compilerOptions": {
    "target": "ES2023",
    "lib": ["ES2023"],
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "types": ["node"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "resolveJsonModule": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "sourceMap": true,
    "rootDir": ".",
    "outDir": "dist"
  },
  "include": ["src", "test", "vitest.config.ts"]
}
__ATTENDANCE_EOF__

write 'apps/api/vitest.config.ts' <<'__ATTENDANCE_EOF__'
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
    globalSetup: ['./test/support/global-setup.ts'],
    // The first run downloads a MongoDB binary for mongodb-memory-server (cached afterwards).
    hookTimeout: 180_000,
    testTimeout: 30_000,
    pool: 'forks',
  },
});
__ATTENDANCE_EOF__

write 'docker-compose.yml' <<'__ATTENDANCE_EOF__'
# Optional local MongoDB:  docker compose up -d
# Then use MONGO_URI=mongodb://127.0.0.1:27017/attendance in apps/api/.env
services:
  mongo:
    image: mongo:8
    restart: unless-stopped
    ports:
      - '27017:27017'
    volumes:
      - mongo-data:/data/db

volumes:
  mongo-data:
__ATTENDANCE_EOF__

write 'docs/api.http' <<'__ATTENDANCE_EOF__'
### Attendance API – sample requests (JetBrains HTTP Client: IntelliJ, WebStorm…)
### Click the ▶ next to each request, top to bottom. Tokens are captured automatically.
### Start the API first: `npm run dev` (and optionally `npm run seed`).

@base = http://localhost:5000/api/v1

### Health
GET http://localhost:5000/api/health

### 1. Register an organization (creates you as OWNER)
POST {{base}}/auth/register
Content-Type: application/json

{
  "organization": { "name": "Sample Academy", "type": "SCHOOL", "timezone": "Africa/Lagos" },
  "user": { "name": "Sample Owner", "email": "owner@sample.test", "password": "change-me-please" }
}

> {% client.global.set("accessToken", response.body.data.accessToken); %}

### 1b. …or log in (seeded demo: demo@attendance.local / demo-password-123)
POST {{base}}/auth/login
Content-Type: application/json

{ "email": "owner@sample.test", "password": "change-me-please" }

> {% client.global.set("accessToken", response.body.data.accessToken); %}

### Who am I
GET {{base}}/auth/me
Authorization: Bearer {{accessToken}}

### Refresh the access token (uses the httpOnly cookie the client stored)
POST {{base}}/auth/refresh
X-Requested-With: XMLHttpRequest

> {% client.global.set("accessToken", response.body.data.accessToken); %}

### 2. Add a member (code auto-generated when omitted)
POST {{base}}/members
Authorization: Bearer {{accessToken}}
Content-Type: application/json

{ "fullName": "Chidi Okeke", "code": "STF-001", "group": "JSS 1" }

> {% client.global.set("memberId", response.body.data.id); %}

### Bulk import
POST {{base}}/members/import
Authorization: Bearer {{accessToken}}
Content-Type: application/json

{
  "members": [
    { "fullName": "Ngozi Eze", "group": "JSS 1" },
    { "fullName": "Bayo Ade", "group": "JSS 2", "code": "STF-002" }
  ]
}

### List members
GET {{base}}/members?status=ACTIVE&page=1&limit=50
Authorization: Bearer {{accessToken}}

### 3. Register a kiosk device (the token is shown once)
POST {{base}}/kiosks
Authorization: Bearer {{accessToken}}
Content-Type: application/json

{ "name": "Front gate" }

> {% client.global.set("kioskToken", response.body.data.token); %}

### Kiosk: session info for the check-in screen
GET {{base}}/kiosk/session
Authorization: Kiosk {{kioskToken}}

### Kiosk: check in by code
### (school default window is 07:00–08:30 Lagos time on weekdays; outside it you get 422 WINDOW_CLOSED)
POST {{base}}/kiosk/check-in
Authorization: Kiosk {{kioskToken}}
Content-Type: application/json

{ "method": "CODE", "code": "STF-001" }

### Widen the window while testing (FLEXIBLE_HOURS = check-in any time after opensAt)
PUT {{base}}/organization/policy
Authorization: Bearer {{accessToken}}
Content-Type: application/json

{ "kind": "FLEXIBLE_HOURS", "workDays": [1, 2, 3, 4, 5, 6, 7], "opensAt": "00:00", "lateAfter": "08:00", "allowCheckOut": true }

### 4. Today's attendance
GET {{base}}/attendance/daily
Authorization: Bearer {{accessToken}}

### Manual correction (forgot to check in)
POST {{base}}/attendance/manual
Authorization: Bearer {{accessToken}}
Content-Type: application/json

{ "memberId": "{{memberId}}", "date": "2026-09-28", "status": "PRESENT", "note": "Signed the paper register" }

### 5. Holidays and terms
POST {{base}}/holidays
Authorization: Bearer {{accessToken}}
Content-Type: application/json

{ "date": "2026-10-01", "name": "Independence Day" }

###
POST {{base}}/periods
Authorization: Bearer {{accessToken}}
Content-Type: application/json

{ "name": "1st Term 2026/27", "type": "TERM", "startsOn": "2026-09-14", "endsOn": "2026-12-18" }

> {% client.global.set("periodId", response.body.data.id); %}

### 6. Reports – JSON
GET {{base}}/reports/attendance?periodId={{periodId}}
Authorization: Bearer {{accessToken}}

### Reports – Excel (saved next to this file as attendance-report.xlsx)
GET {{base}}/reports/attendance?periodId={{periodId}}&format=xlsx
Authorization: Bearer {{accessToken}}

>>! attendance-report.xlsx

### Logout
POST {{base}}/auth/logout
X-Requested-With: XMLHttpRequest
__ATTENDANCE_EOF__

write 'eslint.config.js' <<'__ATTENDANCE_EOF__'
import js from '@eslint/js';
import { defineConfig, globalIgnores } from 'eslint/config';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default defineConfig([
  // client/ is the legacy v1 frontend; it is replaced by apps/web in the next phase.
  globalIgnores(['**/dist/**', '**/coverage/**', '**/node_modules/**', 'client/**', '.idea/**']),
  js.configs.recommended,
  tseslint.configs.recommended,
  {
    files: ['**/*.ts'],
    languageOptions: { globals: globals.node },
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
    files: ['**/test/**/*.ts'],
    rules: { '@typescript-eslint/no-non-null-assertion': 'off' },
  },
]);
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
        "eslint": "^10.11.0",
        "globals": "^17.0.0",
        "prettier": "^3.9.9",
        "typescript": "~6.0.3",
        "typescript-eslint": "^8.71.0"
      },
      "engines": {
        "node": ">=22.12"
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
    "node_modules/@attendance/api": {
      "resolved": "apps/api",
      "link": true
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
      "engines": {
        "node": "^20.19.0 || >=22.12.0"
      }
    },
    "node_modules/@rolldown/pluginutils": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/@rolldown/pluginutils/-/pluginutils-1.0.1.tgz",
      "integrity": "sha512-2j9bGt5Jh8hj+vPtgzPtl72j0yRxHAyumoo6TNfAjsLB04UtpSvPbPcDcBMxz7n+9CYB0c1GxQFxYRg2jimqGw==",
      "dev": true,
      "license": "MIT",
      "peer": true
    },
    "node_modules/@standard-schema/spec": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/@standard-schema/spec/-/spec-1.1.0.tgz",
      "integrity": "sha512-l2aFy5jALhniG5HgqrD6jXLi/rUWrKvqN/qJx6yoJsgKhblVd+iqqU4RCXavm/jPityDo5TCvKMnpjKnOriy0w==",
      "license": "MIT"
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
    "node_modules/bcryptjs": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/bcryptjs/-/bcryptjs-3.0.3.tgz",
      "integrity": "sha512-GlF5wPWnSa/X5LKM1o0wz0suXIINz1iHRLvTS+sLyi7XPbe5ycmYI3DlZqVGZZtDgl4DmasFg7gOB3JYbphV5g==",
      "license": "BSD-3-Clause",
      "bin": {
        "bcrypt": "bin/bcrypt"
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
    "node_modules/cookie": {
      "version": "0.7.2",
      "resolved": "https://registry.npmjs.org/cookie/-/cookie-0.7.2.tgz",
      "integrity": "sha512-yki5XnKuf750l50uGTllt6kKILY4nQ1eNIQatoXEByZ5dWgnKqbnqmTrBE5B4N7lrMJKQ2ytWMiTO2o0v6Ew/w==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
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
    "node_modules/detect-libc": {
      "version": "2.1.2",
      "resolved": "https://registry.npmjs.org/detect-libc/-/detect-libc-2.1.2.tgz",
      "integrity": "sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ==",
      "dev": true,
      "license": "Apache-2.0",
      "peer": true,
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
      "dev": true,
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
    "node_modules/get-caller-file": {
      "version": "2.0.5",
      "resolved": "https://registry.npmjs.org/get-caller-file/-/get-caller-file-2.0.5.tgz",
      "integrity": "sha512-DyFP3BM/3YHTQOCUL/w0OZHR0lpKeGrxotcHWcqNEdnltqFwXVfhEBQ94eIo34AfQpo0rGki4cyIiftY06h2Fg==",
      "license": "ISC",
      "engines": {
        "node": "6.* || 8.* || >= 10.*"
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
    "node_modules/hookified": {
      "version": "1.15.1",
      "resolved": "https://registry.npmjs.org/hookified/-/hookified-1.15.1.tgz",
      "integrity": "sha512-MvG/clsADq1GPM2KGo2nyfaWVyn9naPiXrqIe4jYjXNZQt238kWyOGrsyc/DmRAQ+Re6yeo6yX/yoNCG5KAEVg==",
      "dev": true,
      "license": "MIT"
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
      "peer": true,
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
    "node_modules/luxon": {
      "version": "3.7.2",
      "resolved": "https://registry.npmjs.org/luxon/-/luxon-3.7.2.tgz",
      "integrity": "sha512-vtEhXh/gNjI9Yg1u4jX/0YVPMvxzHuGgCm6tC5kZyb08yjGWGnqAjGJvcXbqQR2P3MyMEFnRbpcdFS6PBcLqew==",
      "license": "MIT",
      "engines": {
        "node": ">=12"
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
      "peer": true,
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
      "dev": true,
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
      "dev": true,
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
      "license": "ISC",
      "peer": true
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
      "peer": true,
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
      "peer": true,
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
    "node_modules/source-map-js": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/source-map-js/-/source-map-js-1.2.1.tgz",
      "integrity": "sha512-UXWMKhLOwVKb728IUtQPXxfYU+usdybtUrK/8uGE8CQMvrhOpwvzDBwj0QhSL7MQc7vIsISBG8VQ8+IDQxpfQA==",
      "dev": true,
      "license": "BSD-3-Clause",
      "peer": true,
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
    "node_modules/webidl-conversions": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/webidl-conversions/-/webidl-conversions-7.0.0.tgz",
      "integrity": "sha512-VwddBukDzu71offAQR975unBIGqfKZpM+8ZX6ySk8nYhVoo5CYaZyzt3YBvYtRtO+aoGlqxPg/B87NGVZ/fu6g==",
      "license": "BSD-2-Clause",
      "engines": {
        "node": ">=12"
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
    "node_modules/wrappy": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/wrappy/-/wrappy-1.0.2.tgz",
      "integrity": "sha512-l4Sp/DRseor9wL6EvV2+TuQn63dMkPjZ/sp9XkghTEbV9KlPS1xUsZ3u7/IQO4wxtcFB4bgpQPRcR3QCvezPcQ==",
      "license": "ISC"
    },
    "node_modules/xmlchars": {
      "version": "2.2.0",
      "resolved": "https://registry.npmjs.org/xmlchars/-/xmlchars-2.2.0.tgz",
      "integrity": "sha512-JZnDKK8B0RCDw84FNdDAIpZK+JuJw+s7Lz8nksI7SIuU3UXJJslUthsi+uWBUYOwPFwW7W7PRLRfUKpxjtjFCw==",
      "license": "MIT"
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
    }
  }
}
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
    "node": ">=22.12"
  },
  "scripts": {
    "dev": "npm run dev --workspace=@attendance/api",
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
    "eslint": "^10.11.0",
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

ok "Wrote $FILE_COUNT files"

# ── 4. Environment file ──────────────────────────────────────────────────────
if [ ! -f apps/api/.env ]; then
  SECRET=$(node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))")
  sed "s#^JWT_ACCESS_SECRET=.*#JWT_ACCESS_SECRET=$SECRET#" apps/api/.env.example > apps/api/.env
  ok "Created apps/api/.env with a fresh JWT secret"
  warn "Set MONGO_URI in apps/api/.env if you are not using a local MongoDB on 127.0.0.1:27017"
else
  ok "apps/api/.env already exists – left untouched"
fi

# ── 5. Dependencies ──────────────────────────────────────────────────────────
if [ "$SKIP_INSTALL" = 0 ]; then
  say "Installing dependencies (first run also downloads a MongoDB binary for tests)…"
  npm install --no-fund --no-audit
  ok "Dependencies installed"
else
  warn "Skipped npm install (--skip-install). Run it yourself from the repo root."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
cat <<'NEXT'

  Phase 1 (API) installed.

  Next:
    1. Check apps/api/.env  (MONGO_URI → local MongoDB, Atlas, or: docker compose up -d)
    2. npm test             (102 tests; first run may take a minute while MongoDB downloads)
    3. npm run dev          → http://localhost:5000/api/health
    4. npm run seed         (demo school + kiosk token), then open docs/api.http
    5. git add -A && git commit -m "feat(api): v2 rebuild – phase 1"

  Note: client/ is the legacy frontend and is untouched. It no longer matches the API
  and is replaced by apps/web in the next phase – don't npm install inside it.

NEXT
