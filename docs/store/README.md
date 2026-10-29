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

## 采集要求

- **设备**：`Huawei_Tablet`（平板，2560×1600，density 360）与 `Huawei_2in1`
  （2-in-1，2160×1440，density 200；窗口最大化后 1728vp，三栏布局才会出现）。
- **尺寸**：原图 2560×1600 / 2160×1440，按原样提交，不裁剪、不加边框。
- **数据**：真实订阅源（含封面图），不出现真实账号令牌。
- **语言**：设置 → 界面语言 切换后重新采集，保证同一套截图界面一致。
- **命名**：见上表；缺图时不要放占位文件。

## 当前进度

已完成 6 / 12（平板中英文齐）：

- `tablet-zh-01-main.jpeg`、`tablet-zh-02-cards.jpeg`、`tablet-zh-03-settings.jpeg`
- `tablet-en-01-main.jpeg`、`tablet-en-02-cards.jpeg`、`tablet-en-03-settings.jpeg`

待采集：`2in1-zh-*`、`2in1-en-*` 六张（需 `Huawei_2in1` 窗口最大化，1728vp 才出现三栏）。
