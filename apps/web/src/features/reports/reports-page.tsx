import { useMutation, useQuery } from '@tanstack/react-query';
import { Download } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router';
import { toast } from 'sonner';
import { calendarApi, membersApi, queryKeys, reportsApi, type ReportQuery } from '@/api/endpoints';
import { PageHeader } from '@/components/layout/page-header';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Input, Select } from '@/components/ui/input';
import { useProfile } from '@/features/auth/use-auth';
import { errorMessage } from '@/lib/api-error';
import { cn } from '@/lib/cn';
import { saveDownload } from '@/lib/download';
import { formatPercent, formatShortDate, plural, startOfMonth, todayIn } from '@/lib/format';
import { MAX_GRID_DAYS, RegisterGrid } from './register-grid';

const LOW_ATTENDANCE = 75;

export function ReportsPage() {
  const { organization } = useProfile();
  const today = todayIn(organization.timezone);
  const [source, setSource] = useState<string>('month'); // 'month' | 'custom' | period id
  const [custom, setCustom] = useState({ from: startOfMonth(today), to: today });
  const [group, setGroup] = useState('');

  const periods = useQuery({ queryKey: queryKeys.periods, queryFn: calendarApi.periods });
  const groups = useQuery({ queryKey: queryKeys.groups, queryFn: membersApi.groups });

  const range: ReportQuery =
    source === 'month' ? { from: startOfMonth(today), to: today } : source === 'custom' ? custom : { periodId: source };
  const query: ReportQuery = { ...range, ...(group ? { group } : {}) };
  const valid = !('from' in query) || (query.from !== '' && query.to !== '' && query.from <= query.to);

  const report = useQuery({
    queryKey: queryKeys.report(query),
    queryFn: () => reportsApi.attendance(query),
    enabled: valid,
  });

  const download = useMutation({
    mutationFn: (format: 'xlsx' | 'csv') => reportsApi.download(query, format),
    onSuccess: saveDownload,
    onError: (error) => toast.error(errorMessage(error)),
  });

  const data = report.data;

  return (
    <>
      <PageHeader
        title="Reports"
        actions={
          <>
            <Button
              variant="secondary"
              disabled={!data}
              loading={download.isPending && download.variables === 'csv'}
              onClick={() => download.mutate('csv')}
            >
              CSV
            </Button>
            <Button
              disabled={!data}
              loading={download.isPending && download.variables === 'xlsx'}
              onClick={() => download.mutate('xlsx')}
            >
              <Download className="size-4" aria-hidden />
              Download Excel
            </Button>
          </>
        }
      >
        Attendance for a month, term or session, ready to share.
      </PageHeader>

      <div className="mb-6 flex flex-wrap items-end gap-2">
        <Select
          aria-label="Period"
          value={source}
          onChange={(event) => setSource(event.target.value)}
          className="w-auto"
        >
          <option value="month">This month</option>
          {periods.data?.map((period) => (
            <option key={period.id} value={period.id}>
              {period.name}
            </option>
          ))}
          <option value="custom">Choose dates</option>
        </Select>
        {source === 'custom' && (
          <>
            <Input
              type="date"
              aria-label="From"
              value={custom.from}
              onChange={(e) => setCustom({ ...custom, from: e.target.value })}
              className="w-40"
            />
            <Input
              type="date"
              aria-label="To"
              value={custom.to}
              onChange={(e) => setCustom({ ...custom, to: e.target.value })}
              className="w-40"
            />
          </>
        )}
        {(groups.data?.length ?? 0) > 0 && (
          <Select
            aria-label="Group"
            value={group}
            onChange={(event) => setGroup(event.target.value)}
            className="w-auto"
          >
            <option value="">All groups</option>
            {groups.data?.map((name) => (
              <option key={name}>{name}</option>
            ))}
          </Select>
        )}
        {periods.data?.length === 0 && (
          <p className="text-sm text-muted">
            Add your terms and sessions in{' '}
            <Link to="/settings?tab=periods" className="font-medium text-ink underline underline-offset-2">
              Settings
            </Link>{' '}
            to report on them in one click.
          </p>
        )}
      </div>

      {!valid && <ErrorNotice error={new Error('Choose a start date on or before the end date.')} />}
      {report.isPending && valid && <Spinner label="Building the report" />}
      {report.isError && <ErrorNotice error={report.error} onRetry={() => void report.refetch()} />}

      {data && data.rows.length === 0 && <EmptyState title="Nobody was expected in this period" />}

      {data && data.rows.length > 0 && (
        <>
          <section className="mb-6 rounded-2xl border border-rule bg-paper px-6 py-5">
            <p className="text-sm text-muted">
              {data.range.label ? `${data.range.label}, ` : ''}
              {formatShortDate(data.range.from)} to {formatShortDate(data.range.to)}
            </p>
            <p className="mt-1 font-display text-xl font-medium text-ink sm:text-2xl">
              {formatPercent(data.totals.attendanceRate)} attendance across{' '}
              {plural(data.totals.members, 'person', 'people')}.
            </p>
            <p className="mt-1 text-muted">
              {plural(data.totals.late, 'late arrival')} and {plural(data.totals.absent, 'absence')} in{' '}
              {plural(data.totals.expected, 'expected day')}.
            </p>
          </section>

          <h2 className="mb-3 text-xl font-semibold">By person</h2>
          <div className="mb-8 overflow-x-auto rounded-2xl border border-rule bg-paper">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-rule text-muted">
                <tr>
                  <th scope="col" className="px-4 py-3 font-medium">
                    Name
                  </th>
                  <th scope="col" className="hidden px-4 py-3 font-medium sm:table-cell">
                    Group
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    Expected
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    On time
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    Late
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    Absent
                  </th>
                  <th scope="col" className="px-4 py-3 text-right font-medium">
                    Attendance
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-rule tabular">
                {data.rows.map((row) => (
                  <tr key={row.memberId}>
                    <td className="px-4 py-2.5">
                      <Link to={`/people/${row.memberId}`} className="font-medium hover:text-ink hover:underline">
                        {row.fullName}
                      </Link>
                    </td>
                    <td className="hidden px-4 py-2.5 text-muted sm:table-cell">{row.group ?? '–'}</td>
                    <td className="px-4 py-2.5 text-right">{row.expected}</td>
                    <td className="px-4 py-2.5 text-right">{row.present}</td>
                    <td className="px-4 py-2.5 text-right">{row.late}</td>
                    <td className={cn('px-4 py-2.5 text-right', row.absent > 0 && 'text-absent')}>{row.absent}</td>
                    <td
                      className={cn(
                        'px-4 py-2.5 text-right font-semibold',
                        row.attendanceRate !== null && row.attendanceRate < LOW_ATTENDANCE && 'text-absent',
                      )}
                    >
                      {formatPercent(row.attendanceRate)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <h2 className="mb-3 text-xl font-semibold">Register</h2>
          {data.dates.length <= MAX_GRID_DAYS ? (
            <RegisterGrid report={data} />
          ) : (
            <p className="text-sm text-muted">
              The on-screen register shows up to {MAX_GRID_DAYS} days. Download Excel for the full {data.dates.length}
              -day grid.
            </p>
          )}
        </>
      )}
    </>
  );
}
