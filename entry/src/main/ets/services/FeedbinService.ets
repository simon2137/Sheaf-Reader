import { Feed, Article, ServiceConfigs, SyncService } from '../model/Models';
import { HttpClient, HttpResult } from '../data/HttpClient';
import { FeedParser } from '../utils/FeedParser';
import { RuleEngine } from './RuleEngine';
import { SourceMapping, ItemBatch, RemoteState } from './MinifluxService';

/* ------------------------------------------------ Feedbin response shapes */

export interface FbSubscription {
  id: number;
  feed_id: number;
  title: string;
  feed_url: string;
  site_url: string;
}

/** Feedbin files a feed under a folder through a "tagging" record. */
export interface FbTagging {
  id: number;
  feed_id: number;
  name: string;
}

export interface FbEntry {
  id: number;
  feed_id: number;
  title: string;
  url: string;
  author: string;
  content: string;
  summary: string;
  published: string;
  created_at: string;
}

/* --------------------------------------------- Nextcloud response shapes */

export interface NcFeed {
  id: number;
  url: string;
  title: string;
  folderId: number;
}

export interface NcFolder {
  id: number;
  name: string;
}

export interface NcFeedsBody {
  feeds: NcFeed[];
  starredCount: number;
  newestItemId: number;
}

export interface NcFoldersBody {
  folders: NcFolder[];
}

export interface NcItem {
  id: number;
  guid: string;
  url: string;
  title: string;
  author: string;
  pubDate: number;
  body: string;
  feedId: number;
  unread: boolean;
  starred: boolean;
}

export interface NcItemsBody {
  items: NcItem[];
}

/* ---------------------------------------------------------------- service */

/**
 * Feedbin and Nextcloud News sync clients.
 *
 * Both are JSON REST APIs authenticated with HTTP Basic, so they share one
 * implementation the way `GReaderService` serves Google Reader and Inoreader.
 * The per-service differences are the URL base, the subscription shape and the
 * cursor: Feedbin pages by `since=<ISO time>`, Nextcloud by numeric item id.
 */
export class FeedbinService {
  /** Entries per page while walking new items. */
  static readonly PAGE_SIZE: number = 100;
  /** Rows pulled when enumerating read/star state. */
  static readonly STATE_PAGE: number = 1000;
  /** Stop after this many pages even if the service keeps returning full ones. */
  private static readonly MAX_PAGES: number = 50;

  private static isFeedbin(configs: ServiceConfigs): boolean {
    return configs.type === SyncService.Feedbin;
  }

  private static async request(configs: ServiceConfigs, endpoint: string,
    verb: string, body: string): Promise<HttpResult> {
    const base: string = FeedbinService.isFeedbin(configs)
      ? HttpClient.feedbinBase(configs.endpoint)
      : HttpClient.nextcloudBase(configs.endpoint);

    if (base.length === 0) {
      const missing: HttpResult = new HttpResult();
      missing.error = 'Service endpoint is not configured';
      return missing;
    }

    const headers: Record<string, string> = {};
    if (body.length > 0) {
      headers['Content-Type'] = 'application/json';
    }
    if (configs.authKey.length > 0) {
      headers['Authorization'] = 'Basic ' + configs.authKey;
    }

    return HttpClient.send(verb, base.concat(endpoint), headers, body);
  }

  private static parse<T>(body: string): T | null {
    if (body.length === 0) {
      return null;
    }
    try {
      return JSON.parse(body) as T;
    } catch (err) {
      console.error('FeedbinService: malformed JSON response');
      return null;
    }
  }

  /** ISO-8601 timestamp for a Feedbin `since` cursor. */
  private static isoSince(seconds: number): string {
    return new Date(seconds * 1000).toISOString();
  }

  /**
   * Verify credentials. Feedbin exposes `/authentication.json`; Nextcloud's
   * `/version` is the documented probe and also confirms the News app exists.
   */
  static async authenticate(configs: ServiceConfigs): Promise<boolean> {
    const endpoint: string = FeedbinService.isFeedbin(configs)
      ? 'authentication.json' : 'version';
    const response: HttpResult = await FeedbinService.request(
      configs, endpoint, HttpClient.GET, '');
    return response.ok();
  }

  /* --------------------------------------------------------------- sources */

  static async updateSources(configs: ServiceConfigs): Promise<SourceMapping | null> {
    return FeedbinService.isFeedbin(configs)
      ? FeedbinService.feedbinSources(configs)
      : FeedbinService.nextcloudSources(configs);
  }

  private static async feedbinSources(configs: ServiceConfigs): Promise<SourceMapping | null> {
    const mapping: SourceMapping = new SourceMapping();

    const response: HttpResult = await FeedbinService.request(
      configs, 'subscriptions.json', HttpClient.GET, '');
    if (!response.ok()) {
      return null;
    }
    const subscriptions: FbSubscription[] | null =
      FeedbinService.parse<FbSubscription[]>(response.body);
    if (subscriptions === null) {
      return null;
    }

    // Feedbin folders are taggings, not a field on the subscription.
    const folders: Map<number, string> = new Map<number, string>();
    if (configs.importGroups) {
      const taggingResponse: HttpResult = await FeedbinService.request(
        configs, 'taggings.json', HttpClient.GET, '');
      if (taggingResponse.ok()) {
        const taggings: FbTagging[] | null =
          FeedbinService.parse<FbTagging[]>(taggingResponse.body);
        if (taggings !== null) {
          const seen: Set<string> = new Set<string>();
          for (const tagging of taggings) {
            folders.set(tagging.feed_id, tagging.name);
            if (!seen.has(tagging.name)) {
              seen.add(tagging.name);
              mapping.categories.push(tagging.name);
            }
          }
        }
      }
    }

    for (const subscription of subscriptions) {
      const feed: Feed = new Feed(subscription.feed_url, subscription.title);
      feed.link = subscription.site_url;
      feed.serviceRef = subscription.feed_id.toString();
      mapping.sources.push(feed);

      const folder: string | undefined = folders.get(subscription.feed_id);
      if (folder !== undefined) {
        mapping.groupsMap.set(feed.serviceRef, folder);
      }
    }

    return mapping;
  }

  private static async nextcloudSources(configs: ServiceConfigs): Promise<SourceMapping | null> {
    const mapping: SourceMapping = new SourceMapping();

    const folderNames: Map<number, string> = new Map<number, string>();
    if (configs.importGroups) {
      const folderResponse: HttpResult = await FeedbinService.request(
        configs, 'folders', HttpClient.GET, '');
      if (folderResponse.ok()) {
        const folders: NcFoldersBody | null =
          FeedbinService.parse<NcFoldersBody>(folderResponse.body);
        if (folders !== null && folders.folders !== undefined && folders.folders !== null) {
          for (const folder of folders.folders) {
            folderNames.set(folder.id, folder.name);
            mapping.categories.push(folder.name);
          }
        }
      }
    }

    const response: HttpResult = await FeedbinService.request(
      configs, 'feeds', HttpClient.GET, '');
    if (!response.ok()) {
      return null;
    }
    const body: NcFeedsBody | null = FeedbinService.parse<NcFeedsBody>(response.body);
    if (body === null || body.feeds === undefined || body.feeds === null) {
      return null;
    }

    for (const remote of body.feeds) {
      const feed: Feed = new Feed(remote.url, remote.title);
      feed.serviceRef = remote.id.toString();
      mapping.sources.push(feed);

      const folder: string | undefined = folderNames.get(remote.folderId);
      if (folder !== undefined) {
        mapping.groupsMap.set(feed.serviceRef, folder);
      }
    }

    return mapping;
  }

  /* ------------------------------------------------------------ item batch */

  static async fetchItems(configs: ServiceConfigs,
    sourceMap: Map<string, Feed>): Promise<ItemBatch> {
    return FeedbinService.isFeedbin(configs)
      ? FeedbinService.feedbinItems(configs, sourceMap)
      : FeedbinService.nextcloudItems(configs, sourceMap);
  }

  private static async feedbinItems(configs: ServiceConfigs,
    sourceMap: Map<string, Feed>): Promise<ItemBatch> {
    const batch: ItemBatch = new ItemBatch();
    const collected: FbEntry[] = [];

    const since: string = configs.lastFetched > 0
      ? '&since=' + encodeURIComponent(FeedbinService.isoSince(configs.lastFetched)) : '';

    for (let page = 1; page <= FeedbinService.MAX_PAGES; page++) {
      const endpoint: string = 'entries.json?per_page=' + FeedbinService.PAGE_SIZE
        + '&page=' + page + since;
      const response: HttpResult = await FeedbinService.request(
        configs, endpoint, HttpClient.GET, '');
      if (!response.ok()) {
        break;
      }
      const entries: FbEntry[] | null = FeedbinService.parse<FbEntry[]>(response.body);
      if (entries === null || entries.length === 0) {
        break;
      }
      for (const entry of entries) {
        collected.push(entry);
      }
      if (entries.length < FeedbinService.PAGE_SIZE
        || collected.length >= configs.fetchLimit) {
        break;
      }
    }

    if (collected.length === 0) {
      batch.lastFetched = configs.lastFetched;
      return batch;
    }

    // Feedbin's cursor is exclusive on created_at, so advance it to the newest
    // entry seen rather than to the head of the page.
    let newest: number = configs.lastFetched;
    for (const entry of collected) {
      const created: number = Math.floor(Date.parse(entry.created_at) / 1000);
      if (!isNaN(created) && created > newest) {
        newest = created;
      }
    }
    batch.lastFetched = newest;

    for (const entry of collected) {
      const source: Feed | undefined = sourceMap.get(entry.feed_id.toString());
      if (source === undefined) {
        continue;
      }

      const article: Article = new Article();
      article.feedId = source.id;
      article.title = entry.title;
      article.link = entry.url;
      const parsedDate: number = Date.parse(entry.published);
      article.published = isNaN(parsedDate) ? Date.now() : parsedDate;
      article.fetched = Date.now();
      article.content = entry.content;
      article.snippet = FeedParser.htmlDecode(entry.content);
      article.author = entry.author;
      article.read = false;
      article.starred = false;
      article.hidden = false;
      article.notify = false;
      article.serviceRef = entry.id.toString();
      article.guid = 'feedbin-'.concat(entry.id.toString());
      article.imageUrl = FeedParser.firstImageSrc(entry.content, article.link);

      FeedbinService.applyRules(source, article, batch);
      batch.articles.push(article);
    }

    return batch;
  }

  private static async nextcloudItems(configs: ServiceConfigs,
    sourceMap: Map<string, Feed>): Promise<ItemBatch> {
    const batch: ItemBatch = new ItemBatch();
    const collected: NcItem[] = [];
    const startId: number = configs.lastId;

    for (let page = 0; page < FeedbinService.MAX_PAGES; page++) {
      const offset: number = page * FeedbinService.PAGE_SIZE;
      const endpoint: string = 'items?batchSize=' + FeedbinService.PAGE_SIZE
        + '&offset=' + offset
        + '&type=3&getRead=true&oldestFirst=false';
      const response: HttpResult = await FeedbinService.request(
        configs, endpoint, HttpClient.GET, '');
      if (!response.ok()) {
        break;
      }
      const body: NcItemsBody | null = FeedbinService.parse<NcItemsBody>(response.body);
      if (body === null || body.items === undefined || body.items === null
        || body.items.length === 0) {
        break;
      }

      // Items arrive newest-first, so the first row at or below the cursor ends
      // the walk: everything after it is older still.
      let sawOld: boolean = false;
      for (const item of body.items) {
        if (item.id <= startId) {
          sawOld = true;
          break;
        }
        collected.push(item);
        if (collected.length >= configs.fetchLimit) {
          sawOld = true;
          break;
        }
      }
      if (sawOld || body.items.length < FeedbinService.PAGE_SIZE) {
        break;
      }
    }

    if (collected.length === 0) {
      batch.lastId = startId;
      return batch;
    }

    let newest: number = startId;
    for (const item of collected) {
      if (item.id > newest) {
        newest = item.id;
      }
    }
    batch.lastId = newest;

    for (const item of collected) {
      const source: Feed | undefined = sourceMap.get(item.feedId.toString());
      if (source === undefined) {
        continue;
      }

      const article: Article = new Article();
      article.feedId = source.id;
      article.title = item.title;
      article.link = item.url;
      article.published = item.pubDate > 0 ? item.pubDate * 1000 : Date.now();
      article.fetched = Date.now();
      article.content = item.body;
      article.snippet = FeedParser.htmlDecode(item.body);
      article.author = item.author;
      article.read = item.unread === false;
      article.starred = item.starred === true;
      article.hidden = false;
      article.notify = false;
      article.serviceRef = item.id.toString();
      article.guid = 'nextcloud-'.concat(item.id.toString());
      article.imageUrl = FeedParser.firstImageSrc(item.body, article.link);

      FeedbinService.applyRules(source, article, batch);
      batch.articles.push(article);
    }

    return batch;
  }

  /**
   * Run the source's rules and record any state they changed so the caller can
   * push it back, matching the Miniflux port's behaviour.
   */
  private static applyRules(source: Feed, article: Article, batch: ItemBatch): void {
    if (source.rulesJson.length === 0) {
      return;
    }
    const before: boolean = article.read;
    const beforeStar: boolean = article.starred;
    RuleEngine.applyForFeed(source.rulesJson, article);

    if (before !== article.read && article.serviceRef.length > 0) {
      if (article.read) {
        batch.pushRead.push(article.serviceRef);
      } else {
        batch.pushUnread.push(article.serviceRef);
      }
    }
    if (beforeStar !== article.starred && article.serviceRef.length > 0) {
      if (article.starred) {
        batch.pushStar.push(article.serviceRef);
      } else {
        batch.pushUnstar.push(article.serviceRef);
      }
    }
  }

  /* ------------------------------------------------------------ remote state */

  static async syncItems(configs: ServiceConfigs): Promise<RemoteState | null> {
    return FeedbinService.isFeedbin(configs)
      ? FeedbinService.feedbinState(configs)
      : FeedbinService.nextcloudState(configs);
  }

  private static async feedbinState(configs: ServiceConfigs): Promise<RemoteState | null> {
    const state: RemoteState = new RemoteState();

    const unreadResponse: HttpResult = await FeedbinService.request(
      configs, 'unread_entries.json', HttpClient.GET, '');
    const starredResponse: HttpResult = await FeedbinService.request(
      configs, 'starred_entries.json', HttpClient.GET, '');
    if (!unreadResponse.ok() || !starredResponse.ok()) {
      return null;
    }

    const unread: number[] | null = FeedbinService.parse<number[]>(unreadResponse.body);
    const starred: number[] | null = FeedbinService.parse<number[]>(starredResponse.body);
    if (unread === null || starred === null) {
      return null;
    }

    // Feedbin caps these lists, so a full page means the set is incomplete and
    // reconciling against it would wrongly mark the overflow read.
    if (unread.length >= FeedbinService.STATE_PAGE
      || starred.length >= FeedbinService.STATE_PAGE) {
      console.error('FeedbinService: read/star state truncated; skipping reconciliation');
      return null;
    }

    for (const id of unread) {
      state.unread.add(id.toString());
    }
    for (const id of starred) {
      state.starred.add(id.toString());
    }
    return state;
  }

  private static async nextcloudState(configs: ServiceConfigs): Promise<RemoteState | null> {
    const state: RemoteState = new RemoteState();

    // type=3 is "all items" with getRead=false -> exactly the unread set;
    // type=2 is "starred". Both are bounded, unlike walking every item.
    const unread: Set<string> | null =
      await FeedbinService.nextcloudItemIds(configs, 'type=3&getRead=false');
    const starred: Set<string> | null =
      await FeedbinService.nextcloudItemIds(configs, 'type=2&getRead=true');
    if (unread === null || starred === null) {
      return null;
    }

    state.unread = unread;
    state.starred = starred;
    return state;
  }

  private static async nextcloudItemIds(configs: ServiceConfigs,
    selector: string): Promise<Set<string> | null> {
    const ids: Set<string> = new Set<string>();

    for (let page = 0; page < FeedbinService.MAX_PAGES; page++) {
      const offset: number = page * FeedbinService.STATE_PAGE;
      const endpoint: string = 'items?batchSize=' + FeedbinService.STATE_PAGE
        + '&offset=' + offset + '&' + selector;
      const response: HttpResult = await FeedbinService.request(
        configs, endpoint, HttpClient.GET, '');
      if (!response.ok()) {
        return null;
      }
      const body: NcItemsBody | null = FeedbinService.parse<NcItemsBody>(response.body);
      if (body === null || body.items === undefined || body.items === null) {
        return null;
      }
      for (const item of body.items) {
        ids.add(item.id.toString());
      }
      if (body.items.length < FeedbinService.STATE_PAGE) {
        return ids;
      }
    }

    console.error('FeedbinService: item enumeration hit the page cap');
    return null;
  }

  /* ------------------------------------------------------------- writes */

  /**
   * Feedbin's bulk write endpoints take exactly one array. The body is built by
   * hand so the other array is absent rather than empty — Feedbin validates the
   * payload strictly and an empty `unread_entries` alongside a starred write is
   * rejected.
   */
  private static async write(configs: ServiceConfigs, endpoint: string,
    ids: string[]): Promise<boolean> {
    const numeric: number[] = [];
    for (const id of ids) {
      const parsed: number = Number.parseInt(id, 10);
      if (!isNaN(parsed)) {
        numeric.push(parsed);
      }
    }
    if (numeric.length === 0) {
      return true;
    }

    const key: string = endpoint.indexOf('starred') >= 0
      ? 'starred_entries' : 'unread_entries';
    const body: string = '{"' + key + '":[' + numeric.join(',') + ']}';

    const response: HttpResult = await FeedbinService.request(
      configs, endpoint, HttpClient.POST, body);
    return response.ok();
  }

  static async markRead(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    return FeedbinService.markEntriesRead(configs, [serviceRef]);
  }

  static async markUnread(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    if (FeedbinService.isFeedbin(configs)) {
      // Adding to the unread list is what marks an entry unread.
      return FeedbinService.write(configs, 'unread_entries.json', [serviceRef]);
    }
    return FeedbinService.nextcloudItemAction(configs, serviceRef, 'unread');
  }

  static async markEntriesRead(configs: ServiceConfigs,
    serviceRefs: string[]): Promise<boolean> {
    if (FeedbinService.isFeedbin(configs)) {
      // Removing from the unread list is what marks an entry read.
      return FeedbinService.write(configs, 'unread_entries/delete.json', serviceRefs);
    }
    for (const ref of serviceRefs) {
      await FeedbinService.nextcloudItemAction(configs, ref, 'read');
    }
    return true;
  }

  static async star(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    if (FeedbinService.isFeedbin(configs)) {
      return FeedbinService.write(configs, 'starred_entries.json', [serviceRef]);
    }
    return FeedbinService.nextcloudItemAction(configs, serviceRef, 'star');
  }

  static async unstar(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    if (FeedbinService.isFeedbin(configs)) {
      return FeedbinService.write(configs, 'starred_entries/delete.json', [serviceRef]);
    }
    return FeedbinService.nextcloudItemAction(configs, serviceRef, 'unstar');
  }

  private static async nextcloudItemAction(configs: ServiceConfigs,
    serviceRef: string, action: string): Promise<boolean> {
    const response: HttpResult = await FeedbinService.request(
      configs, 'items/' + serviceRef + '/' + action, HttpClient.PUT, '');
    return response.ok();
  }

  /**
   * Mark an entire Nextcloud feed read. Feedbin has no per-feed endpoint, so
   * its caller passes the entry ids it selected instead.
   */
  static async markFeedAllRead(configs: ServiceConfigs,
    feedServiceRef: string): Promise<boolean> {
    if (FeedbinService.isFeedbin(configs)) {
      return false;
    }
    const response: HttpResult = await FeedbinService.request(
      configs, 'feeds/' + feedServiceRef + '/read', HttpClient.PUT, '');
    return response.ok();
  }
}
