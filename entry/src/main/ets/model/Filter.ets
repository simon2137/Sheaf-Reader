/**
 * Filter model, a direct port of `FilterType` and `FeedFilter` from the
 * original `scripts/models/feed.ts`.
 *
 * The type is a bit field so filters compose, which is what makes the
 * original's "unread only / starred only / full search / case sensitive"
 * toggles combinable rather than mutually exclusive presets.
 */
export enum FilterType {
  None = 0,
  ShowRead = 1 << 0,
  ShowNotStarred = 1 << 1,
  ShowHidden = 1 << 2,
  /** Search snippet/body in addition to the title. */
  FullSearch = 1 << 3,
  /** When set, matching is case sensitive. */
  CaseInsensitive = 1 << 4,

  Default = ShowRead | ShowNotStarred,
  UnreadOnly = ShowNotStarred,
  StarredOnly = ShowRead,
  Toggles = ShowHidden | FullSearch | CaseInsensitive
}

/**
 * The search scope a *rule* is written in, as stored in `SourceRule.filterType`.
 *
 * Upstream has no separate type for this: a rule's scope reuses the list
 * filter's own bits, `CreatorSearch` (`1 << 5`) among them. The list filter no
 * longer offers a creator scope (it was removed on request, see the README), but
 * rules still do, so the bit is declared here — at its upstream value, which is
 * what keeps rules already stored by this port *or by the original app*
 * matching the author instead of silently falling back to the title.
 */
export enum RuleSearchScope {
  Title = 0,
  FullSearch = FilterType.FullSearch,
  Creator = 1 << 5
}

/** The fields a filter can be applied to. */
export interface FilterableItem {
  title: string;
  snippet: string;
  creator: string;
  hasRead: boolean;
  starred: boolean;
  hidden: boolean;
}

/**
 * A composable article filter. Ported from `FeedFilter`; the original builds
 * Lovefield SQL predicates, this project evaluates in memory because the
 * candidate set is already bounded by the store query.
 */
export class FeedFilter {
  type: number = FilterType.Default | FilterType.CaseInsensitive;
  search: string = '';

  constructor(type?: number, search?: string) {
    if (type !== undefined) {
      this.type = type;
    }
    if (search !== undefined) {
      this.search = search;
    }
  }

  has(flag: number): boolean {
    return (this.type & flag) !== 0;
  }

  /**
   * True when the preset bits are exactly the default, i.e. neither "unread
   * only" nor "starred only" is narrowing the list.
   *
   * The original expresses this as `(filter & ~FilterType.Toggles) ==
   * FilterType.Default`; testing the two preset bits directly is equivalent and
   * immune to new toggle bits being added to `Toggles`.
   */
  isAllPreset(): boolean {
    return this.has(FilterType.ShowRead) && this.has(FilterType.ShowNotStarred);
  }

  /**
   * Build the search matcher, or null when the pattern is empty/invalid.
   * Invalid patterns are treated as "no match" instead of throwing, matching
   * the app's `validateRegex` guard.
   */
  private matcher(): RegExp | null {
    if (this.search.length === 0) {
      return null;
    }
    const flags: string = this.has(FilterType.CaseInsensitive) ? 'i' : '';
    try {
      return new RegExp(this.search, flags);
    } catch (err) {
      return null;
    }
  }

  /**
   * True when the item satisfies every active constraint.
   */
  testItem(item: FilterableItem): boolean {
    let flag: boolean = true;

    if (!this.has(FilterType.ShowRead)) {
      flag = flag && !item.hasRead;
    }
    if (!this.has(FilterType.ShowNotStarred)) {
      flag = flag && item.starred;
    }
    if (!this.has(FilterType.ShowHidden)) {
      flag = flag && !item.hidden;
    }

    if (this.search.length > 0) {
      const regex: RegExp | null = this.matcher();
      if (regex === null) {
        return false;
      }
      if (this.has(FilterType.FullSearch)) {
        flag = flag && (regex.test(item.title) || regex.test(item.snippet));
      } else if (this.has(RuleSearchScope.Creator)) {
        // Only a rule sets this bit now; a list filter never does.
        flag = flag && regex.test(item.creator ? item.creator : '');
      } else {
        flag = flag && regex.test(item.title);
      }
    }

    return flag;
  }

  /**
   * SQL fragment for the constraints that SQLite can evaluate.
   *
   * The search pattern is deliberately NOT translated here: the original runs
   * it through Lovefield's `match(regex)`, which relies on a REGEXP hook in
   * the underlying database. HarmonyOS relationalStore does not let an app
   * register custom SQL functions, so the pattern is evaluated in memory by
   * `testItem` instead (see `DatabaseManager.getArticles`).
   */
  static toSql(filter: FeedFilter, excludeHiddenFeeds: boolean = false): FilterClause {
    const clause: FilterClause = new FilterClause();

    if (!filter.has(FilterType.ShowRead)) {
      clause.sql = clause.sql.concat(' AND a.read = 0');
    }
    if (!filter.has(FilterType.ShowNotStarred)) {
      clause.sql = clause.sql.concat(' AND a.starred = 1');
    }
    if (!filter.has(FilterType.ShowHidden)) {
      clause.sql = clause.sql.concat(' AND a.hidden = 0');
    }
    // A source can be marked "hide in all articles" (`sources.hidden`). That is
    // a property of the source, not of the article, so it is only applied to
    // the aggregate view — selecting the source itself still lists it.
    if (excludeHiddenFeeds && !filter.has(FilterType.ShowHidden)) {
      clause.sql = clause.sql
        .concat(' AND a.feed_id NOT IN (SELECT id FROM feeds WHERE hidden = 1)');
    }

    return clause;
  }

  /**
   * Convenience wrapper for callers holding an `Article`, so the row-to-filter
   * projection lives in one place.
   */
  static testArticle(filter: FeedFilter, title: string, snippet: string,
    creator: string, hasRead: boolean, starred: boolean, hidden: boolean): boolean {
    const item: FilterableItem = {
      title: title,
      snippet: snippet,
      creator: creator,
      hasRead: hasRead,
      starred: starred,
      hidden: hidden
    };
    return filter.testItem(item);
  }
}

/** A SQL fragment with its bound arguments. */
export class FilterClause {
  sql: string = '';
  args: (string | number)[] = [];
}
