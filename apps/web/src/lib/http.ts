import { ApiError } from './api-error';

export type Query = Record<string, string | number | boolean | null | undefined>;

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: unknown;
  query?: Query;
  headers?: Record<string, string>;
  signal?: AbortSignal;
  /** Auth endpoints must not trigger a token refresh when they return 401. */
  skipRefresh?: boolean;
}

export interface Envelope<T, M = undefined> {
  data: T;
  meta: M;
}

export interface Download {
  blob: Blob;
  fileName: string;
}

export type FetchLike = (input: string, init: RequestInit) => Promise<Response>;

/**
 * Base API client: URL building, JSON encoding, envelope unwrapping and error mapping.
 * Subclasses only decide how a request is authenticated (SessionHttpClient, KioskHttpClient).
 */
export class HttpClient {
  constructor(
    protected readonly baseUrl: string,
    protected readonly fetchImpl: FetchLike = (input, init) => fetch(input, init),
  ) {}

  get<T>(path: string, query?: Query, signal?: AbortSignal): Promise<T> {
    return this.request<T>(path, { query, signal });
  }

  post<T>(path: string, body?: unknown, options: RequestOptions = {}): Promise<T> {
    return this.request<T>(path, { ...options, method: 'POST', body });
  }

  put<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>(path, { method: 'PUT', body });
  }

  patch<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>(path, { method: 'PATCH', body });
  }

  delete<T = void>(path: string): Promise<T> {
    return this.request<T>(path, { method: 'DELETE' });
  }

  /** Returns `data` from the `{ data }` envelope. */
  async request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    return (await this.envelope<T>(path, options)).data;
  }

  /** Returns the whole envelope, for paginated lists that carry `meta`. */
  async envelope<T, M = undefined>(path: string, options: RequestOptions = {}): Promise<Envelope<T, M>> {
    const response = await this.execute(path, options);
    if (response.status === 204) return { data: undefined as T, meta: undefined as M };
    return (await response.json()) as Envelope<T, M>;
  }

  /** Binary download (Excel/CSV). The file name comes from Content-Disposition. */
  async download(path: string, query?: Query): Promise<Download> {
    const response = await this.execute(path, { query });
    const disposition = response.headers.get('content-disposition') ?? '';
    const fileName = /filename="([^"]+)"/.exec(disposition)?.[1] ?? 'download';
    return { blob: await response.blob(), fileName };
  }

  /** Sends the request and throws ApiError for any non-2xx response. */
  protected async execute(path: string, options: RequestOptions): Promise<Response> {
    const response = await this.send(path, options);
    if (!response.ok) throw await ApiError.fromResponse(response);
    return response;
  }

  /** One HTTP round trip. Subclasses override this to add authentication behaviour. */
  protected async send(path: string, options: RequestOptions): Promise<Response> {
    const headers: Record<string, string> = { Accept: 'application/json', ...this.authHeaders(), ...options.headers };
    let body: string | undefined;
    if (options.body !== undefined) {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify(options.body);
    }
    try {
      return await this.fetchImpl(this.url(path, options.query), {
        method: options.method ?? 'GET',
        headers,
        body,
        credentials: 'include',
        signal: options.signal,
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') throw error;
      throw ApiError.network(error);
    }
  }

  protected authHeaders(): Record<string, string> {
    return {};
  }

  protected url(path: string, query?: Query): string {
    const search = new URLSearchParams();
    for (const [key, value] of Object.entries(query ?? {})) {
      if (value !== undefined && value !== null && value !== '') search.set(key, String(value));
    }
    const qs = search.toString();
    return `${this.baseUrl}${path}${qs ? `?${qs}` : ''}`;
  }
}

/**
 * Dashboard client. Keeps the short-lived access token in memory only (never localStorage) and
 * transparently refreshes it with the httpOnly cookie when a request comes back 401.
 * Concurrent 401s share one refresh, because the server rotates the refresh token on every use.
 */
export class SessionHttpClient<TSession extends { accessToken: string }> extends HttpClient {
  private accessToken: string | null = null;
  private inflightRefresh: Promise<TSession | null> | null = null;

  /** Called when a refresh fails: the user must sign in again. */
  onSessionExpired: (() => void) | null = null;
  /** Called after every successful refresh with the fresh profile (roles can change). */
  onSessionRefreshed: ((session: TSession) => void) | null = null;

  setAccessToken(token: string | null): void {
    this.accessToken = token;
  }

  /** Exchanges the refresh cookie for a new access token. Safe to call from many places at once. */
  refresh(): Promise<TSession | null> {
    this.inflightRefresh ??= this.performRefresh().finally(() => {
      this.inflightRefresh = null;
    });
    return this.inflightRefresh;
  }

  protected override authHeaders(): Record<string, string> {
    return this.accessToken ? { Authorization: `Bearer ${this.accessToken}` } : {};
  }

  protected override async send(path: string, options: RequestOptions): Promise<Response> {
    const response = await super.send(path, options);
    if (response.status !== 401 || options.skipRefresh) return response;

    const session = await this.refresh();
    if (!session) {
      this.onSessionExpired?.();
      return response;
    }
    return super.send(path, options);
  }

  private async performRefresh(): Promise<TSession | null> {
    try {
      const response = await super.send('/auth/refresh', {
        method: 'POST',
        headers: { 'X-Requested-With': 'XMLHttpRequest' },
        skipRefresh: true,
      });
      if (!response.ok) {
        this.accessToken = null;
        return null;
      }
      const { data } = (await response.json()) as Envelope<TSession>;
      this.accessToken = data.accessToken;
      this.onSessionRefreshed?.(data);
      return data;
    } catch {
      return null; // offline: keep the current state; the next request tries again
    }
  }
}

/**
 * Check-in device client. Authenticates with the device token from pairing.
 * A 401 means an admin revoked the device: the token is dropped and the device must be paired again.
 */
export class KioskHttpClient extends HttpClient {
  onUnpaired: (() => void) | null = null;

  constructor(
    baseUrl: string,
    private readonly tokens: { get(): string | null; clear(): void },
    fetchImpl?: FetchLike,
  ) {
    super(baseUrl, fetchImpl);
  }

  protected override authHeaders(): Record<string, string> {
    const token = this.tokens.get();
    return token ? { Authorization: `Kiosk ${token}` } : {};
  }

  protected override async send(path: string, options: RequestOptions): Promise<Response> {
    const response = await super.send(path, options);
    if (response.status === 401) {
      this.tokens.clear();
      this.onUnpaired?.();
    }
    return response;
  }
}
