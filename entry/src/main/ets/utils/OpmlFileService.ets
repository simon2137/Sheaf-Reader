import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

/**
 * What came back from a read.
 *
 * `cancelled` and `failed` have to stay apart: cancelling the picker is a normal
 * outcome and must stay silent, while a failed read/write has to be reported —
 * the earlier code returned a bare `null` for both, so a broken save looked
 * exactly like the user pressing 关闭 (measured on the 2in1 emulator: the picker
 * reported `savedFileUris:1` while `AppFileService … realpath failed with 2`,
 * and the app showed nothing at all).
 */
export class FileReadResult {
  text: string = '';
  /** The user dismissed the picker. */
  cancelled: boolean = false;
  /** The picker or the file system refused; `detail` carries the message. */
  failed: boolean = false;
  detail: string = '';

  static cancel(): FileReadResult {
    const result: FileReadResult = new FileReadResult();
    result.cancelled = true;
    return result;
  }

  static fail(detail: string): FileReadResult {
    const result: FileReadResult = new FileReadResult();
    result.failed = true;
    result.detail = detail;
    return result;
  }

  static of(text: string): FileReadResult {
    const result: FileReadResult = new FileReadResult();
    result.text = text;
    return result;
  }
}

/** What came back from a save. */
export class FileWriteResult {
  uri: string = '';
  cancelled: boolean = false;
  failed: boolean = false;
  detail: string = '';

  static cancel(): FileWriteResult {
    const result: FileWriteResult = new FileWriteResult();
    result.cancelled = true;
    return result;
  }

  static fail(detail: string): FileWriteResult {
    const result: FileWriteResult = new FileWriteResult();
    result.failed = true;
    result.detail = detail;
    return result;
  }

  static of(uri: string): FileWriteResult {
    const result: FileWriteResult = new FileWriteResult();
    result.uri = uri;
    return result;
  }
}

/**
 * Reads and writes OPML documents through the system file picker.
 */
export class OpmlFileService {
  /**
   * Let the user choose an .opml/.xml file and return its text content.
   */
  static async pickAndRead(context: common.UIAbilityContext): Promise<FileReadResult> {
    return OpmlFileService.pickAndReadAny(context, ['.opml', '.xml', '.txt']);
  }

  /**
   * Ask for a destination and write the OPML payload there.
   */
  static async pickAndWrite(context: common.UIAbilityContext,
    content: string): Promise<FileWriteResult> {
    return OpmlFileService.pickAndWriteAny(context, content,
      'sheaf-reader-subscriptions.opml');
  }

  /**
   * Generic reader: the same picker, for any file type the app handles.
   */
  static async pickAndReadAny(context: common.UIAbilityContext,
    suffixes: string[]): Promise<FileReadResult> {
    let uri: string = '';
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = suffixes;

      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return FileReadResult.cancel();
      }
      uri = uris[0];
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FileService.pickAndReadAny picker failed: ' + error.message);
      return FileReadResult.fail('picker: ' + error.message);
    }
    try {
      return FileReadResult.of(OpmlFileService.readText(uri));
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FileService.pickAndReadAny read failed: ' + error.message);
      return FileReadResult.fail('read: ' + error.message);
    }
  }

  /**
   * Generic writer, for any file the app produces.
   */
  static async pickAndWriteAny(context: common.UIAbilityContext, content: string,
    fileName: string): Promise<FileWriteResult> {
    let uri: string = '';
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];

      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return FileWriteResult.cancel();
      }
      uri = uris[0];
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FileService.pickAndWriteAny picker failed: ' + error.message);
      return FileWriteResult.fail('picker: ' + error.message);
    }
    try {
      OpmlFileService.writeText(uri, content);
      return FileWriteResult.of(uri);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FileService.pickAndWriteAny write failed: ' + error.message);
      return FileWriteResult.fail('write: ' + error.message);
    }
  }

  /**
   * Same picker, for binary payloads (the "save image as" action).
   */
  static async pickAndWriteBytes(context: common.UIAbilityContext, content: ArrayBuffer,
    fileName: string): Promise<FileWriteResult> {
    let uri: string = '';
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];

      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return FileWriteResult.cancel();
      }
      uri = uris[0];
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FileService.pickAndWriteBytes picker failed: ' + error.message);
      return FileWriteResult.fail('picker: ' + error.message);
    }
    try {
      OpmlFileService.writeBytes(uri, content);
      return FileWriteResult.of(uri);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FileService.pickAndWriteBytes write failed: ' + error.message);
      return FileWriteResult.fail('write: ' + error.message);
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
