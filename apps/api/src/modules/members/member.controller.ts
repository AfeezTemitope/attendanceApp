import type { RequestHandler } from 'express';
import { authOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendPage } from '../../core/http/respond.js';
import { idParamsSchema } from '../../core/http/schemas.js';
import { toMemberDto } from './member.dto.js';
import {
  createMemberSchema,
  importMembersSchema,
  listMembersQuerySchema,
  updateMemberSchema,
} from './member.schemas.js';
import type { MemberService } from './member.service.js';

export class MemberController {
  constructor(private readonly members: MemberService) {}

  list: RequestHandler = async (req, res) => {
    const query = parse(listMembersQuerySchema, req.query);
    const { items, total } = await this.members.list(authOf(req).orgId, query);
    sendPage(res, items.map(toMemberDto), { page: query.page, limit: query.limit, total });
  };

  groups: RequestHandler = async (req, res) => {
    sendData(res, await this.members.groups(authOf(req).orgId));
  };

  get: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    sendData(res, toMemberDto(await this.members.get(authOf(req).orgId, id)));
  };

  create: RequestHandler = async (req, res) => {
    const input = parse(createMemberSchema, req.body);
    sendData(res, toMemberDto(await this.members.create(authOf(req).orgId, input)), 201);
  };

  update: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    const input = parse(updateMemberSchema, req.body);
    sendData(res, toMemberDto(await this.members.update(authOf(req).orgId, id, input)));
  };

  archive: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    sendData(res, toMemberDto(await this.members.archive(authOf(req).orgId, id)));
  };

  rotateQrToken: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    const { member, qrToken } = await this.members.rotateQrToken(authOf(req).orgId, id);
    sendData(res, { member: toMemberDto(member), qrToken });
  };

  import: RequestHandler = async (req, res) => {
    const input = parse(importMembersSchema, req.body);
    sendData(res, await this.members.import(authOf(req).orgId, input), 201);
  };
}
