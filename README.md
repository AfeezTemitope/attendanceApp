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
