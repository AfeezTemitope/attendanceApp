import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { toast } from 'sonner';
import { attendanceApi, queryKeys } from '@/api/endpoints';
import type { AttendanceStatus, DailyRow } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Dialog } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/cn';

type Choice = AttendanceStatus | 'CLEAR';

const CHOICES: Array<{ value: Choice; label: string }> = [
  { value: 'PRESENT', label: 'On time' },
  { value: 'LATE', label: 'Late' },
  { value: 'CLEAR', label: 'No record' },
];

/** Admin correction for one person on one day: forgot to check in, device was offline, wrong mark. */
export function CorrectDialog({ row, date, onClose }: { row: DailyRow | null; date: string; onClose: () => void }) {
  const queryClient = useQueryClient();
  const current: Choice = row?.status === 'PRESENT' || row?.status === 'LATE' ? row.status : 'CLEAR';
  const [choice, setChoice] = useState<Choice>(current);
  const [time, setTime] = useState('');
  const [note, setNote] = useState('');

  const save = useMutation({
    mutationFn: async () => {
      if (!row) return;
      if (choice === 'CLEAR') {
        if (row.recordId) await attendanceApi.deleteRecord(row.recordId);
        return;
      }
      await attendanceApi.recordManually({
        memberId: row.member.id,
        date,
        status: choice,
        ...(time ? { time } : {}),
        ...(note.trim() ? { note: note.trim() } : {}),
      });
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      await queryClient.invalidateQueries({ queryKey: ['reports'] });
      toast.success(`Saved ${row?.member.fullName}’s attendance`);
      onClose();
    },
  });

  return (
    <Dialog
      open={row !== null}
      onClose={onClose}
      title={row ? `Correct ${row.member.fullName}` : ''}
      description="Changes are recorded as a manual correction."
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={() => save.mutate()} loading={save.isPending}>
            Save correction
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        {save.isError && <ErrorNotice error={save.error} />}
        <fieldset>
          <legend className="mb-2 text-sm font-medium">Mark as</legend>
          <div className="grid grid-cols-3 gap-2">
            {CHOICES.map((option) => (
              <label
                key={option.value}
                className={cn(
                  'cursor-pointer rounded-lg border px-3 py-2 text-center text-sm font-medium has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink',
                  choice === option.value ? 'border-ink bg-ink-wash text-ink' : 'border-rule text-muted',
                )}
              >
                <input
                  type="radio"
                  name="mark"
                  value={option.value}
                  checked={choice === option.value}
                  onChange={() => setChoice(option.value)}
                  className="sr-only"
                />
                {option.label}
              </label>
            ))}
          </div>
        </fieldset>
        {choice !== 'CLEAR' && (
          <>
            <Field label="Arrival time" hint="Optional. Defaults to the opening or late time.">
              <Input type="time" value={time} onChange={(event) => setTime(event.target.value)} />
            </Field>
            <Field label="Note" hint="Optional, e.g. “Signed the paper register”.">
              <Input value={note} maxLength={200} onChange={(event) => setNote(event.target.value)} />
            </Field>
          </>
        )}
      </div>
    </Dialog>
  );
}
