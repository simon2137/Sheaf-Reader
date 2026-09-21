import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/**
 * Result of a raw HTTP call. The sync-service ports need the status code and
 * the raw body rather than a pre-parsed object, because the Miniflux API
 * signals success with 204 (empty body) and errors with a JSON envelope.
 */
export class HttpResult {
  status: number = 0;
  body: string = '';
  /** Transport-level failure message; empty when the request completed. */
  error: string = '';

  ok(): boolean {
    return this.error.length === 0 && this.status >= 200 && this.status < 300;
  }

  succeeded(): boolean {
    return this.ok();
  }
}

/**
 * Thin JSON-oriented wrapper over `@kit.NetworkKit`'s http module.
 */
export class HttpClient {
  /** Verb names mirroring the string verbs used by the ported services. */
  static readonly GET: string = 'GET';
  static readonly POST: string = 'POST';
  static readonly PUT: string = 'PUT';
  static readonly DELETE: string = 'DELETE';

  private static readonly TIMEOUT: number = 30000;

  private static methodOf(verb: string): http.RequestMethod {
    switch (verb) {
      case HttpClient.POST:
        return http.RequestMethod.POST;
      case HttpClient.PUT:
        return http.RequestMethod.PUT;
      case HttpClient.DELETE:
        return http.RequestMethod.DELETE;
      default:
        return http.RequestMethod.GET;
    }
  }

  /**
   * Download a binary resource (an image) as raw bytes.
   *
   * Kept separate from `send` because the response cannot go through the
   * string-typed `HttpResult`; a failed decode would corrupt the bytes.
   */
  static async fetchBytes(url: string): Promise<ArrayBuffer | null> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: HttpClient.TIMEOUT,
        readTimeout: HttpClient.TIMEOUT,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      const response: http.HttpResponse = await request.request(url, options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return null;
      }
      if (response.result === undefined || response.result === null) {
        return null;
      }
      return response.result as ArrayBuffer;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('HttpClient.fetchBytes failed ' + url + ' -> ' + error.message);
      return null;
    } finally {
      request.destroy();
    }
  }

  /**
   * Perform a request and return status plus body. Transport errors are
   * reported through `HttpResult.error` rather than thrown, so callers can
   * mirror the original's `APIError()` handling.
   */
  static async send(verb: string, url: string, headers: Record<string, string>,
    body: string): Promise<HttpResult> {
    const result: HttpResult = new HttpResult();
    const request: http.HttpRequest = http.createHttp();

    try {
      // `extraData` must be omitted entirely for bodyless requests: the SDK
      // rejects an empty string with errcode 401 (parameter error), which is
      // easy to misread as an HTTP 401 from the server.
      let options: http.HttpRequestOptions;
      if (body.length > 0) {
        options = {
          method: HttpClient.methodOf(verb),
          header: headers,
          connectTimeout: HttpClient.TIMEOUT,
          readTimeout: HttpClient.TIMEOUT,
          expectDataType: http.HttpDataType.STRING,
          extraData: body
        };
      } else {
        options = {
          method: HttpClient.methodOf(verb),
          header: headers,
          connectTimeout: HttpClient.TIMEOUT,
          readTimeout: HttpClient.TIMEOUT,
          expectDataType: http.HttpDataType.STRING
        };
      }

      const response: http.HttpResponse = await request.request(url, options);
      result.status = response.responseCode;
      if (response.result !== undefined && response.result !== null) {
        result.body = response.result as string;
      }
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      result.error = 'HTTP ' + error.code + ': ' + error.message;
      console.error('HttpClient.send failed ' + verb + ' ' + url + ' -> ' + result.error);
    } finally {
      request.destroy();
    }

    return result;
  }

  /**
   * Normalise a Miniflux endpoint into a `/v1/` base URL, matching the
   * original's `fetchAPI` behaviour.
   */
  static minifluxBase(endpoint: string): string {
    let base: string = endpoint ? endpoint.trim() : '';
    if (base.length === 0) {
      return '';
    }
    if (!base.endsWith('/')) {
      base = base.concat('/');
    }
    if (!base.endsWith('/v1/')) {
      base = base.concat('v1/');
    }
    return base;
  }

  /**
   * Normalise a Feedbin endpoint into its `/v2/` base. Feedbin is a hosted
   * service, so an empty endpoint means the public API host.
   */
  static feedbinBase(endpoint: string): string {
    let base: string = endpoint ? endpoint.trim() : '';
    if (base.length === 0) {
      base = 'https://api.feedbin.com';
    }
    if (!base.endsWith('/')) {
      base = base.concat('/');
    }
    if (!base.endsWith('/v2/')) {
      base = base.concat('v2/');
    }
    return base;
  }

  /**
   * Normalise a Nextcloud endpoint into the News app's v1-3 API base. The user
   * enters the instance root; the app path is appended unless already present.
   */
  static nextcloudBase(endpoint: string): string {
    let base: string = endpoint ? endpoint.trim() : '';
    if (base.length === 0) {
      return '';
    }
    if (!base.endsWith('/')) {
      base = base.concat('/');
    }
    if (base.indexOf('/apps/news/api/') < 0) {
      base = base.concat('index.php/apps/news/api/v1-3/');
    }
    return base;
  }

  /**
   * Normalise a Fever endpoint into the API URL, up to and including `?api`.
   *
   * The documented form is `https://host/fever/?api`, but users paste all of
   * that, a bare instance root, or a FreshRSS-style `.../api/fever.php`, so all
   * three are accepted and the result is idempotent.
   */
  static feverBase(endpoint: string): string {
    let base: string = endpoint ? endpoint.trim() : '';
    if (base.length === 0) {
      return '';
    }
    const marker: number = base.indexOf('?api');
    if (marker >= 0) {
      base = base.substring(0, marker);
    }
    if (!base.endsWith('/') && base.indexOf('.php') < 0) {
      base = base.concat('/');
    }
    if (base.endsWith('/fever/') || base.endsWith('fever.php')) {
      return base.concat('?api');
    }
    return base.concat('fever/?api');
  }

  /**
   * Lower-case hex MD5 of a UTF-8 string.
   *
   * Fever derives its `api_key` as `md5(email:password)`, so this is the one
   * place the port needs a hash primitive.
   */
  static async md5Hex(input: string): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(input);
    const blob: cryptoFramework.DataBlob = { data: bytes };
    await md.update(blob);
    const digest: cryptoFramework.DataBlob = await md.digest();

    let out: string = '';
    for (let i = 0; i < digest.data.length; i++) {
      const byte: number = digest.data[i];
      out = out.concat(byte < 16 ? '0' : '').concat(byte.toString(16));
    }
    return out;
  }

  /**
   * Base64-encode `user:pass` for HTTP Basic auth, matching what the original
   * stores in `authKey` when `apiKeyAuth` is false.
   */
  static basicAuthValue(user: string, password: string): string {
    const helper: util.Base64Helper = new util.Base64Helper();
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(user.concat(':').concat(password));
    return helper.encodeToStringSync(bytes);
  }
}
