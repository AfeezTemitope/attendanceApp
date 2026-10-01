import { ConflictError, NotFoundError, ValidationError } from '../../core/errors/index.js';
import { daysInclusive, type LocalDate } from '../../core/time/local-date.js';
import type { HolidayRecord, HolidayRepository, PeriodRecord, PeriodRepository } from './calendar.repositories.js';
import { MAX_RANGE_DAYS, type CreatePeriodInput, type UpdatePeriodInput } from './calendar.schemas.js';

export class CalendarService {
  constructor(
    private readonly holidays: HolidayRepository,
    private readonly periods: PeriodRepository,
  ) {}

  listHolidays(orgId: string, from: LocalDate, to: LocalDate): Promise<HolidayRecord[]> {
    return this.holidays.between(orgId, from, to);
  }

  async holidayDates(orgId: string, from: LocalDate, to: LocalDate): Promise<Map<LocalDate, string>> {
    const rows = await this.holidays.between(orgId, from, to);
    return new Map(rows.map((row) => [row.date, row.name]));
  }

  isHoliday(orgId: string, date: LocalDate): Promise<boolean> {
    return this.holidays.isHoliday(orgId, date);
  }

  async addHoliday(orgId: string, date: LocalDate, name: string): Promise<HolidayRecord> {
    if (await this.holidays.isHoliday(orgId, date)) {
      throw new ConflictError(`${date} is already marked as a holiday`);
    }
    return this.holidays.create(orgId, { date, name });
  }

  async removeHoliday(orgId: string, id: string): Promise<void> {
    if (!(await this.holidays.deleteById(orgId, id))) throw new NotFoundError('Holiday');
  }

  listPeriods(orgId: string): Promise<PeriodRecord[]> {
    return this.periods.list(orgId);
  }

  async getPeriod(orgId: string, id: string): Promise<PeriodRecord> {
    const period = await this.periods.findById(orgId, id);
    if (!period) throw new NotFoundError('Period');
    return period;
  }

  createPeriod(orgId: string, input: CreatePeriodInput): Promise<PeriodRecord> {
    return this.periods.create(orgId, input);
  }

  async updatePeriod(orgId: string, id: string, input: UpdatePeriodInput): Promise<PeriodRecord> {
    const current = await this.getPeriod(orgId, id);
    const startsOn = input.startsOn ?? current.startsOn;
    const endsOn = input.endsOn ?? current.endsOn;
    if (startsOn > endsOn) throw new ValidationError('endsOn must be on or after startsOn');
    if (daysInclusive(startsOn, endsOn) > MAX_RANGE_DAYS) {
      throw new ValidationError(`a period can span at most ${MAX_RANGE_DAYS} days`);
    }
    const updated = await this.periods.update(orgId, id, { $set: input });
    if (!updated) throw new NotFoundError('Period');
    return updated;
  }

  async deletePeriod(orgId: string, id: string): Promise<void> {
    if (!(await this.periods.deleteById(orgId, id))) throw new NotFoundError('Period');
  }
}

export const toHolidayDto = (holiday: HolidayRecord) => ({
  id: holiday._id.toString(),
  date: holiday.date,
  name: holiday.name,
});

export const toPeriodDto = (period: PeriodRecord) => ({
  id: period._id.toString(),
  name: period.name,
  type: period.type,
  startsOn: period.startsOn,
  endsOn: period.endsOn,
});
