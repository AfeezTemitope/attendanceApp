import { useMutation, useQueryClient } from '@tanstack/react-query';
import { FileUp } from 'lucide-react';
import { useState, type ChangeEvent } from 'react';
import { toast } from 'sonner';
import { membersApi, queryKeys } from '@/api/endpoints';
import type { ImportResult } from '@/api/types';
import { Button } from '@/components/ui/button';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice } from '@/components/ui/feedback';
import { saveText } from '@/lib/download';
import { parsePeopleCsv, TEMPLATE_CSV, type ParsedImport } from './import-csv';

const BATCH = 1_000; // the API accepts up to 1,000 people per request

export function ImportDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const queryClient = useQueryClient();
  const [fileName, setFileName] = useState('');
  const [parsed, setParsed] = useState<ParsedImport | null>(null);
  const [result, setResult] = useState<ImportResult | null>(null);

  const reset = () => {
    setFileName('');
    setParsed(null);
    setResult(null);
    importRows.reset();
  };
  const close = () => {
    reset();
    onClose();
  };

  const importRows = useMutation({
    mutationFn: async (rows: ParsedImport['rows']) => {
      const total: ImportResult = { created: 0, skipped: [] };
      for (let start = 0; start < rows.length; start += BATCH) {
        const batch = rows.slice(start, start + BATCH);
        const outcome = await membersApi.import(batch.map(({ line: _line, ...row }) => row));
        total.created += outcome.created;
        // The API numbers rows within the batch; translate back to spreadsheet lines.
        total.skipped.push(...outcome.skipped.map((skip) => ({ ...skip, row: batch[skip.row - 1]?.line ?? skip.row })));
      }
      return total;
    },
    onSuccess: async (outcome) => {
      setResult(outcome);
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      toast.success(`Imported ${outcome.created} ${outcome.created === 1 ? 'person' : 'people'}`);
    },
  });

  const onFile = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;
    setFileName(file.name);
    setResult(null);
    setParsed(parsePeopleCsv(await file.text()));
  };

  const ready = parsed?.rows.length ?? 0;

  return (
    <Dialog
      open={open}
      onClose={close}
      size="lg"
      title="Import people"
      description="Upload a CSV from Excel or Google Sheets (File → Save as / Download → CSV)."
      footer={
        result ? (
          <Button onClick={close}>Done</Button>
        ) : (
          <>
            <Button variant="secondary" onClick={close}>
              Cancel
            </Button>
            <Button
              disabled={ready === 0}
              loading={importRows.isPending}
              onClick={() => parsed && importRows.mutate(parsed.rows)}
            >
              Import {ready > 0 ? `${ready} ${ready === 1 ? 'person' : 'people'}` : ''}
            </Button>
          </>
        )
      }
    >
      {result ? (
        <div className="flex flex-col gap-3">
          <p className="font-display text-xl text-ink">
            Imported {result.created} {result.created === 1 ? 'person' : 'people'}.
          </p>
          {result.skipped.length > 0 && (
            <>
              <p className="text-sm text-muted">These rows were skipped:</p>
              <ul className="max-h-48 overflow-y-auto rounded-lg border border-rule text-sm">
                {result.skipped.map((skip) => (
                  <li key={`${skip.row}-${skip.fullName}`} className="border-b border-rule px-3 py-2 last:border-0">
                    Line {skip.row}, {skip.fullName}: {skip.reason}
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          {importRows.isError && <ErrorNotice error={importRows.error} />}
          <label className="flex cursor-pointer flex-col items-center gap-2 rounded-xl border-2 border-dashed border-rule px-6 py-8 text-center hover:border-ink-soft has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink">
            <FileUp className="size-6 text-ink" aria-hidden />
            <span className="font-medium text-ink">{fileName || 'Choose a CSV file'}</span>
            <span className="text-sm text-muted">
              Columns: Full name (or Surname + First name), Code, Group, Joined on. Only the name is required.
            </span>
            <input type="file" accept=".csv,text/csv" className="sr-only" onChange={(event) => void onFile(event)} />
          </label>
          <button
            type="button"
            onClick={() => saveText(TEMPLATE_CSV, 'people-template.csv')}
            className="self-start text-sm font-semibold text-ink underline underline-offset-2"
          >
            Download a template
          </button>

          {parsed && (
            <div className="flex flex-col gap-3">
              <p className="text-sm">
                <strong className="tabular">{ready}</strong> ready to import.{' '}
                {parsed.issues.length > 0 && (
                  <span className="text-absent">
                    {parsed.issues.length} {parsed.issues.length === 1 ? 'row needs' : 'rows need'} fixing in the file
                    first.
                  </span>
                )}{' '}
                Codes are generated for anyone without one.
              </p>
              {parsed.issues.length > 0 && (
                <ul className="max-h-36 overflow-y-auto rounded-lg border border-absent/30 bg-absent-wash text-sm text-absent">
                  {parsed.issues.map((issue) => (
                    <li key={issue.line} className="px-3 py-1.5">
                      Line {issue.line}: {issue.message}
                    </li>
                  ))}
                </ul>
              )}
              {ready > 0 && (
                <div className="overflow-x-auto rounded-lg border border-rule">
                  <table className="w-full text-left text-sm">
                    <thead className="bg-desk text-muted">
                      <tr>
                        <th className="px-3 py-2 font-medium">Name</th>
                        <th className="px-3 py-2 font-medium">Code</th>
                        <th className="px-3 py-2 font-medium">Group</th>
                        <th className="px-3 py-2 font-medium">Joined</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-rule">
                      {parsed.rows.slice(0, 6).map((row) => (
                        <tr key={row.line}>
                          <td className="px-3 py-2">{row.fullName}</td>
                          <td className="px-3 py-2 tabular text-muted">{row.code ?? 'auto'}</td>
                          <td className="px-3 py-2 text-muted">{row.group ?? '–'}</td>
                          <td className="px-3 py-2 tabular text-muted">{row.joinedOn ?? 'today'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  {ready > 6 && <p className="px-3 py-2 text-xs text-muted">…and {ready - 6} more</p>}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </Dialog>
  );
}
