import { Article } from '../model/Models';

/**
 * The one article row as it is measured for storage accounting. Field names come
 * from this port's schema; the *measure* mirrors the original, which sums the
 * serialized byte length of every row in the item store.
 */
interface ArticleRecord {
  id: number;
  feedId: number;
  title: string;
  link: string;
  author: string;
  content: string;
  snippet: string;
  published: number;
  fetched: number;
  read: boolean;
  starred: boolean;
  imageUrl: string;
  guid: string;
  serviceRef: string;
  hidden: boolean;
  notify: boolean;
}

/**
 * Storage accounting for the settings "Clean up" section, ported from
 * `src/scripts/utils.ts` of the original.
 *
 * The original measures the article store by walking every row and summing
 * `byteLength(JSON.stringify(item))`, then formats the total with
 * `Math.round(B / 1048576) + "MB"`. Both are pure functions, so they are
 * asserted in `verify/harness.ts` rather than only observed on a device.
 */
export class StorageSize {
  /**
   * UTF-8 byte length of a string, ported verbatim from the original's
   * `byteLength`.
   *
   * It does not build a buffer: it starts from the UTF-16 length and adds one
   * byte per two-byte character, two per three-byte character, and steps over
   * the low half of each surrogate pair so an astral character counts as four
   * bytes instead of six. That approximation is the original's, and is kept so
   * the reported size stays comparable.
   */
  static byteLength(text: string): number {
    let size: number = text.length;
    for (let i = text.length - 1; i >= 0; i--) {
      const code: number = text.charCodeAt(i);
      if (code > 0x7f && code <= 0x7ff) {
        size += 1;
      } else if (code > 0x7ff && code <= 0xffff) {
        size += 2;
      }
      if (code >= 0xdc00 && code <= 0xdfff) {
        i -= 1; // trail surrogate: already counted with its lead
      }
    }
    return size;
  }

  /** One article as the JSON the original would have serialized. */
  static serialized(article: Article): string {
    const record: ArticleRecord = {
      id: article.id,
      feedId: article.feedId,
      title: article.title,
      link: article.link,
      author: article.author,
      content: article.content,
      snippet: article.snippet,
      published: article.published,
      fetched: article.fetched,
      read: article.read,
      starred: article.starred,
      imageUrl: article.imageUrl,
      guid: article.guid,
      serviceRef: article.serviceRef,
      hidden: article.hidden,
      notify: article.notify
    };
    return JSON.stringify(record);
  }

  /** Total serialized size of a set of articles. */
  static totalBytes(articles: Article[]): number {
    let total: number = 0;
    for (const article of articles) {
      total += StorageSize.byteLength(StorageSize.serialized(article));
    }
    return total;
  }

  /**
   * The original's `byteToMB`. Note it rounds rather than truncates and always
   * appends `MB`, so a small store reads `"0MB"` — the cache button relies on
   * exactly that string to disable itself.
   */
  static formatMb(bytes: number): string {
    return Math.round(bytes / 1048576).toString().concat('MB');
  }
}
