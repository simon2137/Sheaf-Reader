import { window } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { Article, Feed, NavigationTarget, NavType, AddFeedResult, FeedGroup, ImportSummary, ServiceConfigs, SyncResult, SourceRule, SourceOpenTarget, RuleTestResult } from '../model/Models';
import { AppStore } from '../state/AppStore';
import { SidebarView } from '../components/SidebarView';
import { ArticleListView } from '../components/ArticleListView';
import { ArticleReaderView } from '../components/ArticleReaderView';
import { AddFeedDialog } from '../components/AddFeedDialog';
import { SettingsDialog } from '../components/SettingsDialog';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { FeedSettingsDialog } from '../components/FeedSettingsDialog';
import { GroupDialog } from '../components/GroupDialog';
import { GroupSettingsDialog } from '../components/GroupSettingsDialog';
import { ServiceSettingsDialog } from '../components/ServiceSettingsDialog';
import { RulesDialog } from '../components/RulesDialog';
import { LogMenuView } from '../components/LogMenuView';
import { OpmlFileService } from '../utils/OpmlFileService';
import { ImageActions } from '../utils/ImageActions';
import { BrowserLauncher } from '../utils/BrowserLauncher';
import { CacheService } from '../utils/CacheService';
import { TimeBounds } from '../utils/TimeBounds';
import { I18n } from '../utils/I18n';
import { RuleEngine } from '../services/RuleEngine';
import { SearchEngines } from '../utils/SearchEngines';
import { BackupOutcome } from '../services/BackupService';
import { SIDEBAR_WIDTH, SidebarState } from '../utils/SidebarState';
import { Notifier } from '../utils/Notifier';
import { DeepLink } from '../utils/DeepLink';

const LIST_MIN: number = 300;
const LIST_MAX: number = 420;
/** Minimum width the reader pane needs to stay readable. */
const READER_MIN: number = 380;

/**
 * The drawer's transition, from the original's
 * `transition: clip-path 0.367s, opacity 0.367s`.
 */
const DRAWER_DURATION: number = 367;

/**
 * Root page. A three-pane master/detail layout tuned for tablets and 2-in-1 PCs:
 *
 *   [ sidebar ][ article list ][ reader ]
 *
 * Pane widths scale with the window. When the window is too narrow to host all
 * three panes comfortably, the reader replaces the list (master/detail swap)
 * instead of squeezing every column.
 */
@Entry
@Component
struct Index {
  @State store: AppStore = new AppStore();
  @State isReady: boolean = false;
  @State windowWidth: number = 1280;
  @State toast: string = '';
  /**
   * The parked notification deep link, bound to `AppStorage` so that a tap
   * arriving while this page is already alive wakes the watcher immediately.
   * A cold start sets it before the page exists, which is why
   * `openPendingArticle()` also runs from `bootstrap` and `onPageShow`.
   */
  @StorageLink('sheafReaderPendingArticle') @Watch('onPendingArticleChange')
  pendingArticle: string = '';

  private mainWindow: window.Window | null = null;
  private addFeedDialog: CustomDialogController | null = null;
  private settingsDialog: CustomDialogController | null = null;
  private confirmDialog: CustomDialogController | null = null;
  private groupDialog: CustomDialogController | null = null;
  private serviceDialog: CustomDialogController | null = null;
  private rulesDialog: CustomDialogController | null = null;
  private feedSettingsDialog: CustomDialogController | null = null;
  private groupSettingsDialog: CustomDialogController | null = null;
  private refreshTimer: number = -1;
  /** Mirrors the original's `app.settings.display` guard for the fetch timer. */
  private settingsOpen: boolean = false;

  aboutToAppear(): void {
    this.bootstrap();
  }

  /** A notification tap while this page is alive: open the parked article. */
  onPendingArticleChange(): void {
    this.openPendingArticle();
  }

  /** Coming back to the front from a notification tap. */
  onPageShow(): void {
    this.openPendingArticle();
  }

  aboutToDisappear(): void {
    if (this.mainWindow !== null) {
      this.mainWindow.off('windowSizeChange');
      this.mainWindow.off('windowEvent');
    }
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private async bootstrap(): Promise<void> {
    await this.attachWindow();
    await this.store.initialize();
    this.isReady = true;
    // Ask once for notification permission: the original's Electron runtime
    // raises notifications without a prompt, HarmonyOS needs the user's consent
    // and otherwise fails `publish` with 1600004.
    await Notifier.ensureEnabled(this.hostContext());
    // A notification tap that cold-started this ability parks an article id
    // before the page exists, so pick it up now as well as from the watcher.
    this.openPendingArticle();
    // A configured sync service must run even with no local subscriptions yet,
    // since the feeds come from the service. Startup fetches are "background"
    // so rule-requested notifications are raised.
    if (this.store.feeds.length > 0 || this.store.hasService()) {
      this.store.refreshFeeds(true);
    }
    this.startRefreshTimer();
  }

  /**
   * Open the article a notification tap asked for, if any.
   *
   * Both the `@StorageLink` watcher and `onPageShow` land here; `DeepLink`
   * clears the parked value on the first call, so the second one is a no-op.
   */
  private openPendingArticle(): void {
    const articleId: number = DeepLink.consume();
    if (articleId > 0) {
      this.store.openArticleById(articleId);
    }
  }

  /**
   * Periodic background refresh honouring the configured interval.
   *
   * The original arms a one-shot `setTimeout` (`setupAutoFetch`) and re-arms it
   * from the end of `fetchItems`, rather than keeping a repeating interval:
   *
   *   - while the settings panel is open it does **not** fetch, it re-arms with
   *     one minute and tries again (`setupTimeout(1)`), so a panel the user is
   *     editing is never yanked out from under them;
   *   - if a fetch is already running the tick is dropped;
   *   - `interval === 0` disables automatic fetching entirely.
   *
   * `startRefreshTimer` is also called when the interval setting changes, which
   * is the port's equivalent of the original's `dispatch(setupAutoFetch())`
   * after a settings save.
   */
  private startRefreshTimer(): void {
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
    this.armRefreshTimer(this.store.settings.fetchIntervalMinutes);
  }

  /** One-shot arm, mirroring the original's `setupTimeout(interval)`. */
  private armRefreshTimer(minutes: number): void {
    if (minutes <= 0) {
      this.refreshTimer = -1;
      return;
    }
    this.refreshTimer = setTimeout(async () => {
      this.refreshTimer = -1;
      if (this.settingsOpen) {
        this.armRefreshTimer(1);
        return;
      }
      if (!this.store.isFetching) {
        await this.store.refreshFeeds(true);
      }
      // Re-arm for the next run, the way the original does once its fetch
      // settles.
      this.armRefreshTimer(this.store.settings.fetchIntervalMinutes);
    }, minutes * 60 * 1000);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /**
   * Track the host window so the layout can adapt to PC window resizing.
   */
  private async attachWindow(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const host: window.Window = await window.getLastWindow(context);
      this.mainWindow = host;
      this.applySize(host.getWindowProperties().windowRect.width);
      host.on('windowSizeChange', (size: window.Size) => {
        this.applySize(size.width);
      });
      // Notification gating needs to know whether the window is in front, the
      // same signal the original reads through `window.utils.isFocused()`.
      // Measured on the emulator: bringing another window forward delivers
      // WINDOW_INACTIVE (3) and coming back delivers WINDOW_ACTIVE (2). A mere
      // Home press delivers nothing, so a hidden window counts as unfocused;
      // WINDOW_SHOWN (1) is deliberately *not* treated as focus — it arrives
      // between ACTIVE and INACTIVE, and treating it as focus would re-open the
      // gate while the window is on its way out.
      host.on('windowEvent', (event: window.WindowEventType) => {
        if (event === window.WindowEventType.WINDOW_ACTIVE) {
          this.store.windowFocused = true;
        } else if (event === window.WindowEventType.WINDOW_INACTIVE
          || event === window.WindowEventType.WINDOW_HIDDEN) {
          this.store.windowFocused = false;
        }
      });
    } catch (err) {
      // Metrics are best-effort: keep the tablet-class default width.
      const error: BusinessError = err as BusinessError;
      console.warn('Index: window metrics unavailable ' + error.message);
    }
  }

  private applySize(widthPx: number): void {
    const widthVp: number = this.getUIContext().px2vp(widthPx);
    if (widthVp > 0) {
      this.windowWidth = widthVp;
    }
    // The sidebar's breakpoint gate is applied on the first real measurement,
    // which is where the original evaluates `getWindowBreakpoint()`.
    this.store.applySidebarBreakpoint(this.windowWidth);
    // ...but the original re-evaluates `getWindowBreakpoint()` on every later
    // selection (`keepMenu`), so the store needs the live width too.
    this.store.windowWidthVp = this.windowWidth;
  }

  // ---------------------------------------------------------------- geometry

  /**
   * Whether the window is at or above the original's 1440px breakpoint.
   *
   * This decides what the sidebar *is*: at or above the breakpoint the original
   * lays it out as a fixed 280px column, below it the very same panel is an
   * overlay drawer that sits on top of the content and closes when you tap
   * outside it. Both branches render the same `SidebarView`.
   */
  private isWide(): boolean {
    return SidebarState.isWide(this.windowWidth);
  }

  /**
   * Layout width the sidebar claims.
   *
   * Zero in the drawer branch: an overlay must not squeeze the list, which is
   * exactly the difference between the original's fixed container
   * (`width: 280px` at large sizes) and its full-size overlay container
   * (`width: 100%; pointer-events: none` while hidden) below the breakpoint.
   */
  private sidebarWidth(): number {
    return SidebarState.layoutWidth(this.store.sidebarOpen, this.windowWidth);
  }

  private listWidth(): number {
    // With no article open the list owns the whole content area — the same
    // behaviour as the original, and what makes the Cards / Magazine layouts
    // usable (a 300vp column can only fit one card). Once an article is open
    // the list narrows to its column and the reader takes the rest.
    if (this.store.selectedArticleId < 0) {
      const full: number = this.windowWidth - this.sidebarWidth();
      return full > LIST_MIN ? full : LIST_MIN;
    }
    const raw: number = Math.round(this.windowWidth * 0.28);
    return Math.min(Math.max(raw, LIST_MIN), LIST_MAX);
  }

  private fitsThreePanes(): boolean {
    return this.windowWidth >= this.sidebarWidth() + LIST_MIN + READER_MIN;
  }

  /**
   * Narrow windows host the list and the reader one at a time. Both panes must
   * be gated by the same predicate: rendering the reader unconditionally
   * squeezes it into a sliver next to the list instead of replacing it.
   */
  private showListPane(): boolean {
    return this.fitsThreePanes() || this.store.selectedArticleId < 0;
  }

  /**
   * The reader only appears once something is selected; the placeholder was
   * wasting the whole right side on large screens.
   */
  private showReaderPane(): boolean {
    return this.store.selectedArticleId >= 0;
  }

  // ----------------------------------------------------------------- palette

  private pageBg(): string {
    return this.store.isDarkMode ? '#1B1A19' : '#FAFAFA';
  }

  private surfaceBg(): string {
    return this.store.isDarkMode ? '#252423' : '#FFFFFF';
  }

  private dividerColor(): string {
    return this.store.isDarkMode ? '#3B3A39' : '#EDEBE9';
  }

  private textColor(): string {
    return this.store.isDarkMode ? '#FFFFFF' : '#323130';
  }

  private secondaryColor(): string {
    return this.store.isDarkMode ? '#C8C6C4' : '#605E5C';
  }

  // --------------------------------------------------------------- behaviours

  private showToast(message: string): void {
    this.toast = message;
    setTimeout(() => {
      this.toast = '';
    }, 2600);
  }

  /** Open an article in the system browser, reporting either failure. */
  private openExternal(article: Article): void {
    if (article.link.length === 0) {
      this.showToast(I18n.get('app.noLink'));
      return;
    }
    const link: string = article.link;
    BrowserLauncher.open(this.hostContext(), link).then((opened: boolean) => {
      if (!opened) {
        this.showToast(I18n.get('app.noBrowser') + ': ' + link);
      }
    });
  }

  /**
   * Open the configured search engine for a snippet the user selected in the
   * article body, mirroring the original's selected-text search.
   */
  private openSearch(text: string): void {
    const url: string = SearchEngines.urlFor(this.store.settings.searchEngine, text);
    BrowserLauncher.open(this.hostContext(), url).then((opened: boolean) => {
      if (!opened) {
        this.showToast(I18n.get('app.noBrowser') + ': ' + url);
      }
    });
  }

  /** Put an article's link on the system clipboard. */
  private copyLink(article: Article): void {
    if (article.link.length === 0) {
      this.showToast(I18n.get('app.noLink'));
      return;
    }
    this.copyText(article.link, 'context.copyURL');
  }

  /** Put the article's title on the system clipboard. */
  private copyTitle(article: Article): void {
    if (article.title.length === 0) {
      this.showToast(I18n.get('article.untitled'));
      return;
    }
    this.copyText(article.title, 'context.copyTitle');
  }

  /** Put the article's cover image link on the system clipboard. */
  private copyImageLink(article: Article): void {
    if (article.imageUrl.length === 0) {
      this.showToast(I18n.get('app.noImage'));
      return;
    }
    this.copyText(article.imageUrl, 'app.imageLinkCopied');
  }

  private copyText(value: string, successKey: string): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.showToast(I18n.get(successKey));
    }).catch(() => {
      this.showToast(I18n.get('app.copyFailed'));
    });
  }

  /** "Save image as …": download the cover image and pick a destination. */
  private async saveImage(article: Article): Promise<void> {
    const failure: string =
      await ImageActions.saveImage(this.hostContext(), article.imageUrl);
    this.showToast(I18n.get(failure.length > 0 ? failure : 'app.imageSaved'));
  }

  /** "Copy image": decode the cover image and put the pixels on the clipboard. */
  private async copyImage(article: Article): Promise<void> {
    const failure: string = await ImageActions.copyImage(article.imageUrl);
    this.showToast(I18n.get(failure.length > 0 ? failure : 'app.imageCopied'));
  }

  /**
   * "Load full content": fetch the page and keep only its article body.
   *
   * Toggles, as the original's does: choosing it again drops the fetched page and
   * restores the feed's own text. The stored article is never rewritten.
   */
  private async loadFull(article: Article): Promise<void> {
    if (this.store.loadedModeFor(article.id) === 1) {
      this.store.clearLoadedPage(article.id);
      return;
    }
    const failure: string = await this.store.loadFullContent(article.id);
    if (failure.length > 0) {
      this.showToast(I18n.get(failure));
    }
  }

  /**
   * "Load webpage": keep the page as fetched, without extracting a body.
   * Toggles the same way `loadFull` does.
   */
  private async loadWebpage(article: Article): Promise<void> {
    if (this.store.loadedModeFor(article.id) === 0) {
      this.store.clearLoadedPage(article.id);
      return;
    }
    const failure: string = await this.store.loadSourcePage(article.id, false);
    if (failure.length > 0) {
      this.showToast(I18n.get(failure));
    }
  }

  /**
   * Open an article the way its source asks to be opened
   * (`sources.openTarget`): the in-app reader, the reader with the source page
   * loaded verbatim, the reader with the extracted body, or the system browser.
   */
  private async openArticle(articleId: number): Promise<void> {
    const target: number = this.store.openTargetFor(articleId);
    if (target === SourceOpenTarget.External) {
      const external: Article | undefined = this.store.articleById(articleId);
      if (external !== undefined) {
        this.openExternal(external);
      }
      return;
    }

    await this.store.selectArticle(articleId);

    const article: Article | undefined = this.store.articleById(articleId);
    if (article === undefined) {
      return;
    }
    if (target === SourceOpenTarget.FullContent) {
      await this.loadFull(article);
    } else if (target === SourceOpenTarget.Webpage) {
      await this.loadWebpage(article);
    }
  }

  private openAddFeed(): void {
    this.addFeedDialog = new CustomDialogController({
      builder: AddFeedDialog({
        isDarkMode: this.store.isDarkMode,
        groups: this.store.groups,
        onConfirm: async (url: string, name: string, groupId: number): Promise<AddFeedResult> => {
          const result: AddFeedResult = await this.store.addFeed(url, name, groupId);
          if (result.success) {
            const label: string = result.feed !== null ? result.feed.title : name;
            this.showToast(I18n.get('app.subscribedTo',
              new Map<string, string | number>([['name', label]])));
          }
          return result;
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.addFeedDialog.open();
  }

  private openSettings(): void {
    this.settingsDialog = new CustomDialogController({
      builder: SettingsDialog({
        isDarkMode: this.store.isDarkMode,
        darkMode: this.store.settings.darkMode,
        locale: this.store.locale,
        onClose: () => {
          this.settingsOpen = false;
        },
        onLocaleChange: async (locale: string) => {
          await this.store.setLocale(locale, this.hostContext());
          // A `CustomDialog` captures its builder when the controller is built,
          // so the panel that is open right now still holds the previous
          // catalogue: every label in it would stay in the old language until
          // the user closed and reopened it. Rebuild it instead, which is what
          // the original gets for free from React re-rendering the tree.
          const open: CustomDialogController | null = this.settingsDialog;
          if (open !== null) {
            open.close();
          }
          this.openSettings();
        },
        fontSize: this.store.settings.fontSize,
        showThumbnails: this.store.settings.showThumbnails,
        openInBuiltInView: this.store.settings.openInBuiltInView,
        fetchInterval: this.store.settings.fetchIntervalMinutes,
        feedCount: this.store.feeds.length,
        articleCount: this.store.articles.length,
        onDarkModeChange: (mode: number) => {
          this.store.setDarkMode(mode);
        },
        onFontSizeChange: (size: number) => {
          this.store.setFontSize(size);
        },
        onShowThumbnailsChange: (value: boolean) => {
          this.store.setShowThumbnails(value);
        },
        onOpenInBuiltInViewChange: (value: boolean) => {
          this.store.setOpenInBuiltInView(value);
        },
        onFetchIntervalChange: (minutes: number) => {
          this.store.setFetchInterval(minutes);
          this.startRefreshTimer();
        },
        searchEngine: this.store.settings.searchEngine,
        onSearchEngineChange: (engine: number) => {
          this.store.setSearchEngine(engine);
        },
        onImportOpml: async () => {
          await this.importOpml();
        },
        onExportOpml: async () => {
          await this.exportOpml();
        },
        onBackup: async () => {
          await this.exportBackup();
        },
        onRestore: async () => {
          await this.pickBackup();
        },
        onMeasureArticles: async () => {
          return await this.store.articleStorageBytes();
        },
        // The original reports the outcome by refreshing the size hint rather
        // than by raising a message, so no toast is raised here either.
        onDeleteArticles: async (days: number) => {
          await this.store.deleteOldArticles(days);
        },
        onMeasureCache: async () => {
          return await CacheService.size(this.hostContext());
        },
        onClearCache: async () => {
          await CacheService.clear(this.hostContext());
          this.showToast(I18n.get('app.cacheCleared'));
        }
      }),
      autoCancel: true,
      // `onDidDisappear` is API 19 and this project builds against 12, so the
      // mask/back dismissal is caught with `cancel` instead; the programmatic
      // path clears the flag in `closeSettings`.
      cancel: () => {
        this.settingsOpen = false;
      },
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.settingsDialog.open();
    this.settingsOpen = true;
  }

  // ------------------------------------------------------------ OPML support

  private async importOpml(): Promise<void> {
    const content: string | null = await OpmlFileService.pickAndRead(this.hostContext());
    if (content === null) {
      return;
    }
    this.showToast(I18n.get('app.importingFeeds'));
    const summary: ImportSummary = await this.store.importOpml(content);
    this.showToast(I18n.get('app.importedFeeds',
      new Map<string, string | number>([
        ['feeds', summary.success], ['failed', summary.failed]
      ])));
  }

  private async exportOpml(): Promise<void> {
    if (this.store.feeds.length === 0) {
      this.showToast(I18n.get('app.nothingToExport'));
      return;
    }
    const opml: string = await this.store.exportOpml();
    const uri: string | null = await OpmlFileService.pickAndWrite(this.hostContext(), opml);
    if (uri !== null) {
      this.showToast(I18n.get('app.exportedFeeds',
        new Map<string, string | number>([['count', this.store.feeds.length]])));
    }
  }

  // ------------------------------------------------- backup / restore

  /**
   * Write a full backup. The settings sheet is dismissed first so the system
   * file picker is not stacked on top of a modal dialog.
   */
  private async exportBackup(): Promise<void> {
    this.closeSettings();
    const content: string = await this.store.exportBackup();
    const uri: string | null = await OpmlFileService.pickAndWriteAny(
      this.hostContext(), content, 'Sheaf_Reader_Backup.frdata');
    if (uri !== null) {
      this.showToast(I18n.get('app.backupSaved'));
    }
  }

  /**
   * Choose a backup and, after showing what it contains, restore it. Restore
   * is destructive, so it always goes through a confirmation.
   */
  private async pickBackup(): Promise<void> {
    this.closeSettings();
    const content: string | null = await OpmlFileService.pickAndReadAny(
      this.hostContext(), ['.frdata', '.json']);
    if (content === null) {
      return;
    }
    const preview: BackupOutcome | null = this.store.describeBackup(content);
    if (preview === null) {
      this.showToast(I18n.get('app.backupInvalid'));
      return;
    }
    this.confirmRestore(preview, content);
  }

  private confirmRestore(preview: BackupOutcome, content: string): void {
    this.confirmDialog = new CustomDialogController({
      builder: ConfirmDialog({
        isDarkMode: this.store.isDarkMode,
        title: I18n.get('app.restore'),
        message: I18n.get('app.confirmImport') + '\n\n'
          + I18n.get('app.backupSummary',
            new Map<string, string | number>([
              ['feeds', preview.feeds], ['articles', preview.articles]
            ])),
        confirmLabel: I18n.get('app.restore'),
        destructive: true,
        onConfirm: async () => {
          const outcome: BackupOutcome = await this.store.restoreBackup(content);
          if (outcome.ok) {
            // The backup carries the language setting, so re-apply it.
            await I18n.init(this.hostContext(), this.store.locale);
            this.showToast(I18n.get('app.backupRestored',
              new Map<string, string | number>([
                ['feeds', outcome.feeds], ['articles', outcome.articles]
              ])));
          } else {
            this.showToast(I18n.get('app.backupInvalid'));
          }
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.confirmDialog.open();
  }

  private closeSettings(): void {
    if (this.settingsDialog !== null) {
      this.settingsDialog.close();
    }
    this.settingsOpen = false;
  }

  // ------------------------------------------------------------ automation

  private openRules(): void {
    if (this.store.feeds.length === 0) {
      this.showToast(I18n.get('app.rulesNeedSource'));
      return;
    }
    /*
     * Start on whichever source is selected — but when the user is on "All
     * articles" or a group there is no source to start on, so the panel opens
     * with none chosen and its dropdown shows the `rules.selectSource`
     * placeholder. Falling back to the first source used to silently edit that
     * feed's rules.
     */
    const initial: number = this.store.currentNav.feedId;

    this.rulesDialog = new CustomDialogController({
      builder: RulesDialog({
        isDarkMode: this.store.isDarkMode,
        feeds: this.store.feeds,
        initialFeedId: initial,
        onLoadRules: async (feedId: number): Promise<SourceRule[]> => {
          return this.store.loadRules(feedId);
        },
        onSaveRules: async (feedId: number, rules: SourceRule[]) => {
          await this.store.saveRules(feedId, rules);
        },
        onTestRule: async (rule: SourceRule): Promise<RuleTestResult> => {
          const loaded: Article[] = this.store.articles;
          return {
            matched: RuleEngine.countMatches(rule, loaded),
            total: loaded.length
          };
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.rulesDialog.open();
  }

  // ------------------------------------------------------------ sync service

  private openServiceSettings(): void {
    this.serviceDialog = new CustomDialogController({
      builder: ServiceSettingsDialog({
        isDarkMode: this.store.isDarkMode,
        initialConfigs: this.store.serviceConfigs,
        feedCount: this.store.feeds.length,
        linkedCount: this.store.serviceLinkedCount,
        onTest: async (configs: ServiceConfigs): Promise<boolean> => {
          return this.store.testService(configs);
        },
        onOpenUrl: (url: string) => {
          // Same reporting as the article/selection paths: the emulator has no
          // browser, so the toast is where the URL becomes verifiable.
          BrowserLauncher.open(this.hostContext(), url).then((opened: boolean) => {
            if (!opened) {
              this.showToast(I18n.get('app.noBrowser') + ': ' + url);
            }
          });
        },
        onSave: async (configs: ServiceConfigs) => {
          await this.store.saveServiceConfigs(configs);
        },
        onSyncNow: async (configs: ServiceConfigs) => {
          this.showToast(I18n.get('app.syncingService'));
          // Persist first so the sync reads the configuration just entered.
          await this.store.saveServiceConfigs(configs);
          const result: SyncResult = await this.store.syncWithService();
          this.showToast(result.ok
            ? I18n.get('app.syncComplete', new Map<string, string | number>([
              ['items', result.itemsFetched], ['updates', result.localUpdates]
            ]))
            : result.message);
        },
        onRemove: async () => {
          await this.store.removeSyncService();
          this.showToast(I18n.get('app.serviceRemoved'));
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.serviceDialog.open();
  }

  // --------------------------------------------------------- group management

  private openCreateGroup(): void {
    const names: string[] = [];
    for (const group of this.store.groups) {
      names.push(group.name);
    }
    this.groupDialog = new CustomDialogController({
      builder: GroupDialog({
        isDarkMode: this.store.isDarkMode,
        existingNames: names,
        onCreate: async (name: string) => {
          await this.store.createGroup(name);
          this.showToast(I18n.get('app.groupCreated',
            new Map<string, string | number>([['name', name]])));
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.groupDialog.open();
  }

  /**
   * Group names in store order. The source panel's group dropdown is indexed
   * by position, so index `i` must map back to `groups[i].id`.
   */
  private groupNames(): string[] {
    const names: string[] = [];
    for (const group of this.store.groups) {
      names.push(group.name);
    }
    return names;
  }

  /** Position of `groupId` in the store's group list, or `-1`. */
  private groupIndexOf(groupId: number): number {
    for (let i = 0; i < this.store.groups.length; i++) {
      if (this.store.groups[i].id === groupId) {
        return i;
      }
    }
    return -1;
  }

  /**
   * Per-source settings: name, fetch frequency limit, default open target,
   * text direction, "hide in all articles", group membership and deletion.
   */
  private openFeedSettings(feedId: number): void {
    const feed: Feed | null = this.store.feeds.find((f: Feed) => f.id === feedId) ?? null;
    if (feed === null) {
      return;
    }
    this.feedSettingsDialog = new CustomDialogController({
      builder: FeedSettingsDialog({
        initialTitle: feed.title,
        initialFetchFrequency: feed.fetchFrequency,
        initialOpenTarget: feed.openTarget,
        initialTextDir: feed.textDir,
        initialHidden: feed.hidden,
        serviceManaged: feed.isServiceManaged(),
        isDarkMode: this.store.isDarkMode,
        groupNames: this.groupNames(),
        initialGroupIndex: this.groupIndexOf(feed.groupId),
        onAssignGroup: async (index: number) => {
          const targetId: number = index >= 0 && index < this.store.groups.length
            ? this.store.groups[index].id : -1;
          await this.store.assignFeedGroup(feedId, targetId);
          this.showToast(I18n.get('app.feedSettingsSaved'));
        },
        onSave: async (name: string, frequency: number, openTarget: number,
          textDir: number, hidden: boolean) => {
          await this.store.saveFeedSettings(feedId, name, frequency,
            openTarget, textDir, hidden);
          this.showToast(I18n.get('app.feedSettingsSaved'));
        },
        onDelete: async () => {
          await this.store.deleteFeed(feedId);
          this.showToast(I18n.get('app.subscriptionRemoved'));
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.feedSettingsDialog.open();
  }

  /**
   * Per-group settings: rename and delete. Deletion lives in the panel behind
   * its own two-step confirmation, which is where deletion of a source lives
   * too, so both are reached the same way.
   */
  /**
   * The feeds that live in one group, in sidebar order. Used by the group
   * settings panel's membership list.
   */
  private feedsOfGroup(groupId: number): Feed[] {
    const result: Feed[] = [];
    for (const feed of this.store.feeds) {
      if (feed.groupId === groupId) {
        result.push(feed);
      }
    }
    return result;
  }

  private openGroupSettings(groupId: number): void {
    const group: FeedGroup | null =
      this.store.groups.find((g: FeedGroup) => g.id === groupId) ?? null;
    if (group === null) {
      return;
    }
    const others: string[] = [];
    for (const existing of this.store.groups) {
      if (existing.id !== groupId) {
        others.push(existing.name);
      }
    }
    // Membership, mirroring the original's manage-group screen: the group's own
    // sources, each removable. Adding a source is the *source* panel's job
    // (`groups.addToGroup` / `groups.chooseGroup`), exactly as upstream splits it.
    const members: Feed[] = this.feedsOfGroup(groupId);
    this.groupSettingsDialog = new CustomDialogController({
      builder: GroupSettingsDialog({
        initialName: group.name,
        existingNames: others,
        groupId: groupId,
        members: members,
        isDarkMode: this.store.isDarkMode,
        onAssign: async (feedId: number, targetGroupId: number) => {
          await this.store.assignFeedGroup(feedId, targetGroupId);
        },
        onSave: async (name: string) => {
          await this.store.renameGroup(groupId, name);
          this.showToast(I18n.get('app.groupRenamed',
            new Map<string, string | number>([['name', name]])));
        },
        onDelete: async () => {
          await this.store.deleteGroup(groupId);
          this.showToast(I18n.get('app.groupDeleted'));
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.groupSettingsDialog.open();
  }

  /**
   * Position of a group in the store's order. Drag-and-drop reports the two
   * ids involved, and the store moves by index.
   */
  private indexOfGroup(groupId: number): number {
    for (let i = 0; i < this.store.groups.length; i++) {
      if (this.store.groups[i].id === groupId) {
        return i;
      }
    }
    return -1;
  }

  private indexOfFeed(feedId: number): number {
    for (let i = 0; i < this.store.feeds.length; i++) {
      if (this.store.feeds[i].id === feedId) {
        return i;
      }
    }
    return -1;
  }

  // ------------------------------------------------------------------- build

  /**
   * The navigation pane, rendered either as the fixed column (wide windows) or
   * as the drawer panel (narrow ones). One builder so both branches cannot
   * drift apart.
   */
  @Builder
  private SidebarPane() {
    SidebarView({
      store: this.store,
      onNavigate: (target: NavigationTarget) => {
        this.store.navigateTo(target);
      },
      onAddFeed: () => {
        this.openAddFeed();
      },
      onShowSettings: () => {
        this.openSettings();
      },
      onRefresh: async () => {
        await this.store.refreshFeeds();
      },
      onFeedSettings: (feedId: number) => {
        this.openFeedSettings(feedId);
      },
      onAddGroup: () => {
        this.openCreateGroup();
      },
      onGroupSettings: (groupId: number) => {
        this.openGroupSettings(groupId);
      },
      onGroupMove: async (fromId: number, toId: number) => {
        await this.store.moveGroup(this.indexOfGroup(fromId), this.indexOfGroup(toId));
      },
      onFeedMove: async (fromId: number, toId: number) => {
        await this.store.moveFeed(this.indexOfFeed(fromId), this.indexOfFeed(toId));
      },
      /*
       * Group menu (`GroupContextMenu`): mark a scope read, or refresh
       * just that scope. Exactly one of groupId / feedId is set.
       */
      onScopeMarkRead: async (groupId: number, feedId: number) => {
        await this.store.markAllReadFor(feedId, groupId, 0, true);
        this.showToast(I18n.get('app.allMarkedRead'));
      },
      onScopeRefresh: async (groupId: number, feedId: number) => {
        await this.store.refreshScope(feedId, groupId);
      },
      onToggleUnreadOnly: async () => {
        await this.store.setUnreadSourcesOnly(!this.store.unreadSourcesOnly);
      },
      onToggleSearch: () => {
        this.store.toggleSearch();
      },
      onShowService: () => {
        this.openServiceSettings();
      },
      onShowRules: () => {
        this.openRules();
      },
      onShowLogs: () => {
        this.store.toggleLogMenu();
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (!this.isReady) {
        this.LoadingScreen()
      } else {
        Row() {
          // ---- Pane 1: navigation, as a column only on wide windows ----
          if (this.store.sidebarOpen && this.isWide()) {
            Column() {
              this.SidebarPane()
            }
            .width(this.sidebarWidth())
            .height('100%')
          }

          // The separator belongs to the sidebar: without it a hidden sidebar
          // would leave a 1vp line down the left edge of the content area.
          if (this.store.sidebarOpen && this.isWide()) {
            Divider()
              .vertical(true)
              .color(this.dividerColor())
              .strokeWidth(1)
          }

          // ---- Pane 2: article list ----
          if (this.showListPane()) {
            Column() {
              ArticleListView({
                store: this.store,
                paneWidth: this.listWidth(),
                onArticleSelect: async (articleId: number) => {
                  await this.openArticle(articleId);
                },
                onStarToggle: async (articleId: number) => {
                  await this.store.toggleStar(articleId);
                },
                onSearch: async (query: string) => {
                  await this.store.search(query);
                },
                onMarkAllRead: async () => {
                  await this.store.markAllRead();
                  this.showToast(I18n.get('app.allMarkedRead'));
                },
                /*
                 * The sidebar toggle. The original puts the hamburger in its nav
                 * bar; this port has no separate nav bar, so the control lives
                 * at the left of the list header, where it stays reachable while
                 * the sidebar is hidden.
                 */
                onToggleSidebar: async () => {
                  await this.store.toggleSidebar();
                },
                onRefresh: async () => {
                  await this.store.refreshFeeds();
                },
                /*
                 * The day-bounded variants go through the same store scope the
                 * plain action uses, but with the current navigation's feed /
                 * group and a "published on or before this date" bound.
                 */
                onMarkAllReadSince: async (days: number) => {
                  const nav: NavigationTarget = this.store.currentNav;
                  await this.store.markAllReadFor(
                    nav.type === NavType.FEED ? nav.feedId : -1,
                    nav.type === NavType.GROUP ? nav.groupId : -1,
                    TimeBounds.daysAgo(days, Date.now()), true);
                  this.showToast(I18n.get('app.allMarkedRead'));
                },
                onOpenExternal: (article: Article) => {
                  this.openExternal(article);
                },
                onCopyLink: (article: Article) => {
                  this.copyLink(article);
                },
                onCopyTitle: (article: Article) => {
                  this.copyTitle(article);
                },
                onLoadFull: async (article: Article) => {
                  await this.loadFull(article);
                },
                onImageSave: async (article: Article) => {
                  await this.saveImage(article);
                },
                onImageCopy: async (article: Article) => {
                  await this.copyImage(article);
                },
                onImageCopyLink: (article: Article) => {
                  this.copyImageLink(article);
                }
              })
            }
            .width(this.listWidth())
            .height('100%')

            Divider()
              .vertical(true)
              .color(this.dividerColor())
              .strokeWidth(1)
          }

          // ---- Pane 3: reader ----
          if (this.showReaderPane()) {
            Column() {
              if (this.store.selectedArticleId >= 0) {
                ForEach(this.store.selectedArticles(), (article: Article) => {
                  ArticleReaderView({
                    article: article,
                    isDarkMode: this.store.isDarkMode,
                    fontSize: this.store.settings.fontSize,
                    viewBody: this.store.loadedBodyFor(article.id),
                    lineHeight: this.store.settings.lineHeight,
                    textDir: this.store.textDirFor(article.feedId),
                    searchEngine: this.store.settings.searchEngine,
                    onSearchText: (text: string) => {
                      this.openSearch(text);
                    },
                    onStarToggle: async () => {
                      await this.store.toggleStar(article.id);
                    },
                    onReadToggle: async () => {
                      await this.store.toggleRead(article.id);
                    },
                    onOpenExternal: () => {
                      this.openExternal(article);
                    },
                    isLoadingFull: this.store.isLoadingFullContent,
                    onLoadFull: async () => {
                      await this.loadFull(article);
                    },
                    onClose: () => {
                      this.store.selectedArticleId = -1;
                    }
                  })
                }, (article: Article) => 'reader-' + article.id.toString()
                  + '-' + this.store.settings.fontSize.toString()
                  + '-' + this.store.settings.lineHeight.toString()
                  + '-' + this.store.textDirFor(article.feedId).toString()
                  + '-' + this.store.settings.searchEngine.toString()
                  + '-' + (this.store.isDarkMode ? '1' : '0'))
              } else {
                this.ReaderPlaceholder()
              }
            }
            .layoutWeight(1)
            .height('100%')
          }
        }
        .width('100%')
        .height('100%')

        /*
         * ---- Pane 1 as a drawer, below the 1440vp breakpoint ----
         *
         * The original keeps the same panel mounted and animates it in with
         * `clip-path` + `opacity` over 367ms, inside a full-size container that
         * is `pointer-events: none` until the menu is shown. Two consequences
         * this reproduces:
         *   - the list underneath is never squeezed (the container claims no
         *     layout width), and
         *   - a tap anywhere outside the panel closes it.
         * There is deliberately no dimming scrim: the original's container has
         * no background, only the panel carries `box-shadow: 5px 0 25px #0004`.
         */
        if (!this.isWide()) {
          /*
           * The overlay lives in its own full-size Stack. The page's root Stack
           * uses `alignContent: Alignment.Top`, i.e. it centres any child that
           * does not fill it, which would have parked the 280vp panel in the
           * middle of the window — a bug this nesting exists to prevent.
           * (`.align()` is not the fix: it aligns a component's own content.)
           *
           * `hitTestBehavior` has to be set on the **catcher itself**, not only
           * on the wrapper. Round 27 moved the gate up to the wrapper on the
           * assumption that `HitTestMode.None` disables a subtree; measured on
           * device it does not — a child that declares `HitTestMode.Default`
           * still participates, so with the drawer closed this full-size
           * transparent catch-all stayed the top-most hit target and swallowed
           * **every** tap on the page (only the keyboard remained usable).
           * The hit-test stack at (1568,282) and (500,434) ended on this node.
           */
          Stack({ alignContent: Alignment.TopStart }) {
            // Click-catcher: the original's container is `width: 100%` with an
            // `onClick={toggleMenu}`, so a tap anywhere outside the panel
            // dismisses the drawer.
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Transparent)
              .hitTestBehavior(this.store.sidebarOpen
                ? HitTestMode.Default : HitTestMode.None)
              .onClick(() => {
                // The original's overlay container calls `toggleMenu`, which
                // persists the choice through `setDefaultMenu`.
                this.store.toggleSidebar();
              })

            Column() {
              this.SidebarPane()
            }
            .width(SIDEBAR_WIDTH)
            .height('100%')
            .backgroundColor(this.store.isDarkMode ? '#F21F1F1F' : '#F2F3F2F1')
            .shadow({ radius: 25, color: '#00000044', offsetX: 5, offsetY: 0 })
            .translate({ x: this.store.sidebarOpen ? 0 : -SIDEBAR_WIDTH })
            .opacity(this.store.sidebarOpen ? 1 : 0)
            .animation({ duration: DRAWER_DURATION, curve: Curve.FastOutSlowIn })
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(this.store.sidebarOpen
            ? HitTestMode.Default : HitTestMode.None)
        }

        /*
         * ---- Fetch progress, pinned to the top of the window ----
         *
         * The original's `<ProgressBar className={classes.progress}>` is
         * `position: fixed; top: 0; left: 0; width: 100%; z-index: 10` with
         * `background: none`, shown whenever `isFetching`, and its value is
         * `fetchingProgress / fetchingTotal`.
         *
         * Two deliberate differences, both forced by ArkUI:
         *   - `ProgressOptions.value` is **required** at this API level, so an
         *     indeterminate *bar* cannot be expressed. The per-source phase is
         *     therefore drawn as a real ratio, and the phases with no total yet
         *     (the service sync) are covered by the header's existing
         *     `LoadingProgress` spinner — ArkUI's indeterminate indicator.
         *   - Being a later child of the root Stack, it also renders above the
         *     drawer, which matches upstream's z-index 10 over the menu's 5.
         */
        if (this.store.isFetching && this.store.fetchTotal > 0) {
          Progress({
            value: this.store.fetchDone,
            total: this.store.fetchTotal,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(3)
            .color('#0078D4')
            .backgroundColor(Color.Transparent)
        }
      }

      if (this.store.logMenuDisplay) {
        Stack({ alignContent: Alignment.BottomStart }) {
          // Backdrop: a tap outside dismisses the panel, matching the
          // original Callout's `onDismiss`.
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.store.isDarkMode ? '#33000000' : '#14000000')
            .onClick(() => {
              this.store.closeLogMenu();
            })

          LogMenuView({
            store: this.store,
            onClose: () => {
              this.store.closeLogMenu();
            },
            onOpenArticle: async (articleId: number) => {
              this.store.closeLogMenu();
              await this.store.openArticleById(articleId);
            }
          })
            .margin({ left: this.sidebarWidth() + 12, bottom: 16 })
        }
        .width('100%')
        .height('100%')
      }

      if (this.toast.length > 0) {
        Row() {
          Text(this.toast)
            .fontSize(13)
            .fontColor(Color.White)
            .maxLines(2)
        }
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .backgroundColor('#323130')
        .borderRadius(6)
        .margin({ top: 18 })
        .constraintSize({ maxWidth: 520 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
    // Desktop shortcuts, mirroring the original's global key handler. The
    // events bubble up from whichever pane holds focus.
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent): boolean => {
      return this.handleShortcut(event);
    })
  }

  /**
   * The original's desktop shortcut set.
   *
   * `j`/`k` and the arrow keys move through the list; `m` toggles read, `s`
   * toggles star, `b` marks read and hands the link to the browser, `h` hides
   * (marking read first, as the original does), `l` loads the source page
   * verbatim and `w` loads the extracted body; `/` and F2 jump to search,
   * `r`/F5 refreshes, F1 toggles the sidebar, F6 marks everything read, F7
   * opens the notifications panel, F9 opens settings, and Escape leaves the
   * reader.
   *
   * One of the original's keys has no surface here and is deliberately absent:
   * F8 opens the view menu, which is a `bindMenu` and cannot be opened
   * programmatically.
   */
  private handleShortcut(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    const code: number = event.keyCode;

    if (code === KeyCode.KEYCODE_J || code === KeyCode.KEYCODE_DPAD_DOWN
      || code === KeyCode.KEYCODE_DPAD_RIGHT) {
      this.moveSelection(1);
      return true;
    }
    if (code === KeyCode.KEYCODE_K || code === KeyCode.KEYCODE_DPAD_UP
      || code === KeyCode.KEYCODE_DPAD_LEFT) {
      this.moveSelection(-1);
      return true;
    }
    if (code === KeyCode.KEYCODE_M) {
      const articleId: number = this.store.selectedArticleId;
      if (articleId >= 0) {
        this.store.toggleRead(articleId);
      }
      return true;
    }
    if (code === KeyCode.KEYCODE_S) {
      const articleId: number = this.store.selectedArticleId;
      if (articleId >= 0) {
        this.store.toggleStar(articleId);
      }
      return true;
    }
    if (code === KeyCode.KEYCODE_B) {
      // Open externally, marking read on the way, matching `itemShortcuts`.
      const article: Article | undefined = this.selectedArticle();
      if (article !== undefined) {
        if (!article.read) {
          this.store.toggleRead(article.id);
        }
        this.openExternal(article);
      }
      return true;
    }
    if (code === KeyCode.KEYCODE_H) {
      const article: Article | undefined = this.selectedArticle();
      if (article !== undefined) {
        if (!article.read && !article.hidden) {
          this.store.toggleRead(article.id);
        }
        this.store.toggleHidden(article.id);
      }
      return true;
    }
    if (code === KeyCode.KEYCODE_L) {
      const article: Article | undefined = this.selectedArticle();
      if (article !== undefined) {
        this.loadWebpage(article);
      }
      return true;
    }
    if (code === KeyCode.KEYCODE_W) {
      const article: Article | undefined = this.selectedArticle();
      if (article !== undefined) {
        this.loadFull(article);
      }
      return true;
    }
    if (code === KeyCode.KEYCODE_R || code === KeyCode.KEYCODE_F5) {
      this.store.refreshFeeds();
      return true;
    }
    if (code === KeyCode.KEYCODE_SLASH || code === KeyCode.KEYCODE_F2) {
      // The bar only exists while `searchOn`, so reveal it first — otherwise
      // the original's Ctrl+F equivalent would focus nothing.
      if (!this.store.searchOn) {
        this.store.searchOn = true;
      }
      focusControl.requestFocus('articleSearch');
      return true;
    }
    if (code === KeyCode.KEYCODE_F1) {
      this.store.toggleSidebar();
      return true;
    }
    if (code === KeyCode.KEYCODE_F6) {
      this.store.markAllRead();
      this.showToast(I18n.get('app.allMarkedRead'));
      return true;
    }
    if (code === KeyCode.KEYCODE_F7) {
      this.store.toggleLogMenu();
      return true;
    }
    if (code === KeyCode.KEYCODE_F9) {
      this.openSettings();
      return true;
    }
    if (code === KeyCode.KEYCODE_ESCAPE) {
      this.store.selectedArticleId = -1;
      return true;
    }
    return false;
  }

  /** The article the shortcuts act on, or undefined when nothing is selected. */
  private selectedArticle(): Article | undefined {
    return this.store.articleById(this.store.selectedArticleId);
  }

  /** Move the selection by one entry, clamped to the loaded window. */
  private moveSelection(delta: number): void {
    const list: Article[] = this.store.articles;
    if (list.length === 0) {
      return;
    }
    const current: number =
      list.findIndex((a: Article) => a.id === this.store.selectedArticleId);
    let next: number = current < 0 ? (delta > 0 ? 0 : list.length - 1) : current + delta;
    if (next < 0) {
      next = 0;
    }
    if (next > list.length - 1) {
      next = list.length - 1;
    }
    this.store.selectArticle(list[next].id);
  }

  @Builder
  LoadingScreen() {
    Column() {
      Image($r('app.media.ic_rss'))
        .width(56)
        .height(56)
        .fillColor('#0078D4')
      Text(I18n.get('app.name'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textColor())
        .margin({ top: 16 })
      Text(I18n.get('app.loading'))
        .fontSize(13)
        .fontColor(this.secondaryColor())
        .margin({ top: 6 })
      LoadingProgress()
        .width(28)
        .height(28)
        .color('#0078D4')
        .margin({ top: 18 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ReaderPlaceholder() {
    Column() {
      Image($r('app.media.ic_mail'))
        .width(56)
        .height(56)
        .fillColor(this.secondaryColor())
        .opacity(0.4)
      Text(I18n.get('app.nothingSelected'))
        .fontSize(16)
        .fontColor(this.secondaryColor())
        .margin({ top: 14 })
      Text(I18n.get('app.pickArticle'))
        .fontSize(13)
        .fontColor(this.secondaryColor())
        .opacity(0.75)
        .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.surfaceBg())
  }
}
