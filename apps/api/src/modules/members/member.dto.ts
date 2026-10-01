import type { MemberRecord } from './member.repository.js';

/** Public shape of a member. PIN and QR hashes never leave the server. */
export function toMemberDto(member: MemberRecord) {
  return {
    id: member._id.toString(),
    fullName: member.fullName,
    code: member.code,
    group: member.group ?? null,
    status: member.status,
    joinedOn: member.joinedOn,
    archivedOn: member.archivedOn ?? null,
    pinSet: member.pinSet,
    qrIssuedAt: member.qrIssuedAt ?? null,
    createdAt: member.createdAt,
    updatedAt: member.updatedAt,
  };
}

export type MemberDto = ReturnType<typeof toMemberDto>;
