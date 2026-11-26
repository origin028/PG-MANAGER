/** Helpers for "now serving / up next" on the food screens. Times come as "08:00 AM", "13:30" or "08:00:00". */
export type MealLike = { meal_type: string; start_time?: string | null; end_time?: string | null };

export const MEAL_ORDER = ["BREAKFAST", "LUNCH", "SNACKS", "DINNER"];
const DEFAULT_START: Record<string, number> = { BREAKFAST: 7 * 60 + 30, LUNCH: 12 * 60 + 30, SNACKS: 17 * 60, DINNER: 20 * 60 };

/** Minutes after midnight, or null if the text can't be read. */
export function toMinutes(t?: string | null): number | null {
  const m = /^\s*(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?\s*$/i.exec(t ?? "");
  if (!m) return null;
  let h = Number(m[1]) % 24;
  const ap = m[3]?.toUpperCase();
  if (ap === "PM" && h < 12) h += 12;
  if (ap === "AM" && h === 12) h = 0;
  return h * 60 + Number(m[2]);
}

export const mealName = (t: string) => t.charAt(0) + t.slice(1).toLowerCase();

/** Which of today's meals is being served now, and which comes next. */
export function mealNow<T extends MealLike>(meals: T[], at = new Date()): { now: T | null; next: T | null } {
  const mins = at.getHours() * 60 + at.getMinutes();
  const list = [...meals]
    .map((m) => {
      const start = toMinutes(m.start_time) ?? DEFAULT_START[m.meal_type] ?? 0;
      const end = toMinutes(m.end_time) ?? start + 120;
      return { m, start, end };
    })
    .sort((a, b) => a.start - b.start);
  const now = list.find((x) => mins >= x.start && mins < x.end)?.m ?? null;
  const next = list.find((x) => x.start > mins)?.m ?? null;
  return { now, next };
}
