import { I18n } from '../utils/I18n';

/**
 * Dialog for creating a feed group.
 */
@CustomDialog
export struct GroupDialog {
  @Prop isDarkMode: boolean;
  @State groupName: string = '';
  @State errorMessage: string = '';
  existingNames: string[] = [];
  onCreate: (name: string) => void = () => {
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

  private closeDialog(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }

  build() {
    Column() {
      Text(I18n.get('groups.create'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textColor())
        .width('100%')
        .margin({ bottom: 8 })

      Text(I18n.get('groups.enterName'))
        .fontSize(12)
        .fontColor(this.secondaryColor())
        .width('100%')
        .margin({ bottom: 16 })

      TextInput({ placeholder: I18n.get('app.groupNameHint'), text: this.groupName })
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor(this.isDarkMode ? '#323130' : '#F3F2F1')
        .fontColor(this.textColor())
        .placeholderColor(this.secondaryColor())
        .onChange((value: string) => {
          this.groupName = value;
          this.errorMessage = '';
        })
        .margin({ bottom: 12 })

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor('#D13438')
          .width('100%')
          .margin({ bottom: 12 })
      }

      Row() {
        Button(I18n.get('cancel'))
          .fontSize(14)
          .fontColor(this.textColor())
          .backgroundColor(this.isDarkMode ? '#323130' : '#F3F2F1')
          .layoutWeight(1)
          .onClick(() => {
            this.closeDialog();
          })

        Button(I18n.get('create'))
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#0078D4')
          .layoutWeight(1)
          .margin({ left: 10 })
          .onClick(() => {
            const name: string = this.groupName.trim();
            if (name.length === 0) {
              this.errorMessage = I18n.get('groups.enterName');
              return;
            }
            if (this.existingNames.indexOf(name) >= 0) {
              this.errorMessage = I18n.get('app.groupNameExists');
              return;
            }
            this.onCreate(name);
            this.closeDialog();
          })
      }
      .width('100%')
    }
    .width(400)
    .padding(24)
    .backgroundColor(this.surfaceColor())
    .borderRadius(10)
  }
}
