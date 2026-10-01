import type { Lean } from '../../core/db/tenant-repository.js';
import type { Organization } from './organization.model.js';

export function toOrganizationDto(org: Lean<Organization>) {
  return {
    id: org._id.toString(),
    name: org.name,
    slug: org.slug,
    type: org.type,
    timezone: org.timezone,
    policy: {
      kind: org.policy.kind,
      workDays: org.policy.workDays,
      opensAt: org.policy.opensAt,
      lateAfter: org.policy.lateAfter,
      ...(org.policy.closesAt ? { closesAt: org.policy.closesAt } : {}),
      allowCheckOut: org.policy.allowCheckOut,
    },
    createdAt: org.createdAt,
  };
}

export type OrganizationDto = ReturnType<typeof toOrganizationDto>;
