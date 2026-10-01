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
  await ensureIndexes();
  logger.info({ host: mongoose.connection.host, db: mongoose.connection.name }, 'MongoDB connected');
}

/**
 * Builds every declared index before the app accepts traffic.
 * Unique indexes (one check-in per member per day, unique codes per org) are business rules, not optimisations.
 */
export async function ensureIndexes(): Promise<void> {
  await Promise.all(Object.values(mongoose.models).map((model) => model.init()));
}

export async function disconnectDatabase(): Promise<void> {
  closing = true;
  await mongoose.disconnect();
}

export function isDatabaseReady(): boolean {
  return mongoose.connection.readyState === mongoose.ConnectionStates.connected;
}
