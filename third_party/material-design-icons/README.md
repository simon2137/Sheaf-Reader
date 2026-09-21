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

The application launcher icons (`AppScope/resources/base/media/app_icon.png`,
`entry/src/main/resources/base/media/app_icon.png`,
`entry/src/main/resources/base/media/start_icon.png`) are simple placeholders
drawn for this port — they are not the original application's icon and are not
part of Material Design Icons.

Material Design Icons are a trademark of Google LLC; this project is not
affiliated with or endorsed by Google.
