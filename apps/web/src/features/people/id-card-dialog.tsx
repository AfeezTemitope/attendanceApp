import { useMutation, useQueryClient } from '@tanstack/react-query';
import QRCode from 'qrcode';
import { useState } from 'react';
import { membersApi, queryKeys } from '@/api/endpoints';
import type { Member } from '@/api/types';
import { Button } from '@/components/ui/button';
import { Dialog } from '@/components/ui/dialog';
import { ErrorNotice } from '@/components/ui/feedback';
import { useProfile } from '@/features/auth/use-auth';
import { formatShortDate } from '@/lib/format';

/** Issues a QR ID card. The token is shown once; issuing again makes the previous card stop working. */
export function IdCardDialog({ member, onClose }: { member: Member | null; onClose: () => void }) {
  const { organization } = useProfile();
  const queryClient = useQueryClient();
  const [qrImage, setQrImage] = useState<string | null>(null);

  const issue = useMutation({
    mutationFn: async (id: string) => {
      const { qrToken } = await membersApi.issueQrToken(id);
      return QRCode.toDataURL(qrToken, { margin: 1, width: 360, color: { dark: '#1d2b6b', light: '#ffffff' } });
    },
    onSuccess: async (image) => {
      setQrImage(image);
      await queryClient.invalidateQueries({ queryKey: queryKeys.members() });
    },
  });

  const close = () => {
    setQrImage(null);
    issue.reset();
    onClose();
  };

  return (
    <Dialog
      open={member !== null}
      onClose={close}
      title="ID card"
      description={member?.fullName}
      footer={
        qrImage ? (
          <>
            <Button variant="secondary" onClick={close}>
              Close
            </Button>
            <Button onClick={() => window.print()}>Print card</Button>
          </>
        ) : (
          <>
            <Button variant="secondary" onClick={close}>
              Cancel
            </Button>
            <Button onClick={() => member && issue.mutate(member.id)} loading={issue.isPending}>
              {member?.qrIssuedAt ? 'Issue a new card' : 'Issue card'}
            </Button>
          </>
        )
      }
    >
      {issue.isError && <ErrorNotice error={issue.error} />}
      {!qrImage && member && (
        <div className="flex flex-col gap-2 text-sm text-muted">
          <p>The card’s QR code lets {member.fullName} check in by scanning it at a check-in device.</p>
          <p>For security the code is shown only once, so print the card straight away.</p>
          {member.qrIssuedAt && (
            <p className="font-medium text-late">
              A card was issued on {formatShortDate(member.qrIssuedAt.slice(0, 10))}. Issuing a new one stops the old
              card from working.
            </p>
          )}
        </div>
      )}
      {qrImage && member && (
        <div className="print-area mx-auto flex w-72 flex-col items-center rounded-2xl border border-rule bg-paper p-5 text-center">
          <p className="font-display text-sm font-semibold text-ink">{organization.name}</p>
          <img src={qrImage} alt={`QR code for ${member.fullName}`} className="my-3 size-48" />
          <p className="font-display text-xl font-semibold text-ink">{member.fullName}</p>
          <p className="text-sm text-muted">
            {member.group ? `${member.group}, ` : ''}code <span className="tabular">{member.code}</span>
          </p>
        </div>
      )}
    </Dialog>
  );
}
