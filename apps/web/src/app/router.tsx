import type { RouteObject } from 'react-router';
import { AppShell } from '@/components/layout/app-shell';
import { SessionRoot } from '@/features/auth/auth-context';
import { GuestOnly, RequireAuth } from '@/features/auth/guards';
import { TodayPage } from '@/features/today/today-page';
import { NotFound, RouteError } from './route-error';

export const routes: RouteObject[] = [
  {
    element: <SessionRoot />,
    errorElement: <RouteError />,
    children: [
      {
        // Form pages carry zod and react-hook-form; signed-in users never download them.
        path: '/login',
        lazy: () =>
          import('@/features/auth/login-page').then(({ LoginPage }) => ({
            element: (
              <GuestOnly>
                <LoginPage />
              </GuestOnly>
            ),
          })),
      },
      {
        path: '/register',
        lazy: () =>
          import('@/features/auth/register-page').then(({ RegisterPage }) => ({
            element: (
              <GuestOnly>
                <RegisterPage />
              </GuestOnly>
            ),
          })),
      },
      {
        path: '/',
        element: (
          <RequireAuth>
            <AppShell />
          </RequireAuth>
        ),
        children: [
          { index: true, element: <TodayPage /> },
          {
            path: 'people',
            lazy: () => import('@/features/people/people-page').then((m) => ({ Component: m.PeoplePage })),
          },
          {
            path: 'people/:id',
            lazy: () => import('@/features/people/person-page').then((m) => ({ Component: m.PersonPage })),
          },
          {
            path: 'reports',
            lazy: () => import('@/features/reports/reports-page').then((m) => ({ Component: m.ReportsPage })),
          },
          {
            path: 'settings',
            lazy: () => import('@/features/settings/settings-page').then((m) => ({ Component: m.SettingsPage })),
          },
        ],
      },
    ],
  },
  // The kiosk bundle (camera + QR decoder) only loads on check-in devices.
  {
    path: '/kiosk',
    errorElement: <RouteError />,
    lazy: () => import('@/features/kiosk/kiosk-page').then((m) => ({ Component: m.KioskPage })),
  },
  {
    path: '/kiosk/pair',
    errorElement: <RouteError />,
    lazy: () => import('@/features/kiosk/pair-page').then((m) => ({ Component: m.PairPage })),
  },
  { path: '*', element: <NotFound /> },
];
