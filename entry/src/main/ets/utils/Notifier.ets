import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * System notifications for articles whose rules asked to be notified
 * (the `n-true` rule action, mirroring the original's `article.notify` +
 * `pushNotification`), plus the app-badge fallback for "something arrived".
 *
 * Two things the original gets for free from Electron and this port has to do
 * explicitly:
 *
 *  - **Consent.** Electron raises a notification without asking. HarmonyOS
 *    requires the user to enable notifications for the app first, and
 *    `publish` otherwise fails with 1600004. That failure was previously
 *    swallowed into `console.warn` while `hilog` is empty on this device, so a
 *    notification that never appeared looked exactly like one that did. The
 *    ability now asks once, through `ensureEnabled`, and `lastError` keeps the
 *    reason around for the in-app log.
 *  - **Click-through.** `notification.onclick` is a `wantAgent` here: it
 *    carries the article id, and `DeepLink` hands it to the page so tapping the
 *    notification opens the same article the original would.
 *
 * Publishing can still legitimately fail — the user may have notifications
 * disabled for the app (1600004) or may have dismissed the request dialog for
 * good. Those are not errors worth surfacing: the article is already recorded in
 * the in-app notification log.
 */
export class Notifier {
  private static nextId: number = 1;
  private static context: common.UIAbilityContext | null = null;

  /** Reason for the last failed publish/badge call, or '' after a success. */
  static lastError: string = '';

  /**
   * Why the click-through agent could not be built, or '' when it was. A
   * notification is still published without an agent; the tap then just brings
   * the app forward instead of opening the article, so this is kept for the
   * in-app log rather than treated as a failed notification.
   */
  static lastAgentError: string = '';

  /** Remember the ability context so `notify` can build a click-through agent. */
  static attach(context: common.UIAbilityContext): void {
    Notifier.context = context;
  }

  /**
   * True when this app may publish notifications. Asks the user once when it
   * may not, which is the closest equivalent of Electron's implicit permission.
   */
  static async ensureEnabled(context: common.UIAbilityContext): Promise<boolean> {
    Notifier.attach(context);
    try {
      if (notificationManager.isNotificationEnabledSync()) {
        return true;
      }
      await notificationManager.requestEnableNotification(context);
      const enabled: boolean = notificationManager.isNotificationEnabledSync();
      if (!enabled) {
        Notifier.lastError = 'notifications still disabled';
      }
      return enabled;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      Notifier.lastError = error.code + ' ' + error.message;
      console.warn('Notifier: enable request failed ' + Notifier.lastError);
      return false;
    }
  }

  /**
   * The notification's click target: start this ability again with the article
   * id in the want. Starting an already-running ability delivers `onNewWant`
   * instead of a second window, which is what the original's `showItemFromId`
   * does for an existing window.
   */
  private static async agentFor(articleId: number): Promise<WantAgent | undefined> {
    const context: common.UIAbilityContext | null = Notifier.context;
    if (context === null || articleId <= 0) {
      return undefined;
    }
    try {
      const parameters: Record<string, Object> = {
        'articleId': articleId.toString()
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name,
          parameters: parameters
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: articleId,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      Notifier.lastAgentError = error.code + ' ' + error.message;
      console.warn('Notifier: wantAgent failed ' + error.code + ' ' + error.message);
      return undefined;
    }
  }

  /**
   * Returns true when the notification was actually published.
   */
  static async notify(title: string, body: string, articleId: number): Promise<boolean> {
    try {
      const agent: WantAgent | undefined = await Notifier.agentFor(articleId);
      const request: notificationManager.NotificationRequest = {
        id: Notifier.nextId,
        content: {
          notificationContentType:
          notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: body,
            additionalText: ''
          }
        },
        // Remove the entry once it has been tapped, like the original's
        // notification, which closes as soon as it hands the article over.
        tapDismissed: true
      };
      // Only set the field when there is an agent: assigning `undefined` counts
      // as *present but not an object* and `publish` rejects the whole request
      // with 401 "The type of wantAgent must be object".
      if (agent !== undefined) {
        request.wantAgent = agent;
      }
      // Wrap around so ids stay small over a long session.
      Notifier.nextId = Notifier.nextId >= 100000 ? 1 : Notifier.nextId + 1;

      await notificationManager.publish(request);
      Notifier.lastError = '';
      return true;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      Notifier.lastError = error.code + ' ' + error.message;
      console.warn('Notifier: publish failed ' + Notifier.lastError);
      return false;
    }
  }

  /**
   * Draw attention to new articles that arrived in the background.
   *
   * The original calls Electron's `flashFrame(true)` to blink its taskbar
   * button. A 2-in-1 has no equivalent API, so the unread count is shown on
   * the app badge instead — the same "something arrived" signal, and one that
   * survives the window being behind another. Best-effort like `notify()`:
   * hardware without badge support is not an error.
   */
  static async requestAttention(unread: number): Promise<void> {
    try {
      await notificationManager.setBadgeNumber(unread > 99 ? 99 : unread);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.warn('Notifier: badge failed ' + error.code + ' ' + error.message);
    }
  }
}
