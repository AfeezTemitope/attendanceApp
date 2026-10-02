import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Trash2 } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { calendarApi, queryKeys } from '@/api/endpoints';
import type { Holiday, Period, PeriodType } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { useCan, useProfile } from '@/features/auth/use-auth';
import { errorMessage } from '@/lib/api-error';
import { formatLongDate, formatShortDate, todayIn } from '@/lib/format';
import { NIGERIAN_FIXED_HOLIDAYS } from './holidays';
import { SettingsBlock } from './settings-block';

export function HolidaysSection() {
  const { organization } = useProfile();
  const canEdit = useCan('ADMIN');
  const queryClient = useQueryClient();
  const thisYear = Number(todayIn(organization.timezone).slice(0, 4));
  const [year, setYear] = useState(thisYear);
  const [date, setDate] = useState('');
  const [name, setName] = useState('');
  const [removing, setRemoving] = useState<Holiday | null>(null);

  const from = `${year}-01-01`;
  const to = `${year}-12-31`;
  const holidays = useQuery({ queryKey: queryKeys.holidays(from, to), queryFn: () => calendarApi.holidays(from, to) });
  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['holidays'] });
    await queryClient.invalidateQueries({ queryKey: ['attendance'] });
    await queryClient.invalidateQueries({ queryKey: ['reports'] });
  };

  const add = useMutation({
    mutationFn: () => calendarApi.addHoliday({ date, name: name.trim() }),
    onSuccess: async (holiday) => {
      setDate('');
      setName('');
      await refresh();
      toast.success(`Added ${holiday.name}`);
    },
  });

  const addNigerian = useMutation({
    mutationFn: async () => {
      const existing = new Set(holidays.data?.map((holiday) => holiday.date));
      const missing = NIGERIAN_FIXED_HOLIDAYS.filter(([day]) => !existing.has(`${year}-${day}`));
      for (const [day, holidayName] of missing)
        await calendarApi.addHoliday({ date: `${year}-${day}`, name: holidayName });
      return missing.length;
    },
    onSuccess: async (count) => {
      await refresh();
      toast.success(count === 0 ? 'All fixed public holidays are already added' : `Added ${count} public holidays`);
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const remove = useMutation({
    mutationFn: (holiday: Holiday) => calendarApi.removeHoliday(holiday.id),
    onSuccess: async () => {
      setRemoving(null);
      await refresh();
      toast.success('Removed holiday');
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const onSubmit = (event: FormEvent) => {
    event.preventDefault();
    add.mutate();
  };

  return (
    <SettingsBlock title="Holidays" description="Nobody is marked absent on a holiday, and check-in is closed.">
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Select aria-label="Year" value={year} onChange={(e) => setYear(Number(e.target.value))} className="w-28">
          {[thisYear - 1, thisYear, thisYear + 1].map((y) => (
            <option key={y} value={y}>
              {y}
            </option>
          ))}
        </Select>
        {canEdit && organization.timezone === 'Africa/Lagos' && (
          <Button variant="secondary" size="sm" loading={addNigerian.isPending} onClick={() => addNigerian.mutate()}>
            Add Nigeria’s fixed public holidays
          </Button>
        )}
      </div>

      {holidays.isPending && <Spinner />}
      {holidays.isError && <ErrorNotice error={holidays.error} />}
      {holidays.data && (
        <ul className="mb-5 divide-y divide-rule rounded-lg border border-rule">
          {holidays.data.length === 0 && <li className="px-4 py-3 text-sm text-muted">No holidays in {year} yet.</li>}
          {holidays.data.map((holiday) => (
            <li key={holiday.id} className="flex items-center justify-between gap-3 px-4 py-2.5 text-sm">
              <span>
                <span className="font-medium">{holiday.name}</span>
                <span className="ml-2 text-muted">{formatLongDate(holiday.date)}</span>
              </span>
              {canEdit && (
                <Button
                  variant="ghost"
                  size="sm"
                  aria-label={`Remove ${holiday.name}`}
                  onClick={() => setRemoving(holiday)}
                >
                  <Trash2 className="size-4" />
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}

      {canEdit && (
        <form onSubmit={onSubmit} className="flex flex-col gap-3">
          {add.isError && <ErrorNotice error={add.error} />}
          <div className="grid gap-3 sm:grid-cols-[10rem_1fr_auto] sm:items-end">
            <Field label="Date">
              <Input type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
            </Field>
            <Field label="Name">
              <Input
                required
                minLength={2}
                maxLength={80}
                placeholder="e.g. Mid-term break"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </Field>
            <Button type="submit" loading={add.isPending} disabled={!date || name.trim().length < 2}>
              Add holiday
            </Button>
          </div>
        </form>
      )}

      <ConfirmDialog
        open={removing !== null}
        title="Remove this holiday?"
        confirmLabel="Remove holiday"
        destructive
        loading={remove.isPending}
        onConfirm={() => removing && remove.mutate(removing)}
        onClose={() => setRemoving(null)}
      >
        {removing &&
          `${removing.name} on ${formatLongDate(removing.date)} becomes a normal working day again. Anyone who did not check in will count as absent.`}
      </ConfirmDialog>
    </SettingsBlock>
  );
}

const PERIOD_TYPES: Array<{ value: PeriodType; label: string }> = [
  { value: 'TERM', label: 'Term' },
  { value: 'SESSION', label: 'Session' },
  { value: 'MONTH', label: 'Month' },
  { value: 'CUSTOM', label: 'Other' },
];

export function PeriodsSection() {
  const canEdit = useCan('ADMIN');
  const queryClient = useQueryClient();
  const periods = useQuery({ queryKey: queryKeys.periods, queryFn: calendarApi.periods });
  const [editing, setEditing] = useState<Period | 'new' | null>(null);
  const [removing, setRemoving] = useState<Period | null>(null);

  const remove = useMutation({
    mutationFn: (period: Period) => calendarApi.deletePeriod(period.id),
    onSuccess: async () => {
      setRemoving(null);
      await queryClient.invalidateQueries({ queryKey: queryKeys.periods });
      toast.success('Deleted period');
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <SettingsBlock
      title="Terms & periods"
      description="Name your terms, sessions or months once, then report on them in one click."
    >
      {periods.isPending && <Spinner />}
      {periods.isError && <ErrorNotice error={periods.error} />}
      {periods.data && (
        <ul className="mb-5 divide-y divide-rule rounded-lg border border-rule">
          {periods.data.length === 0 && (
            <li className="px-4 py-3 text-sm text-muted">No periods yet, e.g. “1st Term 2026/27”.</li>
          )}
          {periods.data.map((period) => (
            <li key={period.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5 text-sm">
              <span>
                <span className="font-medium">{period.name}</span>
                <span className="ml-2 text-muted">
                  {formatShortDate(period.startsOn)} to {formatShortDate(period.endsOn)}
                </span>
              </span>
              {canEdit && (
                <span className="flex gap-1">
                  <Button variant="ghost" size="sm" onClick={() => setEditing(period)}>
                    Edit<span className="sr-only"> {period.name}</span>
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    aria-label={`Delete ${period.name}`}
                    onClick={() => setRemoving(period)}
                  >
                    <Trash2 className="size-4" />
                  </Button>
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
      {canEdit && <Button onClick={() => setEditing('new')}>Add a period</Button>}

      {editing && <PeriodDialog period={editing === 'new' ? undefined : editing} onClose={() => setEditing(null)} />}
      <ConfirmDialog
        open={removing !== null}
        title="Delete this period?"
        confirmLabel="Delete period"
        destructive
        loading={remove.isPending}
        onConfirm={() => removing && remove.mutate(removing)}
        onClose={() => setRemoving(null)}
      >
        Attendance records are not affected; only the shortcut for reports is removed.
      </ConfirmDialog>
    </SettingsBlock>
  );
}

function PeriodDialog({ period, onClose }: { period?: Period; onClose: () => void }) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState({
    name: period?.name ?? '',
    type: period?.type ?? ('TERM' as PeriodType),
    startsOn: period?.startsOn ?? '',
    endsOn: period?.endsOn ?? '',
  });
  const invalidRange = form.startsOn && form.endsOn && form.startsOn > form.endsOn;

  const save = useMutation({
    mutationFn: () => (period ? calendarApi.updatePeriod(period.id, form) : calendarApi.createPeriod(form)),
    onSuccess: async (saved) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.periods });
      toast.success(`Saved ${saved.name}`);
      onClose();
    },
  });

  return (
    <Dialog
      open
      onClose={onClose}
      title={period ? `Edit ${period.name}` : 'Add a period'}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            type="submit"
            form="period-form"
            loading={save.isPending}
            disabled={form.name.trim().length < 2 || !form.startsOn || !form.endsOn || Boolean(invalidRange)}
          >
            Save period
          </Button>
        </>
      }
    >
      <form
        id="period-form"
        onSubmit={(event) => {
          event.preventDefault();
          save.mutate();
        }}
        className="flex flex-col gap-4"
      >
        {save.isError && <ErrorNotice error={save.error} />}
        <Field label="Name">
          <Input
            autoFocus
            placeholder="1st Term 2026/27"
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
          />
        </Field>
        <Field label="Type">
          <Select value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value as PeriodType })}>
            {PERIOD_TYPES.map((type) => (
              <option key={type.value} value={type.value}>
                {type.label}
              </option>
            ))}
          </Select>
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Starts">
            <Input type="date" value={form.startsOn} onChange={(e) => setForm({ ...form, startsOn: e.target.value })} />
          </Field>
          <Field label="Ends" error={invalidRange ? 'Must be on or after the start date' : undefined}>
            <Input type="date" value={form.endsOn} onChange={(e) => setForm({ ...form, endsOn: e.target.value })} />
          </Field>
        </div>
      </form>
    </Dialog>
  );
}
