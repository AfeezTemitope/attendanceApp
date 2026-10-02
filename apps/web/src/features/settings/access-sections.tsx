import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import QRCode from 'qrcode';
import { useState } from 'react';
import { toast } from 'sonner';
import { kiosksApi, queryKeys, teamApi } from '@/api/endpoints';
import type { Kiosk, Role, Teammate } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { useCan, useProfile } from '@/features/auth/use-auth';
import { ROLE_LABEL } from '@/features/auth/roles';
import { ApiError, errorMessage } from '@/lib/api-error';
import { formatShortDate, relativeTime } from '@/lib/format';
import { pairingLink } from './pairing';
import { SettingsBlock } from './settings-block';

export function DevicesSection() {
  const queryClient = useQueryClient();
  const kiosks = useQuery({ queryKey: queryKeys.kiosks, queryFn: kiosksApi.list });
  const [name, setName] = useState('');
  const [paired, setPaired] = useState<{ name: string; link: string; qr: string } | null>(null);
  const [revoking, setRevoking] = useState<Kiosk | null>(null);

  const create = useMutation({
    mutationFn: async () => {
      const { kiosk, token } = await kiosksApi.create(name.trim());
      const link = pairingLink(token);
      return {
        name: kiosk.name,
        link,
        qr: await QRCode.toDataURL(link, { margin: 1, width: 320, color: { dark: '#1d2b6b' } }),
      };
    },
    onSuccess: async (result) => {
      setName('');
      setPaired(result);
      await queryClient.invalidateQueries({ queryKey: queryKeys.kiosks });
    },
  });

  const revoke = useMutation({
    mutationFn: (kiosk: Kiosk) => kiosksApi.revoke(kiosk.id),
    onSuccess: async () => {
      setRevoking(null);
      await queryClient.invalidateQueries({ queryKey: queryKeys.kiosks });
      toast.success('Device removed. It can no longer check people in.');
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const active = kiosks.data?.filter((kiosk) => !kiosk.revokedAt) ?? [];

  return (
    <SettingsBlock
      title="Check-in devices"
      description="A tablet or phone at the gate or reception where people check in. Each device can only check people in, nothing else."
    >
      {kiosks.isPending && <Spinner />}
      {kiosks.isError && <ErrorNotice error={kiosks.error} />}
      {kiosks.data && (
        <ul className="mb-5 divide-y divide-rule rounded-lg border border-rule">
          {active.length === 0 && <li className="px-4 py-3 text-sm text-muted">No devices yet.</li>}
          {active.map((kiosk) => (
            <li key={kiosk.id} className="flex items-center justify-between gap-3 px-4 py-2.5 text-sm">
              <span>
                <span className="font-medium">{kiosk.name}</span>
                <span className="ml-2 text-muted">Last used {relativeTime(kiosk.lastSeenAt).toLowerCase()}</span>
              </span>
              <Button variant="ghost" size="sm" onClick={() => setRevoking(kiosk)}>
                Remove<span className="sr-only"> {kiosk.name}</span>
              </Button>
            </li>
          ))}
        </ul>
      )}

      <form
        onSubmit={(event) => {
          event.preventDefault();
          create.mutate();
        }}
        className="flex flex-col gap-3"
      >
        {create.isError && <ErrorNotice error={create.error} />}
        <div className="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end">
          <Field label="Device name">
            <Input
              placeholder="e.g. Main gate tablet"
              minLength={2}
              maxLength={80}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </Field>
          <Button type="submit" loading={create.isPending} disabled={name.trim().length < 2}>
            Add device
          </Button>
        </div>
      </form>

      <Dialog
        open={paired !== null}
        onClose={() => setPaired(null)}
        title={`Pair ${paired?.name ?? 'device'}`}
        description="Open this link on the device, or scan the code with its camera. It is shown only once."
        footer={<Button onClick={() => setPaired(null)}>Done</Button>}
      >
        {paired && (
          <div className="flex flex-col items-center gap-4">
            <img src={paired.qr} alt="Pairing QR code" className="size-56" />
            <div className="flex w-full gap-2">
              <Input readOnly value={paired.link} aria-label="Pairing link" onFocus={(e) => e.target.select()} />
              <Button
                variant="secondary"
                onClick={() =>
                  void navigator.clipboard
                    .writeText(paired.link)
                    .then(() => toast.success('Copied pairing link'))
                    .catch(() => toast.error('Copy failed. Select the link and copy it manually.'))
                }
              >
                Copy
              </Button>
            </div>
            <p className="text-sm text-muted">
              Anyone with this link can check people in for your organisation. Share it only with the device.
            </p>
          </div>
        )}
      </Dialog>

      <ConfirmDialog
        open={revoking !== null}
        title={`Remove ${revoking?.name ?? 'device'}?`}
        confirmLabel="Remove device"
        destructive
        loading={revoke.isPending}
        onConfirm={() => revoking && revoke.mutate(revoking)}
        onClose={() => setRevoking(null)}
      >
        The device stops working immediately. Check-ins it already recorded are kept.
      </ConfirmDialog>
    </SettingsBlock>
  );
}

const ROLE_HELP: Record<Role, string> = {
  OWNER: 'Everything, including managing the team',
  ADMIN: 'Manage people, attendance, devices and settings',
  VIEWER: 'See attendance and download reports',
};

export function TeamSection() {
  const { user } = useProfile();
  const isOwner = useCan('OWNER');
  const queryClient = useQueryClient();
  const team = useQuery({ queryKey: queryKeys.team, queryFn: teamApi.list });
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState<Teammate | null>(null);

  const changeRole = useMutation({
    mutationFn: ({ userId, role }: { userId: string; role: Role }) => teamApi.changeRole(userId, role),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.team });
      toast.success('Role updated. It applies within 15 minutes.');
    },
    onError: async (error) => {
      toast.error(errorMessage(error));
      await queryClient.invalidateQueries({ queryKey: queryKeys.team });
    },
  });

  const remove = useMutation({
    mutationFn: (mate: Teammate) => teamApi.remove(mate.userId),
    onSuccess: async () => {
      setRemoving(null);
      await queryClient.invalidateQueries({ queryKey: queryKeys.team });
      toast.success('Removed from the team');
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <SettingsBlock title="Team" description="People who can sign in to this dashboard.">
      {team.isPending && <Spinner />}
      {team.isError && <ErrorNotice error={team.error} />}
      {team.data && (
        <ul className="mb-5 divide-y divide-rule rounded-lg border border-rule">
          {team.data.map((mate) => (
            <li key={mate.userId} className="flex flex-wrap items-center justify-between gap-3 px-4 py-3 text-sm">
              <span className="min-w-0">
                <span className="block font-medium">
                  {mate.name}
                  {mate.userId === user.id && <span className="ml-1 text-muted">(you)</span>}
                </span>
                <span className="block truncate text-muted">
                  {mate.email}, added {formatShortDate(mate.addedAt.slice(0, 10))}
                </span>
              </span>
              <span className="flex items-center gap-1">
                {isOwner ? (
                  <Select
                    aria-label={`Role for ${mate.name}`}
                    value={mate.role}
                    onChange={(e) => changeRole.mutate({ userId: mate.userId, role: e.target.value as Role })}
                    className="h-8 w-auto"
                  >
                    {(Object.keys(ROLE_LABEL) as Role[]).map((role) => (
                      <option key={role} value={role}>
                        {ROLE_LABEL[role]}
                      </option>
                    ))}
                  </Select>
                ) : (
                  <span className="text-muted">{ROLE_LABEL[mate.role]}</span>
                )}
                {isOwner && mate.userId !== user.id && (
                  <Button variant="ghost" size="sm" onClick={() => setRemoving(mate)}>
                    Remove<span className="sr-only"> {mate.name}</span>
                  </Button>
                )}
              </span>
            </li>
          ))}
        </ul>
      )}
      <Button onClick={() => setAdding(true)}>Add a teammate</Button>

      {adding && <AddTeammateDialog canAddOwner={isOwner} onClose={() => setAdding(false)} />}
      <ConfirmDialog
        open={removing !== null}
        title={`Remove ${removing?.name ?? 'teammate'}?`}
        confirmLabel="Remove"
        destructive
        loading={remove.isPending}
        onConfirm={() => removing && remove.mutate(removing)}
        onClose={() => setRemoving(null)}
      >
        They are signed out and can no longer open this organisation’s register.
      </ConfirmDialog>
    </SettingsBlock>
  );
}

function AddTeammateDialog({ canAddOwner, onClose }: { canAddOwner: boolean; onClose: () => void }) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState({ email: '', role: 'ADMIN' as Role, name: '', temporaryPassword: '' });
  const [needsAccount, setNeedsAccount] = useState(false);

  const add = useMutation({
    mutationFn: () =>
      teamApi.add({
        email: form.email.trim(),
        role: form.role,
        ...(form.name.trim() ? { name: form.name.trim() } : {}),
        ...(form.temporaryPassword ? { temporaryPassword: form.temporaryPassword } : {}),
      }),
    onSuccess: async (mate) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.team });
      toast.success(`Added ${mate.name} as ${ROLE_LABEL[mate.role].toLowerCase()}`);
      onClose();
    },
    onError: (error) => {
      // The API asks for a name and password only when the email has no account yet.
      if (error instanceof ApiError && error.code === 'VALIDATION_ERROR' && !Array.isArray(error.details))
        setNeedsAccount(true);
    },
  });

  return (
    <Dialog
      open
      onClose={onClose}
      title="Add a teammate"
      description="They sign in with their email. Share any temporary password privately."
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" form="teammate-form" loading={add.isPending} disabled={!form.email.includes('@')}>
            Add teammate
          </Button>
        </>
      }
    >
      <form
        id="teammate-form"
        onSubmit={(event) => {
          event.preventDefault();
          add.mutate();
        }}
        className="flex flex-col gap-4"
      >
        {add.isError && !needsAccount && <ErrorNotice error={add.error} />}
        <Field label="Email">
          <Input
            type="email"
            autoFocus
            value={form.email}
            onChange={(e) => setForm({ ...form, email: e.target.value })}
          />
        </Field>
        <Field label="Role" hint={ROLE_HELP[form.role]}>
          <Select value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value as Role })}>
            {canAddOwner && <option value="OWNER">Owner</option>}
            <option value="ADMIN">Admin</option>
            <option value="VIEWER">Viewer</option>
          </Select>
        </Field>
        {needsAccount && (
          <>
            <p className="rounded-lg bg-late-wash px-3 py-2 text-sm text-late">
              This email has no account yet. Add their name and a temporary password.
            </p>
            <Field label="Their full name">
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            </Field>
            <Field label="Temporary password" hint="At least 8 characters.">
              <Input
                type="text"
                autoComplete="off"
                value={form.temporaryPassword}
                onChange={(e) => setForm({ ...form, temporaryPassword: e.target.value })}
              />
            </Field>
          </>
        )}
      </form>
    </Dialog>
  );
}
