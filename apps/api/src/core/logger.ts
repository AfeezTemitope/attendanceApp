import { pino, type Logger, type LoggerOptions } from 'pino';

export type { Logger };

export function createLogger(level: string, pretty = false): Logger {
  const options: LoggerOptions = {
    level,
    base: undefined,
    redact: {
      paths: ['password', 'pin', 'token', 'refreshToken', 'accessToken', '*.password', '*.pin', '*.token'],
      censor: '[REDACTED]',
    },
  };
  if (pretty) {
    options.transport = {
      target: 'pino-pretty',
      options: { colorize: true, translateTime: 'SYS:HH:MM:ss', ignore: 'pid,hostname' },
    };
  }
  return pino(options);
}
