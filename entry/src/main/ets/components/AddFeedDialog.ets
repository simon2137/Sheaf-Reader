import { FeedGroup, AddFeedResult } from '../model/Models';
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
 * Modal dialog for subscribing to a new feed.
 */
@CustomDialog
export struct AddFeedDialog {
  @State feedUrl: string = '';
  @State feedName: string = '';
  @State selectedGroupIndex: number = 0;
  @State isAdding: boolean = false;
  @State errorMessage: string = '';
  // 主题走 AppStorage（不是 @Prop/@State）：弹窗内容由 CustomDialogController 构建，
  // 父组件重渲染不会重建它；原来声明成 @State 更收不到父组件的值，深色下一直是浅色。
  @StorageProp('sheafReaderIsDarkMode') isDarkMode: boolean = false;
  groups: FeedGroup[] = [];
  onConfirm: (url: string, name: string, groupId: number) => Promise<AddFeedResult> =
    async () => {
      return { success: false, message: 'feed_invalid', feed: null };
    };
  controller?: CustomDialogController;

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

  private groupOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: I18n.get('app.noGroup') }];
    for (const group of this.groups) {
      options.push({ value: group.name });
    }
    return options;
  }

  private selectedGroupId(): number {
    if (this.selectedGroupIndex <= 0 || this.selectedGroupIndex > this.groups.length) {
      return -1;
    }
    return this.groups[this.selectedGroupIndex - 1].id;
  }

  private localize(messageKey: string): string {
    if (messageKey === 'feed_added') {
      return I18n.get('app.feedAdded');
    }
    if (messageKey === 'feed_exists') {
      return I18n.get('app.feedExists');
    }
    if (messageKey === 'feed_invalid') {
      return I18n.get('app.feedInvalid');
    }
    return messageKey;
  }

  build() {
    Column() {
      Row() {
        Text(I18n.get('sources.add'))
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

      Text(I18n.get('sources.inputUrl'))
        .fontSize(12)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 6 })

      TextInput({ placeholder: 'https://example.com/feed.xml', text: this.feedUrl })
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor(this.isDarkMode ? '#323130' : '#F3F2F1')
        .fontColor(this.textColor())
        .placeholderColor(this.secondaryColor())
        .onChange((value: string) => {
          this.feedUrl = value;
          this.errorMessage = '';
        })
        .margin({ bottom: 14 })

      Text(I18n.get('sources.name'))
        .fontSize(12)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 6 })

      TextInput({ placeholder: I18n.get('app.myFeed'), text: this.feedName })
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor(this.isDarkMode ? '#323130' : '#F3F2F1')
        .fontColor(this.textColor())
        .placeholderColor(this.secondaryColor())
        .onChange((value: string) => {
          this.feedName = value;
        })
        .margin({ bottom: 14 })

      Text(I18n.get('groups.group'))
        .fontSize(12)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 6 })

      Select(this.groupOptions())
        .selected(this.selectedGroupIndex)
        .value(this.selectedGroupIndex === 0 ? I18n.get('app.noGroup')
          : this.groups[this.selectedGroupIndex - 1].name)
        .themedSelect(this.textColor())
        .width('100%')
        .onSelect((index: number) => {
          this.selectedGroupIndex = index;
        })
        .margin({ bottom: 16 })

      if (this.errorMessage.length > 0) {
        Row() {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor('#D13438')
            .layoutWeight(1)
        }
        .width('100%')
        .padding(8)
        .borderRadius(4)
        .backgroundColor(this.isDarkMode ? '#442726' : '#FDE7E9')
        .margin({ bottom: 12 })
      }

      Divider().color(this.dividerColor()).strokeWidth(1).margin({ bottom: 12 })

      Row() {
        Button(I18n.get('cancel'))
          .fontSize(14)
          .fontColor(this.textColor())
          .backgroundColor(this.isDarkMode ? '#323130' : '#F3F2F1')
          .layoutWeight(1)
          .onClick(() => {
            this.closeDialog();
          })

        Button(this.isAdding ? I18n.get('app.adding') : I18n.get('sources.add'))
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#0078D4')
          .enabled(!this.isAdding)
          .layoutWeight(1)
          .margin({ left: 10 })
          .onClick(async () => {
            if (this.feedUrl.trim().length === 0) {
              this.errorMessage = I18n.get('app.enterFeedUrl');
              return;
            }
            this.isAdding = true;
            this.errorMessage = '';
            const result: AddFeedResult =
              await this.onConfirm(this.feedUrl.trim(), this.feedName.trim(), this.selectedGroupId());
            this.isAdding = false;
            if (result.success) {
              this.closeDialog();
            } else {
              this.errorMessage = this.localize(result.message);
            }
          })
      }
      .width('100%')
    }
    .width(420)
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
