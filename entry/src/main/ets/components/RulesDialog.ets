import { Feed, SourceRule, ItemAction, RuleActions, RuleTestResult } from '../model/Models';
import { FilterType, RuleSearchScope } from '../model/Filter';
import { RuleEngine } from '../services/RuleEngine';
import { I18n } from '../utils/I18n';
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
 * Regex automation rules, ported from the original's Rules settings pane.
 *
 * A rule pairs a condition (which field to match, whether it must match or
 * must not, and the pattern) with a set of actions applied to matching
 * articles before they are stored.
 *
 * Deviation from upstream: reordering uses up/down buttons rather than
 * drag-and-drop, which is more reliable under touch and needs no gesture
 * plumbing. Rule order semantics are identical.
 */
@CustomDialog
export struct RulesDialog {
  // 主题走 AppStorage（不是 @Prop）：弹窗内容由 CustomDialogController 构建，
  // 父组件重渲染不会重建它，切主题时 @Prop 会停在旧值直到关掉重开。
  @StorageProp('sheafReaderIsDarkMode') isDarkMode: boolean = false;
  @Prop feeds: Feed[];
  @Prop initialFeedId: number;

  onLoadRules: (feedId: number) => Promise<SourceRule[]> =
    async () => [];
  onSaveRules: (feedId: number, rules: SourceRule[]) => Promise<void> =
    async () => {
    };
  /**
   * Dry-run a rule against the articles the caller already has, mirroring the
   * original's "Test rules". The dialog owns no article list of its own.
   */
  onTestRule: (rule: SourceRule) => Promise<RuleTestResult> =
    async () => {
      return { matched: 0, total: 0 };
    };

  controller?: CustomDialogController;

  /**
   * Index of the source whose rules are being edited, or `-1` for "none chosen
   * yet".
   *
   * Upstream's rule editor has a source dropdown carrying the placeholder
   * `rules.selectSource`, which only makes sense if that state is reachable.
   * This port used to default to the first source, so the placeholder could
   * never appear *and* opening the panel from "All articles" silently edited
   * the first feed's rules. `-1` is now the honest default, and everything that
   * touches rules already handles a null source (`reload`, `persist`).
   */
  @State feedIndex: number = -1;
  @State rules: SourceRule[] = [];
  @State loading: boolean = true;
  @State editing: boolean = false;
  @State status: string = '';

  /* draft rule */
  @State draftScope: number = 0;
  @State draftMatch: boolean = true;
  @State draftRegex: string = '';
  @State draftCaseSensitive: boolean = false;
  /**
   * Selected action keys, e.g. "r-true" / "s-false". Upstream's UI keeps at
   * most one key per action letter, so picking "mark unread" replaces
   * "mark read" rather than stacking.
   */
  @State draftActions: string[] = [];
  @State draftError: string = '';

  aboutToAppear(): void {
    for (let i = 0; i < this.feeds.length; i++) {
      if (this.feeds[i].id === this.initialFeedId) {
        this.feedIndex = i;
        break;
      }
    }
    this.reload();
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

  private fieldColor(): string {
    return this.isDarkMode ? '#323130' : '#F3F2F1';
  }

  private dividerColor(): string {
    return this.isDarkMode ? '#3B3A39' : '#EDEBE9';
  }

  private closeDialog(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }

  private currentFeed(): Feed | null {
    if (this.feedIndex < 0 || this.feedIndex >= this.feeds.length) {
      return null;
    }
    return this.feeds[this.feedIndex];
  }

  private feedOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const feed of this.feeds) {
      options.push({ value: feed.title });
    }
    return options;
  }

  private async reload(): Promise<void> {
    const feed: Feed | null = this.currentFeed();
    if (feed === null) {
      this.rules = [];
      this.loading = false;
      return;
    }
    this.loading = true;
    this.rules = await this.onLoadRules(feed.id);
    this.loading = false;
  }

  private async persist(): Promise<void> {
    const feed: Feed | null = this.currentFeed();
    if (feed === null) {
      return;
    }
    await this.onSaveRules(feed.id, this.rules);
  }

  /* ------------------------------------------------------- rule drafting */

  /**
   * Build the rule's `FilterType`.
   *
   * The bits are inverted — a CLEAR bit *requires* that state — so the base
   * must include ShowRead, ShowNotStarred and ShowHidden, otherwise the rule
   * would only ever match unread, starred, visible articles. This mirrors
   * upstream's `saveRule`, which starts from
   * `FilterType.Default | FilterType.ShowHidden`.
   *
   * The scope bits are the rule's own (`RuleSearchScope`), not the list
   * filter's presets, but they share the field because that is upstream's stored
   * format.
   */
  private draftFilterType(): number {
    let type: number = FilterType.Default | FilterType.ShowHidden;
    if (this.draftScope === 1) {
      type = type | RuleSearchScope.FullSearch;
    } else if (this.draftScope === 2) {
      type = type | RuleSearchScope.Creator;
    }
    // Upstream defaults to case-insensitive: the flag is set when the user has
    // NOT asked for case sensitivity.
    if (!this.draftCaseSensitive) {
      type = type | FilterType.CaseInsensitive;
    }
    return type;
  }

  private scopeOf(filterType: number): number {
    if ((filterType & RuleSearchScope.Creator) !== 0) {
      return 2;
    }
    if ((filterType & FilterType.FullSearch) !== 0) {
      return 1;
    }
    return 0;
  }

  private scopeLabel(scope: number): string {
    if (scope === 2) {
      return I18n.get('rules.creator');
    }
    if (scope === 1) {
      return I18n.get('rules.fullSearch');
    }
    return I18n.get('rules.title');
  }

  private resetDraft(): void {
    this.draftScope = 0;
    this.draftMatch = true;
    this.draftRegex = '';
    this.draftCaseSensitive = false;
    this.draftActions = [];
    this.draftError = '';
  }

  /**
   * Select or clear an action key, keeping at most one per action letter.
   */
  private toggleAction(key: string): void {
    const prefix: string = key.substring(0, 1).concat('-');
    const next: string[] = [];
    let alreadySelected: boolean = false;
    for (const existing of this.draftActions) {
      if (existing === key) {
        alreadySelected = true;
        continue;
      }
      if (existing.startsWith(prefix)) {
        continue;
      }
      next.push(existing);
    }
    if (!alreadySelected) {
      next.push(key);
    }
    this.draftActions = next;
    this.draftError = '';
  }

  private hasAction(key: string): boolean {
    return this.draftActions.indexOf(key) >= 0;
  }

  private async addRule(): Promise<void> {
    const patternError: string = this.validatePattern();
    if (patternError.length > 0) {
      this.draftError = I18n.get(patternError);
      return;
    }
    if (this.draftActions.length === 0) {
      this.draftError = I18n.get('app.ruleActionRequired');
      return;
    }

    this.rules.push(this.buildDraft());

    await this.persist();
    this.resetDraft();
    this.editing = false;
    this.status = I18n.get('app.ruleAdded');
  }

  /** Error key for the draft's pattern, or '' when it is usable. */
  private validatePattern(): string {
    if (this.draftRegex.length === 0) {
      return 'app.rulePatternRequired';
    }
    const flags: string = this.draftCaseSensitive ? '' : 'i';
    if (!RuleEngine.validateRegex(this.draftRegex, flags)) {
      return 'app.ruleInvalidRegex';
    }
    return '';
  }

  /** The rule the draft currently describes. */
  private buildDraft(): SourceRule {
    const rule: SourceRule = new SourceRule();
    rule.regex = this.draftRegex;
    rule.filterType = this.draftFilterType();
    rule.match = this.draftMatch;
    rule.actions = this.draftActions;
    return rule;
  }

  /**
   * Dry-run the draft over the articles already loaded.
   *
   * Matching does not depend on the actions, so this only needs a usable
   * pattern — the original's "Test rules" behaves the same way.
   */
  private async testDraft(): Promise<void> {
    const patternError: string = this.validatePattern();
    if (patternError.length > 0) {
      this.draftError = I18n.get(patternError);
      return;
    }
    this.draftError = '';
    const outcome: RuleTestResult = await this.onTestRule(this.buildDraft());
    this.status = I18n.get('app.ruleTestResult', new Map<string, string | number>([
      ['matched', outcome.matched], ['total', outcome.total]
    ]));
  }

  private async deleteRule(index: number): Promise<void> {
    if (index < 0 || index >= this.rules.length) {
      return;
    }
    this.rules.splice(index, 1);
    await this.persist();
    this.status = I18n.get('app.ruleRemoved');
  }

  private async moveRule(index: number, delta: number): Promise<void> {
    const target: number = index + delta;
    if (target < 0 || target >= this.rules.length) {
      return;
    }
    const moved: SourceRule = this.rules[index];
    this.rules.splice(index, 1);
    this.rules.splice(target, 0, moved);
    await this.persist();
  }

  /**
   * Human-readable one-line summary of a rule, used in the list.
   */
  private describe(rule: SourceRule): string {
    const scope: string = this.scopeLabel(this.scopeOf(rule.filterType));
    const verb: string = rule.match ? I18n.get('rules.match') : I18n.get('rules.notMatch');
    return scope.concat(' ').concat(verb).concat(' /').concat(rule.regex).concat('/');
  }

  /**
   * Action chips for a stored rule, honouring stored false values.
   */
  private actionLabels(rule: SourceRule): string[] {
    const labels: string[] = [];
    const map: Map<string, boolean> = RuleActions.fromKeys(rule.actions);
    map.forEach((flag: boolean, action: string) => {
      switch (action) {
        case ItemAction.Read:
          labels.push(flag ? I18n.get('article.markRead') : I18n.get('article.markUnread'));
          break;
        case ItemAction.Star:
          labels.push(flag ? I18n.get('article.star') : I18n.get('article.unstar'));
          break;
        case ItemAction.Hide:
          labels.push(flag ? I18n.get('article.hide') : I18n.get('article.unhide'));
          break;
        case ItemAction.Notify:
          labels.push(flag ? I18n.get('article.notify') : I18n.get('article.dontNotify'));
          break;
        default:
          break;
      }
    });
    return labels;
  }

  /* --------------------------------------------------------------- view */

  build() {
    Column() {
      // Header
      Row() {
        Image($r('app.media.ic_rule')).width(18).height(18).fillColor('#0078D4')
        Text(I18n.get('settings.rules'))
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor())
          .margin({ left: 8 })
          .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_close')).width(16).height(16).fillColor(this.secondaryColor())
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
      .padding({ bottom: 12 })

      Divider().color(this.dividerColor()).strokeWidth(1)

      if (this.feeds.length === 0) {
        Column() {
          Text(I18n.get('app.noSubscriptions'))
            .fontSize(15)
            .fontColor(this.secondaryColor())
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Text(I18n.get('rules.source'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.secondaryColor())
              .width('100%')
              .margin({ top: 14, bottom: 8 })

            /*
             * `rules.selectSource` is the *placeholder* of the original's
             * source dropdown, not a caption: upstream passes it as the
             * dropdown's placeholder, so it belongs in `.value()` for the
             * "nothing chosen yet" state. It was previously shown as a hint in
             * the empty state, where it also read wrong — "Select a source"
             * when there are no subscriptions to select from.
             */
            Select(this.feedOptions())
              .selected(this.feedIndex)
              .value(this.currentFeed() !== null
                ? this.currentFeed()!.title : I18n.get('rules.selectSource'))
              .themedSelect(this.textColor())
              .width('100%')
              .enabled(!this.editing)
              .onSelect((index: number) => {
                this.feedIndex = index;
                this.status = '';
                this.reload();
              })

            Row() {
              Text(I18n.get('rules.hint'))
                .fontSize(11)
                .fontColor(this.secondaryColor())
                .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 10 })

            // Existing rules
            if (this.loading) {
              Row() {
                LoadingProgress().width(20).height(20).color('#0078D4')
                Text(I18n.get('app.loading'))
                  .fontSize(12)
                  .fontColor(this.secondaryColor())
                  .margin({ left: 8 })
              }
              .width('100%')
              .margin({ top: 20 })
            } else if (this.currentFeed() !== null && this.rules.length === 0) {
              Row() {
                Text(I18n.get('app.noRules'))
                  .fontSize(13)
                  .fontColor(this.secondaryColor())
              }
              .width('100%')
              .padding({ top: 18, bottom: 6 })
            } else {
              ForEach(this.rules, (rule: SourceRule, index: number) => {
                Column() {
                  Row() {
                    Text((index + 1).toString())
                      .fontSize(11)
                      .fontColor(this.secondaryColor())
                      .width(18)
                      .textAlign(TextAlign.Center)

                    Column() {
                      Text(this.describe(rule))
                        .fontSize(13)
                        .fontColor(this.textColor())
                        .width('100%')
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      Row() {
                        ForEach(this.actionLabels(rule), (label: string) => {
                          Text(label)
                            .fontSize(11)
                            .fontColor('#0078D4')
                            .backgroundColor(this.isDarkMode ? '#1F2A37' : '#EFF6FC')
                            .borderRadius(10)
                            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                            .margin({ right: 6, top: 6 })
                        }, (label: string) => label)
                      }
                      .width('100%')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .margin({ left: 8 })

                    Button({ type: ButtonType.Circle }) {
                      Image($r('app.media.ic_up')).width(14).height(14).fillColor(this.secondaryColor())
                    }
                    .width(28)
                    .height(28)
                    .responseRegion(TouchTarget.region(28))
                    .backgroundColor(Color.Transparent)
                    .enabled(index > 0)
                    .opacity(index > 0 ? 1 : 0.3)
                    .onClick(() => {
                      this.moveRule(index, -1);
                    })

                    Button({ type: ButtonType.Circle }) {
                      Image($r('app.media.ic_down')).width(14).height(14).fillColor(this.secondaryColor())
                    }
                    .width(28)
                    .height(28)
                    .responseRegion(TouchTarget.region(28))
                    .backgroundColor(Color.Transparent)
                    .enabled(index < this.rules.length - 1)
                    .opacity(index < this.rules.length - 1 ? 1 : 0.3)
                    .onClick(() => {
                      this.moveRule(index, 1);
                    })

                    Button({ type: ButtonType.Circle }) {
                      Image($r('app.media.ic_trash')).width(14).height(14).fillColor('#D13438')
                    }
                    .width(28)
                    .height(28)
                    .responseRegion(TouchTarget.region(28))
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      this.deleteRule(index);
                    })
                  }
                  .width('100%')
                  .padding({ top: 10, bottom: 10 })
                  .alignItems(VerticalAlign.Top)

                  Divider().color(this.dividerColor()).strokeWidth(1)
                }
                .width('100%')
              }, (rule: SourceRule, index: number) =>
              index.toString().concat('-').concat(rule.regex).concat('-')
                .concat(rule.actions.join(',')))
            }

            // Editor
            if (this.editing) {
              Column() {
                Text(I18n.get('rules.new'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.secondaryColor())
                  .width('100%')
                  .margin({ top: 16, bottom: 8 })

                Row() {
                  Text(I18n.get('rules.if'))
                    .fontSize(13)
                    .fontColor(this.secondaryColor())
                    .width(28)
                  Select([
                    { value: I18n.get('rules.title') },
                    { value: I18n.get('rules.fullSearch') },
                    { value: I18n.get('rules.creator') }
                  ])
                    .selected(this.draftScope)
                    .value(this.scopeLabel(this.draftScope))
                    .themedSelect(this.textColor())
                    .layoutWeight(1)
                    .onSelect((index: number) => {
                      this.draftScope = index;
                      this.draftError = '';
                    })
                }
                .width('100%')

                Row() {
                  Select([
                    { value: I18n.get('rules.match') },
                    { value: I18n.get('rules.notMatch') }
                  ])
                    .selected(this.draftMatch ? 0 : 1)
                    .value(this.draftMatch ? I18n.get('rules.match') : I18n.get('rules.notMatch'))
                    .themedSelect(this.textColor())
                    .layoutWeight(1)
                    .margin({ left: 28 })
                    .onSelect((index: number) => {
                      this.draftMatch = index === 0;
                      this.draftError = '';
                    })
                }
                .width('100%')
                .margin({ top: 10 })

                TextInput({
                  placeholder: I18n.get('app.ruleRegex'),
                  text: this.draftRegex
                })
                  .width('100%')
                  .height(40)
                  .fontSize(13)
                  .backgroundColor(this.fieldColor())
                  .fontColor(this.textColor())
                  .placeholderColor(this.secondaryColor())
                  .margin({ top: 10 })
                  .onChange((value: string) => {
                    this.draftRegex = value;
                    this.draftError = '';
                  })

                Row() {
                  Text(I18n.get('context.caseSensitive'))
                    .fontSize(13)
                    .fontColor(this.textColor())
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.draftCaseSensitive })
                    .selectedColor('#0078D4')
                    .onChange((isOn: boolean) => {
                      this.draftCaseSensitive = isOn;
                    })
                }
                .width('100%')
                .margin({ top: 10 })

                Text(I18n.get('rules.then'))
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.secondaryColor())
                  .width('100%')
                  .margin({ top: 16, bottom: 8 })

                // Four action groups, each with a true/false pair. Selecting
                // one replaces the other, matching upstream's one-key-per-
                // action rule. Chips are inlined rather than delegated to a
                // @Builder because builders do not reliably re-render on the
                // state they close over.
                Row() {
                  Text(I18n.get('app.readState')).fontSize(12).fontColor(this.secondaryColor()).width(96)
                  Text(I18n.get('article.markRead'))
                    .fontSize(12)
                    .fontColor(this.hasAction('r-true') ? Color.White : this.textColor())
                    .backgroundColor(this.hasAction('r-true') ? '#0078D4' : this.fieldColor())
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .onClick(() => {
                      this.toggleAction('r-true');
                    })
                  Text(I18n.get('article.markUnread'))
                    .fontSize(12)
                    .fontColor(this.hasAction('r-false') ? Color.White : this.textColor())
                    .backgroundColor(this.hasAction('r-false') ? '#0078D4' : this.fieldColor())
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.toggleAction('r-false');
                    })
                }
                .width('100%')
                .margin({ bottom: 8 })

                Row() {
                  Text(I18n.get('article.star')).fontSize(12).fontColor(this.secondaryColor()).width(96)
                  Text(I18n.get('article.star'))
                    .fontSize(12)
                    .fontColor(this.hasAction('s-true') ? Color.White : this.textColor())
                    .backgroundColor(this.hasAction('s-true') ? '#0078D4' : this.fieldColor())
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .onClick(() => {
                      this.toggleAction('s-true');
                    })
                  Text(I18n.get('article.unstar'))
                    .fontSize(12)
                    .fontColor(this.hasAction('s-false') ? Color.White : this.textColor())
                    .backgroundColor(this.hasAction('s-false') ? '#0078D4' : this.fieldColor())
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.toggleAction('s-false');
                    })
                }
                .width('100%')
                .margin({ bottom: 8 })

                Row() {
                  Text(I18n.get('app.visibility')).fontSize(12).fontColor(this.secondaryColor()).width(96)
                  Text(I18n.get('article.hide'))
                    .fontSize(12)
                    .fontColor(this.hasAction('h-true') ? Color.White : this.textColor())
                    .backgroundColor(this.hasAction('h-true') ? '#0078D4' : this.fieldColor())
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .onClick(() => {
                      this.toggleAction('h-true');
                    })
                  Text(I18n.get('article.unhide'))
                    .fontSize(12)
                    .fontColor(this.hasAction('h-false') ? Color.White : this.textColor())
                    .backgroundColor(this.hasAction('h-false') ? '#0078D4' : this.fieldColor())
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.toggleAction('h-false');
                    })
                }
                .width('100%')
                .margin({ bottom: 8 })

                Row() {
                  Text(I18n.get('app.notification')).fontSize(12).fontColor(this.secondaryColor()).width(96)
                  Text(I18n.get('article.notify'))
                    .fontSize(12)
                    .fontColor(this.hasAction('n-true') ? Color.White : this.textColor())
                    .backgroundColor(this.hasAction('n-true') ? '#0078D4' : this.fieldColor())
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .onClick(() => {
                      this.toggleAction('n-true');
                    })
                  Text(I18n.get('article.dontNotify'))
                    .fontSize(12)
                    .fontColor(this.hasAction('n-false') ? Color.White : this.textColor())
                    .backgroundColor(this.hasAction('n-false') ? '#0078D4' : this.fieldColor())
                    .borderRadius(12)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.toggleAction('n-false');
                    })
                }
                .width('100%')

                if (this.draftError.length > 0) {
                  Text(this.draftError)
                    .fontSize(12)
                    .fontColor('#D13438')
                    .width('100%')
                    .margin({ top: 10 })
                }

                Row() {
                  Button(I18n.get('cancel'))
                    .fontSize(13)
                    .fontColor(this.textColor())
                    .backgroundColor(this.fieldColor())
                    .layoutWeight(1)
                    .onClick(() => {
                      this.resetDraft();
                      this.editing = false;
                    })

                  Button(I18n.get('rules.test'))
                    .fontSize(13)
                    .fontColor(this.textColor())
                    .backgroundColor(this.fieldColor())
                    .layoutWeight(1)
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.testDraft();
                    })

                  Button(I18n.get('add'))
                    .fontSize(13)
                    .fontColor(Color.White)
                    .backgroundColor('#0078D4')
                    .layoutWeight(1)
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.addRule();
                    })
                }
                .width('100%')
                .margin({ top: 14 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            if (this.status.length > 0) {
              Row() {
                Text(this.status)
                  .fontSize(12)
                  .fontColor('#0078D4')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(8)
              .borderRadius(4)
              .backgroundColor(this.isDarkMode ? '#1F2A37' : '#EFF6FC')
              .margin({ top: 14 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }

      Divider().color(this.dividerColor()).strokeWidth(1).margin({ top: 12 })

      Row() {
        Button(I18n.get('close'))
          .fontSize(13)
          .fontColor(this.textColor())
          .backgroundColor(this.fieldColor())
          .layoutWeight(1)
          .onClick(() => {
            this.closeDialog();
          })

        // A draft with no source would be silently dropped by `persist()`.
        if (!this.editing && this.currentFeed() !== null) {
          Button(I18n.get('rules.new'))
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor('#0078D4')
            .layoutWeight(1)
            .margin({ left: 8 })
            .onClick(() => {
              this.resetDraft();
              this.editing = true;
              this.status = '';
            })
        }
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width(600)
    .height(720)
    .padding(24)
    .backgroundColor(this.surfaceColor())
    .borderRadius(10)
  }
}
