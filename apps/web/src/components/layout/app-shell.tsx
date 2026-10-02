import { CalendarCheck, FileSpreadsheet, LogOut, Settings, Users } from 'lucide-react';
import { NavLink, Outlet } from 'react-router';
import { APP_NAME } from '@/app/brand';
import { useAuth, useProfile } from '@/features/auth/use-auth';
import { ROLE_LABEL } from '@/features/auth/roles';
import { cn } from '@/lib/cn';

const NAV = [
  { to: '/', label: 'Today', icon: CalendarCheck, end: true },
  { to: '/people', label: 'People', icon: Users, end: false },
  { to: '/reports', label: 'Reports', icon: FileSpreadsheet, end: false },
  { to: '/settings', label: 'Settings', icon: Settings, end: false },
] as const;

export function AppShell() {
  const profile = useProfile();
  const { logout } = useAuth();

  return (
    <div className="min-h-screen md:grid md:grid-cols-[15rem_1fr]">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:rounded-lg focus:bg-paper focus:px-3 focus:py-2"
      >
        Skip to content
      </a>

      {/* Sidebar (tablet and up) */}
      <aside className="sticky top-0 hidden h-screen flex-col border-r border-rule bg-paper md:flex">
        <div className="px-5 pt-6 pb-5">
          <p className="font-display text-2xl font-semibold text-ink">{APP_NAME}</p>
          <p className="mt-0.5 truncate text-sm text-muted" title={profile.organization.name}>
            {profile.organization.name}
          </p>
        </div>
        <nav aria-label="Main" className="flex flex-col gap-0.5 px-3">
          {NAV.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                cn(
                  'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                  isActive ? 'bg-ink text-white' : 'text-muted hover:bg-ink-wash hover:text-ink',
                )
              }
            >
              <Icon className="size-4.5" aria-hidden />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="mt-auto border-t border-rule px-5 py-4">
          <p className="truncate text-sm font-semibold">{profile.user.name}</p>
          <p className="text-xs text-muted">{ROLE_LABEL[profile.role]}</p>
          <button
            type="button"
            onClick={() => void logout()}
            className="mt-3 inline-flex items-center gap-2 text-sm text-muted hover:text-ink"
          >
            <LogOut className="size-4" aria-hidden />
            Sign out
          </button>
        </div>
      </aside>

      {/* Top bar (phones) */}
      <header className="flex items-center justify-between border-b border-rule bg-paper px-4 py-3 md:hidden">
        <div className="min-w-0">
          <p className="font-display text-xl font-semibold text-ink">{APP_NAME}</p>
          <p className="truncate text-xs text-muted">{profile.organization.name}</p>
        </div>
        <button
          type="button"
          onClick={() => void logout()}
          className="rounded-lg p-2 text-muted hover:bg-ink-wash"
          aria-label="Sign out"
        >
          <LogOut className="size-5" />
        </button>
      </header>

      <main id="main" className="mx-auto w-full max-w-6xl px-4 pt-6 pb-24 sm:px-8 md:pt-10 md:pb-12">
        <Outlet />
      </main>

      {/* Bottom tabs (phones) */}
      <nav
        aria-label="Main"
        className="fixed inset-x-0 bottom-0 z-10 grid grid-cols-4 border-t border-rule bg-paper md:hidden"
      >
        {NAV.map(({ to, label, icon: Icon, end }) => (
          <NavLink
            key={to}
            to={to}
            end={end}
            className={({ isActive }) =>
              cn('flex flex-col items-center gap-0.5 py-2 text-xs font-medium', isActive ? 'text-ink' : 'text-muted')
            }
          >
            <Icon className="size-5" aria-hidden />
            {label}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
