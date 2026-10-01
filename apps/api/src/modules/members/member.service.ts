import type { UpdateQuery } from 'mongoose';
import { ConflictError, NotFoundError } from '../../core/errors/index.js';
import type { PasswordHasher } from '../../core/security/password-hasher.js';
import { randomToken, sha256 } from '../../core/security/tokens.js';
import type { Clock } from '../../core/time/clock.js';
import { toLocalDate } from '../../core/time/local-date.js';
import type { OrganizationService } from '../organizations/organization.service.js';
import type { MemberCodeGenerator } from './member-code.generator.js';
import type { Member } from './member.model.js';
import type { MemberListQuery, MemberRecord, MemberRepository } from './member.repository.js';
import type { CreateMemberInput, ImportMembersInput, UpdateMemberInput } from './member.schemas.js';

export interface ImportResult {
  created: number;
  skipped: Array<{ row: number; fullName: string; reason: string }>;
}

export class MemberService {
  constructor(
    private readonly members: MemberRepository,
    private readonly organizations: OrganizationService,
    private readonly codes: MemberCodeGenerator,
    private readonly pinHasher: PasswordHasher,
    private readonly clock: Clock,
  ) {}

  list(orgId: string, query: MemberListQuery) {
    return this.members.list(orgId, query);
  }

  groups(orgId: string): Promise<string[]> {
    return this.members.groups(orgId);
  }

  async get(orgId: string, id: string): Promise<MemberRecord> {
    const member = await this.members.findById(orgId, id);
    if (!member) throw new NotFoundError('Member');
    return member;
  }

  async create(orgId: string, input: CreateMemberInput): Promise<MemberRecord> {
    const code = input.code ?? (await this.codes.generateOne(orgId));
    if (input.code && (await this.members.exists(orgId, { code }))) {
      throw new ConflictError(`Code ${code} is already assigned to another member`);
    }
    return this.members.create(orgId, {
      fullName: input.fullName,
      code,
      group: input.group,
      pinHash: input.pin ? await this.pinHasher.hash(input.pin) : undefined,
      pinSet: Boolean(input.pin),
      status: 'ACTIVE',
      joinedOn: input.joinedOn ?? (await this.today(orgId)),
    });
  }

  async update(orgId: string, id: string, input: UpdateMemberInput): Promise<MemberRecord> {
    const current = await this.get(orgId, id);
    const $set: Partial<Member> = {};
    const $unset: Record<string, 1> = {};

    if (input.fullName !== undefined) $set.fullName = input.fullName;
    if (input.joinedOn !== undefined) $set.joinedOn = input.joinedOn;
    if (input.group !== undefined) {
      if (input.group === null) $unset.group = 1;
      else $set.group = input.group;
    }
    if (input.code !== undefined && input.code !== current.code) {
      if (await this.members.exists(orgId, { code: input.code })) {
        throw new ConflictError(`Code ${input.code} is already assigned to another member`);
      }
      $set.code = input.code;
    }
    if (input.pin !== undefined) {
      if (input.pin === null) {
        $unset.pinHash = 1;
        $set.pinSet = false;
      } else {
        $set.pinHash = await this.pinHasher.hash(input.pin);
        $set.pinSet = true;
      }
    }
    if (input.status !== undefined && input.status !== current.status) {
      if (input.status === 'ARCHIVED') $set.archivedOn = await this.today(orgId);
      else $unset.archivedOn = 1;
      $set.status = input.status;
    }

    const update: UpdateQuery<Member> = {};
    if (Object.keys($set).length > 0) update.$set = $set;
    if (Object.keys($unset).length > 0) update.$unset = $unset;
    if (Object.keys(update).length === 0) return current;
    const updated = await this.members.update(orgId, id, update);
    if (!updated) throw new NotFoundError('Member');
    return updated;
  }

  /** Soft delete: the member stops being expected, but their history stays in every report. */
  archive(orgId: string, id: string): Promise<MemberRecord> {
    return this.update(orgId, id, { status: 'ARCHIVED' });
  }

  /** Issues a new QR token (e.g. for an ID card). The raw token is returned once and never stored. */
  async rotateQrToken(orgId: string, id: string): Promise<{ member: MemberRecord; qrToken: string }> {
    const qrToken = `qr_${randomToken(24)}`;
    const member = await this.members.update(orgId, id, {
      $set: { qrTokenHash: sha256(qrToken), qrIssuedAt: this.clock.now() },
    });
    if (!member) throw new NotFoundError('Member');
    return { member, qrToken };
  }

  async import(orgId: string, input: ImportMembersInput): Promise<ImportResult> {
    const today = await this.today(orgId);
    const skipped: ImportResult['skipped'] = [];

    const providedCodes = input.members.flatMap((row) => (row.code ? [row.code] : []));
    const takenInDb = await this.members.takenCodes(orgId, providedCodes);
    const seenInFile = new Set<string>();

    const accepted = input.members.flatMap((row, index) => {
      if (row.code) {
        if (takenInDb.has(row.code)) {
          skipped.push({ row: index + 1, fullName: row.fullName, reason: `Code ${row.code} already exists` });
          return [];
        }
        if (seenInFile.has(row.code)) {
          skipped.push({
            row: index + 1,
            fullName: row.fullName,
            reason: `Code ${row.code} appears twice in the file`,
          });
          return [];
        }
        seenInFile.add(row.code);
      }
      return [row];
    });

    const missing = accepted.filter((row) => !row.code).length;
    const generated = await this.codes.generate(orgId, missing, seenInFile);

    const created = await this.members.createMany(
      orgId,
      accepted.map((row) => ({
        fullName: row.fullName,
        code: row.code ?? (generated.pop() as string),
        group: row.group,
        pinSet: false,
        status: 'ACTIVE' as const,
        joinedOn: row.joinedOn ?? today,
      })),
    );
    return { created, skipped };
  }

  private async today(orgId: string): Promise<string> {
    const org = await this.organizations.getById(orgId);
    return toLocalDate(this.clock.now(), org.timezone);
  }
}
