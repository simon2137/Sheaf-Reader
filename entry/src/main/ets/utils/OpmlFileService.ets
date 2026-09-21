import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

/**
 * Reads and writes OPML documents through the system file picker.
 */
export class OpmlFileService {
  /**
   * Let the user choose an .opml/.xml file and return its text content.
   * Returns null when the user cancels or the file cannot be read.
   */
  static async pickAndRead(context: common.UIAbilityContext): Promise<string | null> {
    return OpmlFileService.pickAndReadAny(context, ['.opml', '.xml', '.txt']);
  }

  /**
   * Ask for a destination and write the OPML payload there.
   * Returns the saved URI, or null when cancelled.
   */
  static async pickAndWrite(context: common.UIAbilityContext, content: string): Promise<string | null> {
    return OpmlFileService.pickAndWriteAny(context, content,
      'sheaf-reader-subscriptions.opml');
  }

  /**
   * Generic reader: the same picker, for any file type the app handles.
   */
  static async pickAndReadAny(context: common.UIAbilityContext,
    suffixes: string[]): Promise<string | null> {
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = suffixes;

      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return null;
      }
      return OpmlFileService.readText(uris[0]);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FileService.pickAndReadAny failed: ' + error.message);
      return null;
    }
  }

  /**
   * Generic writer, for any file the app produces.
   */
  static async pickAndWriteAny(context: common.UIAbilityContext, content: string,
    fileName: string): Promise<string | null> {
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];

      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return null;
      }
      OpmlFileService.writeText(uris[0], content);
      return uris[0];
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FileService.pickAndWriteAny failed: ' + error.message);
      return null;
    }
  }

  /**
   * Same picker, for binary payloads (the "save image as" action).
   */
  static async pickAndWriteBytes(context: common.UIAbilityContext, content: ArrayBuffer,
    fileName: string): Promise<string | null> {
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];

      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return null;
      }
      OpmlFileService.writeBytes(uris[0], content);
      return uris[0];
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FileService.pickAndWriteBytes failed: ' + error.message);
      return null;
    }
  }

  private static writeBytes(uri: string, content: ArrayBuffer): void {
    const file: fileIo.File = fileIo.openSync(uri,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private static readText(uri: string): string {
    const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = fileIo.statSync(file.fd);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const bytesRead: number = fileIo.readSync(file.fd, buffer);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer.slice(0, bytesRead)));
    } finally {
      fileIo.closeSync(file);
    }
  }

  private static writeText(uri: string, content: string): void {
    const file: fileIo.File = fileIo.openSync(uri,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, content);
    } finally {
      fileIo.closeSync(file);
    }
  }
}
