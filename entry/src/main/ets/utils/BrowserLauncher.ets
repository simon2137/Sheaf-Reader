import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Hands a URL to the system browser.
 *
 * `startAbility` completes asynchronously, so the outcome is only known once the
 * returned promise settles. Reporting success before then would claim a link
 * had opened on a device whose browser launch was in fact rejected — for
 * instance when no browsable ability is installed.
 */
export class BrowserLauncher {
  static async open(context: common.UIAbilityContext, url: string): Promise<boolean> {
    if (!url) {
      return false;
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      };
      await context.startAbility(want);
      return true;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('BrowserLauncher.open failed: ' + error.code + ' ' + error.message);
      return false;
    }
  }
}
