import { Feed, Article, FeedGroup, ParsedFeed, AddFeedResult, ImportSummary, ParsedOpml, OpmlEntry, SourceRule, FetchFailure, RefreshOutcome } from '../model/Models';
import { DatabaseManager } from '../data/DatabaseManager';
import { FeedFetcher } from '../utils/FeedFetcher';
import { FeedParser } from '../utils/FeedParser';
import { UrlUtils } from '../utils/UrlUtils';
import { RuleEngine } from './RuleEngine';
import { FeedFilter } from '../model/Filter';
import { ScopeFilter } from '../utils/ScopeFilter';
import { FetchSchedule } from '../utils/FetchSchedule';

/**
 * Coordinates fetching, parsing and persistence of feeds.
 */
export class FeedService {
  private static instance: FeedService | null = null;
  private db: DatabaseManager = DatabaseManager.getInstance();
  private fetching: boolean = false;

  private constructor() {
  }

  static getInstance(): FeedService {
    if (FeedService.instance === null) {
      FeedService.instance = new FeedService();
    }
    return FeedService.instance;
  }

  isFetching(): boolean {
    return this.fetching;
  }

  /**
   * Add a feed by URL, discovering the real feed address when needed.
   */
  async addFeed(rawUrl: string, title: string, groupId: number): Promise<AddFeedResult> {
    const url: string = UrlUtils.normalize(rawUrl);
    if (!url) {
      return { success: false, message: 'feed_invalid', feed: null };
    }

    const existing: Feed | null = await this.db.getFeedByUrl(url);
    if (existing !== null) {
      return { success: false, message: 'feed_exists', feed: null };
    }

    let parsed: ParsedFeed | null = await FeedFetcher.fetchFeed(url);
    if (parsed === null) {
      const discovered: string | null = await FeedFetcher.discoverFeed(url);
      if (discovered !== null && discovered !== url) {
        parsed = await FeedFetcher.fetchFeed(discovered);
      }
    }

    if (parsed === null) {
      return { success: false, message: 'feed_invalid', feed: null };
    }

    const feed: Feed = parsed.feed;
    feed.url = url;
    if (title) {
      feed.title = title;
    }
    feed.groupId = groupId;
    feed.lastFetched = Date.now();

    const feedId: number = await this.db.insertFeed(feed);
    if (feedId < 0) {
      return { success: false, message: 'feed_invalid', feed: null };
    }
    feed.id = feedId;

    for (const article of parsed.articles) {
      article.feedId = feedId;
      // Rules run before persistence, as in the original's `checkItem`.
      RuleEngine.applyForFeed(feed.rulesJson, article);
      await this.db.insertArticle(article);
    }

    return { success: true, message: 'feed_added', feed: feed };
  }

  /**
   * Refresh a single feed.
   *
   * Returns how many articles were inserted and appends to `outcome` any
   * failure or rule-requested notification, so the caller can surface them in
   * the notification log instead of failing silently.
   */
  async refreshFeed(feedId: number, outcome: RefreshOutcome): Promise<number> {
    const feed: Feed | null = await this.db.getFeedById(feedId);
    if (feed === null) {
      return 0;
    }

    const parsed: ParsedFeed | null = await FeedFetcher.fetchFeed(feed.url);
    if (parsed === null) {
      outcome.failures.push(new FetchFailure(feed.title,
        FeedFetcher.lastError.length > 0 ? FeedFetcher.lastError : 'Could not load the feed'));
      return 0;
    }

    // Fill in metadata that is still missing, but never overwrite what is
    // already there: the original sets a source's name once, when it is empty
    // (`fetchMetaData`), and its refresh path (`fetchItems`) does not touch the
    // name at all. Overwriting here silently reverted a rename — and every
    // OPML-imported title, which is how three sources ended up all called
    // "Local Full Text" and three all called "Notify Source".
    if (feed.title.length === 0 && parsed.feed.title) {
      feed.title = parsed.feed.title;
    }
    if (feed.link.length === 0 && parsed.feed.link) {
      feed.link = parsed.feed.link;
    }
    if (feed.description.length === 0 && parsed.feed.description) {
      feed.description = parsed.feed.description;
    }
    feed.lastFetched = Date.now();
    await this.db.updateFeed(feed);

    let inserted: number = 0;
    for (const article of parsed.articles) {
      article.feedId = feedId;
      article.feedTitle = feed.title;
      RuleEngine.applyForFeed(feed.rulesJson, article);
      const id: number = await this.db.insertArticle(article);
      if (id > 0) {
        inserted++;
        if (article.notify) {
          outcome.notified.push(article);
        }
      }
    }
    return inserted;
  }

  /**
   * Refresh every locally-managed feed sequentially.
   *
   * Sources linked to a sync service are skipped: their articles arrive
   * through the service, and fetching them directly as well would store
   * duplicates that carry no `serviceRef` and therefore never sync read state.
   */
  async refreshAllFeeds(onProgress: (done: number, total: number) => void,
    applyFrequency: boolean = false,
    scopeIds: number[] | null = null): Promise<RefreshOutcome> {
    const outcome: RefreshOutcome = new RefreshOutcome();
    if (this.fetching) {
      return outcome;
    }
    this.fetching = true;
    try {
      const all: Feed[] = await this.db.getAllFeeds();
      let feeds: Feed[] = all.filter((f: Feed) => !f.isServiceManaged());
      if (scopeIds !== null) {
        // A scoped refresh (the group / source context menu) touches only the
        // sources it names, mirroring the original's `fetchItems(false, sids)`.
        feeds = feeds.filter((f: Feed) => ScopeFilter.contains(scopeIds, f.id));
      }
      const now: number = Date.now();
      for (let i = 0; i < feeds.length; i++) {
        // The original consults `fetchFrequency` on the unscoped path only:
        // `fetchItems()` (the header button, F5, the startup run and the
        // interval timer all call it with no source list) filters by
        // `lastFetched + fetchFrequency * 60000 <= now`, while the
        // `sids !== null` branch filters on `!serviceRef` alone. So pressing
        // refresh does *not* override a source's own limit — only a scoped
        // refresh (a group or a single source) does.
        if (!applyFrequency || FetchSchedule.due(feeds[i].fetchFrequency,
          feeds[i].lastFetched, now)) {
          outcome.inserted += await this.refreshFeed(feeds[i].id, outcome);
        }
        onProgress(i + 1, feeds.length);
      }
      return outcome;
    } finally {
      this.fetching = false;
    }
  }

  /** Persist per-source settings edited in the source settings dialog. */
  async updateFeed(feed: Feed): Promise<void> {
    await this.db.updateFeed(feed);
  }

  async getFeedsWithCounts(): Promise<Feed[]> {
    const feeds: Feed[] = await this.db.getAllFeeds();
    for (const feed of feeds) {
      feed.unreadCount = await this.db.getUnreadCount(feed.id, -1);
    }
    return feeds;
  }

  async getGroupsWithCounts(): Promise<FeedGroup[]> {
    const groups: FeedGroup[] = await this.db.getAllGroups();
    for (const group of groups) {
      group.unreadCount = await this.db.getUnreadCount(-1, group.id);
    }
    return groups;
  }

  async getArticles(filter: FeedFilter, feedId: number, groupId: number,
    limit: number, offset: number): Promise<Article[]> {
    return this.db.getArticles(filter, feedId, groupId, limit, offset);
  }

  async getArticleById(articleId: number): Promise<Article | null> {
    return this.db.getArticleById(articleId);
  }

  async markArticleRead(articleId: number, read: boolean): Promise<void> {
    await this.db.markArticleRead(articleId, read);
  }

  /** Mark a set of articles read in one statement. */
  async markArticlesRead(articleIds: number[]): Promise<void> {
    await this.db.markArticlesRead(articleIds);
  }

  async setArticleNotify(articleId: number, notify: boolean): Promise<void> {
    await this.db.setArticleNotify(articleId, notify);
  }

  async markArticleStarred(articleId: number, starred: boolean): Promise<void> {
    await this.db.markArticleStarred(articleId, starred);
  }

  async markArticleHidden(articleId: number, hidden: boolean): Promise<void> {
    await this.db.markArticleHidden(articleId, hidden);
  }

  /**
   * Mark every unread article in scope as read, optionally bounded to one side
   * of a publication date (`cutoff = 0` means no bound).
   */
  async markAllRead(feedId: number, groupId: number,
                    cutoff: number = 0, before: boolean = true): Promise<void> {
    await this.db.markAllRead(feedId, groupId, cutoff, before);
  }

  async deleteFeed(feedId: number): Promise<void> {
    await this.db.deleteFeed(feedId);
  }

  async createGroup(name: string): Promise<number> {
    return this.db.insertGroup(name);
  }

  /** Rename a group, mirroring the original's group name editor. */
  async updateGroupName(groupId: number, name: string): Promise<void> {
    await this.db.updateGroupName(groupId, name);
  }

  /** Persist a manual group order (drag-and-drop in the sidebar). */
  async setGroupOrder(groupIds: number[]): Promise<void> {
    await this.db.setGroupOrder(groupIds);
  }

  /** Persist a group's expansion, the original's `saveGroups` on toggle. */
  async setGroupExpanded(groupId: number, expanded: boolean): Promise<void> {
    await this.db.setGroupExpanded(groupId, expanded);
  }

  /** Persist a manual source order (drag-and-drop in the sidebar). */
  async setFeedOrder(feedIds: number[]): Promise<void> {
    await this.db.setFeedOrder(feedIds);
  }

  async deleteGroup(groupId: number): Promise<void> {
    await this.db.deleteGroup(groupId);
  }

  /**
   * Put a source into a group, or take it out of every group (`groupId = -1`).
   *
   * Until this existed the only caller of the database write was the sync
   * service importing a remote folder, so a source could never be grouped by
   * hand — which also made the original's `groups.addToGroup` /
   * `groups.deleteSource` / `groups.capacity` unreachable.
   */
  async setFeedGroup(feedId: number, groupId: number): Promise<void> {
    await this.db.setFeedGroup(feedId, groupId);
  }

  async getUnreadCount(feedId: number, groupId: number): Promise<number> {
    return this.db.getUnreadCount(feedId, groupId);
  }

  async getTotalUnreadCount(): Promise<number> {
    return this.db.getTotalUnreadCount();
  }

  async getStarredCount(): Promise<number> {
    return this.db.getStarredCount();
  }

  async exportOpml(): Promise<string> {
    const feeds: Feed[] = await this.db.getAllFeeds();
    const groups: FeedGroup[] = await this.db.getAllGroups();
    return FeedParser.generateOpml(feeds, groups);
  }

  /**
   * Import feeds from an OPML document, creating referenced groups.
   */
  async importOpml(opmlContent: string): Promise<ImportSummary> {
    const parsed: ParsedOpml = FeedParser.parseOpml(opmlContent);
    let success: number = 0;
    let failed: number = 0;

    const groupIds: Map<string, number> = new Map<string, number>();
    const existingGroups: FeedGroup[] = await this.db.getAllGroups();
    for (const group of existingGroups) {
      groupIds.set(group.name, group.id);
    }

    for (const entry of parsed.entries) {
      let groupId: number = -1;
      if (entry.groupName) {
        const known: number | undefined = groupIds.get(entry.groupName);
        if (known !== undefined) {
          groupId = known;
        } else {
          const created: number = await this.db.insertGroup(entry.groupName);
          if (created > 0) {
            groupIds.set(entry.groupName, created);
            groupId = created;
          }
        }
      }

      const result: AddFeedResult = await this.addFeed(entry.url, entry.title, groupId);
      if (result.success) {
        success++;
      } else {
        failed++;
      }
    }

    return { success: success, failed: failed };
  }

  /**
   * Delete articles published before `days` ago. `days = 0` deletes every
   * article, which is how the settings "Delete all articles" choice is
   * expressed. Returns the number of rows removed.
   */
  async deleteArticles(days: number): Promise<number> {
    return this.db.deleteOldArticles(days);
  }

  /** Serialized size of the article store, for the "Clean up" hint. */
  async articleStorageBytes(): Promise<number> {
    return this.db.getArticleStorageBytes();
  }

  /**
   * Persist a source's rule set. Rules are stored as JSON on the feed row,
   * matching the original's `RSSSource.rules`.
   */
  async saveRules(feedId: number, rules: SourceRule[]): Promise<void> {
    const feed: Feed | null = await this.db.getFeedById(feedId);
    if (feed === null) {
      return;
    }
    feed.rulesJson = SourceRule.toJson(rules);
    await this.db.updateFeed(feed);
  }

  async getRules(feedId: number): Promise<SourceRule[]> {
    const feed: Feed | null = await this.db.getFeedById(feedId);
    if (feed === null) {
      return [];
    }
    return SourceRule.fromJson(feed.rulesJson);
  }

  /**
   * Convenience wrapper used by first-run seeding.
   */
  async importEntries(entries: OpmlEntry[]): Promise<ImportSummary> {
    let success: number = 0;
    let failed: number = 0;
    for (const entry of entries) {
      const result: AddFeedResult = await this.addFeed(entry.url, entry.title, -1);
      if (result.success) {
        success++;
      } else {
        failed++;
      }
    }
    return { success: success, failed: failed };
  }
}
