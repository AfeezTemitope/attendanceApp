import type { RequestHandler } from 'express';
import { authOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { policyConfigSchema } from '../attendance/policies/policy-config.js';
import { toOrganizationDto } from './organization.dto.js';
import { updateOrganizationSchema } from './organization.schemas.js';
import type { OrganizationService } from './organization.service.js';
import { addTeammateSchema, updateTeammateSchema, userIdParamsSchema } from './team.schemas.js';
import type { TeamService } from './team.service.js';

export class OrganizationController {
  constructor(
    private readonly organizations: OrganizationService,
    private readonly team: TeamService,
  ) {}

  get: RequestHandler = async (req, res) => {
    sendData(res, toOrganizationDto(await this.organizations.getById(authOf(req).orgId)));
  };

  update: RequestHandler = async (req, res) => {
    const input = parse(updateOrganizationSchema, req.body);
    sendData(res, toOrganizationDto(await this.organizations.update(authOf(req).orgId, input)));
  };

  updatePolicy: RequestHandler = async (req, res) => {
    const policy = parse(policyConfigSchema, req.body);
    sendData(res, toOrganizationDto(await this.organizations.updatePolicy(authOf(req).orgId, policy)));
  };

  listTeam: RequestHandler = async (req, res) => {
    sendData(res, await this.team.list(authOf(req).orgId));
  };

  addTeammate: RequestHandler = async (req, res) => {
    const input = parse(addTeammateSchema, req.body);
    sendData(res, await this.team.add(authOf(req), input), 201);
  };

  changeTeammateRole: RequestHandler = async (req, res) => {
    const { userId } = parse(userIdParamsSchema, req.params);
    const { role } = parse(updateTeammateSchema, req.body);
    await this.team.changeRole(authOf(req), userId, role);
    sendNoContent(res);
  };

  removeTeammate: RequestHandler = async (req, res) => {
    const { userId } = parse(userIdParamsSchema, req.params);
    await this.team.remove(authOf(req), userId);
    sendNoContent(res);
  };
}
