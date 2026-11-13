import { SearchEngine } from '../model/Models';
import { I18n } from './I18n';

/**
 * The search engines the original offers for "search selected text"
 * (`src/scripts/models/search.ts`), and the URLs it builds for them.
 *
 * Pure string work, so the query construction is unit-testable.
 */
export class SearchEngines {
  /**
   * Menu order: Bing, Baidu, DuckDuckGo, Google.
   *
   * The stored value is `SearchEngine`'s number, not a position, so this order
   * is display-only and older settings keep pointing at the same engine. It is
   * reordered away from the original's list because the app is used where
   * Google cannot be reached: an engine the reader cannot open does not belong
   * at the top of a menu that is meant to be used in one tap. The other three
   * keep their relative order.
   */
  static readonly ALL: number[] = [
    SearchEngine.Bing, SearchEngine.Baidu, SearchEngine.DuckDuckGo, SearchEngine.Google
  ];

  /** Catalogue key for an engine's display name. */
  static labelKey(engine: number): string {
    switch (engine) {
      case SearchEngine.Bing:
        return 'searchEngine.bing';
      case SearchEngine.Baidu:
        return 'searchEngine.baidu';
      case SearchEngine.DuckDuckGo:
        return 'searchEngine.duckduckgo';
      default:
        return 'searchEngine.google';
    }
  }

  /**
   * Search URL for a query.
   *
   * Each engine's parameter differs — `q` for Google/Bing/DuckDuckGo, `wd` for
   * Baidu — and the query is percent-encoded so a multi-word or CJK selection
   * survives the trip.
   */
  static urlFor(engine: number, query: string): string {
    const encoded: string = encodeURIComponent(query);
    switch (engine) {
      case SearchEngine.Bing:
        return 'https://www.bing.com/search?q='.concat(encoded);
      case SearchEngine.Baidu:
        return 'https://www.baidu.com/s?wd='.concat(encoded);
      case SearchEngine.DuckDuckGo:
        return 'https://duckduckgo.com/?q='.concat(encoded);
      default:
        return 'https://www.google.com/search?q='.concat(encoded);
    }
  }

  /**
   * The selected text a context-menu click should search for.
   *
   * `TextRange` indices are measured against the rendered body, so the caller
   * hands in that same body. Whitespace is trimmed and an empty range yields
   * an empty string, which callers treat as "nothing to search".
   */
  static selectionOf(body: string, start: number, end: number): string {
    const from: number = start < 0 ? 0 : start;
    const to: number = end > body.length ? body.length : end;
    if (to <= from) {
      return '';
    }
    return body.substring(from, to).trim();
  }

  /**
   * Label for the "search selected text" menu entry, built from the original's
   * `context.search` catalogue string ("Search \"{text}\" on {engine}").
   *
   * An empty selection still needs a visible label, so it degrades to an
   * ellipsis rather than rendering "Search "" on Google".
   */
  static menuLabel(engine: number, selection: string): string {
    const text: string = selection.trim();
    return I18n.get('context.search', new Map<string, string | number>([
      ['text', text.length > 0 ? text : '...'],
      ['engine', I18n.get(SearchEngines.labelKey(engine))]
    ]));
  }
}
