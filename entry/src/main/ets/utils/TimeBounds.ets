/** One day in milliseconds, the unit the day-based menus count in. */
const DAY_MS: number = 24 * 60 * 60 * 1000;

/**
 * Day arithmetic shared by the two date-based menus: "delete articles from …
 * days ago" and "mark articles from … days ago as read".
 *
 * Both the original and this port express the choice as a timestamp so it can be
 * handed straight to a `published` comparison.
 *
 * Note that the two callers read a `0` day count differently, which is why the
 * conversion is kept here rather than merged with the "no bound" test:
 *  - **delete**: `0` days means "now", so `published < now` removes everything —
 *    that is how the original encodes "Delete all articles";
 *  - **mark read**: `0` is passed around as "no date predicate at all", so the
 *    caller must not convert it here.
 */
export class TimeBounds {
  /** Timestamp `days` days before `now`. */
  static daysAgo(days: number, now: number): number {
    return now - days * DAY_MS;
  }
}
