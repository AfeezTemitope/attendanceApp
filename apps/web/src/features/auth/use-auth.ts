import { useContext } from 'react';
import type { Profile, Role } from '@/api/types';
import { AuthContext, type AuthContextValue } from './context';
import { hasRole } from './roles';

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used inside <AuthProvider>');
  return context;
}

/** The signed-in profile. Only use below <RequireAuth>. */
export function useProfile(): Profile {
  const { state } = useAuth();
  if (state.status !== 'authenticated') throw new Error('useProfile used outside an authenticated route');
  return state.profile;
}

export function useCan(required: Role): boolean {
  return hasRole(useProfile().role, required);
}
