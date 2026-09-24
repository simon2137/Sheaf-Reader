# Material Design Icons (icon path data)

The 24×24 SVG icons shipped in this repository are **icon path data from
Material Design Icons** (Google), used under the **Apache License 2.0** — see
[LICENSE](LICENSE) in this directory.

- Upstream: <https://github.com/google/material-design-icons>
- License: Apache License 2.0 (<https://www.apache.org/licenses/LICENSE-2.0>)

## What is used

The files under `entry/src/main/resources/base/media/*.svg` are the upstream
icon outlines, exported as single-path SVGs (`width="24" height="24"
viewBox="0 0 24 24"`, one `<path>` inside a `<g fill="#000000">`). No path data
was modified; the fill colour is applied at runtime by the ArkUI components
(`.fillColor(...)`), so the icons follow the light/dark theme.

The application launcher icon is an **original design made for this port** (a stack
of paper sheets bound with a strap — “Sheaf / 束”), shipped as a layered icon:

- `AppScope/resources/base/media/layered_image.json` (+ `foreground.png`, `background.png`)
- `entry/src/main/resources/base/media/layered_image.json` (+ `foreground.png`, `background.png`)

`app_icon.png` in both media folders is the same design flattened into a
square-cornered 1024×1024 master (used by this repository's README and as the
source for the 216×216 AppGallery submission icon); `app_mark_light.png` /
`app_mark_dark.png` are the transparent-background in-app marks (recoloured per
theme) shown in the sidebar header, the About section and the loading screen;
`start_icon.png` is the 144×144 start-window variant. None of these are part of
Material Design Icons.

Material Design Icons are a trademark of Google LLC; this project is not
affiliated with or endorsed by Google.
