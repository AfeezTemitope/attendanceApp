import type { DayMark } from '@/api/types';
import { cn } from '@/lib/cn';

const LABEL: Record<DayMark, string> = {
  P: 'Present',
  L: 'Late',
  A: 'Absent',
  H: 'Holiday',
  W: 'Not a working day',
  '-': 'Not applicable',
};

/** One cell of a register: a tick, a late tick, a red-pen cross, H, or a shaded non-working day. */
export function RegisterMark({ mark, className }: { mark: DayMark; className?: string }) {
  return (
    <span
      role="img"
      aria-label={LABEL[mark]}
      title={LABEL[mark]}
      className={cn(
        'inline-flex size-7 items-center justify-center rounded-md text-xs font-semibold',
        mark === 'P' && 'text-present',
        mark === 'L' && 'bg-late-wash text-late',
        mark === 'A' && 'text-absent',
        mark === 'H' && 'bg-holiday-wash text-holiday',
        mark === 'W' && 'bg-[repeating-linear-gradient(135deg,var(--color-rule)_0_1px,transparent_1px_5px)]',
        mark === '-' && 'text-rule',
        className,
      )}
    >
      {(mark === 'P' || mark === 'L') && <Tick />}
      {mark === 'A' && <Cross />}
      {mark === 'H' && 'H'}
      {mark === '-' && '·'}
    </span>
  );
}

function Tick() {
  return (
    <svg viewBox="0 0 16 16" className="size-4" aria-hidden>
      <path
        d="M3 8.5l3.2 3.2L13 4.5"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function Cross() {
  return (
    <svg viewBox="0 0 16 16" className="size-3.5" aria-hidden>
      <path d="M4 4l8 8M12 4l-8 8" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
    </svg>
  );
}
