import { Types } from 'mongoose';
import type { AuthContext, KioskContext } from '../../core/auth/context.js';
import { isDuplicateKeyError } from '../../core/db/mongo-errors.js';
import { ConflictError, NotFoundError, ValidationError } from '../../core/errors/index.js';
import type { Clock } from '../../core/time/clock.js';
import { isoWeekday, toInstant, toZonedMoment, type LocalDate } from '../../core/time/local-date.js';
import type { CalendarService } from '../calendar/calendar.service.js';
import type { MemberRepository } from '../members/member.repository.js';
import type { OrganizationService } from '../organizations/organization.service.js';
import type { AttendanceRecordRow, AttendanceRepository } from './attendance.repository.js';
import type { ManualRecordInput } from './attendance.schemas.js';
import { CheckInRejectedError } from './check-in/check-in.errors.js';
import type { CheckInCredentials, MemberResolverRegistry } from './check-in/member-resolver.js';

export type DailyStatus = 'PRESENT' | 'LATE' | 'ABSENT' | 'NOT_CHECKED_IN' | 'HOLIDAY' | 'NON_WORKDAY';

export interface CheckInResult {
  member: { id: string; fullName: string; group: string | null };
  status: 'PRESENT' | 'LATE';
  date: LocalDate;
  checkInAt: Date;
}

export class AttendanceService {
  constructor(
    private readonly organizations: OrganizationService,
    private readonly calendar: CalendarService,
    private readonly members: MemberRepository,
    private readonly records: AttendanceRepository,
    private readonly resolvers: MemberResolverRegistry,
    private readonly clock: Clock,
  ) {}

  /** What a kiosk screen needs to render itself. */
  async kioskSession(kiosk: KioskContext) {
    const { org, policy } = await this.organizations.getWithPolicy(kiosk.orgId);
    const now = this.clock.now();
    const moment = toZonedMoment(now, org.timezone);
    return {
      kiosk: { id: kiosk.id, name: kiosk.name },
      organization: { name: org.name, timezone: org.timezone },
      today: {
        date: moment.date,
        time: moment.time,
        isWorkday: policy.isWorkday(moment.weekday),
        isHoliday: await this.calendar.isHoliday(kiosk.orgId, moment.date),
      },
      policy: {
        kind: org.policy.kind,
        opensAt: org.policy.opensAt,
        lateAfter: org.policy.lateAfter,
        closesAt: org.policy.closesAt ?? null,
        allowCheckOut: org.policy.allowCheckOut,
      },
    };
  }

  async checkIn(kiosk: KioskContext, credentials: CheckInCredentials): Promise<CheckInResult> {
    const { org, policy } = await this.organizations.getWithPolicy(kiosk.orgId);
    const now = this.clock.now();
    const moment = toZonedMoment(now, org.timezone);

    // Time rules first: when check-in is closed nobody can probe codes.
    const decision = policy.evaluateCheckIn({
      localTime: moment.time,
      weekday: moment.weekday,
      isHoliday: await this.calendar.isHoliday(kiosk.orgId, moment.date),
    });
    if (!decision.allowed) throw new CheckInRejectedError(decision.reason, decision.message);

    const member = await this.resolvers.resolve(kiosk.orgId, credentials);

    try {
      const record = await this.records.create(kiosk.orgId, {
        memberId: member._id,
        date: moment.date,
        checkInAt: now,
        status: decision.status,
        method: credentials.method,
        kioskId: toObjectId(kiosk.id),
      });
      return {
        member: { id: member._id.toString(), fullName: member.fullName, group: member.group ?? null },
        status: record.status,
        date: record.date,
        checkInAt: record.checkInAt,
      };
    } catch (error) {
      if (isDuplicateKeyError(error)) {
        const existing = await this.records.findForMemberOnDate(kiosk.orgId, member._id, moment.date);
        throw new ConflictError(`${member.fullName} already checked in today`, {
          reason: 'ALREADY_CHECKED_IN',
          checkInAt: existing?.checkInAt ?? null,
        });
      }
      throw error;
    }
  }

  async checkOut(kiosk: KioskContext, credentials: CheckInCredentials) {
    const { org, policy } = await this.organizations.getWithPolicy(kiosk.orgId);
    if (!policy.allowsCheckOut) {
      throw new CheckInRejectedError('CHECK_OUT_DISABLED', 'Check-out is not enabled for this organization');
    }
    const member = await this.resolvers.resolve(kiosk.orgId, credentials);
    const now = this.clock.now();
    const { date } = toZonedMoment(now, org.timezone);

    const record = await this.records.recordCheckOut(kiosk.orgId, member._id, date, now);
    if (!record) {
      const existing = await this.records.findForMemberOnDate(kiosk.orgId, member._id, date);
      if (!existing) throw new CheckInRejectedError('NOT_CHECKED_IN', `${member.fullName} has not checked in today`);
      throw new ConflictError(`${member.fullName} already checked out today`, { reason: 'ALREADY_CHECKED_OUT' });
    }
    return {
      member: { id: member._id.toString(), fullName: member.fullName },
      date,
      checkInAt: record.checkInAt,
      checkOutAt: record.checkOutAt ?? now,
    };
  }

  /** Admin correction: mark someone present/late for a day (forgot to check in, device offline…). */
  async recordManually(auth: AuthContext, input: ManualRecordInput): Promise<AttendanceRecordRow> {
    const org = await this.organizations.getById(auth.orgId);
    const today = toZonedMoment(this.clock.now(), org.timezone).date;
    if (input.date > today) throw new ValidationError('Cannot record attendance for a future date');

    const member = await this.members.findById(auth.orgId, input.memberId);
    if (!member) throw new NotFoundError('Member');

    const time = input.time ?? (input.status === 'LATE' ? org.policy.lateAfter : org.policy.opensAt);
    const record = await this.records.upsertForMemberOnDate(auth.orgId, member._id, input.date, {
      $set: {
        status: input.status,
        checkInAt: toInstant(input.date, time, org.timezone),
        method: 'MANUAL',
        recordedBy: toObjectId(auth.userId),
        ...(input.note ? { note: input.note } : {}),
      },
    });
    if (!record) throw new Error('Manual attendance upsert returned no document');
    return record;
  }

  async deleteRecord(orgId: string, id: string): Promise<void> {
    if (!(await this.records.deleteById(orgId, id))) throw new NotFoundError('Attendance record');
  }

  /** Everyone expected on a date, with their status. The admin's "who is in today" screen. */
  async daily(orgId: string, requestedDate?: LocalDate) {
    const { org, policy } = await this.organizations.getWithPolicy(orgId);
    const today = toZonedMoment(this.clock.now(), org.timezone).date;
    const date = requestedDate ?? today;
    if (date > today) throw new ValidationError('Cannot view attendance for a future date');

    const [members, records, holidays] = await Promise.all([
      this.members.activeDuring(orgId, date, date),
      this.records.between(orgId, date, date),
      this.calendar.holidayDates(orgId, date, date),
    ]);
    const recordByMember = new Map(records.map((record) => [record.memberId.toString(), record]));
    const holidayName = holidays.get(date) ?? null;
    const isWorkday = policy.isWorkday(isoWeekday(date));
    const isExpectedDay = isWorkday && holidayName === null;

    const statusFor = (record: AttendanceRecordRow | undefined): DailyStatus => {
      if (record) return record.status;
      if (holidayName) return 'HOLIDAY';
      if (!isWorkday) return 'NON_WORKDAY';
      return date === today ? 'NOT_CHECKED_IN' : 'ABSENT';
    };

    const rows = members
      .filter((member) => !member.archivedOn || member.archivedOn > date || recordByMember.has(member._id.toString()))
      .map((member) => {
        const record = recordByMember.get(member._id.toString());
        return {
          member: {
            id: member._id.toString(),
            fullName: member.fullName,
            code: member.code,
            group: member.group ?? null,
          },
          status: statusFor(record),
          recordId: record?._id.toString() ?? null,
          checkInAt: record?.checkInAt ?? null,
          checkOutAt: record?.checkOutAt ?? null,
          method: record?.method ?? null,
        };
      });

    const count = (status: DailyStatus) => rows.filter((row) => row.status === status).length;
    return {
      date,
      isToday: date === today,
      isWorkday,
      holiday: holidayName,
      totals: {
        expected: isExpectedDay ? rows.length : 0,
        present: count('PRESENT'),
        late: count('LATE'),
        absent: count('ABSENT'),
        notCheckedIn: count('NOT_CHECKED_IN'),
      },
      rows,
    };
  }
}

function toObjectId(id: string): Types.ObjectId {
  return new Types.ObjectId(id);
}
