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
