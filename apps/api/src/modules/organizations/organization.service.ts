import { randomBytes } from 'node:crypto';
import { toLean, type Lean } from '../../core/db/tenant-repository.js';
import { NotFoundError } from '../../core/errors/index.js';
import {
  createAttendancePolicy,
  DEFAULT_POLICIES,
  type AttendancePolicy,
  type AttendancePolicyConfig,
} from '../attendance/policies/index.js';
import { OrganizationModel, type Organization } from './organization.model.js';
import type { CreateOrganizationInput, UpdateOrganizationInput } from './organization.schemas.js';

export type OrganizationRecord = Lean<Organization>;

export function slugify(value: string): string {
  return (
    value
      .normalize('NFKD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 48) || 'org'
  );
}

export class OrganizationService {
  async create(input: CreateOrganizationInput): Promise<OrganizationRecord> {
    const slug = await this.uniqueSlug(slugify(input.name));
    const created = await OrganizationModel.create({
      name: input.name,
      slug,
      type: input.type,
      timezone: input.timezone,
      policy: { ...DEFAULT_POLICIES[input.type], workDays: [...DEFAULT_POLICIES[input.type].workDays] },
    });
    return toLean<Organization>(created);
  }

  async getById(id: string): Promise<OrganizationRecord> {
    const org = await OrganizationModel.findById(id).lean<OrganizationRecord>().exec();
    if (!org) throw new NotFoundError('Organization');
    return org;
  }

  async findManyByIds(ids: string[]): Promise<OrganizationRecord[]> {
    return OrganizationModel.find({ _id: { $in: ids } })
      .lean<OrganizationRecord[]>()
      .exec();
  }

  async update(id: string, input: UpdateOrganizationInput): Promise<OrganizationRecord> {
    const org = await OrganizationModel.findByIdAndUpdate(
      id,
      { $set: input },
      { returnDocument: 'after', runValidators: true },
    )
      .lean<OrganizationRecord>()
      .exec();
    if (!org) throw new NotFoundError('Organization');
    return org;
  }

  async updatePolicy(id: string, policy: AttendancePolicyConfig): Promise<OrganizationRecord> {
    const org = await OrganizationModel.findByIdAndUpdate(
      id,
      { $set: { policy } },
      { returnDocument: 'after', runValidators: true },
    )
      .lean<OrganizationRecord>()
      .exec();
    if (!org) throw new NotFoundError('Organization');
    return org;
  }

  /** Loads the organisation together with its attendance policy object. */
  async getWithPolicy(id: string): Promise<{ org: OrganizationRecord; policy: AttendancePolicy }> {
    const org = await this.getById(id);
    return { org, policy: createAttendancePolicy(org.policy) };
  }

  async delete(id: string): Promise<void> {
    await OrganizationModel.deleteOne({ _id: id }).exec();
  }

  private async uniqueSlug(base: string): Promise<string> {
    if (!(await OrganizationModel.exists({ slug: base }))) return base;
    return `${base}-${randomBytes(3).toString('hex')}`;
  }
}
