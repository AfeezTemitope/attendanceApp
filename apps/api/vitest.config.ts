import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
    globalSetup: ['./test/support/global-setup.ts'],
    // The first run downloads a MongoDB binary for mongodb-memory-server (cached afterwards).
    hookTimeout: 180_000,
    testTimeout: 30_000,
    pool: 'forks',
  },
});
