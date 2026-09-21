/**
 * Small display helpers shared by the article cards.
 */
export class Display {
  /**
   * Compact relative time, matching the original's `Time` component
   * (`now` / `5m` / `3h` / `2d`).
   */
  static relativeTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }
    const diff: number = Date.now() - timestamp;
    const minutes: number = Math.floor(diff / 60000);
    if (minutes < 1) {
      return 'now';
    }
    if (minutes < 60) {
      return minutes.toString().concat('m');
    }
    const hours: number = Math.floor(minutes / 60);
    if (hours < 24) {
      return hours.toString().concat('h');
    }
    const days: number = Math.floor(hours / 24);
    if (days < 30) {
      return days.toString().concat('d');
    }
    const date: Date = new Date(timestamp);
    return (date.getMonth() + 1).toString().concat('/')
      .concat(date.getDate().toString());
  }

  /**
   * Absolute date for the magazine/grid layouts, where a precise stamp reads
   * better than a relative one.
   */
  static shortDate(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }
    const date: Date = new Date(timestamp);
    return (date.getMonth() + 1).toString().concat('/')
      .concat(date.getDate().toString()).concat('/')
      .concat(date.getFullYear().toString());
  }

  /** Number of grid columns that fit in `width`, never below one. */
  static columnsFor(width: number): number {
    const fit: number = Math.floor((width - 24) / 280);
    return fit < 1 ? 1 : fit;
  }
}
