import { randomInt } from 'node:crypto';
import type { Id } from '../../core/db/tenant-repository.js';
import type { MemberRepository } from './member.repository.js';

const MAX_ROUNDS = 10;

/**
 * Generates random numeric check-in codes (not sequential, so they are not guessable from each other).
 * Batch-oriented: one database round-trip checks a whole batch of candidates.
 */
export class MemberCodeGenerator {
  constructor(
    private readonly members: MemberRepository,
    private readonly digits = 6,
  ) {}

  async generate(orgId: Id, count: number, reserved: ReadonlySet<string> = new Set()): Promise<string[]> {
    const accepted = new Set<string>();
    for (let round = 0; round < MAX_ROUNDS && accepted.size < count; round += 1) {
      const candidates = new Set<string>();
      while (candidates.size < count - accepted.size) {
        const code = this.randomCode();
        if (!reserved.has(code) && !accepted.has(code)) candidates.add(code);
      }
      const taken = await this.members.takenCodes(orgId, [...candidates]);
      for (const code of candidates) if (!taken.has(code)) accepted.add(code);
    }
    if (accepted.size < count) {
      throw new Error('Could not generate unique member codes; consider increasing code length');
    }
    return [...accepted];
  }

  async generateOne(orgId: Id): Promise<string> {
    const [code] = await this.generate(orgId, 1);
    return code as string;
  }

  private randomCode(): string {
    const max = 10 ** this.digits;
    return randomInt(max / 10, max).toString();
  }
}
