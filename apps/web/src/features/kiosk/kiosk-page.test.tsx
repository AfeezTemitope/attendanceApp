import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { KioskSession } from '@/api/types';
import { ApiError } from '@/lib/api-error';
import { renderRoutes } from '@/test/render';
import { KioskPage } from './kiosk-page';

const mocks = vi.hoisted(() => ({
  token: 'kio_test' as string | null,
  session: vi.fn(),
  checkIn: vi.fn(),
  checkOut: vi.fn(),
}));

vi.mock('./kiosk-client', () => ({
  kioskTokens: { get: () => mocks.token, set: vi.fn(), clear: vi.fn() },
  kioskClient: { onUnpaired: null },
  kioskApi: { session: mocks.session, checkIn: mocks.checkIn, checkOut: mocks.checkOut },
}));

const SESSION: KioskSession = {
  kiosk: { id: 'k1', name: 'Main gate' },
  organization: { name: 'Grace High School', timezone: 'Africa/Lagos' },
  today: { date: '2026-09-28', time: '07:40', isWorkday: true, isHoliday: false },
  policy: { kind: 'FIXED_WINDOW', opensAt: '07:00', lateAfter: '08:00', closesAt: '08:30', allowCheckOut: false },
};

const routes = [
  { path: '/kiosk', element: <KioskPage /> },
  { path: '/kiosk/pair', element: <p>Pair this device</p> },
];

describe('kiosk', () => {
  beforeEach(() => {
    mocks.token = 'kio_test';
    mocks.session.mockResolvedValue(SESSION);
  });

  it('checks a person in with the keypad and greets them by first name', async () => {
    mocks.checkIn.mockResolvedValue({
      member: { id: 'm1', fullName: 'Chidi Okeke', group: 'JSS 1' },
      status: 'PRESENT',
      date: '2026-09-28',
      checkInAt: '2026-09-28T06:45:00.000Z',
    });
    const user = userEvent.setup();
    renderRoutes(routes, '/kiosk');

    expect(await screen.findByText('Grace High School')).toBeInTheDocument();
    const checkIn = screen.getByRole('button', { name: 'Check in' });
    expect(checkIn).toBeDisabled();

    for (const digit of ['4', '8', '2', '1']) await user.click(screen.getByRole('button', { name: digit }));
    expect(screen.getByLabelText('Your check-in code')).toHaveValue('4821');
    await user.click(checkIn);

    expect(mocks.checkIn).toHaveBeenCalledWith({ method: 'CODE', code: '4821' });
    expect(await screen.findByText('Welcome, Chidi')).toBeInTheDocument();
    expect(screen.getByText('On time, checked in at 07:45')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Check out' })).not.toBeInTheDocument();
  });

  it('explains a rejected code, sends the PIN when given, and resets when tapped', async () => {
    mocks.checkIn.mockRejectedValue(
      new ApiError(422, 'CHECK_IN_REJECTED', 'Invalid code or PIN', { reason: 'INVALID_CREDENTIALS' }),
    );
    const user = userEvent.setup();
    renderRoutes(routes, '/kiosk');

    await user.type(await screen.findByLabelText('Your check-in code'), 'stf-014');
    await user.click(screen.getByRole('button', { name: 'I have a PIN' }));
    await user.type(screen.getByLabelText('PIN'), '12a34');
    await user.click(screen.getByRole('button', { name: 'Check in' }));

    expect(mocks.checkIn).toHaveBeenCalledWith({ method: 'CODE', code: 'STF-014', pin: '1234' });
    const overlay = await screen.findByText(/don’t recognise that code/);
    await user.click(overlay);
    expect(screen.queryByText(/don’t recognise that code/)).not.toBeInTheDocument();
    expect(screen.getByLabelText('Your check-in code')).toHaveValue('');
  });

  it('sends an unpaired device to the pairing screen', async () => {
    mocks.token = null;
    renderRoutes(routes, '/kiosk');
    expect(await screen.findByText('Pair this device')).toBeInTheDocument();
    expect(mocks.session).not.toHaveBeenCalled();
  });
});
