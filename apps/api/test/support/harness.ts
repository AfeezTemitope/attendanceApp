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
