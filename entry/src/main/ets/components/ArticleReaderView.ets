import { Article, SourceTextDirection } from '../model/Models';
import { SearchEngines } from '../utils/SearchEngines';
import { ReaderBody, ReaderBlock } from '../utils/ReaderBody';
import { TouchTarget } from '../utils/TouchTarget';

/**
 * Identifies the injected "search selected text" menu item. Kept to plain
 * alphanumerics because the platform parses this as a resource-ish identifier.
 */
const SEARCH_ITEM_ID: string = 'frsearch';

/**
 * Right pane: full article reading view.
 */
@Component
export struct ArticleReaderView {
  @ObjectLink article: Article;
  @Prop isDarkMode: boolean;
  @Prop fontSize: number;
  @Prop lineHeight: number;
  onStarToggle: () => void = () => {
  };
  onReadToggle: () => void = () => {
  };
  onOpenExternal: () => void = () => {
  };
  onClose: () => void = () => {
  };
  /** True while the store is fetching this article's full text. */
  @Prop isLoadingFull: boolean;
  onLoadFull: () => void = () => {
  };
  /** `source.textDir`: LTR, RTL or vertical. */
  @Prop textDir: number;
  /** Engine used by "search selected text". */
  @Prop searchEngine: number;
  onSearchText: (text: string) => void = () => {
  };

  /**
   * Last selection reported by the body text, used only to label the injected
   * menu item. The click handler uses the range it is handed, which is
   * authoritative.
   */
  @State selectionText: string = '';

  /** Label for the injected selection-menu item. */
  private searchLabel(): string {
    return SearchEngines.menuLabel(this.searchEngine, this.selectionText);
  }

  /**
   * Append "search on <engine>" to the text selection menu, mirroring the
   * original's selected-text search. Every built-in item is left in place.
   *
   * The array handed in is the very list the platform renders, so the new item
   * is appended in place (`push`) and the same array is returned, following the
   * official `editMenuOptions` sample.
   *
   * ArkUI keeps the built-in 复制 / 全选 buttons inline and moves developer
   * extensions behind the row's `⋯` (`SelectMoreOrBackButton`) popup, so this
   * item is reached by tapping that button rather than being visible directly.
   */
  private extendSelectionMenu(items: Array<TextMenuItem>): Array<TextMenuItem> {
    const item: TextMenuItem = {
      content: this.searchLabel(),
      icon: $r('app.media.ic_search'),
      id: TextMenuItemId.of(SEARCH_ITEM_ID)
    };
    items.push(item);
    return items;
  }

  /**
   * Handle a click on the injected item.
   *
   * The item is recognised by its id, matching the official sample's use of
   * `menuItem.id.equals(...)`. Returning false hands the event back to the
   * platform, which is what the built-in Copy / Select all items need.
   *
   * `blockText` is the text of the very `Text` the menu was opened on: ArkUI
   * measures `TextRange` against that component's own content, so slicing
   * anything else (the whole body was sliced here once) searches for whatever
   * happens to sit at the same offsets near the start of the article.
   */
  private handleSelectionMenu(menuItem: TextMenuItem, range: TextRange,
    blockText: string): boolean {
    const mine: boolean = menuItem.id.equals(TextMenuItemId.of(SEARCH_ITEM_ID))
      || menuItem.content === this.searchLabel();
    if (!mine) {
      return false;
    }
    const start: number = range.start !== undefined ? range.start : 0;
    const end: number = range.end !== undefined ? range.end : start;
    const selected: string = SearchEngines.selectionOf(blockText, start, end);
    if (selected.length === 0) {
      return true;
    }
    this.onSearchText(selected);
    return true;
  }

  /**
   * ArkUI has no vertical writing mode, so only LTR and RTL change the layout.
   * `SourceTextDirection.Vertical` is stored and round-trips through backup but
   * renders left-to-right; that gap is documented in the README.
   */
  private textDirection(): Direction {
    return this.textDir === SourceTextDirection.RTL ? Direction.Rtl : Direction.Ltr;
  }

  private textColor(): string {
    return this.isDarkMode ? '#E8E6E3' : '#323130';
  }

  private secondaryColor(): string {
    return this.isDarkMode ? '#A19F9D' : '#605E5C';
  }

  private dividerColor(): string {
    return this.isDarkMode ? '#3B3A39' : '#EDEBE9';
  }

  private surfaceColor(): string {
    return this.isDarkMode ? '#1B1A19' : '#FFFFFF';
  }

  private formattedDate(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }
    const date: Date = new Date(timestamp);
    return date.getFullYear().toString() + '-' + this.pad(date.getMonth() + 1)
      + '-' + this.pad(date.getDate()) + ' ' + this.pad(date.getHours())
      + ':' + this.pad(date.getMinutes());
  }

  private pad(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }

  /**
   * A page fetched by "load webpage" / "load full content" for this article,
   * empty when the feed's own text should be shown. Kept out of `Article`
   * because the loaded page is view state: the original never rewrites the
   * stored item, which is what lets the action toggle back.
   */
  @Prop viewBody: string;

  /**
   * The body's paragraphs and inline images, in document order.
   *
   * The original renders the article HTML in a webview so pictures come along
   * with the text; ArkUI draws them from blocks instead.
   */
  private bodyBlocks(): ReaderBlock[] {
    return ReaderBody.blocks(this.bodyHtml(), this.article.link);
  }

  /** The body markup the reader is showing, before it is split into blocks. */
  private bodyHtml(): string {
    let html: string = this.viewBody.length > 0 ? this.viewBody : this.article.content;
    if (!html) {
      html = this.article.snippet;
    }
    return html;
  }

  build() {
    Column() {
      // Toolbar
      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_arrow_left'))
            .width(18)
            .height(18)
            .fillColor(this.textColor())
        }
        .width(34)
        .height(34)
        .responseRegion(TouchTarget.region(34))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onClose();
        })

        Blank()

        // Star
        Button({ type: ButtonType.Circle }) {
          Image(this.article.starred ? $r('app.media.ic_star') : $r('app.media.ic_star_outline'))
            .width(18)
            .height(18)
            .fillColor(this.article.starred ? '#FFB900' : this.secondaryColor())
        }
        .width(34)
        .height(34)
        .responseRegion(TouchTarget.region(34))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onStarToggle();
        })

        // Read toggle
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_mail_read'))
            .width(18)
            .height(18)
            .fillColor(this.article.read ? '#0078D4' : this.secondaryColor())
        }
        .width(34)
        .height(34)
        .responseRegion(TouchTarget.region(34))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onReadToggle();
        })

        // Load the full text from the article's own page
        Button({ type: ButtonType.Circle }) {
          if (this.isLoadingFull) {
            LoadingProgress().width(18).height(18).color('#0078D4')
          } else {
            Image($r('app.media.ic_full_text'))
              .width(18)
              .height(18)
              .fillColor(this.secondaryColor())
          }
        }
        .width(34)
        .height(34)
        .responseRegion(TouchTarget.region(34))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onLoadFull();
        })

        // Open in browser
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_globe'))
            .width(18)
            .height(18)
            .fillColor(this.secondaryColor())
        }
        .width(34)
        .height(34)
        .responseRegion(TouchTarget.region(34))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onOpenExternal();
        })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })

      Divider().color(this.dividerColor()).strokeWidth(1)

      Scroll() {
        Column() {
          Text(this.article.title)
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textColor())
            .width('100%')
            .margin({ bottom: 14 })

          Row() {
            if (this.article.feedTitle.length > 0) {
              Text(this.article.feedTitle)
                .fontSize(13)
                .fontColor('#0078D4')
                .maxLines(1)
            }
            if (this.article.author.length > 0) {
              Text(this.article.author)
                .fontSize(13)
                .fontColor(this.secondaryColor())
                .margin({ left: 10 })
                .maxLines(1)
            }
            Text(this.formattedDate(this.article.published))
              .fontSize(13)
              .fontColor(this.secondaryColor())
              .margin({ left: 10 })
          }
          .width('100%')
          .margin({ bottom: 18 })

          Divider()
            .color(this.dividerColor())
            .strokeWidth(1)
            .margin({ bottom: 18 })

          ForEach(this.bodyBlocks(), (block: ReaderBlock, index: number) => {
            if (block.kind === ReaderBody.IMAGE) {
              // A picture is drawn where it sat in the body, at the pane's
              // width; ArkUI keeps the intrinsic ratio once the width is fixed.
              Image(block.value)
                .width('100%')
                .objectFit(ImageFit.Contain)
                .constraintSize({ maxHeight: 420 })
                .margin({ top: 6, bottom: 12 })
            } else if (block.kind === ReaderBody.VIDEO) {
              // A `<video>` in the body. Upstream's webview plays these inline,
              // so the reader does too; the feed's `poster` frame is used as the
              // placeholder until the clip is started.
              if (block.poster.length > 0) {
                Video({ src: block.value, previewUri: block.poster })
                  .width('100%')
                  .aspectRatio(1.7778)
                  .controls(true)
                  .autoPlay(false)
                  .objectFit(ImageFit.Contain)
                  .margin({ top: 6, bottom: 12 })
              } else {
                Video({ src: block.value })
                  .width('100%')
                  .aspectRatio(1.7778)
                  .controls(true)
                  .autoPlay(false)
                  .objectFit(ImageFit.Contain)
                  .margin({ top: 6, bottom: 12 })
              }
            } else {
              Text(block.value)
                .fontSize(this.fontSize)
                .fontColor(this.textColor())
                .lineHeight(this.fontSize * this.lineHeight)
                .width('100%')
                .textAlign(TextAlign.Start)
                .direction(this.textDirection())
                .margin({ bottom: 10 })
                // Long-press to select, then "search on <engine>" in the menu.
                .copyOption(CopyOptions.LocalDevice)
                .onTextSelectionChange((start: number, end: number) => {
                  // The offsets belong to *this* block, so the slice has to come
                  // from the block as well: with the whole body the selection
                  // would be wrong for every paragraph but the first.
                  this.selectionText = block.value.substring(start, end).trim();
                })
                .editMenuOptions({
                  onCreateMenu: (menuItems: Array<TextMenuItem>): Array<TextMenuItem> => {
                    return this.extendSelectionMenu(menuItems);
                  },
                  onMenuItemClick: (menuItem: TextMenuItem, range: TextRange): boolean => {
                    // Same reason: the menu belongs to this block, and the
                    // range it hands back is measured against it.
                    return this.handleSelectionMenu(menuItem, range, block.value);
                  }
                })
            }
          }, (block: ReaderBlock, index: number) => this.article.id.toString()
            + ':' + index.toString() + ':' + block.kind.toString()
            + ':' + block.value.length.toString())

          Column().height(72)
        }
        .width('100%')
        .padding({ left: 32, right: 32, top: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfaceColor())
  }
}
