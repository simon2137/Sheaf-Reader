/**
 * Touch-target sizing.
 *
 * The official UX guidance for HarmonyOS apps requires a tap area of at least
 * 40vp x 40vp ("点击热区不得小于40vp×40vp", 应用UX体验建议). Measured on the
 * `Huawei_Tablet` image, 35 of the port's 44 clickable targets were under it:
 * the icon buttons draw at 30vp (the mark-all arrow at 24vp), the sidebar's
 * footer buttons at 34vp, its rows at 32–38vp and the filter chips at ~21vp.
 *
 * Buttons therefore get a *response region* rather than a bigger box: the hit
 * area grows to the minimum while every layout that was measured on both images
 * stays exactly where it was. Things whose height is what makes them hard to hit
 * (the chips, the sidebar rows) grow for real.
 *
 * `responseRegion` is `@since 9`, so it is safe at this project's API 12.
 */
export class TouchTarget {
  /** Minimum tap area, in vp, from the UX guidance. */
  static readonly MIN: number = 40;

  /**
   * A `MIN` x `MIN` response rectangle centred on a `size` x `size` control.
   *
   * The region is expressed relative to the component, so a negative offset
   * grows it outwards. Adjacent controls overlap by a few vp; that is the
   * intended trade — the tap area reaches the minimum and there is no dead strip
   * between two icons.
   */
  static region(size: number): Rectangle {
    const pad: number = Math.max(0, (TouchTarget.MIN - size) / 2);
    const rect: Rectangle = { x: -pad, y: -pad, width: TouchTarget.MIN, height: TouchTarget.MIN };
    return rect;
  }

  /**
   * The same for a control that is not square — the mark-all arrow draws 24x30,
   * so it needs a different pad on each axis.
   */
  static regionFor(width: number, height: number): Rectangle {
    const padX: number = Math.max(0, (TouchTarget.MIN - width) / 2);
    const padY: number = Math.max(0, (TouchTarget.MIN - height) / 2);
    const rect: Rectangle = {
      x: -padX,
      y: -padY,
      width: Math.max(width, TouchTarget.MIN),
      height: Math.max(height, TouchTarget.MIN)
    };
    return rect;
  }
}
