import type { Env } from './env.js';

/** Runtime configuration consumed by the app. Decoupled from process.env so tests can build it directly. */
export interface AppConfig {
  isProduction: boolean;
  corsOrigins: string[];
  trustProxy: number;
  auth: {
    jwtAccessSecret: string;
    accessTokenTtlSeconds: number;
    refreshTokenTtlDays: number;
    bcryptRounds: number;
  };
  cookie: {
    secure: boolean;
    sameSite: 'lax' | 'strict' | 'none';
  };
}

export function toAppConfig(env: Env): AppConfig {
  const isProduction = env.NODE_ENV === 'production';
  return {
    isProduction,
    corsOrigins: env.CORS_ORIGINS,
    trustProxy: env.TRUST_PROXY,
    auth: {
      jwtAccessSecret: env.JWT_ACCESS_SECRET,
      accessTokenTtlSeconds: env.ACCESS_TOKEN_TTL_SECONDS,
      refreshTokenTtlDays: env.REFRESH_TOKEN_TTL_DAYS,
      bcryptRounds: env.BCRYPT_ROUNDS,
    },
    cookie: {
      // Browsers only honour SameSite=None on Secure cookies.
      secure: isProduction || env.COOKIE_SAMESITE === 'none',
      sameSite: env.COOKIE_SAMESITE,
    },
  };
}
