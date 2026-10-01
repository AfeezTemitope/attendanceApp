import type { RequestHandler } from 'express';
import { authOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { idParamsSchema } from '../../core/http/schemas.js';
import { createHolidaySchema, createPeriodSchema, holidayQuerySchema, updatePeriodSchema } from './calendar.schemas.js';
import { toHolidayDto, toPeriodDto, type CalendarService } from './calendar.service.js';

export class CalendarController {
  constructor(private readonly calendar: CalendarService) {}

  listHolidays: RequestHandler = async (req, res) => {
    const { from, to } = parse(holidayQuerySchema, req.query);
    sendData(res, (await this.calendar.listHolidays(authOf(req).orgId, from, to)).map(toHolidayDto));
  };

  addHoliday: RequestHandler = async (req, res) => {
    const { date, name } = parse(createHolidaySchema, req.body);
    sendData(res, toHolidayDto(await this.calendar.addHoliday(authOf(req).orgId, date, name)), 201);
  };

  removeHoliday: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    await this.calendar.removeHoliday(authOf(req).orgId, id);
    sendNoContent(res);
  };

  listPeriods: RequestHandler = async (req, res) => {
    sendData(res, (await this.calendar.listPeriods(authOf(req).orgId)).map(toPeriodDto));
  };

  createPeriod: RequestHandler = async (req, res) => {
    const input = parse(createPeriodSchema, req.body);
    sendData(res, toPeriodDto(await this.calendar.createPeriod(authOf(req).orgId, input)), 201);
  };

  updatePeriod: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    const input = parse(updatePeriodSchema, req.body);
    sendData(res, toPeriodDto(await this.calendar.updatePeriod(authOf(req).orgId, id, input)));
  };

  deletePeriod: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    await this.calendar.deletePeriod(authOf(req).orgId, id);
    sendNoContent(res);
  };
}
