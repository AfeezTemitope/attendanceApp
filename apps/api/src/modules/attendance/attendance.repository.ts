import type { Types, UpdateQuery } from 'mongoose';
import { TenantRepository, toLean, type Id, type Lean } from '../../core/db/tenant-repository.js';
import type { LocalDate } from '../../core/time/local-date.js';
import { AttendanceRecordModel, type AttendanceRecord } from './attendance-record.model.js';

export type AttendanceRecordRow = Lean<AttendanceRecord>;

export class AttendanceRepository extends TenantRepository<AttendanceRecord> {
  constructor() {
    super(AttendanceRecordModel);
  }

  async create(orgId: Id, data: Omit<AttendanceRecord, 'orgId'>): Promise<AttendanceRecordRow> {
    return toLean<AttendanceRecord>(await AttendanceRecordModel.create({ ...data, orgId }));
  }

  findForMemberOnDate(orgId: Id, memberId: Id, date: LocalDate): Promise<AttendanceRecordRow | null> {
    return AttendanceRecordModel.findOne(this.scoped(orgId, { memberId, date })).lean<AttendanceRecordRow>().exec();
  }

  between(orgId: Id, from: LocalDate, to: LocalDate, memberIds?: Types.ObjectId[]): Promise<AttendanceRecordRow[]> {
    return AttendanceRecordModel.find(
      this.scoped(orgId, {
        date: { $gte: from, $lte: to },
        ...(memberIds ? { memberId: { $in: memberIds } } : {}),
      }),
    )
      .sort({ date: 1, checkInAt: 1 })
      .lean<AttendanceRecordRow[]>()
      .exec();
  }

  /** Sets check-out only if the member checked in and has not checked out yet. */
  recordCheckOut(orgId: Id, memberId: Id, date: LocalDate, at: Date): Promise<AttendanceRecordRow | null> {
    return AttendanceRecordModel.findOneAndUpdate(
      this.scoped(orgId, { memberId, date, checkOutAt: { $exists: false } }),
      { $set: { checkOutAt: at } },
      { returnDocument: 'after' },
    )
      .lean<AttendanceRecordRow>()
      .exec();
  }

  upsertForMemberOnDate(
    orgId: Id,
    memberId: Id,
    date: LocalDate,
    update: UpdateQuery<AttendanceRecord>,
  ): Promise<AttendanceRecordRow | null> {
    return AttendanceRecordModel.findOneAndUpdate(this.scoped(orgId, { memberId, date }), update, {
      returnDocument: 'after',
      upsert: true,
      runValidators: true,
      setDefaultsOnInsert: true,
    })
      .lean<AttendanceRecordRow>()
      .exec();
  }
}
