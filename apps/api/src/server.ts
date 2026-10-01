import { toAppConfig } from './config/app-config.js';
import { loadDotEnvFile, loadEnv } from './config/env.js';
import { createApp } from './app.js';
import { createContainer } from './container.js';
import { connectDatabase, disconnectDatabase } from './core/db/connect.js';
import { createLogger } from './core/logger.js';

loadDotEnvFile();
const env = loadEnv();
const logger = createLogger(env.LOG_LEVEL, env.NODE_ENV === 'development');

process.on('unhandledRejection', (reason) => {
  logger.fatal({ err: reason }, 'Unhandled promise rejection');
  process.exit(1);
});

try {
  await connectDatabase(env.MONGO_URI, logger);
} catch (error) {
  logger.fatal(
    { reason: error instanceof Error ? error.message : String(error) },
    'Could not connect to MongoDB. Is it running, and is MONGO_URI in apps/api/.env correct?',
  );
  process.exit(1);
}

const app = createApp(createContainer(toAppConfig(env), { logger }));
const server = app.listen(env.PORT, () => {
  logger.info(`API listening on http://localhost:${env.PORT} (${env.NODE_ENV})`);
});

let shuttingDown = false;
async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info({ signal }, 'Shutting down');

  const forceExit = setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10_000);
  forceExit.unref();

  server.close(async () => {
    await disconnectDatabase();
    logger.info('Shutdown complete');
    process.exit(0);
  });
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
