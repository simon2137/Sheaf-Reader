import { Article, ViewConfigs } from '../model/Models';
import { Display } from '../utils/Display';
import { TouchTarget } from '../utils/TouchTarget';

/**
 * The four article card layouts, mirroring the original's
 * `cards/list-card`, `cards/compact-card`, `cards/magazine-card` and
 * `cards/default-card`.
 *
 * All of them honour the same display bits (`ViewConfigs`), which is what
 * makes the "Customised" view work: it is one of these layouts with
 * user-chosen bits.
 *
 * Note on fidelity: the original differentiates largely through CSS. ArkUI has
 * no equivalent cascade, so the structure and the display-bit semantics are
 * ported rather than the stylesheet.
 */

/* ------------------------------------------------------------------ List */

@Component
export struct ListCard {
  @ObjectLink article: Article;
  @Prop isSelected: boolean;
  @Prop isDarkMode: boolean;
  @Prop showCover: boolean;
  @Prop showSnippet: boolean;
  @Prop fadeRead: boolean;
  onItemClick: () => void = () => {
  };
  onStarClick: () => void = () => {
  };

  private textColor(): string {
    return this.isDarkMode ? '#E8E6E3' : '#323130';
  }

  private secondaryColor(): string {
    return this.isDarkMode ? '#A19F9D' : '#605E5C';
  }

  build() {
    Row() {
      Column()
        .width(3)
        .height(38)
        .borderRadius(2)
        .backgroundColor(this.article.read ? Color.Transparent : '#0078D4')
        .margin({ right: 10 })

      Column() {
        Text(this.article.title)
          .fontSize(14)
          .fontWeight(this.article.read ? FontWeight.Normal : FontWeight.Medium)
          .fontColor(this.textColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.showSnippet && this.article.snippet.length > 0) {
          Text(this.article.snippet)
            .fontSize(12)
            .fontColor(this.secondaryColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
            .width('100%')
        }

        Row() {
          Text(this.article.feedTitle)
            .fontSize(11)
            .fontColor('#0078D4')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(Display.relativeTime(this.article.published))
            .fontSize(11)
            .fontColor(this.secondaryColor())
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 5 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button({ type: ButtonType.Circle }) {
        Image(this.article.starred ? $r('app.media.ic_star') : $r('app.media.ic_star_outline'))
          .width(16)
          .height(16)
          .fillColor(this.article.starred ? '#FFB900' : this.secondaryColor())
      }
      .width(30)
      .height(30)
      .responseRegion(TouchTarget.region(30))
      .backgroundColor(Color.Transparent)
      .margin({ left: 4 })
      .onClick(() => {
        this.onStarClick();
      })

      if (this.showCover && this.article.imageUrl.length > 0) {
        Image(this.article.imageUrl)
          .width(56)
          .height(56)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
          .margin({ left: 6 })
          .alt($r('app.media.ic_rss'))
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.isSelected
      ? (this.isDarkMode ? '#323130' : '#EDEBE9') : Color.Transparent)
    .opacity(this.fadeRead && this.article.read ? 0.55 : 1)
    .onClick(() => {
      this.onItemClick();
    })
  }
}

/* --------------------------------------------------------------- Compact */

@Component
export struct CompactCard {
  @ObjectLink article: Article;
  @Prop isSelected: boolean;
  @Prop isDarkMode: boolean;
  @Prop fadeRead: boolean;
  onItemClick: () => void = () => {
  };

  private textColor(): string {
    return this.isDarkMode ? '#E8E6E3' : '#323130';
  }

  private secondaryColor(): string {
    return this.isDarkMode ? '#A19F9D' : '#605E5C';
  }

  build() {
    Row() {
      Column()
        .width(3)
        .height(16)
        .borderRadius(2)
        .backgroundColor(this.article.read ? Color.Transparent : '#0078D4')
        .margin({ right: 8 })

      // One dense line: title first, meta pushed to the right.
      Text(this.article.title)
        .fontSize(13)
        .fontWeight(this.article.read ? FontWeight.Normal : FontWeight.Medium)
        .fontColor(this.textColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.article.starred) {
        Image($r('app.media.ic_star'))
          .width(12)
          .height(12)
          .fillColor('#FFB900')
          .margin({ left: 6 })
      }

      Text(this.article.feedTitle)
        .fontSize(11)
        .fontColor(this.secondaryColor())
        .maxLines(1)
        .constraintSize({ maxWidth: 140 })
        .margin({ left: 10 })

      Text(Display.relativeTime(this.article.published))
        .fontSize(11)
        .fontColor(this.secondaryColor())
        .width(44)
        .textAlign(TextAlign.End)
        .margin({ left: 6 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.isSelected
      ? (this.isDarkMode ? '#323130' : '#EDEBE9') : Color.Transparent)
    .opacity(this.fadeRead && this.article.read ? 0.55 : 1)
    .onClick(() => {
      this.onItemClick();
    })
  }
}

/* -------------------------------------------------------------- Magazine */

@Component
export struct MagazineCard {
  @ObjectLink article: Article;
  @Prop isSelected: boolean;
  @Prop isDarkMode: boolean;
  @Prop showCover: boolean;
  @Prop showSnippet: boolean;
  @Prop fadeRead: boolean;
  onItemClick: () => void = () => {
  };
  onStarClick: () => void = () => {
  };

  private textColor(): string {
    return this.isDarkMode ? '#E8E6E3' : '#323130';
  }

  private secondaryColor(): string {
    return this.isDarkMode ? '#A19F9D' : '#605E5C';
  }

  build() {
    Column() {
      // A wide cover across the top, the defining trait of this layout.
      if (this.showCover && this.article.imageUrl.length > 0) {
        Image(this.article.imageUrl)
          .width('100%')
          .height(150)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .alt($r('app.media.ic_rss'))
          .margin({ bottom: 10 })
      }

      Text(this.article.title)
        .fontSize(18)
        .fontWeight(this.article.read ? FontWeight.Normal : FontWeight.Bold)
        .fontColor(this.textColor())
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.showSnippet && this.article.snippet.length > 0) {
        Text(this.article.snippet)
          .fontSize(13)
          .fontColor(this.secondaryColor())
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
          .width('100%')
      }

      Row() {
        Text(this.article.feedTitle)
          .fontSize(12)
          .fontColor('#0078D4')
          .maxLines(1)
          .layoutWeight(1)

        Text(Display.shortDate(this.article.published))
          .fontSize(12)
          .fontColor(this.secondaryColor())
          .margin({ left: 8 })

        Button({ type: ButtonType.Circle }) {
          Image(this.article.starred ? $r('app.media.ic_star') : $r('app.media.ic_star_outline'))
            .width(15)
            .height(15)
            .fillColor(this.article.starred ? '#FFB900' : this.secondaryColor())
        }
        .width(26)
        .height(26)
        .responseRegion(TouchTarget.region(26))
        .backgroundColor(Color.Transparent)
        .margin({ left: 4 })
        .onClick(() => {
          this.onStarClick();
        })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.isSelected
      ? (this.isDarkMode ? '#323130' : '#EDEBE9') : Color.Transparent)
    .opacity(this.fadeRead && this.article.read ? 0.55 : 1)
    .onClick(() => {
      this.onItemClick();
    })
  }
}

/* ----------------------------------------------------------------- Cards */

@Component
export struct GridCard {
  @ObjectLink article: Article;
  @Prop isSelected: boolean;
  @Prop isDarkMode: boolean;
  @Prop showSnippet: boolean;
  @Prop fadeRead: boolean;
  onItemClick: () => void = () => {
  };
  onStarClick: () => void = () => {
  };

  private textColor(): string {
    return this.isDarkMode ? '#E8E6E3' : '#323130';
  }

  private secondaryColor(): string {
    return this.isDarkMode ? '#A19F9D' : '#605E5C';
  }

  private surfaceColor(): string {
    return this.isDarkMode ? '#252423' : '#FFFFFF';
  }

  /** Named to avoid clashing with CustomComponent's built-in `borderColor`. */
  private cardBorder(): string {
    return this.isDarkMode ? '#3B3A39' : '#E1DFDD';
  }

  build() {
    Column() {
      // Fixed-height media area keeps rows aligned whether or not a card has
      // an image, matching the original's uniform 280x304 grid cells.
      Stack() {
        if (this.article.imageUrl.length > 0) {
          Image(this.article.imageUrl)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.ic_rss'))
        } else {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.isDarkMode ? '#323130' : '#F3F2F1')
          Image($r('app.media.ic_rss'))
            .width(28)
            .height(28)
            .fillColor(this.secondaryColor())
            .opacity(0.5)
        }

        if (!this.article.read) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor('#0078D4')
            .position({ x: 8, y: 8 })
        }
      }
      .width('100%')
      .height(120)

      Column() {
        Text(this.article.title)
          .fontSize(13)
          .fontWeight(this.article.read ? FontWeight.Normal : FontWeight.Medium)
          .fontColor(this.textColor())
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.showSnippet && this.article.snippet.length > 0) {
          Text(this.article.snippet)
            .fontSize(11)
            .fontColor(this.secondaryColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
            .width('100%')
        }

        Blank()

        Row() {
          Text(this.article.feedTitle)
            .fontSize(10)
            .fontColor('#0078D4')
            .maxLines(1)
            .layoutWeight(1)

          Button({ type: ButtonType.Circle }) {
            Image(this.article.starred ? $r('app.media.ic_star') : $r('app.media.ic_star_outline'))
              .width(13)
              .height(13)
              .fillColor(this.article.starred ? '#FFB900' : this.secondaryColor())
          }
          .width(22)
          .height(22)
          .responseRegion(TouchTarget.region(22))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onStarClick();
          })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(8)
    }
    .width('100%')
    .height(230)
    .backgroundColor(this.surfaceColor())
    .borderRadius(6)
    .border({
      width: this.isSelected ? 2 : 1,
      color: this.isSelected ? '#0078D4' : this.cardBorder()
    })
    .clip(true)
    .opacity(this.fadeRead && this.article.read ? 0.55 : 1)
    .onClick(() => {
      this.onItemClick();
    })
  }
}
