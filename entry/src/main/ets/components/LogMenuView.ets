import { AppLog, AppLogType } from '../model/Models';
import { AppStore } from '../state/AppStore';
import { I18n } from '../utils/I18n';
import { TouchTarget } from '../utils/TouchTarget';

/**
 * Notification log panel, mirroring the original's `LogMenu`.
 *
 * Records what the app did in the background: per-source fetch failures (with
 * the reason), successful fetches with a count, sync failures, and articles
 * whose rules asked for a notification. Article entries are clickable.
 */
@Component
export struct LogMenuView {
  @ObjectLink store: AppStore;
  onOpenArticle: (articleId: number) => void = () => {
  };
  onClose: () => void = () => {
  };

  private textColor(): string {
    return this.store.isDarkMode ? '#E8E6E3' : '#323130';
  }

  private secondaryColor(): string {
    return this.store.isDarkMode ? '#A19F9D' : '#605E5C';
  }

  private surfaceColor(): string {
    return this.store.isDarkMode ? '#252423' : '#FFFFFF';
  }

  private dividerColor(): string {
    return this.store.isDarkMode ? '#3B3A39' : '#EDEBE9';
  }

  /** Named to avoid clashing with CustomComponent's built-in `borderColor`. */
  private panelBorder(): string {
    return this.store.isDarkMode ? '#4A4845' : '#E1DFDD';
  }

  /** Newest first, matching the original's `.reverse()`. */
  private newestFirst(): AppLog[] {
    const copy: AppLog[] = this.store.logs.slice();
    copy.reverse();
    return copy;
  }

  private iconFor(entry: AppLog): Resource {
    if (entry.type === AppLogType.Failure || entry.type === AppLogType.Warning) {
      return $r('app.media.ic_warning');
    }
    if (entry.type === AppLogType.Article) {
      return $r('app.media.ic_article');
    }
    return $r('app.media.ic_info');
  }

  private colorFor(entry: AppLog): string {
    if (entry.type === AppLogType.Failure) {
      return '#D13438';
    }
    if (entry.type === AppLogType.Warning) {
      return '#FFB900';
    }
    if (entry.type === AppLogType.Article) {
      return '#0078D4';
    }
    return this.secondaryColor();
  }

  private relativeTime(timestamp: number): string {
    const diff: number = Date.now() - timestamp;
    const minutes: number = Math.floor(diff / 60000);
    if (minutes < 1) {
      return 'now';
    }
    if (minutes < 60) {
      return minutes.toString() + 'm';
    }
    const hours: number = Math.floor(minutes / 60);
    if (hours < 24) {
      return hours.toString() + 'h';
    }
    return Math.floor(hours / 24).toString() + 'd';
  }

  build() {
    Column() {
      // Header
      Row() {
        Image($r('app.media.ic_notify'))
          .width(16)
          .height(16)
          .fillColor(this.textColor())
        Text(I18n.get('nav.notifications'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor())
          .margin({ left: 8 })
          .layoutWeight(1)

        if (this.store.logs.length > 0) {
          Text(I18n.get('app.clear'))
            .fontSize(12)
            .fontColor('#0078D4')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => {
              this.store.clearLogs();
            })
        }

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
          this.onClose();
        })
      }
      .width('100%')
      .padding({ left: 14, right: 8, top: 10, bottom: 10 })

      Divider().color(this.dividerColor()).strokeWidth(1)

      if (this.store.logs.length === 0) {
        Column() {
          Image($r('app.media.ic_notify'))
            .width(28)
            .height(28)
            .fillColor(this.secondaryColor())
            .opacity(0.4)
          Text(I18n.get('log.empty'))
            .fontSize(13)
            .fontColor(this.secondaryColor())
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.newestFirst(), (entry: AppLog, index: number) => {
            ListItem() {
              Row() {
                Image(this.iconFor(entry))
                  .width(15)
                  .height(15)
                  .fillColor(this.colorFor(entry))
                  .margin({ top: 2 })
                  .alignSelf(ItemAlign.Start)

                Column() {
                  Text(entry.title)
                    .fontSize(13)
                    .fontWeight(entry.refersToArticle() ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(entry.refersToArticle() ? '#0078D4' : this.textColor())
                    .width('100%')
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  if (entry.details.length > 0) {
                    Text(entry.details)
                      .fontSize(11)
                      .fontColor(this.secondaryColor())
                      .width('100%')
                      .maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 8 })

                Text(this.relativeTime(entry.time))
                  .fontSize(11)
                  .fontColor(this.secondaryColor())
                  .margin({ left: 6 })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 9, bottom: 9 })
              .alignItems(VerticalAlign.Top)
              .onClick(() => {
                if (entry.refersToArticle()) {
                  this.onOpenArticle(entry.iid);
                }
              })
            }
          }, (entry: AppLog, index: number) =>
          entry.time.toString().concat('-').concat(index.toString())
            .concat('-').concat(entry.title))
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({ strokeWidth: 1, color: this.dividerColor(), startMargin: 14, endMargin: 14 })
      }
    }
    .width(400)
    .height(340)
    .backgroundColor(this.surfaceColor())
    .borderRadius(8)
    .border({ width: 1, color: this.panelBorder() })
    .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
  }
}
