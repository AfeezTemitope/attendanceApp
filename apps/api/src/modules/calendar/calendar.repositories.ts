import type { UpdateQuery } from 'mongoose';
import { TenantRepository, toLean, type Lean } from '../../core/db/tenant-repository.js';
import type { LocalDate } from '../../core/time/local-date.js';
import { HolidayModel, type Holiday } from './holiday.model.js';
import { PeriodModel, type Period } from './period.model.js';

export type HolidayRecord = Lean<Holiday>;
export type PeriodRecord = Lean<Period>;

export class HolidayRepository extends TenantRepository<Holiday> {
  constructor() {
    super(HolidayModel);
  }

  between(orgId: string, from: LocalDate, to: LocalDate): Promise<HolidayRecord[]> {
    return HolidayModel.find(this.scoped(orgId, { date: { $gte: from, $lte: to } }))
      .sort({ date: 1 })
      .lean<HolidayRecord[]>()
      .exec();
  }

  isHoliday(orgId: string, date: LocalDate): Promise<boolean> {
    return this.exists(orgId, { date });
  }

  async create(orgId: string, data: Omit<Holiday, 'orgId'>): Promise<HolidayRecord> {
    return toLean<Holiday>(await HolidayModel.create({ ...data, orgId }));
  }
}

export class PeriodRepository extends TenantRepository<Period> {
  constructor() {
    super(PeriodModel);
  }

  list(orgId: string): Promise<PeriodRecord[]> {
    return PeriodModel.find(this.scoped(orgId)).sort({ startsOn: -1 }).lean<PeriodRecord[]>().exec();
  }

  async create(orgId: string, data: Omit<Period, 'orgId'>): Promise<PeriodRecord> {
    return toLean<Period>(await PeriodModel.create({ ...data, orgId }));
  }

  update(orgId: string, id: string, update: UpdateQuery<Period>): Promise<PeriodRecord | null> {
    return PeriodModel.findOneAndUpdate(this.scoped(orgId, { _id: id }), update, {
      returnDocument: 'after',
      runValidators: true,
    })
      .lean<PeriodRecord>()
      .exec();
  }
}
