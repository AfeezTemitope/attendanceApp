import type { ReactNode } from 'react';

/** Consistent block for one settings form. */
export function SettingsBlock({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: ReactNode;
}) {
  return (
    <section className="max-w-2xl rounded-2xl border border-rule bg-paper px-6 py-5">
      <h2 className="text-xl font-semibold">{title}</h2>
      {description && <p className="mt-1 text-sm text-muted">{description}</p>}
      <div className="mt-5">{children}</div>
    </section>
  );
}
