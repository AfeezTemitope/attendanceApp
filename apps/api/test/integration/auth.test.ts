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
