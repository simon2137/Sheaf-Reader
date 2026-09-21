import { Feed, Article, FeedGroup } from '../model/Models';
import { DatabaseManager } from '../data/DatabaseManager';

/**
 * The on-disk shape of a backup. Mirrors the original's `.frdata` file, which
 * bundles the settings together with the sources and items tables.
 */
export class BackupFile {
  /** Format marker written into new backups. */
  static readonly FORMAT: string = 'sheaf-reader-hm';
  /** Marker written before the project was renamed; still accepted on import. */
  static readonly LEGACY_FORMAT: string = 'fluent-reader-hm';
  static readonly CURRENT_VERSION: number = 1;
  /** Format marker, so a future change can be detected. */
  format: string = BackupFile.FORMAT;
  version: number = 1;
  exportedAt: number = 0;
  /** Settings as a flat key/value map. */
  settings: Map<string, string> = new Map<string, string>();
  groups: FeedGroup[] = [];
  feeds: Feed[] = [];
  articles: Article[] = [];
}

/** What a backup or restore did, for reporting back to the user. */
export class BackupOutcome {
  ok: boolean = false;
  message: string = '';
  feeds: number = 0;
  articles: number = 0;
  groups: number = 0;
}

/**
 * Full-application backup and restore.
 *
 * Restore is destructive by design — the original warns that "all current data
 * will be wiped" — so the caller must confirm before invoking it.
 */
export class BackupService {
  private static db: DatabaseManager = DatabaseManager.getInstance();

  /**
   * Capture the whole library. Article `feedId` values are meaningful only
   * alongside `feeds`; restore re-points them at the ids it assigns.
   */
  static async exportAll(): Promise<string> {
    const backup: BackupFile = new BackupFile();
    backup.exportedAt = Date.now();
    backup.settings = await BackupService.db.getAllSettings();
    backup.groups = await BackupService.db.getAllGroups();
    backup.feeds = await BackupService.db.getAllFeeds();
    backup.articles = await BackupService.db.getAllArticles();
    return JSON.stringify(backup);
  }

  /**
   * Summarise a backup without applying it, so the user can be told what they
   * are about to import.
   */
  static describe(content: string): BackupOutcome | null {
    const parsed: BackupFile | null = BackupService.parse(content);
    if (parsed === null) {
      return null;
    }
    const outcome: BackupOutcome = new BackupOutcome();
    outcome.ok = true;
    outcome.feeds = parsed.feeds.length;
    outcome.articles = parsed.articles.length;
    outcome.groups = parsed.groups.length;
    return outcome;
  }

  private static parse(content: string): BackupFile | null {
    if (!content) {
      return null;
    }
    try {
      const parsed: BackupFile = JSON.parse(content) as BackupFile;
      if (parsed === null || parsed === undefined
        || parsed.feeds === undefined || parsed.feeds === null) {
        return null;
      }
      // Guard against a truncated or unrelated JSON file. The pre-rename marker
      // is still accepted, so a backup exported before the project was renamed
      // (Fluent Reader for HarmonyOS -> Sheaf Reader) keeps restoring.
      if (parsed.format !== BackupFile.FORMAT
        && parsed.format !== BackupFile.LEGACY_FORMAT) {
        return null;
      }
      return parsed;
    } catch (err) {
      console.error('BackupService: malformed backup file');
      return null;
    }
  }

  /**
   * Replace the current library with the contents of `content`.
   *
   * Ids are remapped rather than reused: the feeds are inserted first, each
   * old id is mapped to the id it received, and articles are re-pointed
   * through that map so a restore into a non-empty database stays consistent.
   */
  static async importAll(content: string): Promise<BackupOutcome> {
    const outcome: BackupOutcome = new BackupOutcome();

    const parsed: BackupFile | null = BackupService.parse(content);
    if (parsed === null) {
      outcome.message = 'backup_invalid';
      return outcome;
    }

    // 1. Wipe user content. Settings are overwritten after the content lands,
    //    so a failure mid-way leaves the previous settings intact.
    await BackupService.db.clearContent();

    // 2. Groups, remembering old -> new ids.
    const groupIds: Map<number, number> = new Map<number, number>();
    for (const group of parsed.groups) {
      const newId: number = await BackupService.db.insertGroupNamed(group.name);
      if (newId > 0) {
        groupIds.set(group.id, newId);
        outcome.groups++;
      }
    }

    // 3. Feeds, likewise.
    const feedIds: Map<number, number> = new Map<number, number>();
    for (const feed of parsed.feeds) {
      const restored: Feed = new Feed(feed.url, feed.title);
      restored.link = feed.link;
      restored.description = feed.description;
      restored.iconUrl = feed.iconUrl;
      restored.lastFetched = feed.lastFetched;
      restored.serviceRef = feed.serviceRef;
      restored.fetchFrequency = feed.fetchFrequency;
      restored.openTarget = feed.openTarget;
      restored.textDir = feed.textDir;
      restored.hidden = feed.hidden;
      restored.rulesJson = feed.rulesJson;
      const mappedGroup: number | undefined = groupIds.get(feed.groupId);
      restored.groupId = mappedGroup !== undefined ? mappedGroup : -1;

      const newId: number = await BackupService.db.insertFeedRaw(restored);
      if (newId > 0) {
        feedIds.set(feed.id, newId);
        outcome.feeds++;
      }
    }

    // 4. Articles, re-pointed at their feed's new id.
    for (const article of parsed.articles) {
      const mappedFeed: number | undefined = feedIds.get(article.feedId);
      if (mappedFeed === undefined) {
        // Its feed was not in the backup; skip rather than orphan the row.
        continue;
      }
      const restored: Article = new Article();
      restored.feedId = mappedFeed;
      restored.serviceRef = article.serviceRef;
      restored.title = article.title;
      restored.link = article.link;
      restored.author = article.author;
      restored.content = article.content;
      restored.snippet = article.snippet;
      restored.published = article.published;
      restored.fetched = article.fetched;
      restored.read = article.read;
      restored.starred = article.starred;
      restored.hidden = article.hidden;
      restored.notify = article.notify;
      restored.imageUrl = article.imageUrl;
      restored.guid = article.guid;

      const newId: number = await BackupService.db.insertArticle(restored);
      if (newId > 0) {
        outcome.articles++;
      }
    }

    // 5. Settings last, so the restored preferences apply to a consistent
    //    library.
    await BackupService.db.setSettings(parsed.settings);

    outcome.ok = true;
    outcome.message = 'backup_restored';
    return outcome;
  }
}
