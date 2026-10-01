import jwt from 'jsonwebtoken';
import { UnauthorizedError } from '../errors/index.js';
import type { AuthContext } from './context.js';
import { isRole } from './roles.js';

const ISSUER = 'attendance-api';
const AUDIENCE = 'attendance-web';

export interface SignedAccessToken {
  accessToken: string;
  expiresIn: number;
}

/** Short-lived JWTs for dashboard users. Long-lived sessions live in refresh tokens (see SessionService). */
export class AccessTokenService {
  constructor(
    private readonly secret: string,
    private readonly ttlSeconds: number,
  ) {}

  sign(context: AuthContext): SignedAccessToken {
    const accessToken = jwt.sign({ org: context.orgId, role: context.role }, this.secret, {
      subject: context.userId,
      expiresIn: this.ttlSeconds,
      issuer: ISSUER,
      audience: AUDIENCE,
      algorithm: 'HS256',
    });
    return { accessToken, expiresIn: this.ttlSeconds };
  }

  verify(token: string): AuthContext {
    let payload: string | jwt.JwtPayload;
    try {
      payload = jwt.verify(token, this.secret, { issuer: ISSUER, audience: AUDIENCE, algorithms: ['HS256'] });
    } catch (error) {
      if (error instanceof jwt.TokenExpiredError) {
        throw new UnauthorizedError('Access token expired', { reason: 'TOKEN_EXPIRED' });
      }
      throw new UnauthorizedError('Invalid access token');
    }
    if (typeof payload === 'string' || !payload.sub || typeof payload.org !== 'string' || !isRole(payload.role)) {
      throw new UnauthorizedError('Invalid access token');
    }
    return { userId: payload.sub, orgId: payload.org, role: payload.role };
  }
}
