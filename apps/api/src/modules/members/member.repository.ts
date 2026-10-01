import type { QueryFilter, UpdateQuery } from 'mongoose';
import { TenantRepository, toLean, type Id, type Lean } from '../../core/db/tenant-repository.js';
import type { LocalDate } from '../../core/time/local-date.js';
import { MemberModel, type Member, type MemberStatus } from './member.model.js';

export type MemberRecord = Lean<Member>;

export interface MemberListQuery {
  search?: string | undefined;
  status: MemberStatus | 'ALL';
  group?: string | undefined;
  page: number;
  limit: number;
}

const escapeRegex = (value: string) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export class MemberRepository extends TenantRepository<Member> {
  constructor() {
    super(MemberModel);
  }

  async list(orgId: Id, query: MemberListQuery): Promise<{ items: MemberRecord[]; total: number }> {
    const filter: QueryFilter<Member> = {};
    if (query.status !== 'ALL') filter.status = query.status;
    if (query.group) filter.group = query.group;
    if (query.search) {
      const pattern = new RegExp(escapeRegex(query.search), 'i');
      filter.$or = [{ fullName: pattern }, { code: pattern }];
    }
    const scoped = this.scoped(orgId, filter);
    const [items, total] = await Promise.all([
      MemberModel.find(scoped)
        .sort({ fullName: 1, _id: 1 })
        .skip((query.page - 1) * query.limit)
        .limit(query.limit)
        .lean<MemberRecord[]>()
        .exec(),
      MemberModel.countDocuments(scoped).exec(),
    ]);
    return { items, total };
  }

  async findActiveByCodeWithPin(orgId: Id, code: string): Promise<MemberRecord | null> {
    return MemberModel.findOne(this.scoped(orgId, { code, status: 'ACTIVE' }))
      .select('+pinHash')
      .lean<MemberRecord>()
      .exec();
  }

  async findActiveByQrHash(orgId: Id, qrTokenHash: string): Promise<MemberRecord | null> {
    return MemberModel.findOne(this.scoped(orgId, { qrTokenHash, status: 'ACTIVE' }))
      .lean<MemberRecord>()
      .exec();
  }

  async findManyByIds(orgId: Id, ids: Id[]): Promise<MemberRecord[]> {
    return MemberModel.find(this.scoped(orgId, { _id: { $in: ids } }))
      .lean<MemberRecord[]>()
      .exec();
  }

  /** Which of these codes are already taken in the organisation. */
  async takenCodes(orgId: Id, codes: string[]): Promise<Set<string>> {
    if (codes.length === 0) return new Set();
    const rows = await MemberModel.find(this.scoped(orgId, { code: { $in: codes } }))
      .select('code')
      .lean<Array<{ code: string }>>()
      .exec();
    return new Set(rows.map((row) => row.code));
  }

  async create(orgId: Id, data: Omit<Member, 'orgId'>): Promise<MemberRecord> {
    return toLean<Member>(await MemberModel.create({ ...data, orgId }));
  }

  async createMany(orgId: Id, rows: Array<Omit<Member, 'orgId'>>): Promise<number> {
    if (rows.length === 0) return 0;
    const inserted = await MemberModel.insertMany(
      rows.map((row) => ({ ...row, orgId })),
      { ordered: false },
    );
    return inserted.length;
  }

  async update(orgId: Id, id: Id, update: UpdateQuery<Member>): Promise<MemberRecord | null> {
    return MemberModel.findOneAndUpdate(this.scoped(orgId, { _id: id }), update, {
      returnDocument: 'after',
      runValidators: true,
    })
      .lean<MemberRecord>()
      .exec();
  }

  /**
   * Members whose active span overlaps [from, to]: joined on/before `to`
   * and not archived before `from`. Used for daily views and reports.
   */
  async activeDuring(
    orgId: Id,
    from: LocalDate,
    to: LocalDate,
    options: { group?: string | undefined; memberId?: Id | undefined } = {},
  ): Promise<MemberRecord[]> {
    return MemberModel.find(
      this.scoped(orgId, {
        joinedOn: { $lte: to },
        $or: [{ status: 'ACTIVE' }, { archivedOn: { $gt: from } }],
        ...(options.group ? { group: options.group } : {}),
        ...(options.memberId ? { _id: options.memberId } : {}),
      }),
    )
      .sort({ fullName: 1, _id: 1 })
      .lean<MemberRecord[]>()
      .exec();
  }

  async groups(orgId: Id): Promise<string[]> {
    const values = await MemberModel.distinct('group', this.scoped(orgId, { status: 'ACTIVE' })).exec();
    return values.filter((value): value is string => typeof value === 'string' && value.length > 0).sort();
  }
}
