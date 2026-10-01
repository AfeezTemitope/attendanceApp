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
