/**
 * Ordering helpers for the manually sorted lists (sidebar groups and sources).
 *
 * Kept separate from `AppStore` so the move maths is unit-testable without a
 * database or ArkUI, and so both lists share one implementation.
 */

/**
 * Splice `items[fromIndex]` to `toIndex`, returning a new array.
 *
 * Returns null for a no-op or an out-of-range request, which lets callers skip
 * the database write as well as the re-render.
 */
export function moveItem<T>(items: T[], fromIndex: number, toIndex: number): T[] | null {
  if (fromIndex === toIndex) {
    return null;
  }
  if (fromIndex < 0 || fromIndex >= items.length) {
    return null;
  }
  if (toIndex < 0 || toIndex >= items.length) {
    return null;
  }

  const next: T[] = [];
  for (const item of items) {
    next.push(item);
  }
  const moved: T = next[fromIndex];
  next.splice(fromIndex, 1);
  next.splice(toIndex, 0, moved);
  return next;
}

/** The ids of a list whose elements expose an `id`, in list order. */
export interface Identified {
  id: number;
}

export function idsOf<T extends Identified>(items: T[]): number[] {
  const ids: number[] = [];
  for (const item of items) {
    ids.push(item.id);
  }
  return ids;
}
