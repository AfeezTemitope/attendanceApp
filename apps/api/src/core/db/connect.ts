import mongoose from 'mongoose';
import type { Logger } from '../logger.js';

mongoose.set('strictQuery', true);

/** Set during graceful shutdown so an intentional disconnect is not logged as a failure. */
let closing = false;

export async function connectDatabase(uri: string, logger: Logger): Promise<void> {
  mongoose.connection.on('disconnected', () => {
    if (!closing) logger.warn('MongoDB disconnected');
  });
  mongoose.connection.on('reconnected', () => logger.info('MongoDB reconnected'));

  await mongoose.connect(uri, {
    serverSelectionTimeoutMS: 10_000,
    maxPoolSize: 20,
  });
  await prepareDatabase();
  logger.info({ host: mongoose.connection.host, db: mongoose.connection.name }, 'MongoDB connected');
}

/**
 * Builds every declared index before the app accepts traffic.
 * Unique indexes (one check-in per member per day, unique codes per org) are business rules, not optimisations.
 */
export async function ensureIndexes(): Promise<void> {
  await Promise.all(Object.values(mongoose.models).map((model) => model.init()));
}

/**
 * The database cannot be used safely. Typically it is shared with another app (such as attendanceApp v1)
 * whose documents block our unique indexes, or whose own unique indexes reject our writes.
 */
export class DatabaseSetupError extends Error {
  constructor(
    readonly problems: string[],
    readonly database: string,
  ) {
    super(
      [
        `Database "${database}" cannot be used by this app:`,
        ...problems.map((problem) => `  - ${problem}`),
        'This usually means the database also holds data from another app (for example attendanceApp v1).',
        `Fix: point MONGO_URI in apps/api/.env at a new database, e.g. mongodb://127.0.0.1:27017/${database}_v2`,
      ].join('\n'),
    );
    this.name = 'DatabaseSetupError';
  }
}

/** Builds the indexes, then refuses to continue if any of them would make writes fail later. */
export async function prepareDatabase(): Promise<void> {
  let buildError: unknown;
  try {
    await ensureIndexes();
  } catch (error) {
    buildError = error;
  }
  const problems = await findIndexProblems();
  if (problems.length > 0) throw new DatabaseSetupError(problems, mongoose.connection.name);
  if (buildError) throw buildError;
}

/**
 * Compares the indexes in the database with the ones the models declare. Reports
 * declared indexes that are missing (usually a unique index that failed to build because of
 * existing data) and unique indexes nobody declared (they reject inserts with a duplicate-key error).
 */
export async function findIndexProblems(): Promise<string[]> {
  const problems: string[] = [];
  for (const model of Object.values(mongoose.models)) {
    const collection = model.collection.collectionName;
    const { toCreate, toDrop } = await model.diffIndexes();
    for (const index of toCreate as unknown[]) {
      problems.push(
        `${collection}: required index ${describeIndex(index)} is missing; existing documents probably prevented it from being built`,
      );
    }
    if (toDrop.length === 0) continue;
    const existing = (await model.listIndexes()) as Array<{ name?: string; unique?: boolean }>;
    for (const name of toDrop as string[]) {
      if (existing.find((index) => index.name === name)?.unique) {
        problems.push(`${collection}: unique index "${name}" was not created by this app and will reject new records`);
      }
    }
  }
  return problems;
}

function describeIndex(index: unknown): string {
  const keys = Array.isArray(index)
    ? index[0]
    : index && typeof index === 'object' && 'key' in index
      ? index.key
      : index;
  return keys && typeof keys === 'object' ? Object.keys(keys).join(' + ') : String(index);
}

export async function disconnectDatabase(): Promise<void> {
  closing = true;
  await mongoose.disconnect();
}

export function isDatabaseReady(): boolean {
  return mongoose.connection.readyState === mongoose.ConnectionStates.connected;
}
