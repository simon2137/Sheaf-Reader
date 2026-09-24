import { I18n } from '../utils/I18n';
import { Feed } from '../model/Models';
import { TouchTarget } from '../utils/TouchTarget';

/**
 * Per-group settings, mirroring the original's "manage group" screen
 * (`src/components/settings/groups.tsx`) plus the group's insert/delete.
 *
 * Reading that file settled how each label is actually used upstream, and this
 * panel had three of them in the wrong place:
 *
 *   - `groups.editName` is the **rename button** in the selected-group row, not
 *     a panel title — the title upstream is `groups.selectedGroup`
 *     (`groups.selectedSource` when the row is a one-source group, which
 *     upstream renders as a plain source).
 *   - `groups.addToGroup` / `groups.chooseGroup` are the button and the
 *     **dropdown placeholder** of the *source-side* flow ("selected source →
 *     pick a target group"). Upstream's manage screen has **no add control at
 *     all**, so hosting them here inverted both strings. That flow now lives in
 *     `FeedSettingsDialog`, where this port keeps per-source settings.
 *   - `groups.sourceHint` is "Drag and drop sources to reorder." and belongs
 *     under the group's source list. Dragging is not wired inside this dialog,
 *     so the hint would promise an affordance that is not here; it was only
 *     being shown when the group was *empty*, which is the one case where there
 *     is nothing to reorder. It is gone, and reordering stays on the sidebar
 *     (where dragging a source row does reorder within its group).
 *
 * `groups.source` and `groups.capacity` keep their upstream meanings ("Source"
 * as the type cell opposite `groups.group`, "Capacity" as the source count);
 * they head the member list here because this port has no group table to put
 * them in.
 */
@CustomDialog
export struct GroupSettingsDialog {
  /** Current values, copied into editable state in `aboutToAppear`. */
  initialName: string = '';
  /** Other group names, used to reject a duplicate. */
  existingNames: string[] = [];
  /** The group being edited. */
  groupId: number = -1;
  /** Sources currently in the group. */
  members: Feed[] = [];

  @State name: string = '';
  // 主题走 AppStorage（不是 @Prop/@State）：弹窗内容由 CustomDialogController 构建，
  // 父组件重渲染不会重建它；原来声明成 @State 更收不到父组件的值，深色下一直是浅色。
  @StorageProp('sheafReaderIsDarkMode') isDarkMode: boolean = false;
  @State errorMessage: string = '';
  @State confirmingDelete: boolean = false;
  @State isSaving: boolean = false;
  /** Local copy of the membership so edits show without reopening. */
  @State memberNames: string[] = [];
  @State memberIds: number[] = [];

  onSave: (name: string) => Promise<void> = async () => {
  };
  onDelete: () => Promise<void> = async () => {
  };
  /** Remove a source from this group (`-1` = no group). */
  onAssign: (feedId: number, groupId: number) => Promise<void> = async () => {
  };
  controller?: CustomDialogController;

  aboutToAppear(): void {
    this.name = this.initialName;
    this.memberNames = this.namesOf(this.members);
    this.memberIds = this.idsOf(this.members);
  }

  private namesOf(feeds: Feed[]): string[] {
    const names: string[] = [];
    for (const feed of feeds) {
      names.push(feed.title);
    }
    return names;
  }

  private idsOf(feeds: Feed[]): number[] {
    const ids: number[] = [];
    for (const feed of feeds) {
      ids.push(feed.id);
    }
    return ids;
  }

  /**
   * Upstream shows `groups.selectedGroup` for a real group and
   * `groups.selectedSource` when the row is a one-source group.
   */
  private titleKey(): string {
    return this.memberIds.length === 1
      ? 'groups.selectedSource' : 'groups.selectedGroup';
  }

  /** Take a source out of the group. */
  private async removeMember(index: number): Promise<void> {
    const feedId: number = this.memberIds[index];
    await this.onAssign(feedId, -1);
    const nextMembers: number[] = this.memberIds.slice();
    nextMembers.splice(index, 1);
    this.memberIds = nextMembers;
    this.memberNames = this.namesForIds(nextMembers);
  }

  /** The label list for a set of feed ids, using the titles seen on open. */
  private namesForIds(ids: number[]): string[] {
    const names: string[] = [];
    for (const id of ids) {
      names.push(this.titleOf(id));
    }
    return names;
  }

  private titleOf(feedId: number): string {
    for (const feed of this.members) {
      if (feed.id === feedId) {
        return feed.title;
      }
    }
    return '';
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

  /** True when the typed name duplicates another group. */
  private isDuplicate(): boolean {
    const candidate: string = this.name.trim();
    if (candidate.length === 0 || candidate === this.initialName) {
      return false;
    }
    for (const existing of this.existingNames) {
      if (existing === candidate) {
        return true;
      }
    }
    return false;
  }

  build() {
    Column() {
      Row() {
        Text(I18n.get(this.titleKey()))
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

      Text(I18n.get('groups.enterName'))
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
        .onChange((value: string) => {
          this.name = value;
          this.errorMessage = '';
        })
        .margin({ bottom: 14 })

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor('#D13438')
          .width('100%')
          .padding(8)
          .borderRadius(4)
          .backgroundColor(this.isDarkMode ? '#442726' : '#FDE7E9')
          .margin({ bottom: 12 })
      }

      if (this.confirmingDelete) {
        Text(I18n.get('app.deleteGroupMessage', new Map<string, string | number>([
          ['name', this.initialName]
        ])))
          .fontSize(12)
          .fontColor('#D13438')
          .width('100%')
          .padding(8)
          .borderRadius(4)
          .backgroundColor(this.isDarkMode ? '#442726' : '#FDE7E9')
          .margin({ bottom: 12 })
      }

      Divider().color(this.dividerColor()).strokeWidth(1).margin({ bottom: 12 })

      // ---- Membership (the original's manage-group screen) ----
      Row() {
        Text(I18n.get('groups.source'))
          .fontSize(12)
          .fontColor(this.secondaryColor())
          .layoutWeight(1)
        Text(I18n.get('groups.capacity') + ': ' + this.memberIds.length.toString())
          .fontSize(12)
          .fontColor(this.secondaryColor())
      }
      .width('100%')
      .margin({ bottom: 6 })

      ForEach(this.memberIds, (feedId: number) => {
        Row() {
          Text(this.titleOf(feedId))
            .fontSize(13)
            .fontColor(this.textColor())
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button(I18n.get('groups.deleteSource'))
            .fontSize(11)
            .fontColor('#D13438')
            .backgroundColor(this.fieldColor())
            .height(26)
            .onClick(async () => {
              await this.removeMember(this.memberIds.indexOf(feedId));
            })
        }
        .width('100%')
        .padding({ top: 3, bottom: 3 })
      }, (feedId: number) => 'member-' + feedId.toString())

      Divider().color(this.dividerColor()).strokeWidth(1).margin({ top: 12, bottom: 12 })

      Row() {
        Button(this.confirmingDelete ? I18n.get('delete') : I18n.get('groups.deleteGroup'))
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

        // `groups.editName` is upstream's rename button in the selected-group
        // row; it is the primary action here rather than a generic "save".
        Button(this.isSaving ? I18n.get('app.saving') : I18n.get('groups.editName'))
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#0078D4')
          .enabled(!this.isSaving)
          .layoutWeight(1)
          .margin({ left: 10 })
          .onClick(async () => {
            const candidate: string = this.name.trim();
            if (candidate.length === 0) {
              this.errorMessage = I18n.get('emptyName');
              return;
            }
            if (this.isDuplicate()) {
              this.errorMessage = I18n.get('groups.exist');
              return;
            }
            this.isSaving = true;
            await this.onSave(candidate);
            this.isSaving = false;
            this.closeDialog();
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
