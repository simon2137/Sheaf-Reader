import { Article, ItemAction, RuleActions, SourceRule } from '../model/Models';
import { FeedFilter } from '../model/Filter';

/**
 * Rule evaluation, a port of `SourceRule.apply` / `applyAll` from the
 * original `scripts/models/rule.ts`.
 *
 * Rules run in list order and mutate the article in place, which is why the
 * original applies them at parse time before the item is persisted.
 */
export class RuleEngine {
  /**
   * Apply a single rule. The rule fires when its filter result equals its
   * `match` flag, so a rule can be written as "doesn't match" as well.
   */
  static apply(rule: SourceRule, item: Article): void {
    if (!RuleEngine.matches(rule, item)) {
      return;
    }

    const actions: Map<string, boolean> = RuleActions.fromKeys(rule.actions);
    actions.forEach((flag: boolean, action: string) => {
      RuleEngine.transform(action, flag, item);
    });
  }

  /**
   * Whether a rule would fire for this article, without changing anything.
   *
   * `apply` is defined in terms of this so the rules panel's "test" action
   * cannot drift from what a real fetch would do.
   */
  static matches(rule: SourceRule, item: Article): boolean {
    const filter: FeedFilter = new FeedFilter(rule.filterType, rule.regex);
    const result: boolean = filter.testItem({
      title: item.title,
      snippet: item.snippet,
      creator: item.author,
      hasRead: item.read,
      starred: item.starred,
      hidden: item.hidden
    });
    return result === rule.match;
  }

  /** How many of the given articles a rule would fire for. */
  static countMatches(rule: SourceRule, items: Article[]): number {
    let count: number = 0;
    for (const item of items) {
      if (RuleEngine.matches(rule, item)) {
        count++;
      }
    }
    return count;
  }

  static applyAll(rules: SourceRule[], item: Article): void {
    for (const rule of rules) {
      RuleEngine.apply(rule, item);
    }
  }

  /**
   * Port of the original `actionTransform` table.
   */
  private static transform(action: string, flag: boolean, item: Article): void {
    switch (action) {
      case ItemAction.Read:
        item.read = flag;
        break;
      case ItemAction.Star:
        item.starred = flag;
        break;
      case ItemAction.Hide:
        item.hidden = flag;
        break;
      case ItemAction.Notify:
        item.notify = flag;
        break;
      default:
        break;
    }
  }

  /**
   * Rules stored on a feed as JSON, evaluated against a freshly parsed item.
   */
  static applyForFeed(feedRulesJson: string, item: Article): void {
    if (!feedRulesJson) {
      return;
    }
    RuleEngine.applyAll(SourceRule.fromJson(feedRulesJson), item);
  }

  /**
   * Validate a user-supplied pattern, mirroring `validateRegex`.
   */
  static validateRegex(regex: string, flags: string): boolean {
    if (!regex) {
      return true;
    }
    try {
      new RegExp(regex, flags);
      return true;
    } catch (err) {
      return false;
    }
  }
}
