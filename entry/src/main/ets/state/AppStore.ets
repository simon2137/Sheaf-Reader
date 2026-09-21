import {
  Feed, Article, FeedGroup, AppSettings, DarkModeSetting, NavigationTarget, NavType,
  AddFeedResult, ImportSummary, ServiceConfigs, SyncService, SyncResult, SourceRule,
  AppLog, AppLogType, RefreshOutcome, ViewType, ViewConfigs, ViewDefaults,
  SourceTextDirection, SourceOpenTarget, SearchEngine, LoadedPage
} from '../model/Models';
import { FeedService } from '../services/FeedService';
import { SyncManager } from '../services/SyncManager';
import { BackupService, BackupOutcome } from '../services/BackupService';
import { DatabaseManager } from '../data/DatabaseManager';
import { FeedFilter, FilterType } from '../model/Filter';
import { Notifier } from '../utils/Notifier';
import { I18n } from '../utils/I18n';
import { FeedFetcher } from '../utils/FeedFetcher';
import { ContentExtractor, ExtractedContent } from '../utils/ContentExtractor';
import { moveItem, idsOf } from '../utils/ListOrder';
import { ScopeFilter } from '../utils/ScopeFilter';
import { FetchSchedule } from '../utils/FetchSchedule';
import { SIDEBAR_BREAKPOINT, SidebarState } from '../utils/SidebarState';
import { common } from '@kit.AbilityKit';

/**
 * Article list page size. The original renders a "Load more" button once the
 * window is exhausted; the same page size is used here.
 */
const ARTICLE_PAGE_SIZE: number = 300;

/**
 * Global application state. An @Observed class so child components can
 * bind to it with @ObjectLink and re-render on mutation.
 */
@Observed
export class AppStore {
  currentNav: NavigationTarget = new NavigationTarget();
  selectedArticleId: number = -1;
  /** Active UI language, e.g. `zh-CN`. Changing it rebuilds every surface. */
  locale: string = 'en-US';
  /**
   * The active article filter. Combines three mutually exclusive presets
   * (all / unread only / starred only) with independently toggleable bits
   * (show hidden, full-text search, case sensitivity), matching the original's
   * `FeedFilter`.
   */
  filter: FeedFilter = new FeedFilter();
  searchQuery: string = '';
  /** Whether the search bar is showing. The original starts with it hidden
   * (`PageState.searchOn = false`) and reveals it from the sidebar's "Search"
   * entry, the toolbar button, or Ctrl+F — the query is only applied while it
   * is on.
   */
  searchOn: boolean = false;

  /**
   * Ids of the groups whose sources are showing, mirroring `is_expanded`.
   * Held as a replaced array on the store so the sidebar redraws on a toggle.
   */
  expandedGroupIds: number[] = [];

  /**
   * Pages fetched by "load full content" / "load webpage", keyed by article id.
   * Transient view state: never persisted, never part of a backup.
   */
  loadedPages: Map<number, LoadedPage> = new Map<number, LoadedPage>();
  /**
   * Show only sources that still have unread articles in the sidebar, the
   * original's `unreadSourcesOnly`. Persisted so the choice survives a restart.
   */
  unreadSourcesOnly: boolean = false;
  /**
   * Whether the navigation sidebar is shown, the original's `menuOn` (`F1`
   * toggles it). Persisted; the breakpoint gate is applied once, on the first
   * layout pass, by `applySidebarBreakpoint`.
   */
  sidebarOpen: boolean = true;
  /** True once the breakpoint gate has been applied, so it only happens once. */
  private sidebarGated: boolean = false;
  /**
   * Live window width in vp. The original re-reads `getWindowBreakpoint()` on
   * every page selection (`keepMenu`), unlike the one-shot gate above, so the
   * page reports each measurement here.
   */
  windowWidthVp: number = SIDEBAR_BREAKPOINT;
  /**
   * Whether the window is in front, from `window.on('windowEvent')`. The
   * original only raises a system notification for a background fetch while its
   * window is *not* focused (`window.utils.isFocused()`), so this mirrors that
   * gate; it starts true because the app is in front when it launches.
   */
  windowFocused: boolean = true;
  feeds: Feed[] = [];
  groups: FeedGroup[] = [];
  articles: Article[] = [];
  totalUnread: number = 0;
  starredCount: number = 0;
  /**
   * Size of the currently loaded window. Grows by ARTICLE_PAGE_SIZE as the
   * user presses "Load more"; reset whenever the filter or selection changes.
   */
  articleLimit: number = ARTICLE_PAGE_SIZE;
  /** True while a further page is known to exist behind the current window. */
  canLoadMore: boolean = false;
  isLoadingMore: boolean = false;
  /** True while the reader is fetching the full text of the open article. */
  isLoadingFullContent: boolean = false;

  isLoading: boolean = false;
  isFetching: boolean = false;
  /**
   * Per-source fetch progress, the original's `fetchingProgress` /
   * `fetchingTotal`. `fetchTotal === 0` means "no per-source total yet" — during
   * the service-sync phase upstream leaves the ProgressBar indeterminate, so the
   * renderer distinguishes the two cases rather than dividing by zero.
   */
  fetchDone: number = 0;
  fetchTotal: number = 0;
  toastMessage: string = '';
  showAddFeed: boolean = false;
  showSettings: boolean = false;
  isDarkMode: boolean = false;

  settings: AppSettings = new AppSettings();

  /* ---- sync service state ---- */
  serviceConfigs: ServiceConfigs = new ServiceConfigs();
  serviceLinkedCount: number = 0;
  isSyncing: boolean = false;
  syncStatus: string = '';

  /* ---- notification log ---- */
  logs: AppLog[] = [];
  logMenuDisplay: boolean = false;
  /** Unread marker shown on the notification button. */
  logNotify: boolean = false;

  /* ---- article view ---- */
  viewType: number = ViewType.List;
  /** Display bits per view type, indexed by `ViewType`. */
  viewConfigs: number[] = [0, 0, 0, 0, 0];
  /** Whether the per-view display options row is expanded. */
  viewOptionsOpen: boolean = false;

  /** Keep the in-memory history bounded; the original grows unbounded. */
  private static readonly MAX_LOGS: number = 200;

  private service: FeedService = FeedService.getInstance();

  async initialize(): Promise<void> {
    await this.loadSettings();
    await this.loadServiceConfigs();
    await this.refreshData();
  }

  async loadSettings(): Promise<void> {
    const db: DatabaseManager = DatabaseManager.getInstance();
    this.settings.darkMode = parseInt(await db.getSetting('dark_mode', '0'), 10);
    this.settings.fetchIntervalMinutes = parseInt(await db.getSetting('fetch_interval', '30'), 10);
    this.settings.fontSize = parseInt(await db.getSetting('font_size', '16'), 10);
    // The sidebar's source filter, the original's `unreadSourcesOnly`.
    this.unreadSourcesOnly = (await db.getSetting('unread_sources_only', '0')) === '1';
    // Sidebar visibility, the original's `menuOn`.
    this.sidebarOpen = (await db.getSetting('menu_on', '1')) === '1';
    this.settings.lineHeight = parseFloat(await db.getSetting('line_height', '1.6'));
    this.settings.showThumbnails = (await db.getSetting('show_thumbnails', '1')) === '1';
    this.settings.openInBuiltInView = (await db.getSetting('built_in_view', '1')) === '1';
    this.settings.searchEngine = parseInt(
      await db.getSetting('search_engine', SearchEngine.Google.toString()), 10);

    // Article view. Configs are stored per view type so each layout keeps its
    // own display bits, as the original's `setViewConfigs(viewType, configs)`.
    this.viewType = parseInt(await db.getSetting('view_type',
      ViewType.List.toString()), 10);
    const storedConfigs: string = await db.getSetting('view_configs', '');
    this.viewConfigs = AppStore.parseViewConfigs(storedConfigs);

    // Filter presets and toggles, persisted as the original's `filterType`.
    // The fallback matches `FeedFilter`'s own initial value.
    const storedFilter: number = parseInt(await db.getSetting('filter_type',
      (FilterType.Default | FilterType.CaseInsensitive).toString()), 10);
    this.filter = new FeedFilter(storedFilter, this.searchQuery);

    // The locale itself was applied in EntryAbility, before the first frame.
    this.locale = I18n.currentLocale();

    this.updateDarkMode();
  }

  /**
   * Change the display language. The messages are swapped first so the rebuild
   * triggered by `locale` already reads the new strings.
   */
  async setLocale(locale: string, context: common.UIAbilityContext): Promise<void> {
    await I18n.init(context, locale);
    this.locale = I18n.currentLocale();
    await this.saveSetting('locale', this.locale);
  }

  /**
   * Parse the per-view display bits, falling back to each view's defaults for
   * anything missing or malformed.
   */
  private static parseViewConfigs(json: string): number[] {
    const configs: number[] = [
      ViewDefaults.forType(ViewType.Cards),
      ViewDefaults.forType(ViewType.List),
      ViewDefaults.forType(ViewType.Magazine),
      ViewDefaults.forType(ViewType.Compact),
      ViewDefaults.forType(ViewType.Customized)
    ];
    if (!json) {
      return configs;
    }
    try {
      const parsed: number[] = JSON.parse(json) as number[];
      if (parsed !== null && parsed !== undefined) {
        for (let i = 0; i < configs.length && i < parsed.length; i++) {
          if (parsed[i] !== undefined && parsed[i] !== null) {
            configs[i] = parsed[i];
          }
        }
      }
    } catch (err) {
      console.warn('AppStore: could not read stored view configs');
    }
    return configs;
  }

  /* ------------------------------------------------------- article view */

  async switchView(viewType: number): Promise<void> {
    this.viewType = viewType;
    await this.saveSetting('view_type', viewType.toString());
  }

  async toggleViewOptions(): Promise<void> {
    this.viewOptionsOpen = !this.viewOptionsOpen;
  }

  viewConfigFor(viewType: number): number {
    const value: number | undefined = this.viewConfigs[viewType];
    return value !== undefined ? value : ViewDefaults.forType(viewType);
  }

  hasViewConfig(bit: number): boolean {
    return (this.viewConfigFor(this.viewType) & bit) !== 0;
  }

  async toggleViewConfig(bit: number): Promise<void> {
    const next: number[] = this.viewConfigs.slice();
    next[this.viewType] = this.viewConfigFor(this.viewType) ^ bit;
    // Reassign so the @Observed store notifies the UI.
    this.viewConfigs = next;
    await this.saveSetting('view_configs', JSON.stringify(next));
  }

  async saveSetting(key: string, value: string): Promise<void> {
    await DatabaseManager.getInstance().setSetting(key, value);
  }

  /**
   * Publish a change made inside `settings`.
   *
   * `settings` is a nested object, so `this.settings.fontSize = n` notifies
   * nobody — only a property write on this `@Observed` store does (the same trap
   * the dark-mode, group and archive paths already document). Replacing the
   * object with a copy is that write. Without it the reader kept rendering the
   * typography it was built with while the panel showed the new value: measured
   * on device, the label read "24 px" and the body still had 16 px metrics.
   */
  private publishSettings(): void {
    this.settings = this.settings.copy();
  }

  updateDarkMode(): void {
    this.isDarkMode = this.settings.darkMode === DarkModeSetting.DARK;
  }

  async setDarkMode(mode: number): Promise<void> {
    this.settings.darkMode = mode;
    this.publishSettings();
    await this.saveSetting('dark_mode', mode.toString());
    this.updateDarkMode();
  }

  async setFontSize(size: number): Promise<void> {
    this.settings.fontSize = size;
    this.publishSettings();
    await this.saveSetting('font_size', size.toString());
  }

  /** Toggle the sidebar's "unread sources only" filter, as the original does. */
  async setUnreadSourcesOnly(value: boolean): Promise<void> {
    this.unreadSourcesOnly = value;
    await this.saveSetting('unread_sources_only', value ? '1' : '0');
  }

  /**
   * Show or hide the navigation sidebar, persisting the choice the way the
   * original's `toggleMenu` does (`setDefaultMenu`).
   */
  async toggleSidebar(): Promise<void> {
    this.sidebarOpen = !this.sidebarOpen;
    await this.saveSetting('menu_on', this.sidebarOpen ? '1' : '0');
  }

  /**
   * Apply the breakpoint gate to the stored sidebar choice, once. The original
   * evaluates `getWindowBreakpoint() && getDefaultMenu()` when the state is
   * built, i.e. before the user can have toggled anything, so a later resize
   * does not close a sidebar the user opened on purpose.
   */
  applySidebarBreakpoint(widthVp: number): void {
    if (this.sidebarGated) {
      return;
    }
    this.sidebarGated = true;
    this.sidebarOpen = SidebarState.initial(this.sidebarOpen, widthVp);
  }

  async setFetchInterval(minutes: number): Promise<void> {
    this.settings.fetchIntervalMinutes = minutes;
    this.publishSettings();
    await this.saveSetting('fetch_interval', minutes.toString());
  }

  async setShowThumbnails(value: boolean): Promise<void> {
    this.settings.showThumbnails = value;
    this.publishSettings();
    await this.saveSetting('show_thumbnails', value ? '1' : '0');
  }

  async setOpenInBuiltInView(value: boolean): Promise<void> {
    this.settings.openInBuiltInView = value;
    this.publishSettings();
    await this.saveSetting('built_in_view', value ? '1' : '0');
  }

  /** Engine used by "search selected text". */
  async setSearchEngine(engine: number): Promise<void> {
    this.settings.searchEngine = engine;
    this.publishSettings();
    await this.saveSetting('search_engine', engine.toString());
  }

  async refreshData(): Promise<void> {
    this.isLoading = true;
    this.feeds = await this.service.getFeedsWithCounts();
    this.groups = await this.service.getGroupsWithCounts();
    this.syncExpandedGroups();
    this.totalUnread = await this.service.getTotalUnreadCount();
    this.starredCount = await this.service.getStarredCount();
    await this.loadArticles();
    this.isLoading = false;
  }

  /**
   * Delete articles published before `days` ago and reload every count that
   * depends on them. `days = 0` deletes the whole archive.
   *
   * Mirrors the original's `deleteArticles` thunk, which deletes the rows and
   * then recomputes the unread counts; here the reload covers feeds, groups and
   * the article window at once.
   */
  async deleteOldArticles(days: number): Promise<number> {
    const removed: number = await this.service.deleteArticles(days);
    await this.refreshData();
    return removed;
  }

  /** Serialized size of the article store, in bytes. */
  async articleStorageBytes(): Promise<number> {
    return await this.service.articleStorageBytes();
  }

  /**
   * Refresh just the sources named by a scope: one feed (`groupId = -1`) or
   * every feed of one group (`feedId = -1`). Backs the group / source context
   * menu's "refresh", mirroring the original's `fetchItems(false, sids)`.
   */
  async refreshScope(feedId: number, groupId: number): Promise<number> {
    const scopeIds: number[] = ScopeFilter.feedIds(this.feeds, groupId, feedId);
    if (scopeIds.length === 0) {
      return 0;
    }
    return await this.refreshFeeds(false, scopeIds);
  }

  /**
   * Reload the current window. The window size is preserved so that a
   * background refresh, or marking an article read, does not collapse a list
   * the user already paged through.
   */
  async loadArticles(): Promise<void> {
    // The active filter carries its own search pattern.
    if (this.filter.search !== this.searchQuery) {
      this.filter = new FeedFilter(this.filter.type, this.searchQuery);
    }
    this.articles = await this.queryPage(this.articleLimit);
  }

  /**
   * Reload from the first page. Used whenever the filter or the selected
   * source changes, mirroring the original's reset on navigation.
   */
  async resetArticles(): Promise<void> {
    this.articleLimit = ARTICLE_PAGE_SIZE;
    await this.loadArticles();
  }

  /**
   * Append the next page, mirroring the original's "Load more" button. The
   * whole window is re-queried at the larger size rather than appended by
   * offset, so an article arriving between two pages can neither leave a gap
   * nor appear twice.
   */
  async loadMoreArticles(): Promise<void> {
    if (this.isLoadingMore || !this.canLoadMore) {
      return;
    }
    this.isLoadingMore = true;
    this.articleLimit += ARTICLE_PAGE_SIZE;
    this.articles = await this.queryPage(this.articleLimit);
    this.isLoadingMore = false;
  }

  /**
   * Fetch one window of articles. A single row beyond the window is requested
   * so that "load more" is only offered when a further page really exists.
   */
  private async queryPage(limit: number): Promise<Article[]> {
    const nav: NavigationTarget = this.currentNav;
    const feedId: number = nav.type === NavType.FEED ? nav.feedId : -1;
    const groupId: number = nav.type === NavType.GROUP ? nav.groupId : -1;

    // A full-text search is evaluated in memory over a bounded scan, so a
    // window that reaches the end of that scan must not promise more.
    const searching: boolean = this.filter.search.length > 0;
    const scanExhausted: boolean = searching && limit + 1 > DatabaseManager.SEARCH_SCAN_LIMIT;
    const probe: number = scanExhausted ? limit : limit + 1;

    const rows: Article[] = await this.service.getArticles(this.filter, feedId, groupId, probe, 0);
    this.canLoadMore = !scanExhausted && rows.length > limit;
    if (rows.length > limit) {
      return rows.slice(0, limit);
    }
    return rows;
  }

  /**
   * Switch the preset (all / unread only / starred only) while preserving the
   * independent toggle bits, mirroring the original's `switchFilter`:
   * `filter | (oldType & FilterType.Toggles)`.
   */
  async switchFilter(preset: number): Promise<void> {
    const toggles: number = this.filter.type & FilterType.Toggles;
    // Reassign rather than mutate: only a property write on the @Observed
    // store is tracked, a nested field write would not notify the UI.
    this.filter = new FeedFilter(preset | toggles, this.searchQuery);
    await this.saveFilterType();
    await this.resetArticles();
  }

  /**
   * Flip one toggle bit, mirroring the original's `toggleFilter` (`type ^= bit`).
   */
  async toggleFilter(bit: number): Promise<void> {
    this.filter = new FeedFilter(this.filter.type ^ bit, this.searchQuery);
    await this.saveFilterType();
    await this.resetArticles();
  }

  /**
   * Persist the filter bits, as the original does through `SchemaTypes.filterType`
   * (`setFilterType` in `page.ts`).
   *
   * Without this the presets and the six toggles were memory-only, so a restart
   * silently put the list back to "All articles" — the view layout was already
   * persisted, which made the loss look like a bug rather than a missing write.
   */
  private async saveFilterType(): Promise<void> {
    await this.saveSetting('filter_type', this.filter.type.toString());
  }

  filterHas(bit: number): boolean {
    return (this.filter.type & bit) !== 0;
  }

  async setFullSearch(enabled: boolean): Promise<void> {
    if (this.filterHas(FilterType.FullSearch) !== enabled) {
      await this.toggleFilter(FilterType.FullSearch);
    }
  }

  async setShowHidden(enabled: boolean): Promise<void> {
    if (this.filterHas(FilterType.ShowHidden) !== enabled) {
      await this.toggleFilter(FilterType.ShowHidden);
    }
  }

  /**
   * The `CaseInsensitive` bit is positive, so "case sensitive" means clearing
   * it — the same polarity the original's rules pane uses.
   */
  async setCaseSensitive(enabled: boolean): Promise<void> {
    if (this.filterHas(FilterType.CaseInsensitive) === enabled) {
      await this.toggleFilter(FilterType.CaseInsensitive);
    }
  }

  async navigateTo(target: NavigationTarget): Promise<void> {
    this.currentNav = target;
    this.selectedArticleId = -1;
    /*
     * The original's `SELECT_PAGE` reducer does `menu: state.menu && keepMenu`
     * with `keepMenu = getWindowBreakpoint()`, i.e. picking a page on a narrow
     * window closes the drawer. Note it only changes the live flag — the stored
     * `menuOn` preference is untouched, so a later wide window still honours it.
     */
    if (!SidebarState.keepsMenuOnSelect(this.windowWidthVp)) {
      this.sidebarOpen = false;
    }
    // Selecting "All articles" also switches the preset. The original's sidebar
    // has only that entry; unread / starred are filter-bar toggles, so there is
    // no `Unread` / `Starred` page to switch to.
    if (target.type === NavType.ALL) {
      await this.switchFilter(FilterType.Default);
    } else {
      await this.resetArticles();
    }
  }

  /**
   * Toggle the search bar, mirroring the original's `toggleSearch`:
   * it closes an open drawer on a narrow window, and switching search *off*
   * clears the query so the list is not left silently filtered.
   */
  async toggleSearch(): Promise<void> {
    this.searchOn = !this.searchOn;
    if (!SidebarState.keepsMenuOnSelect(this.windowWidthVp)) {
      this.sidebarOpen = false;
    }
    if (!this.searchOn) {
      await this.search('');
    }
  }

  async search(query: string): Promise<void> {
    this.searchQuery = query;
    await this.resetArticles();
  }

  async selectArticle(articleId: number): Promise<void> {
    this.selectedArticleId = articleId;
    const article: Article | undefined = this.articles.find((a: Article) => a.id === articleId);
    if (article !== undefined && !article.read) {
      article.read = true;
      await this.service.markArticleRead(articleId, true);
      await SyncManager.pushRead(article.serviceRef, true);
      await this.recount();
    }
  }

  /**
   * Open an article that may not be in the current list — used by the
   * notification log, whose entries can point outside the active filter.
   * Mirrors the original's `showItemFromId`.
   */
  async openArticleById(articleId: number): Promise<void> {
    if (articleId < 0) {
      return;
    }
    const present: boolean = this.articles.some((a: Article) => a.id === articleId);
    if (!present) {
      const article: Article | null = await this.service.getArticleById(articleId);
      if (article === null) {
        return;
      }
      this.articles = [article].concat(this.articles);
    }
    await this.selectArticle(articleId);
  }

  async toggleStar(articleId: number): Promise<void> {
    const article: Article | undefined = this.articles.find((a: Article) => a.id === articleId);
    if (article !== undefined) {
      article.starred = !article.starred;
      await this.service.markArticleStarred(articleId, article.starred);
      await SyncManager.pushStar(article.serviceRef, article.starred);
      this.starredCount = await this.service.getStarredCount();
    }
  }

  async toggleRead(articleId: number): Promise<void> {
    const article: Article | undefined = this.articles.find((a: Article) => a.id === articleId);
    if (article !== undefined) {
      article.read = !article.read;
      await this.service.markArticleRead(articleId, article.read);
      await SyncManager.pushRead(article.serviceRef, article.read);
      await this.recount();
    }
  }

  /**
   * Hide or unhide an article. Hiding is local to this client — the sync
   * services have no equivalent concept — so nothing is pushed upstream.
   */
  async toggleHidden(articleId: number): Promise<void> {
    const article: Article | undefined = this.articles.find((a: Article) => a.id === articleId);
    if (article === undefined) {
      return;
    }
    article.hidden = !article.hidden;
    await this.service.markArticleHidden(articleId, article.hidden);
    // A hidden article drops out of the list unless hidden ones are shown.
    if (article.hidden && !this.filterHas(FilterType.ShowHidden)) {
      await this.loadArticles();
    }
  }

  async markAllRead(): Promise<void> {
    const nav: NavigationTarget = this.currentNav;
    await this.markAllReadFor(
      nav.type === NavType.FEED ? nav.feedId : -1,
      nav.type === NavType.GROUP ? nav.groupId : -1, 0, true);
  }

  /**
   * Mark every unread article in one scope as read, optionally bounded by a
   * publication date. Mirrors the original's `markAllRead(sids, date, before)`,
   * which the "mark all as read" menu uses for its 1 / 3 / 7 day entries.
   *
   * `cutoff = 0` keeps the unbounded behaviour the toolbar's plain action has.
   */
  async markAllReadFor(feedId: number, groupId: number,
                       cutoff: number = 0, before: boolean = true): Promise<void> {
    // Tell the service first. The service is the authority on read state, so a
    // local-only mark-all is reverted by the next sync: the service still
    // reports those entries as unread and reconciliation believes it.
    await this.pushMarkAllRead(feedId, groupId, cutoff, before);

    await this.service.markAllRead(feedId, groupId, cutoff, before);
    await this.loadArticles();
    await this.recount();
  }

  /**
   * Push "everything in scope is read" to the configured service, if any.
   *
   * The scope is expressed as local feed ids because that is what every
   * service's implementation translates into its own addressing: a per-feed
   * endpoint where one exists, or the exact remote refs otherwise.
   */
  private async pushMarkAllRead(feedId: number, groupId: number,
                                cutoff: number, before: boolean): Promise<void> {
    if (!this.hasService()) {
      return;
    }
    const ids: number[] = [];
    for (const feed of this.feeds) {
      if (feed.serviceRef.length === 0) {
        continue;
      }
      if (feedId >= 0 && feed.id !== feedId) {
        continue;
      }
      if (groupId >= 0 && feed.groupId !== groupId) {
        continue;
      }
      ids.push(feed.id);
    }
    if (ids.length > 0) {
      // A cutoff of 0 means "no date bound": mark the whole feed, not a window.
      await SyncManager.pushMarkAllRead(ids, cutoff, before);
    }
  }

  /**
   * Mark every article above (or below) the given one as read, mirroring the
   * original's `article.markAbove` / `article.markBelow`.
   *
   * The range is the window the user is looking at, not the whole source: the
   * original applies it to the rendered list, and so does this.
   */
  async markAround(articleId: number, above: boolean): Promise<void> {
    const index: number = this.articles.findIndex((a: Article) => a.id === articleId);
    if (index < 0) {
      return;
    }
    const from: number = above ? 0 : index + 1;
    const to: number = above ? index : this.articles.length;

    const ids: number[] = [];
    const refs: string[] = [];
    for (let i = from; i < to; i++) {
      const article: Article = this.articles[i];
      if (article.read) {
        continue;
      }
      // Mutate in place so the list re-renders without a re-query.
      article.read = true;
      ids.push(article.id);
      if (article.serviceRef.length > 0) {
        refs.push(article.serviceRef);
      }
    }
    if (ids.length === 0) {
      return;
    }

    await this.service.markArticlesRead(ids);
    await SyncManager.pushReadMany(refs);
    await this.recount();
  }

  /**
   * Toggle the per-article "notify if fetched in the background" flag, the
   * manual counterpart of the `n-true` rule action.
   */
  async toggleNotify(articleId: number): Promise<void> {
    const article: Article | undefined = this.articleById(articleId);
    if (article === undefined) {
      return;
    }
    article.notify = !article.notify;
    await this.service.setArticleNotify(articleId, article.notify);
  }

  /**
   * Fetch the article's own page as *view* state, mirroring the original's
   * "Load full content" (extract) and "Load webpage" (verbatim).
   *
   * The original never rewrites the stored item: the fetched page lives in the
   * article component's state, so choosing the action again restores the feed's
   * own text. This port keeps it in `loadedPages` for the same reason — an
   * earlier revision wrote the page into `article.content` and persisted it,
   * which made the action destructive and impossible to undo.
   *
   * Returns an I18n key describing a failure, or an empty string on success, so
   * the caller keeps ownership of the presentation.
   */
  async loadSourcePage(articleId: number, extract: boolean): Promise<string> {
    const article: Article | undefined = this.articles.find((a: Article) => a.id === articleId);
    if (article === undefined || this.isLoadingFullContent) {
      return '';
    }
    if (article.link.length === 0) {
      return 'app.noLink';
    }

    this.isLoadingFullContent = true;
    try {
      const page: string | null = await FeedFetcher.fetchUrl(article.link);
      if (page === null) {
        return 'article.error';
      }

      let body: string = page;
      if (extract) {
        const extracted: ExtractedContent | null = ContentExtractor.extract(page);
        if (extracted === null) {
          return 'app.noContent';
        }
        body = extracted.html;
      }

      const loaded: LoadedPage = new LoadedPage();
      loaded.body = body;
      loaded.extracted = extract;
      // Reassign rather than mutate: only a property write on the @Observed
      // store is tracked, a nested map write would not notify the UI.
      const next: Map<number, LoadedPage> = new Map<number, LoadedPage>(this.loadedPages);
      next.set(articleId, loaded);
      this.loadedPages = next;
      return '';
    } finally {
      this.isLoadingFullContent = false;
    }
  }

  /** "Load full content": fetch the page and keep only its article body. */
  async loadFullContent(articleId: number): Promise<string> {
    return this.loadSourcePage(articleId, true);
  }

  /**
   * Which page load is active for an article: -1 none, 0 verbatim, 1 extracted.
   * The caller uses it to make the actions toggle, as the original's do.
   */
  loadedModeFor(articleId: number): number {
    const loaded: LoadedPage | undefined = this.loadedPages.get(articleId);
    if (loaded === undefined) {
      return -1;
    }
    return loaded.mode();
  }

  /** The loaded page for an article, or an empty string when there is none. */
  loadedBodyFor(articleId: number): string {
    const loaded: LoadedPage | undefined = this.loadedPages.get(articleId);
    return loaded === undefined ? '' : loaded.body;
  }

  /** Drop a loaded page, restoring the feed's own text. */
  clearLoadedPage(articleId: number): void {
    if (!this.loadedPages.has(articleId)) {
      return;
    }
    const next: Map<number, LoadedPage> = new Map<number, LoadedPage>(this.loadedPages);
    next.delete(articleId);
    this.loadedPages = next;
  }

  /** The article from the currently loaded window, if present. */
  articleById(articleId: number): Article | undefined {
    return this.articles.find((a: Article) => a.id === articleId);
  }

  /**
   * The open target configured on the article's source, defaulting to the
   * in-app reader. Mirrors `sources.openTarget`.
   */
  openTargetFor(articleId: number): number {
    const article: Article | undefined = this.articleById(articleId);
    if (article === undefined) {
      return SourceOpenTarget.Local;
    }
    const feed: Feed | undefined = this.feeds.find((f: Feed) => f.id === article.feedId);
    return feed === undefined ? SourceOpenTarget.Local : feed.openTarget;
  }

  /**
   * The text direction configured on the article's source, defaulting to LTR.
   */
  textDirFor(feedId: number): number {
    const feed: Feed | undefined = this.feeds.find((f: Feed) => f.id === feedId);
    return feed === undefined ? SourceTextDirection.LTR : feed.textDir;
  }

  /**
   * Persist edited per-source settings, then reload: a rename changes every
   * list row and a hidden flag changes the unscoped list.
   */
  async saveFeedSettings(feedId: number, title: string, fetchFrequency: number,
    openTarget: number, textDir: number, hidden: boolean): Promise<void> {
    const feed: Feed | undefined = this.feeds.find((f: Feed) => f.id === feedId);
    if (feed === undefined) {
      return;
    }
    feed.title = title;
    feed.fetchFrequency = fetchFrequency;
    feed.openTarget = openTarget;
    feed.textDir = textDir;
    feed.hidden = hidden;
    await this.service.updateFeed(feed);
    await this.refreshData();
  }

  async recount(): Promise<void> {
    this.totalUnread = await this.service.getTotalUnreadCount();
    this.starredCount = await this.service.getStarredCount();
    this.feeds = await this.service.getFeedsWithCounts();
    this.groups = await this.service.getGroupsWithCounts();
    this.syncExpandedGroups();
    // Keep the badge honest once everything has been read.
    if (this.totalUnread === 0) {
      await Notifier.requestAttention(0);
    }
  }

  /**
   * Refresh every source, or only `scopeIds` when the group / source context
   * menu asks for one scope.
   *
   * `background` marks an automatic run (startup or the interval timer). Only
   * those raise system notifications, matching the original's
   * `fetchItems(background)` behaviour — a manual refresh stays quiet.
   *
   * Note that `background` is *not* what gates the per-source frequency limit:
   * upstream keys that off `sids === null`, so a manual unscoped refresh obeys
   * it too. See `FetchSchedule`.
   */
  async refreshFeeds(background: boolean = false,
                     scopeIds: number[] | null = null): Promise<number> {
    if (this.isFetching) {
      return 0;
    }
    this.isFetching = true;
    // No per-source total yet: the bar stays indeterminate until the fetch
    // phase reports one, exactly like `fetchingTotal === 0` upstream.
    this.fetchDone = 0;
    this.fetchTotal = 0;
    try {
      // Service-managed sources are pulled from the service; everything else
      // is fetched directly. Both may be present at once.
      //
      // A scoped refresh only syncs when the scope actually contains a
      // service-linked source, mirroring the original's guard in `fetchItems`.
      const scopeHasService: boolean = scopeIds === null
        || this.feeds.some((f: Feed) => scopeIds.indexOf(f.id) >= 0
          && f.serviceRef.length > 0);
      if (this.hasService() && scopeHasService) {
        const sync: SyncResult = await this.syncWithService(background);
        if (!sync.ok) {
          this.toastMessage = sync.message;
        }
      }

      // The original consults each source's `fetchFrequency` on the unscoped
      // path only — the header refresh button, F5 and the interval timer all
      // call `fetchItems()` with no source list, and all of them honour the
      // limit. A scoped refresh names its sources and skips the limit.
      const outcome: RefreshOutcome = await this.service.refreshAllFeeds(
        (done: number, total: number) => {
          this.fetchDone = done;
          this.fetchTotal = total;
        }, FetchSchedule.appliesToScope(scopeIds), scopeIds);

      await this.recordRefresh(outcome, background);
      await this.refreshData();
      // A background run that found something new draws attention the way the
      // original flashes its taskbar icon: the unread count becomes the badge.
      if (background) {
        await Notifier.requestAttention(this.totalUnread);
      }
      this.toastMessage = outcome.inserted > 0
        ? I18n.get('app.fetched',
          new Map<string, string | number>([['count', outcome.inserted]]))
        : I18n.get('app.upToDate');
      return outcome.inserted;
    } finally {
      this.isFetching = false;
      this.fetchDone = 0;
      this.fetchTotal = 0;
    }
  }

  /**
   * Turn a refresh result into notification-log entries. Without this a
   * failing source is completely silent, which is how a truncated sync went
   * unnoticed earlier.
   */
  private async recordRefresh(outcome: RefreshOutcome,
    background: boolean): Promise<void> {
    for (const failure of outcome.failures) {
      this.addLog(AppLogType.Failure,
        I18n.get('app.fetchFailed',
          new Map<string, string | number>([['name', failure.feedTitle]])),
        failure.message, -1);
    }
    if (outcome.inserted > 0) {
      this.addLog(AppLogType.Info,
        I18n.get('app.fetchedOk',
          new Map<string, string | number>([['count', outcome.inserted]])), '', -1);
    }
    for (const article of outcome.notified) {
      this.addLog(AppLogType.Article, article.title,
        article.feedTitle, article.id);
      // The original raises a system notification only when the window is not
      // focused (`if (!window.utils.isFocused())`): a visible window already
      // shows the article in its own log menu, so a popup would be noise.
      if (background && !this.windowFocused) {
        const published: boolean = await Notifier.notify(article.title,
          article.feedTitle, article.id);
        if (!published) {
          // The original cannot fail here — Electron always raises the popup.
          // A refusal (1600004: notifications disabled for the app) is worth a
          // line in the log instead of a silent `console.warn`, which is
          // invisible on a device with an empty hilog buffer.
          this.addLog(AppLogType.Failure, I18n.get('app.notifyFailed'),
            Notifier.lastError, article.id);
        }
      }
    }
  }

  /* ------------------------------------------------ notification log */

  addLog(type: number, title: string, details: string, iid: number): void {
    // Reassign rather than push: only a property write on the @Observed store
    // is tracked.
    this.logs = this.logs.concat([new AppLog(type, title, details, iid)]);
    if (this.logs.length > AppStore.MAX_LOGS) {
      this.logs = this.logs.slice(this.logs.length - AppStore.MAX_LOGS);
    }
    if (!this.logMenuDisplay) {
      this.logNotify = true;
    }
  }

  toggleLogMenu(): void {
    this.logMenuDisplay = !this.logMenuDisplay;
    if (this.logMenuDisplay) {
      this.logNotify = false;
    }
  }

  closeLogMenu(): void {
    this.logMenuDisplay = false;
  }

  clearLogs(): void {
    this.logs = [];
    this.logNotify = false;
  }

  problemCount(): number {
    let count: number = 0;
    for (const entry of this.logs) {
      if (entry.isProblem()) {
        count++;
      }
    }
    return count;
  }

  /* ------------------------------------------------ sync service control */

  hasService(): boolean {
    return this.serviceConfigs.type !== SyncService.None;
  }

  async loadServiceConfigs(): Promise<void> {
    this.serviceConfigs = await SyncManager.loadConfigs();
    await this.refreshServiceCounts();
  }

  async refreshServiceCounts(): Promise<void> {
    const linked: Map<string, Feed> =
      await DatabaseManager.getInstance().getServiceLinkedFeeds();
    this.serviceLinkedCount = linked.size;
  }

  async saveServiceConfigs(configs: ServiceConfigs): Promise<void> {
    await SyncManager.saveConfigs(configs);
    this.serviceConfigs = configs;
    await this.refreshServiceCounts();
  }

  async testService(configs: ServiceConfigs): Promise<boolean> {
    return SyncManager.authenticate(configs);
  }

  /**
   * Run a full service sync and refresh the local views afterwards.
   * `background` mirrors the refresh flag: only automatic runs raise system
   * notifications.
   */
  async syncWithService(background: boolean = false): Promise<SyncResult> {
    if (this.isSyncing) {
      return {
        ok: false,
        message: I18n.get('app.syncRunning'),
        sourcesAdded: 0,
        sourcesRemoved: 0,
        itemsFetched: 0,
        localUpdates: 0,
        notified: []
      };
    }

    this.isSyncing = true;
    this.syncStatus = I18n.get('app.syncStarting');
    try {
      const result: SyncResult = await SyncManager.sync(this.serviceConfigs,
        (stage: string) => {
          this.syncStatus = stage;
        });
      if (!result.ok) {
        this.addLog(AppLogType.Failure, I18n.get('app.syncFailed'),
          result.message, -1);
      }
      for (const article of result.notified) {
        this.addLog(AppLogType.Article, article.title,
          article.feedTitle, article.id);
        if (background && !this.windowFocused) {
          const published: boolean = await Notifier.notify(article.title,
            article.feedTitle, article.id);
          if (!published) {
            this.addLog(AppLogType.Failure, I18n.get('app.notifyFailed'),
              Notifier.lastError, article.id);
          }
        }
      }
      await this.loadServiceConfigs();
      await this.refreshData();
      return result;
    } finally {
      this.isSyncing = false;
      this.syncStatus = '';
    }
  }

  async removeSyncService(): Promise<void> {
    await SyncManager.removeService();
    await this.loadServiceConfigs();
    await this.refreshData();
  }

  async addFeed(url: string, title: string, groupId: number): Promise<AddFeedResult> {
    const result: AddFeedResult = await this.service.addFeed(url, title, groupId);
    if (result.success) {
      await this.refreshData();
    }
    return result;
  }

  async deleteFeed(feedId: number): Promise<void> {
    await this.service.deleteFeed(feedId);
    if (this.currentNav.type === NavType.FEED && this.currentNav.feedId === feedId) {
      const all: NavigationTarget = new NavigationTarget();
      all.type = NavType.ALL;
      all.title = I18n.get('allArticles');
      this.currentNav = all;
      this.selectedArticleId = -1;
    }
    await this.refreshData();
  }

  async createGroup(name: string): Promise<void> {
    await this.service.createGroup(name);
    await this.refreshData();
  }

  async deleteGroup(groupId: number): Promise<void> {
    await this.service.deleteGroup(groupId);
    await this.refreshData();
  }

  /** Rename a group. */
  async renameGroup(groupId: number, name: string): Promise<void> {
    await this.service.updateGroupName(groupId, name);
    await this.refreshData();
  }

  /**
   * Put a source into a group, or take it out of every group (`groupId = -1`),
   * mirroring the original's group membership editing.
   */
  async assignFeedGroup(feedId: number, groupId: number): Promise<void> {
    await this.service.setFeedGroup(feedId, groupId);
    await this.refreshData();
  }

  /**
   * Expand or collapse a group, mirroring the original's
   * `toggleGroupExpansion` → `saveGroups`.
   *
   * The expanded set is kept here as a replaced array rather than only as
   * `FeedGroup.isExpanded`. `@Observed` did not propagate a mutation of a
   * nested group's field into the sidebar: the arrow and the children only
   * redraw when an observed property of the store itself changes, which is the
   * same reason `moveGroup` reassigns `groups` instead of reordering in place.
   * The group's own flag is kept in step so a reload stays consistent.
   */
  async setGroupExpanded(groupId: number, expanded: boolean): Promise<void> {
    const next: number[] = [];
    for (const id of this.expandedGroupIds) {
      if (id !== groupId) {
        next.push(id);
      }
    }
    if (expanded) {
      next.push(groupId);
    }
    this.expandedGroupIds = next;
    const group: FeedGroup | undefined =
      this.groups.find((g: FeedGroup) => g.id === groupId);
    if (group !== undefined) {
      group.isExpanded = expanded;
    }
    await this.service.setGroupExpanded(groupId, expanded);
  }

  /** Whether a group's children are showing in the sidebar. */
  isGroupExpanded(groupId: number): boolean {
    return this.expandedGroupIds.indexOf(groupId) >= 0;
  }

  /** Re-derive the expanded set from the loaded groups, after a (re)load. */
  private syncExpandedGroups(): void {
    const ids: number[] = [];
    for (const group of this.groups) {
      if (group.isExpanded) {
        ids.push(group.id);
      }
    }
    this.expandedGroupIds = ids;
  }

  /**
   * Move one group to a new position in the sidebar order.
   *
   * The move is applied to the in-memory list first so the UI reflects the drop
   * immediately, then the whole order is written out.
   */
  async moveGroup(fromIndex: number, toIndex: number): Promise<void> {
    const next: FeedGroup[] | null = moveItem(this.groups, fromIndex, toIndex);
    if (next === null) {
      return;
    }
    // Apply in memory first so the drop is reflected immediately, then persist.
    this.groups = next;
    await this.service.setGroupOrder(idsOf(this.groups));
  }

  /** Move one source to a new position within its own scope. */
  async moveFeed(fromIndex: number, toIndex: number): Promise<void> {
    const next: Feed[] | null = moveItem(this.feeds, fromIndex, toIndex);
    if (next === null) {
      return;
    }
    this.feeds = next;
    await this.service.setFeedOrder(idsOf(this.feeds));
  }

  async importOpml(content: string): Promise<ImportSummary> {
    const summary: ImportSummary = await this.service.importOpml(content);
    await this.refreshData();
    return summary;
  }

  async exportOpml(): Promise<string> {
    return this.service.exportOpml();
  }

  /* --------------------------------------------------- backup / restore */

  /** Serialise the whole library — settings, groups, feeds and articles. */
  async exportBackup(): Promise<string> {
    return BackupService.exportAll();
  }

  /**
   * Inspect a backup without applying it, so the user can be shown what a
   * restore would bring in before confirming.
   */
  describeBackup(content: string): BackupOutcome | null {
    return BackupService.describe(content);
  }

  /**
   * Replace the library with a backup. Settings come back too, so everything
   * is reloaded afterwards.
   */
  async restoreBackup(content: string): Promise<BackupOutcome> {
    const outcome: BackupOutcome = await BackupService.importAll(content);
    if (outcome.ok) {
      this.selectedArticleId = -1;
      const all: NavigationTarget = new NavigationTarget();
      all.type = NavType.ALL;
      all.title = I18n.get('allArticles');
      this.currentNav = all;
      await this.loadSettings();
      await this.loadServiceConfigs();
      await this.refreshData();
    }
    return outcome;
  }

  /* ------------------------------------------------------- automation */

  /**
   * Rules stored on a source. They are applied to articles fetched from now
   * on; already-stored articles are unaffected, matching upstream.
   */
  async loadRules(feedId: number): Promise<SourceRule[]> {
    return this.service.getRules(feedId);
  }

  async saveRules(feedId: number, rules: SourceRule[]): Promise<void> {
    await this.service.saveRules(feedId, rules);
    // `rulesJson` lives on the feed row, so refresh the in-memory copies.
    await this.recount();
  }

  /**
   * How many sources currently carry at least one rule, for the sidebar hint.
   */
  rulesCount(): number {
    let count: number = 0;
    for (const feed of this.feeds) {
      if (feed.rulesJson.length > 0) {
        count++;
      }
    }
    return count;
  }

  /**
   * Selected article, or null when nothing is open.
   */
  selectedArticle(): Article | null {
    for (const article of this.articles) {
      if (article.id === this.selectedArticleId) {
        return article;
      }
    }
    return null;
  }

  /**
   * Articles belonging to the current selection; used to render the reader
   * pane without null assertions.
   */
  selectedArticles(): Article[] {
    const result: Article[] = [];
    for (const article of this.articles) {
      if (article.id === this.selectedArticleId) {
        result.push(article);
      }
    }
    return result;
  }
}
