import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseManager } from '../data/DatabaseManager';
import { I18n } from '../utils/I18n';
import { DeepLink } from '../utils/DeepLink';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'EntryAbility', 'Ability onCreate');
    EntryAbility.applyDeepLink(want);
  }

  /**
   * A notification tap while the ability is still alive arrives here rather
   * than in `onCreate`; both paths park the article id for the page.
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'EntryAbility', 'Ability onNewWant');
    EntryAbility.applyDeepLink(want);
  }

  /**
   * The notification's `wantAgent` carries the article id as a string (want
   * parameters are `Record<string, Object>`); a launch from the launcher simply
   * has no such parameter.
   */
  private static applyDeepLink(want: Want): void {
    const parameters: Record<string, Object> | undefined = want.parameters;
    if (parameters === undefined) {
      return;
    }
    const raw: Object | undefined = parameters['articleId'];
    if (raw === undefined) {
      return;
    }
    const articleId: number = parseInt(raw.toString(), 10);
    if (articleId > 0) {
      hilog.info(0x0000, 'EntryAbility', 'Deep link to article %{public}d', articleId);
      DeepLink.publish(articleId);
    }
  }

  onDestroy(): void {
    hilog.info(0x0000, 'EntryAbility', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // Initialize database
    try {
      const db = DatabaseManager.getInstance();
      await db.init(this.context);
      hilog.info(0x0000, 'EntryAbility', 'Database initialized');

      // Localisation must be ready before the first frame, so the stored
      // choice (or the device language) is resolved here rather than in a
      // component's async bootstrap.
      const stored: string = await db.getSetting('locale', '');
      const locale: string = stored.length > 0 ? stored : I18n.systemLocale();
      await I18n.init(this.context, locale);
      hilog.info(0x0000, 'EntryAbility', 'Locale: %{public}s', I18n.currentLocale());
    } catch (e) {
      hilog.error(0x0000, 'EntryAbility', 'Startup init failed: %{public}s', JSON.stringify(e));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'EntryAbility', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'EntryAbility', 'Content loaded successfully');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'EntryAbility', 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, 'EntryAbility', 'onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, 'EntryAbility', 'onBackground');
  }
}