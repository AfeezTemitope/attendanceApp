export const ROLES = ['OWNER', 'ADMIN', 'VIEWER'] as const;
export type Role = (typeof ROLES)[number];

const RANK: Record<Role, number> = { VIEWER: 1, ADMIN: 2, OWNER: 3 };

export const isRole = (value: unknown): value is Role => ROLES.includes(value as Role);

/** OWNER ⊃ ADMIN ⊃ VIEWER */
export const hasRole = (actual: Role, required: Role): boolean => RANK[actual] >= RANK[required];
