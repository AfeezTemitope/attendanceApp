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
