import { ValidationError } from '../../core/errors/index.js';
import type { Clock } from '../../core/time/clock.js';
import { daysInclusive, eachDate, toLocalDate, type LocalDate } from '../../core/time/local-date.js';
import type { AttendanceRecordRow, AttendanceRepository } from '../attendance/attendance.repository.js';
import type { AttendancePolicy } from '../attendance/policies/index.js';
import { MAX_RANGE_DAYS } from '../calendar/calendar.schemas.js';
import type { CalendarService } from '../calendar/calendar.service.js';
import type { MemberRecord, MemberRepository } from '../members/member.repository.js';
import type { OrganizationService } from '../organizations/organization.service.js';
import type { AttendanceReport, DayMark, ReportLogEntry, ReportRow } from './report.types.js';

export interface ReportRequest {
  from: LocalDate;
  to: LocalDate;
  label?: string | null | undefined;
  group?: string | undefined;
  memberId?: string | undefined;
}

interface MarkContext {
  today: LocalDate;
  policy: AttendancePolicy;
  holidays: ReadonlySet<LocalDate>;
}

const rate = (attended: number, expected: number): number | null =>
  expected === 0 ? null : Math.round((attended / expected) * 1000) / 10;

/**
 * Builds the attendance matrix for a date range. Absences are derived here, never stored.
 * Three queries regardless of range size: members, records, holidays.
 */
export class ReportService {
  constructor(
    private readonly organizations: OrganizationService,
    private readonly calendar: CalendarService,
    private readonly members: MemberRepository,
    private readonly records: AttendanceRepository,
    private readonly clock: Clock,
  ) {}

  async build(orgId: string, request: ReportRequest): Promise<AttendanceReport> {
    const { from, to } = request;
    if (from > to) throw new ValidationError('"from" must be on or before "to"');
    if (daysInclusive(from, to) > MAX_RANGE_DAYS) {
      throw new ValidationError(`A report can span at most ${MAX_RANGE_DAYS} days`);
    }

    const { org, policy } = await this.organizations.getWithPolicy(orgId);
    const today = toLocalDate(this.clock.now(), org.timezone);

    const members = await this.members.activeDuring(orgId, from, to, {
      group: request.group,
      memberId: request.memberId,
    });

    const [records, holidayNames] = await Promise.all([
      this.records.between(orgId, from, to, request.memberId ? members.map((m) => m._id) : undefined),
      this.calendar.holidayDates(orgId, from, to),
    ]);

    const dates = eachDate(from, to);
    const context: MarkContext = { today, policy, holidays: new Set(holidayNames.keys()) };
    const recordsByMember = groupByMember(records);
    const rows = members.map((member) =>
      this.buildRow(member, dates, recordsByMember.get(member._id.toString()) ?? new Map(), context),
    );

    const memberById = new Map(members.map((member) => [member._id.toString(), member]));
    const log: ReportLogEntry[] = records.flatMap((record) => {
      const member = memberById.get(record.memberId.toString());
      return member
        ? [
            {
              date: record.date,
              memberId: member._id.toString(),
              fullName: member.fullName,
              code: member.code,
              status: record.status,
              checkInAt: record.checkInAt,
              checkOutAt: record.checkOutAt ?? null,
              method: record.method,
            },
          ]
        : [];
    });

    const sum = (key: 'expected' | 'present' | 'late' | 'attended' | 'absent') =>
      rows.reduce((total, row) => total + row[key], 0);
    const expected = sum('expected');
    const attended = sum('attended');

    return {
      organization: {
        id: org._id.toString(),
        name: org.name,
        slug: org.slug,
        type: org.type,
        timezone: org.timezone,
      },
      range: { from, to, label: request.label ?? null },
      generatedAt: this.clock.now(),
      dates,
      holidays: [...holidayNames].map(([date, name]) => ({ date, name })),
      rows,
      totals: {
        members: rows.length,
        expected,
        present: sum('present'),
        late: sum('late'),
        attended,
        absent: sum('absent'),
        attendanceRate: rate(attended, expected),
      },
      log,
    };
  }

  private buildRow(
    member: MemberRecord,
    dates: LocalDate[],
    records: ReadonlyMap<LocalDate, AttendanceRecordRow>,
    context: MarkContext,
  ): ReportRow {
    let expected = 0;
    let present = 0;
    let late = 0;
    let absent = 0;

    const marks = dates.map((date): DayMark => {
      const mark = this.markFor(member, date, records.get(date), context);
      const counts = context.policy.isExpectedDay(date, context.holidays) && mark !== '-';
      if (counts) {
        expected += 1;
        if (mark === 'P') present += 1;
        else if (mark === 'L') late += 1;
        else if (mark === 'A') absent += 1;
      }
      return mark;
    });

    return {
      memberId: member._id.toString(),
      fullName: member.fullName,
      code: member.code,
      group: member.group ?? null,
      status: member.status,
      marks,
      expected,
      present,
      late,
      attended: present + late,
      absent,
      attendanceRate: rate(present + late, expected),
    };
  }

  private markFor(
    member: MemberRecord,
    date: LocalDate,
    record: AttendanceRecordRow | undefined,
    { today, policy, holidays }: MarkContext,
  ): DayMark {
    if (date > today || date < member.joinedOn) return '-';
    if (member.archivedOn && date >= member.archivedOn) return record ? statusMark(record) : '-';
    if (record) return statusMark(record);
    if (holidays.has(date)) return 'H';
    if (!policy.isExpectedDay(date, holidays)) return 'W';
    // Today is still in progress: not checked in yet is not the same as absent.
    return date === today ? '-' : 'A';
  }
}

const statusMark = (record: AttendanceRecordRow): DayMark => (record.status === 'LATE' ? 'L' : 'P');

function groupByMember(records: AttendanceRecordRow[]): Map<string, Map<LocalDate, AttendanceRecordRow>> {
  const grouped = new Map<string, Map<LocalDate, AttendanceRecordRow>>();
  for (const record of records) {
    const key = record.memberId.toString();
    let byDate = grouped.get(key);
    if (!byDate) {
      byDate = new Map();
      grouped.set(key, byDate);
    }
    byDate.set(record.date, record);
  }
  return grouped;
}
