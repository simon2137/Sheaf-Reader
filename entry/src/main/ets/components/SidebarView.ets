import { Feed, FeedGroup, NavigationTarget, NavType } from '../model/Models';
import { SourceFilter } from '../utils/SourceFilter';
import { AppStore } from '../state/AppStore';
import { I18n } from '../utils/I18n';
import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';
import { TouchTarget } from '../utils/TouchTarget';

/**
 * Source avatar: the favicon fetched for the source when there is one, else
 * the first letter of its name. A component rather than a `@Builder` because a
 * `@Builder`'s value parameters are not re-rendered when they change.
 */
@Component
struct FeedIconView {
  @Prop iconUrl: string;
  @Prop label: string;

  build() {
    // The letter sits underneath the image rather than in an `else`: a favicon
    // URL that fails to load (offline, 404, blocked) must still leave a visible
    // avatar instead of an empty gap.
    Stack() {
      Text(this.label.length > 0 ? this.label.substring(0, 1).toUpperCase() : '?')
        .fontSize(10)
        .fontColor(Color.White)
        .width(18)
        .height(18)
        .borderRadius(4)
        .backgroundColor('#0078D4')
        .textAlign(TextAlign.Center)

      if (this.iconUrl.length > 0) {
        Image(this.iconUrl)
          .width(18)
          .height(18)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
      }
    }
    .width(18)
    .height(18)
    .margin({ right: 8 })
  }
}

/**
 * The subscriptions header: the section label plus the original's "unread
 * sources only" toggle.
 *
 * A component rather than inline markup on purpose. Inline, the conditionally
 * rendered label was **reused by ArkUI across a language change** and kept the
 * language it was first built in, while its siblings updated; taking the label
 * as a `@Prop` makes the rebuild follow the value, the same fix as `ChipView`.
 */
@Component
struct SubscriptionsHeader {
  @Prop active: boolean;
  /**
   * Section title and filter label, both **bound** rather than looked up here.
   *
   * ArkUI re-evaluates a bound value in a reused subtree but not a plain call:
   * when this markup was inline, `menu.subscriptions` followed the language
   * while the conditionally rendered filter label kept its first one; with only
   * the label bound here the two swapped roles. Binding both is what makes the
   * whole header follow a language change.
   */
  @Prop sectionLabel: string;
  @Prop unreadLabel: string;
  /** Theme-aware secondary colour, taken from the parent. */
  @Prop secondaryColor: string;
  onToggle: () => void = () => {
  };

  build() {
    Row() {
      Text(this.sectionLabel)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.secondaryColor)
        .layoutWeight(1)

      if (this.active) {
        Text(this.unreadLabel)
          .fontSize(11)
          .fontColor('#0078D4')
          .margin({ right: 4 })
      }

      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_filter'))
          .width(14)
          .height(14)
          .fillColor(this.active ? '#0078D4' : this.secondaryColor)
      }
      .width(24)
      .height(24)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.onToggle();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 10, bottom: 6 })
  }
}

/**
 * Sidebar with filters, groups and feed subscriptions.
 * Designed for tablet / PC widths.
 */
@Component
export struct SidebarView {
  @ObjectLink store: AppStore;
  onNavigate: (target: NavigationTarget) => void = () => {
  };
  onAddFeed: () => void = () => {
  };
  onShowSettings: () => void = () => {
  };
  onRefresh: () => void = () => {
  };
  /** Open the per-source settings panel (rename, frequency, open target, ...). */
  onFeedSettings: (feedId: number) => void = () => {
  };
  /** Open the per-group settings panel (rename, delete). */
  onGroupSettings: (groupId: number) => void = () => {
  };
  /** Drag-and-drop reorder: the dragged group id and the group it was dropped on. */
  onGroupMove: (fromId: number, toId: number) => void = () => {
  };
  /**
   * Group menu (the original's `GroupContextMenu`): mark everything in a scope
   * as read, or refresh it. Exactly one of `groupId` / `feedId` is set.
   */
  onScopeMarkRead: (groupId: number, feedId: number) => void = () => {
  };
  onScopeRefresh: (groupId: number, feedId: number) => void = () => {
  };
  /** Toggle the sidebar's "unread sources only" filter. */
  onToggleUnreadOnly: () => void = () => {
  };
  /** Toggle the search bar (the original's `toggleSearch`). */
  onToggleSearch: () => void = () => {
  };

  /**
   * The original's `GroupContextMenu` (`components/context-menu.tsx`), reachable
   * from a group row or a source row.
   *
   * The scope is expressed the way the original's `sids` are: a group row
   * passes the group, a source row passes just that source. "Manage sources"
   * maps to this port's own source / group settings panel, which is where those
   * two dialogs live — the original instead preselects the sources inside its
   * settings dialog.
   */
  @Builder
  ScopeMenu(groupId: number, feedId: number) {
    Menu() {
      MenuItem({ content: I18n.get('nav.markAllRead') })
        .onClick(() => {
          this.onScopeMarkRead(groupId, feedId);
        })
      MenuItem({ content: I18n.get('nav.refresh') })
        .onClick(() => {
          this.onScopeRefresh(groupId, feedId);
        })
      MenuItem({ content: I18n.get('context.manageSources') })
        .onClick(() => {
          if (feedId >= 0) {
            this.onFeedSettings(feedId);
          } else {
            this.onGroupSettings(groupId);
          }
        })
    }
  }
  /** Same, for sources. */
  onFeedMove: (fromId: number, toId: number) => void = () => {
  };

  /**
   * Id being dragged. The drag payload is a plain-text id so that ArkUI accepts
   * the drop, but the id is also kept here: reading it back out of the payload
   * would need a cast that buys nothing.
   */
  @State draggingGroupId: number = -1;
  @State draggingFeedId: number = -1;
  onAddGroup: () => void = () => {
  };
  onShowService: () => void = () => {
  };
  onShowRules: () => void = () => {
  };
  onShowLogs: () => void = () => {
  };

  /**
   * ArkUI only fires `onDrop` when the target opts in with a matching data
   * type, so every draggable row carries its id as plain text even though the
   * value is not read back.
   */
  private dragData(id: number): unifiedDataChannel.UnifiedData {
    const record: unifiedDataChannel.PlainText = new unifiedDataChannel.PlainText();
    record.textContent = id.toString();
    return new unifiedDataChannel.UnifiedData(record);
  }

  private plainTextTypes(): Array<uniformTypeDescriptor.UniformDataType> {
    return [uniformTypeDescriptor.UniformDataType.PLAIN_TEXT];
  }

  private textColor(): string {
    return this.store.isDarkMode ? '#FFFFFF' : '#323130';
  }

  private secondaryColor(): string {
    return this.store.isDarkMode ? '#C8C6C4' : '#605E5C';
  }

  private dividerColor(): string {
    return this.store.isDarkMode ? '#3B3A39' : '#EDEBE9';
  }

  private selectedBg(): string {
    return this.store.isDarkMode ? '#323130' : '#EDEBE9';
  }

  private feedsOfGroup(groupId: number): Feed[] {
    const result: Feed[] = [];
    for (const feed of this.store.feeds) {
      if (feed.groupId === groupId) {
        result.push(feed);
      }
    }
    return result;
  }

  private ungroupedFeeds(): Feed[] {
    const result: Feed[] = [];
    for (const feed of this.store.feeds) {
      if (feed.groupId < 0) {
        result.push(feed);
      }
    }
    return result;
  }

  /**
   * The "unread sources only" filter (the original's `unreadSourcesOnly`): with
   * it on, empty sources disappear and a group disappears once all of its
   * sources are empty. The rule itself lives in `SourceFilter` so it can be
   * asserted without a device.
   */
  private visibleGroups(): FeedGroup[] {
    if (!this.store.unreadSourcesOnly) {
      return this.store.groups;
    }
    return this.store.groups.filter(
      (g: FeedGroup) => SourceFilter.groupVisible(this.feedsOfGroup(g.id), true));
  }

  private visibleFeedsOfGroup(groupId: number): Feed[] {
    return SourceFilter.filter(this.feedsOfGroup(groupId), this.store.unreadSourcesOnly);
  }

  private visibleUngroupedFeeds(): Feed[] {
    return SourceFilter.filter(this.ungroupedFeeds(), this.store.unreadSourcesOnly);
  }

  /**
   * The single source of a one-source group, or null for any other size.
   *
   * The original's `SourceGroup.isMultiple` is false exactly when the group
   * holds one source, and `menu.tsx` then renders that source on its own — no
   * group header, and a click selects the *source* rather than "the group".
   */
  private singleGroupFeed(groupId: number): Feed | null {
    const feeds: Feed[] = this.visibleFeedsOfGroup(groupId);
    return feeds.length === 1 ? feeds[0] : null;
  }

  /**
   * Reuse key for one group entry.
   *
   * A one-source group is displayed as its source, so the key has to carry that
   * source's display state as well — ArkUI skips the item builder when the key
   * is unchanged, which is how a rename or an unread count once stayed stale.
   */
  private groupKey(group: FeedGroup): string {
    const single: Feed | null = this.singleGroupFeed(group.id);
    const singlePart: string = single === null
      ? ''
      : '-' + single.id.toString() + '-' + single.title
        + '-' + single.unreadCount.toString()
        + '-' + (this.store.currentNav.feedId === single.id ? '1' : '0')
        + '-' + (single.hidden ? 'h' : '') + '-' + single.iconUrl;
    return 'group-' + group.id.toString() + '-' + group.unreadCount.toString()
      + '-' + (this.store.isGroupExpanded(group.id) ? '1' : '0')
      + '-' + (this.store.currentNav.groupId === group.id ? '1' : '0')
      + singlePart
      // The name must be part of the key: ArkUI reuses a node whose key is
      // unchanged and skips the item builder, so a rename would otherwise
      // not show until the next restart.
      + '-' + group.name;
  }

  /**
   * A one-source group rendered as that source.
   *
   * The edit and ⋯ controls still act on the **group**, because that is where
   * renaming and deleting live in this port; the original keeps them in its
   * settings dialog instead, so its bare row carries no such affordance.
   */
  @Builder
  SingleSourceRow(groupId: number, feed: Feed) {
    Row() {
      FeedIconView({ iconUrl: feed.iconUrl, label: feed.title })
      Text(feed.title)
        .fontSize(13)
        .fontColor(this.store.currentNav.feedId === feed.id ? '#0078D4' : this.textColor())
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (feed.hidden) {
        Image($r('app.media.ic_hide'))
          .width(13)
          .height(13)
          .fillColor(this.secondaryColor())
          .margin({ right: 6 })
      }
      if (feed.unreadCount > 0) {
        Text(feed.unreadCount.toString())
          .fontSize(11)
          .fontColor(this.secondaryColor())
      }
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_edit'))
          .width(14)
          .height(14)
          .fillColor(this.secondaryColor())
      }
      .width(24)
      .height(24)
      .backgroundColor(Color.Transparent)
      .margin({ left: 4 })
      .onClick(() => {
        this.onGroupSettings(groupId);
      })

      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_more'))
          .width(14)
          .height(14)
          .fillColor(this.secondaryColor())
      }
      .width(22)
      .height(24)
      .backgroundColor(Color.Transparent)
      .bindMenu(this.ScopeMenu(groupId, -1))
    }
    .width('100%')
    .padding({ left: 16, right: 10, top: 8, bottom: 8 })
    .backgroundColor(this.store.currentNav.feedId === feed.id ? this.selectedBg() : Color.Transparent)
    // The row represents a group entry, so it reorders groups (this port keeps
    // group and feed order in separate lists).
    .draggable(true)
    .onDragStart((event: DragEvent) => {
      this.draggingGroupId = groupId;
      event.setData(this.dragData(groupId));
    })
    .allowDrop(this.plainTextTypes())
    .onDrop((event: DragEvent) => {
      const from: number = this.draggingGroupId;
      this.draggingGroupId = -1;
      if (from < 0 || from === groupId) {
        return;
      }
      this.onGroupMove(from, groupId);
    })
    .bindContextMenu(this.ScopeMenu(groupId, -1), ResponseType.RightClick)
    .onClick(() => {
      this.openFeed(feed);
    })
  }

  private openAll(): void {
    const target: NavigationTarget = new NavigationTarget();
    target.type = NavType.ALL;
    target.title = I18n.get('allArticles');
    this.onNavigate(target);
  }

  private openFeed(feed: Feed): void {
    const target: NavigationTarget = new NavigationTarget();
    target.type = NavType.FEED;
    target.feedId = feed.id;
    target.title = feed.title;
    this.onNavigate(target);
  }

  private openGroup(group: FeedGroup): void {
    const target: NavigationTarget = new NavigationTarget();
    target.type = NavType.GROUP;
    target.groupId = group.id;
    target.title = group.name;
    this.onNavigate(target);
  }

  private serviceLabel(): string {
    switch (this.store.serviceConfigs.type) {
      case 5:
        return 'Miniflux';
      case 1:
        return 'Fever';
      case 2:
        return 'Feedbin';
      case 3:
        return 'Google Reader';
      case 4:
        return 'Inoreader';
      case 6:
        return 'Nextcloud';
      default:
        return I18n.get('app.syncService');
    }
  }

  build() {
    Column() {
      // Header
      Row() {
        Image(this.store.isDarkMode ? $r('app.media.app_mark_dark') : $r('app.media.app_mark_light'))
          .width(22)
          .height(22)
        Text(I18n.get('app.name'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor())
          .margin({ left: 8 })
          .layoutWeight(1)

        // Notification status. Turns red while there are unacknowledged
        // entries, so a failing source cannot pass unnoticed.
        Button({ type: ButtonType.Circle }) {
          Stack() {
            Image($r('app.media.ic_notify'))
              .width(18)
              .height(18)
              .fillColor(this.store.logNotify ? '#D13438' : this.textColor())
            if (this.store.logNotify) {
              Column()
                .width(7)
                .height(7)
                .borderRadius(4)
                .backgroundColor('#D13438')
                .position({ x: 14, y: 0 })
            }
          }
          .width(20)
          .height(20)
        }
        .width(32)
        .height(32)
        .responseRegion(TouchTarget.region(32))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onShowLogs();
        })

        /*
         * Upstream disables its refresh button while fetching and leaves the
         * icon alone (`disabled={isFetching}` on the `nav.refresh` FlatButton);
         * the bar reports progress. Showing `ic_close` here instead put a
         * "cancel" affordance on a button that still refreshes.
         */
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_refresh'))
            .width(18)
            .height(18)
            .fillColor(this.store.isFetching ? this.secondaryColor() : this.textColor())
        }
        .width(32)
        .height(32)
        .responseRegion(TouchTarget.region(32))
        .backgroundColor(Color.Transparent)
        .enabled(!this.store.isFetching)
        .onClick(() => {
          this.onRefresh();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 16, bottom: 12 })

      Divider().color(this.dividerColor()).strokeWidth(1)

      Scroll() {
        Column() {
          /*
           * Search, the original's first nav item (`menu.tsx` renders a
           * `MenuTreeItem value="search"` with `aside={<Checkmark16Regular/>}`
           * when `page.searchOn`). It toggles the search bar rather than
           * navigating, so it carries a check instead of an unread count.
           */
          Row() {
            Image($r('app.media.ic_search'))
              .width(16)
              .height(16)
              .fillColor(this.store.searchOn ? '#0078D4' : this.secondaryColor())
            Text(I18n.get('search'))
              .fontSize(14)
              .fontColor(this.textColor())
              .margin({ left: 10 })
              .layoutWeight(1)
            if (this.store.searchOn) {
              Image($r('app.media.ic_check'))
                .width(14)
                .height(14)
                .fillColor('#0078D4')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 11, bottom: 11 })
          .constraintSize({ minHeight: TouchTarget.MIN })
          .onClick(() => {
            this.onToggleSearch();
          })

          // Smart filters
          Row() {
            Image($r('app.media.ic_mail'))
              .width(16)
              .height(16)
              .fillColor(this.store.currentNav.type === NavType.ALL ? '#0078D4' : this.secondaryColor())
            Text(I18n.get('allArticles'))
              .fontSize(14)
              .fontColor(this.textColor())
              .margin({ left: 10 })
              .layoutWeight(1)
            if (this.store.totalUnread > 0) {
              Text(this.store.totalUnread.toString())
                .fontSize(12)
                .fontColor(this.secondaryColor())
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 11, bottom: 11 })
          .constraintSize({ minHeight: TouchTarget.MIN })
          .backgroundColor(this.store.currentNav.type === NavType.ALL ? this.selectedBg() : Color.Transparent)
          .onClick(() => {
            this.openAll();
          })

          Divider()
            .color(this.dividerColor())
            .strokeWidth(1)
            .margin({ top: 8, bottom: 8 })

          // Subscriptions header, with the original's "unread sources only"
          // filter: the icon tints while it is on, and the label appears
          // beside it — the same shape as the original's ToggleButton.
          SubscriptionsHeader({
            active: this.store.unreadSourcesOnly,
            sectionLabel: I18n.get('menu.subscriptions'),
            unreadLabel: I18n.get('context.unreadOnly'),
            secondaryColor: this.secondaryColor(),
            onToggle: () => {
              this.onToggleUnreadOnly();
            }
          })
          .width('100%')
          .padding({ left: 16, right: 10, bottom: 6 })

          // Groups
          ForEach(this.visibleGroups(), (group: FeedGroup) => {
            // A one-source group is that source in the original
            // (`SourceGroup.isMultiple === false`), so it gets a plain row.
            if (this.singleGroupFeed(group.id) !== null) {
              this.SingleSourceRow(group.id, this.singleGroupFeed(group.id) as Feed)
            } else {
            Column() {
              Row() {
                /*
                 * Only the arrow toggles expansion, which is what the original
                 * does: `handleOpenChange` dispatches `toggleGroupExpansion`
                 * for `ExpandIconClick` / `ArrowRight` / `ArrowLeft` only,
                 * while the row's own `onClick` selects the group. Toggling on
                 * the whole row as well made selecting a group silently
                 * collapse it.
                 */
                Image(this.store.isGroupExpanded(group.id) ? $r('app.media.ic_arrow_down') : $r('app.media.ic_arrow_right'))
                  .width(16)
                  .height(16)
                  .padding(4)
                  .fillColor(this.secondaryColor())
                  .onClick(() => {
                    this.store.setGroupExpanded(group.id, !this.store.isGroupExpanded(group.id));
                  })
                Image($r('app.media.ic_folder'))
                  .width(15)
                  .height(15)
                  .fillColor(this.secondaryColor())
                  .margin({ left: 4 })
                Text(group.name)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.textColor())
                  .margin({ left: 8 })
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (group.unreadCount > 0) {
                  Text(group.unreadCount.toString())
                    .fontSize(11)
                    .fontColor(this.secondaryColor())
                }
                // A dedicated affordance rather than a long press: the row is
                // already draggable, and a drag *is* a long press plus movement,
                // so overloading the gesture would make both unreliable.
                Button({ type: ButtonType.Circle }) {
                  Image($r('app.media.ic_edit'))
                    .width(14)
                    .height(14)
                    .fillColor(this.secondaryColor())
                }
                .width(24)
                .height(24)
                .backgroundColor(Color.Transparent)
                .margin({ left: 4 })
                .onClick(() => {
                  this.onGroupSettings(group.id);
                })

                // Touch route to the group menu (right-click covers PC).
                Button({ type: ButtonType.Circle }) {
                  Image($r('app.media.ic_more'))
                    .width(14)
                    .height(14)
                    .fillColor(this.secondaryColor())
                }
                .width(22)
                .height(24)
                .backgroundColor(Color.Transparent)
                .bindMenu(this.ScopeMenu(group.id, -1))
              }
              .width('100%')
              .padding({ left: 16, right: 10, top: 10, bottom: 10 })
              .constraintSize({ minHeight: TouchTarget.MIN })
              // Drag to reorder, mirroring the original's groupHint.
              .draggable(true)
              .onDragStart((event: DragEvent) => {
                this.draggingGroupId = group.id;
                event.setData(this.dragData(group.id));
              })
              .allowDrop(this.plainTextTypes())
              .onDrop((event: DragEvent) => {
                const from: number = this.draggingGroupId;
                this.draggingGroupId = -1;
                if (from < 0 || from === group.id) {
                  return;
                }
                this.onGroupMove(from, group.id);
              })
              // The original's group menu, on right-click (PC) and on the small
              // ⋯ button (touch). The row is draggable, and a drag *is* a long
              // press plus movement, so a long-press binding would fight it.
              .bindContextMenu(this.ScopeMenu(group.id, -1), ResponseType.RightClick)
              .onClick(() => {
                this.openGroup(group);
              })

              if (this.store.isGroupExpanded(group.id)) {
                ForEach(this.visibleFeedsOfGroup(group.id), (feed: Feed) => {
                  Row() {
                    FeedIconView({ iconUrl: feed.iconUrl, label: feed.title })
                    Text(feed.title)
                      .fontSize(13)
                      .fontColor(this.store.currentNav.feedId === feed.id ? '#0078D4' : this.textColor())
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (feed.hidden) {
                      Image($r('app.media.ic_hide'))
                        .width(13)
                        .height(13)
                        .fillColor(this.secondaryColor())
                        .margin({ right: 6 })
                    }
                    if (feed.unreadCount > 0) {
                      Text(feed.unreadCount.toString())
                        .fontSize(11)
                        .fontColor(this.secondaryColor())
                    }
                    Button({ type: ButtonType.Circle }) {
                      Image($r('app.media.ic_edit'))
                        .width(14)
                        .height(14)
                        .fillColor(this.secondaryColor())
                    }
                    .width(24)
                    .height(24)
                    .backgroundColor(Color.Transparent)
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.onFeedSettings(feed.id);
                    })

                  // Touch route to the group menu, scoped to this one source.
                  Button({ type: ButtonType.Circle }) {
                    Image($r('app.media.ic_more'))
                      .width(14)
                      .height(14)
                      .fillColor(this.secondaryColor())
                  }
                  .width(22)
                  .height(24)
                  .backgroundColor(Color.Transparent)
                  .bindMenu(this.ScopeMenu(-1, feed.id))
                  }
                  .width('100%')
                  .padding({ left: 40, right: 10, top: 8, bottom: 8 })
                  .constraintSize({ minHeight: TouchTarget.MIN })
                  .backgroundColor(this.store.currentNav.feedId === feed.id ? this.selectedBg() : Color.Transparent)
                  // Drag reorders; the edit button opens settings.
                  .draggable(true)
                  .onDragStart((event: DragEvent) => {
                    this.draggingFeedId = feed.id;
                    event.setData(this.dragData(feed.id));
                  })
                  .allowDrop(this.plainTextTypes())
                  .onDrop((event: DragEvent) => {
                    const from: number = this.draggingFeedId;
                    this.draggingFeedId = -1;
                    if (from < 0 || from === feed.id) {
                      return;
                    }
                    this.onFeedMove(from, feed.id);
                  })
                  .bindContextMenu(this.ScopeMenu(-1, feed.id), ResponseType.RightClick)
                  .onClick(() => {
                    this.openFeed(feed);
                  })
                }, (feed: Feed) => 'gf-' + feed.id.toString() + '-' + feed.unreadCount.toString()
                  + '-' + (this.store.currentNav.feedId === feed.id ? '1' : '0')
                  + '-' + (feed.hidden ? 'h' : '') + '-' + feed.iconUrl + '-' + feed.title)
              }
            }
            .width('100%')
            }
          }, (group: FeedGroup) => this.groupKey(group))

          // Ungrouped feeds
          ForEach(this.visibleUngroupedFeeds(), (feed: Feed) => {
            Row() {
              FeedIconView({ iconUrl: feed.iconUrl, label: feed.title })
              Text(feed.title)
                .fontSize(13)
                .fontColor(this.store.currentNav.feedId === feed.id ? '#0078D4' : this.textColor())
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (feed.hidden) {
                Image($r('app.media.ic_hide'))
                  .width(13)
                  .height(13)
                  .fillColor(this.secondaryColor())
                  .margin({ right: 6 })
              }
              if (feed.unreadCount > 0) {
                Text(feed.unreadCount.toString())
                  .fontSize(11)
                  .fontColor(this.secondaryColor())
              }
              Button({ type: ButtonType.Circle }) {
                Image($r('app.media.ic_edit'))
                  .width(14)
                  .height(14)
                  .fillColor(this.secondaryColor())
              }
              .width(24)
              .height(24)
              .backgroundColor(Color.Transparent)
              .margin({ left: 4 })
              .onClick(() => {
                this.onFeedSettings(feed.id);
              })

              // Touch route to the group menu, scoped to this one source.
              Button({ type: ButtonType.Circle }) {
                Image($r('app.media.ic_more'))
                  .width(14)
                  .height(14)
                  .fillColor(this.secondaryColor())
              }
              .width(22)
              .height(24)
              .backgroundColor(Color.Transparent)
              .bindMenu(this.ScopeMenu(-1, feed.id))
            }
            .width('100%')
            .padding({ left: 24, right: 10, top: 8, bottom: 8 })
            .constraintSize({ minHeight: TouchTarget.MIN })
            .backgroundColor(this.store.currentNav.feedId === feed.id ? this.selectedBg() : Color.Transparent)
            .draggable(true)
            .onDragStart((event: DragEvent) => {
              this.draggingFeedId = feed.id;
              event.setData(this.dragData(feed.id));
            })
            .allowDrop(this.plainTextTypes())
            .onDrop((event: DragEvent) => {
              const from: number = this.draggingFeedId;
              this.draggingFeedId = -1;
              if (from < 0 || from === feed.id) {
                return;
              }
              this.onFeedMove(from, feed.id);
            })
            .bindContextMenu(this.ScopeMenu(-1, feed.id), ResponseType.RightClick)
            .onClick(() => {
              this.openFeed(feed);
            })
          }, (feed: Feed) => 'uf-' + feed.id.toString() + '-' + feed.unreadCount.toString()
            + '-' + (this.store.currentNav.feedId === feed.id ? '1' : '0') + '-' + feed.title
            + '-' + (feed.hidden ? 'h' : '') + '-' + feed.iconUrl)

          if (this.store.feeds.length === 0) {
            Text(I18n.get('app.noSubscriptions') + '\n' + I18n.get('app.addFeedHint'))
              .fontSize(12)
              .fontColor(this.secondaryColor())
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ left: 16, right: 16, top: 24 })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)

      Divider().color(this.dividerColor()).strokeWidth(1)

      // Sync service status strip
      Row() {
        Image($r('app.media.ic_globe'))
          .width(16)
          .height(16)
          .fillColor(this.store.hasService() ? '#0078D4' : this.secondaryColor())
        Column() {
          Text(this.store.hasService() ? this.serviceLabel() : I18n.get('app.syncOff'))
            .fontSize(12)
            .fontColor(this.store.hasService() ? '#0078D4' : this.secondaryColor())
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.store.isSyncing) {
            Text(this.store.syncStatus.length > 0 ? this.store.syncStatus : I18n.get('app.syncing'))
              .fontSize(10)
              .fontColor(this.secondaryColor())
              .width('100%')
              .maxLines(1)
          } else if (this.store.hasService()) {
            Text(I18n.get('app.linkedFeeds',
              new Map<string, string | number>([['count', this.store.serviceLinkedCount]])))
              .fontSize(10)
              .fontColor(this.secondaryColor())
              .width('100%')
              .maxLines(1)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .constraintSize({ minHeight: TouchTarget.MIN })
      .onClick(() => {
        this.onShowService();
      })

      Divider().color(this.dividerColor()).strokeWidth(1)

      // Footer actions
      Row() {
        Row() {
          Image($r('app.media.ic_add'))
            .width(18)
            .height(18)
            .fillColor(this.textColor())
          Text(I18n.get('sources.add'))
            .fontSize(13)
            .fontColor(this.textColor())
            .margin({ left: 6 })
        }
        .layoutWeight(1)
        .padding({ left: 12, top: 8, bottom: 8 })
        .constraintSize({ minHeight: TouchTarget.MIN })
        .borderRadius(4)
        .onClick(() => {
          this.onAddFeed();
        })

        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_folder'))
            .width(18)
            .height(18)
            .fillColor(this.textColor())
        }
        .width(34)
        .height(34)
        .responseRegion(TouchTarget.region(34))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onAddGroup();
        })

        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_rule'))
            .width(18)
            .height(18)
            .fillColor(this.store.rulesCount() > 0 ? '#0078D4' : this.textColor())
        }
        .width(34)
        .height(34)
        .responseRegion(TouchTarget.region(34))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onShowRules();
        })

        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_settings'))
            .width(18)
            .height(18)
            .fillColor(this.textColor())
        }
        .width(34)
        .height(34)
        .responseRegion(TouchTarget.region(34))
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onShowSettings();
        })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.isDarkMode ? '#1B1A19' : '#FAFAFA')
  }
}
