/**
 * The sidebar's geometry rules, from the original's `getWindowBreakpoint()` and
 * `menu.tsx`.
 *
 * The original's sidebar is two different things at two sizes. At or above
 * 1440px it is a fixed 280px column laid out inside the page
 * (`@media (min-width: 1440px) { width: 280px !important }`). Below it the very
 * same panel is a drawer: an overlay whose container is `width: 100%` with
 * `pointer-events: none` while hidden, so it claims **no** layout width and the
 * content underneath is never squeezed.
 *
 * The rules are pure, so they are asserted in `verify/harness.ts` rather than
 * only observed at one window size.
 */
export const SIDEBAR_BREAKPOINT: number = 1440;

/** `menuInner { width: 280px }` — a fixed width, not a proportion. */
export const SIDEBAR_WIDTH: number = 280;

export class SidebarState {
  /**
   * Initial visibility: the stored choice, but only on a window wide enough to
   * host the sidebar as a column.
   */
  static initial(stored: boolean, widthVp: number): boolean {
    return stored && widthVp >= SIDEBAR_BREAKPOINT;
  }

  /** `getWindowBreakpoint()`, i.e. `window.innerWidth >= 1440`. */
  static isWide(widthVp: number): boolean {
    return widthVp >= SIDEBAR_BREAKPOINT;
  }

  /**
   * Layout width the open sidebar claims, which is what decides whether the
   * list is pushed aside (column) or covered (drawer).
   */
  static layoutWidth(open: boolean, widthVp: number): number {
    return open && SidebarState.isWide(widthVp) ? SIDEBAR_WIDTH : 0;
  }

  /**
   * The original passes `keepMenu: getWindowBreakpoint()` to `SELECT_PAGE`,
   * whose reducer does `menu: state.menu && action.keepMenu`. So picking a page
   * on a narrow window dismisses the drawer, while on a wide one the column
   * stays put. Only the live flag changes — the stored `menuOn` preference is
   * untouched.
   */
  static keepsMenuOnSelect(widthVp: number): boolean {
    return SidebarState.isWide(widthVp);
  }
}
