import { useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Outlet } from 'react-router';
import { api } from '@/api/client';
import { authApi } from '@/api/endpoints';
import type { Profile, Session } from '@/api/types';
import { AuthContext, type AuthContextValue, type AuthState } from './context';

const toProfile = ({ accessToken: _token, expiresIn: _ttl, ...profile }: Session): Profile => profile;

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [state, setState] = useState<AuthState>({ status: 'loading' });

  useEffect(() => {
    api.onSessionRefreshed = (session) => setState({ status: 'authenticated', profile: toProfile(session) });
    api.onSessionExpired = () => {
      queryClient.clear();
      setState({ status: 'anonymous', expired: true });
    };

    // Restore the session from the httpOnly refresh cookie, if there is one.
    let active = true;
    void api.refresh().then((session) => {
      if (active && !session) setState({ status: 'anonymous' });
    });
    return () => {
      active = false;
      api.onSessionRefreshed = null;
      api.onSessionExpired = null;
    };
  }, [queryClient]);

  const startSession = useCallback((session: Session) => {
    api.setAccessToken(session.accessToken);
    setState({ status: 'authenticated', profile: toProfile(session) });
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      login: async (email, password) => startSession(await authApi.login({ email, password })),
      register: async (input) => startSession(await authApi.register(input)),
      logout: async () => {
        try {
          await authApi.logout();
        } finally {
          api.setAccessToken(null);
          queryClient.clear();
          setState({ status: 'anonymous' });
        }
      },
      reloadProfile: async () => {
        const profile = await authApi.me();
        setState({ status: 'authenticated', profile });
      },
    }),
    [state, startSession, queryClient],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

/** Layout route for everything that uses the dashboard session. Kiosk routes deliberately sit outside it. */
export function SessionRoot() {
  return (
    <AuthProvider>
      <Outlet />
    </AuthProvider>
  );
}
