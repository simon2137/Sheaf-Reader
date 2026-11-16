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
   * Whether a group is listed.
   *
   * A group with sources is listed only while one of them has unread articles,
   * which is the rule the original's `menu.tsx` applies to a group's contents.
   *
   * A group with **no** sources is always listed. The filter is a statement
   * about sources — "hide the ones with nothing unread" — and an empty group has
   * no source to be read or unread, so there is nothing for it to hide. Hiding
   * it made a group created by hand vanish the moment the "created" toast
   * appeared: new groups start empty, and with the filter on there was no row to
   * assign sources to, rename or delete, so the group was unreachable until the
   * filter was switched off. Listing it also keeps an emptied group visible as
   * something to delete or refill.
   */
  static groupVisible(feeds: Feed[], unreadOnly: boolean): boolean {
    if (!unreadOnly || feeds.length === 0) {
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
