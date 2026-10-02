import { SessionHttpClient } from '@/lib/http';
import type { Session } from './types';

/** Same-origin by default: Vite proxies /api in development and the host rewrites it in production. */
export const API_BASE_URL: string = import.meta.env.VITE_API_URL ?? '/api/v1';

/** The dashboard's single API client. Auth state is wired up by AuthProvider. */
export const api = new SessionHttpClient<Session>(API_BASE_URL);
