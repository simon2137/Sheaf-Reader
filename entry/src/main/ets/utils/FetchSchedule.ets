/**
 * The per-source fetch-frequency rule, ported from the original's `fetchItems`.
 *
 * Upstream builds the list of sources to fetch with
 *
 *     sourcesState = Object.values(sourcesState).filter(s => {
 *       let last = s.lastFetched ? s.lastFetched.getTime() : 0
 *       return !s.serviceRef &&
 *         (last > timenow || last + (s.fetchFrequency || 0) * 60000 <= timenow)
 *     })
 *
 * Three properties of that expression are easy to get wrong, so they are
 * stated explicitly here and pinned by the harness:
 *
 *  1. `fetchFrequency === 0` (the "unlimited" option) can never block a fetch:
 *     the bound collapses to `last <= now`, which any past fetch satisfies.
 *  2. A source that has never been fetched has `lastFetched === 0`, which is
 *     also always in the past — so it is always due.
 *  3. `last > now` is a separate disjunct. If the device clock moves backwards
 *     after a fetch, `lastFetched` ends up in the future, and upstream still
 *     fetches rather than waiting out the whole interval. A plain
 *     `elapsed >= frequency` test would silently stall such a source.
 *
 * Scope matters as much as the arithmetic: upstream applies this rule only on
 * the unscoped path. Its `sids !== null` branch filters on `!s.serviceRef`
 * alone, so an explicit scoped refresh (a group or a single source) fetches
 * even a source whose limit has not elapsed.
 */
export class FetchSchedule {
  /**
   * The original's automatic-fetch interval choices, in minutes, from
   * `settings/app.tsx`: Never, 10, 15, 20, 30, 45 minutes and 1 hour. (The
   * port used to offer 15/30/60/120/240/720 instead — that is the *source*
   * list below, i.e. the two dropdowns had been swapped.)
   */
  static INTERVALS: number[] = [0, 10, 15, 20, 30, 45, 60];

  /**
   * The original's per-source `fetchFrequency` choices, in minutes, from
   * `settings/sources.tsx`: Unlimited, 15, 30, 1h, 2h, 3h, 6h and 12h.
   */
  static FREQUENCIES: number[] = [0, 15, 30, 60, 120, 180, 360, 720];

  /**
   * Keep a stored value that is not in the original's list selectable rather
   * than showing the wrong entry: the port's earlier builds wrote intervals and
   * frequencies the original never offers (2h/4h/12h intervals), and snapping
   * them would silently change a setting the user chose.
   */
  static options(values: number[], stored: number): number[] {
    return values.indexOf(stored) >= 0 ? values : values.concat([stored]);
  }

  /**
   * True when the source's limit allows another fetch. `lastFetched` is a
   * millisecond timestamp (0 for "never"), `fetchFrequency` is in minutes and
   * `now` is the current millisecond timestamp.
   */
  static due(fetchFrequency: number, lastFetched: number, now: number): boolean {
    if (lastFetched > now) {
      return true;
    }
    const frequency: number = fetchFrequency > 0 ? fetchFrequency : 0;
    return lastFetched + frequency * 60000 <= now;
  }

  /**
   * Upstream only consults the frequency limit while refreshing *everything*:
   * a scoped refresh names the sources it wants and bypasses the limit.
   */
  static appliesToScope(scopeIds: number[] | null): boolean {
    return scopeIds === null;
  }
}
