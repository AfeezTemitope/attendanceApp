import type { RequestHandler } from 'express';
import { z } from 'zod';
import { authOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { idParamsSchema } from '../../core/http/schemas.js';
import { toKioskDto, type KioskService } from './kiosk.service.js';

const createKioskSchema = z.object({ name: z.string().trim().min(2).max(80) });

export class KioskController {
  constructor(private readonly kiosks: KioskService) {}

  list: RequestHandler = async (req, res) => {
    sendData(res, (await this.kiosks.list(authOf(req).orgId)).map(toKioskDto));
  };

  create: RequestHandler = async (req, res) => {
    const { name } = parse(createKioskSchema, req.body);
    const { kiosk, token } = await this.kiosks.create(authOf(req).orgId, name);
    sendData(res, { kiosk: toKioskDto(kiosk), token }, 201);
  };

  revoke: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    await this.kiosks.revoke(authOf(req).orgId, id);
    sendNoContent(res);
  };
}
