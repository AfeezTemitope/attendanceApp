import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { KeyRound, QrCode, Search, Upload, UserPlus } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { toast } from 'sonner';
import { membersApi, queryKeys, type MemberQuery } from '@/api/endpoints';
import type { Member, MemberStatus } from '@/api/types';
import { PageHeader } from '@/components/layout/page-header';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorNotice, Spinner } from '@/components/ui/feedback';
import { Input, Select } from '@/components/ui/input';
import { useCan } from '@/features/auth/use-auth';
import { errorMessage } from '@/lib/api-error';
import { formatShortDate } from '@/lib/format';
import { IdCardDialog } from './id-card-dialog';
import { ImportDialog } from './import-dialog';
import { PersonFormDialog } from './person-form-dialog';

const PAGE_SIZE = 50;

export function PeoplePage() {
  const canEdit = useCan('ADMIN');
  const queryClient = useQueryClient();
  const [params, setParams] = useSearchParams();
  const query: MemberQuery = {
    search: params.get('search') ?? undefined,
    group: params.get('group') ?? undefined,
    status: (params.get('status') as MemberStatus | 'ALL' | null) ?? 'ACTIVE',
    page: Number(params.get('page') ?? 1),
    limit: PAGE_SIZE,
  };

  const [searchDraft, setSearchDraft] = useState(query.search ?? '');
  const [editing, setEditing] = useState<Member | 'new' | null>(null);
  const [carding, setCarding] = useState<Member | null>(null);
  const [importing, setImporting] = useState(false);

  const update = (changes: Record<string, string | undefined>) => {
    const next = new URLSearchParams(params);
    for (const [key, value] of Object.entries(changes)) {
      if (value) next.set(key, value);
      else next.delete(key);
    }
    if (!('page' in changes)) next.delete('page');
    setParams(next, { replace: true });
  };

  // Debounce typing so the list is not re-queried on every keystroke.
  useEffect(() => {
    const timer = setTimeout(() => {
      if ((query.search ?? '') !== searchDraft.trim()) update({ search: searchDraft.trim() || undefined });
    }, 300);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only react to typing
  }, [searchDraft]);

  const list = useQuery({
    queryKey: queryKeys.members(query),
    queryFn: () => membersApi.list(query),
    placeholderData: keepPreviousData,
  });
  const groups = useQuery({ queryKey: queryKeys.groups, queryFn: membersApi.groups });

  const toggleArchive = useMutation({
    mutationFn: (member: Member) =>
      member.status === 'ACTIVE' ? membersApi.archive(member.id) : membersApi.update(member.id, { status: 'ACTIVE' }),
    onSuccess: async (member) => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
      await queryClient.invalidateQueries({ queryKey: queryKeys.attendance });
      toast.success(
        member.status === 'ARCHIVED'
          ? `Archived ${member.fullName}. Their history is kept.`
          : `Restored ${member.fullName}`,
      );
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const meta = list.data?.meta;
  const people = list.data?.data ?? [];
  const firstShown = meta ? (meta.page - 1) * meta.limit + 1 : 0;

  return (
    <>
      <PageHeader
        title="People"
        actions={
          canEdit && (
            <>
              <Button variant="secondary" onClick={() => setImporting(true)}>
                <Upload className="size-4" aria-hidden />
                Import CSV
              </Button>
              <Button onClick={() => setEditing('new')}>
                <UserPlus className="size-4" aria-hidden />
                Add person
              </Button>
            </>
          )
        }
      >
        Everyone whose attendance you take: students, teachers, staff.
      </PageHeader>

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
            value={searchDraft}
            onChange={(event) => setSearchDraft(event.target.value)}
            className="pl-9"
          />
        </div>
        <Select
          aria-label="Group"
          value={query.group ?? ''}
          onChange={(event) => update({ group: event.target.value || undefined })}
          className="w-auto"
        >
          <option value="">All groups</option>
          {groups.data?.map((group) => (
            <option key={group}>{group}</option>
          ))}
        </Select>
        <Select
          aria-label="Status"
          value={query.status}
          onChange={(event) => update({ status: event.target.value === 'ACTIVE' ? undefined : event.target.value })}
          className="w-auto"
        >
          <option value="ACTIVE">Active</option>
          <option value="ARCHIVED">Archived</option>
          <option value="ALL">Everyone</option>
        </Select>
      </div>

      {list.isPending && <Spinner label="Loading people" />}
      {list.isError && <ErrorNotice error={list.error} onRetry={() => void list.refetch()} />}

      {list.data &&
        people.length === 0 &&
        (query.search || query.group || query.status !== 'ACTIVE' ? (
          <EmptyState title="Nobody matches these filters" />
        ) : (
          <EmptyState
            title="Add the people you take attendance for"
            action={
              canEdit && (
                <div className="flex gap-2">
                  <Button onClick={() => setImporting(true)}>Import a CSV</Button>
                  <Button variant="secondary" onClick={() => setEditing('new')}>
                    Add one person
                  </Button>
                </div>
              )
            }
          >
            Import your class lists or staff list from Excel, or add people one at a time. Everyone gets a check-in
            code.
          </EmptyState>
        ))}

      {people.length > 0 && (
        <div className="overflow-hidden rounded-2xl border border-rule bg-paper">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-rule text-muted">
              <tr>
                <th scope="col" className="px-4 py-3 font-medium">
                  Name
                </th>
                <th scope="col" className="px-4 py-3 font-medium">
                  Code
                </th>
                <th scope="col" className="hidden px-4 py-3 font-medium sm:table-cell">
                  Group
                </th>
                <th scope="col" className="hidden px-4 py-3 font-medium md:table-cell">
                  Expected from
                </th>
                {canEdit && (
                  <th scope="col" className="w-0 px-4 py-3">
                    <span className="sr-only">Actions</span>
                  </th>
                )}
              </tr>
            </thead>
            <tbody className="divide-y divide-rule">
              {people.map((member) => (
                <tr key={member.id} className={member.status === 'ARCHIVED' ? 'text-muted' : undefined}>
                  <td className="px-4 py-3">
                    <Link to={`/people/${member.id}`} className="font-medium hover:text-ink hover:underline">
                      {member.fullName}
                    </Link>
                    {member.status === 'ARCHIVED' && <span className="ml-2 text-xs">archived</span>}
                    <span className="ml-2 inline-flex gap-1 align-middle text-muted">
                      {member.pinSet && <KeyRound className="size-3.5" aria-label="Has a PIN" />}
                      {member.qrIssuedAt && <QrCode className="size-3.5" aria-label="Has an ID card" />}
                    </span>
                  </td>
                  <td className="px-4 py-3 tabular">{member.code}</td>
                  <td className="hidden px-4 py-3 text-muted sm:table-cell">{member.group ?? '–'}</td>
                  <td className="hidden px-4 py-3 text-muted md:table-cell">{formatShortDate(member.joinedOn)}</td>
                  {canEdit && (
                    <td className="px-2 py-2">
                      <div className="flex justify-end">
                        <Button variant="ghost" size="sm" onClick={() => setEditing(member)}>
                          Edit<span className="sr-only"> {member.fullName}</span>
                        </Button>
                        {member.status === 'ACTIVE' && (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="hidden sm:inline-flex"
                            onClick={() => setCarding(member)}
                          >
                            ID card<span className="sr-only"> for {member.fullName}</span>
                          </Button>
                        )}
                        <Button
                          variant="ghost"
                          size="sm"
                          className="hidden sm:inline-flex"
                          onClick={() => toggleArchive.mutate(member)}
                        >
                          {member.status === 'ACTIVE' ? 'Archive' : 'Restore'}
                          <span className="sr-only"> {member.fullName}</span>
                        </Button>
                      </div>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
          {meta && meta.totalPages > 1 && (
            <nav
              aria-label="Pages"
              className="flex items-center justify-between border-t border-rule px-4 py-3 text-sm text-muted"
            >
              <span className="tabular">
                {firstShown}–{firstShown + people.length - 1} of {meta.total}
              </span>
              <div className="flex gap-2">
                <Button
                  variant="secondary"
                  size="sm"
                  disabled={meta.page <= 1}
                  onClick={() => update({ page: String(meta.page - 1) })}
                >
                  Previous
                </Button>
                <Button
                  variant="secondary"
                  size="sm"
                  disabled={meta.page >= meta.totalPages}
                  onClick={() => update({ page: String(meta.page + 1) })}
                >
                  Next
                </Button>
              </div>
            </nav>
          )}
        </div>
      )}

      {editing && (
        <PersonFormDialog
          key={editing === 'new' ? 'new' : editing.id}
          open
          member={editing === 'new' ? undefined : editing}
          onClose={() => setEditing(null)}
        />
      )}
      <IdCardDialog member={carding} onClose={() => setCarding(null)} />
      <ImportDialog open={importing} onClose={() => setImporting(false)} />
    </>
  );
}
