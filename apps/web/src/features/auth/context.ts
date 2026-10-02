import { createContext } from 'react';
import type { OrganizationType, Profile } from '@/api/types';

export type AuthState =
  { status: 'loading' } | { status: 'anonymous'; expired?: boolean } | { status: 'authenticated'; profile: Profile };

export interface RegisterInput {
  organization: { name: string; type: OrganizationType; timezone: string };
  user: { name: string; email: string; password: string };
}

export interface AuthContextValue {
  state: AuthState;
  login(email: string, password: string): Promise<void>;
  register(input: RegisterInput): Promise<void>;
  logout(): Promise<void>;
  /** Re-reads the profile, e.g. after renaming the organisation. */
  reloadProfile(): Promise<void>;
}

export const AuthContext = createContext<AuthContextValue | null>(null);
