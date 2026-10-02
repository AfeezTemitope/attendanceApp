import mongoose from 'mongoose';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DatabaseSetupError, findIndexProblems, prepareDatabase } from '../../src/core/db/connect.js';
import { connectTestDatabase, disconnectTestDatabase } from '../support/harness.js';

// These tests damage indexes on purpose, so every test gets a fresh database.
beforeEach(connectTestDatabase);
afterEach(disconnectTestDatabase);

describe('database setup check', () => {
  it('accepts a database that only this app uses', async () => {
    expect(await findIndexProblems()).toEqual([]);
    await expect(prepareDatabase()).resolves.toBeUndefined();
  });

  it('refuses a database that still holds attendanceApp v1 users, and says how to fix it', async () => {
    // Reproduce a v1 database: staff records in "users" with v1's own unique indexes and no email.
    const users = mongoose.connection.collection('users');
    await users.dropIndex('email_1');
    const admin = new mongoose.Types.ObjectId();
    await users.insertMany([
      { name: 'Old Staff One', userCode: '001', admin },
      { name: 'Old Staff Two', userCode: '002', admin },
    ]);
    await users.createIndex({ admin: 1, userCode: 1 }, { unique: true });
    await users.createIndex({ admin: 1, name: 1 }, { unique: true });

    const failure = await prepareDatabase().catch((error: unknown) => error);

    expect(failure).toBeInstanceOf(DatabaseSetupError);
    const { problems, message } = failure as DatabaseSetupError;
    expect(problems).toEqual(
      expect.arrayContaining([
        expect.stringMatching(/^users: required index email is missing/),
        'users: unique index "admin_1_userCode_1" was not created by this app and will reject new records',
        'users: unique index "admin_1_name_1" was not created by this app and will reject new records',
      ]),
    );
    expect(message).toContain('attendanceApp v1');
    expect(message).toMatch(/MONGO_URI in apps\/api\/\.env .*_v2/);
  });

  it('ignores extra non-unique indexes, which cannot break writes', async () => {
    await mongoose.connection.collection('members').createIndex({ fullName: 1, group: 1 });
    expect(await findIndexProblems()).toEqual([]);
  });
});
