import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '@/api/client';
import { routes } from '@/app/router';
import { fakeFetch, json } from '@/test/fake-fetch';
import { renderRoutes } from '@/test/render';
import { todayIn } from '@/lib/format';

const session = {
  accessToken: 'access-1',
  expiresIn: 900,
  user: { id: 'u1', name: 'Ada Obi', email: 'ada@school.ng' },
  role: 'OWNER',
  organizations: [{ id: 'o1', name: 'Grace High School', role: 'OWNER' }],
  organization: {
    id: 'o1',
    name: 'Grace High School',
    slug: 'grace-high-school',
    type: 'SCHOOL',
    timezone: 'Africa/Lagos',
    createdAt: '2026-09-01T00:00:00.000Z',
    policy: {
      kind: 'FIXED_WINDOW',
      workDays: [1, 2, 3, 4, 5],
      opensAt: '07:00',
      lateAfter: '08:00',
      closesAt: '08:30',
      allowCheckOut: false,
    },
  },
};

const daily = {
  date: todayIn('Africa/Lagos'),
  isToday: true,
  isWorkday: true,
  holiday: null,
  totals: { expected: 2, present: 1, late: 0, absent: 0, notCheckedIn: 1 },
  rows: [
    {
      member: { id: 'm1', fullName: 'Chidi Okeke', code: '4821', group: 'JSS 1' },
      status: 'PRESENT',
      recordId: 'r1',
      checkInAt: '2026-09-28T06:45:00.000Z',
      checkOutAt: null,
      method: 'CODE',
    },
    {
      member: { id: 'm2', fullName: 'Bola Ade', code: '7310', group: 'JSS 1' },
      status: 'NOT_CHECKED_IN',
      recordId: null,
      checkInAt: null,
      checkOutAt: null,
      method: null,
    },
  ],
};

describe('signing in', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'fetch',
      fakeFetch({
        'POST /auth/refresh': () => json(401, { error: { code: 'UNAUTHORIZED', message: 'No session' } }),
        'POST /auth/login': [
          () => json(401, { error: { code: 'UNAUTHORIZED', message: 'Invalid email or password' } }),
          () => json(200, { data: session }),
        ],
        'GET /attendance/daily': (init) =>
          (init.headers as Record<string, string>).Authorization === 'Bearer access-1'
            ? json(200, { data: daily })
            : json(401, { error: { code: 'UNAUTHORIZED', message: 'nope' } }),
      }),
    );
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    api.setAccessToken(null);
  });

  it('sends visitors to sign in, shows a wrong password, then opens today’s register', async () => {
    const user = userEvent.setup();
    renderRoutes(routes, '/');

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByText('Enter a valid email address')).toBeInTheDocument();

    await user.type(screen.getByLabelText('Email'), 'ada@school.ng');
    await user.type(screen.getByLabelText('Password'), 'wrong-password');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Invalid email or password');

    await user.clear(screen.getByLabelText('Password'));
    await user.type(screen.getByLabelText('Password'), 'correct-password');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(await screen.findByText('1 of 2 in. 1 not in yet.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Chidi Okeke' })).toHaveAttribute('href', '/people/m1');
    expect(within(screen.getByRole('table')).getByText('On time').parentElement).toHaveTextContent('07:45');
    expect(screen.getAllByText('Grace High School').length).toBeGreaterThan(0);
  });
});
