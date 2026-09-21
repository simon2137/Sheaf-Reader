import { Feed, Article, ServiceConfigs, SyncService } from '../model/Models';
import { HttpClient, HttpResult } from '../data/HttpClient';
import { FeedParser } from '../utils/FeedParser';
import { RuleEngine } from './RuleEngine';

/* ------------------------------------------------------------------ *
 * Google Reader API schema (partial), matching the original service
 * ------------------------------------------------------------------ */

const ALL_TAG: string = 'user/-/state/com.google/reading-list';
const READ_TAG: string = 'user/-/state/com.google/read';
const STAR_TAG: string = 'user/-/state/com.google/starred';

/** Inoreader requires an application id/key; the original ships a default. */
const DEFAULT_INOREADER_ID: string = '999999298';
const DEFAULT_INOREADER_KEY: string = 'KPbKYXTfgrKbwmroOeYC7mcW21ZRwF5Y';

export interface GrCategory {
  id: string;
  label: string;
}

export interface GrSubscription {
  id: string;
  title: string;
  url: string;
  htmlUrl: string;
  categories: GrCategory[];
}

export interface GrSubscriptionList {
  subscriptions: GrSubscription[];
}

export interface GrItemRef {
  id: string;
}

export interface GrItemRefs {
  itemRefs: GrItemRef[];
  continuation: string;
}

export interface GrOrigin {
  streamId: string;
  title: string;
  htmlUrl: string;
}

export interface GrSummary {
  content: string;
  direction: string;
}

export interface GrLink {
  href: string;
}

export interface GrContentItem {
  id: string;
  title: string;
  published: number;
  crawlTimeMsec: string;
  author: string;
  summary: GrSummary;
  canonical: GrLink[];
  alternate: GrLink[];
  origin: GrOrigin;
  /** Tag ids, e.g. `user/-/state/com.google/read`. */
  categories: string[];
}

export interface GrStreamContents {
  items: GrContentItem[];
  continuation: string;
}

/** A page-walk of new entries, plus the cursor to persist. */
export class GrItemBatch {
  articles: Article[] = [];
  /** New opaque id cursor; empty when nothing was fetched. */
  lastIdRef: string = '';
  /** New `ot` cursor in seconds; 0 when unchanged. */
  lastFetched: number = 0;
  /** Refs a local rule marked read; pushed back to the service. */
  pushRead: string[] = [];
  /** Refs a local rule starred; pushed back to the service. */
  pushStar: string[] = [];
}

/**
 * Google Reader API client, shared by GReader and Inoreader exactly as the
 * original shares `gReaderServiceHooks` between `SyncService.GReader` and
 * `SyncService.Inoreader`.
 */
export class GReaderService {
  /** Page size for the id-walk. */
  static readonly ID_PAGE: number = 1000;
  /** Hard cap on the contents-request page size. */
  static readonly CONTENT_PAGE: number = 1000;

  /**
   * Build headers and issue the request. Inoreader additionally needs the
   * `AppId` / `AppKey` pair.
   */
  private static async fetchApi(configs: ServiceConfigs, params: string,
    method: string, body: string): Promise<HttpResult> {
    const headers: Record<string, string> = {};
    if (configs.auth.length > 0) {
      headers['Authorization'] = configs.auth;
    }
    if (configs.type === SyncService.Inoreader) {
      headers['AppId'] = configs.inoreaderId.length > 0
        ? configs.inoreaderId : DEFAULT_INOREADER_ID;
      headers['AppKey'] = configs.inoreaderKey.length > 0
        ? configs.inoreaderKey : DEFAULT_INOREADER_KEY;
    }
    if (body.length > 0) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }

    const base: string = configs.endpoint ? configs.endpoint.trim() : '';
    if (base.length === 0) {
      const missing: HttpResult = new HttpResult();
      missing.error = 'GReader endpoint is not configured';
      return missing;
    }

    return HttpClient.send(method, base.concat(params), headers, body);
  }

  private static parse<T>(body: string): T | null {
    if (body.length === 0) {
      return null;
    }
    try {
      return JSON.parse(body) as T;
    } catch (err) {
      console.error('GReaderService: malformed JSON response');
      return null;
    }
  }

  /**
   * Walk a paginated id list using the `c=` continuation token.
   *
   * The loop is driven by the continuation token, NOT by "did the page fill
   * up to n?". A server is allowed to return fewer items than requested while
   * still handing back a continuation, and stopping early here would silently
   * truncate the unread/starred sets — which the reconciliation then reads as
   * "the service no longer has these", marking articles read locally.
   *
   * Returns null when a page could not be retrieved, so the caller can abort
   * the sync instead of reconciling against an incomplete set.
   */
  private static async fetchAll(configs: ServiceConfigs,
    params: string): Promise<Set<string> | null> {
    const results: Set<string> = new Set<string>();
    let continuation: string = '';

    do {
      let requestParams: string = params;
      if (continuation.length > 0) {
        requestParams = requestParams.concat('&c=').concat(continuation);
      }

      const response: HttpResult = await GReaderService.fetchApi(
        configs, requestParams, HttpClient.GET, '');
      if (!response.ok()) {
        console.error('GReaderService.fetchAll: request failed, aborting');
        return null;
      }

      const parsed: GrItemRefs | null = GReaderService.parse<GrItemRefs>(response.body);
      if (parsed === null) {
        return null;
      }

      let pageLength: number = 0;
      const refs: GrItemRef[] | undefined = parsed.itemRefs;
      if (refs !== undefined && refs !== null) {
        pageLength = refs.length;
        for (const ref of refs) {
          // Compact the id exactly as `fetchItems` does when it stores an
          // article's serviceRef. Upstream collects the raw id here while
          // storing the compacted one, so the two never compare equal and its
          // reconciliation marks every locally-unread article as read.
          results.add(GReaderService.compactId(ref.id, configs.useInt64));
        }
      }

      continuation = (parsed.continuation !== undefined && parsed.continuation !== null)
        ? parsed.continuation : '';

      // Guard against a server that repeats a continuation without progress.
      if (pageLength === 0) {
        break;
      }
    } while (continuation.length > 0);

    return results;
  }

  /**
   * POST `/reader/api/0/edit-tag`.
   *
   * `ref` may itself be a list joined with `&i=` (the mark-all-read path), so
   * the body is assembled parameter by parameter rather than by encoding the
   * whole string — encoding a joined list would destroy the separators.
   */
  private static async editTag(configs: ServiceConfigs, ref: string,
    tag: string, add: boolean): Promise<boolean> {
    if (ref.length === 0) {
      return false;
    }

    const refs: string[] = ref.split('&i=');
    let body: string = '';
    for (const single of refs) {
      if (body.length > 0) {
        body = body.concat('&');
      }
      body = body.concat('i=').concat(encodeURIComponent(single));
    }
    body = body.concat('&').concat(add ? 'a' : 'r')
      .concat('=').concat(encodeURIComponent(tag));

    const response: HttpResult = await GReaderService.fetchApi(
      configs, '/reader/api/0/edit-tag', HttpClient.POST, body);
    return response.ok();
  }

  /**
   * The last path segment of a GReader id. The Old Reader (`useInt64`) issues
   * ids wider than 64 bits, which are folded to a signed 64-bit decimal.
   */
  private static compactId(longId: string, useInt64: boolean): string {
    const parts: string[] = longId.split('/');
    const last: string = parts[parts.length - 1];
    if (!useInt64) {
      return last;
    }
    try {
      const value: bigint = BigInt('0x'.concat(last));
      return BigInt.asIntN(64, value).toString();
    } catch (err) {
      return last;
    }
  }

  /* ------------------------------------------------------------ hooks */

  /**
   * Validate the stored token against `/user-info`.
   */
  static async authenticate(configs: ServiceConfigs): Promise<boolean> {
    if (configs.auth.length === 0) {
      return false;
    }
    const response: HttpResult = await GReaderService.fetchApi(
      configs, '/reader/api/0/user-info', HttpClient.GET, '');
    return response.status === 200;
  }

  /**
   * Exchange username/password for an `Auth` token via ClientLogin.
   * Returns true when a token was obtained.
   */
  static async reauthenticate(configs: ServiceConfigs): Promise<boolean> {
    let body: string = 'Email='.concat(encodeURIComponent(configs.username))
      .concat('&Passwd=').concat(encodeURIComponent(configs.password));

    const response: HttpResult = await GReaderService.fetchApi(
      configs, '/accounts/ClientLogin', HttpClient.POST, body);
    if (response.status !== 200) {
      return false;
    }

    const match: RegExpMatchArray | null = response.body.match(/Auth=(\S+)/);
    if (match !== null && match.length > 1) {
      configs.auth = 'GoogleLogin auth='.concat(match[1]);
      return true;
    }
    return false;
  }

  /**
   * Collect subscriptions, and optionally their category labels.
   */
  static async updateSources(configs: ServiceConfigs): Promise<GrSubscription[] | null> {
    const response: HttpResult = await GReaderService.fetchApi(
      configs, '/reader/api/0/subscription/list?output=json', HttpClient.GET, '');
    if (response.status !== 200) {
      return null;
    }

    const parsed: GrSubscriptionList | null =
      GReaderService.parse<GrSubscriptionList>(response.body);
    if (parsed === null || parsed.subscriptions === undefined
      || parsed.subscriptions === null) {
      return null;
    }
    return parsed.subscriptions;
  }

  /**
   * Map a subscription onto a local source, mirroring the original, including
   * the The Old Reader duplicate-feed guard.
   */
  static toSource(subscription: GrSubscription, useInt64: boolean): Feed | null {
    const url: string = (subscription.url !== undefined && subscription.url !== null
      && subscription.url.length > 0) ? subscription.url : subscription.htmlUrl;
    const source: Feed = new Feed(url, subscription.title);
    source.serviceRef = subscription.id;

    if (!useInt64 && subscription.url === 'http://blog.theoldreader.com/rss') {
      // Omit the duplicate source The Old Reader injects.
      return null;
    }
    return source;
  }

  /**
   * Category label of a subscription used for group import, or empty.
   */
  static groupOf(subscription: GrSubscription): string {
    if (subscription.categories === undefined || subscription.categories === null
      || subscription.categories.length === 0) {
      return '';
    }
    const first: GrCategory = subscription.categories[0];
    return (first !== undefined && first !== null) ? first.label : '';
  }

  /**
   * Enumerate remote unread and starred ids.
   *
   * Inoreader exposes "unread" as an exclusion tag (`xt`) against the implicit
   * reading list, whereas GReader needs an explicit source stream (`s`).
   *
   * Returns null when either set could not be retrieved: reconciling against a
   * partial set would mark good articles as read.
   */
  static async syncItems(configs: ServiceConfigs): Promise<GReaderRemoteState | null> {
    const state: GReaderRemoteState = new GReaderRemoteState();

    let unread: Set<string> | null;
    let starred: Set<string> | null;

    if (configs.type === SyncService.Inoreader) {
      unread = await GReaderService.fetchAll(configs,
        '/reader/api/0/stream/items/ids?output=json&xt='.concat(READ_TAG).concat('&n=1000'));
      starred = await GReaderService.fetchAll(configs,
        '/reader/api/0/stream/items/ids?output=json&it='.concat(STAR_TAG).concat('&n=1000'));
    } else {
      unread = await GReaderService.fetchAll(configs,
        '/reader/api/0/stream/items/ids?output=json&s='.concat(ALL_TAG)
          .concat('&xt=').concat(READ_TAG).concat('&n=1000'));
      starred = await GReaderService.fetchAll(configs,
        '/reader/api/0/stream/items/ids?output=json&s='.concat(STAR_TAG).concat('&n=1000'));
    }

    if (unread === null || starred === null) {
      return null;
    }

    state.unread = unread;
    state.starred = starred;
    return state;
  }

  /**
   * Pull new entries. Mirrors the original's continuation walk, the `lastId`
   * stop condition and the `ot` (older-than) cursor advance.
   */
  static async fetchItems(configs: ServiceConfigs,
    sourceMap: Map<string, Feed>): Promise<GrItemBatch> {
    const batch: GrItemBatch = new GrItemBatch();
    const items: GrContentItem[] = [];
    let continuation: string = '';
    let stop: boolean = false;

    do {
      try {
        const remaining: number = configs.fetchLimit - items.length;
        const limit: number = Math.min(remaining, GReaderService.CONTENT_PAGE);
        if (limit <= 0) {
          break;
        }

        let params: string = '/reader/api/0/stream/contents?output=json&n='.concat(limit.toString());
        if (configs.lastFetched > 0) {
          params = params.concat('&ot=').concat(configs.lastFetched.toString());
        }
        if (continuation.length > 0) {
          params = params.concat('&c=').concat(continuation);
        }

        const response: HttpResult = await GReaderService.fetchApi(
          configs, params, HttpClient.GET, '');
        if (!response.ok()) {
          break;
        }

        const parsed: GrStreamContents | null =
          GReaderService.parse<GrStreamContents>(response.body);
        if (parsed === null || parsed.items === undefined || parsed.items === null) {
          break;
        }

        for (const item of parsed.items) {
          item.id = GReaderService.compactId(item.id, configs.useInt64);
          if (item.id === configs.lastIdRef || items.length >= configs.fetchLimit) {
            stop = true;
            break;
          }
          items.push(item);
        }

        continuation = (parsed.continuation !== undefined && parsed.continuation !== null)
          ? parsed.continuation : '';
      } catch (err) {
        break;
      }
    } while (!stop && continuation.length > 0 && items.length < configs.fetchLimit);

    if (items.length === 0) {
      return batch;
    }

    batch.lastIdRef = items[0].id;

    for (const raw of items) {
      const source: Feed | undefined = sourceMap.get(raw.origin.streamId);
      if (source === undefined) {
        continue;
      }

      const article: Article = new Article();
      article.feedId = source.id;
      article.title = raw.title;

      const canonical: GrLink[] | undefined = raw.canonical;
      article.link = (canonical !== undefined && canonical !== null && canonical.length > 0)
        ? canonical[0].href : '';

      // `published` is seconds; `crawlTimeMsec` is milliseconds as a string.
      article.published = raw.published * 1000;
      const crawl: number = parseInt(raw.crawlTimeMsec, 10);
      article.fetched = isNaN(crawl) ? Date.now() : crawl;

      const summaryHtml: string = (raw.summary !== undefined && raw.summary !== null
        && raw.summary.content !== undefined) ? raw.summary.content : '';

      let content: string = summaryHtml;
      if (configs.type === SyncService.Inoreader && configs.removeInoreaderAd) {
        content = GReaderService.stripInoreaderAd(content);
      }

      article.content = content;
      article.snippet = FeedParser.htmlDecode(content);
      article.author = raw.author;
      article.serviceRef = raw.id;
      article.guid = 'greader-'.concat(raw.id);
      article.hidden = false;
      article.notify = false;
      article.imageUrl = FeedParser.firstImageSrc(content, article.link);

      // Read/star state comes from the item's category tags.
      article.read = false;
      article.starred = false;
      if (raw.categories !== undefined && raw.categories !== null) {
        for (const category of raw.categories) {
          if (!article.read && category.endsWith('/state/com.google/read')) {
            article.read = true;
          } else if (!article.starred && category.endsWith('/state/com.google/starred')) {
            article.starred = true;
          }
        }
      }

      // Inoreader returns HTML entities in titles.
      if (configs.type === SyncService.Inoreader) {
        article.title = FeedParser.htmlDecode(article.title);
      }

      // Rules run here, and any resulting state change is pushed back.
      // Unlike the Miniflux port, the original does invoke these requests.
      if (source.rulesJson.length > 0) {
        const wasRead: boolean = article.read;
        const wasStarred: boolean = article.starred;
        RuleEngine.applyForFeed(source.rulesJson, article);
        if (article.read !== wasRead) {
          batch.pushRead.push(article.serviceRef);
        }
        if (article.starred !== wasStarred) {
          batch.pushStar.push(article.serviceRef);
        }
      }

      batch.articles.push(article);
    }

    if (batch.articles.length > 0) {
      batch.lastFetched = Math.round(batch.articles[0].fetched / 1000);
    }

    return batch;
  }

  /**
   * Drop Inoreader's injected advertisement block, which is the first element
   * of the body when present.
   */
  private static stripInoreaderAd(html: string): string {
    const text: string = FeedParser.htmlDecode(html);
    if (!text.trim().startsWith('Ads from Inoreader')) {
      return html;
    }
    // Remove the first top-level element only.
    const match: RegExpMatchArray | null = html.match(/^\s*<([a-zA-Z]+)[^>]*>[\s\S]*?<\/\1>/);
    if (match !== null) {
      return html.substring(match[0].length);
    }
    return html;
  }

  /* ------------------------------------------------------ state writes */

  static async markRead(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    return GReaderService.editTag(configs, serviceRef, READ_TAG, true);
  }

  static async markUnread(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    return GReaderService.editTag(configs, serviceRef, READ_TAG, false);
  }

  static async star(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    return GReaderService.editTag(configs, serviceRef, STAR_TAG, true);
  }

  static async unstar(configs: ServiceConfigs, serviceRef: string): Promise<boolean> {
    return GReaderService.editTag(configs, serviceRef, STAR_TAG, false);
  }

  /**
   * Batch mark-read for explicit refs (the date-bounded path).
   */
  static async markEntriesRead(configs: ServiceConfigs, refs: string[]): Promise<boolean> {
    if (refs.length === 0) {
      return true;
    }
    return GReaderService.editTag(configs, refs.join('&i='), READ_TAG, true);
  }

  /**
   * Server-side "mark all as read" for a whole subscription stream.
   */
  static async markStreamAllRead(configs: ServiceConfigs,
    streamRef: string): Promise<boolean> {
    if (streamRef.length === 0) {
      return false;
    }
    const body: string = 's='.concat(encodeURIComponent(streamRef));
    const response: HttpResult = await GReaderService.fetchApi(
      configs, '/reader/api/0/mark-all-as-read', HttpClient.POST, body);
    return response.ok();
  }
}

/** Remote read/star state used to reconcile local rows. */
export class GReaderRemoteState {
  unread: Set<string> = new Set<string>();
  starred: Set<string> = new Set<string>();
}
