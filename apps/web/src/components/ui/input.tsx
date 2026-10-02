import { forwardRef, type InputHTMLAttributes, type SelectHTMLAttributes } from 'react';
import { cn } from '@/lib/cn';

const control =
  'h-10 w-full rounded-lg border border-rule bg-paper px-3 text-sm text-text placeholder:text-muted/70 transition-colors hover:border-ink-soft/60 focus:border-ink focus:outline-none aria-[invalid=true]:border-absent disabled:bg-desk disabled:text-muted';

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(function Input(
  { className, ...props },
  ref,
) {
  return <input ref={ref} className={cn(control, className)} {...props} />;
});

export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(function Select(
  { className, children, ...props },
  ref,
) {
  return (
    <select ref={ref} className={cn(control, 'pr-8', className)} {...props}>
      {children}
    </select>
  );
});
