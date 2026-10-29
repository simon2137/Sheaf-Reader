import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

/**
 * Reads a bundled `rawfile` as UTF-8 text.
 *
 * The legal documents (privacy policy, licence and notice) ship inside the HAP
 * rather than only on the web: BSD-3-Clause clause 2 requires the copyright
 * notice and licence text in binary distributions, and a store reviewer should
 * be able to read the privacy policy with the device offline.
 */
export class BundledText {
  static async read(context: common.Context, path: string): Promise<string> {
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent(path);
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (err) {
      console.error('BundledText: could not load ' + path);
      return '';
    }
  }
}
