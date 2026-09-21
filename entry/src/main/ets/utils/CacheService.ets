import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * The application cache directory, the counterpart of the original's
 * `window.utils.getCacheSize()` / `clearCache()` (which measure and clear the
 * Electron session cache).
 *
 * Only the cache directory is touched: article data lives in the database and
 * has its own, separate "delete articles" action.
 */
export class CacheService {
  /** Total size of everything under the cache directory, in bytes. */
  static async size(context: common.Context): Promise<number> {
    const root: string = context.cacheDir;
    if (!root || root.length === 0) {
      return 0;
    }
    try {
      if (!await fs.access(root)) {
        return 0;
      }
      return await CacheService.measure(root);
    } catch (err) {
      return 0;
    }
  }

  private static async measure(dir: string): Promise<number> {
    let total: number = 0;
    const names: string[] = await fs.listFile(dir);
    for (const name of names) {
      const full: string = dir.concat('/').concat(name);
      const info: fs.Stat = await fs.stat(full);
      if (info.isDirectory()) {
        total += await CacheService.measure(full);
      } else {
        total += info.size;
      }
    }
    return total;
  }

  /**
   * Remove every entry under the cache directory, leaving the directory itself
   * in place. Failures are ignored per entry so one locked file cannot stop the
   * rest from being reclaimed.
   */
  static async clear(context: common.Context): Promise<void> {
    const root: string = context.cacheDir;
    if (!root || root.length === 0) {
      return;
    }
    try {
      if (!await fs.access(root)) {
        return;
      }
      const names: string[] = await fs.listFile(root);
      for (const name of names) {
        const full: string = root.concat('/').concat(name);
        try {
          const info: fs.Stat = await fs.stat(full);
          if (info.isDirectory()) {
            await fs.rmdir(full);
          } else {
            await fs.unlink(full);
          }
        } catch (err) {
          // Entry already gone, or held open by the system: skip it.
        }
      }
    } catch (err) {
      // Cache directory unavailable: nothing to clear.
    }
  }
}
