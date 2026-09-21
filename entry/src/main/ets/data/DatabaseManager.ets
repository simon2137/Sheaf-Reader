import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Feed, Article, FeedGroup, ServiceArticleRow } from '../model/Models';
import { FeedFilter, FilterClause } from '../model/Filter';
import { StorageSize } from '../utils/StorageSize';
import { TimeBounds } from '../utils/TimeBounds';

/**
 * Database manager using HarmonyOS relational store.
 */
export class DatabaseManager {
  private static instance: DatabaseManager;
  /**
   * Upper bound on rows scanned when an in-memory regex search is active.
   * Larger than one screen so scrolling stays useful, small enough to bound
   * the per-keystroke cost.
   */
  static readonly SEARCH_SCAN_LIMIT: number = 800;

  private store: relationalStore.RdbStore | null = null;
  private context: common.Context | null = null;

  private constructor() {}

  static getInstance(): DatabaseManager {
    if (!DatabaseManager.instance) {
      DatabaseManager.instance = new DatabaseManager();
    }
    return DatabaseManager.instance;
  }

  async init(context: common.Context): Promise<void> {
    this.context = context;
    const config: relationalStore.StoreConfig = {
      name: 'sheaf_reader.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };

    this.store = await relationalStore.getRdbStore(context, config);

    // Create tables
    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS feeds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL DEFAULT '',
        link TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        group_id INTEGER NOT NULL DEFAULT -1,
        icon_url TEXT NOT NULL DEFAULT '',
        last_fetched INTEGER NOT NULL DEFAULT 0,
        service_ref TEXT NOT NULL DEFAULT '',
        fetch_frequency INTEGER NOT NULL DEFAULT 0,
        open_target INTEGER NOT NULL DEFAULT 0,
        text_dir INTEGER NOT NULL DEFAULT 0,
        hidden INTEGER NOT NULL DEFAULT 0,
        rules_json TEXT NOT NULL DEFAULT ''
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feed_id INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        link TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        snippet TEXT NOT NULL DEFAULT '',
        published INTEGER NOT NULL DEFAULT 0,
        fetched INTEGER NOT NULL DEFAULT 0,
        read INTEGER NOT NULL DEFAULT 0,
        starred INTEGER NOT NULL DEFAULT 0,
        image_url TEXT NOT NULL DEFAULT '',
        guid TEXT NOT NULL DEFAULT '',
        service_ref TEXT NOT NULL DEFAULT '',
        hidden INTEGER NOT NULL DEFAULT 0,
        notify INTEGER NOT NULL DEFAULT 0,
        UNIQUE(feed_id, guid)
      )
    `);

    // Migrations for databases created before the sync-service columns existed.
    // RdbStore has no "ADD COLUMN IF NOT EXISTS", so a duplicate-column error
    // is the success path on every run after the first.
    await this.ensureColumn('feeds', 'service_ref', "TEXT NOT NULL DEFAULT ''");
    await this.ensureColumn('feeds', 'fetch_frequency', 'INTEGER NOT NULL DEFAULT 0');
    await this.ensureColumn('feeds', 'open_target', 'INTEGER NOT NULL DEFAULT 0');
    await this.ensureColumn('feeds', 'text_dir', 'INTEGER NOT NULL DEFAULT 0');
    await this.ensureColumn('feeds', 'hidden', 'INTEGER NOT NULL DEFAULT 0');
    await this.ensureColumn('feeds', 'rules_json', "TEXT NOT NULL DEFAULT ''");
    await this.ensureColumn('articles', 'service_ref', "TEXT NOT NULL DEFAULT ''");
    await this.ensureColumn('articles', 'hidden', 'INTEGER NOT NULL DEFAULT 0');
    await this.ensureColumn('articles', 'notify', 'INTEGER NOT NULL DEFAULT 0');
    // Manual ordering for the sidebar's drag-and-drop sort. Existing rows all
    // get 0, so the tie-break on `id` keeps their current order until the user
    // reorders something.
    await this.ensureColumn('groups', 'sort_order', 'INTEGER NOT NULL DEFAULT 0');
    await this.ensureColumn('feeds', 'sort_order', 'INTEGER NOT NULL DEFAULT 0');

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        is_expanded INTEGER NOT NULL DEFAULT 1
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL DEFAULT ''
      )
    `);

    // Create indices
    await this.store.executeSql('CREATE INDEX IF NOT EXISTS idx_articles_feed ON articles(feed_id)');
    await this.store.executeSql('CREATE INDEX IF NOT EXISTS idx_articles_read ON articles(read)');
    await this.store.executeSql('CREATE INDEX IF NOT EXISTS idx_articles_starred ON articles(starred)');
    await this.store.executeSql('CREATE INDEX IF NOT EXISTS idx_articles_published ON articles(published DESC)');
    await this.store.executeSql('CREATE INDEX IF NOT EXISTS idx_articles_service_ref ON articles(service_ref)');
    await this.store.executeSql('CREATE INDEX IF NOT EXISTS idx_feeds_service_ref ON feeds(service_ref)');
  }

  /**
   * Add a column when an older database predates it. A duplicate-column error
   * is expected on every run after the first and is not a failure.
   */
  private async ensureColumn(table: string, column: string, definition: string): Promise<void> {
    if (!this.store) return;
    try {
      await this.store.executeSql(
        'ALTER TABLE ' + table + ' ADD COLUMN ' + column + ' ' + definition);
    } catch (err) {
      // Already present.
    }
  }

  // ========== Feed Operations ==========

  async insertFeed(feed: Feed): Promise<number> {
    if (!this.store) return -1;
    const values: relationalStore.ValuesBucket = {
      url: feed.url,
      title: feed.title,
      link: feed.link,
      description: feed.description,
      group_id: feed.groupId,
      icon_url: feed.iconUrl,
      last_fetched: feed.lastFetched,
      service_ref: feed.serviceRef,
      fetch_frequency: feed.fetchFrequency,
      open_target: feed.openTarget,
      text_dir: feed.textDir,
      hidden: feed.hidden ? 1 : 0,
      rules_json: feed.rulesJson,
      sort_order: await this.nextFeedOrder()
    };
    const result = await this.store.insert('feeds', values);
    return result;
  }

  async updateFeed(feed: Feed): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = {
      title: feed.title,
      link: feed.link,
      description: feed.description,
      group_id: feed.groupId,
      icon_url: feed.iconUrl,
      last_fetched: feed.lastFetched,
      service_ref: feed.serviceRef,
      fetch_frequency: feed.fetchFrequency,
      open_target: feed.openTarget,
      text_dir: feed.textDir,
      hidden: feed.hidden ? 1 : 0,
      rules_json: feed.rulesJson
    };
    const predicates = new relationalStore.RdbPredicates('feeds');
    predicates.equalTo('id', feed.id);
    await this.store.update(values, predicates);
  }

  async deleteFeed(feedId: number): Promise<void> {
    if (!this.store) return;
    // Delete articles first
    let articlePredicates = new relationalStore.RdbPredicates('articles');
    articlePredicates.equalTo('feed_id', feedId);
    await this.store.delete(articlePredicates);

    // Delete feed
    let feedPredicates = new relationalStore.RdbPredicates('feeds');
    feedPredicates.equalTo('id', feedId);
    await this.store.delete(feedPredicates);
  }

  /**
   * Drop every downloaded article for a feed while keeping the subscription.
   * Used when an existing local source is adopted by a sync service.
   */
  async deleteArticlesForFeed(feedId: number): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('feed_id', feedId);
    await this.store.delete(predicates);
  }

  /**
   * Move a feed into a group.
   */
  async setFeedGroup(feedId: number, groupId: number): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = { group_id: groupId };
    const predicates = new relationalStore.RdbPredicates('feeds');
    predicates.equalTo('id', feedId);
    await this.store.update(values, predicates);
  }

  /**
   * Map a feeds row onto the model. Shared by every feed query so a new
   * column is added in exactly one place.
   */
  private parseFeedRow(resultSet: relationalStore.ResultSet): Feed {
    const feed = new Feed();
    feed.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    feed.url = resultSet.getString(resultSet.getColumnIndex('url'));
    feed.title = resultSet.getString(resultSet.getColumnIndex('title'));
    feed.link = resultSet.getString(resultSet.getColumnIndex('link'));
    feed.description = resultSet.getString(resultSet.getColumnIndex('description'));
    feed.groupId = resultSet.getLong(resultSet.getColumnIndex('group_id'));
    feed.iconUrl = resultSet.getString(resultSet.getColumnIndex('icon_url'));
    feed.lastFetched = resultSet.getLong(resultSet.getColumnIndex('last_fetched'));
    feed.serviceRef = resultSet.getString(resultSet.getColumnIndex('service_ref'));
    feed.fetchFrequency = resultSet.getLong(resultSet.getColumnIndex('fetch_frequency'));
    feed.openTarget = resultSet.getLong(resultSet.getColumnIndex('open_target'));
    feed.textDir = resultSet.getLong(resultSet.getColumnIndex('text_dir'));
    feed.hidden = resultSet.getLong(resultSet.getColumnIndex('hidden')) === 1;
    feed.rulesJson = resultSet.getString(resultSet.getColumnIndex('rules_json'));
    return feed;
  }

  async getAllFeeds(): Promise<Feed[]> {
    if (!this.store) return [];
    const resultSet = await this.store.querySql(
      'SELECT * FROM feeds ORDER BY sort_order ASC, id ASC');
    const feeds: Feed[] = [];
    while (resultSet.goToNextRow()) {
      feeds.push(this.parseFeedRow(resultSet));
    }
    resultSet.close();
    return feeds;
  }

  async getFeedById(feedId: number): Promise<Feed | null> {
    if (!this.store) return null;
    const predicates = new relationalStore.RdbPredicates('feeds');
    predicates.equalTo('id', feedId);
    const resultSet = await this.store.query(predicates);
    if (resultSet.goToFirstRow()) {
      const feed = this.parseFeedRow(resultSet);
      resultSet.close();
      return feed;
    }
    resultSet.close();
    return null;
  }

  async getFeedByUrl(url: string): Promise<Feed | null> {
    if (!this.store) return null;
    const predicates = new relationalStore.RdbPredicates('feeds');
    predicates.equalTo('url', url);
    const resultSet = await this.store.query(predicates);
    if (resultSet.goToFirstRow()) {
      const feed = this.parseFeedRow(resultSet);
      resultSet.close();
      return feed;
    }
    resultSet.close();
    return null;
  }

  async getFeedByServiceRef(serviceRef: string): Promise<Feed | null> {
    if (!this.store) return null;
    const predicates = new relationalStore.RdbPredicates('feeds');
    predicates.equalTo('service_ref', serviceRef);
    const resultSet = await this.store.query(predicates);
    if (resultSet.goToFirstRow()) {
      const feed = this.parseFeedRow(resultSet);
      resultSet.close();
      return feed;
    }
    resultSet.close();
    return null;
  }

  /**
   * Every feed currently linked to the sync service, keyed by serviceRef.
   */
  async getServiceLinkedFeeds(): Promise<Map<string, Feed>> {
    const map: Map<string, Feed> = new Map<string, Feed>();
    if (!this.store) return map;
    const sql = "SELECT * FROM feeds WHERE service_ref <> ''";
    const resultSet = await this.store.querySql(sql);
    while (resultSet.goToNextRow()) {
      const feed = this.parseFeedRow(resultSet);
      map.set(feed.serviceRef, feed);
    }
    resultSet.close();
    return map;
  }

  // ========== Article Operations ==========

  async insertArticle(article: Article): Promise<number> {
    if (!this.store) return -1;
    const values: relationalStore.ValuesBucket = {
      feed_id: article.feedId,
      title: article.title,
      link: article.link,
      author: article.author,
      content: article.content,
      snippet: article.snippet,
      published: article.published,
      fetched: article.fetched,
      read: article.read ? 1 : 0,
      starred: article.starred ? 1 : 0,
      image_url: article.imageUrl,
      guid: article.guid,
      service_ref: article.serviceRef,
      hidden: article.hidden ? 1 : 0,
      notify: article.notify ? 1 : 0
    };
    try {
      const result = await this.store.insert('articles', values);
      return result;
    } catch {
      // Duplicate entry, ignore
      return -1;
    }
  }

  async insertArticles(articles: Article[]): Promise<number> {
    if (!this.store) return 0;
    let inserted = 0;
    for (const article of articles) {
      const id = await this.insertArticle(article);
      if (id > 0) inserted++;
    }
    return inserted;
  }

  async updateArticle(article: Article): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = {
      read: article.read ? 1 : 0,
      starred: article.starred ? 1 : 0
    };
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('id', article.id);
    await this.store.update(values, predicates);
  }

  /**
   * Note on article bodies: this port used to expose `updateArticleContent` so
   * that "Load full content" could overwrite the stored body. The original never
   * does that — a loaded page is view state, and choosing the action again
   * restores the feed's own text — so the write is gone and the fetched page
   * lives in `AppStore.loadedPages` instead.
   */

  async markArticleRead(articleId: number, read: boolean): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = {
      read: read ? 1 : 0
    };
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('id', articleId);
    await this.store.update(values, predicates);
  }

  /**
   * Mark a specific set of articles read. Used by the "mark above / below as
   * read" actions, which work on the window the user is looking at rather than
   * on a whole source.
   */
  async markArticlesRead(articleIds: number[]): Promise<void> {
    if (!this.store || articleIds.length === 0) return;
    const values: relationalStore.ValuesBucket = { read: 1 };
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.in('id', articleIds);
    await this.store.update(values, predicates);
  }

  /**
   * Per-article background-notification flag (`article.notify`). Rules can set
   * it at fetch time; this is the manual equivalent.
   */
  async setArticleNotify(articleId: number, notify: boolean): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = { notify: notify ? 1 : 0 };
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('id', articleId);
    await this.store.update(values, predicates);
  }

  async markArticleStarred(articleId: number, starred: boolean): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = {
      starred: starred ? 1 : 0
    };
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('id', articleId);
    await this.store.update(values, predicates);
  }

  /**
   * Hide or unhide one article. Hidden articles drop out of every list unless
   * the "show hidden" filter bit is set.
   */
  async markArticleHidden(articleId: number, hidden: boolean): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = {
      hidden: hidden ? 1 : 0
    };
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('id', articleId);
    await this.store.update(values, predicates);
  }

  /**
   * Mark every unread article in scope as read.
   *
   * `cutoff > 0` bounds the update to one side of a publication date, mirroring
   * the original's `markAllRead(sids, date, before)`:
   * `before` keeps articles at or before the date, otherwise at or after it.
   * `cutoff = 0` means "no date bound", so the whole scope is marked.
   */
  async markAllRead(feedId: number, groupId: number,
                    cutoff: number = 0, before: boolean = true): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = { read: 1 };
    let predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('read', 0);

    if (feedId >= 0) {
      predicates.equalTo('feed_id', feedId);
    } else if (groupId >= 0) {
      // Get feeds in group
      const feedPredicates = new relationalStore.RdbPredicates('feeds');
      feedPredicates.equalTo('group_id', groupId);
      const feedResult = await this.store.query(feedPredicates, ['id']);
      const feedIds: number[] = [];
      while (feedResult.goToNextRow()) {
        feedIds.push(feedResult.getLong(feedResult.getColumnIndex('id')));
      }
      feedResult.close();
      if (feedIds.length > 0) {
        predicates.in('feed_id', feedIds);
      }
    }

    if (cutoff > 0) {
      if (before) {
        predicates.lessThanOrEqualTo('published', cutoff);
      } else {
        predicates.greaterThanOrEqualTo('published', cutoff);
      }
    }

    await this.store.update(values, predicates);
  }

  /**
   * Articles matching a filter, newest first.
   *
   * Read/starred/hidden constraints are pushed into SQL. The search pattern is
   * applied in memory because HarmonyOS relationalStore cannot register the
   * REGEXP function the original relies on; when a pattern is present a
   * bounded window is scanned and then sliced by offset/limit.
   */
  async getArticles(
    filter: FeedFilter,
    feedId: number = -1,
    groupId: number = -1,
    limit: number = 100,
    offset: number = 0
  ): Promise<Article[]> {
    if (!this.store) return [];

    let sql = `
      SELECT a.*, f.title as feed_title
      FROM articles a
      LEFT JOIN feeds f ON a.feed_id = f.id
      WHERE 1=1
    `;
    const args: (string | number)[] = [];

    // Sources marked "hide in all articles" drop out of the unscoped list only;
    // opening the source itself still shows everything it holds.
    const excludeHiddenFeeds: boolean = feedId < 0 && groupId < 0;
    const clause: FilterClause = FeedFilter.toSql(filter, excludeHiddenFeeds);
    sql += clause.sql;
    for (const arg of clause.args) {
      args.push(arg);
    }

    if (feedId >= 0) {
      sql += ' AND a.feed_id = ?';
      args.push(feedId);
    } else if (groupId >= 0) {
      sql += ' AND a.feed_id IN (SELECT id FROM feeds WHERE group_id = ?)';
      args.push(groupId);
    }

    sql += ' ORDER BY a.published DESC';

    const hasSearch: boolean = filter.search.length > 0;
    if (hasSearch) {
      sql += ' LIMIT ?';
      args.push(DatabaseManager.SEARCH_SCAN_LIMIT);
    } else {
      sql += ' LIMIT ? OFFSET ?';
      args.push(limit, offset);
    }

    const resultSet = await this.store.querySql(sql, args);
    const rows: Article[] = [];
    while (resultSet.goToNextRow()) {
      rows.push(this.parseArticleRow(resultSet));
    }
    resultSet.close();

    if (!hasSearch) {
      return rows;
    }

    const matched: Article[] = [];
    for (const article of rows) {
      if (FeedFilter.testArticle(filter, article.title, article.snippet,
        article.author, article.read, article.starred, article.hidden)) {
        matched.push(article);
      }
    }
    return matched.slice(offset, offset + limit);
  }

  async getArticleById(articleId: number): Promise<Article | null> {
    if (!this.store) return null;
    const sql = `
      SELECT a.*, f.title as feed_title
      FROM articles a
      LEFT JOIN feeds f ON a.feed_id = f.id
      WHERE a.id = ?
    `;
    const resultSet = await this.store.querySql(sql, [articleId]);
    if (resultSet.goToFirstRow()) {
      const article = this.parseArticleRow(resultSet);
      resultSet.close();
      return article;
    }
    resultSet.close();
    return null;
  }

  async getUnreadCount(feedId: number, groupId: number): Promise<number> {
    if (!this.store) return 0;
    let sql = 'SELECT COUNT(*) as cnt FROM articles WHERE read = 0';
    const args: (string | number)[] = [];

    if (feedId >= 0) {
      sql += ' AND feed_id = ?';
      args.push(feedId);
    } else if (groupId >= 0) {
      sql += ' AND feed_id IN (SELECT id FROM feeds WHERE group_id = ?)';
      args.push(groupId);
    }

    const resultSet = await this.store.querySql(sql, args);
    let count = 0;
    if (resultSet.goToFirstRow()) {
      count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
    }
    resultSet.close();
    return count;
  }

  async getTotalUnreadCount(): Promise<number> {
    return this.getUnreadCount(-1, -1);
  }

  async getStarredCount(): Promise<number> {
    if (!this.store) return 0;
    const sql = 'SELECT COUNT(*) as cnt FROM articles WHERE starred = 1';
    const resultSet = await this.store.querySql(sql);
    let count = 0;
    if (resultSet.goToFirstRow()) {
      count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
    }
    resultSet.close();
    return count;
  }

  /**
   * Delete articles published before `days` ago, mirroring the original's
   * `deleteArticles` (`src/containers/settings/app-container.tsx`) which runs
   * `where(items.date < now - days * 86400000)` and nothing else.
   *
   * Two consequences are deliberate and match the original:
   *  - `days = 0` puts the cutoff at *now*, so every article is deleted. That is
   *    how "Delete all articles" is expressed; there is no separate call.
   *  - **Starred articles are not spared.** An earlier revision of this port
   *    added `starred = 0`, which silently kept articles the user asked to
   *    remove and made the reported count differ from the original's.
   */
  async deleteOldArticles(days: number): Promise<number> {
    if (!this.store) return 0;
    const cutoff = TimeBounds.daysAgo(days, Date.now());
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.lessThan('published', cutoff);
    return await this.store.delete(predicates);
  }

  /**
   * Serialized size of the whole article store, backing the "Clean up" section's
   * "Around N MB of local storage is occupied by articles" hint.
   */
  async getArticleStorageBytes(): Promise<number> {
    const articles: Article[] = await this.getAllArticles();
    return StorageSize.totalBytes(articles);
  }

  private parseArticleRow(resultSet: relationalStore.ResultSet): Article {
    const article = new Article();
    article.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    article.feedId = resultSet.getLong(resultSet.getColumnIndex('feed_id'));
    article.title = resultSet.getString(resultSet.getColumnIndex('title'));
    article.link = resultSet.getString(resultSet.getColumnIndex('link'));
    article.author = resultSet.getString(resultSet.getColumnIndex('author'));
    article.content = resultSet.getString(resultSet.getColumnIndex('content'));
    article.snippet = resultSet.getString(resultSet.getColumnIndex('snippet'));
    article.published = resultSet.getLong(resultSet.getColumnIndex('published'));
    article.fetched = resultSet.getLong(resultSet.getColumnIndex('fetched'));
    article.read = resultSet.getLong(resultSet.getColumnIndex('read')) === 1;
    article.starred = resultSet.getLong(resultSet.getColumnIndex('starred')) === 1;
    article.imageUrl = resultSet.getString(resultSet.getColumnIndex('image_url'));
    article.guid = resultSet.getString(resultSet.getColumnIndex('guid'));
    article.serviceRef = resultSet.getString(resultSet.getColumnIndex('service_ref'));
    article.hidden = resultSet.getLong(resultSet.getColumnIndex('hidden')) === 1;
    article.notify = resultSet.getLong(resultSet.getColumnIndex('notify')) === 1;
    const feedTitleIdx = resultSet.getColumnIndex('feed_title');
    if (feedTitleIdx >= 0) {
      article.feedTitle = resultSet.getString(feedTitleIdx);
    }
    return article;
  }

  // ========== Sync Service Operations ==========

  /**
   * Local rows that carry a service ref together with their read/star state,
   * used to reconcile against the remote sets.
   */
  async getServiceLinkedArticles(): Promise<ServiceArticleRow[]> {
    const rows: ServiceArticleRow[] = [];
    if (!this.store) return rows;
    const sql = "SELECT service_ref, read, starred FROM articles"
      + " WHERE service_ref <> '' AND (read = 0 OR starred = 1)";
    const resultSet = await this.store.querySql(sql);
    while (resultSet.goToNextRow()) {
      const row = new ServiceArticleRow();
      row.serviceRef = resultSet.getString(resultSet.getColumnIndex('service_ref'));
      row.read = resultSet.getLong(resultSet.getColumnIndex('read')) === 1;
      row.starred = resultSet.getLong(resultSet.getColumnIndex('starred')) === 1;
      rows.push(row);
    }
    resultSet.close();
    return rows;
  }

  /**
   * Apply a remote read/star state to one local article.
   */
  async setServiceState(serviceRef: string, read: boolean, starred: boolean): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = {
      read: read ? 1 : 0,
      starred: starred ? 1 : 0
    };
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('service_ref', serviceRef);
    await this.store.update(values, predicates);
  }

  async setReadByServiceRef(serviceRef: string, read: boolean): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = { read: read ? 1 : 0 };
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('service_ref', serviceRef);
    await this.store.update(values, predicates);
  }

  async setStarredByServiceRef(serviceRef: string, starred: boolean): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = { starred: starred ? 1 : 0 };
    const predicates = new relationalStore.RdbPredicates('articles');
    predicates.equalTo('service_ref', serviceRef);
    await this.store.update(values, predicates);
  }

  /**
   * Service refs of unread articles belonging to the given feeds, optionally
   * bounded by date. Mirrors the predicate set the original builds in
   * `markAllRead`.
   */
  async getUnreadServiceRefs(feedIds: number[], date: number, before: boolean): Promise<string[]> {
    const refs: string[] = [];
    if (!this.store || feedIds.length === 0) return refs;

    const placeholders: string[] = [];
    const args: (string | number)[] = [];
    for (const id of feedIds) {
      placeholders.push('?');
      args.push(id);
    }

    let sql = 'SELECT service_ref FROM articles WHERE feed_id IN ('
      .concat(placeholders.join(','))
      .concat(") AND read = 0 AND service_ref <> ''");
    if (date > 0) {
      sql = sql.concat(before ? ' AND published <= ?' : ' AND published >= ?');
      args.push(date);
    }

    const resultSet = await this.store.querySql(sql, args);
    while (resultSet.goToNextRow()) {
      refs.push(resultSet.getString(resultSet.getColumnIndex('service_ref')));
    }
    resultSet.close();
    return refs;
  }

  /**
   * Drop the remote association from every feed and article. Used when the
   * sync service is disconnected; keeps the downloaded content.
   */
  async unlinkAllServiceFeeds(): Promise<void> {
    if (!this.store) return;
    const feedPredicates = new relationalStore.RdbPredicates('feeds');
    const feedValues: relationalStore.ValuesBucket = { service_ref: '' };
    await this.store.update(feedValues, feedPredicates);

    const articlePredicates = new relationalStore.RdbPredicates('articles');
    const articleValues: relationalStore.ValuesBucket = { service_ref: '' };
    await this.store.update(articleValues, articlePredicates);
  }

  // ========== Group Operations ==========

  async insertGroup(name: string): Promise<number> {
    if (!this.store) return -1;
    const values: relationalStore.ValuesBucket = {
      name: name,
      is_expanded: 1,
      sort_order: await this.nextGroupOrder()
    };
    return await this.store.insert('groups', values);
  }

  /** One past the highest existing order, so new groups append at the end. */
  private async nextGroupOrder(): Promise<number> {
    if (!this.store) return 0;
    const resultSet = await this.store.querySql(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM groups');
    let next: number = 0;
    if (resultSet.goToFirstRow()) {
      next = resultSet.getLong(resultSet.getColumnIndex('next'));
    }
    resultSet.close();
    return next;
  }

  /** Same, for a newly added source. */
  private async nextFeedOrder(): Promise<number> {
    if (!this.store) return 0;
    const resultSet = await this.store.querySql(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM feeds');
    let next: number = 0;
    if (resultSet.goToFirstRow()) {
      next = resultSet.getLong(resultSet.getColumnIndex('next'));
    }
    resultSet.close();
    return next;
  }

  /** Rename a group, mirroring the original's group name editor. */
  async updateGroupName(groupId: number, name: string): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = { name: name };
    const predicates = new relationalStore.RdbPredicates('groups');
    predicates.equalTo('id', groupId);
    await this.store.update(values, predicates);
  }

  /**
   * Persist a group's expansion, mirroring the original's
   * `toggleGroupExpansion` → `saveGroups`. The `is_expanded` column has been
   * written since the groups table was created but nothing ever read or
   * updated it, so every group collapsed on relaunch.
   */
  async setGroupExpanded(groupId: number, expanded: boolean): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = { is_expanded: expanded ? 1 : 0 };
    const predicates = new relationalStore.RdbPredicates('groups');
    predicates.equalTo('id', groupId);
    await this.store.update(values, predicates);
  }

  /**
   * Persist a manual group order. The ids are written in array order, so the
   * caller only has to move one entry and hand back the whole list.
   */
  async setGroupOrder(groupIds: number[]): Promise<void> {
    if (!this.store) return;
    for (let i = 0; i < groupIds.length; i++) {
      const values: relationalStore.ValuesBucket = { sort_order: i };
      const predicates = new relationalStore.RdbPredicates('groups');
      predicates.equalTo('id', groupIds[i]);
      await this.store.update(values, predicates);
    }
  }

  /** Persist a manual source order, used for drag-and-drop in the sidebar. */
  async setFeedOrder(feedIds: number[]): Promise<void> {
    if (!this.store) return;
    for (let i = 0; i < feedIds.length; i++) {
      const values: relationalStore.ValuesBucket = { sort_order: i };
      const predicates = new relationalStore.RdbPredicates('feeds');
      predicates.equalTo('id', feedIds[i]);
      await this.store.update(values, predicates);
    }
  }

  async getAllGroups(): Promise<FeedGroup[]> {
    if (!this.store) return [];
    const resultSet = await this.store.querySql(
      'SELECT id, name, is_expanded FROM groups ORDER BY sort_order ASC, id ASC');
    const groups: FeedGroup[] = [];
    while (resultSet.goToNextRow()) {
      const group = new FeedGroup();
      group.id = resultSet.getLong(resultSet.getColumnIndex('id'));
      group.name = resultSet.getString(resultSet.getColumnIndex('name'));
      group.isExpanded = resultSet.getLong(resultSet.getColumnIndex('is_expanded')) === 1;
      groups.push(group);
    }
    resultSet.close();
    return groups;
  }

  async deleteGroup(groupId: number): Promise<void> {
    if (!this.store) return;
    // Reset feeds to no group
    const values: relationalStore.ValuesBucket = { group_id: -1 };
    const feedPredicates = new relationalStore.RdbPredicates('feeds');
    feedPredicates.equalTo('group_id', groupId);
    await this.store.update(values, feedPredicates);

    // Delete group
    const groupPredicates = new relationalStore.RdbPredicates('groups');
    groupPredicates.equalTo('id', groupId);
    await this.store.delete(groupPredicates);
  }

  // ========== Settings Operations ==========

  async getSetting(key: string, defaultValue: string = ''): Promise<string> {
    if (!this.store) return defaultValue;
    const predicates = new relationalStore.RdbPredicates('settings');
    predicates.equalTo('key', key);
    const resultSet = await this.store.query(predicates, ['value']);
    if (resultSet.goToFirstRow()) {
      const value = resultSet.getString(resultSet.getColumnIndex('value'));
      resultSet.close();
      return value;
    }
    resultSet.close();
    return defaultValue;
  }

  async setSetting(key: string, value: string): Promise<void> {
    if (!this.store) return;
    const values: relationalStore.ValuesBucket = {
      key: key,
      value: value
    };
    const predicates = new relationalStore.RdbPredicates('settings');
    predicates.equalTo('key', key);
    const existing = await this.store.query(predicates);
    if (existing.goToFirstRow()) {
      await this.store.update(values, predicates);
    } else {
      await this.store.insert('settings', values);
    }
    existing.close();
  }

  async close(): Promise<void> {
    if (this.store) {
      await this.store.close();
      this.store = null;
    }
  }

  // ========== Backup / Restore ==========

  /**
   * Every article, newest first. Unlike `getArticles` this is not paginated —
   * a backup must contain the whole library.
   */
  async getAllArticles(): Promise<Article[]> {
    if (!this.store) return [];
    const resultSet = await this.store.querySql(
      'SELECT a.*, f.title as feed_title FROM articles a'
      + ' LEFT JOIN feeds f ON a.feed_id = f.id ORDER BY a.published DESC');
    const articles: Article[] = [];
    while (resultSet.goToNextRow()) {
      articles.push(this.parseArticleRow(resultSet));
    }
    resultSet.close();
    return articles;
  }

  /** Every key/value setting, for inclusion in a backup. */
  async getAllSettings(): Promise<Map<string, string>> {
    const settings: Map<string, string> = new Map<string, string>();
    if (!this.store) return settings;
    const resultSet = await this.store.querySql('SELECT key, value FROM settings');
    while (resultSet.goToNextRow()) {
      settings.set(resultSet.getString(resultSet.getColumnIndex('key')),
        resultSet.getString(resultSet.getColumnIndex('value')));
    }
    resultSet.close();
    return settings;
  }

  async setSettings(settings: Map<string, string>): Promise<void> {
    if (!this.store) return;
    const keys: string[] = [];
    settings.forEach((value: string, key: string) => {
      keys.push(key);
    });
    for (const key of keys) {
      const value: string | undefined = settings.get(key);
      if (value !== undefined) {
        await this.setSetting(key, value);
      }
    }
  }

  /**
   * Remove all user content — articles, feeds and groups — while leaving
   * settings alone. Used as the first half of a restore.
   */
  async clearContent(): Promise<void> {
    if (!this.store) return;
    await this.store.executeSql('DELETE FROM articles');
    await this.store.executeSql('DELETE FROM feeds');
    await this.store.executeSql('DELETE FROM groups');
  }

  /**
   * Insert a group and return its new id, or -1 on failure.
   */
  async insertGroupNamed(name: string): Promise<number> {
    return this.insertGroup(name);
  }

  /**
   * Insert a feed preserving nothing but the data; returns the new id so
   * articles can be re-pointed at it during a restore.
   */
  async insertFeedRaw(feed: Feed): Promise<number> {
    return this.insertFeed(feed);
  }
}