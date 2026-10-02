import type { ReactNode } from 'react';
import { APP_NAME } from '@/app/brand';

/** Sign-in pages: a single sheet of ruled register paper on the desk. */
export function AuthLayout({
  title,
  intro,
  children,
  footer,
}: {
  title: string;
  intro: ReactNode;
  children: ReactNode;
  footer: ReactNode;
}) {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-4 py-10">
      <p className="mb-6 font-display text-2xl font-semibold text-ink">{APP_NAME}</p>
      <div className="w-full max-w-md overflow-hidden rounded-2xl border border-rule bg-paper shadow-[0_20px_50px_-30px_rgb(29_43_107/0.5)]">
        <div className="border-l-4 border-absent/70 px-8 py-8">
          <h1 className="text-3xl font-semibold">{title}</h1>
          <p className="mt-2 text-muted">{intro}</p>
          <div className="mt-6">{children}</div>
        </div>
      </div>
      <div className="mt-6 text-sm text-muted">{footer}</div>
    </main>
  );
}
