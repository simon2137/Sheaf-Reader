import { Feed } from '../model/Models';

/**
 * The sidebar's "unread sources only" filter — the original's
 * `unreadSourcesOnly`, persisted under the same name (`menu.tsx`).
 *
 * With it on, a source is listed only while it has unread articles, and a group
 * is listed only while at least one of its sources does. The rule is pure, so it
 * is asserted in `verify/harness.ts` rather than only observed on a device.
 */
export class SourceFilter {
  /** Whether one source is listed under the current setting. */
  static visible(feed: Feed, unreadOnly: boolean): boolean {
    return !unreadOnly || feed.unreadCount > 0;
  }

  /** The subset of `feeds` that is listed under the current setting. */
  static filter(feeds: Feed[], unreadOnly: boolean): Feed[] {
    const visible: Feed[] = [];
    for (const feed of feeds) {
      if (SourceFilter.visible(feed, unreadOnly)) {
        visible.push(feed);
      }
    }
    return visible;
  }

  /**
   * Whether a group is listed: with the filter on it needs at least one source
   * with unread articles, so an emptied group does not linger as a header.
   */
  static groupVisible(feeds: Feed[], unreadOnly: boolean): boolean {
    if (!unreadOnly) {
      return true;
    }
    for (const feed of feeds) {
      if (feed.unreadCount > 0) {
        return true;
      }
    }
    return false;
  }
}
