import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { organizationApi } from '@/api/endpoints';
import type { Policy, PolicyKind } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { useAuth, useCan, useProfile } from '@/features/auth/use-auth';
import { cn } from '@/lib/cn';
import { WEEKDAYS } from '@/lib/format';
import { timeZones } from '@/lib/time-zones';
import { validatePolicy } from './policy';
import { SettingsBlock } from './settings-block';

export function OrganizationSection() {
  const { organization } = useProfile();
  const { reloadProfile } = useAuth();
  const canEdit = useCan('ADMIN');
  const [name, setName] = useState(organization.name);
  const [timezone, setTimezone] = useState(organization.timezone);

  const save = useMutation({
    mutationFn: () => organizationApi.update({ name: name.trim(), timezone }),
    onSuccess: async () => {
      await reloadProfile();
      toast.success('Saved organisation details');
    },
  });

  const onSubmit = (event: FormEvent) => {
    event.preventDefault();
    save.mutate();
  };

  return (
    <SettingsBlock
      title="Organisation"
      description={`Registered as a ${organization.type === 'SCHOOL' ? 'school' : 'company'}.`}
    >
      <form onSubmit={onSubmit} className="flex flex-col gap-4">
        {save.isError && <ErrorNotice error={save.error} />}
        <Field label="Name">
          <Input
            value={name}
            disabled={!canEdit}
            minLength={2}
            maxLength={120}
            onChange={(e) => setName(e.target.value)}
          />
        </Field>
        <Field label="Timezone" hint="Check-in times, late marks and dates all use this timezone.">
          <Select value={timezone} disabled={!canEdit} onChange={(e) => setTimezone(e.target.value)}>
            {timeZones().map((zone) => (
              <option key={zone} value={zone}>
                {zone.replaceAll('_', ' ')}
              </option>
            ))}
          </Select>
        </Field>
        {canEdit && (
          <Button type="submit" className="self-start" loading={save.isPending} disabled={name.trim().length < 2}>
            Save changes
          </Button>
        )}
      </form>
    </SettingsBlock>
  );
}

const KINDS: Array<{ value: PolicyKind; title: string; detail: string }> = [
  { value: 'FIXED_WINDOW', title: 'Fixed window', detail: 'Check-in closes at a set time. Suits schools and shifts.' },
  { value: 'FLEXIBLE_HOURS', title: 'Flexible hours', detail: 'Check in any time after opening. Suits offices.' },
];

export function PolicySection() {
  const { organization } = useProfile();
  const { reloadProfile } = useAuth();
  const queryClient = useQueryClient();
  const canEdit = useCan('ADMIN');
  const [policy, setPolicy] = useState<Policy>({
    ...organization.policy,
    closesAt: organization.policy.closesAt ?? '08:30',
  });
  const problem = validatePolicy(policy);

  const save = useMutation({
    mutationFn: () => {
      const { closesAt, ...rest } = policy;
      return organizationApi.updatePolicy(policy.kind === 'FIXED_WINDOW' ? { ...rest, closesAt } : rest);
    },
    onSuccess: async () => {
      await reloadProfile();
      await queryClient.invalidateQueries({ queryKey: ['attendance'] });
      await queryClient.invalidateQueries({ queryKey: ['reports'] });
      toast.success('Saved attendance rules');
    },
  });

  const set = <K extends keyof Policy>(key: K, value: Policy[K]) =>
    setPolicy((current) => ({ ...current, [key]: value }));
  const toggleDay = (day: number) =>
    set(
      'workDays',
      policy.workDays.includes(day) ? policy.workDays.filter((d) => d !== day) : [...policy.workDays, day].sort(),
    );

  return (
    <SettingsBlock
      title="Attendance rules"
      description={`All times are in ${organization.timezone.replaceAll('_', ' ')}.`}
    >
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (!problem) save.mutate();
        }}
        className="flex flex-col gap-5"
      >
        {save.isError && <ErrorNotice error={save.error} />}
        <fieldset disabled={!canEdit} className="grid gap-2 sm:grid-cols-2">
          <legend className="mb-2 text-sm font-medium">How check-in works</legend>
          {KINDS.map((kind) => (
            <label
              key={kind.value}
              className={cn(
                'cursor-pointer rounded-lg border px-3 py-2.5 has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink',
                policy.kind === kind.value ? 'border-ink bg-ink-wash' : 'border-rule',
              )}
            >
              <input
                type="radio"
                name="kind"
                className="sr-only"
                checked={policy.kind === kind.value}
                onChange={() => set('kind', kind.value)}
              />
              <span className="block font-semibold text-ink">{kind.title}</span>
              <span className="block text-xs text-muted">{kind.detail}</span>
            </label>
          ))}
        </fieldset>

        <fieldset disabled={!canEdit}>
          <legend className="mb-2 text-sm font-medium">Working days</legend>
          <div className="flex flex-wrap gap-1.5">
            {WEEKDAYS.map((day) => {
              const on = policy.workDays.includes(day.value);
              return (
                <label
                  key={day.value}
                  className={cn(
                    'cursor-pointer rounded-lg border px-3 py-1.5 text-sm font-medium has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink',
                    on ? 'border-ink bg-ink text-white' : 'border-rule text-muted',
                  )}
                >
                  <input
                    type="checkbox"
                    className="sr-only"
                    checked={on}
                    onChange={() => toggleDay(day.value)}
                    aria-label={day.long}
                  />
                  {day.short}
                </label>
              );
            })}
          </div>
        </fieldset>

        <div className="grid gap-4 sm:grid-cols-3">
          <Field label="Opens at">
            <Input
              type="time"
              disabled={!canEdit}
              value={policy.opensAt}
              onChange={(e) => set('opensAt', e.target.value)}
            />
          </Field>
          <Field label="Late after" hint="On time up to this minute.">
            <Input
              type="time"
              disabled={!canEdit}
              value={policy.lateAfter}
              onChange={(e) => set('lateAfter', e.target.value)}
            />
          </Field>
          {policy.kind === 'FIXED_WINDOW' && (
            <Field label="Closes at" hint="No check-ins after this.">
              <Input
                type="time"
                disabled={!canEdit}
                value={policy.closesAt ?? ''}
                onChange={(e) => set('closesAt', e.target.value)}
              />
            </Field>
          )}
        </div>

        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            disabled={!canEdit}
            checked={policy.allowCheckOut}
            onChange={(e) => set('allowCheckOut', e.target.checked)}
            className="size-4 accent-[var(--color-ink)]"
          />
          Record check-out times too
        </label>

        {problem && <p className="text-sm text-absent">{problem}</p>}
        {canEdit && (
          <Button type="submit" className="self-start" loading={save.isPending} disabled={problem !== null}>
            Save rules
          </Button>
        )}
      </form>
    </SettingsBlock>
  );
}
