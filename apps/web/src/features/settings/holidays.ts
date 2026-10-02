/** Fixed-date public holidays in Nigeria. Movable ones (Easter, Eid) change yearly: add those by hand. */
export const NIGERIAN_FIXED_HOLIDAYS = [
  ['01-01', "New Year's Day"],
  ['05-01', "Workers' Day"],
  ['06-12', 'Democracy Day'],
  ['10-01', 'Independence Day'],
  ['12-25', 'Christmas Day'],
  ['12-26', 'Boxing Day'],
] as const;
