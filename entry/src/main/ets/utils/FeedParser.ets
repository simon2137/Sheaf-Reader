import { Feed, Article, FeedGroup, ParsedFeed, ParsedOpml, OpmlEntry } from '../model/Models';

const MONTHS: string[] = ['jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

const ENTITIES: string[] = ['&nbsp;', '&amp;', '&lt;', '&gt;', '&quot;', '&#39;'];
const ENTITY_VALUES: string[] = [' ', '&', '<', '>', '"', "'"];

/**
 * RSS/Atom feed parser.
 * Supports RSS 2.0, RSS 1.0 (RDF) and Atom 1.0 without external dependencies.
 */
export class FeedParser {
  /**
   * Parse feed XML into feed metadata plus its articles.
   */
  static parse(xmlContent: string, feedUrl: string): ParsedFeed | null {
    try {
      const isAtom: boolean =
        xmlContent.indexOf('<feed') >= 0 && xmlContent.indexOf('http://www.w3.org/2005/Atom') >= 0;
      if (isAtom) {
        return FeedParser.parseAtom(xmlContent, feedUrl);
      }
      return FeedParser.parseRss(xmlContent, feedUrl);
    } catch (err) {
      console.error('FeedParser.parse failed: ' + JSON.stringify(err));
      return null;
    }
  }

  private static parseRss(xml: string, feedUrl: string): ParsedFeed | null {
    const channelMatch: RegExpMatchArray | null =
      xml.match(/<channel[^>]*>([\s\S]*?)<\/channel>/i);
    if (channelMatch === null) {
      return null;
    }
    const channel: string = channelMatch[1];

    const feed: Feed = new Feed(feedUrl, '');
    feed.title = FeedParser.decodeEntities(FeedParser.extractTag(channel, 'title')) || 'Untitled Feed';
    feed.link = FeedParser.extractTag(channel, 'link');
    feed.description = FeedParser.decodeEntities(FeedParser.extractTag(channel, 'description'));

    const articles: Article[] = [];
    const itemRegex: RegExp = /<item[^>]*>([\s\S]*?)<\/item>/gi;
    let itemMatch: RegExpExecArray | null = itemRegex.exec(xml);

    while (itemMatch !== null) {
      articles.push(FeedParser.parseRssItem(itemMatch[1]));
      itemMatch = itemRegex.exec(xml);
    }

    return { feed: feed, articles: articles };
  }

  private static parseRssItem(itemXml: string): Article {
    const article: Article = new Article();
    article.title = FeedParser.decodeEntities(FeedParser.extractTag(itemXml, 'title')) || 'Untitled';
    article.link = FeedParser.extractTag(itemXml, 'link');

    const contentEncoded: string = FeedParser.extractTag(itemXml, 'content:encoded');
    const description: string = FeedParser.extractTag(itemXml, 'description');
    article.content = contentEncoded.length > 0 ? contentEncoded : description;
    article.snippet = FeedParser.stripHtml(description.length > 0 ? description : contentEncoded);

    const pubDate: string = FeedParser.extractTag(itemXml, 'pubDate');
    article.published = FeedParser.parseDate(pubDate.length > 0 ? pubDate
      : FeedParser.extractTag(itemXml, 'dc:date'));

    article.guid = FeedParser.stableId(FeedParser.extractTag(itemXml, 'guid'),
      article.link, article.title, article.published);

    const author: string = FeedParser.extractTag(itemXml, 'author');
    article.author = FeedParser.decodeEntities(author.length > 0 ? author
      : FeedParser.extractTag(itemXml, 'dc:creator'));

    article.imageUrl = FeedParser.extractImage(itemXml);
    article.fetched = Date.now();
    return article;
  }

  /**
   * Feeds frequently omit or duplicate identifiers. Produce a deterministic
   * non-empty key so the (feed_id, guid) unique index keeps deduplicating
   * correctly across refreshes.
   */
  private static stableId(guid: string, link: string, title: string, published: number): string {
    if (guid.length > 0) {
      return guid;
    }
    if (link.length > 0) {
      return link;
    }
    return title.concat('#').concat(published.toString());
  }

  private static parseAtom(xml: string, feedUrl: string): ParsedFeed | null {
    const feedMatch: RegExpMatchArray | null = xml.match(/<feed[^>]*>([\s\S]*?)<\/feed>/i);
    if (feedMatch === null) {
      return null;
    }
    const feedXml: string = feedMatch[1];

    const feed: Feed = new Feed(feedUrl, '');
    feed.title = FeedParser.decodeEntities(FeedParser.extractTag(feedXml, 'title')) || 'Untitled Feed';
    feed.link = FeedParser.extractAttr(feedXml, 'link', 'href');
    feed.description = FeedParser.decodeEntities(FeedParser.extractTag(feedXml, 'subtitle'));

    const articles: Article[] = [];
    const entryRegex: RegExp = /<entry[^>]*>([\s\S]*?)<\/entry>/gi;
    let entryMatch: RegExpExecArray | null = entryRegex.exec(xml);

    while (entryMatch !== null) {
      articles.push(FeedParser.parseAtomEntry(entryMatch[1]));
      entryMatch = entryRegex.exec(xml);
    }

    return { feed: feed, articles: articles };
  }

  private static parseAtomEntry(entryXml: string): Article {
    const article: Article = new Article();
    article.title = FeedParser.decodeEntities(FeedParser.extractTag(entryXml, 'title')) || 'Untitled';
    article.link = FeedParser.extractAttr(entryXml, 'link', 'href');

    const content: string = FeedParser.extractTag(entryXml, 'content');
    const summary: string = FeedParser.extractTag(entryXml, 'summary');
    article.content = content.length > 0 ? content : summary;
    article.snippet = FeedParser.stripHtml(summary.length > 0 ? summary : content);

    const published: string = FeedParser.extractTag(entryXml, 'published');
    article.published = FeedParser.parseDate(published.length > 0 ? published
      : FeedParser.extractTag(entryXml, 'updated'));

    article.guid = FeedParser.stableId(FeedParser.extractTag(entryXml, 'id'),
      article.link, article.title, article.published);

    article.author = FeedParser.decodeEntities(FeedParser.extractAtomAuthor(entryXml));
    article.fetched = Date.now();
    return article;
  }

  private static extractAtomAuthor(entryXml: string): string {
    const authorMatch: RegExpMatchArray | null =
      entryXml.match(/<author[^>]*>[\s\S]*?<name[^>]*>([\s\S]*?)<\/name>/i);
    if (authorMatch !== null) {
      return authorMatch[1].trim();
    }
    return '';
  }

  private static extractImage(itemXml: string): string {
    const enclosure: RegExpMatchArray | null =
      itemXml.match(/<enclosure[^>]+url="([^"]+)"[^>]*>/i);
    if (enclosure !== null) {
      return enclosure[1];
    }
    const media: RegExpMatchArray | null =
      itemXml.match(/<media:content[^>]+url="([^"]+)"[^>]*>/i);
    if (media !== null) {
      return media[1];
    }
    const img: RegExpMatchArray | null = itemXml.match(/<img[^>]+src="([^"]+)"/i);
    if (img !== null) {
      return img[1];
    }
    return '';
  }

  /**
   * Extract the text content between a pair of tags.
   *
   * A single element may legally hold several CDATA sections interleaved with
   * whitespace (阮一峰's Atom feed does exactly this for <content>), so the
   * naive "<tag><![CDATA[x]]></tag>" pattern is not enough: it fails to match
   * and the raw markup leaks into the article body. Locate the element first,
   * then concatenate every CDATA block it contains.
   */
  private static extractTag(xml: string, tagName: string): string {
    const openRegex: RegExp = new RegExp('<'.concat(tagName).concat('(?:\\s[^>]*)?>'), 'i');
    const openMatch: RegExpExecArray | null = openRegex.exec(xml);
    if (openMatch === null) {
      return '';
    }

    const innerStart: number = openMatch.index + openMatch[0].length;
    const closeTag: string = '</'.concat(tagName.toLowerCase()).concat('>');
    const closeIndex: number = xml.toLowerCase().indexOf(closeTag, innerStart);
    if (closeIndex < 0) {
      return '';
    }

    const inner: string = xml.substring(innerStart, closeIndex);
    return FeedParser.joinCdata(inner).trim();
  }

  /**
   * Concatenate every CDATA section found in the fragment. When the fragment
   * carries no CDATA at all it is returned unchanged.
   */
  private static joinCdata(fragment: string): string {
    const cdataRegex: RegExp = /<!\[CDATA\[([\s\S]*?)\]\]>/g;
    let result: string = '';
    let sawCdata: boolean = false;

    let match: RegExpExecArray | null = cdataRegex.exec(fragment);
    while (match !== null) {
      sawCdata = true;
      result = result.concat(match[1]);
      match = cdataRegex.exec(fragment);
    }

    return sawCdata ? result : fragment;
  }

  /**
   * Extract an attribute value from the first matching self-closing tag.
   */
  private static extractAttr(xml: string, tagName: string, attrName: string): string {
    const regex: RegExp = new RegExp('<'.concat(tagName).concat('[^>]*\\s')
      .concat(attrName).concat('="([^"]+)"'), 'i');
    const match: RegExpMatchArray | null = xml.match(regex);
    if (match !== null) {
      return match[1];
    }
    return '';
  }

  /**
   * Strip markup and return a bounded plain-text snippet.
   */
  static stripHtml(html: string): string {
    if (!html) {
      return '';
    }
    let text: string = html.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, ' ');
    text = text.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, ' ');
    // Defence in depth: never let CDATA markers reach the reader.
    text = text.replace(/<!\[CDATA\[/g, ' ');
    text = text.replace(/\]\]>/g, ' ');
    // Many feeds (e.g. sspai) entity-escape the HTML inside <description>, so
    // the markup only becomes visible after decoding. Decode first, then strip;
    // repeat once so double-escaped payloads are unwrapped too.
    text = FeedParser.decodeEntities(text);
    text = text.replace(/<[^>]*>/g, ' ');
    text = FeedParser.decodeEntities(text);
    text = text.replace(/<[^>]*>/g, ' ');
    text = text.replace(/\s+/g, ' ').trim();
    if (text.length > 300) {
      text = text.substring(0, 300).concat('...');
    }
    return text;
  }

  /**
   * Port of the original `htmlDecode`: parse the fragment as HTML and take its
   * text content, stripping markup and decoding entities **without**
   * truncating. Used by the sync-service path for article snippets.
   *
   * The DOM `textContent` in the original does not insert separators where a
   * tag was, so `<p>a</p><p>b</p>` becomes `ab` there. A single space is used
   * here instead, which avoids words running together when feeds omit
   * whitespace between block tags.
   */
  static htmlDecode(input: string): string {
    if (!input) {
      return '';
    }
    let text: string = input.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, ' ');
    text = text.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, ' ');
    text = text.replace(/<!\[CDATA\[/g, ' ');
    text = text.replace(/\]\]>/g, ' ');
    text = FeedParser.decodeEntities(text);
    text = text.replace(/<[^>]*>/g, ' ');
    text = FeedParser.decodeEntities(text);
    text = text.replace(/<[^>]*>/g, ' ');
    return text.replace(/\s+/g, ' ').trim();
  }

  /**
   * Extract the first `<img src>` from a fragment, mirroring the original's
   * thumbnail probe. Relative references are resolved against `baseUrl`.
   */
  static firstImageSrc(html: string, baseUrl: string): string {
    if (!html) {
      return '';
    }
    let match: RegExpMatchArray | null = html.match(/<img[^>]+src\s*=\s*["']([^"']+)["']/i);
    if (match === null) {
      match = html.match(/<img[^>]+src\s*=\s*([^\s>]+)/i);
    }
    if (match === null) {
      return '';
    }
    const src: string = match[1];
    if (/^https?:\/\//i.test(src)) {
      return src;
    }
    if (src.startsWith('//')) {
      return 'https:'.concat(src);
    }
    return '';
  }

  /**
   * Decode the common HTML entities found in feed payloads.
   */
  static decodeEntities(text: string): string {
    if (!text) {
      return '';
    }
    let out: string = text;
    for (let i = 0; i < ENTITIES.length; i++) {
      out = out.split(ENTITIES[i]).join(ENTITY_VALUES[i]);
    }
    return out.trim();
  }

  /**
   * Parse the date formats commonly used by feeds into a timestamp.
   */
  private static parseDate(dateStr: string): number {
    if (!dateStr) {
      return Date.now();
    }

    const direct: number = Date.parse(dateStr);
    if (!isNaN(direct)) {
      return direct;
    }

    const parts: RegExpMatchArray | null = dateStr.match(
      /(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?/);
    if (parts !== null) {
      const day: number = parseInt(parts[1], 10);
      const month: number = MONTHS.indexOf(parts[2].toLowerCase());
      let year: number = parseInt(parts[3], 10);
      if (year < 100) {
        year += year < 70 ? 2000 : 1900;
      }
      const hour: number = parseInt(parts[4], 10);
      const minute: number = parseInt(parts[5], 10);
      const second: number = parts[6] ? parseInt(parts[6], 10) : 0;
      const parsed: number = Date.UTC(year, month < 0 ? 0 : month, day, hour, minute, second);
      if (!isNaN(parsed)) {
        return parsed;
      }
    }

    return Date.now();
  }

  /**
   * Serialise feeds and groups into an OPML 2.0 document.
   */
  static generateOpml(feeds: Feed[], groups: FeedGroup[]): string {
    let opml: string = '<?xml version="1.0" encoding="UTF-8"?>\n'
      .concat('<opml version="2.0">\n  <head>\n')
      .concat('    <title>Sheaf Reader Subscriptions</title>\n')
      .concat('  </head>\n  <body>\n');

    const grouped: Map<number, Feed[]> = new Map<number, Feed[]>();
    const ungrouped: Feed[] = [];

    for (const feed of feeds) {
      if (feed.groupId >= 0) {
        const bucket: Feed[] | undefined = grouped.get(feed.groupId);
        if (bucket === undefined) {
          grouped.set(feed.groupId, [feed]);
        } else {
          bucket.push(feed);
        }
      } else {
        ungrouped.push(feed);
      }
    }

    for (const group of groups) {
      const groupFeeds: Feed[] | undefined = grouped.get(group.id);
      if (groupFeeds === undefined || groupFeeds.length === 0) {
        continue;
      }
      const safeName: string = FeedParser.escapeXml(group.name);
      opml = opml.concat('    <outline text="').concat(safeName)
        .concat('" title="').concat(safeName).concat('">\n');
      for (const feed of groupFeeds) {
        opml = opml.concat(FeedParser.feedOutline(feed, '      '));
      }
      opml = opml.concat('    </outline>\n');
    }

    for (const feed of ungrouped) {
      opml = opml.concat(FeedParser.feedOutline(feed, '    '));
    }

    opml = opml.concat('  </body>\n</opml>\n');
    return opml;
  }

  private static feedOutline(feed: Feed, indent: string): string {
    const title: string = FeedParser.escapeXml(feed.title);
    return indent.concat('<outline type="rss" text="').concat(title)
      .concat('" title="').concat(title)
      .concat('" xmlUrl="').concat(FeedParser.escapeXml(feed.url))
      .concat('" htmlUrl="').concat(FeedParser.escapeXml(feed.link))
      .concat('"/>\n');
  }

  /**
   * Parse an OPML document into feed entries.
   *
   * OPML groups are nested <outline> elements, so the group a feed belongs to
   * is the innermost enclosing outline. A flat "last seen group" cursor is not
   * enough: a top-level feed that follows a closed group would otherwise be
   * attributed to that group. An explicit open-element stack keeps the nesting
   * correct.
   */
  static parseOpml(opmlContent: string): ParsedOpml {
    const entries: OpmlEntry[] = [];
    const tokenRegex: RegExp = /<outline\b[^>]*>|<\/outline>/gi;

    // Innermost group names, outermost first.
    const groupStack: string[] = [];
    // One flag per currently open <outline>: true when it pushed a group.
    const openStack: boolean[] = [];

    let match: RegExpExecArray | null = tokenRegex.exec(opmlContent);
    while (match !== null) {
      const token: string = match[0];

      if (token.substring(0, 2) === '</') {
        if (openStack.length > 0) {
          const wasGroup: boolean = openStack.pop() as boolean;
          if (wasGroup && groupStack.length > 0) {
            groupStack.pop();
          }
        }
      } else {
        const selfClosing: boolean = /\/\s*>$/.test(token);
        const url: string = FeedParser.attrOf(token, 'xmlUrl');
        const currentGroup: string = groupStack.length > 0
          ? groupStack[groupStack.length - 1] : '';

        if (url.length > 0) {
          let title: string = FeedParser.attrOf(token, 'text');
          if (title.length === 0) {
            title = FeedParser.attrOf(token, 'title');
          }
          entries.push({ url: url, title: title, groupName: currentGroup });
          if (!selfClosing) {
            openStack.push(false);
          }
        } else {
          let name: string = FeedParser.attrOf(token, 'text');
          if (name.length === 0) {
            name = FeedParser.attrOf(token, 'title');
          }
          if (!selfClosing) {
            groupStack.push(name);
            openStack.push(true);
          }
        }
      }
      match = tokenRegex.exec(opmlContent);
    }

    return { entries: entries };
  }

  private static attrOf(tag: string, attrName: string): string {
    const regex: RegExp = new RegExp(attrName.concat('="([^"]*)"'), 'i');
    const match: RegExpMatchArray | null = tag.match(regex);
    if (match !== null) {
      return FeedParser.decodeEntities(match[1]);
    }
    return '';
  }

  private static escapeXml(text: string): string {
    let out: string = text ? text : '';
    out = out.split('&').join('&amp;');
    out = out.split('<').join('&lt;');
    out = out.split('>').join('&gt;');
    out = out.split('"').join('&quot;');
    out = out.split("'").join('&apos;');
    return out;
  }
}
