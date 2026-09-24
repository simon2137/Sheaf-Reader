# Sheaf Reader 束阅 · 应用图标（6 版设计稿 + 已落地资源）

> 状态：**已选定 02 麦束 / 纸束，并已落地到工程**——分层图标配置完成，见文末「已落地的资源」。
> 总览图：[`overview.png`](overview.png) · 安全区说明：[`_guides.png`](_guides.png)

## 六版方案

| # | 方案 | 视觉 | 立意 | 风险 |
|---|---|---|---|---|
| 01 | [RSS 弧线](01-rss-arcs/masked.png) | 白色信号弧 + 圆点，蓝底渐变 | 识别度最高的通用解，一眼知道是订阅/阅读器 | “太标准”，缺品牌个性 |
| **02 ✅ 选定** | [麦束 / 纸束](02-sheaf-bundle/masked.png) | 三张纸扇形叠放、蓝色束带扎起，深色底 | 呼应品牌名 **Sheaf / 束**——“把信息扎成一束” | 深色底在浅色桌面上略重 |
| 03 | [字标 S](03-monogram-s/masked.png) | 加粗 S + 深蓝投影，品牌蓝底 | 字标路线，小尺寸下轮廓最清晰 | 单字母与“订阅”语义无关 |
| 04 | [文档 + 订阅弧](04-doc-feed/masked.png) | 折角文档 + 正文线 + RSS 弧，深蓝底 | 把“读文章”和“订源”两个核心动作放进一张图 | 元素多，极小尺寸会糊 |
| 05 | [流线](05-fluent-flow/masked.png) | 一点发散的三条流线，青蓝渐变 | 抽象路线，同源 Fluent 设计语言 | 语义最弱，需配合应用名 |
| 06 | [卡片流 + 未读点](06-card-list/masked.png) | 三层半透明卡片 + 琥珀色未读徽标 | 直译应用主界面（列表 + 未读） | 卡片堆叠在小尺寸下易粘连 |

配色取自工程内已有的 `entry/src/main/resources/base/element/color.json`：
品牌蓝 `#0078D4` / `#106EBE`、深色底 `#1B1A19` 系、星标琥珀 `#FFB900`。

## 每一版里有什么

```
NN-<slug>/
  background.png   1024×1024 不透明背景层（纯色/渐变/柔光，无主体元素）
  foreground.png   1024×1024 透明背景前景层（只含图标主体，未做圆角与内边距）
  preview.png      1024×1024 前景叠背景的方图效果
  masked.png       1024×1024 套用系统超椭圆遮罩后的示意（仅预览用）
```

## 设计约束（按官方/上架要求执行）

- **前景图**：1024×1024 px、透明底 PNG，只放主体，**不要自己做圆角、内边距、阴影**——系统会自动裁切。
- **背景图**：1024×1024 px、不透明 PNG，只有颜色/渐变，不含主体元素。
- **安全区**：本批设计稿所有主体都画在画布中心 **620×620** 范围内（见 `_guides.png`）——
  这是按“系统圆角裁切 + 桌面留白”取的保守值，越界内容在部分形态下会被切掉。
- **生成工具**：上架要求用 **DevEco Studio ≥ 5.0.5.315** 的 `右键模块 → New > Image Asset`（分层图标）再处理一次，
  它会产出 `layered_image.json` 与各 dpi 资源；低版本产物会被审核拒绝。
- **应用市场**：AGC 另需一张 **216×216 px 直角图标**（前景+背景合成，非分层图）。
- 本目录里的 `masked.png` 只用于**看效果**，不能当资源文件提交——超椭圆遮罩由系统加，不是画上去的。

## 重新生成 / 改稿

```powershell
python docs/icon-drafts/generate_icons.py     # 需要 Pillow + numpy（本机已装，纯本地、不联网）
```

脚本 `generate_icons.py` 是**设计稿生成器**（numpy + Pillow，4× 超采样、预乘 alpha 缩放）：
改颜色、几何、角度都在文件顶部的常量与各 `vN_*()` 函数里。它**不是**产线工具——
最终资源仍需经 DevEco Studio 的 Image Asset 走一遍。

## 已落地的资源（02 麦束 / 纸束）

`python docs/icon-drafts/apply_icon.py` 已把选定方案写进工程（脚本会断言：分层图层必须是
1024×1024、前景主体不出中心 620×620 安全区、背景完全不透明、前景含透明区）：

| 文件 | 尺寸 | 用途 |
|---|---|---|
| `AppScope/resources/base/media/foreground.png` | 1024×1024 透明底 | 应用图标前景层 |
| `AppScope/resources/base/media/background.png` | 1024×1024 不透明 | 应用图标背景层 |
| `AppScope/resources/base/media/layered_image.json` | — | 分层图标声明（`$media:foreground` / `$media:background`） |
| `entry/src/main/resources/base/media/foreground.png` | 1024×1024 透明底 | 模块（Ability）图标前景层 |
| `entry/src/main/resources/base/media/background.png` | 1024×1024 不透明 | 模块图标背景层 |
| `entry/src/main/resources/base/media/layered_image.json` | — | 同上 |
| `AppScope|entry/.../app_icon.png` | 1024×1024 直角 | 同一设计的平面主图（README 顶部展示、AGC 上传源） |
| `entry/src/main/resources/base/media/app_mark_light.png` | 256×256 透明底 | **应用内标识（浅色界面）**：去掉方块底，纸改成深蓝、文字线浅蓝、束带品牌蓝 |
| `entry/src/main/resources/base/media/app_mark_dark.png` | 256×256 透明底 | **应用内标识（深色界面）**：纸 near-white、文字线深蓝、束带亮蓝 |
| `entry/src/main/resources/base/media/start_icon.png` | 144×144 | 启动页图标（`startWindowIcon`） |
| `02-sheaf-bundle/agc-216.png` | 216×216 直角 | AGC 上架用图标 |

配置改动（与官方《配置分层图标》一致）：

- `AppScope/app.json5` → `"icon": "$media:layered_image"`
- `entry/src/main/module.json5` → `abilities[0].icon = "$media:layered_image"`、
  `startWindowIcon` 仍指向 `$media:start_icon`（内容已是新图标）

应用内品牌位（原先都用 Material 的 `ic_rss.svg` 顶替，现改为按主题取透明底标识）：

- `entry/src/main/ets/components/SidebarView.ets` — 侧栏头部（22px，`this.store.isDarkMode`）
- `entry/src/main/ets/components/SettingsDialog.ets` — 设置 → 关于（24px，`this.isDarkMode`）
- `entry/src/main/ets/pages/Index.ets` — `LoadingScreen()` 加载页（56px，`this.store.isDarkMode`）

为什么不是直接抠掉 App 图标的方法底：图标里三张纸是白色、文字线是蓝色，放在浅色侧栏（`#FAFAFA`）
上会直接消失；所以做成**透明底 + 元素按主题换色**（`app_mark_light` / `app_mark_dark`）。
标识本体仍是同一套图形（三张扇形叠放的纸 + 束带），由 `make_inapp_mark.py` 生成。

语义用途的 `ic_rss` **刻意保留**（订阅源/文章的占位图、`ArticleCards` 的 `alt` 回退、空态插画），
它们是“这是一条订阅/文章”的图标，不是品牌标识。

`foreground.png` 实测 alpha 包围盒 = `(263, 259, 760, 734)`，完整落在 620×620 安全区内。

### 验证

**构建 / 打包（本机）**

- `hvigorw --mode module -p product=default assembleHap --no-daemon` → **BUILD SUCCESSFUL**（增量构建 13–14 s）；
  产物 `entry/build/default/outputs/default/entry-default-unsigned.hap`（2,150,386 字节，debug 未签名，
  含应用内标识改动后的版本）。
- 解包核对 HAP：内含 `resources/base/media/foreground.png`、`background.png`、`layered_image.json`、`start_icon.png`；
  打包后的 `module.json` 里 `app.icon` 与 `abilities[0].icon` 都是 `$media:layered_image` 并**已解析出资源 ID**
  （`iconId: 16777330`，`startWindowIconId: 16777321`）。

**模拟器实机（2in1）**

- 设备：`hdc` 目标 `127.0.0.1:5555`，`const.product.devicetype` = `2in1`、`const.product.model` = `emulator`、
  API 17、`emulator 5.0.0.319(SP31DEVC00E319R1P5log)`，画面 2160×1440。
- `hdc install -r` → `install bundle successfully`（模拟器接受未签名 HAP）。
- **桌面图标渲染正确**：应用列表里出现 `束阅`，图标是新的纸束设计，系统超椭圆遮罩正常套用、主体无裁切 ——
  见 [`emulator/app-list-sheaf-reader.jpeg`](emulator/app-list-sheaf-reader.jpeg)、放大图
  [`emulator/launcher-icon-zoom.png`](emulator/launcher-icon-zoom.png)。
- **应用内品牌位已换过来**（报告过的两处 + 同源的加载页），浅色/深色都实测：
  侧栏头部浅色 [`emulator/inapp-sidebar-light.png`](emulator/inapp-sidebar-light.png)、
  深色 [`emulator/inapp-sidebar-dark.png`](emulator/inapp-sidebar-dark.png)；
  设置 → 关于浅色 [`emulator/inapp-about-light.png`](emulator/inapp-about-light.png)、
  深色 [`emulator/inapp-about-dark.png`](emulator/inapp-about-dark.png)；
  整体运行截图 [`emulator/app-running-light.jpeg`](emulator/app-running-light.jpeg) /
  [`emulator/app-running-dark.jpeg`](emulator/app-running-dark.jpeg)。
  深色是在 设置 → 应用主题 里切到「深色模式」实测的，验完已还原成「跟随系统」。
- **应用照常运行**：窗口标题栏与任务栏都显示新图标，界面正常（侧栏 + 全部文章 + 空态）。
- **加载页没截到**：本机没有任何订阅源，启动后瞬间进入空态（`LoadingScreen()` 只是一闪），
  所以加载页那处只有代码与构建证据，没有截图；侧栏与关于页都是眼见为实。
- **没抓到启动页**：2in1 上窗口是瞬间恢复的（force-stop 后重启，前后两张截图 SHA-256 完全相同，说明没经过可截取的启动页帧）。
  所以 `start_icon.png` 只有“已打包 + `startWindowIconId` 已解析”这一层证据，没有启动页的视觉取证。
- **尺寸对得上系统默认值**：前景内容占比实测 `49% × 46%`（alpha bbox 498×476 / 1024），
  与 DevEco Studio 自带模板前景图的 `45% × 45%`（1024 模板 bbox 284–739、288 模板 bbox 80–208）同级；
  桌面上与相邻系统图标比，量级一致（系统图标是满幅画法，本图标按分层规范留了边距）。

**尚未取证**

- AGC 提审前的「图标再处理」（DevEco Studio ≥ 5.0.5.315 的 Image Asset，见下一节）；真机（非模拟器）未测。

## 仍必须在 DevEco Studio 里做的一步

提审前请用 **DevEco Studio ≥ 5.0.5.315** 打开工程，对 `AppScope` 与 `entry` 各执行一次
`右键模块 → New > Image Asset`（前景选 `foreground.png`、背景选 `background.png`），
让 IDE 做一次「图标再处理」并生成各 dpi 资源——上架审核会检查这一步，手写的单份
`base/media` 资源可以正常构建运行，但不等于审核认可的产物。

