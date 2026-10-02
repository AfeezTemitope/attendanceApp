import type { DailyStatus } from '@/api/types';
import { cn } from '@/lib/cn';

const STYLE: Record<DailyStatus, { label: string; className: string }> = {
  PRESENT: { label: 'On time', className: 'bg-present-wash text-present' },
  LATE: { label: 'Late', className: 'bg-late-wash text-late' },
  ABSENT: { label: 'Absent', className: 'bg-absent-wash text-absent' },
  NOT_CHECKED_IN: { label: 'Not in yet', className: 'border border-dashed border-rule text-muted' },
  HOLIDAY: { label: 'Holiday', className: 'bg-holiday-wash text-holiday' },
  NON_WORKDAY: { label: 'Day off', className: 'bg-desk text-muted' },
};

export function StatusPill({ status, time }: { status: DailyStatus; time?: string | null }) {
  const { label, className } = STYLE[status];
  return (
    <span className={cn('inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-sm font-medium', className)}>
      {label}
      {time && <span className="tabular opacity-80">{time}</span>}
    </span>
  );
}
