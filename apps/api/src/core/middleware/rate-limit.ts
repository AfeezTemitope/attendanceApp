import { rateLimit, type Options } from 'express-rate-limit';

const errorResponse = (code: string, message: string) => ({ error: { code, message } });

/**
 * Rate limiters use the default in-memory store: correct for a single instance.
 * When you run more than one API instance, plug in a shared store (e.g. rate-limit-redis).
 */
export function createRateLimiters(overrides: Partial<Options> = {}) {
  const base: Partial<Options> = {
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    ...overrides,
  };

  return {
    /** Login / register: slows down credential stuffing. */
    auth: rateLimit({
      ...base,
      windowMs: 15 * 60 * 1000,
      limit: 20,
      message: errorResponse('TOO_MANY_REQUESTS', 'Too many attempts. Please try again later.'),
    }),
    /** Check-in: only failed attempts count, per kiosk device, so code guessing gets locked out fast. */
    checkInFailures: rateLimit({
      ...base,
      windowMs: 5 * 60 * 1000,
      limit: 15,
      skipSuccessfulRequests: true,
      keyGenerator: (req) => `kiosk:${req.kiosk?.id ?? 'anonymous'}`,
      message: errorResponse('TOO_MANY_REQUESTS', 'Too many failed check-ins on this device. Wait a few minutes.'),
    }),
  };
}

export type RateLimiters = ReturnType<typeof createRateLimiters>;
