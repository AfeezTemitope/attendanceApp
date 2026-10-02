import { useEffect } from 'react';
import { cn } from '@/lib/cn';
import type { Outcome } from './outcome';

const DISMISS_MS = { success: 3_500, error: 6_000 };

/** Full-screen answer to "did it work?", readable from across the gate. Tap anywhere to dismiss. */
export function ResultOverlay({ outcome, onDone }: { outcome: Outcome; onDone: () => void }) {
  useEffect(() => {
    const timer = setTimeout(onDone, outcome.kind === 'error' ? DISMISS_MS.error : DISMISS_MS.success);
    return () => clearTimeout(timer);
  }, [outcome, onDone]);

  const success = outcome.kind !== 'error';
  return (
    <button
      type="button"
      onClick={onDone}
      aria-live="assertive"
      className={cn(
        'fixed inset-0 z-20 flex flex-col items-center justify-center gap-6 px-8 text-center',
        outcome.kind === 'in' && !outcome.late && 'bg-present text-white',
        outcome.kind === 'in' && outcome.late && 'bg-late text-white',
        outcome.kind === 'out' && 'bg-ink text-white',
        outcome.kind === 'error' && 'border-l-[12px] border-absent bg-paper text-text',
      )}
    >
      {success ? (
        <svg viewBox="0 0 64 64" className="size-40 sm:size-56" aria-hidden>
          <path
            d="M14 34l12 12L50 18"
            pathLength={1}
            fill="none"
            stroke="currentColor"
            strokeWidth="7"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="animate-draw"
          />
        </svg>
      ) : (
        <svg viewBox="0 0 64 64" className="size-28 text-absent sm:size-36" aria-hidden>
          <path d="M18 18l28 28M46 18L18 46" fill="none" stroke="currentColor" strokeWidth="7" strokeLinecap="round" />
        </svg>
      )}
      {outcome.kind === 'error' ? (
        <p className="max-w-2xl font-display text-3xl font-semibold text-balance sm:text-5xl">{outcome.message}</p>
      ) : (
        <>
          <p className="font-display text-5xl font-semibold sm:text-7xl">
            {outcome.kind === 'in' ? `Welcome, ${outcome.name}` : `Goodbye, ${outcome.name}`}
          </p>
          <p className="text-2xl opacity-90 sm:text-3xl">{outcome.detail}</p>
        </>
      )}
      <span className="sr-only">Tap to continue</span>
    </button>
  );
}
