import type { DailyView } from '@/api/types';

/** One bar, four segments: on time, late, absent, not in yet. */
export function SegmentBar({ totals }: { totals: DailyView['totals'] }) {
  const segments = [
    { key: 'present', value: totals.present, className: 'bg-present', label: 'On time' },
    { key: 'late', value: totals.late, className: 'bg-late', label: 'Late' },
    { key: 'absent', value: totals.absent, className: 'bg-absent', label: 'Absent' },
    { key: 'pending', value: totals.notCheckedIn, className: 'bg-rule', label: 'Not in yet' },
  ].filter((segment) => segment.value > 0);
  const total = segments.reduce((sum, segment) => sum + segment.value, 0);
  if (total === 0) return null;

  return (
    <div>
      <div className="flex h-2.5 overflow-hidden rounded-full bg-desk" aria-hidden>
        {segments.map((segment) => (
          <div key={segment.key} className={segment.className} style={{ width: `${(segment.value / total) * 100}%` }} />
        ))}
      </div>
      <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted">
        {segments.map((segment) => (
          <li key={segment.key} className="inline-flex items-center gap-1.5">
            <span className={`size-2 rounded-full ${segment.className}`} aria-hidden />
            {segment.label} <span className="tabular font-semibold text-text">{segment.value}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
