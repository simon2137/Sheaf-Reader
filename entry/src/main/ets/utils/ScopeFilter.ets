import { Feed } from '../model/Models';

/**
 * Source scopes for the group / source context menu (the original's `sids`).
 *
 * A scope is either one source, one group's sources, or — when neither is set —
 * everything. The same rule decides which sources the menu marks as read and
 * which ones a scoped refresh fetches, so it lives here rather than being
 * written out twice.
 */
export class ScopeFilter {
  /**
   * The feed ids a scope selects. `feedId >= 0` wins over `groupId`, matching
   * the original, where a source row passes exactly that source's id.
   */
  static feedIds(feeds: Feed[], groupId: number, feedId: number): number[] {
    const ids: number[] = [];
    for (const feed of feeds) {
      if (feedId >= 0 && feed.id !== feedId) {
        continue;
      }
      if (groupId >= 0 && feed.groupId !== groupId) {
        continue;
      }
      ids.push(feed.id);
    }
    return ids;
  }

  /** True when `id` is inside `scopeIds`; `null` means "no scope, i.e. all". */
  static contains(scopeIds: number[] | null, id: number): boolean {
    return scopeIds === null || scopeIds.indexOf(id) >= 0;
  }
}
