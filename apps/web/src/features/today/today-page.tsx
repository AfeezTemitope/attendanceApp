import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, ChevronRight, Search } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { attendanceApi, queryKeys } from '@/api/endpoints';
import type { DailyRow, DailyStatus } from '@/api/types';
import { PageHeader } from '@/components/layout/page-header';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Input, Select } from '@/components/ui/input';
import { StatusPill } from '@/components/ui/status-pill';
import { useCan, useProfile } from '@/features/auth/use-auth';
import { addDays, formatLongDate, timeIn, todayIn } from '@/lib/format';
import { CorrectDialog } from './correct-dialog';
import { SegmentBar } from './segment-bar';
import { summarizeDay } from './today-summary';

type Filter = 'ALL' | 'IN' | 'LATE' | 'OUT';

const FILTERS: Record<Filter, (status: DailyStatus) => boolean> = {
  ALL: () => true,
  IN: (status) => status === 'PRESENT' || status === 'LATE',
  LATE: (status) => status === 'LATE',
  OUT: (status) => status === 'ABSENT' || status === 'NOT_CHECKED_IN',
};

export function TodayPage() {
  const { organization } = useProfile();
  const canCorrect = useCan('ADMIN');
  const showLeft = organization.policy.allowCheckOut;
  const today = todayIn(organization.timezone);
  const [params, setParams] = useSearchParams();
  const date = params.get('date') ?? today;

  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<Filter>('ALL');
  const [group, setGroup] = useState('');
  const [correcting, setCorrecting] = useState<DailyRow | null>(null);

  const daily = useQuery({
    queryKey: queryKeys.daily(date),
    queryFn: () => attendanceApi.daily(date === today ? undefined : date),
    refetchInterval: date === today ? 30_000 : false, // live board while the day is in progress
  });

  const goTo = (next: string) => setParams(next === today ? {} : { date: next }, { replace: true });

  const groups = useMemo(
    () =>
      [
        ...new Set((daily.data?.rows ?? []).map((row) => row.member.group).filter((g): g is string => Boolean(g))),
      ].sort(),
    [daily.data],
  );

  const rows = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return (daily.data?.rows ?? []).filter(
      (row) =>
        FILTERS[filter](row.status) &&
        (!group || row.member.group === group) &&
        (!needle ||
          row.member.fullName.toLowerCase().includes(needle) ||
          row.member.code.toLowerCase().includes(needle)),
    );
  }, [daily.data, search, filter, group]);

  return (
    <>
      <PageHeader
        title={date === today ? 'Today' : 'Register'}
        actions={
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="sm" aria-label="Previous day" onClick={() => goTo(addDays(date, -1))}>
              <ChevronLeft className="size-4" />
            </Button>
            <Input
              type="date"
              aria-label="Choose a date"
              value={date}
              max={today}
              onChange={(event) => event.target.value && goTo(event.target.value)}
              className="h-8 w-40"
            />
            <Button
              variant="ghost"
              size="sm"
              aria-label="Next day"
              disabled={date >= today}
              onClick={() => goTo(addDays(date, 1))}
            >
              <ChevronRight className="size-4" />
            </Button>
            {date !== today && (
              <Button variant="secondary" size="sm" onClick={() => goTo(today)}>
                Back to today
              </Button>
            )}
          </div>
        }
      >
        {formatLongDate(date)}
      </PageHeader>

      {daily.isPending && <Spinner label="Loading the register" />}
      {daily.isError && <ErrorNotice error={daily.error} onRetry={() => void daily.refetch()} />}

      {daily.data && (
        <>
          <section aria-label="Summary" className="mb-6 rounded-2xl border border-rule bg-paper px-6 py-5">
            <p className="font-display text-xl font-medium text-ink sm:text-2xl">{summarizeDay(daily.data)}</p>
            <div className="mt-4">
              <SegmentBar totals={daily.data.totals} />
            </div>
          </section>

          {daily.data.rows.length === 0 ? (
            <EmptyState
              title="No one on the register yet"
              action={
                <Link to="/people" className="font-semibold text-ink underline underline-offset-4">
                  Add people
                </Link>
              }
            >
              People you add appear here every working day.
            </EmptyState>
          ) : (
            <section aria-label="Register">
              <div className="mb-3 flex flex-wrap gap-2">
                <div className="relative min-w-48 flex-1">
                  <Search
                    className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted"
                    aria-hidden
                  />
                  <Input
                    type="search"
                    placeholder="Search name or code"
                    aria-label="Search name or code"
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                    className="pl-9"
                  />
                </div>
                <Select
                  aria-label="Show"
                  value={filter}
                  onChange={(event) => setFilter(event.target.value as Filter)}
                  className="w-auto"
                >
                  <option value="ALL">Everyone</option>
                  <option value="IN">Checked in</option>
                  <option value="LATE">Late</option>
                  <option value="OUT">{daily.data.isToday ? 'Not in yet' : 'Absent'}</option>
                </Select>
                {groups.length > 0 && (
                  <Select
                    aria-label="Group"
                    value={group}
                    onChange={(event) => setGroup(event.target.value)}
                    className="w-auto"
                  >
                    <option value="">All groups</option>
                    {groups.map((name) => (
                      <option key={name}>{name}</option>
                    ))}
                  </Select>
                )}
              </div>

              <div className="overflow-hidden rounded-2xl border border-rule bg-paper">
                <table className="w-full text-left text-sm">
                  <thead className="border-b border-rule text-muted">
                    <tr>
                      <th scope="col" className="px-4 py-3 font-medium">
                        Name
                      </th>
                      <th scope="col" className="hidden px-4 py-3 font-medium sm:table-cell">
                        Group
                      </th>
                      <th scope="col" className="px-4 py-3 font-medium">
                        Status
                      </th>
                      {showLeft && (
                        <th scope="col" className="hidden px-4 py-3 font-medium md:table-cell">
                          Left
                        </th>
                      )}
                      {canCorrect && (
                        <th scope="col" className="w-0 px-4 py-3">
                          <span className="sr-only">Actions</span>
                        </th>
                      )}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-rule">
                    {rows.map((row) => (
                      <tr key={row.member.id} className="hover:bg-desk/60">
                        <td className="px-4 py-3">
                          <Link
                            to={`/people/${row.member.id}`}
                            className="font-medium text-text hover:text-ink hover:underline"
                          >
                            {row.member.fullName}
                          </Link>
                          <span className="ml-2 tabular text-xs text-muted">{row.member.code}</span>
                        </td>
                        <td className="hidden px-4 py-3 text-muted sm:table-cell">{row.member.group ?? '–'}</td>
                        <td className="px-4 py-3">
                          <StatusPill
                            status={row.status}
                            time={row.checkInAt ? timeIn(organization.timezone, row.checkInAt) : null}
                          />
                        </td>
                        {showLeft && (
                          <td className="hidden px-4 py-3 tabular text-muted md:table-cell">
                            {row.checkOutAt ? timeIn(organization.timezone, row.checkOutAt) : '–'}
                          </td>
                        )}
                        {canCorrect && (
                          <td className="px-4 py-3 text-right">
                            {row.status !== 'HOLIDAY' && row.status !== 'NON_WORKDAY' && (
                              <Button variant="ghost" size="sm" onClick={() => setCorrecting(row)}>
                                Correct<span className="sr-only"> {row.member.fullName}</span>
                              </Button>
                            )}
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
                {rows.length === 0 && <p className="px-4 py-6 text-sm text-muted">Nobody matches these filters.</p>}
              </div>
            </section>
          )}
        </>
      )}

      {correcting && (
        <CorrectDialog key={correcting.member.id} row={correcting} date={date} onClose={() => setCorrecting(null)} />
      )}
    </>
  );
}
