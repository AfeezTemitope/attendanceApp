import type { TestProject } from 'vitest/node';

declare module 'vitest' {
  export interface ProvidedContext {
    mongoUri: string;
  }
}

/**
 * Starts one in-memory MongoDB for the whole run. Each test file then uses its own database on it.
 * Set MONGO_TEST_URI to run against an existing server instead (CI service container, local mongod…).
 */
export default async function setup(project: TestProject) {
  const external = process.env.MONGO_TEST_URI;
  if (external) {
    project.provide('mongoUri', external);
    return undefined;
  }

  const { MongoMemoryServer } = await import('mongodb-memory-server');
  const server = await MongoMemoryServer.create();
  project.provide('mongoUri', server.getUri());
  return async () => {
    await server.stop();
  };
}
