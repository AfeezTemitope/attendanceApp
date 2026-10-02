import { useMutation, useQuery } from '@tanstack/react-query';
import { Delete, ScanLine, Settings } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import type { ButtonHTMLAttributes } from 'react';
import { Navigate, useNavigate } from 'react-router';
import type { CheckInCredentials } from '@/api/types';
import { Button } from '@/components/ui/button';
import { ConfirmDialog } from '@/components/ui/confirm-dialog';
import { ErrorNotice, Spinner } from '@/components/ui/feedback';
import { cn } from '@/lib/cn';
import { formatLongDate, timeIn, todayIn } from '@/lib/format';
import { kioskApi, kioskClient, kioskTokens } from './kiosk-client';
import { checkInOutcome, checkOutOutcome, errorOutcome, type Outcome } from './outcome';
import { QrScanner } from './qr-scanner';
import { ResultOverlay } from './result-overlay';
import { useNow } from './use-now';
import { windowStatus } from './window-status';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9'] as const;
type Action = 'in' | 'out';

export function KioskPage() {
  const navigate = useNavigate();
  const hasToken = kioskTokens.get() !== null;
  const now = useNow();
  const codeRef = useRef<HTMLInputElement>(null);

  const [code, setCode] = useState('');
  const [pin, setPin] = useState('');
  const [showPin, setShowPin] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [scanning, setScanning] = useState<Action | null>(null);
  const [unpairing, setUnpairing] = useState(false);

  useEffect(() => {
    kioskClient.onUnpaired = () => navigate('/kiosk/pair?removed=1', { replace: true });
    return () => {
      kioskClient.onUnpaired = null;
    };
  }, [navigate]);

  // Re-read the session when the local date changes (new day, holiday) and every few minutes (policy edits).
  const session = useQuery({
    queryKey: ['kiosk-session', now.toISOString().slice(0, 10)],
    queryFn: kioskApi.session,
    enabled: hasToken,
    refetchInterval: 5 * 60_000,
    retry: 1,
  });
  const timeZone = session.data?.organization.timezone ?? 'Africa/Lagos';

  const submit = useMutation({
    mutationFn: ({ action, credentials }: { action: Action; credentials: CheckInCredentials }) =>
      action === 'in'
        ? kioskApi.checkIn(credentials).then((result) => checkInOutcome(result, timeZone))
        : kioskApi.checkOut(credentials).then((result) => checkOutOutcome(result, timeZone)),
    onSuccess: setOutcome,
    onError: (error) => setOutcome(errorOutcome(error, timeZone)),
  });

  const reset = useCallback(() => {
    setOutcome(null);
    setCode('');
    setPin('');
    setShowPin(false);
    codeRef.current?.focus();
  }, []);

  const onScanned = useCallback(
    (token: string) => {
      const action = scanning ?? 'in';
      setScanning(null);
      submit.mutate({ action, credentials: { method: 'QR', token } });
    },
    [scanning, submit],
  );

  if (!hasToken) return <Navigate to="/kiosk/pair" replace />;
  if (session.isPending) return <Spinner label="Starting check-in" className="min-h-screen" />;
  if (session.isError) {
    return (
      <main className="flex min-h-screen items-center justify-center p-8">
        <ErrorNotice error={session.error} onRetry={() => void session.refetch()} />
      </main>
    );
  }

  const info = session.data;
  const localTime = timeIn(timeZone, now);
  const status = windowStatus(info, localTime);
  const normalized = code.trim().toUpperCase();
  const canSubmit = normalized.length >= 3 && (!showPin || /^\d{4,6}$/.test(pin)) && !submit.isPending;

  const send = (action: Action) => {
    if (!canSubmit) return;
    submit.mutate({ action, credentials: { method: 'CODE', code: normalized, ...(showPin && pin ? { pin } : {}) } });
  };

  const press = (key: string) => {
    setCode((current) => (current + key).slice(0, 20));
    codeRef.current?.focus();
  };

  return (
    <main className="grid min-h-screen bg-paper lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)]">
      {/* The clock: the one bold thing on this screen. */}
      <section className="flex flex-col justify-between bg-ink px-8 py-8 text-white sm:px-12 sm:py-10">
        <div>
          <p className="font-display text-2xl font-semibold sm:text-3xl">{info.organization.name}</p>
          <p className="mt-1 text-white/70">{formatLongDate(todayIn(timeZone, now))}</p>
        </div>
        <p
          className="my-8 font-display text-[clamp(6rem,18vw,12rem)] leading-none font-semibold tabular"
          aria-label={`Time ${localTime}`}
        >
          {localTime}
        </p>
        <p
          className={cn(
            'inline-flex items-center gap-3 self-start rounded-full px-4 py-2 text-lg font-medium',
            status.tone === 'open' && 'bg-present text-white',
            status.tone === 'late' && 'bg-late text-white',
            status.tone === 'closed' && 'bg-white/15 text-white',
          )}
        >
          {status.message}
        </p>
      </section>

      <section className="flex flex-col justify-center gap-6 px-6 py-8 sm:px-12">
        <div className="flex items-center justify-between gap-4">
          <h1 className="text-4xl font-semibold">Check in</h1>
          <Button variant="secondary" size="lg" onClick={() => setScanning('in')}>
            <ScanLine className="size-5" aria-hidden />
            Scan ID card
          </Button>
        </div>

        <form
          onSubmit={(event) => {
            event.preventDefault();
            send('in');
          }}
          className="flex flex-col gap-4"
        >
          <label className="flex flex-col gap-2">
            <span className="text-lg text-muted">Your check-in code</span>
            <input
              ref={codeRef}
              autoFocus
              autoComplete="off"
              autoCapitalize="characters"
              spellCheck={false}
              inputMode="text"
              value={code}
              onChange={(event) => setCode(event.target.value.toUpperCase().slice(0, 20))}
              className="h-20 rounded-2xl border-2 border-rule bg-desk px-6 font-display text-5xl tracking-[0.15em] text-ink tabular focus:border-ink focus:outline-none"
            />
          </label>

          {showPin ? (
            <label className="flex flex-col gap-2">
              <span className="text-lg text-muted">PIN</span>
              <input
                type="password"
                inputMode="numeric"
                autoComplete="off"
                maxLength={6}
                value={pin}
                onChange={(event) => setPin(event.target.value.replace(/\D/g, ''))}
                className="h-16 rounded-2xl border-2 border-rule bg-desk px-6 text-3xl tracking-[0.4em] focus:border-ink focus:outline-none"
              />
            </label>
          ) : (
            <button
              type="button"
              onClick={() => setShowPin(true)}
              className="self-start text-lg font-medium text-ink underline underline-offset-4"
            >
              I have a PIN
            </button>
          )}

          <div className="grid grid-cols-3 gap-3" aria-label="Number pad">
            {KEYS.map((key) => (
              <KeypadButton key={key} onClick={() => press(key)}>
                {key}
              </KeypadButton>
            ))}
            <KeypadButton onClick={() => setCode('')} aria-label="Clear">
              <span className="text-xl">Clear</span>
            </KeypadButton>
            <KeypadButton onClick={() => press('0')}>0</KeypadButton>
            <KeypadButton onClick={() => setCode((current) => current.slice(0, -1))} aria-label="Delete last digit">
              <Delete className="size-8" aria-hidden />
            </KeypadButton>
          </div>

          <div className="flex gap-3">
            <Button
              type="submit"
              size="lg"
              disabled={!canSubmit}
              loading={submit.isPending && submit.variables?.action === 'in'}
              className="h-16 flex-1 text-xl"
            >
              Check in
            </Button>
            {info.policy.allowCheckOut && (
              <Button
                variant="secondary"
                size="lg"
                disabled={!canSubmit}
                loading={submit.isPending && submit.variables?.action === 'out'}
                onClick={() => send('out')}
                className="h-16 flex-1 text-xl"
              >
                Check out
              </Button>
            )}
          </div>
        </form>

        <button
          type="button"
          onClick={() => setUnpairing(true)}
          className="inline-flex items-center gap-2 self-end text-sm text-muted hover:text-ink"
        >
          <Settings className="size-4" aria-hidden />
          {info.kiosk.name}
        </button>
      </section>

      {outcome && <ResultOverlay outcome={outcome} onDone={reset} />}
      {scanning && <QrScanner onToken={onScanned} onClose={() => setScanning(null)} />}
      <ConfirmDialog
        open={unpairing}
        title="Unpair this device?"
        confirmLabel="Unpair device"
        destructive
        onConfirm={() => {
          kioskTokens.clear();
          navigate('/kiosk/pair', { replace: true });
        }}
        onClose={() => setUnpairing(false)}
      >
        This device will stop taking check-ins until it is paired again with a new link from Settings, Check-in devices.
      </ConfirmDialog>
    </main>
  );
}

function KeypadButton({ className, ...props }: ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="button"
      className={cn(
        'flex h-16 items-center justify-center rounded-2xl border border-rule bg-paper font-display text-3xl font-medium text-ink transition-colors active:bg-ink-wash sm:h-20',
        className,
      )}
      {...props}
    />
  );
}
