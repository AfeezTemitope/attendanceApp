import Papa from 'papaparse';

export interface ImportRow {
  line: number;
  fullName: string;
  code?: string;
  group?: string;
  joinedOn?: string;
}

export interface ImportIssue {
  line: number;
  message: string;
}

export interface ParsedImport {
  rows: ImportRow[];
  issues: ImportIssue[];
  /** Which spreadsheet column fed each field (null when absent). */
  columns: { fullName: string | null; code: string | null; group: string | null; joinedOn: string | null };
}

const ALIASES = {
  fullName: ['name', 'full name', 'fullname', 'student name', 'staff name', 'employee name', 'pupil name'],
  surname: ['surname', 'last name', 'lastname', 'family name'],
  firstName: ['first name', 'firstname', 'given name'],
  otherNames: ['other names', 'other name', 'middle name', 'middle names'],
  code: [
    'code',
    'id',
    'staff id',
    'student id',
    'employee id',
    'admission no',
    'admission number',
    'reg no',
    'staff no',
  ],
  group: ['group', 'class', 'department', 'dept', 'arm', 'team', 'unit'],
  joinedOn: ['joined', 'joined on', 'date joined', 'start date', 'resumption date'],
} as const;

const CODE_PATTERN = /^[A-Z0-9-]{3,20}$/;

const normalizeHeader = (header: string) => header.toLowerCase().replace(/[._]/g, ' ').replace(/\s+/g, ' ').trim();

/** Accepts 2026-09-14, 14/09/2026 and 14-9-2026; returns YYYY-MM-DD or null. */
export function normalizeDate(value: string): string | null {
  const trimmed = value.trim();
  let year: number, month: number, day: number;
  const iso = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(trimmed);
  const dmy = /^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/.exec(trimmed);
  if (iso) [year, month, day] = [Number(iso[1]), Number(iso[2]), Number(iso[3])];
  else if (dmy) [day, month, year] = [Number(dmy[1]), Number(dmy[2]), Number(dmy[3])];
  else return null;

  const date = new Date(Date.UTC(year, month - 1, day));
  const valid = date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
  return valid ? date.toISOString().slice(0, 10) : null;
}

/** Parses a people CSV exported from Excel / Google Sheets into import rows plus row-level problems. */
export function parsePeopleCsv(text: string): ParsedImport {
  const parsed = Papa.parse<Record<string, string>>(text.replace(/^\uFEFF/, ''), {
    header: true,
    skipEmptyLines: 'greedy',
  });
  const headers = parsed.meta.fields ?? [];
  const find = (aliases: readonly string[]) =>
    headers.find((header) => aliases.includes(normalizeHeader(header))) ?? null;

  const column = {
    fullName: find(ALIASES.fullName),
    surname: find(ALIASES.surname),
    firstName: find(ALIASES.firstName),
    otherNames: find(ALIASES.otherNames),
    code: find(ALIASES.code),
    group: find(ALIASES.group),
    joinedOn: find(ALIASES.joinedOn),
  };

  const issues: ImportIssue[] = [];
  const rows: ImportRow[] = [];
  const hasNames = column.fullName || column.surname || column.firstName;
  if (!hasNames) {
    issues.push({
      line: 1,
      message: 'No name column found. Add a column called "Full name" (or "Surname" and "First name").',
    });
    return {
      rows,
      issues,
      columns: { fullName: null, code: column.code, group: column.group, joinedOn: column.joinedOn },
    };
  }

  const seenCodes = new Map<string, number>();
  parsed.data.forEach((record, index) => {
    const line = index + 2; // line 1 is the header
    const cell = (name: string | null) => (name ? (record[name] ?? '').trim() : '');

    const fullName = column.fullName
      ? cell(column.fullName)
      : [cell(column.surname), cell(column.firstName), cell(column.otherNames)].filter(Boolean).join(' ');
    const code = cell(column.code).toUpperCase();
    const group = cell(column.group);
    const joinedRaw = cell(column.joinedOn);

    const problems: string[] = [];
    if (fullName.length < 2) problems.push('name is missing');
    if (fullName.length > 120) problems.push('name is longer than 120 characters');
    if (code && !CODE_PATTERN.test(code)) problems.push(`code "${code}" must be 3–20 letters, digits or dashes`);
    if (code && seenCodes.has(code)) problems.push(`code ${code} is also on line ${seenCodes.get(code)}`);
    if (group.length > 60) problems.push('group is longer than 60 characters');
    const joinedOn = joinedRaw ? normalizeDate(joinedRaw) : null;
    if (joinedRaw && !joinedOn) problems.push(`"${joinedRaw}" is not a date (use DD/MM/YYYY)`);

    if (problems.length > 0) {
      issues.push({ line, message: problems.join('; ') });
      return;
    }
    if (code) seenCodes.set(code, line);
    rows.push({
      line,
      fullName,
      ...(code ? { code } : {}),
      ...(group ? { group } : {}),
      ...(joinedOn ? { joinedOn } : {}),
    });
  });

  return {
    rows,
    issues,
    columns: {
      fullName: column.fullName ?? [column.surname, column.firstName, column.otherNames].filter(Boolean).join(' + '),
      code: column.code,
      group: column.group,
      joinedOn: column.joinedOn,
    },
  };
}

export const TEMPLATE_CSV =
  'Full name,Code,Group,Joined on\r\nAdaeze Okafor,,JSS 1,14/09/2026\r\nTunde Bello,STF-014,Teachers,\r\n';
