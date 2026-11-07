// Day helpers for scripts/page-dates.mjs, kept apart so tests can import them without writing lib/pageDates.ts.

// The day of `date` in the build machine's own time zone, as YYYY-MM-DD. toISOString() would give the UTC day, which
// in the evening in the Americas is already tomorrow (a guide edited on 2026-11-06 showed 2026-11-07).
export function localDay(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

// A page's date, never later than the build day: a commit made in a time zone ahead of the build machine's could
// otherwise date a page in the future.
export function capDay(day, today) {
  return day > today ? today : day;
}
