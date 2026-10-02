import { API_BASE_URL } from '@/api/client';
import type { CheckInCredentials, CheckInResult, CheckOutResult, KioskSession } from '@/api/types';
import { KioskHttpClient } from '@/lib/http';

const STORAGE_KEY = 'rollcall.kioskToken';

/**
 * The device token lives in localStorage on purpose: it identifies the device, not a person,
 * it can only check people in or out, and an admin can revoke it at any time.
 */
export const kioskTokens = {
  get(): string | null {
    try {
      return localStorage.getItem(STORAGE_KEY);
    } catch {
      return null;
    }
  },
  set(token: string): void {
    localStorage.setItem(STORAGE_KEY, token);
  },
  clear(): void {
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch {
      // storage unavailable: nothing to clear
    }
  },
};

export const kioskClient = new KioskHttpClient(API_BASE_URL, kioskTokens);

export const kioskApi = {
  session: () => kioskClient.get<KioskSession>('/kiosk/session'),
  checkIn: (credentials: CheckInCredentials) => kioskClient.post<CheckInResult>('/kiosk/check-in', credentials),
  checkOut: (credentials: CheckInCredentials) => kioskClient.post<CheckOutResult>('/kiosk/check-out', credentials),
};
