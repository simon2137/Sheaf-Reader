/**
 * One-shot hand-off from a launched `want` to the page.
 *
 * The original attaches `notification.onclick` to the system notification it
 * raises for a rule-notified article, so clicking it focuses the window and
 * shows that article (`showItemFromId`). HarmonyOS delivers the equivalent
 * through the notification's `wantAgent`: the want carries the article id, but
 * the ability may be **cold-started** (the page does not exist yet) or merely
 * brought to the front (the page already exists). The id is therefore parked in
 * `AppStorage`, which covers both cases: a `@StorageLink` picks up the value at
 * construction, and a later write triggers its `@Watch`.
 *
 * The parked value is an opaque "seq:id" token so that
 *  - every publish is unique — writing the same number twice would not notify a
 *    bound state at all (README ㉖), and tapping the same notification twice
 *    must still open the article;
 *  - consumption is idempotent: the two entry points (the `@Watch` and the
 *    page's `onPageShow`) both call `consume()`, and only the first sees a value.
 */
export class DeepLink {
  static readonly STORAGE_KEY: string = 'sheafReaderPendingArticle';

  private static sequence: number = 0;

  /** Park an article id for the page to pick up. */
  static publish(articleId: number): void {
    if (articleId <= 0) {
      return;
    }
    DeepLink.sequence++;
    AppStorage.setOrCreate(DeepLink.STORAGE_KEY,
      DeepLink.sequence.toString() + ':' + articleId.toString());
  }

  /** Read the pending article id and clear it; 0 when there is nothing to do. */
  static consume(): number {
    const raw: string = AppStorage.get<string>(DeepLink.STORAGE_KEY) ?? '';
    if (raw.length === 0) {
      return 0;
    }
    AppStorage.setOrCreate(DeepLink.STORAGE_KEY, '');
    const parts: string[] = raw.split(':');
    if (parts.length !== 2) {
      return 0;
    }
    const id: number = parseInt(parts[1], 10);
    return id > 0 ? id : 0;
  }
}
