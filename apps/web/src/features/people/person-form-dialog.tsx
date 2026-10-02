import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useForm, useWatch } from 'react-hook-form';
import { toast } from 'sonner';
import { z } from 'zod';
import { membersApi, queryKeys, type MemberInput } from '@/api/endpoints';
import type { Member } from '@/api/types';
import { Button } from '@/components/ui/button';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input, Select } from '@/components/ui/input';
import { ApiError } from '@/lib/api-error';

const schema = z
  .object({
    fullName: z.string().trim().min(2, 'Enter at least 2 characters').max(120),
    code: z
      .string()
      .trim()
      .toUpperCase()
      .refine((value) => value === '' || /^[A-Z0-9-]{3,20}$/.test(value), '3–20 letters, digits or dashes'),
    group: z.string().trim().max(60),
    joinedOn: z.string(),
    pinAction: z.enum(['KEEP', 'SET', 'REMOVE']),
    pin: z.string(),
  })
  .refine((values) => values.pinAction !== 'SET' || /^\d{4,6}$/.test(values.pin), {
    path: ['pin'],
    message: 'PIN must be 4–6 digits',
  });
type Values = z.infer<typeof schema>;

interface Props {
  open: boolean;
  member?: Member;
  onClose: () => void;
}

export function PersonFormDialog({ open, member, onClose }: Props) {
  const queryClient = useQueryClient();
  const groups = useQuery({ queryKey: queryKeys.groups, queryFn: membersApi.groups, enabled: open });
  const { register, handleSubmit, formState, control, setError, reset } = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: {
      fullName: member?.fullName ?? '',
      code: member?.code ?? '',
      group: member?.group ?? '',
      joinedOn: member?.joinedOn ?? '',
      pinAction: member?.pinSet ? 'KEEP' : 'KEEP',
      pin: '',
    },
  });
  const pinAction = useWatch({ control, name: 'pinAction' });

  const save = useMutation({
    mutationFn: (values: Values) => {
      const body: Partial<MemberInput> = {
        fullName: values.fullName,
        group: values.group || (member ? null : undefined),
        ...(values.code ? { code: values.code } : {}),
        ...(values.joinedOn ? { joinedOn: values.joinedOn } : {}),
        ...(values.pinAction === 'SET' ? { pin: values.pin } : {}),
        ...(values.pinAction === 'REMOVE' ? { pin: null } : {}),
      };
      return member ? membersApi.update(member.id, body) : membersApi.create(body as MemberInput);
    },
    onSuccess: async (saved) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      toast.success(member ? `Saved ${saved.fullName}` : `Added ${saved.fullName} with code ${saved.code}`);
      reset();
      onClose();
    },
    onError: (error) => {
      if (error instanceof ApiError && error.status === 409) setError('code', { message: error.message });
      if (error instanceof ApiError && error.code === 'VALIDATION_ERROR') {
        for (const [path, message] of Object.entries(error.fieldErrors)) {
          if (path in schema.shape) setError(path as keyof Values, { message });
        }
      }
    },
  });

  const onSubmit = handleSubmit((values) => save.mutate(values));
  const showError =
    save.isError &&
    !(save.error instanceof ApiError && (save.error.status === 409 || save.error.code === 'VALIDATION_ERROR'));

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={member ? `Edit ${member.fullName}` : 'Add a person'}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" form="person-form" loading={save.isPending}>
            {member ? 'Save changes' : 'Add person'}
          </Button>
        </>
      }
    >
      <form id="person-form" onSubmit={onSubmit} noValidate className="flex flex-col gap-4">
        {showError && <ErrorNotice error={save.error} />}
        <Field label="Full name" error={formState.errors.fullName?.message}>
          <Input autoFocus {...register('fullName')} />
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Check-in code"
            hint={member ? undefined : 'Leave blank to generate one.'}
            error={formState.errors.code?.message}
          >
            <Input className="tabular uppercase" autoComplete="off" {...register('code')} />
          </Field>
          <Field label="Group" hint="Class, department or team." error={formState.errors.group?.message}>
            <Input list="group-options" autoComplete="off" {...register('group')} />
          </Field>
        </div>
        <datalist id="group-options">
          {groups.data?.map((group) => (
            <option key={group} value={group} />
          ))}
        </datalist>
        <Field
          label="Expected from"
          hint="No absences are counted before this date. Defaults to today."
          error={formState.errors.joinedOn?.message}
        >
          <Input type="date" {...register('joinedOn')} />
        </Field>
        <Field label="PIN" hint="Optional. A PIN stops others from checking in with this person’s code.">
          <Select {...register('pinAction')}>
            <option value="KEEP">{member?.pinSet ? 'Keep current PIN' : 'No PIN'}</option>
            <option value="SET">{member?.pinSet ? 'Set a new PIN' : 'Set a PIN'}</option>
            {member?.pinSet && <option value="REMOVE">Remove PIN</option>}
          </Select>
        </Field>
        {pinAction === 'SET' && (
          <Field label="New PIN" error={formState.errors.pin?.message}>
            <Input type="password" inputMode="numeric" autoComplete="new-password" maxLength={6} {...register('pin')} />
          </Field>
        )}
      </form>
    </Dialog>
  );
}
