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
