import type { AttendanceReport, DayMark } from '@/api/types';
import { RegisterMark } from '@/components/ui/register-mark';
import { cn } from '@/lib/cn';
import { formatDayLabel, formatShortDate } from '@/lib/format';

export const MAX_GRID_DAYS = 62;

const LEGEND: Array<[DayMark, string]> = [
  ['P', 'On time'],
  ['L', 'Late'],
  ['A', 'Absent'],
  ['H', 'Holiday'],
  ['W', 'Not a working day'],
];

/** The report as a class register: one row per person, one column per day. */
export function RegisterGrid({ report }: { report: AttendanceReport }) {
  const holidays = new Set(report.holidays.map((holiday) => holiday.date));
  return (
    <div>
      <div className="overflow-x-auto rounded-2xl border border-rule bg-paper">
        <table className="border-separate border-spacing-0 text-sm">
          <thead>
            <tr>
              <th
                scope="col"
                className="sticky left-0 z-10 min-w-48 border-r border-b border-rule bg-paper px-4 py-2 text-left font-medium text-muted"
              >
                Name
              </th>
              {report.dates.map((date) => {
                const label = formatDayLabel(date);
                return (
                  <th
                    key={date}
                    scope="col"
                    title={formatShortDate(date)}
                    className={cn(
                      'border-b border-rule px-0.5 py-1 text-center font-normal text-muted',
                      holidays.has(date) && 'bg-holiday-wash',
                    )}
                  >
                    <span className="block text-[10px]">{label.weekday}</span>
                    <span className="tabular block text-xs">{label.day}</span>
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody>
            {report.rows.map((row) => (
              <tr key={row.memberId} className="group">
                <th
                  scope="row"
                  className="sticky left-0 z-10 border-r border-b border-rule bg-paper px-4 py-1 text-left font-medium group-hover:bg-desk"
                >
                  <span className="block max-w-56 truncate">{row.fullName}</span>
                </th>
                {row.marks.map((mark, index) => (
                  <td
                    key={report.dates[index]}
                    className="border-b border-rule px-0.5 py-0.5 text-center group-hover:bg-desk/60"
                  >
                    <RegisterMark mark={mark} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted" aria-label="Key">
        {LEGEND.map(([mark, label]) => (
          <li key={mark} className="inline-flex items-center gap-1">
            <RegisterMark mark={mark} className="size-6" />
            {label}
          </li>
        ))}
      </ul>
    </div>
  );
}
