/**
 * Minimal URL helpers. ArkTS does not expose the DOM `URL` constructor,
 * so the pieces needed by the feed fetcher are implemented explicitly.
 */
export class UrlUtils {
  /**
   * Return true when the string looks like an absolute HTTP(S) URL.
   */
  static isAbsolute(url: string): boolean {
    return /^https?:\/\//i.test(url);
  }

  /**
   * Extract the scheme + host + port portion of a URL.
   */
  static origin(url: string): string {
    const match: RegExpMatchArray | null = url.match(/^(https?:\/\/[^\/?#]+)/i);
    if (match !== null) {
      return match[1];
    }
    return '';
  }

  /**
   * Extract the host name of a URL.
   */
  static host(url: string): string {
    const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^\/?#:]+)/i);
    if (match !== null) {
      return match[1];
    }
    return '';
  }

  /**
   * Resolve a possibly relative reference against a base URL.
   */
  static resolve(base: string, reference: string): string {
    if (!reference) {
      return base;
    }
    if (UrlUtils.isAbsolute(reference)) {
      return reference;
    }
    // Protocol-relative reference: //host/path
    if (reference.startsWith('//')) {
      const schemeMatch: RegExpMatchArray | null = base.match(/^(https?:)/i);
      const scheme: string = schemeMatch !== null ? schemeMatch[1] : 'https:';
      return scheme.concat(reference);
    }

    const origin: string = UrlUtils.origin(base);
    if (reference.startsWith('/')) {
      return origin.concat(reference);
    }

    // Relative to the base directory
    let dir: string = base;
    const queryIndex: number = dir.indexOf('?');
    if (queryIndex >= 0) {
      dir = dir.substring(0, queryIndex);
    }
    const hashIndex: number = dir.indexOf('#');
    if (hashIndex >= 0) {
      dir = dir.substring(0, hashIndex);
    }
    const lastSlash: number = dir.lastIndexOf('/');
    if (lastSlash > origin.length) {
      dir = dir.substring(0, lastSlash + 1);
    } else {
      dir = origin.concat('/');
    }
    return dir.concat(reference);
  }

  /**
   * Normalise a user-typed address into an absolute URL.
   */
  static normalize(input: string): string {
    const trimmed: string = input.trim();
    if (!trimmed) {
      return '';
    }
    if (UrlUtils.isAbsolute(trimmed)) {
      return trimmed;
    }
    return 'https://'.concat(trimmed);
  }
}
