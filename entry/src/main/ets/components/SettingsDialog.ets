import { AppStore } from '../state/AppStore';
import { DarkModeSetting } from '../model/Models';
import { I18n } from '../utils/I18n';
import { SearchEngines } from '../utils/SearchEngines';
import { StorageSize } from '../utils/StorageSize';
import { FetchSchedule } from '../utils/FetchSchedule';
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
 * "Delete articles from … days ago" choices, mirroring the original's list.
 * `0` is the original's own encoding of "Delete all articles".
 */
const DELETE_DAYS: number[] = [7, 14, 21, 28, 0];

/**
 * Settings dialog. Scrollable sections, sized for tablet / PC.
 */
@CustomDialog
export struct SettingsDialog {
  // 主题走 AppStorage（不是 @Prop）：弹窗内容由 CustomDialogController 构建，
  // 父组件重渲染不会重建它，切主题时 @Prop 会停在旧值直到关掉重开。
  @StorageProp('sheafReaderIsDarkMode') isDarkMode: boolean = false;
  // 同理：这个下拉的当前值要立刻跟着变，不能停在打开弹窗时的快照。
  @StorageProp('sheafReaderDarkModeSetting') darkMode: number = DarkModeSetting.SYSTEM;
  /*
   * 其余设置在弹窗里是**改完立刻要看到新值**的：用 @Prop 传快照时，弹窗只会在自己重建时
   * 重新读到它们，而切主题正好会触发一次重建 —— 于是「先改抓取频率、再切主题」会把那一行
   * 显示回旧值（实测）。链 store 就和侧栏/列表一样始终读实时状态。回调仍由页面传入。
   */
  @ObjectLink store: AppStore;
  onSearchEngineChange: (engine: number) => void = () => {
  };

  private searchEngineOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const engine of SearchEngines.ALL) {
      options.push({ value: I18n.get(SearchEngines.labelKey(engine)) });
    }
    return options;
  }

  onDarkModeChange: (mode: number) => void = () => {
  };
  @Prop locale: string;
  onLocaleChange: (locale: string) => void = () => {
  };
  onFontSizeChange: (size: number) => void = () => {
  };
  /** Raised on every close path so the page can drop its "panel is open" flag. */
  onClose: () => void = () => {
  };

  onShowThumbnailsChange: (value: boolean) => void = () => {
  };
  onOpenInBuiltInViewChange: (value: boolean) => void = () => {
  };
  onFetchIntervalChange: (minutes: number) => void = () => {
  };
  onImportOpml: () => void = () => {
  };
  onBackup: () => void = () => {
  };
  onRestore: () => void = () => {
  };
  onExportOpml: () => void = () => {
  };
  /** Serialized size of the article store, in bytes. */
  onMeasureArticles: () => Promise<number> = async () => 0;
  /** Delete articles published before `days` ago; `0` means the whole archive. */
  onDeleteArticles: (days: number) => Promise<void> = async () => {
  };
  /** Size of the application cache directory, in bytes. */
  onMeasureCache: () => Promise<number> = async () => 0;
  onClearCache: () => void = () => {
  };

  controller?: CustomDialogController;

  /**
   * Chosen "delete articles" option, as an index into `deleteOptions()`; -1
   * until the user picks one. The delete button stays disabled while it is -1,
   * matching the original.
   */
  @State deleteIndex: number = -1;
  /** Article store size, or empty while it is still being measured. */
  @State itemSize: string = '';
  /** Cache size, or empty while it is still being measured. */
  @State cacheSize: string = '';
  /** True while a delete is running, to keep the button from re-firing. */
  @State deleting: boolean = false;
  /**
   * Working copy of the reader's font size.
   *
   * A `CustomDialogController` builds its content once, when the dialog is
   * created, so the `@Prop` value handed in at that moment never changes while
   * the panel is open. The stepper therefore reads from a value this dialog
   * owns: the "N px" label kept showing the size from opening time, and every
   * tap of + / − recomputed from that same stale number — three taps in a row
   * all wrote "16 + 1", and the label never moved (measured on device).
   */
  @State fontSizeShown: number = 16;

  aboutToAppear(): void {
    this.fontSizeShown = this.store.settings.fontSize;
    this.measureArticles();
    this.measureCache();
  }

  private async measureArticles(): Promise<void> {
    this.itemSize = '';
    const bytes: number = await this.onMeasureArticles();
    this.itemSize = StorageSize.formatMb(bytes);
  }

  private async measureCache(): Promise<void> {
    this.cacheSize = '';
    const bytes: number = await this.onMeasureCache();
    this.cacheSize = StorageSize.formatMb(bytes);
  }

  /**
   * "7 days ago" … "Delete all articles", mirroring the original's list. The
   * labels are built separately from the `SelectOption`s because `SelectOption.value`
   * is a `ResourceStr`, which cannot be used as a plain label.
   */
  private deleteLabels(): string[] {
    const labels: string[] = [];
    for (const value of DELETE_DAYS) {
      labels.push(value === 0
        ? I18n.get('app.deleteAll')
        : I18n.get('app.daysAgo', new Map<string, string | number>([['days', value]])));
    }
    return labels;
  }

  private deleteOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const label of this.deleteLabels()) {
      options.push({ value: label });
    }
    return options;
  }

  private deleteLabel(): string {
    const labels: string[] = this.deleteLabels();
    if (this.deleteIndex < 0 || this.deleteIndex >= labels.length) {
      return I18n.get('app.deleteChoices');
    }
    return labels[this.deleteIndex];
  }

  private async confirmDelete(): Promise<void> {
    if (this.deleting || this.deleteIndex < 0) {
      return;
    }
    const days: number = DELETE_DAYS[this.deleteIndex];
    this.deleting = true;
    this.itemSize = '';
    await this.onDeleteArticles(days);
    this.deleting = false;
    this.deleteIndex = -1;
    await this.measureArticles();
  }

  private async clearCache(): Promise<void> {
    this.cacheSize = '';
    this.onClearCache();
    await this.measureCache();
  }

  private textColor(): string {
    return this.isDarkMode ? '#E8E6E3' : '#323130';
  }

  private secondaryColor(): string {
    return this.isDarkMode ? '#A19F9D' : '#605E5C';
  }

  private surfaceColor(): string {
    return this.isDarkMode ? '#252423' : '#FFFFFF';
  }

  private dividerColor(): string {
    return this.isDarkMode ? '#3B3A39' : '#EDEBE9';
  }

  private closeDialog(): void {
    // The page tracks whether this panel is open, because the original refuses
    // to run a background fetch while `app.settings.display` is set. Let it
    // clear that flag on every close path, not just the mask tap.
    this.onClose();
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }

  /**
   * The original's interval dropdown (`settings/app.tsx`): Never, 10, 15, 20,
   * 30, 45 minutes and 1 hour — seven entries, not the port's old
   * 15/30/60/120/240/720 list.
   */
  private intervalValues(): number[] {
    return FetchSchedule.options(FetchSchedule.INTERVALS, this.store.settings.fetchIntervalMinutes);
  }

  private fetchIntervalOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const minutes of this.intervalValues()) {
      options.push({ value: this.intervalLabel(minutes) });
    }
    return options;
  }

  private fetchIntervalIndex(): number {
    const index: number = this.intervalValues().indexOf(this.store.settings.fetchIntervalMinutes);
    return index >= 0 ? index : 0;
  }

  /** 0 is `app.never` upstream; every other entry is a minute or hour label. */
  private intervalLabel(minutes: number): string {
    switch (minutes) {
      case 0:
        return I18n.get('app.never');
      case 60:
        return I18n.get('time.hour', new Map<string, string | number>([['h', 1]]));
      default:
        return I18n.get('time.minute', new Map<string, string | number>([['m', minutes]]));
    }
  }

  private fetchIntervalLabel(): string {
    return this.intervalLabel(this.store.settings.fetchIntervalMinutes);
  }

  build() {
    Column() {
      // Header
      Row() {
        Text(I18n.get('settings.name'))
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor())
          .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_close'))
            .width(16)
            .height(16)
            .fillColor(this.secondaryColor())
        }
        .width(30)
        .height(30)
        .responseRegion(TouchTarget.region(30))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.closeDialog();
        })
      }
      .width('100%')
      .padding({ bottom: 14 })

      Divider().color(this.dividerColor()).strokeWidth(1)

      Scroll() {
        Column() {
          // ---- Appearance ----
          Text(I18n.get('settings.app'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ top: 16, bottom: 8 })

          Row() {
            Text(I18n.get('app.language'))
              .fontSize(14)
              .fontColor(this.textColor())
              .layoutWeight(1)
            Select(this.localeOptions())
              .selected(this.localeIndex())
              .value(I18n.localeLabel(this.store.locale))
              .themedSelect(this.textColor())
              .width(150)
              .onSelect((index: number) => {
                this.onLocaleChange(I18n.availableLocales()[index]);
              })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })

          Row() {
            Text(I18n.get('app.theme'))
              .fontSize(14)
              .fontColor(this.textColor())
              .layoutWeight(1)
            Select([
              { value: I18n.get('followSystem') },
              { value: I18n.get('app.lightTheme') },
              { value: I18n.get('app.darkTheme') }
            ])
              .selected(this.darkMode)
              .value(this.darkMode === DarkModeSetting.DARK ? I18n.get('app.darkTheme')
                : (this.darkMode === DarkModeSetting.LIGHT
                  ? I18n.get('app.lightTheme') : I18n.get('followSystem')))
              .themedSelect(this.textColor())
              .width(150)
              .onSelect((index: number) => {
                this.onDarkModeChange(index);
              })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })

          Row() {
            Text(I18n.get('article.fontSize'))
              .fontSize(14)
              .fontColor(this.textColor())
              .layoutWeight(1)

            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.ic_close')).width(12).height(12).fillColor(this.textColor())
            }
            .width(30)
            .height(30)
            .responseRegion(TouchTarget.region(30))
            .backgroundColor(this.dividerColor())
            .onClick(() => {
              if (this.fontSizeShown > 12) {
                this.fontSizeShown = this.fontSizeShown - 1;
                this.onFontSizeChange(this.fontSizeShown);
              }
            })

            Text(this.fontSizeShown.toString() + ' px')
              .fontSize(14)
              .fontColor(this.textColor())
              .width(58)
              .textAlign(TextAlign.Center)

            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.ic_add')).width(12).height(12).fillColor(this.textColor())
            }
            .width(30)
            .height(30)
            .responseRegion(TouchTarget.region(30))
            .backgroundColor(this.dividerColor())
            .onClick(() => {
              if (this.fontSizeShown < 28) {
                this.fontSizeShown = this.fontSizeShown + 1;
                this.onFontSizeChange(this.fontSizeShown);
              }
            })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })

          Divider().color(this.dividerColor()).strokeWidth(1).margin({ top: 6, bottom: 6 })

          // ---- Reading ----
          Text(I18n.get('app.reading'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ bottom: 8 })

          Row() {
            Text(I18n.get('context.showCover'))
              .fontSize(14)
              .fontColor(this.textColor())
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.store.settings.showThumbnails })
              .selectedColor('#0078D4')
              .onChange((isOn: boolean) => {
                this.onShowThumbnailsChange(isOn);
              })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })

          Row() {
            Column() {
              Text(I18n.get('article.loadWebpage'))
                .fontSize(14)
                .fontColor(this.textColor())
                .width('100%')
              Text(I18n.get('app.builtinViewHint'))
                .fontSize(11)
                .fontColor(this.secondaryColor())
                .width('100%')
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.store.settings.openInBuiltInView })
              .selectedColor('#0078D4')
              .onChange((isOn: boolean) => {
                this.onOpenInBuiltInViewChange(isOn);
              })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })

          Row() {
            Text(I18n.get('searchEngine.name'))
              .fontSize(14)
              .fontColor(this.textColor())
              .layoutWeight(1)
            Select(this.searchEngineOptions())
              .selected(this.store.settings.searchEngine)
              .value(I18n.get(SearchEngines.labelKey(this.store.settings.searchEngine)))
              .themedSelect(this.textColor())
              .width(150)
              .onSelect((index: number) => {
                this.onSearchEngineChange(SearchEngines.ALL[index]);
              })
          }
          .width('100%')
          .padding({ top: 4, bottom: 10 })

          Divider().color(this.dividerColor()).strokeWidth(1).margin({ top: 6, bottom: 6 })

          // ---- Sync ----
          Text(I18n.get('app.sync'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ bottom: 8 })

          Row() {
            Text(I18n.get('app.fetchInterval'))
              .fontSize(14)
              .fontColor(this.textColor())
              .layoutWeight(1)
            Select(this.fetchIntervalOptions())
              .selected(this.fetchIntervalIndex())
              .value(this.fetchIntervalLabel())
              .themedSelect(this.textColor())
              .width(150)
              .onSelect((index: number) => {
                this.onFetchIntervalChange(this.intervalValues()[index]);
              })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })

          Text(I18n.get('app.subscriptionsCount', new Map<string, string | number>([['count', this.store.feeds.length]]))
            + '   |   ' + I18n.get('app.cachedArticles', new Map<string, string | number>([['count', this.store.articles.length]])))
            .fontSize(12)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ top: 6 })

          Divider().color(this.dividerColor()).strokeWidth(1).margin({ top: 12, bottom: 6 })

          // ---- Data ----
          Text(I18n.get('app.data'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ bottom: 8 })

          Row() {
            Button(I18n.get('sources.import'))
              .fontSize(13)
              .fontColor(this.textColor())
              .backgroundColor(this.dividerColor())
              .layoutWeight(1)
              .onClick(() => {
                this.onImportOpml();
              })

            Button(I18n.get('sources.export'))
              .fontSize(13)
              .fontColor(this.textColor())
              .backgroundColor(this.dividerColor())
              .layoutWeight(1)
              .margin({ left: 10 })
              .onClick(() => {
                this.onExportOpml();
              })
          }
          .width('100%')
          .margin({ top: 8 })

          // Full application data, mirroring the original's .frdata backup.
          Row() {
            Button(I18n.get('app.backup'))
              .fontSize(13)
              .fontColor(this.textColor())
              .backgroundColor(this.dividerColor())
              .layoutWeight(1)
              .onClick(() => {
                this.onBackup();
              })

            Button(I18n.get('app.restore'))
              .fontSize(13)
              .fontColor(this.textColor())
              .backgroundColor(this.dividerColor())
              .layoutWeight(1)
              .margin({ left: 10 })
              .onClick(() => {
                this.onRestore();
              })
          }
          .width('100%')
          .margin({ top: 10 })

          Text(I18n.get('app.restoreHint'))
            .fontSize(11)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ top: 6 })

          Divider().color(this.dividerColor()).strokeWidth(1).margin({ top: 12, bottom: 6 })

          // ---- Clean up ----
          // Mirrors the original's App tab: a "delete articles from … ago"
          // choice with a danger button, then the cache action, each with its
          // own size hint.
          Text(I18n.get('app.cleanup'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ bottom: 8 })

          Row() {
            Select(this.deleteOptions())
              .selected(this.deleteIndex)
              .value(this.deleteLabel())
              .themedSelect(this.textColor())
              .layoutWeight(1)
              .onSelect((index: number) => {
                this.deleteIndex = index;
              })

            Button(I18n.get('app.confirmDelete'))
              .fontSize(13)
              .fontColor('#FFFFFF')
              .backgroundColor(this.deleteIndex < 0 || this.deleting ? '#C8C6C4' : '#D13438')
              .enabled(this.itemSize.length > 0 && this.deleteIndex >= 0 && !this.deleting)
              .margin({ left: 8 })
              .onClick(() => {
                this.confirmDelete();
              })
          }
          .width('100%')

          Text(this.itemSize.length > 0
            ? I18n.get('app.itemSize', new Map<string, string | number>([['size', this.itemSize]]))
            : I18n.get('app.calculatingSize'))
            .fontSize(11)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ top: 6 })

          Button(I18n.get('app.cache'))
            .fontSize(13)
            .fontColor(this.textColor())
            .backgroundColor(this.dividerColor())
            .enabled(this.cacheSize.length > 0 && this.cacheSize !== '0MB')
            .margin({ top: 10 })
            .onClick(() => {
              this.clearCache();
            })

          Text(this.cacheSize.length > 0
            ? I18n.get('app.cacheSize', new Map<string, string | number>([['size', this.cacheSize]]))
            : I18n.get('app.calculatingSize'))
            .fontSize(11)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ top: 6 })

          Divider().color(this.dividerColor()).strokeWidth(1).margin({ top: 16, bottom: 6 })

          // ---- About ----
          Text(I18n.get('settings.about'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryColor())
            .width('100%')
            .margin({ bottom: 8 })

          Row() {
            Image(this.isDarkMode ? $r('app.media.app_mark_dark') : $r('app.media.app_mark_light'))
              .width(24)
              .height(24)
            Column() {
              Text('Sheaf Reader 束阅')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.textColor())
                .width('100%')
              Text(I18n.get('settings.version') + ' 1.0.0  ·  BSD-3-Clause')
                .fontSize(11)
                .fontColor(this.secondaryColor())
                .width('100%')
                .margin({ top: 2 })
              Text('Ported from Fluent Reader by yang991178')
                .fontSize(11)
                .fontColor(this.secondaryColor())
                .width('100%')
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })
          }
          .width('100%')
          .margin({ top: 8, bottom: 16 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)

      Button(I18n.get('close'))
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor('#0078D4')
        .width('100%')
        .margin({ top: 14 })
        .onClick(() => {
          this.closeDialog();
        })
    }
    .width(520)
    .height(640)
    .padding(24)
    .backgroundColor(this.surfaceColor())
    .borderRadius(10)
  }

  /** Every bundled locale, in the runtime's own order. */
  private localeOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const locale of I18n.availableLocales()) {
      options.push({ value: I18n.localeLabel(locale) });
    }
    return options;
  }

  private localeIndex(): number {
    const index: number = I18n.availableLocales().indexOf(this.store.locale);
    return index >= 0 ? index : 0;
  }
}
