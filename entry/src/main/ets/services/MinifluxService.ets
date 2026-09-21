import { Feed, Article, ServiceConfigs } from '../model/Models';
import { HttpClient, HttpResult } from '../data/HttpClient';
import { FeedParser } from '../utils/FeedParser';
import { RuleEngine } from './RuleEngine';

/* ------------------------------------------------------------------ *
 * Miniflux API v1 schema (partial, matching the original's interfaces)
 * ------------------------------------------------------------------ */

export interface MfCategory {
  id: number;
  title: string;
}

export interface MfFeed {
  id: number;
  feed_url: string;
  title: string;
  category: MfCategory;
}

export interface MfEntry {
  id: number;
  /** "unread" | "read" | "removed" */
  status: string;
  title: string;
  url: string;
  published_at: string;
  created_at: string;
  content: string;
  author: string;
  starred: boolean;
  feed: MfFeed;
}

export interface MfEntries {
  total: number;
  entries: MfEntry[];
}

export interface MfError {
  error_message: string;
}

/** Request body for `PUT /v1/entries`. */
class EntryStatusBody {
  entry_ids: number[] = [];
  status: string = '';

  constructor(entryIds: number[], status: string) {
    this.entry_ids = entryIds;
    this.status = status;
  }
}

/* ------------------------------------------------------------ results */

/** Feeds discovered on the service, plus their category mapping. */
export class SourceMapping {
  sources: Feed[] = [];
  /** serviceRef -> category title. Only populated when importGroups was set. */
  groupsMap: Map<string, string> = new Map<string, string>();
  /** Category titles in service order, when importGroups was set. */
  categories: string[] = [];
}

/** A page-walk of new entries. */
export class ItemBatch {
  articles: Article[] = [];
  /** New incremental cursor; 0 when nothing was fetched. */
  lastId: number = 0;
  /** Second cursor for services whose position is a timestamp (Feedbin). */
  lastFetched: number = 0;
  /** Entries whose read state a local rule changed; push these back. */
  pushRead: string[] = [];
  pushUnread: string[] = [];
  /** Entries whose star state a local rule changed; push these back. */
  pushStar: string[] = [];
  pushUnstar: string[] = [];
}

/** Remote read/star state, used to reconcile local rows. */
export class RemoteState {
  unread: Set<string> = new Set<string>();
  starred: Set<string> = new Set<string>();
}

/* ------------------------------------------------------------ service */

/**
 * Miniflux sync client, ported from `scripts/models/services/miniflux.ts`.
 *
 * The original exposes these as redux thunks; here they are plain async
 * methods returning data, and `SyncManager` performs the store writes. The API
 * surface, query parameters and pagination logic are preserved verbatim.
 */
export class MinifluxService {
  /** Page size for the incremental entry walk. */
  static readonly ENTRY_QUANTITY: number = 125;
  /** Page size used when reconciling read/star state. */
  static readonly SYNC_PAGE: number = 1000;

  /**
   * Build the `/v1/` base URL and issue the request with the configured auth
   * header, mirroring the original `fetchAPI`.
   */
  private static async fetchApi(configs: ServiceConfigs, endpoint: string,
    method: string, body: string): Promise<HttpResult> {
    const base: string = HttpClient.minifluxBase(configs.endpoint);
    if (base.length === 0) {
      const missing: HttpResult = new HttpResult();
      missing.error = 'Miniflux endpoint is not configured';
      return missing;
    }

    const headers: Record<string, string> = {};
    if (body.length > 0) {
      headers['Content-Type'] = 'application/json';
    }
    if (configs.apiKeyAuth) {
      headers['X-Auth-Token'] = configs.authKey;
    } else {
      headers['Authorization'] = 'Basic ' + configs.authKey;
    }

    return HttpClient.send(method, base.concat(endpoint), headers, body);
  }

  private static parse<T>(body: string): T | null {
    if (body.length === 0) {
      return null;
    }
    try {
      return JSON.parse(body) as T;
    } catch (err) {
      console.error('MinifluxService: malformed JSON response');
      return null;
    }
  }

  /**
   * Verify the credentials by polling `/v1/me`, as the original does.
   */
  static async authenticate(configs: ServiceConfigs): Promise<boolean> {
    const response: HttpResult = await MinifluxService.fetchApi(
      configs, 'me', HttpClient.GET, '');
    if (!response.ok()) {
      return false;
    }
    const error: MfError | null = MinifluxService.parse<MfError>(response.body);
    if (error !== null && error.error_message !== undefined
      && error.error_message !== null && error.error_message.length > 0) {
      return false;
    }
    return true;
  }

  /**
   * Collect feeds, and optionally categories, from the service.
   */
  static async updateSources(configs: ServiceConfigs): Promise<SourceMapping | null> {
    const mapping: SourceMapping = new SourceMapping();

    if (configs.importGroups) {
      const categoryResponse: HttpResult = await MinifluxService.fetchApi(
        configs, 'categories', HttpClient.GET, '');
      if (categoryResponse.ok()) {
        const categories: MfCategory[] | null =
          MinifluxService.parse<MfCategory[]>(categoryResponse.body);
        if (categories !== null) {
          for (const category of categories) {
            mapping.categories.push(category.title);
          }
        }
      }
    }

    const feedResponse: HttpResult = await MinifluxService.fetchApi(
      configs, 'feeds', HttpClient.GET, '');
    if (!feedResponse.ok()) {
      return null;
    }

    const feeds: MfFeed[] | null = MinifluxService.parse<MfFeed[]>(feedResponse.body);
    if (feeds === null) {
      return null;
    }

    for (const feed of feeds) {
      const source: Feed = new Feed(feed.feed_url, feed.title);
      // Associate the service-assigned id so later requests can match it.
      source.serviceRef = feed.id.toString();
      mapping.sources.push(source);
      if (feed.category !== undefined && feed.category !== null) {
        mapping.groupsMap.set(feed.id.toString(), feed.category.title);
      }
    }

    return mapping;
  }

  /**
   * Walk entries newer than `configs.lastId`, newest first.
   *
   * NOTE (from the original): `/entries` orders by `published_at` by default,
   * and offers no `created_at` sort, but `id` correlates with creation. Some
   * feeds publish `published_at` values that are out of order, so `id` is used.
   */
  static async fetchItems(configs: ServiceConfigs, sourceMap: Map<string, Feed>): Promise<ItemBatch> {
    const batch: ItemBatch = new ItemBatch();
    const entries: MfEntry[] = [];
    const startId: number = configs.lastId;
    let continueId: number = 0;
    let pageLength: number = 0;

    do {
      let endpoint: string;
      if (continueId > 0) {
        endpoint = 'entries?order=id&direction=desc&after_entry_id=' + startId
          + '&before_entry_id=' + continueId
          + '&limit=' + MinifluxService.ENTRY_QUANTITY;
      } else {
        endpoint = 'entries?order=id&direction=desc&after_entry_id=' + startId
          + '&limit=' + MinifluxService.ENTRY_QUANTITY;
      }

      const response: HttpResult = await MinifluxService.fetchApi(
        configs, endpoint, HttpClient.GET, '');
      if (!response.ok()) {
        break;
      }

      const page: MfEntries | null = MinifluxService.parse<MfEntries>(response.body);
      if (page === null || page.entries === undefined || page.entries === null) {
        break;
      }

      pageLength = page.entries.length;
      for (const entry of page.entries) {
        entries.push(entry);
      }
      if (entries.length > 0) {
        continueId = entries[entries.length - 1].id;
      }
    } while (pageLength >= MinifluxService.ENTRY_QUANTITY
      && entries.length < configs.fetchLimit);

    if (entries.length === 0) {
      batch.lastId = startId;
      return batch;
    }

    // Newest first, so the head carries the new cursor.
    batch.lastId = entries[0].id;

    for (const entry of entries) {
      const source: Feed | undefined = sourceMap.get(entry.feed.id.toString());
      if (source === undefined) {
        // The feed is not subscribed locally; skip rather than orphan the row.
        continue;
      }

      const article: Article = new Article();
      article.feedId = source.id;
      article.title = entry.title;
      article.link = entry.url;

      const dateSource: string = (entry.published_at !== undefined && entry.published_at !== null
        && entry.published_at.length > 0) ? entry.published_at : entry.created_at;
      const parsedDate: number = Date.parse(dateSource);
      article.published = isNaN(parsedDate) ? Date.now() : parsedDate;
      article.fetched = Date.now();

      article.content = entry.content;
      article.snippet = FeedParser.htmlDecode(entry.content);
      article.author = entry.author;
      article.read = entry.status === 'read';
      article.starred = entry.starred === true;
      article.hidden = false;
      article.notify = false;
      article.serviceRef = entry.id.toString();
      // Local de-duplication key, namespaced so it cannot collide with the
      // guid of a locally-fetched article from the same feed.
      article.guid = 'miniflux-'.concat(entry.id.toString());
      article.imageUrl = FeedParser.firstImageSrc(entry.content, article.link);

      if (source.rulesJson.length > 0) {
        const before: boolean = article.read;
        const beforeStar: boolean = article.starred;
        RuleEngine.applyForFeed(source.rulesJson, article);

        // Push rule-driven state changes back to the service.
        //
        // NOTE: upstream calls `minifluxServiceHooks.markRead(item)` here but
        // never dispatches the returned thunk, so the push is a no-op there.
        // This port performs the intended request instead.
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

      batch.articles.push(article);
    }

    return batch;
  }

  /**
   * Enumerate remote entry ids that are unread and starred.
   *
   * Returns null when a page could not be retrieved. Reconciling against a
   * truncated set would be read as "the service no longer lists these", which
   * would mark the missing articles read locally.
   */
  static async syncItems(configs: ServiceConfigs): Promise<RemoteState | null> {
    const state: RemoteState = new RemoteState();

    const unread: Set<string> | null =
      await MinifluxService.fetchEntryIds(configs, 'status=unread');
    const starred: Set<string> | null =
      await MinifluxService.fetchEntryIds(configs, 'starred=true');

    if (unread === null || starred === null) {
      return null;
    }

    state.unread = unread;
    state.starred = starred;
    return state;
  }

  private static async fetchEntryIds(configs: ServiceConfigs,
    params: string): Promise<Set<string> | null> {
    const ids: Set<string> = new Set<string>();
    let offset: number = 0;
    let pageLength: number = 0;

    do {
      const endpoint: string = 'entries?'.concat(params)
        .concat('&limit=').concat(MinifluxService.SYNC_PAGE.toString())
        .concat('&offset=').concat(offset.toString());

      const response: HttpResult = await MinifluxService.fetchApi(
        configs, endpoint, HttpClient.GET, '');
      if (!response.ok()) {
        console.error('MinifluxService.fetchEntryIds: request failed, aborting');
        return null;
      }

      const page: MfEntries | null = MinifluxService.parse<MfEntries>(response.body);
      if (page === null || page.entries === undefined || page.entries === null) {
        return null;
      }

      pageLength = page.entries.length;
      for (const entry of page.entries) {
        ids.add(entry.id.toString());
      }
      offset += MinifluxService.SYNC_PAGE;
    } while (pageLength >= MinifluxService.SYNC_PAGE);

    return ids;
  }

  /* ------------------------------------------------------ state writes */

  /**
   * `PUT /v1/entries` with a status. The service answers 204 on success.
   */
  private static async updateEntriesStatus(configs: ServiceConfigs, entryIds: number[],
    status: string): Promise<boolean> {
    if (entryIds.length === 0) {
      return true;
    }
    const body: string = JSON.stringify(new EntryStatusBody(entryIds, status));
    const response: HttpResult = await MinifluxService.fetchApi(
      configs, 'entries', HttpClient.PUT, body);
    // Upstream asserts 204 for markRead; accept any 2xx for robustness.
    return response.ok();
  }

  static async markRead(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    if (serviceRef.length === 0) {
      return true;
    }
    return MinifluxService.updateEntriesStatus(configs, [Number(serviceRef)], 'read');
  }

  static async markUnread(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    if (serviceRef.length === 0) {
      return true;
    }
    return MinifluxService.updateEntriesStatus(configs, [Number(serviceRef)], 'unread');
  }

  static async markEntriesRead(configs: ServiceConfigs, serviceRefs: string[]): Promise<boolean> {
    const ids: number[] = [];
    for (const ref of serviceRefs) {
      ids.push(Number(ref));
    }
    return MinifluxService.updateEntriesStatus(configs, ids, 'read');
  }

  /**
   * Server-side "mark all as read" for a whole feed.
   */
  static async markFeedAllRead(configs: ServiceConfigs, feedServiceRef: string): Promise<boolean> {
    if (feedServiceRef.length === 0) {
      return false;
    }
    const response: HttpResult = await MinifluxService.fetchApi(
      configs, 'feeds/'.concat(feedServiceRef).concat('/mark-all-as-read'),
      HttpClient.PUT, '');
    return response.ok();
  }

  /**
   * `PUT /v1/entries/{id}/bookmark` — a toggle on the service side.
   */
  static async toggleBookmark(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    if (serviceRef.length === 0) {
      return false;
    }
    const response: HttpResult = await MinifluxService.fetchApi(
      configs, 'entries/'.concat(serviceRef).concat('/bookmark'),
      HttpClient.PUT, '');
    return response.ok();
  }
}
