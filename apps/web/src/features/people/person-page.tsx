import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { ArrowLeft } from 'lucide-react';
import { useState } from 'react';
import { Link, useParams } from 'react-router';
import { calendarApi, membersApi, queryKeys, reportsApi } from '@/api/endpoints';
import { PageHeader } from '@/components/layout/page-header';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Input, Select } from '@/components/ui/input';
import { RegisterMark } from '@/components/ui/register-mark';
import { useCan, useProfile } from '@/features/auth/use-auth';
import { ApiError, errorMessage } from '@/lib/api-error';
import {
  addDays,
  formatDayLabel,
  formatPercent,
  formatShortDate,
  plural,
  startOfMonth,
  timeIn,
  todayIn,
} from '@/lib/format';
import { IdCardDialog } from './id-card-dialog';
import { PersonFormDialog } from './person-form-dialog';

type Preset = 'month' | '30' | 'custom' | `period:${string}`;

export function PersonPage() {
  const { id = '' } = useParams();
  const { organization } = useProfile();
  const canEdit = useCan('ADMIN');
  const today = todayIn(organization.timezone);

  const [preset, setPreset] = useState<Preset>('month');
  const [custom, setCustom] = useState({ from: startOfMonth(today), to: today });
  const [editing, setEditing] = useState(false);
  const [carding, setCarding] = useState(false);
  const queryClient = useQueryClient();

  const member = useQuery({ queryKey: queryKeys.member(id), queryFn: () => membersApi.get(id) });
  const toggleArchive = useMutation({
    mutationFn: (archive: boolean) => (archive ? membersApi.archive(id) : membersApi.update(id, { status: 'ACTIVE' })),
    onSuccess: async (saved) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      toast.success(
        saved.status === 'ARCHIVED'
          ? `Archived ${saved.fullName}. Their history is kept.`
          : `Restored ${saved.fullName}`,
      );
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const periods = useQuery({ queryKey: queryKeys.periods, queryFn: calendarApi.periods });

  const range = (() => {
    if (preset === 'month') return { from: startOfMonth(today), to: today };
    if (preset === '30') return { from: addDays(today, -29), to: today };
    if (preset.startsWith('period:')) {
      const period = periods.data?.find((p) => `period:${p.id}` === preset);
      if (period) return { from: period.startsOn, to: period.endsOn < today ? period.endsOn : today };
    }
    return custom;
  })();

  const history = useQuery({
    queryKey: queryKeys.memberHistory(id, range.from, range.to),
    queryFn: () => reportsApi.member(id, range.from, range.to),
    enabled: range.from <= range.to,
    retry: false,
  });

  if (member.isPending) return <Spinner />;
  if (member.isError) return <ErrorNotice error={member.error} />;
  const person = member.data;
  const summary = history.data?.summary;

  return (
    <>
      <Link to="/people" className="mb-4 inline-flex items-center gap-1.5 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> People
      </Link>
      <PageHeader
        title={person.fullName}
        actions={
          canEdit && (
            <>
              <Button variant="secondary" onClick={() => setEditing(true)}>
                Edit
              </Button>
              {person.status === 'ACTIVE' && (
                <Button variant="secondary" onClick={() => setCarding(true)}>
                  ID card
                </Button>
              )}
              <Button
                variant="secondary"
                loading={toggleArchive.isPending}
                onClick={() => toggleArchive.mutate(person.status === 'ACTIVE')}
              >
                {person.status === 'ACTIVE' ? 'Archive' : 'Restore'}
              </Button>
            </>
          )
        }
      >
        Code <span className="tabular font-medium text-text">{person.code}</span>
        {person.group && <>, {person.group}</>}
        {person.status === 'ARCHIVED' && <>, archived {person.archivedOn && formatShortDate(person.archivedOn)}</>}
      </PageHeader>

      <div className="mb-5 flex flex-wrap items-end gap-2">
        <Select
          aria-label="Period"
          value={preset}
          onChange={(event) => setPreset(event.target.value as Preset)}
          className="w-auto"
        >
          <option value="month">This month</option>
          <option value="30">Last 30 days</option>
          {periods.data?.map((period) => (
            <option key={period.id} value={`period:${period.id}`}>
              {period.name}
            </option>
          ))}
          <option value="custom">Choose dates</option>
        </Select>
        {preset === 'custom' && (
          <>
            <Input
              type="date"
              aria-label="From"
              value={custom.from}
              max={today}
              onChange={(e) => setCustom({ ...custom, from: e.target.value })}
              className="w-40"
            />
            <Input
              type="date"
              aria-label="To"
              value={custom.to}
              max={today}
              onChange={(e) => setCustom({ ...custom, to: e.target.value })}
              className="w-40"
            />
          </>
        )}
      </div>

      {history.isPending && history.fetchStatus !== 'idle' && <Spinner label="Loading attendance" />}
      {history.isError &&
        (history.error instanceof ApiError && history.error.status === 404 ? (
          <EmptyState title="No attendance expected in this period">
            {person.fullName} was not on the register for these dates. They are expected from{' '}
            {formatShortDate(person.joinedOn)}.
          </EmptyState>
        ) : (
          <ErrorNotice error={history.error} onRetry={() => void history.refetch()} />
        ))}

      {history.data && summary && (
        <>
          <section className="mb-6 rounded-2xl border border-rule bg-paper px-6 py-5">
            <p className="font-display text-xl font-medium text-ink sm:text-2xl">
              {summary.expected === 0
                ? 'No working days in this period yet.'
                : `Attended ${summary.attended} of ${plural(summary.expected, 'day')} (${formatPercent(summary.attendanceRate)}).`}
            </p>
            {summary.expected > 0 && (
              <p className="mt-1 text-muted">
                {summary.late} late, {summary.absent} absent.
              </p>
            )}
            <div className="mt-5 flex flex-wrap gap-1" aria-label="Day by day">
              {history.data.dates.map((date, index) => {
                const label = formatDayLabel(date);
                return (
                  <div key={date} className="flex flex-col items-center gap-0.5" title={formatShortDate(date)}>
                    <span className="text-[10px] text-muted">{label.weekday}</span>
                    <RegisterMark mark={summary.marks[index] ?? '-'} />
                    <span className="tabular text-[10px] text-muted">{label.day}</span>
                  </div>
                );
              })}
            </div>
          </section>

          <h2 className="mb-3 text-xl font-semibold">Check-ins</h2>
          {history.data.log.length === 0 ? (
            <p className="text-sm text-muted">No check-ins in this period.</p>
          ) : (
            <div className="overflow-hidden rounded-2xl border border-rule bg-paper">
              <table className="w-full text-left text-sm">
                <thead className="border-b border-rule text-muted">
                  <tr>
                    <th scope="col" className="px-4 py-3 font-medium">
                      Date
                    </th>
                    <th scope="col" className="px-4 py-3 font-medium">
                      Arrived
                    </th>
                    <th scope="col" className="px-4 py-3 font-medium">
                      Left
                    </th>
                    <th scope="col" className="hidden px-4 py-3 font-medium sm:table-cell">
                      How
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-rule">
                  {[...history.data.log].reverse().map((entry) => (
                    <tr key={entry.date}>
                      <td className="px-4 py-3">{formatShortDate(entry.date)}</td>
                      <td className="px-4 py-3 tabular">
                        {timeIn(organization.timezone, entry.checkInAt)}
                        {entry.status === 'LATE' && <span className="ml-2 font-medium text-late">late</span>}
                      </td>
                      <td className="px-4 py-3 tabular text-muted">
                        {entry.checkOutAt ? timeIn(organization.timezone, entry.checkOutAt) : '–'}
                      </td>
                      <td className="hidden px-4 py-3 text-muted sm:table-cell">
                        {entry.method === 'MANUAL' ? 'Corrected by admin' : entry.method === 'QR' ? 'ID card' : 'Code'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}

      {editing && <PersonFormDialog open member={person} onClose={() => setEditing(false)} />}
      <IdCardDialog member={carding ? person : null} onClose={() => setCarding(false)} />
    </>
  );
}
