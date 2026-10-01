import { createHash, randomBytes } from 'node:crypto';

export const sha256 = (value: string): string => createHash('sha256').update(value).digest('hex');

/** URL-safe random token. 32 bytes = 256 bits of entropy. */
export const randomToken = (bytes = 32): string => randomBytes(bytes).toString('base64url');
