import { FeedParser } from './FeedParser';
import { UrlUtils } from './UrlUtils';

/**
 * One rendered piece of an article body.
 *
 * The original renders the article HTML in a webview, so paragraphs, lists,
 * inline images and inline video all appear exactly as the feed or the
 * extracted page wrote them. ArkUI has no HTML view, so the body is split here
 * into the three things the reader can actually draw: text paragraphs, images
 * and video.
 */
export interface ReaderBlock {
  /** `ReaderBody.TEXT`, `ReaderBody.IMAGE` or `ReaderBody.VIDEO`. */
  kind: number;
  /** Paragraph text, the absolute image URL, or the absolute video URL. */
  value: string;
  /** Poster URL for a video block; '' for text and image blocks. */
  poster: string;
}

/**
 * Turns stored article HTML into reader blocks. Pure string work, so the
 * harness can exercise it under Node.
 */
export class ReaderBody {
  static readonly TEXT: number = 0;
  static readonly IMAGE: number = 1;
  static readonly VIDEO: number = 2;

  private static readonly IMG_TAG = /<img\b[^>]*>/gi;
  /**
   * A whole `<video>` element, or a self-closing one. Feeds that publish video
   * items often ship nothing else, so without this the reader showed a blank
   * body for them (`<p><video src=… poster=…></video></p>` is the common shape).
   */
  private static readonly VIDEO_TAG = /<video\b[^>]*>[\s\S]*?<\/video\s*>|<video\b[^>]*\/?>/gi;
  /** A `<video>` may carry its file in a nested `<source>` instead of `src`. */
  private static readonly SOURCE_TAG = /<source\b[^>]*>/i;
  private static readonly SRC_ATTR = /\bsrc\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/i;
  private static readonly POSTER_ATTR = /\bposter\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/i;
  /** Paragraph break, so a body without block tags still becomes paragraphs. */
  private static readonly BLOCK_CLOSE = /<\/(p|div|h[1-6]|li|tr|blockquote|figure|figcaption|section|article)\s*>/gi;

  /**
   * Absolute URL for an image reference, or '' when it cannot be drawn.
   *
   * Relative references are resolved against the article (or fetched page)
   * URL, which is what the original's webview gets for free. `data:` URIs are
   * already self-contained and are kept as-is.
   */
  static imageUrl(src: string, baseUrl: string): string {
    return ReaderBody.mediaUrl(src, baseUrl, 'data:image/');
  }

  /**
   * Absolute URL for a video reference, or '' when it cannot be played.
   *
   * Same resolution rules as an image. `blob:` URLs are deliberately *not*
   * kept: they only mean anything inside the page that created them, so a
   * player here could never load one.
   */
  static videoUrl(src: string, baseUrl: string): string {
    return ReaderBody.mediaUrl(src, baseUrl, 'data:video/');
  }

  private static mediaUrl(src: string, baseUrl: string, dataPrefix: string): string {
    let url: string = src.trim();
    if (url.length === 0) {
      return '';
    }
    if (url.startsWith(dataPrefix)) {
      return url;
    }
    if (url.startsWith('//')) {
      url = 'https:' + url;
    }
    if (!UrlUtils.isAbsolute(url)) {
      if (baseUrl.length === 0) {
        return '';
      }
      url = UrlUtils.resolve(baseUrl, url);
    }
    return UrlUtils.isAbsolute(url) ? url : '';
  }

  /**
   * Normalise the body into markup this class can split: entities decoded once
   * (feeds deliver escaped markup), scripts and styles gone, CDATA markers
   * stripped, block ends and `<br>` turned into line breaks.
   */
  private static normalise(html: string): string {
    let out: string = html.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '');
    out = out.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '');
    out = out.replace(/<!\[CDATA\[/g, '');
    out = out.replace(/\]\]>/g, '');
    // Decode before splitting so escaped markup is seen as markup.
    out = FeedParser.decodeEntities(out);
    out = out.replace(ReaderBody.BLOCK_CLOSE, '\n\n');
    out = out.replace(/<br\s*\/?>/gi, '\n');
    // A list item becomes a bullet, as the text-only reader always did.
    out = out.replace(/<li[^>]*>/gi, '\u2022 ');
    return out;
  }

  /** Strip every remaining tag from a paragraph and tidy its whitespace. */
  private static paragraphText(fragment: string): string {
    let out: string = fragment.replace(/<[^>]*>/g, '');
    // A second pass covers double-escaped content.
    out = FeedParser.decodeEntities(out);
    out = out.replace(/<[^>]*>/g, '');
    out = out.replace(/&nbsp;/g, ' ');
    out = out.replace(/[ \t]+/g, ' ');
    return out.trim();
  }

  private static attrOf(tag: string, pattern: RegExp): string {
    const match: RegExpExecArray | null = pattern.exec(tag);
    if (match === null) {
      return '';
    }
    let raw: string = match[1];
    if (raw.length >= 2 && (raw.charAt(0) === '"' || raw.charAt(0) === '\'')) {
      raw = raw.slice(1, raw.length - 1);
    }
    return FeedParser.decodeEntities(raw);
  }

  private static srcOf(tag: string): string {
    return ReaderBody.attrOf(tag, ReaderBody.SRC_ATTR);
  }

  private static posterOf(tag: string): string {
    return ReaderBody.attrOf(tag, ReaderBody.POSTER_ATTR);
  }

  /**
   * Split the body into paragraphs, images and videos, in document order.
   *
   * Each `<img>` and `<video>` becomes its own block so it can be drawn between
   * the paragraphs around it; everything between two markers becomes a
   * paragraph block. Empty paragraphs are dropped, so a body that is only an
   * image — or only a video — still yields exactly one block.
   */
  static blocks(html: string, baseUrl: string): ReaderBlock[] {
    if (!html) {
      return [];
    }
    // Images and videos share one list so the markers keep document order.
    const media: ReaderBlock[] = [];
    let marked: string = ReaderBody.normalise(html);
    marked = marked.replace(ReaderBody.VIDEO_TAG, (tag: string): string => {
      let src: string = ReaderBody.videoUrl(ReaderBody.srcOf(tag), baseUrl);
      if (src.length === 0) {
        const nested: RegExpExecArray | null = ReaderBody.SOURCE_TAG.exec(tag);
        if (nested !== null) {
          src = ReaderBody.videoUrl(ReaderBody.srcOf(nested[0]), baseUrl);
        }
      }
      if (src.length === 0) {
        return '\n\n';
      }
      media.push({
        kind: ReaderBody.VIDEO,
        value: src,
        poster: ReaderBody.imageUrl(ReaderBody.posterOf(tag), baseUrl)
      });
      return '\n\n\u0001' + (media.length - 1).toString() + '\u0001\n\n';
    });
    marked = marked.replace(ReaderBody.IMG_TAG, (tag: string): string => {
      const url: string = ReaderBody.imageUrl(ReaderBody.srcOf(tag), baseUrl);
      if (url.length === 0) {
        return '\n\n';
      }
      media.push({ kind: ReaderBody.IMAGE, value: url, poster: '' });
      return '\n\n\u0001' + (media.length - 1).toString() + '\u0001\n\n';
    });

    const out: ReaderBlock[] = [];
    for (const piece of marked.split('\n')) {
      const trimmed: string = piece.trim();
      if (trimmed.length === 0) {
        continue;
      }
      const marker = /^\u0001(\d+)\u0001$/.exec(trimmed);
      if (marker !== null) {
        const index: number = parseInt(marker[1], 10);
        if (index >= 0 && index < media.length) {
          out.push(media[index]);
        }
        continue;
      }
      const text: string = ReaderBody.paragraphText(trimmed);
      if (text.length > 0) {
        out.push({ kind: ReaderBody.TEXT, value: text, poster: '' });
      }
    }
    return out;
  }

  /**
   * The body as plain text, paragraphs separated by a blank line.
   *
   * The text projection of the block model, and what the harness asserts the
   * media never reaches. It is deliberately *not* what selected-text search
   * uses: ArkUI measures a `TextRange` against the one `Text` the menu was
   * opened on, so the reader slices that block rather than the whole body.
   */
  static text(html: string): string {
    if (!html) {
      return '';
    }
    const parts: string[] = [];
    for (const block of ReaderBody.blocks(html, '')) {
      if (block.kind === ReaderBody.TEXT) {
        parts.push(block.value);
      }
    }
    if (parts.length > 0) {
      return parts.join('\n\n');
    }
    // An image-only body still needs the alt-free fallback the caller expects.
    const fallback: string = ReaderBody.paragraphText(ReaderBody.normalise(html));
    return fallback.trim();
  }
}
