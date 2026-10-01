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
