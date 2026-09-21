import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ParsedFeed } from '../model/Models';
import { FeedParser } from './FeedParser';
import { UrlUtils } from './UrlUtils';

/**
 * Service that fetches and parses feeds over HTTP(S).
 */
export class FeedFetcher {
  private static readonly TIMEOUT: number = 20000;
  private static readonly USER_AGENT: string =
    'Mozilla/5.0 (HarmonyOS; Tablet/2in1) SheafReader-HM/1.0';

  /**
   * Reason for the most recent failure, so the caller can put it in the
   * notification log. Distinguishes transport problems from unparseable
   * payloads, matching the original's `log.networkError` / `log.parseError`.
   */
  static lastError: string = '';

  /**
   * Fetch and parse a feed. Returns null when the payload is not a valid feed.
   */
  static async fetchFeed(url: string): Promise<ParsedFeed | null> {
    FeedFetcher.lastError = '';
    const content: string | null = await FeedFetcher.fetchUrl(url);
    if (content === null || content.length === 0) {
      if (FeedFetcher.lastError.length === 0) {
        FeedFetcher.lastError = 'The server returned an empty response';
      }
      return null;
    }

    const parsed: ParsedFeed | null = FeedParser.parse(content, url);
    if (parsed === null) {
      FeedFetcher.lastError = 'An error occurred while parsing the XML feed';
      return null;
    }

    parsed.feed.iconUrl = FeedFetcher.faviconFor(url, parsed.feed.link);
    return parsed;
  }

  /**
   * Perform an HTTP GET and return the response body as text.
   */
  static async fetchUrl(url: string): Promise<string | null> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': FeedFetcher.USER_AGENT,
          'Accept': 'application/rss+xml, application/atom+xml, application/rdf+xml, application/xml, text/xml, text/html, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
        },
        connectTimeout: FeedFetcher.TIMEOUT,
        readTimeout: FeedFetcher.TIMEOUT,
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode === 200) {
        const body: string = response.result as string;
        return body;
      }
      FeedFetcher.lastError = 'A network error occurred (HTTP '
        .concat(response.responseCode.toString()).concat(')');
      console.warn('FeedFetcher: HTTP ' + response.responseCode + ' for ' + url);
      return null;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      FeedFetcher.lastError = 'A network error occurred ('
        .concat(error.code.toString()).concat(': ').concat(error.message).concat(')');
      console.error('FeedFetcher: request failed ' + error.code + ' ' + error.message);
      return null;
    } finally {
      request.destroy();
    }
  }

  /**
   * Attempt to locate a feed for a human-facing website address.
   */
  static async discoverFeed(siteUrl: string): Promise<string | null> {
    const content: string | null = await FeedFetcher.fetchUrl(siteUrl);
    if (content !== null) {
      const linkRegex: RegExp =
        /<link[^>]+type="application\/(?:rss|atom|rdf)\+xml"[^>]*>/gi;
      let match: RegExpExecArray | null = linkRegex.exec(content);
      while (match !== null) {
        const hrefMatch: RegExpMatchArray | null = match[0].match(/href="([^"]+)"/i);
        if (hrefMatch !== null) {
          return UrlUtils.resolve(siteUrl, hrefMatch[1]);
        }
        match = linkRegex.exec(content);
      }
    }

    const origin: string = UrlUtils.origin(siteUrl);
    if (!origin) {
      return null;
    }

    const candidates: string[] = ['/feed', '/rss', '/rss.xml', '/atom.xml',
      '/feed.xml', '/index.xml', '/feeds/posts/default'];
    for (const path of candidates) {
      const probe: string = origin.concat(path);
      const probeBody: string | null = await FeedFetcher.fetchUrl(probe);
      if (probeBody !== null && FeedFetcher.looksLikeFeed(probeBody)) {
        return probe;
      }
    }
    return null;
  }

  /**
   * Heuristic check for feed payloads.
   */
  static looksLikeFeed(content: string): boolean {
    const head: string = content.substring(0, 2000);
    return head.indexOf('<rss') >= 0 || head.indexOf('<feed') >= 0
      || head.indexOf('<rdf:RDF') >= 0 || head.indexOf('<rdf:rdf') >= 0;
  }

  private static faviconFor(feedUrl: string, siteUrl: string): string {
    const base: string = siteUrl && UrlUtils.origin(siteUrl) ? siteUrl : feedUrl;
    const origin: string = UrlUtils.origin(base);
    if (!origin) {
      return '';
    }
    return origin.concat('/favicon.ico');
  }
}
