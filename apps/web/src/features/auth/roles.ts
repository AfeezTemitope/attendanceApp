import type { Role } from '@/api/types';

const RANK: Record<Role, number> = { VIEWER: 1, ADMIN: 2, OWNER: 3 };

/** Mirrors the API: OWNER ⊃ ADMIN ⊃ VIEWER. The API enforces this; the UI only hides what would fail. */
export const hasRole = (actual: Role, required: Role): boolean => RANK[actual] >= RANK[required];

export const ROLE_LABEL: Record<Role, string> = { OWNER: 'Owner', ADMIN: 'Admin', VIEWER: 'Viewer' };
