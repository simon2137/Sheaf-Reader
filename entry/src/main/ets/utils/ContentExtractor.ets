/**
 * Readability-style full-content extraction, standing in for the original's
 * Mercury / Postlight parser ("Load full content").
 *
 * HarmonyOS has no DOM, so this works textually on the raw markup but follows
 * the same shape of heuristic the original leans on: drop the page chrome,
 * split what is left into block-level fragments, score each one by prose
 * density, and keep the ones that look like article body. It is a structural
 * port of the idea, not the upstream library.
 */
import { FeedParser } from './FeedParser';
import { ReaderBody } from './ReaderBody';

export interface ExtractedContent {
  /** Block-level HTML, ready for the reader's own markup stripping. */
  html: string;
  /** Characters of visible text; used to reject a failed extraction. */
  textLength: number;
}

/** One block-level fragment plus the tag that terminated it. */
interface BlockFragment {
  html: string;
  tag: string;
}

export class ContentExtractor {
  /** Fragments shorter than this are captions, labels or navigation. */
  private static readonly MIN_BLOCK_LENGTH: number = 25;
  /** A heading is allowed to be shorter than a prose block. */
  private static readonly MIN_HEADING_LENGTH: number = 4;
  /** Below this total the extraction is treated as failed, not shipped. */
  private static readonly MIN_TOTAL_LENGTH: number = 250;
  /** Guard against pathological pages. */
  private static readonly MAX_BLOCKS: number = 400;
  /** A fragment this short needs sentence punctuation to look like prose. */
  private static readonly PROSE_HINT_LENGTH: number = 120;
  /** Above this share of linked text a fragment is a menu, not body copy. */
  private static readonly MAX_LINK_SHARE: number = 0.5;

  /** Elements that are never article body. */
  private static readonly CHROME: string[] = [
    'script', 'style', 'noscript', 'svg', 'iframe', 'form', 'nav',
    'header', 'footer', 'aside', 'button', 'select', 'option', 'template'
  ];

  /** Tags whose closing form ends a block-level fragment. */
  private static readonly BLOCK_TAGS: string[] = [
    'p', 'div', 'section', 'article', 'blockquote', 'li', 'h1', 'h2', 'h3',
    'h4', 'h5', 'h6', 'pre', 'td', 'figure', 'figcaption', 'dd', 'dt'
  ];

  /** Tags allowed to survive into the extracted body. */
  private static readonly KEEP_TAGS: string[] = [
    'p', 'br', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre',
    'code', 'ul', 'ol', 'li', 'strong', 'b', 'em', 'i', 'a', 'figure',
    'figcaption', 'table', 'thead', 'tbody', 'tr', 'th', 'td'
  ];

  /**
   * Pull the article body out of a fetched web page. Returns null when the
   * page does not yield enough prose, so the caller can tell the user rather
   * than replace a good feed body with an empty one.
   */
  static extract(pageHtml: string, baseUrl: string = ''): ExtractedContent | null {
    if (!pageHtml) {
      return null;
    }

    let html: string = ContentExtractor.stripComments(pageHtml);
    html = ContentExtractor.dropChrome(html);

    const region: string = ContentExtractor.mainRegion(html);
    const fragments: BlockFragment[] = ContentExtractor.splitBlocks(region);

    const kept: string[] = [];
    for (const fragment of fragments) {
      if (kept.length >= ContentExtractor.MAX_BLOCKS) {
        break;
      }
      if (ContentExtractor.worthKeeping(fragment)) {
        kept.push('<p>' + ContentExtractor.cleanBlock(fragment.html, baseUrl) + '</p>');
      }
    }
    if (kept.length === 0) {
      return null;
    }

    const body: string = kept.join('\n');
    const textLength: number = ContentExtractor.visibleText(body).length;
    if (textLength < ContentExtractor.MIN_TOTAL_LENGTH) {
      return null;
    }
    return { html: body, textLength: textLength };
  }

  /**
   * Visible text without truncation. `FeedParser.stripHtml` is a snippet
   * builder and caps its output, which would make every long paragraph look
   * the same length here.
   */
  private static visibleText(html: string): string {
    return FeedParser.htmlDecode(html).replace(/\s+/g, ' ').trim();
  }

  private static stripComments(html: string): string {
    return html.replace(/<!--[\s\S]*?-->/g, ' ');
  }

  /** Remove every non-body element together with its contents. */
  private static dropChrome(html: string): string {
    let out: string = html;
    for (const tag of ContentExtractor.CHROME) {
      const paired = new RegExp('<' + tag + '\\b[^>]*>[\\s\\S]*?<\\/' + tag + '\\s*>', 'gi');
      out = out.replace(paired, ' ');
    }
    return out;
  }

  /**
   * Prefer the largest `<article>`, then the largest `<main>`, then `<body>`,
   * then the document as a whole — the same order of preference the original
   * gets from its parser's candidate selection.
   */
  private static mainRegion(html: string): string {
    const article: string = ContentExtractor.largestOf(html, 'article');
    if (article.length > 0) {
      return article;
    }
    const main: string = ContentExtractor.largestOf(html, 'main');
    if (main.length > 0) {
      return main;
    }
    const body: string = ContentExtractor.largestOf(html, 'body');
    if (body.length > 0) {
      return body;
    }
    return html;
  }

  /**
   * Longest match for `<tag>…</tag>`. Pairing is non-greedy so nested elements
   * of the same name are split rather than swallowed whole; the largest result
   * is still the outer wrapper in practice.
   */
  private static largestOf(html: string, tag: string): string {
    const re = new RegExp('<' + tag + '\\b[^>]*>([\\s\\S]*?)<\\/' + tag + '\\s*>', 'gi');
    let best: string = '';
    let match = re.exec(html);
    while (match !== null) {
      if (match[1].length > best.length) {
        best = match[1];
      }
      match = re.exec(html);
    }
    return best;
  }

  /**
   * Split on every block-level closing tag. The terminator is returned with
   * its fragment so a heading can be recognised as such — headings carry no
   * sentence punctuation and would otherwise fail the prose test.
   */
  private static splitBlocks(region: string): BlockFragment[] {
    let marked: string = region;
    for (const tag of ContentExtractor.BLOCK_TAGS) {
      const close = new RegExp('</' + tag + '\\s*>', 'gi');
      marked = marked.replace(close, '\u0000' + tag + '\u0000');
    }

    const parts: string[] = marked.split('\u0000');
    const out: BlockFragment[] = [];
    for (let i = 0; i < parts.length; i += 2) {
      const tag: string = (i + 1) < parts.length ? parts[i + 1] : '';
      out.push({ html: parts[i], tag: tag });
    }
    return out;
  }

  /** True for the `h1`–`h6` terminators. */
  private static isHeading(tag: string): boolean {
    if (tag.length !== 2 || tag.charAt(0) !== 'h') {
      return false;
    }
    const digit: string = tag.charAt(1);
    return digit >= '1' && digit <= '6';
  }

  /** Prose density test: long enough, not a menu, and sentence-shaped. */
  private static worthKeeping(fragment: BlockFragment): boolean {
    const text: string = ContentExtractor.visibleText(fragment.html);

    // A block carrying an image is body content even when it has no prose of
    // its own: the original's webview draws the picture, and the reader now
    // does too (`ReaderBody`).
    if (ContentExtractor.hasUsableImage(fragment.html)) {
      return true;
    }

    // A heading is a legitimate part of the body even though it is short and
    // carries no sentence punctuation.
    if (ContentExtractor.isHeading(fragment.tag)) {
      return text.length >= ContentExtractor.MIN_HEADING_LENGTH;
    }

    if (text.length < ContentExtractor.MIN_BLOCK_LENGTH) {
      return false;
    }

    const linked: number = ContentExtractor.linkTextLength(fragment.html);
    if (linked > 0 && linked > text.length * ContentExtractor.MAX_LINK_SHARE) {
      return false;
    }

    if (text.length < ContentExtractor.PROSE_HINT_LENGTH
      && ContentExtractor.countStops(text) === 0) {
      return false;
    }
    return true;
  }

  private static linkTextLength(fragment: string): number {
    const re = /<a\b[^>]*>([\s\S]*?)<\/a>/gi;
    let total: number = 0;
    let match = re.exec(fragment);
    while (match !== null) {
      total += ContentExtractor.visibleText(match[1]).length;
      match = re.exec(fragment);
    }
    return total;
  }

  /** Sentence terminators, including the full-width CJK forms. */
  private static countStops(text: string): number {
    let count: number = 0;
    for (let i = 0; i < text.length; i++) {
      const c: string = text.charAt(i);
      if (c === '.' || c === '!' || c === '?'
        || c === '\u3002' || c === '\uff01' || c === '\uff1f') {
        count++;
      }
    }
    return count;
  }

  /** True when the fragment carries an image the reader could actually draw. */
  private static hasUsableImage(fragment: string): boolean {
    const re = /<img\b[^>]*>/gi;
    let match = re.exec(fragment);
    while (match !== null) {
      if (ContentExtractor.imageSrc(match[0]).length > 0) {
        return true;
      }
      match = re.exec(fragment);
    }
    return false;
  }

  /** The `src` of an `<img>` tag, decoded, or '' when it has none. */
  private static imageSrc(imgTag: string): string {
    const match = /\bsrc\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/i.exec(imgTag);
    if (match === null) {
      return '';
    }
    let raw: string = match[1];
    if (raw.length >= 2 && (raw.charAt(0) === '"' || raw.charAt(0) === '\'')) {
      raw = raw.slice(1, raw.length - 1);
    }
    return FeedParser.decodeEntities(raw).trim();
  }

  /**
   * Strip the fragment down to the tags that survive into the body, keeping
   * images as `<img src="...">` with an absolute URL.
   *
   * Attributes are dropped from every other tag because a text-only reader has
   * no use for them (and `href` targets would only dangle). The image URL is
   * resolved here, while the page URL is still known, so the view layer never
   * has to guess a base.
   */
  private static cleanBlock(fragment: string, baseUrl: string): string {
    const anyTag = /<\/?([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>/g;
    const parts: string[] = [];
    const images: string[] = [];
    let last: number = 0;
    let match = anyTag.exec(fragment);
    while (match !== null) {
      parts.push(fragment.slice(last, match.index));
      const tagName: string = match[1].toLowerCase();
      if (tagName === 'img') {
        const src: string = ContentExtractor.imageSrc(match[0]);
        const url: string = src.length > 0
          ? ReaderBody.imageUrl(src, baseUrl) : '';
        if (url.length > 0) {
          images.push('<img src="' + url + '">');
          parts.push('\u0002' + (images.length - 1).toString() + '\u0002');
        }
      } else if (ContentExtractor.KEEP_TAGS.indexOf(tagName) >= 0) {
        parts.push(match[0]);
      } else {
        parts.push(' ');
      }
      last = match.index + match[0].length;
      match = anyTag.exec(fragment);
    }
    parts.push(fragment.slice(last));

    let out: string = parts.join('');
    // Attributes carry no value in a text-only reader, except the image URL
    // parked above as a marker.
    out = out.replace(/<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>/g, '<$1>');
    out = FeedParser.decodeEntities(out);
    out = out.replace(/\u0002(\d+)\u0002/g, (marker: string, index: string): string => {
      const at: number = parseInt(index, 10);
      return (at >= 0 && at < images.length) ? images[at] : '';
    });
    out = out.replace(/\s+/g, ' ').trim();
    return out;
  }
}
