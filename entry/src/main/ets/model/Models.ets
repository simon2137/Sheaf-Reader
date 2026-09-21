/**
 * Data model.
 *
 * Field names track the original project's `RSSSource` / `RSSItem` so the
 * sync-service ports can be read side by side with upstream source.
 */

/** Where an article opens when tapped. Mirrors `SourceOpenTarget`. */
export enum SourceOpenTarget {
  Local = 0,
  Webpage = 1,
  External = 2,
  FullContent = 3
}

/** Mirrors `SourceTextDirection`. */
export enum SourceTextDirection {
  LTR = 0,
  RTL = 1,
  Vertical = 2
}

/** Mirrors `SyncService` in the original `schema-types.ts`. */
export enum SyncService {
  None = 0,
  Fever = 1,
  Feedbin = 2,
  GReader = 3,
  Inoreader = 4,
  Miniflux = 5,
  Nextcloud = 6
}

/**
 * Feed model, equivalent to the original `RSSSource`.
 */
@Observed
export class Feed {
  /** `sid` upstream. */
  id: number = -1;
  url: string = '';
  /** `iconurl` upstream. */
  iconUrl: string = '';
  /** `name` upstream. */
  title: string = '';
  link: string = '';
  description: string = '';
  groupId: number = -1;
  openTarget: number = SourceOpenTarget.Local;
  unreadCount: number = 0;
  lastFetched: number = 0;
  /** Set when this source is managed by a sync service. */
  serviceRef: string = '';
  /** Per-source fetch frequency limit, in minutes. 0 = unlimited. */
  fetchFrequency: number = 0;
  textDir: number = SourceTextDirection.LTR;
  hidden: boolean = false;
  /** Serialised `SourceRule[]`. */
  rulesJson: string = '';

  constructor(url?: string, title?: string) {
    if (url) {
      this.url = url;
    }
    if (title) {
      this.title = title;
    }
  }

  isServiceManaged(): boolean {
    return this.serviceRef.length > 0;
  }
}

/**
 * Article model, equivalent to the original `RSSItem`.
 */
@Observed
export class Article {
  id: number = -1;
  /** `source` (the owning sid) upstream. */
  feedId: number = -1;
  /** Remote identifier used to reconcile read/star state with a service. */
  serviceRef: string = '';
  title: string = '';
  link: string = '';
  /** `creator` upstream. */
  author: string = '';
  content: string = '';
  snippet: string = '';
  /** `date` upstream. */
  published: number = 0;
  /** `fetchedDate` upstream. */
  fetched: number = 0;
  /** `hasRead` upstream. */
  read: boolean = false;
  starred: boolean = false;
  hidden: boolean = false;
  notify: boolean = false;
  /** `thumb` upstream. */
  imageUrl: string = '';
  guid: string = '';

  /** Transient field populated by joins for display. */
  feedTitle: string = '';
}

/**
 * Group model for organizing feeds.
 */
@Observed
export class FeedGroup {
  id: number = -1;
  name: string = '';
  isExpanded: boolean = true;
  feedCount: number = 0;
  unreadCount: number = 0;
}

/**
 * Actions a rule can apply, mirroring `ItemAction` in the original.
 */
export enum ItemAction {
  Read = 'r',
  Star = 's',
  Hide = 'h',
  Notify = 'n'
}

/**
 * Serialised rule actions, stored as `["r-true", "s-false"]` exactly like the
 * original `RuleActions.toKeys` / `fromKeys` pair.
 */
export class RuleActions {
  static toKeys(actions: Map<string, boolean>): string[] {
    const keys: string[] = [];
    actions.forEach((flag: boolean, action: string) => {
      keys.push(action + '-' + (flag ? 'true' : 'false'));
    });
    return keys;
  }

  /**
   * A bare action key (no "-value" suffix) means "apply", matching upstream.
   */
  static fromKeys(keys: string[]): Map<string, boolean> {
    const actions: Map<string, boolean> = new Map<string, boolean>();
    for (const key of keys) {
      const parts: string[] = key.split('-');
      const action: string = parts[0];
      if (parts.length > 1 && parts[1].length > 0) {
        actions.set(action, parts[1] === 'true');
      } else {
        actions.set(action, true);
      }
    }
    return actions;
  }
}

/**
 * A per-source automation rule, equivalent to `SourceRule`.
 */
export class SourceRule {
  regex: string = '';
  /** `FilterType` bit flags controlling which field is matched. */
  filterType: number = 0;
  /** When true the rule fires on match; when false, on non-match. */
  match: boolean = true;
  /** Serialised actions, see `RuleActions`. */
  actions: string[] = [];

  static toJson(rules: SourceRule[]): string {
    return JSON.stringify(rules);
  }

  static fromJson(json: string): SourceRule[] {
    if (!json) {
      return [];
    }
    try {
      const parsed: SourceRule[] = JSON.parse(json) as SourceRule[];
      return parsed !== null && parsed !== undefined ? parsed : [];
    } catch (err) {
      return [];
    }
  }
}

/**
 * Application settings.
 */
export class AppSettings {
  darkMode: number = DarkModeSetting.SYSTEM;
  fetchIntervalMinutes: number = 30;
  fontSize: number = 16;
  lineHeight: number = 1.6;
  showThumbnails: boolean = true;
  openInBuiltInView: boolean = true;
  /** Engine used by "search selected text" (`context.search`). */
  searchEngine: number = SearchEngine.Google;

  /**
   * A fresh copy of these settings.
   *
   * `AppStore.settings` is a *nested* object, and ArkUI only re-renders on a
   * property write to the `@Observed` store itself: mutating `settings.fontSize`
   * notifies nobody, so the reader kept rendering the typography it was built
   * with while the settings panel showed the new value (measured on device — the
   * label read "24 px" and the body still had 16 px metrics). Every setter
   * therefore replaces the whole object with a copy, which *is* such a write.
   */
  copy(): AppSettings {
    const next: AppSettings = new AppSettings();
    next.darkMode = this.darkMode;
    next.fetchIntervalMinutes = this.fetchIntervalMinutes;
    next.fontSize = this.fontSize;
    next.lineHeight = this.lineHeight;
    next.showThumbnails = this.showThumbnails;
    next.openInBuiltInView = this.openInBuiltInView;
    next.searchEngine = this.searchEngine;
    return next;
  }
}

export enum DarkModeSetting {
  SYSTEM = 0,
  LIGHT = 1,
  DARK = 2
}

/**
 * A page fetched for one article by "load webpage" / "load full content".
 *
 * The original keeps these as per-article *view* state: the stored item is never
 * rewritten, and choosing the action again toggles back to the feed's own text.
 * Keeping it here rather than on `Article` is what makes that reversible — and
 * it keeps the fetched page out of the database and out of backups, which
 * serialize whole `Article` objects.
 */
export class LoadedPage {
  /** The verbatim page, or the extracted article body. */
  body: string = '';
  /** True when `body` is an extracted article rather than the whole page. */
  extracted: boolean = false;

  /**
   * The mode code the callers compare against: 0 for a verbatim page, 1 for an
   * extracted one. "Nothing loaded" is the absence of the entry (-1), which is
   * why this is only ever built for a page that exists.
   */
  mode(): number {
    return this.extracted ? 1 : 0;
  }
}

/** Outcome of dry-running a rule against the articles already loaded. */
export interface RuleTestResult {
  matched: number;
  total: number;
}

/** Mirrors the original's `SearchEngine` choices. */
export enum SearchEngine {
  Google = 0,
  Bing = 1,
  Baidu = 2,
  DuckDuckGo = 3
}

/**
 * Filter for the article list.
 */
export enum ArticleFilter {
  ALL = 'all',
  UNREAD = 'unread',
  STARRED = 'starred'
}

export enum NavType {
  ALL,
  UNREAD,
  STARRED,
  FEED,
  GROUP
}

/**
 * Navigation target for the sidebar.
 */
export class NavigationTarget {
  type: NavType = NavType.ALL;
  feedId: number = -1;
  groupId: number = -1;
  /**
   * Localised title. Empty means "not set", letting the list header fall back
   * to the translated label for the current preset.
   */
  title: string = '';
}

/**
 * Result of a feed-parsing operation.
 */
export interface ParsedFeed {
  feed: Feed;
  articles: Article[];
}

/**
 * Result of an add-feed operation.
 */
export interface AddFeedResult {
  success: boolean;
  message: string;
  feed: Feed | null;
}

/**
 * Result of a refresh operation.
 */
export interface RefreshSummary {
  inserted: number;
  total: number;
}

/**
 * Result of an OPML import.
 */
export interface ImportSummary {
  success: number;
  failed: number;
}

/**
 * A single OPML outline entry.
 */
export interface OpmlEntry {
  url: string;
  title: string;
  groupName: string;
}

/**
 * Parsed OPML document.
 */
export interface ParsedOpml {
  entries: OpmlEntry[];
}

/**
 * Label / count pair used by sidebar rows.
 */
export interface SidebarRow {
  key: string;
  title: string;
  count: number;
  selected: boolean;
}

/**
 * Sync-service configuration, equivalent to `ServiceConfigs`.
 */
export class ServiceConfigs {
  type: number = SyncService.None;
  importGroups: boolean = false;
  /** Miniflux: base endpoint. GReader: API root, e.g. `https://theoldreader.com`. */
  endpoint: string = '';
  /** Miniflux: true = `X-Auth-Token`, false = HTTP Basic. */
  apiKeyAuth: boolean = true;
  /** Miniflux: API token, or base64 of `user:pass` for Basic auth. */
  authKey: string = '';
  /** Maximum number of entries to pull per sync. */
  fetchLimit: number = 1000;
  /** Miniflux: highest entry id seen so far. */
  lastId: number = 0;

  /* ---- GReader / Inoreader ---- */

  /** Credentials used to obtain the `Auth` token via ClientLogin. */
  username: string = '';
  password: string = '';
  /** `GoogleLogin auth=<token>`; sent verbatim in the Authorization header. */
  auth: string = '';
  /**
   * Opaque incremental cursor. GReader ids are strings (and can exceed 64
   * bits), so they cannot share the numeric `lastId` used by Miniflux.
   */
  lastIdRef: string = '';
  /** Seconds; the `/stream/contents?ot=` cursor. */
  lastFetched: number = 0;
  /** The Old Reader issues ids wider than 64 bits. */
  useInt64: boolean = false;
  /** Inoreader developer credentials; empty falls back to the app default. */
  inoreaderId: string = '';
  inoreaderKey: string = '';
  /** Strip Inoreader's injected "Ads from Inoreader" block. */
  removeInoreaderAd: boolean = true;

  static toJson(configs: ServiceConfigs): string {
    return JSON.stringify(configs);
  }

  static fromJson(json: string): ServiceConfigs {
    const configs: ServiceConfigs = new ServiceConfigs();
    if (!json) {
      return configs;
    }
    try {
      const parsed: ServiceConfigs = JSON.parse(json) as ServiceConfigs;
      if (parsed === null || parsed === undefined) {
        return configs;
      }
      configs.type = ServiceConfigs.numOr(parsed.type, SyncService.None);
      configs.importGroups = parsed.importGroups === true;
      configs.endpoint = ServiceConfigs.strOr(parsed.endpoint, '');
      configs.apiKeyAuth = parsed.apiKeyAuth !== false;
      configs.authKey = ServiceConfigs.strOr(parsed.authKey, '');
      configs.fetchLimit = ServiceConfigs.numOr(parsed.fetchLimit, 1000);
      configs.lastId = ServiceConfigs.numOr(parsed.lastId, 0);
      configs.username = ServiceConfigs.strOr(parsed.username, '');
      configs.password = ServiceConfigs.strOr(parsed.password, '');
      configs.auth = ServiceConfigs.strOr(parsed.auth, '');
      configs.lastIdRef = ServiceConfigs.strOr(parsed.lastIdRef, '');
      configs.lastFetched = ServiceConfigs.numOr(parsed.lastFetched, 0);
      configs.useInt64 = parsed.useInt64 === true;
      configs.inoreaderId = ServiceConfigs.strOr(parsed.inoreaderId, '');
      configs.inoreaderKey = ServiceConfigs.strOr(parsed.inoreaderKey, '');
      configs.removeInoreaderAd = parsed.removeInoreaderAd !== false;
    } catch (err) {
      console.error('ServiceConfigs.fromJson failed: ' + JSON.stringify(err));
    }
    return configs;
  }

  private static strOr(value: string | undefined, fallback: string): string {
    return (value !== undefined && value !== null) ? value : fallback;
  }

  private static numOr(value: number | undefined, fallback: number): number {
    return (value !== undefined && value !== null) ? value : fallback;
  }
}

/**
 * Article list layouts. Mirrors `ViewType` in the original's
 * `schema-types.ts`; `Cards` renders a grid, the rest render a vertical list
 * with a different card.
 */
export enum ViewType {
  Cards = 0,
  List = 1,
  Magazine = 2,
  Compact = 3,
  Customized = 4
}

/**
 * Display bits a view can carry. Mirrors `ViewConfigs`; the bits are positive
 * here (set = enabled), unlike `FilterType`.
 */
export enum ViewConfigs {
  None = 0,
  ShowCover = 1 << 0,
  ShowSnippet = 1 << 1,
  FadeRead = 1 << 2
}

/** Default display bits per view, matching each card's built-in look. */
export class ViewDefaults {
  static forType(viewType: number): number {
    switch (viewType) {
      case ViewType.Cards:
        return ViewConfigs.ShowCover | ViewConfigs.ShowSnippet;
      case ViewType.Magazine:
        return ViewConfigs.ShowCover | ViewConfigs.ShowSnippet;
      case ViewType.Compact:
        return ViewConfigs.None;
      case ViewType.Customized:
        return ViewConfigs.ShowCover | ViewConfigs.ShowSnippet;
      default:
        // List: a small cover and a snippet.
        return ViewConfigs.ShowCover | ViewConfigs.ShowSnippet;
    }
  }

  static label(viewType: number): string {
    switch (viewType) {
      case ViewType.Cards:
        return 'Cards';
      case ViewType.Magazine:
        return 'Magazine';
      case ViewType.Compact:
        return 'Compact';
      case ViewType.Customized:
        return 'Customised';
      default:
        return 'List';
    }
  }
}

/**
 * Outcome of a service synchronisation run.
 */
export interface SyncResult {
  ok: boolean;
  message: string;
  sourcesAdded: number;
  sourcesRemoved: number;
  itemsFetched: number;
  localUpdates: number;
  /**
   * Articles whose rules requested a notification. Both the local fetch path
   * and the service path raise these, matching the original.
   */
  notified: Article[];
}

/**
 * Minimal projection of an article used when reconciling read/star state with
 * a sync service.
 */
export class ServiceArticleRow {
  serviceRef: string = '';
  read: boolean = false;
  starred: boolean = false;
}

/**
 * Severity of an entry in the notification log. Mirrors `AppLogType`.
 */
export enum AppLogType {
  Info = 0,
  Warning = 1,
  Failure = 2,
  Article = 3
}

/**
 * One entry in the notification log, mirroring `AppLog` in the original's
 * `models/app.ts`.
 */
export class AppLog {
  type: number = AppLogType.Info;
  title: string = '';
  details: string = '';
  /** Article id, when the entry refers to one and should be clickable. */
  iid: number = -1;
  time: number = 0;

  constructor(type: number = AppLogType.Info, title: string = '',
    details: string = '', iid: number = -1) {
    this.type = type;
    this.title = title;
    this.details = details;
    this.iid = iid;
    this.time = Date.now();
  }

  isProblem(): boolean {
    return this.type === AppLogType.Failure || this.type === AppLogType.Warning;
  }

  refersToArticle(): boolean {
    return this.iid >= 0;
  }
}

/**
 * A single source that could not be fetched.
 */
export class FetchFailure {
  feedTitle: string = '';
  message: string = '';

  constructor(feedTitle: string = '', message: string = '') {
    this.feedTitle = feedTitle;
    this.message = message;
  }
}

/**
 * Everything a refresh produced that the notification log needs to record.
 */
export class RefreshOutcome {
  inserted: number = 0;
  /** Articles whose rules asked for a notification. */
  notified: Article[] = [];
  failures: FetchFailure[] = [];
}
