import type { CookieOptions, Request, RequestHandler, Response } from 'express';
import type { AppConfig } from '../../config/app-config.js';
import { authOf } from '../../core/auth/context.js';
import { UnauthorizedError } from '../../core/errors/index.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { loginSchema, registerSchema } from './auth.schemas.js';
import type { AuthResult, AuthService } from './auth.service.js';
import type { ClientMeta } from './session.service.js';

export const REFRESH_COOKIE = 'att_rt';
export const REFRESH_COOKIE_PATH = '/api/v1/auth';

export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly config: AppConfig,
  ) {}

  register: RequestHandler = async (req, res) => {
    const input = parse(registerSchema, req.body);
    this.respondWithSession(res, await this.auth.register(input, clientMeta(req)), 201);
  };

  login: RequestHandler = async (req, res) => {
    const input = parse(loginSchema, req.body);
    this.respondWithSession(res, await this.auth.login(input, clientMeta(req)));
  };

  refresh: RequestHandler = async (req, res) => {
    const token = readRefreshCookie(req);
    if (!token) throw new UnauthorizedError('No active session', { reason: 'SESSION_MISSING' });
    try {
      this.respondWithSession(res, await this.auth.refresh(token, clientMeta(req)));
    } catch (error) {
      res.clearCookie(REFRESH_COOKIE, this.cookieOptions());
      throw error;
    }
  };

  logout: RequestHandler = async (req, res) => {
    await this.auth.logout(readRefreshCookie(req));
    res.clearCookie(REFRESH_COOKIE, this.cookieOptions());
    sendNoContent(res);
  };

  me: RequestHandler = async (req, res) => {
    sendData(res, await this.auth.profile(authOf(req)));
  };

  private respondWithSession(res: Response, result: AuthResult, status = 200): void {
    res.cookie(REFRESH_COOKIE, result.refreshToken, { ...this.cookieOptions(), expires: result.refreshExpiresAt });
    sendData(res, { accessToken: result.accessToken, expiresIn: result.expiresIn, ...result.profile }, status);
  }

  private cookieOptions(): CookieOptions {
    return {
      httpOnly: true,
      secure: this.config.cookie.secure,
      sameSite: this.config.cookie.sameSite,
      path: REFRESH_COOKIE_PATH,
    };
  }
}

function readRefreshCookie(req: Request): string | undefined {
  const value: unknown = req.cookies?.[REFRESH_COOKIE];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function clientMeta(req: Request): ClientMeta {
  return { userAgent: req.get('user-agent'), ip: req.ip };
}
