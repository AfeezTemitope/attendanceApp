import type { RequestHandler } from 'express';
import { authOf, kioskOf } from '../../core/auth/context.js';
import { parse } from '../../core/http/parse.js';
import { sendData, sendNoContent } from '../../core/http/respond.js';
import { idParamsSchema } from '../../core/http/schemas.js';
import { checkInSchema, dailyQuerySchema, manualRecordSchema } from './attendance.schemas.js';
import type { AttendanceService } from './attendance.service.js';

/** Dashboard endpoints (signed-in users). */
export class AttendanceController {
  constructor(private readonly attendance: AttendanceService) {}

  daily: RequestHandler = async (req, res) => {
    const { date } = parse(dailyQuerySchema, req.query);
    sendData(res, await this.attendance.daily(authOf(req).orgId, date));
  };

  recordManually: RequestHandler = async (req, res) => {
    const input = parse(manualRecordSchema, req.body);
    const record = await this.attendance.recordManually(authOf(req), input);
    sendData(
      res,
      {
        id: record._id.toString(),
        memberId: record.memberId.toString(),
        date: record.date,
        status: record.status,
        checkInAt: record.checkInAt,
        method: record.method,
        note: record.note ?? null,
      },
      201,
    );
  };

  deleteRecord: RequestHandler = async (req, res) => {
    const { id } = parse(idParamsSchema, req.params);
    await this.attendance.deleteRecord(authOf(req).orgId, id);
    sendNoContent(res);
  };
}

/** Endpoints called by a registered check-in device. */
export class KioskDeviceController {
  constructor(private readonly attendance: AttendanceService) {}

  session: RequestHandler = async (req, res) => {
    sendData(res, await this.attendance.kioskSession(kioskOf(req)));
  };

  checkIn: RequestHandler = async (req, res) => {
    const credentials = parse(checkInSchema, req.body);
    sendData(res, await this.attendance.checkIn(kioskOf(req), credentials), 201);
  };

  checkOut: RequestHandler = async (req, res) => {
    const credentials = parse(checkInSchema, req.body);
    sendData(res, await this.attendance.checkOut(kioskOf(req), credentials));
  };
}
