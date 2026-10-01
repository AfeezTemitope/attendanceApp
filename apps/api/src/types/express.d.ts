import type { AuthContext, KioskContext } from '../core/auth/context.js';

declare global {
  namespace Express {
    interface Request {
      auth?: AuthContext;
      kiosk?: KioskContext;
    }
  }
}

export {};
