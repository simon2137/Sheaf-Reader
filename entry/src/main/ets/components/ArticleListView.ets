import { Article, ViewType, ViewConfigs, ViewDefaults } from '../model/Models';
import { FilterType } from '../model/Filter';
import { AppStore } from '../state/AppStore';
import { Display } from '../utils/Display';
import { I18n } from '../utils/I18n';
import { ListCard, CompactCard, MagazineCard, GridCard } from './ArticleCards';
import { TouchTarget } from '../utils/TouchTarget';

/*
 * ArkUI 的 Select 不跟随应用配色：不显式设色时，值文本取浅色主题的默认黑，深色下就是黑字压深底。
 * 值文本跟随主题；**展开的菜单固定成浅色菜单** —— 菜单容器与每个菜单项的描边由系统绘制且是浅色的，
 * 深色菜单配上那些白描边很不协调，所以两种主题下都用浅色模式那一套。
 */
@Extend(Select)
function themedSelect(textColor: string) {
  .fontColor(textColor)
  .optionFontColor('#323130')
  .selectedOptionFontColor('#0078D4')
  .menuBackgroundColor('#FFFFFF')
  .optionBgColor('#FFFFFF')
  .selectedOptionBgColor('#F3F2F1')
}

/**
 * "Mark as read up to N days ago" choices, mirroring the original's
 * `MarkReadContextMenu`, which offers 1, 3 and 7 days on top of "all".
 */
const MARK_READ_DAYS: number[] = [1, 3, 7];

/**
 * One toggle chip.
 *
 * This is a component rather than a `@Builder` on purpose. A `@Builder`
 * receives its parameters by value and is not re-rendered when they change, so
 * the active chip kept its inactive colour after a tap even though the list
 * behind it updated correctly. An `@Prop` is diffed, so it does re-render.
 */
@Component
struct ChipView {
  @Prop label: string;
  @Prop active: boolean;
  @Prop isDarkMode: boolean;
  /** Space to the next chip: tighter in the filter row, wider in the options row. */
  @Prop gap: number;
  onTap: () => void = () => {
  };

  build() {
    Text(this.label)
      .fontSize(12)
      .fontColor(this.active ? Color.White : (this.isDarkMode ? '#C8C6C4' : '#605E5C'))
      .backgroundColor(this.active ? '#0078D4' : (this.isDarkMode ? '#3B3A39' : '#EDEBE9'))
      .borderRadius(12)
      /*
       * Sized for a finger. Measured on the `Huawei_Tablet` image, the old
       * 11vp/4vp-padding chip was 20.9vp tall — half the 40vp the UX guidance
       * requires for a tap area, and these are the controls that filter the
       * list. The padding carries the height so the label stays centred.
       */
      .padding({ left: 12, right: 12, top: 13, bottom: 13 })
      // `bottom` separates the lines once the chip row wraps.
      .margin({ right: this.gap, bottom: 6 })
      .onClick(() => {
        this.onTap();
      })
  }
}

/**
 * Middle pane: search, filters, the view switcher and the article list.
 *
 * The layout mirrors the original's `feeds/feed.tsx` dispatch — `Cards` is a
 * grid of `GridCard`, everything else is a vertical list of `ListCard` /
 * `MagazineCard` / `CompactCard` — and every layout honours the same
 * `ViewConfigs` bits, which is what makes "Customised" meaningful.
 */
@Component
export struct ArticleListView {
  @ObjectLink store: AppStore;
  /** Width of this pane, used to size the card grid. */
  @Prop paneWidth: number;
  onArticleSelect: (articleId: number) => void = () => {
  };
  onStarToggle: (articleId: number) => void = () => {
  };
  /** Toggle the navigation sidebar (the original's `F1` / nav hamburger). */
  onToggleSidebar: () => void = () => {
  };
  /**
   * Fetch every source now — the original's `nav.refresh` title-bar button.
   *
   * Upstream keeps this button in the title bar (top-right, always visible,
   * `disabled={isFetching}`). This port had it only in the sidebar header, so
   * with the sidebar closed there was no visible refresh control at all — just
   * the F5 / `r` shortcuts.
   */
  onRefresh: () => void = () => {
  };
  onSearch: (query: string) => void = () => {
  };
  onMarkAllRead: () => void = () => {
  };
  /**
   * Mark everything published before `days` days ago as read, for the
   * "mark all as read" menu's day entries.
   */
  onMarkAllReadSince: (days: number) => void = () => {
  };
  /** Article context-menu actions that need the page's own facilities. */
  onOpenExternal: (article: Article) => void = () => {
  };
  onCopyLink: (article: Article) => void = () => {
  };
  onCopyTitle: (article: Article) => void = () => {
  };
  onLoadFull: (article: Article) => void = () => {
  };
  /** Image actions from the original's image menu. */
  onImageSave: (article: Article) => void = () => {
  };
  onImageCopy: (article: Article) => void = () => {
  };
  onImageCopyLink: (article: Article) => void = () => {
  };

  private textColor(): string {
    return this.store.isDarkMode ? '#FFFFFF' : '#323130';
  }

  private secondaryColor(): string {
    return this.store.isDarkMode ? '#C8C6C4' : '#605E5C';
  }

  private dividerColor(): string {
    return this.store.isDarkMode ? '#3B3A39' : '#EDEBE9';
  }

  private surfaceColor(): string {
    return this.store.isDarkMode ? '#252423' : '#FFFFFF';
  }

  private chipColor(): string {
    return this.store.isDarkMode ? '#3B3A39' : '#EDEBE9';
  }

  /* ------------------------------------------------------------ helpers */

  private isUnreadOnly(): boolean {
    return !this.store.filterHas(FilterType.ShowRead);
  }

  private isStarredOnly(): boolean {
    return !this.store.filterHas(FilterType.ShowNotStarred);
  }

  private isCaseSensitive(): boolean {
    return !this.store.filterHas(FilterType.CaseInsensitive);
  }

  /** True when no preset is narrowing the list, i.e. the "All articles" entry. */
  private isAllPreset(): boolean {
    return this.store.filter.isAllPreset();
  }

  /**
   * The original's `MarkReadContextMenu` (`components/context-menu.tsx`), bound
   * to its `#mark-all-toggle` arrow next to the "mark all as read" button:
   * everything, or only what was published before 1 / 3 / 7 days ago.
   *
   * The plain button keeps marking the whole scope, which is the action the
   * original binds to the main half of that split control.
   */
  @Builder
  MarkReadMenu() {
    Menu() {
      MenuItemGroup({ header: I18n.get('nav.markAllRead') }) {
        MenuItem({ content: I18n.get('allArticles') })
          .onClick(() => {
            this.onMarkAllRead();
          })
        ForEach(MARK_READ_DAYS, (days: number) => {
          MenuItem({
            content: I18n.get('app.daysAgo', new Map<string, string | number>([['days', days]]))
          })
            .onClick(() => {
              this.onMarkAllReadSince(days);
            })
        }, (days: number) => days.toString())
      }
    }
  }

  /**
   * The original's `ViewContextMenu` (`components/context-menu.tsx`), bound to
   * its `#view-toggle`: one menu carrying the layout section, the preset filter
   * section, the search options and "show hidden articles".
   *
   * Every entry toggles the same store calls the chips and the layout picker
   * use, and `MenuItem.selected`/`selectIcon` render the original's
   * `canCheck`/`checked` marks; `MenuItemGroup` renders its `sectionProps.title`.
   */
  @Builder
  ViewMenu() {
    Menu() {
      MenuItemGroup({ header: I18n.get('context.view') }) {
        MenuItem({ content: this.viewLabelFor(ViewType.Cards) })
          .selected(this.store.viewType === ViewType.Cards)
          .selectIcon(true)
          .onClick(() => {
            this.store.switchView(ViewType.Cards);
          })
        MenuItem({ content: this.viewLabelFor(ViewType.List) })
          .selected(this.store.viewType === ViewType.List)
          .selectIcon(true)
          .onClick(() => {
            this.store.switchView(ViewType.List);
          })
        MenuItem({ content: this.viewLabelFor(ViewType.Magazine) })
          .selected(this.store.viewType === ViewType.Magazine)
          .selectIcon(true)
          .onClick(() => {
            this.store.switchView(ViewType.Magazine);
          })
        MenuItem({ content: this.viewLabelFor(ViewType.Compact) })
          .selected(this.store.viewType === ViewType.Compact)
          .selectIcon(true)
          .onClick(() => {
            this.store.switchView(ViewType.Compact);
          })
      }

      MenuItemGroup({ header: I18n.get('context.filter') }) {
        MenuItem({ content: I18n.get('allArticles') })
          .selected(this.isAllPreset())
          .selectIcon(true)
          .onClick(() => {
            this.store.switchFilter(FilterType.Default);
          })
        MenuItem({ content: I18n.get('context.unreadOnly') })
          .selected(this.isUnreadOnly())
          .selectIcon(true)
          .onClick(() => {
            this.store.switchFilter(FilterType.UnreadOnly);
          })
        MenuItem({ content: I18n.get('context.starredOnly') })
          .selected(this.isStarredOnly())
          .selectIcon(true)
          .onClick(() => {
            this.store.switchFilter(FilterType.StarredOnly);
          })
      }

      MenuItemGroup({ header: I18n.get('search') }) {
        MenuItem({ content: I18n.get('context.caseSensitive') })
          .selected(this.isCaseSensitive())
          .selectIcon(true)
          .onClick(() => {
            this.store.toggleFilter(FilterType.CaseInsensitive);
          })
        MenuItem({ content: I18n.get('context.fullSearch') })
          .selected(this.store.filterHas(FilterType.FullSearch))
          .selectIcon(true)
          .onClick(() => {
            this.store.toggleFilter(FilterType.FullSearch);
          })
      }

      MenuItem({ content: I18n.get('context.showHidden') })
        .selected(this.store.filterHas(FilterType.ShowHidden))
        .selectIcon(true)
        .onClick(() => {
          this.store.toggleFilter(FilterType.ShowHidden);
        })
    }
  }

  private showCover(): boolean {
    return this.store.hasViewConfig(ViewConfigs.ShowCover);
  }

  private showSnippet(): boolean {
    return this.store.hasViewConfig(ViewConfigs.ShowSnippet);
  }

  private fadeRead(): boolean {
    return this.store.hasViewConfig(ViewConfigs.FadeRead);
  }

  private viewLabel(): string {
    return this.viewLabelFor(this.store.viewType);
  }

  /**
   * Preset navigation targets carry no title, so the header falls back to the
   * translated name of the preset rather than an English literal.
   */
  private headerTitle(): string {
    const title: string = this.store.currentNav.title;
    if (title.length > 0) {
      return title;
    }
    return I18n.get('allArticles');
  }

  /** Localised name of a layout; the model only knows its default English. */
  private viewLabelFor(viewType: number): string {
    switch (viewType) {
      case ViewType.Cards:
        return I18n.get('context.cardView');
      case ViewType.Magazine:
        return I18n.get('context.magazineView');
      case ViewType.Compact:
        return I18n.get('context.compactView');
      case ViewType.Customized:
        return I18n.get('app.customised');
      default:
        return I18n.get('context.listView');
    }
  }

  private columnsTemplate(): string {
    const columns: number = Display.columnsFor(this.paneWidth);
    let template: string = '';
    for (let i = 0; i < columns; i++) {
      template = template.length === 0 ? '1fr' : template.concat(' 1fr');
    }
    return template;
  }

  /**
   * Rebuild a row when the selection or the layout changes; read/starred
   * propagate through `@ObjectLink` on the card itself.
   */
  private rowKey(article: Article): string {
    return 'a-'.concat(article.id.toString())
      .concat(article.id === this.store.selectedArticleId ? '-sel' : '-idle')
      .concat('-v').concat(this.store.viewType.toString());
  }

  /* --------------------------------------------------------------- view */

  /**
   * Footer offering the next page, mirroring the original's "Load more".
   * It lives inside the scroll container so that it trails the last card, the
   * way the original's button trails the last article.
   */
  @Builder
  LoadMoreFooter() {
    Row() {
      if (this.store.isLoadingMore) {
        LoadingProgress().width(18).height(18).color('#0078D4')
        Text(I18n.get('app.loading'))
          .fontSize(13)
          .fontColor(this.secondaryColor())
          .margin({ left: 8 })
      } else {
        Text(I18n.get('loadMore'))
          .fontSize(13)
          .fontColor('#0078D4')
      }
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.store.loadMoreArticles();
    })
  }

  /**
   * Right-click / long-press menu for one article, mirroring the original's
   * article context menu. It carries the actions this port can honour: the
   * sync services track read and star state only, and hiding is local by
   * design, so neither is pushed upstream.
   */
  @Builder
  ArticleMenu(article: Article) {
    Menu() {
      MenuItem({ content: I18n.get(article.read ? 'article.markUnread' : 'article.markRead') })
        .onClick(() => {
          this.store.toggleRead(article.id);
        })
      MenuItem({ content: I18n.get('article.markAbove') })
        .onClick(() => {
          this.store.markAround(article.id, true);
        })
      MenuItem({ content: I18n.get('article.markBelow') })
        .onClick(() => {
          this.store.markAround(article.id, false);
        })
      MenuItem({ content: I18n.get(article.starred ? 'article.unstar' : 'article.star') })
        .onClick(() => {
          this.store.toggleStar(article.id);
        })
      MenuItem({ content: I18n.get(article.hidden ? 'article.unhide' : 'article.hide') })
        .onClick(() => {
          this.store.toggleHidden(article.id);
        })
      MenuItem({ content: I18n.get(article.notify ? 'article.dontNotify' : 'article.notify') })
        .onClick(() => {
          this.store.toggleNotify(article.id);
        })
      MenuItem({ content: I18n.get('article.loadFull') })
        .onClick(() => {
          this.onLoadFull(article);
        })
      MenuItem({ content: I18n.get('openExternal') })
        .onClick(() => {
          this.onOpenExternal(article);
        })
      MenuItem({ content: I18n.get('context.copyURL') })
        .onClick(() => {
          this.onCopyLink(article);
        })
      MenuItem({ content: I18n.get('context.copyTitle') })
        .onClick(() => {
          this.onCopyTitle(article);
        })
      // Image actions, matching the original's image menu. The original hangs
      // them off an inline <img> in the rendered article; this reader renders
      // text, so they apply to the article's cover image instead.
      if (article.imageUrl.length > 0) {
        MenuItem({ content: I18n.get('context.saveImageAs') })
          .onClick(() => {
            this.onImageSave(article);
          })
        MenuItem({ content: I18n.get('context.copyImage') })
          .onClick(() => {
            this.onImageCopy(article);
          })
        MenuItem({ content: I18n.get('context.copyImageURL') })
          .onClick(() => {
            this.onImageCopyLink(article);
          })
      }
    }
  }


  /**
   * Width below which the header stacks instead of sharing one line.
   *
   * `LIST_MIN`/`LIST_MAX` keep the pane between 300 and 420vp, and the icon
   * group needs ≈296vp by itself, so the title and the icons cannot coexist
   * below this. 420 is `LIST_MAX`, i.e. "any pane that is not the full-width
   * list stacks".
   */
  private headerStacks(): boolean {
    return this.paneWidth < 420;
  }

  /** Sidebar toggle, article-list title and the article count. */
  @Builder
  HeaderTitle() {
    Row() {
      // Sidebar toggle. The original keeps this in its nav bar, which this
      // port does not have; the list header is always visible, so the control
      // stays reachable while the sidebar is hidden.
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_menu'))
          .width(17)
          .height(17)
          .fillColor(this.secondaryColor())
      }
      .width(30)
      .height(30)
      .responseRegion(TouchTarget.region(30))
      .backgroundColor(Color.Transparent)
      .margin({ right: 6 })
      .onClick(() => {
        this.onToggleSidebar();
      })

      Column() {
        Text(this.headerTitle())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor())
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(I18n.get('app.articlesCount',
          new Map<string, string | number>([['count', this.store.articles.length]])))
          .fontSize(11)
          .fontColor(this.secondaryColor())
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** Refresh, layout picker, view menu, display options and mark-all-read. */
  @Builder
  HeaderButtons() {
    Row() {
      if (this.store.isFetching) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color('#0078D4')
          .margin({ right: 6 })
      }

      /*
       * Refresh, first in the right-hand icon group — the position and
       * behaviour of the original's `nav.refresh` FlatButton: always visible
       * (independent of the sidebar), disabled while a fetch is running, and
       * with the icon left alone (progress is reported by the bar).
       */
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_refresh'))
          .width(17)
          .height(17)
          .fillColor(this.store.isFetching ? this.secondaryColor() : this.textColor())
      }
      .width(30)
      .height(30)
      .responseRegion(TouchTarget.region(30))
      .backgroundColor(Color.Transparent)
      .margin({ left: 4 })
      .enabled(!this.store.isFetching)
      .onClick(() => {
        this.onRefresh();
      })

      // View switcher, mirroring the original's `#view-toggle` menu.
      Select([
        { value: this.viewLabelFor(ViewType.Cards) },
        { value: this.viewLabelFor(ViewType.List) },
        { value: this.viewLabelFor(ViewType.Magazine) },
        { value: this.viewLabelFor(ViewType.Compact) },
        { value: this.viewLabelFor(ViewType.Customized) }
      ])
        .selected(this.store.viewType)
        .value(this.viewLabel())
        .themedSelect(this.textColor())
        .font({ size: 12 })
        .width(118)
        .onSelect((index: number) => {
          this.store.switchView(index);
        })

      // The original's `#view-toggle` context menu: layouts, presets, search
      // options and "show hidden" in one place. Kept alongside the layout
      // picker above, which is the touch-friendly route to the same state.
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_down'))
          .width(16)
          .height(16)
          .fillColor(this.secondaryColor())
      }
      .width(30)
      .height(30)
      .responseRegion(TouchTarget.region(30))
      .backgroundColor(Color.Transparent)
      .margin({ left: 4 })
      .bindMenu(this.ViewMenu())

      // Per-view display options.
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_rule'))
          .width(17)
          .height(17)
          .fillColor(this.store.viewOptionsOpen ? '#0078D4' : this.secondaryColor())
      }
      .width(30)
      .height(30)
      .responseRegion(TouchTarget.region(30))
      .backgroundColor(Color.Transparent)
      .margin({ left: 4 })
      .onClick(() => {
        this.store.toggleViewOptions();
      })

      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_mark_read'))
          .width(17)
          .height(17)
          .fillColor(this.secondaryColor())
      }
      .width(30)
      .height(30)
      .responseRegion(TouchTarget.region(30))
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.onMarkAllRead();
      })

      // The original's `#mark-all-toggle`: the arrow half of the split
      // "mark all as read" control, opening the day-bounded variants.
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_down'))
          .width(14)
          .height(14)
          .fillColor(this.secondaryColor())
      }
      .width(24)
      .height(30)
      .responseRegion(TouchTarget.regionFor(24, 30))
      .backgroundColor(Color.Transparent)
      .bindMenu(this.MarkReadMenu())
    }
  }

  build() {
    Column() {
      /*
       * Header.
       *
       * The icon group alone needs ~370px (≈296vp) at these sizes, so a
       * 300–420vp pane (`LIST_MIN`..`LIST_MAX`) cannot hold it *and* the title:
       * measured on device, the title Column was squeezed to zero width and
       * vanished, leaving a header of buttons only. Below `HEADER_STACK_BELOW`
       * the title takes its own line and the icons follow on the next; above it
       * the two share one line exactly as before.
       */
      if (this.headerStacks()) {
        Column() {
          this.HeaderTitle()

          Column() {
            this.HeaderButtons()
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 8, top: 12, bottom: 6 })
      } else {
        Row() {
          Column() {
            this.HeaderTitle()
          }
          .layoutWeight(1)

          this.HeaderButtons()
        }
        .width('100%')
        .padding({ left: 16, right: 8, top: 12, bottom: 8 })
      }

      /*
       * Search, hidden until toggled. The original keeps `PageState.searchOn`
       * false on start-up and only reveals the bar from the sidebar's Search
       * entry, the toolbar button or Ctrl+F — the query is likewise only
       * applied while it is on.
       */
      if (this.store.searchOn) {
        Row() {
          Image($r('app.media.ic_search'))
            .width(16)
            .height(16)
            .fillColor(this.secondaryColor())
            .margin({ left: 10, right: 6 })

          TextInput({ placeholder: I18n.get('search'), text: this.store.searchQuery })
            .placeholderColor(this.secondaryColor())
            .fontColor(this.textColor())
            .fontSize(13)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .layoutWeight(1)
            // Target of the "/" shortcut.
            .id('articleSearch')
            .onChange((value: string) => {
              this.onSearch(value);
            })

          if (this.store.searchQuery.length > 0) {
            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.ic_close'))
                .width(14)
                .height(14)
                .fillColor(this.secondaryColor())
            }
            .width(26)
            .height(26)
            .responseRegion(TouchTarget.region(26))
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.onSearch('');
            })
          }
        }
        .width('100%')
        .height(36)
        .backgroundColor(this.store.isDarkMode ? '#323130' : '#F3F2F1')
        .borderRadius(6)
        .margin({ left: 12, right: 12, bottom: 8 })
        .alignItems(VerticalAlign.Center)
      }

      /*
       * Filter toggles. Independent bits on top of the sidebar's preset.
       *
       * Three search modifiers used to sit here too ("在正文中搜索" / "区分大小写" /
       * "作者") and were removed on request: the row keeps the two presets and
       * "显示隐藏文章", which is what actually filters a list. The ▾ menu still
       * offers the first two; the author scope was dropped from the list filter
       * altogether and now exists only for rules (`RuleSearchScope.Creator`).
       *
       * A wrapping `Flex`, not a `Row`: the labels need more width than the pane
       * (`LIST_MIN`..`LIST_MAX`, 300–420vp) can give once it is narrow, and as a
       * `Row` they ran straight past the pane's right edge and drew on top of the
       * reader (measured: row `[356,317][761,353]` with the last chip ending at
       * x=916). Wrapping keeps every chip inside the pane; a single line looks
       * exactly as before.
       */
      Flex({ wrap: FlexWrap.Wrap }) {
        ChipView({
          label: I18n.get('context.unreadOnly'),
          active: this.isUnreadOnly(),
          isDarkMode: this.store.isDarkMode,
          gap: 0,
          onTap: () => {
            this.store.switchFilter(this.isUnreadOnly()
              ? FilterType.Default : FilterType.UnreadOnly);
          }
        })
        ChipView({
          label: I18n.get('context.starredOnly'),
          active: this.isStarredOnly(),
          isDarkMode: this.store.isDarkMode,
          gap: 0,
          onTap: () => {
            this.store.switchFilter(this.isStarredOnly()
              ? FilterType.Default : FilterType.StarredOnly);
          }
        })
        ChipView({
          label: I18n.get('context.showHidden'),
          active: this.store.filterHas(FilterType.ShowHidden),
          isDarkMode: this.store.isDarkMode,
          gap: 0,
          onTap: () => {
            this.store.toggleFilter(FilterType.ShowHidden);
          }
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 8 })

      // Per-view display options. Wraps for the same reason the filter row does.
      if (this.store.viewOptionsOpen) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ChipView({
            label: I18n.get('context.showCover'),
            active: this.showCover(),
            isDarkMode: this.store.isDarkMode,
            gap: 6,
            onTap: () => {
              this.store.toggleViewConfig(ViewConfigs.ShowCover);
            }
          })
          ChipView({
            label: I18n.get('context.showSnippet'),
            active: this.showSnippet(),
            isDarkMode: this.store.isDarkMode,
            gap: 6,
            onTap: () => {
              this.store.toggleViewConfig(ViewConfigs.ShowSnippet);
            }
          })
          ChipView({
            label: I18n.get('context.fadeRead'),
            active: this.fadeRead(),
            isDarkMode: this.store.isDarkMode,
            gap: 6,
            onTap: () => {
              this.store.toggleViewConfig(ViewConfigs.FadeRead);
            }
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 8 })
      }

      Divider().color(this.dividerColor()).strokeWidth(1)

      // Body
      if (this.store.isLoading) {
        Column() {
          LoadingProgress().width(30).height(30).color('#0078D4')
          Text(I18n.get('app.loading'))
            .fontSize(13)
            .fontColor(this.secondaryColor())
            .margin({ top: 10 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.store.articles.length === 0) {
        Column() {
          Image($r('app.media.ic_mail'))
            .width(44)
            .height(44)
            .fillColor(this.secondaryColor())
            .opacity(0.4)
          Text(I18n.get('article.empty'))
            .fontSize(15)
            .fontColor(this.secondaryColor())
            .margin({ top: 12 })
          Text(this.store.feeds.length === 0
            ? I18n.get('app.startHint')
            : I18n.get('app.refreshHint'))
            .fontSize(12)
            .fontColor(this.secondaryColor())
            .opacity(0.75)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.store.viewType === ViewType.Cards) {
        Grid() {
          ForEach(this.store.articles, (article: Article) => {
            GridItem() {
              Column() {
                GridCard({
                  article: article,
                  isSelected: article.id === this.store.selectedArticleId,
                  isDarkMode: this.store.isDarkMode,
                  showSnippet: this.showSnippet(),
                  fadeRead: this.fadeRead(),
                  onItemClick: () => {
                    this.onArticleSelect(article.id);
                  },
                  onStarClick: () => {
                    this.onStarToggle(article.id);
                  }
                })
              }
              .width('100%')
              // The mouse trigger lives on the inner node and the touch trigger
              // on the outer one: a second bindContextMenu on the same node
              // replaces the first rather than adding a trigger.
              .bindContextMenu(this.ArticleMenu(article), ResponseType.RightClick)
            }
            .bindContextMenu(this.ArticleMenu(article), ResponseType.LongPress)
          }, (article: Article) => this.rowKey(article))
          if (this.store.canLoadMore) {
            GridItem() {
              this.LoadMoreFooter()
            }
            .columnStart(0)
            .columnEnd(-1)
          }
        }
        .columnsTemplate(this.columnsTemplate())
        .columnsGap(12)
        .rowsGap(12)
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
      } else {
        List() {
          ForEach(this.store.articles, (article: Article) => {
            ListItem() {
              Column() {
                if (this.store.viewType === ViewType.Compact) {
                  CompactCard({
                    article: article,
                    isSelected: article.id === this.store.selectedArticleId,
                    isDarkMode: this.store.isDarkMode,
                    fadeRead: this.fadeRead(),
                    onItemClick: () => {
                      this.onArticleSelect(article.id);
                    }
                  })
                } else if (this.store.viewType === ViewType.Magazine) {
                  MagazineCard({
                    article: article,
                    isSelected: article.id === this.store.selectedArticleId,
                    isDarkMode: this.store.isDarkMode,
                    showCover: this.showCover(),
                    showSnippet: this.showSnippet(),
                    fadeRead: this.fadeRead(),
                    onItemClick: () => {
                      this.onArticleSelect(article.id);
                    },
                    onStarClick: () => {
                      this.onStarToggle(article.id);
                    }
                  })
                } else {
                  ListCard({
                    article: article,
                    isSelected: article.id === this.store.selectedArticleId,
                    isDarkMode: this.store.isDarkMode,
                    showCover: this.showCover(),
                    showSnippet: this.showSnippet(),
                    fadeRead: this.fadeRead(),
                    onItemClick: () => {
                      this.onArticleSelect(article.id);
                    },
                    onStarClick: () => {
                      this.onStarToggle(article.id);
                    }
                  })
                }
              }
              .width('100%')
              // The mouse trigger lives on the inner node and the touch trigger
              // on the outer one: a second bindContextMenu on the same node
              // replaces the first rather than adding a trigger.
              .bindContextMenu(this.ArticleMenu(article), ResponseType.RightClick)
            }
            .bindContextMenu(this.ArticleMenu(article), ResponseType.LongPress)
          }, (article: Article) => this.rowKey(article))
          if (this.store.canLoadMore) {
            ListItem() {
              this.LoadMoreFooter()
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .divider({
          strokeWidth: 1,
          color: this.dividerColor(),
          startMargin: 12,
          endMargin: 12
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfaceColor())
  }
}
