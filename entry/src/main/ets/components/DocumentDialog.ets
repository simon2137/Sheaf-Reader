import { I18n } from '../utils/I18n';

/**
 * Scrollable plain-text viewer for the bundled legal documents.
 *
 * The caller reads the file from `rawfile` (see `BundledText`) and passes the
 * text in, so this dialog does no I/O of its own and can be rebuilt cheaply
 * when the language or theme changes.
 */
@CustomDialog
export struct DocumentDialog {
  // 主题走 AppStorage（不是 @Prop），理由同其它弹窗：CustomDialogController
  // 构建一次就固定了 builder，切主题时 @Prop 会停在旧值。
  @StorageProp('sheafReaderIsDarkMode') isDarkMode: boolean = false;
  title: string = '';
  body: string = '';
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

  private closeDialog(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textColor())
        .width('100%')

      Divider()
        .color(this.dividerColor())
        .strokeWidth(1)
        .margin({ top: 12, bottom: 12 })

      Scroll() {
        Text(this.body.length > 0 ? this.body : I18n.get('app.loading'))
          .fontSize(12)
          .lineHeight(19)
          .fontColor(this.secondaryColor())
          .width('100%')
          .textAlign(TextAlign.Start)
          // 滚动条占的是 Scroll 盒内的右边缘，正文占满宽度会被它压住。
          .padding({ right: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)

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
    .width(640)
    .height(720)
    .padding(24)
    .backgroundColor(this.surfaceColor())
    .borderRadius(10)
  }
}
