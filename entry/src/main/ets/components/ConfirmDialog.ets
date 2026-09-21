/**
 * Simple yes/no confirmation dialog.
 */
import { I18n } from '../utils/I18n';

@CustomDialog
export struct ConfirmDialog {
  @Prop isDarkMode: boolean;
  @Prop title: string;
  @Prop message: string;
  @Prop confirmLabel: string;
  @Prop destructive: boolean;
  onConfirm: () => void = () => {
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

  build() {
    Column() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textColor())
        .width('100%')
        .margin({ bottom: 10 })

      Text(this.message)
        .fontSize(13)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 22 })

      Row() {
        Button(I18n.get('cancel'))
          .fontSize(14)
          .fontColor(this.textColor())
          .backgroundColor(this.isDarkMode ? '#323130' : '#F3F2F1')
          .layoutWeight(1)
          .onClick(() => {
            this.closeDialog();
          })

        Button(this.confirmLabel)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(this.destructive ? '#D13438' : '#0078D4')
          .layoutWeight(1)
          .margin({ left: 10 })
          .onClick(() => {
            this.onConfirm();
            this.closeDialog();
          })
      }
      .width('100%')
    }
    .width(380)
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
