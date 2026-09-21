import { Feed, Article, ServiceConfigs } from '../model/Models';
import { HttpClient, HttpResult } from '../data/HttpClient';
import { FeedParser } from '../utils/FeedParser';
import { RuleEngine } from './RuleEngine';
import { SourceMapping, ItemBatch, RemoteState } from './MinifluxService';

/* -------------------------------------------------- Fever response shapes */

export interface FeverFeed {
  id: number;
  favicon_id: number;
  title: string;
  url: string;
  site_url: string;
  is_spark: number;
  last_updated_on_time: number;
}

export interface FeverGroup {
  id: number;
  title: string;
}

/** `feed_ids` is a comma-separated string, not an array, per the API spec. */
export interface FeverFeedsGroup {
  group_id: number;
  feed_ids: string;
}

export interface FeverItem {
  id: number;
  feed_id: number;
  title: string;
  author: string;
  html: string;
  url: string;
  is_saved: number;
  is_read: number;
  created_on_time: number;
}

/**
 * One Fever response. Every action adds its own members to a common envelope,
 * so all of them are optional.
 */
export interface FeverResponse {
  api_version?: number;
  auth?: number;
  last_refreshed_on_time?: string;
  feeds?: FeverFeed[];
  groups?: FeverGroup[];
  feeds_groups?: FeverFeedsGroup[];
  items?: FeverItem[];
  total_items?: number;
  unread_item_ids?: string;
  saved_item_ids?: string;
}

/* ---------------------------------------------------------------- service */

/**
 * Fever sync client, following the official Fever API (feedafever.com/api).
 *
 * Two properties of that API shape this port:
 *
 *   - The read actions go in the *query string* and `api_key` goes in the
 *     *POST body*; the spec is explicit that posting the read arguments makes
 *     them unrecognised.
 *   - `api_key` is `md5(email:password)`, so there is no token to cache and
 *     nothing to refresh.
 *
 * `items` is a forward walk: `since_id` returns the next 50 newer items, so the
 * cursor advances to the highest id on each page until a page comes back empty.
 */
export class FeverService {
  /** Fever returns at most this many items per request. */
  static readonly PAGE_SIZE: number = 50;
  /** Guard against a server that keeps returning non-advancing pages. */
  private static readonly MAX_PAGES: number = 40;

  /** Memoised `api_key`, keyed by the credentials it was derived from. */
  private static cachedFor: string = '';
  private static cachedKey: string = '';

  private static async apiKey(configs: ServiceConfigs): Promise<string> {
    const seed: string = configs.username.concat(':').concat(configs.password);
    if (FeverService.cachedKey.length > 0 && FeverService.cachedFor === seed) {
      return FeverService.cachedKey;
    }
    const key: string = await HttpClient.md5Hex(seed);
    FeverService.cachedFor = seed;
    FeverService.cachedKey = key;
    return key;
  }

  private static async send(configs: ServiceConfigs, query: string,
    body: string): Promise<HttpResult> {
    const base: string = HttpClient.feverBase(configs.endpoint);
    if (base.length === 0) {
      const missing: HttpResult = new HttpResult();
      missing.error = 'Fever endpoint is not configured';
      return missing;
    }
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded'
    };
    return HttpClient.send(HttpClient.POST, base.concat(query), headers, body);
  }

  /** A read action: arguments in the query string, `api_key` in the body. */
  private static async read(configs: ServiceConfigs, query: string): Promise<HttpResult> {
    const key: string = await FeverService.apiKey(configs);
    return FeverService.send(configs, query, 'api_key='.concat(key));
  }

  /** A write action: every argument, including `api_key`, in the body. */
  private static async write(configs: ServiceConfigs, form: string): Promise<HttpResult> {
    const key: string = await FeverService.apiKey(configs);
    return FeverService.send(configs, '',
      'api_key='.concat(key).concat('&').concat(form));
  }

  private static parse(body: string): FeverResponse | null {
    if (body.length === 0) {
      return null;
    }
    try {
      return JSON.parse(body) as FeverResponse;
    } catch (err) {
      console.error('FeverService: malformed JSON response');
      return null;
    }
  }

  private static authenticated(response: FeverResponse | null): boolean {
    return response !== null && response.auth === 1;
  }

  /**
   * Verify the credentials. The bare `?api` call is the documented probe: it
   * only reports the API version and whether the key was accepted.
   */
  static async authenticate(configs: ServiceConfigs): Promise<boolean> {
    const response: HttpResult = await FeverService.read(configs, '');
    if (!response.ok()) {
      return false;
    }
    return FeverService.authenticated(FeverService.parse(response.body));
  }

  /* --------------------------------------------------------------- sources */

  static async updateSources(configs: ServiceConfigs): Promise<SourceMapping | null> {
    const mapping: SourceMapping = new SourceMapping();

    const response: HttpResult = await FeverService.read(configs, '&feeds');
    if (!response.ok()) {
      return null;
    }
    const body: FeverResponse | null = FeverService.parse(response.body);
    if (!FeverService.authenticated(body) || body === null
      || body.feeds === undefined || body.feeds === null) {
      return null;
    }

    // Groups arrive as a separate list plus a feed-id membership string.
    const groupOf: Map<number, string> = new Map<number, string>();
    if (configs.importGroups) {
      const groupResponse: HttpResult = await FeverService.read(configs, '&groups');
      if (groupResponse.ok()) {
        const groups: FeverResponse | null = FeverService.parse(groupResponse.body);
        if (groups !== null && groups.groups !== undefined && groups.groups !== null
          && groups.feeds_groups !== undefined && groups.feeds_groups !== null) {
          const titles: Map<number, string> = new Map<number, string>();
          for (const group of groups.groups) {
            titles.set(group.id, group.title);
            mapping.categories.push(group.title);
          }
          for (const membership of groups.feeds_groups) {
            const title: string | undefined = titles.get(membership.group_id);
            if (title === undefined) {
              continue;
            }
            for (const raw of membership.feed_ids.split(',')) {
              const feedId: number = Number.parseInt(raw.trim(), 10);
              if (!isNaN(feedId)) {
                groupOf.set(feedId, title);
              }
            }
          }
        }
      }
    }

    for (const remote of body.feeds) {
      const feed: Feed = new Feed(remote.url, remote.title);
      feed.link = remote.site_url;
      feed.serviceRef = remote.id.toString();
      mapping.sources.push(feed);

      const group: string | undefined = groupOf.get(remote.id);
      if (group !== undefined) {
        mapping.groupsMap.set(feed.serviceRef, group);
      }
    }

    return mapping;
  }

  /* ------------------------------------------------------------ item batch */

  static async fetchItems(configs: ServiceConfigs,
    sourceMap: Map<string, Feed>): Promise<ItemBatch> {
    const batch: ItemBatch = new ItemBatch();
    const collected: FeverItem[] = [];

    let sinceId: number = configs.lastId;
    for (let page = 0; page < FeverService.MAX_PAGES; page++) {
      const response: HttpResult = await FeverService.read(
        configs, '&items&since_id=' + sinceId.toString());
      if (!response.ok()) {
        break;
      }
      const body: FeverResponse | null = FeverService.parse(response.body);
      if (body === null || body.items === undefined || body.items === null
        || body.items.length === 0) {
        break;
      }

      let pageMax: number = sinceId;
      for (const item of body.items) {
        collected.push(item);
        if (item.id > pageMax) {
          pageMax = item.id;
        }
      }
      // `since_id` is exclusive, so a page that does not advance would loop.
      if (pageMax <= sinceId) {
        break;
      }
      sinceId = pageMax;

      if (body.items.length < FeverService.PAGE_SIZE
        || collected.length >= configs.fetchLimit) {
        break;
      }
    }

    if (collected.length === 0) {
      batch.lastId = configs.lastId;
      return batch;
    }

    batch.lastId = sinceId;
    // Fever wants a `before` timestamp when marking a whole feed read: the time
    // of this client's most recent items request.
    batch.lastFetched = Math.floor(Date.now() / 1000);

    for (const item of collected) {
      const source: Feed | undefined = sourceMap.get(item.feed_id.toString());
      if (source === undefined) {
        continue;
      }

      const article: Article = new Article();
      article.feedId = source.id;
      article.title = item.title;
      article.link = item.url;
      article.published = item.created_on_time > 0
        ? item.created_on_time * 1000 : Date.now();
      article.fetched = Date.now();
      article.content = item.html;
      article.snippet = FeedParser.htmlDecode(item.html);
      article.author = item.author;
      article.read = item.is_read === 1;
      article.starred = item.is_saved === 1;
      article.hidden = false;
      article.notify = false;
      article.serviceRef = item.id.toString();
      article.guid = 'fever-'.concat(item.id.toString());
      article.imageUrl = FeedParser.firstImageSrc(item.html, article.link);

      if (source.rulesJson.length > 0) {
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

      batch.articles.push(article);
    }

    return batch;
  }

  /* ---------------------------------------------------------- remote state */

  private static addIds(target: Set<string>, csv: string | undefined): void {
    if (csv === undefined || csv === null || csv.length === 0) {
      return;
    }
    for (const raw of csv.split(',')) {
      const id: string = raw.trim();
      if (id.length > 0) {
        target.add(id);
      }
    }
  }

  /**
   * Fever reports read and saved state as two comma-separated id strings.
   * Both must be readable: reconciling against one and assuming the other is
   * empty would clear every local star.
   */
  static async syncItems(configs: ServiceConfigs): Promise<RemoteState | null> {
    const state: RemoteState = new RemoteState();

    const unreadResponse: HttpResult = await FeverService.read(configs, '&unread_item_ids');
    const savedResponse: HttpResult = await FeverService.read(configs, '&saved_item_ids');
    if (!unreadResponse.ok() || !savedResponse.ok()) {
      return null;
    }

    const unread: FeverResponse | null = FeverService.parse(unreadResponse.body);
    const saved: FeverResponse | null = FeverService.parse(savedResponse.body);
    if (unread === null || saved === null) {
      return null;
    }
    if (!FeverService.authenticated(unread) || !FeverService.authenticated(saved)) {
      return null;
    }

    FeverService.addIds(state.unread, unread.unread_item_ids);
    FeverService.addIds(state.starred, saved.saved_item_ids);
    return state;
  }

  /* ------------------------------------------------------------- writes */

  static async markRead(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    const response: HttpResult = await FeverService.write(
      configs, 'mark=item&as=read&id='.concat(serviceRef));
    return response.ok();
  }

  static async markUnread(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    const response: HttpResult = await FeverService.write(
      configs, 'mark=item&as=unread&id='.concat(serviceRef));
    return response.ok();
  }

  /**
   * `mark=item` takes a single id, so marking many is a sequence of writes
   * rather than one bulk call.
   */
  static async markEntriesRead(configs: ServiceConfigs,
    serviceRefs: string[]): Promise<boolean> {
    let ok: boolean = true;
    for (const ref of serviceRefs) {
      if (!await FeverService.markRead(configs, ref)) {
        ok = false;
      }
    }
    return ok;
  }

  static async star(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    const response: HttpResult = await FeverService.write(
      configs, 'mark=item&as=saved&id='.concat(serviceRef));
    return response.ok();
  }

  static async unstar(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    const response: HttpResult = await FeverService.write(
      configs, 'mark=item&as=unsaved&id='.concat(serviceRef));
    return response.ok();
  }

  /**
   * Mark a whole feed read. The `before` bound is required so items the client
   * has not received yet are not silently marked read.
   */
  static async markFeedAllRead(configs: ServiceConfigs,
    feedServiceRef: string): Promise<boolean> {
    const before: number = configs.lastFetched > 0
      ? configs.lastFetched : Math.floor(Date.now() / 1000);
    const response: HttpResult = await FeverService.write(configs,
      'mark=feed&as=read&id='.concat(feedServiceRef).concat('&before=').concat(before.toString()));
    return response.ok();
  }
}
