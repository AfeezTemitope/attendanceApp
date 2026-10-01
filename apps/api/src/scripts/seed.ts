/**
 * Demo data for local development: a school with 24 students, a kiosk, a term and four weeks of attendance.
 * Usage (from the repo root):  npm run seed
 * Safe to re-run: it does nothing if the demo account already exists.
 */
import { toAppConfig } from '../config/app-config.js';
import { loadDotEnvFile, loadEnv } from '../config/env.js';
import { createContainer } from '../container.js';
import { connectDatabase, disconnectDatabase } from '../core/db/connect.js';
import { createLogger } from '../core/logger.js';
import { eachDate, toInstant, toLocalDate } from '../core/time/local-date.js';
import { AttendanceRecordModel } from '../modules/attendance/attendance-record.model.js';
import { createAttendancePolicy } from '../modules/attendance/policies/index.js';
import { UserModel } from '../modules/auth/user.model.js';
import { MemberModel } from '../modules/members/member.model.js';

const DEMO_EMAIL = 'demo@attendance.local';
const DEMO_PASSWORD = 'demo-password-123';
const TIMEZONE = 'Africa/Lagos';

const STUDENTS = [
  'Adaeze Okafor',
  'Babatunde Adeyemi',
  'Chiamaka Eze',
  'Damilola Bakare',
  'Emeka Nwosu',
  'Fatima Bello',
  'Gbenga Ogunleye',
  'Halima Yusuf',
  'Ifeoma Obi',
  'Jide Akinola',
  'Kemi Adebayo',
  'Lanre Coker',
  'Musa Abdullahi',
  'Nkechi Uche',
  'Olumide Fashola',
  'Precious Etim',
  'Quadri Lawal',
  'Rukayat Salami',
  'Segun Ojo',
  'Temitope Bello',
  'Uchenna Ibe',
  'Victoria Essien',
  'Wale Adeleke',
  'Zainab Garba',
];
const CLASSES = ['JSS 1', 'JSS 2', 'JSS 3'];

/** Small deterministic PRNG so every developer gets the same demo data. */
function mulberry32(seed: number): () => number {
  let state = seed;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

async function main(): Promise<void> {
  loadDotEnvFile();
  const env = loadEnv();
  const logger = createLogger('warn');
  await connectDatabase(env.MONGO_URI, logger);
  const { services } = createContainer(toAppConfig(env), { logger });

  if (await UserModel.exists({ email: DEMO_EMAIL })) {
    console.warn(`Demo data already exists. Log in with ${DEMO_EMAIL} / ${DEMO_PASSWORD}`);
    return;
  }

  const session = await services.auth.register(
    {
      organization: { name: 'Demo Academy', type: 'SCHOOL', timezone: TIMEZONE },
      user: { name: 'Demo Owner', email: DEMO_EMAIL, password: DEMO_PASSWORD },
    },
    { userAgent: 'seed-script' },
  );
  const orgId = session.profile.organization.id;

  const today = toLocalDate(new Date(), TIMEZONE);
  const start = toLocalDate(new Date(Date.now() - 28 * 86_400_000), TIMEZONE);

  await services.members.import(orgId, {
    members: STUDENTS.map((fullName, index) => ({
      fullName,
      group: CLASSES[index % CLASSES.length],
      joinedOn: start,
    })),
  });
  await services.calendar.createPeriod(orgId, { name: 'Demo term', type: 'TERM', startsOn: start, endsOn: today });
  const { token: kioskToken } = await services.kiosks.create(orgId, 'Front gate');

  // Four weeks of history: ~85% on time, ~8% late, the rest absent. Today is left for live check-ins.
  const policy = createAttendancePolicy(session.profile.organization.policy);
  const random = mulberry32(2026);
  const members = await MemberModel.find({ orgId }).lean().exec();
  const days = eachDate(start, today).filter((date) => date < today && policy.isExpectedDay(date, new Set()));

  const records = days.flatMap((date) =>
    members.flatMap((member) => {
      const roll = random();
      if (roll > 0.93) return [];
      const late = roll > 0.85;
      const minute = late ? 1 + Math.floor(random() * 29) : Math.floor(random() * 60);
      const time = late ? `08:${String(minute).padStart(2, '0')}` : `07:${String(minute).padStart(2, '0')}`;
      return [
        {
          orgId: member.orgId,
          memberId: member._id,
          date,
          checkInAt: toInstant(date, time, TIMEZONE),
          status: late ? 'LATE' : 'PRESENT',
          method: 'CODE',
        },
      ];
    }),
  );
  await AttendanceRecordModel.insertMany(records);

  console.warn(
    [
      '',
      'Demo data created',
      `  Dashboard login : ${DEMO_EMAIL} / ${DEMO_PASSWORD}`,
      `  Kiosk token     : ${kioskToken}`,
      `  Students        : ${members.length} (codes are listed in GET /api/v1/members)`,
      `  History         : ${records.length} check-ins over ${days.length} school days`,
      '',
    ].join('\n'),
  );
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => disconnectDatabase());
