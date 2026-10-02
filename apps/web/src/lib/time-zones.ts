const FALLBACK = [
  'Africa/Lagos',
  'Africa/Accra',
  'Africa/Nairobi',
  'Africa/Johannesburg',
  'Africa/Cairo',
  'Europe/London',
  'UTC',
];

/** All IANA zones the browser knows, African zones first. */
export function timeZones(): string[] {
  const all = typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : FALLBACK;
  const african = all.filter((zone) => zone.startsWith('Africa/'));
  return [...african, ...all.filter((zone) => !zone.startsWith('Africa/'))];
}
