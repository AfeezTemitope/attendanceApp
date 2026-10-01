/** Injectable time source. Business rules never call `new Date()` directly, so tests can freeze time. */
export interface Clock {
  now(): Date;
}

export const systemClock: Clock = {
  now: () => new Date(),
};

export class FixedClock implements Clock {
  constructor(private current: Date) {}

  now(): Date {
    return new Date(this.current);
  }

  set(instant: Date | string): void {
    this.current = new Date(instant);
  }
}
