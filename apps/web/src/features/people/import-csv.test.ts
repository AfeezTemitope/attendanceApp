import { describe, expect, it } from 'vitest';
import { normalizeDate, parsePeopleCsv, TEMPLATE_CSV } from './import-csv';

describe('normalizeDate', () => {
  it.each([
    ['2026-09-14', '2026-09-14'],
    ['14/09/2026', '2026-09-14'],
    ['4-9-2026', '2026-09-04'],
    [' 01/10/2026 ', '2026-10-01'],
  ])('reads %s as %s', (input, expected) => expect(normalizeDate(input)).toBe(expected));

  it.each(['31/02/2026', '2026-13-01', '09/14', 'yesterday', '14.09.2026'])('rejects %s', (input) =>
    expect(normalizeDate(input)).toBeNull(),
  );
});

describe('parsePeopleCsv', () => {
  it('parses the template and generates no issues', () => {
    const result = parsePeopleCsv(TEMPLATE_CSV);
    expect(result.issues).toEqual([]);
    expect(result.rows).toEqual([
      { line: 2, fullName: 'Adaeze Okafor', group: 'JSS 1', joinedOn: '2026-09-14' },
      { line: 3, fullName: 'Tunde Bello', code: 'STF-014', group: 'Teachers' },
    ]);
  });

  it('understands school-list headers: Surname / First name / Other names, Class, Admission No', () => {
    const csv =
      '\uFEFFS/N,Surname,First Name,Other Names,Class,Admission No.\n1,OKAFOR,Adaeze,Chioma,JSS 1A,adm-0042\n';
    const result = parsePeopleCsv(csv);
    expect(result.rows).toEqual([{ line: 2, fullName: 'OKAFOR Adaeze Chioma', code: 'ADM-0042', group: 'JSS 1A' }]);
    expect(result.columns).toMatchObject({ code: 'Admission No.', group: 'Class' });
  });

  it('reports bad rows by spreadsheet line and keeps the good ones', () => {
    const csv = [
      'Name,Code,Joined',
      'Ada Obi,ABC-1,14/09/2026',
      ',XYZ,',
      'Bola Ade,AB,',
      'Chi Eze,abc-1,',
      'Dayo Ojo,,31/02/2026',
      '',
      'Efe Uche,,',
    ].join('\n');
    const result = parsePeopleCsv(csv);
    expect(result.rows.map((row) => row.fullName)).toEqual(['Ada Obi', 'Efe Uche']);
    expect(result.issues).toEqual([
      { line: 3, message: 'name is missing' },
      { line: 4, message: 'code "AB" must be 3–20 letters, digits or dashes' },
      { line: 5, message: 'code ABC-1 is also on line 2' },
      { line: 6, message: '"31/02/2026" is not a date (use DD/MM/YYYY)' },
    ]);
  });

  it('explains what is missing when there is no name column', () => {
    const result = parsePeopleCsv('Code,Group\nA1B,JSS1\n');
    expect(result.rows).toEqual([]);
    expect(result.issues[0]?.message).toMatch(/No name column/);
  });
});
