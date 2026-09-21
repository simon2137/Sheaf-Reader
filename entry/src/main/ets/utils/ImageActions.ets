import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { HttpClient } from '../data/HttpClient';
import { OpmlFileService } from './OpmlFileService';

/**
 * The article image actions from the original's context menu:
 * `context.saveImageAs`, `context.copyImage` and `context.copyImageURL`.
 *
 * The original renders the article HTML in a webview, so its menu hangs off an
 * inline `<img>`. This port renders text, so the same three actions hang off
 * the article's cover image instead — the image the card shows.
 *
 * Each action returns an I18n key on failure and an empty string on success, so
 * the caller owns the presentation.
 */
export class ImageActions {
  /** File extension used when the URL does not end in something usable. */
  private static readonly FALLBACK_NAME: string = 'image.png';

  /**
   * Derive a file name from an image URL.
   *
   * Only the last path segment is used: query strings, fragments and the
   * directory are dropped, and a name with no recognisable image extension is
   * replaced outright so the picker is not handed something like `photo`.
   */
  static suggestedFileName(url: string): string {
    if (!url) {
      return ImageActions.FALLBACK_NAME;
    }

    let path: string = url;
    const query: number = path.indexOf('?');
    if (query >= 0) {
      path = path.substring(0, query);
    }
    const fragment: number = path.indexOf('#');
    if (fragment >= 0) {
      path = path.substring(0, fragment);
    }
    const slash: number = path.lastIndexOf('/');
    if (slash >= 0) {
      path = path.substring(slash + 1);
    }
    // Percent-encoding in a file name confuses the picker's own escaping.
    path = decodeURIComponentSafe(path);

    const dot: number = path.lastIndexOf('.');
    if (dot <= 0 || dot === path.length - 1) {
      return ImageActions.FALLBACK_NAME;
    }
    const extension: string = path.substring(dot + 1).toLowerCase();
    if (!ImageActions.isImageExtension(extension)) {
      return ImageActions.FALLBACK_NAME;
    }
    return path;
  }

  private static isImageExtension(extension: string): boolean {
    return extension === 'png' || extension === 'jpg' || extension === 'jpeg'
      || extension === 'gif' || extension === 'webp' || extension === 'bmp'
      || extension === 'svg' || extension === 'avif';
  }

  /** "Save image as …": download, then let the user choose a destination. */
  static async saveImage(context: common.UIAbilityContext, url: string): Promise<string> {
    if (url.length === 0) {
      return 'app.noImage';
    }
    const bytes: ArrayBuffer | null = await HttpClient.fetchBytes(url);
    if (bytes === null) {
      return 'app.imageFetchFailed';
    }
    const uri: string | null = await OpmlFileService.pickAndWriteBytes(
      context, bytes, ImageActions.suggestedFileName(url));
    return uri === null ? 'app.saveCancelled' : '';
  }

  /** "Copy image": download and decode, then put the pixels on the clipboard. */
  static async copyImage(url: string): Promise<string> {
    if (url.length === 0) {
      return 'app.noImage';
    }
    const bytes: ArrayBuffer | null = await HttpClient.fetchBytes(url);
    if (bytes === null) {
      return 'app.imageFetchFailed';
    }
    try {
      const source: image.ImageSource = image.createImageSource(bytes);
      const pixelMap: image.PixelMap = await source.createPixelMap();
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
      await pasteboard.getSystemPasteboard().setData(data);
      return '';
    } catch (err) {
      // An undecodable body (an HTML error page served with an image content
      // type, say) lands here rather than producing a broken clip.
      console.error('ImageActions.copyImage failed to decode');
      return 'app.imageDecodeFailed';
    }
  }
}

/**
 * `decodeURIComponent` throws on a malformed escape such as `%zz`; a file name
 * is not worth failing over, so the raw segment is kept instead.
 */
function decodeURIComponentSafe(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (err) {
    return value;
  }
}
