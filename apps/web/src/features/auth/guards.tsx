import type { ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router';
import { Spinner } from '@/components/ui/feedback';
import { useAuth } from './use-auth';

export function RequireAuth({ children }: { children: ReactNode }) {
  const { state } = useAuth();
  const location = useLocation();
  if (state.status === 'loading') return <Spinner label="Opening your register" className="min-h-screen" />;
  if (state.status === 'anonymous') return <Navigate to="/login" replace state={{ from: location }} />;
  return children;
}

/** Login and sign-up pages: send signed-in users straight to the app. */
export function GuestOnly({ children }: { children: ReactNode }) {
  const { state } = useAuth();
  if (state.status === 'loading') return <Spinner className="min-h-screen" />;
  if (state.status === 'authenticated') return <Navigate to="/" replace />;
  return children;
}
