# 商店截图 / Store screenshots

应用市场（AGC）要求同一设备类型下每种语言提供同一组界面截图。本目录按
`<设备>-<语言>-<序号>-<界面>.jpeg` 命名，**12 张** 为一整套：

| # | 文件名 | 界面 | 说明 |
|---|---|---|---|
| 01 | `tablet-zh-01-main.jpeg` | 主界面 | 列表 + 阅读器，含正文插图 |
| 02 | `tablet-zh-02-cards.jpeg` | 卡片视图 | 卡片网格，未开阅读器时全宽多列 |
| 03 | `tablet-zh-03-settings.jpeg` | 设置菜单 | 「选项」面板 |
| 04 | `tablet-en-01-main.jpeg` | 主界面 | 同上，英文 |
| 05 | `tablet-en-02-cards.jpeg` | 卡片视图 | 同上，英文 |
| 06 | `tablet-en-03-settings.jpeg` | 设置菜单 | 同上，英文 |
| 07 | `2in1-zh-01-main.jpeg` | 主界面 | 三栏布局（侧栏常驻） |
| 08 | `2in1-zh-02-cards.jpeg` | 卡片视图 | 三栏 + 卡片 |
| 09 | `2in1-zh-03-settings.jpeg` | 设置菜单 | 三栏 + 选项面板 |
| 10 | `2in1-en-01-main.jpeg` | 主界面 | 同上，英文 |
| 11 | `2in1-en-02-cards.jpeg` | 卡片视图 | 同上，英文 |
| 12 | `2in1-en-03-settings.jpeg` | 设置菜单 | 同上，英文 |

## 规格（2026-11-01 重拍）

| 设备 | 成品尺寸 | 采集方式 |
|---|---|---|
| 平板 `Huawei_Tablet` | **1920×1280** | 实例按 2560×1600 / density 360 采集，再按 0.75 等比缩到 1920×1280 |
| 2-in-1 `Huawei_2in1` | **1920×1080** | 实例直接改成 1920×1080 / density 178，原生采集，无缩放 |

平板为什么要缩放：实例的 `hw.lcd.density` 改了不生效（系统仍按 userdata 里存下的 2.25 走，
`hw.lcd.phy.*` 又让它算出 205 DPI），应用因此在 1920 宽下按宽屏版式（侧栏常驻）渲染、
卡片列数偏少。先在 2560×1600 拿到完整构图，再缩到 1920×1280，是目前最稳的一条路。

## 采集方法（无头模拟器）

```powershell
devecocli emulator start Huawei_2in1 --no-window      # 无窗口，照样能截图
# 分辨率：改 F:\Huawei\<实例>\config.ini 里的 hw.lcd.single.width / .height / density，
#         先 stop 再 start 生效（配置在冷启动时读）
hdc shell "uitest uiInput doubleClick 900 160"        # 双击标题栏最大化（2-in-1）
hdc shell "uitest uiInput keyEvent 2090"              # F1 开关侧栏
hdc shell "snapshot_display -f /data/local/tmp/s.jpeg"
hdc file recv /data/local/tmp/s.jpeg docs\store\<名字>.jpeg
```

语言：设置 → 界面语言 → English / 简体中文，切完把三张重拍一遍。

## 当前进度

**12 / 12 完成（2026-11-01）**，两套尺寸、两套语言：

| 设备 | 中文 | 英文 |
|---|---|---|
| 平板 1920×1280 | `tablet-zh-01-main` / `-02-cards` / `-03-settings` | `tablet-en-01-main` / `-02-cards` / `-03-settings` |
| 2-in-1 1920×1080 | `2in1-zh-01-main` / `-02-cards` / `-03-settings` | `2in1-en-01-main` / `-02-cards` / `-03-settings` |

采集数据：平板实例 5 个源（小众软件 / 少数派 / 机核 / 爱范儿，另有 `Tech` 分组），
2-in-1 实例 4 个源，均为真实订阅源、带封面图，不含账号与令牌；两种界面语言在应用内切换后各拍一套。
主界面与卡片视图都在「机核」筛选下拍摄（卡片全部有图）；设置页拍的是同一会话里的选项面板。

## 卡片视图的取景约定

四张卡片截图**必须全部有封面**：先在侧栏选中「机核」再切卡片视图，这个源的文章篇篇带图，
整个网格扫下来不会出现灰色占位（`.fr` 里 RSS 频道图标那种）。已逐张核对：
平板 3 列 × 2 行、2-in-1 4 列 × 2 行，每一张卡片都有配图。

不要用「全部文章」拍卡片视图 —— 少数派的条目没有封面，网格里会留灰块，这种图不能上 AGC。

## 与上一版（2026-10-30）的差别

上一版是 2560×1600 / 2160×1440，平板上是抽屉式侧栏（1138vp）。这一版按 1920×1280 /
1920×1080 重拍：平板落在宽屏版式（侧栏常驻、三列卡片），2-in-1 仍是三栏 + 卡片。
要还原成抽屉版式，得先把实例密度真正降到 270 左右再采集（原因见上面「平板为什么要缩放」）。
