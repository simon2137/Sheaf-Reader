import { I18n } from '../utils/I18n';
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
 * Per-source settings, mirroring the original's source settings panel:
 * name, fetch frequency limit, default open target, text direction and
 * "hide in all articles", plus deleting the source.
 *
 * Every label comes from an upstream key, so both bundled locales cover it.
 */
@CustomDialog
export struct FeedSettingsDialog {
  /** Current values, copied into editable state in `aboutToAppear`. */
  initialTitle: string = '';
  initialFetchFrequency: number = 0;
  initialOpenTarget: number = 0;
  initialTextDir: number = 0;
  initialHidden: boolean = false;
  /** True when the source is provided by a sync service, which owns its name. */
  serviceManaged: boolean = false;
  /**
   * Names of the groups this source can be moved into, and the index of the
   * group it is in now (`-1` when ungrouped).
   *
   * This is upstream's "selected source" flow from
   * `src/components/settings/groups.tsx`: `groups.selectedSource` above a
   * dropdown whose placeholder is `groups.chooseGroup`, plus a
   * `groups.addToGroup` button that is disabled until a target is picked.
   * Upstream hosts it in its groups tab; this port hosts it here, next to the
   * source's other settings.
   */
  groupNames: string[] = [];
  initialGroupIndex: number = -1;

  @State name: string = '';
  @State fetchFrequency: number = 0;
  @State openTarget: number = 0;
  @State textDir: number = 0;
  @State hidden: boolean = false;
  @State isDarkMode: boolean = false;
  @State confirmingDelete: boolean = false;
  @State isSaving: boolean = false;
  /** Target group picked in the dropdown; `-1` until one is chosen. */
  @State groupIndex: number = -1;

  onSave: (name: string, fetchFrequency: number, openTarget: number,
    textDir: number, hidden: boolean) => Promise<void> = async () => {
  };
  onDelete: () => Promise<void> = async () => {
  };
  /** Move the source into `groupNames[index]`, or out of every group (`-1`). */
  onAssignGroup: (index: number) => Promise<void> = async () => {
  };
  controller?: CustomDialogController;

  aboutToAppear(): void {
    this.name = this.initialTitle;
    this.fetchFrequency = this.initialFetchFrequency;
    this.openTarget = this.initialOpenTarget;
    this.textDir = this.initialTextDir;
    this.hidden = this.initialHidden;
    this.groupIndex = this.initialGroupIndex;
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

  private fieldColor(): string {
    return this.isDarkMode ? '#323130' : '#F3F2F1';
  }

  private frequencyLabel(minutes: number): string {
    switch (minutes) {
      case 15:
      case 30:
        return I18n.get('time.minute', new Map<string, string | number>([['m', minutes]]));
      case 60:
        return I18n.get('time.hour', new Map<string, string | number>([['h', 1]]));
      case 120:
        return I18n.get('time.hour', new Map<string, string | number>([['h', 2]]));
      case 180:
        return I18n.get('time.hour', new Map<string, string | number>([['h', 3]]));
      case 360:
        return I18n.get('time.hour', new Map<string, string | number>([['h', 6]]));
      case 720:
        return I18n.get('time.hour', new Map<string, string | number>([['h', 12]]));
      default:
        return I18n.get('sources.unlimited');
    }
  }

  /** The original's per-source limits (`settings/sources.tsx`). */
  private frequencyValues(): number[] {
    return FetchSchedule.options(FetchSchedule.FREQUENCIES, this.fetchFrequency);
  }

  private frequencyOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const minutes of this.frequencyValues()) {
      options.push({ value: this.frequencyLabel(minutes) });
    }
    return options;
  }

  private frequencyIndex(): number {
    const index: number = this.frequencyValues().indexOf(this.fetchFrequency);
    return index < 0 ? 0 : index;
  }

  private openTargetLabel(target: number): string {
    switch (target) {
      case 1:
        return I18n.get('sources.loadWebpage');
      case 2:
        return I18n.get('openExternal');
      case 3:
        return I18n.get('article.loadFull');
      default:
        return I18n.get('sources.rssText');
    }
  }

  private openTargetOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let target = 0; target <= 3; target++) {
      options.push({ value: this.openTargetLabel(target) });
    }
    return options;
  }

  private textDirLabel(dir: number): string {
    switch (dir) {
      case 1:
        return I18n.get('article.RTL');
      case 2:
        return I18n.get('article.Vertical');
      default:
        return I18n.get('article.LTR');
    }
  }

  private textDirOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let dir = 0; dir <= 2; dir++) {
      options.push({ value: this.textDirLabel(dir) });
    }
    return options;
  }

  /** One option per group the source could join. */
  private groupOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const name of this.groupNames) {
      options.push({ value: name });
    }
    return options;
  }

  build() {
    Column() {
      Row() {
        Text(I18n.get('sources.editName'))
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
      .margin({ bottom: 18 })

      Text(I18n.get('sources.name'))
        .fontSize(12)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 6 })

      TextInput({ text: this.name })
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor(this.fieldColor())
        .fontColor(this.textColor())
        .enabled(!this.serviceManaged)
        .onChange((value: string) => {
          this.name = value;
        })
        .margin({ bottom: 14 })

      Text(I18n.get('sources.fetchFrequency'))
        .fontSize(12)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 6 })

      Select(this.frequencyOptions())
        .selected(this.frequencyIndex())
        .value(this.frequencyLabel(this.fetchFrequency))
        .themedSelect(this.textColor())
        .width('100%')
        .onSelect((index: number) => {
          this.fetchFrequency = this.frequencyValues()[index];
        })
        .margin({ bottom: 14 })

      Text(I18n.get('sources.openTarget'))
        .fontSize(12)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 6 })

      Select(this.openTargetOptions())
        .selected(this.openTarget)
        .value(this.openTargetLabel(this.openTarget))
        .themedSelect(this.textColor())
        .width('100%')
        .onSelect((index: number) => {
          this.openTarget = index;
        })
        .margin({ bottom: 14 })

      Text(I18n.get('article.textDir'))
        .fontSize(12)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 6 })

      Select(this.textDirOptions())
        .selected(this.textDir)
        .value(this.textDirLabel(this.textDir))
        .themedSelect(this.textColor())
        .width('100%')
        .onSelect((index: number) => {
          this.textDir = index;
        })
        .margin({ bottom: 14 })

      Row() {
        Column() {
          Text(I18n.get('sources.hidden'))
            .fontSize(14)
            .fontColor(this.textColor())
            .width('100%')
        }
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.hidden })
          .onChange((isOn: boolean) => {
            this.hidden = isOn;
          })
      }
      .width('100%')
      .margin({ bottom: 16 })

      /*
       * Upstream's "selected source" row: pick a target group, then confirm.
       * The dropdown shows its placeholder (`groups.chooseGroup`) until a group
       * is chosen, and the button stays disabled until then — both exactly as
       * `groups.tsx` does it.
       */
      Text(I18n.get('groups.selectedSource'))
        .fontSize(12)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 6 })

      Row() {
        Select(this.groupOptions())
          .selected(this.groupIndex)
          .value(this.groupIndex >= 0 && this.groupIndex < this.groupNames.length
            ? this.groupNames[this.groupIndex]
            : I18n.get('groups.chooseGroup'))
          .themedSelect(this.textColor())
          .layoutWeight(1)
          .onSelect((index: number) => {
            this.groupIndex = index;
          })

        Button(I18n.get('groups.addToGroup'))
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#0078D4')
          .enabled(this.groupIndex >= 0 && this.groupIndex !== this.initialGroupIndex)
          .margin({ left: 8 })
          .onClick(async () => {
            await this.onAssignGroup(this.groupIndex);
            this.initialGroupIndex = this.groupIndex;
          })
      }
      .width('100%')
      .margin({ bottom: 16 })

      if (this.confirmingDelete) {
        Text(I18n.get('sources.deleteWarning'))
          .fontSize(12)
          .fontColor('#D13438')
          .width('100%')
          .padding(8)
          .borderRadius(4)
          .backgroundColor(this.isDarkMode ? '#442726' : '#FDE7E9')
          .margin({ bottom: 12 })
      }

      Divider().color(this.dividerColor()).strokeWidth(1).margin({ bottom: 12 })

      Row() {
        Button(this.confirmingDelete ? I18n.get('delete') : I18n.get('sources.delete'))
          .fontSize(14)
          .fontColor(this.confirmingDelete ? Color.White : '#D13438')
          .backgroundColor(this.confirmingDelete
            ? '#D13438' : (this.isDarkMode ? '#323130' : '#F3F2F1'))
          .layoutWeight(1)
          .onClick(async () => {
            if (!this.confirmingDelete) {
              this.confirmingDelete = true;
              return;
            }
            await this.onDelete();
            this.closeDialog();
          })

        Button(this.isSaving ? I18n.get('app.saving') : I18n.get('app.save'))
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#0078D4')
          .enabled(!this.isSaving)
          .layoutWeight(1)
          .margin({ left: 10 })
          .onClick(async () => {
            if (this.name.trim().length === 0) {
              return;
            }
            this.isSaving = true;
            await this.onSave(this.name.trim(), this.fetchFrequency,
              this.openTarget, this.textDir, this.hidden);
            this.isSaving = false;
            this.closeDialog();
          })
      }
      .width('100%')
    }
    .width(460)
    .padding(24)
    .backgroundColor(this.surfaceColor())
    .borderRadius(10)
  }

  private closeDialog(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }
}
