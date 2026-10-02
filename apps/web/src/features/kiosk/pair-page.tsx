import { useMutation } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { APP_NAME } from '@/app/brand';
import { Button } from '@/components/ui/button';
import { ErrorNotice } from '@/components/ui/feedback';
import { Field } from '@/components/ui/field';
import { Input } from '@/components/ui/input';
import { ApiError } from '@/lib/api-error';
import { kioskApi, kioskTokens } from './kiosk-client';

/**
 * Pairs this browser as a check-in device. The token arrives in the URL fragment (#token=…),
 * which browsers never send to any server, then moves into storage and out of the address bar.
 */
export function PairPage() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [token, setToken] = useState('');

  const pair = useMutation({
    mutationFn: async (value: string) => {
      kioskTokens.set(value.trim());
      try {
        return await kioskApi.session();
      } catch (error) {
        kioskTokens.clear();
        throw error;
      }
    },
    onSuccess: () => navigate('/kiosk', { replace: true }),
  });

  useEffect(() => {
    const fromLink = new URLSearchParams(window.location.hash.slice(1)).get('token');
    if (fromLink) {
      window.history.replaceState(null, '', window.location.pathname);
      pair.mutate(fromLink);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- run once on load
  }, []);

  const invalid = pair.error instanceof ApiError && pair.error.status === 401;

  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-6 py-10">
      <p className="mb-6 font-display text-2xl font-semibold text-ink">{APP_NAME}</p>
      <div className="w-full max-w-lg rounded-2xl border border-rule bg-paper px-8 py-8">
        <h1 className="text-3xl font-semibold">Set up this check-in device</h1>
        <p className="mt-2 text-muted">
          An admin creates a pairing link in Settings, under Check-in devices. Open the link on this device, or paste it
          below.
        </p>
        {params.get('removed') && (
          <p className="mt-4 rounded-lg bg-late-wash px-3 py-2 text-sm text-late">
            This device was removed by an admin. Pair it again to keep using it.
          </p>
        )}
        <form
          onSubmit={(event) => {
            event.preventDefault();
            const value = token.includes('#token=') ? decodeURIComponent(token.split('#token=')[1] ?? '') : token;
            if (value) pair.mutate(value);
          }}
          className="mt-6 flex flex-col gap-4"
        >
          {pair.isError && (
            <ErrorNotice
              error={
                invalid
                  ? new Error('That link has expired or the device was removed. Ask an admin for a new one.')
                  : pair.error
              }
            />
          )}
          <Field label="Pairing link or device key">
            <Input
              value={token}
              onChange={(event) => setToken(event.target.value)}
              autoComplete="off"
              spellCheck={false}
            />
          </Field>
          <Button type="submit" size="lg" loading={pair.isPending} disabled={!token.trim()}>
            Pair device
          </Button>
        </form>
      </div>
    </main>
  );
}
