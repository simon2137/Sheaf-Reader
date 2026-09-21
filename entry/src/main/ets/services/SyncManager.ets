import {
  Feed, Article, ServiceConfigs, SyncService, SyncResult, ServiceArticleRow, FeedGroup
} from '../model/Models';
import { DatabaseManager } from '../data/DatabaseManager';
import { MinifluxService, SourceMapping, ItemBatch, RemoteState } from './MinifluxService';
import { GReaderService, GrItemBatch, GrSubscription } from './GReaderService';
import { FeedbinService } from './FeedbinService';
import { FeverService } from './FeverService';

/**
 * Result of the source-reconciliation phase.
 */
class SourceSyncOutcome {
  added: number = 0;
  removed: number = 0;
}

/** Remote read/star sets, normalised across the supported services. */
class RemoteSets {
  unread: Set<string> = new Set<string>();
  starred: Set<string> = new Set<string>();
}

/**
 * Orchestrates a sync run, ported from `syncWithService` and its three helper
 * thunks in the original `scripts/models/service.ts`.
 *
 * The original interleaves store dispatches with the service calls; the phases
 * and their order are preserved here, with `DatabaseManager` standing in for
 * the redux store.
 *
 *   updateSources -> syncItems -> fetchItems
 */
export class SyncManager {
  static readonly SETTING_KEY: string = 'service_configs';

  /** Load the persisted service configuration. */
  static async loadConfigs(): Promise<ServiceConfigs> {
    const raw: string = await DatabaseManager.getInstance().getSetting(SyncManager.SETTING_KEY, '');
    return ServiceConfigs.fromJson(raw);
  }

  static async saveConfigs(configs: ServiceConfigs): Promise<void> {
    await DatabaseManager.getInstance().setSetting(
      SyncManager.SETTING_KEY, ServiceConfigs.toJson(configs));
  }

  /**
   * Validate credentials without performing a full sync. For GReader-family
   * services this also refreshes an expired token, mirroring the original's
   * `reauthenticate` step.
   */
  static async authenticate(configs: ServiceConfigs): Promise<boolean> {
    if (configs.type === SyncService.Miniflux) {
      return MinifluxService.authenticate(configs);
    }
    if (configs.type === SyncService.GReader || configs.type === SyncService.Inoreader) {
      if (configs.auth.length > 0 && await GReaderService.authenticate(configs)) {
        return true;
      }
      // No usable token: exchange the stored credentials for a fresh one.
      return GReaderService.reauthenticate(configs);
    }
    if (configs.type === SyncService.Feedbin || configs.type === SyncService.Nextcloud) {
      return FeedbinService.authenticate(configs);
    }
    if (configs.type === SyncService.Fever) {
      return FeverService.authenticate(configs);
    }
    return false;
  }

  /**
   * Whether a service implementation backs this configuration.
   */
  static isSupported(type: number): boolean {
    return type === SyncService.Miniflux
      || type === SyncService.GReader
      || type === SyncService.Inoreader
      || type === SyncService.Feedbin
      || type === SyncService.Nextcloud
      || type === SyncService.Fever;
  }

  /**
   * Run a full synchronisation. `onProgress` receives short stage labels so
   * the UI can show what is happening.
   */
  static async sync(configs: ServiceConfigs,
    onProgress: (stage: string) => void): Promise<SyncResult> {
    const result: SyncResult = {
      ok: false,
      message: '',
      sourcesAdded: 0,
      sourcesRemoved: 0,
      itemsFetched: 0,
      localUpdates: 0,
      notified: []
    };

    if (configs.type === SyncService.None) {
      result.message = 'No sync service configured';
      return result;
    }
    if (!SyncManager.isSupported(configs.type)) {
      result.message = 'This service is not implemented yet';
      return result;
    }

    try {
      onProgress('Verifying credentials');
      if (!await SyncManager.authenticate(configs)) {
        result.message = 'Cannot connect to service';
        return result;
      }
      // A refreshed GReader token lives on the configs object; persist it so
      // the next run does not have to log in again.
      await SyncManager.saveConfigs(configs);

      onProgress('Updating sources');
      const sourceOutcome: SourceSyncOutcome = await SyncManager.updateSources(configs);
      result.sourcesAdded = sourceOutcome.added;
      result.sourcesRemoved = sourceOutcome.removed;

      onProgress('Syncing read state');
      result.localUpdates = await SyncManager.syncItems(configs);

      onProgress('Fetching articles');
      result.itemsFetched = await SyncManager.fetchItems(configs, result);

      await SyncManager.saveConfigs(configs);
      result.ok = true;
      result.message = 'Sync complete';
      return result;
    } catch (err) {
      console.error('SyncManager.sync failed: ' + JSON.stringify(err));
      result.message = 'Sync failed: ' + JSON.stringify(err);
      return result;
    }
  }

  /**
   * Reconcile the local source list with the service's feed list.
   * Port of the original `updateSources`.
   */
  private static async updateSources(configs: ServiceConfigs): Promise<SourceSyncOutcome> {
    const outcome: SourceSyncOutcome = new SourceSyncOutcome();
    const db: DatabaseManager = DatabaseManager.getInstance();

    const mapping: SourceMapping | null = await SyncManager.fetchSourceMapping(configs);
    if (mapping === null) {
      throw new Error('Failed to fetch feeds from service');
    }

    // Import service categories as local groups first, so the membership step
    // below can look them up by name.
    const groupIds: Map<string, number> = new Map<string, number>();
    if (configs.importGroups) {
      const existingGroups: FeedGroup[] = await db.getAllGroups();
      for (const group of existingGroups) {
        groupIds.set(group.name, group.id);
      }
      for (const title of mapping.categories) {
        if (!groupIds.has(title)) {
          const created: number = await db.insertGroup(title);
          if (created > 0) {
            groupIds.set(title, created);
          }
        }
      }
    }

    // Local sources already linked to the service, keyed by serviceRef.
    const linked: Map<string, Feed> = await db.getServiceLinkedFeeds();

    for (const remote of mapping.sources) {
      const already: Feed | undefined = linked.get(remote.serviceRef);
      if (already !== undefined) {
        linked.delete(remote.serviceRef);
        SyncManager.assignGroup(remote, mapping, groupIds, db, already.id);
        continue;
      }

      const byUrl: Feed | null = await db.getFeedByUrl(remote.url);
      if (byUrl === null) {
        // New source on the service.
        remote.lastFetched = Date.now();
        const insertedId: number = await db.insertFeed(remote);
        if (insertedId > 0) {
          outcome.added++;
          SyncManager.assignGroup(remote, mapping, groupIds, db, insertedId);
        }
      } else if (byUrl.serviceRef !== remote.serviceRef) {
        // The URL exists locally but is not yet tied to the service: adopt it
        // and drop previously downloaded articles, matching upstream.
        byUrl.serviceRef = remote.serviceRef;
        await db.updateFeed(byUrl);
        await db.deleteArticlesForFeed(byUrl.id);
        outcome.added++;
        SyncManager.assignGroup(remote, mapping, groupIds, db, byUrl.id);
      }
    }

    // Anything still linked locally no longer exists on the service.
    const toRemove: Feed[] = [];
    linked.forEach((feed: Feed) => {
      toRemove.push(feed);
    });
    for (const feed of toRemove) {
      outcome.removed++;
      await db.deleteFeed(feed.id);
    }

    if (configs.importGroups) {
      configs.importGroups = false;
    }

    return outcome;
  }

  /**
   * Phase 1 data source, dispatched by service type.
   */
  private static async fetchSourceMapping(configs: ServiceConfigs): Promise<SourceMapping | null> {
    if (configs.type === SyncService.Miniflux) {
      return MinifluxService.updateSources(configs);
    }
    if (configs.type === SyncService.GReader || configs.type === SyncService.Inoreader) {
      return SyncManager.gReaderSourceMapping(configs);
    }
    if (configs.type === SyncService.Feedbin || configs.type === SyncService.Nextcloud) {
      return FeedbinService.updateSources(configs);
    }
    if (configs.type === SyncService.Fever) {
      return FeverService.updateSources(configs);
    }
    return null;
  }

  /**
   * GReader / Inoreader subscriptions to local sources, with category labels
   * promoted to groups when group import is active.
   */
  private static async gReaderSourceMapping(configs: ServiceConfigs): Promise<SourceMapping | null> {
    const subscriptions: GrSubscription[] | null = await GReaderService.updateSources(configs);
    if (subscriptions === null) {
      return null;
    }

    const mapping: SourceMapping = new SourceMapping();

    if (configs.importGroups) {
      const seen: Set<string> = new Set<string>();
      for (const subscription of subscriptions) {
        const group: string = GReaderService.groupOf(subscription);
        if (group.length > 0) {
          if (!seen.has(group)) {
            seen.add(group);
            mapping.categories.push(group);
          }
          mapping.groupsMap.set(subscription.id, group);
        }
      }
    }

    for (const subscription of subscriptions) {
      const source: Feed | null = GReaderService.toSource(subscription, configs.useInt64);
      if (source !== null) {
        mapping.sources.push(source);
      }
    }

    return mapping;
  }

  /**
   * Assign a service feed to its imported group, when group import is active.
   */
  private static assignGroup(remote: Feed, mapping: SourceMapping,
    groupIds: Map<string, number>, db: DatabaseManager, localFeedId: number): void {
    if (localFeedId <= 0) {
      return;
    }
    const category: string | undefined = mapping.groupsMap.get(remote.serviceRef);
    if (category === undefined) {
      return;
    }
    const groupId: number | undefined = groupIds.get(category);
    if (groupId === undefined) {
      return;
    }
    // Fire-and-forget; group membership is cosmetic and must not fail a sync.
    db.setFeedGroup(localFeedId, groupId);
  }

  /**
   * Reconcile remote unread/starred sets with local rows.
   * Port of the original `syncItems`.
   *
   * A ref still present in the remote set after deletion means the service is
   * the authority; a ref that the service no longer reports is cleared
   * locally.
   */
  private static async syncItems(configs: ServiceConfigs): Promise<number> {
    const db: DatabaseManager = DatabaseManager.getInstance();
    const state: RemoteSets | null = await SyncManager.fetchRemoteSets(configs);

    if (state === null) {
      // Reconciling against a partial or empty set would mark every locally
      // unread article as read. Abort the sync instead.
      throw new Error('Remote read/star state unavailable; sync aborted so local state is preserved');
    }

    const unreadCopy: Set<string> = new Set<string>();
    state.unread.forEach((ref: string) => unreadCopy.add(ref));
    const starredCopy: Set<string> = new Set<string>();
    state.starred.forEach((ref: string) => starredCopy.add(ref));

    const rows: ServiceArticleRow[] = await db.getServiceLinkedArticles();
    let updates: number = 0;

    for (const row of rows) {
      if (!row.read && !unreadCopy.delete(row.serviceRef)) {
        // Locally unread, but the service does not list it as unread.
        await db.setReadByServiceRef(row.serviceRef, true);
        updates++;
      }
      if (row.starred && !starredCopy.delete(row.serviceRef)) {
        // Locally starred, but the service does not list it as starred.
        await db.setStarredByServiceRef(row.serviceRef, false);
        updates++;
      }
    }

    // Whatever remains is remote-only state to be pulled down.
    const remainingUnread: string[] = [];
    unreadCopy.forEach((ref: string) => remainingUnread.push(ref));
    for (const ref of remainingUnread) {
      await db.setReadByServiceRef(ref, false);
      updates++;
    }

    const remainingStarred: string[] = [];
    starredCopy.forEach((ref: string) => remainingStarred.push(ref));
    for (const ref of remainingStarred) {
      await db.setStarredByServiceRef(ref, true);
      updates++;
    }

    return updates;
  }

  /**
   * Phase 2 data source: the remote unread/starred id sets. Null when the
   * remote state could not be read completely.
   */
  private static async fetchRemoteSets(configs: ServiceConfigs): Promise<RemoteSets | null> {
    const sets: RemoteSets = new RemoteSets();

    if (configs.type === SyncService.Miniflux) {
      const state: RemoteState | null = await MinifluxService.syncItems(configs);
      if (state === null) {
        return null;
      }
      sets.unread = state.unread;
      sets.starred = state.starred;
      return sets;
    }

    if (configs.type === SyncService.GReader || configs.type === SyncService.Inoreader) {
      const state = await GReaderService.syncItems(configs);
      if (state === null) {
        return null;
      }
      sets.unread = state.unread;
      sets.starred = state.starred;
      return sets;
    }

    if (configs.type === SyncService.Feedbin || configs.type === SyncService.Nextcloud) {
      const state: RemoteState | null = await FeedbinService.syncItems(configs);
      if (state === null) {
        return null;
      }
      sets.unread = state.unread;
      sets.starred = state.starred;
      return sets;
    }

    if (configs.type === SyncService.Fever) {
      const state: RemoteState | null = await FeverService.syncItems(configs);
      if (state === null) {
        return null;
      }
      sets.unread = state.unread;
      sets.starred = state.starred;
      return sets;
    }

    return sets;
  }

  /**
   * Pull new entries and persist them.
   * Port of the original `fetchItems`.
   */
  private static async fetchItems(configs: ServiceConfigs,
    result: SyncResult): Promise<number> {
    if (configs.type === SyncService.Miniflux) {
      return SyncManager.fetchItemsMiniflux(configs, result);
    }
    if (configs.type === SyncService.GReader || configs.type === SyncService.Inoreader) {
      return SyncManager.fetchItemsGReader(configs, result);
    }
    if (configs.type === SyncService.Feedbin || configs.type === SyncService.Nextcloud) {
      return SyncManager.fetchItemsRest(configs, result);
    }
    if (configs.type === SyncService.Fever) {
      return SyncManager.fetchItemsFever(configs, result);
    }
    return 0;
  }

  /**
   * Insert articles, returning how many rows were actually created. Articles
   * whose rules asked for a notification are collected on the sync result.
   */
  private static async persistArticles(articles: Article[],
    result: SyncResult): Promise<number> {
    const db: DatabaseManager = DatabaseManager.getInstance();
    let inserted: number = 0;
    for (const article of articles) {
      const id: number = await db.insertArticle(article);
      if (id > 0) {
        inserted++;
        article.id = id;
        if (article.notify) {
          result.notified.push(article);
        }
      }
    }
    return inserted;
  }

  private static async fetchItemsMiniflux(configs: ServiceConfigs,
    result: SyncResult): Promise<number> {
    const db: DatabaseManager = DatabaseManager.getInstance();

    const sourceMap: Map<string, Feed> = await db.getServiceLinkedFeeds();
    const batch: ItemBatch = await MinifluxService.fetchItems(configs, sourceMap);

    if (batch.articles.length === 0) {
      return 0;
    }

    const inserted: number = await SyncManager.persistArticles(batch.articles, result);

    // Advance the incremental cursor only after the rows are stored, so a
    // failed write cannot skip entries on the next run.
    configs.lastId = batch.lastId;

    // Push rule-driven state changes back to the service.
    for (const ref of batch.pushRead) {
      await MinifluxService.markRead(configs, ref);
    }
    for (const ref of batch.pushUnread) {
      await MinifluxService.markUnread(configs, ref);
    }
    for (const ref of batch.pushStar) {
      await MinifluxService.toggleBookmark(configs, ref);
    }
    for (const ref of batch.pushUnstar) {
      await MinifluxService.toggleBookmark(configs, ref);
    }

    return inserted;
  }

  /**
   * Feedbin / Nextcloud pull. Both advance a single cursor — Feedbin a
   * timestamp, Nextcloud an item id — and both push rule-driven state back.
   */
  private static async fetchItemsRest(configs: ServiceConfigs,
    result: SyncResult): Promise<number> {
    const db: DatabaseManager = DatabaseManager.getInstance();

    const sourceMap: Map<string, Feed> = await db.getServiceLinkedFeeds();
    const batch: ItemBatch = await FeedbinService.fetchItems(configs, sourceMap);

    if (batch.articles.length === 0) {
      return 0;
    }

    const inserted: number = await SyncManager.persistArticles(batch.articles, result);

    // Advance the cursors only after the rows are stored, so a failed write
    // cannot skip entries on the next run.
    if (batch.lastId > 0) {
      configs.lastId = batch.lastId;
    }
    if (batch.lastFetched > 0) {
      configs.lastFetched = batch.lastFetched;
    }

    for (const ref of batch.pushRead) {
      await FeedbinService.markRead(configs, ref);
    }
    for (const ref of batch.pushUnread) {
      await FeedbinService.markUnread(configs, ref);
    }
    for (const ref of batch.pushStar) {
      await FeedbinService.star(configs, ref);
    }
    for (const ref of batch.pushUnstar) {
      await FeedbinService.unstar(configs, ref);
    }

    return inserted;
  }

  /**
   * Fever pull. Its cursor is the highest item id seen, and its `before`
   * timestamp is refreshed on every run so a later "mark feed read" cannot
   * reach items this client has not received.
   */
  private static async fetchItemsFever(configs: ServiceConfigs,
    result: SyncResult): Promise<number> {
    const db: DatabaseManager = DatabaseManager.getInstance();

    const sourceMap: Map<string, Feed> = await db.getServiceLinkedFeeds();
    const batch: ItemBatch = await FeverService.fetchItems(configs, sourceMap);

    if (batch.articles.length === 0) {
      return 0;
    }

    const inserted: number = await SyncManager.persistArticles(batch.articles, result);

    if (batch.lastId > 0) {
      configs.lastId = batch.lastId;
    }
    if (batch.lastFetched > 0) {
      configs.lastFetched = batch.lastFetched;
    }

    for (const ref of batch.pushRead) {
      await FeverService.markRead(configs, ref);
    }
    for (const ref of batch.pushUnread) {
      await FeverService.markUnread(configs, ref);
    }
    for (const ref of batch.pushStar) {
      await FeverService.star(configs, ref);
    }
    for (const ref of batch.pushUnstar) {
      await FeverService.unstar(configs, ref);
    }

    return inserted;
  }

  private static async fetchItemsGReader(configs: ServiceConfigs,
    result: SyncResult): Promise<number> {
    const db: DatabaseManager = DatabaseManager.getInstance();

    const sourceMap: Map<string, Feed> = await db.getServiceLinkedFeeds();
    const batch: GrItemBatch = await GReaderService.fetchItems(configs, sourceMap);

    if (batch.articles.length === 0) {
      return 0;
    }

    const inserted: number = await SyncManager.persistArticles(batch.articles, result);

    // Advance both cursors only after the rows are stored.
    if (batch.lastIdRef.length > 0) {
      configs.lastIdRef = batch.lastIdRef;
    }
    if (batch.lastFetched > 0) {
      configs.lastFetched = batch.lastFetched;
    }

    for (const ref of batch.pushRead) {
      await GReaderService.markRead(configs, ref);
    }
    for (const ref of batch.pushStar) {
      await GReaderService.star(configs, ref);
    }

    return inserted;
  }

  /* -------------------------------------------------- per-article writes */

  /**
   * Push a local read-state change to the service. No-op for local articles.
   */
  static async pushRead(articleServiceRef: string, read: boolean): Promise<void> {
    if (articleServiceRef.length === 0) {
      return;
    }
    const configs: ServiceConfigs = await SyncManager.loadConfigs();

    if (configs.type === SyncService.Miniflux) {
      if (read) {
        await MinifluxService.markRead(configs, articleServiceRef);
      } else {
        await MinifluxService.markUnread(configs, articleServiceRef);
      }
      return;
    }

    if (configs.type === SyncService.GReader || configs.type === SyncService.Inoreader) {
      if (read) {
        await GReaderService.markRead(configs, articleServiceRef);
      } else {
        await GReaderService.markUnread(configs, articleServiceRef);
      }
      return;
    }

    if (configs.type === SyncService.Feedbin || configs.type === SyncService.Nextcloud) {
      if (read) {
        await FeedbinService.markRead(configs, articleServiceRef);
      } else {
        await FeedbinService.markUnread(configs, articleServiceRef);
      }
      return;
    }

    if (configs.type === SyncService.Fever) {
      if (read) {
        await FeverService.markRead(configs, articleServiceRef);
      } else {
        await FeverService.markUnread(configs, articleServiceRef);
      }
    }
  }

  /**
   * Push a batch of read-state changes.
   *
   * The per-article `pushRead` reloads the configuration on every call; the
   * "mark above/below as read" actions can touch hundreds of rows, so the
   * configuration is loaded once and each service's bulk endpoint is used.
   */
  static async pushReadMany(articleServiceRefs: string[]): Promise<void> {
    if (articleServiceRefs.length === 0) {
      return;
    }
    const configs: ServiceConfigs = await SyncManager.loadConfigs();

    if (configs.type === SyncService.Miniflux) {
      await MinifluxService.markEntriesRead(configs, articleServiceRefs);
      return;
    }
    if (configs.type === SyncService.GReader || configs.type === SyncService.Inoreader) {
      await GReaderService.markEntriesRead(configs, articleServiceRefs);
      return;
    }
    if (configs.type === SyncService.Feedbin || configs.type === SyncService.Nextcloud) {
      await FeedbinService.markEntriesRead(configs, articleServiceRefs);
      return;
    }
    if (configs.type === SyncService.Fever) {
      await FeverService.markEntriesRead(configs, articleServiceRefs);
    }
  }

  /**
   * Push a local star toggle to the service.
   *
   * Miniflux's bookmark endpoint toggles server-side, so both directions make
   * the same call; GReader needs an explicit add/remove tag.
   */
  static async pushStar(articleServiceRef: string, starred: boolean): Promise<void> {
    if (articleServiceRef.length === 0) {
      return;
    }
    const configs: ServiceConfigs = await SyncManager.loadConfigs();

    if (configs.type === SyncService.Miniflux) {
      await MinifluxService.toggleBookmark(configs, articleServiceRef);
      return;
    }

    if (configs.type === SyncService.GReader || configs.type === SyncService.Inoreader) {
      if (starred) {
        await GReaderService.star(configs, articleServiceRef);
      } else {
        await GReaderService.unstar(configs, articleServiceRef);
      }
      return;
    }

    if (configs.type === SyncService.Feedbin || configs.type === SyncService.Nextcloud) {
      if (starred) {
        await FeedbinService.star(configs, articleServiceRef);
      } else {
        await FeedbinService.unstar(configs, articleServiceRef);
      }
      return;
    }

    if (configs.type === SyncService.Fever) {
      if (starred) {
        await FeverService.star(configs, articleServiceRef);
      } else {
        await FeverService.unstar(configs, articleServiceRef);
      }
    }
  }

  /**
   * Mark all read, either server-side per feed (no date bound) or by pushing
   * the exact refs the local filter selected — mirroring the original's two
   * branches for each service.
   */
  static async pushMarkAllRead(feedIds: number[], date: number,
    before: boolean): Promise<void> {
    const configs: ServiceConfigs = await SyncManager.loadConfigs();
    const db: DatabaseManager = DatabaseManager.getInstance();

    if (configs.type === SyncService.Miniflux) {
      if (date > 0) {
        const refs: string[] = await db.getUnreadServiceRefs(feedIds, date, before);
        if (refs.length > 0) {
          await MinifluxService.markEntriesRead(configs, refs);
        }
        return;
      }
      for (const feedId of feedIds) {
        const feed: Feed | null = await db.getFeedById(feedId);
        if (feed !== null && feed.serviceRef.length > 0) {
          await MinifluxService.markFeedAllRead(configs, feed.serviceRef);
        }
      }
      return;
    }

    if (configs.type === SyncService.GReader || configs.type === SyncService.Inoreader) {
      if (date > 0) {
        const refs: string[] = await db.getUnreadServiceRefs(feedIds, date, before);
        if (refs.length > 0) {
          await GReaderService.markEntriesRead(configs, refs);
        }
        return;
      }
      for (const feedId of feedIds) {
        const feed: Feed | null = await db.getFeedById(feedId);
        if (feed !== null && feed.serviceRef.length > 0) {
          await GReaderService.markStreamAllRead(configs, feed.serviceRef);
        }
      }
      return;
    }

    if (configs.type === SyncService.Feedbin || configs.type === SyncService.Nextcloud) {
      if (date > 0) {
        const refs: string[] = await db.getUnreadServiceRefs(feedIds, date, before);
        if (refs.length > 0) {
          await FeedbinService.markEntriesRead(configs, refs);
        }
        return;
      }
      if (configs.type === SyncService.Nextcloud) {
        for (const feedId of feedIds) {
          const feed: Feed | null = await db.getFeedById(feedId);
          if (feed !== null && feed.serviceRef.length > 0) {
            await FeedbinService.markFeedAllRead(configs, feed.serviceRef);
          }
        }
        return;
      }
      // Feedbin has no per-feed mark-all endpoint, so the exact unread refs are
      // pushed as one bulk write instead.
      const all: string[] = await db.getUnreadServiceRefs(feedIds, 0, true);
      if (all.length > 0) {
        await FeedbinService.markEntriesRead(configs, all);
      }
      return;
    }

    if (configs.type === SyncService.Fever) {
      if (date > 0) {
        const refs: string[] = await db.getUnreadServiceRefs(feedIds, date, before);
        if (refs.length > 0) {
          await FeverService.markEntriesRead(configs, refs);
        }
        return;
      }
      for (const feedId of feedIds) {
        const feed: Feed | null = await db.getFeedById(feedId);
        if (feed !== null && feed.serviceRef.length > 0) {
          await FeverService.markFeedAllRead(configs, feed.serviceRef);
        }
      }
    }
  }

  /**
   * Disconnect the service, keeping downloaded articles locally.
   */
  static async removeService(): Promise<void> {
    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.unlinkAllServiceFeeds();
    const cleared: ServiceConfigs = new ServiceConfigs();
    await SyncManager.saveConfigs(cleared);
  }
}
