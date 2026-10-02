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
