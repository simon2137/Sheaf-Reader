#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把选定的 02-sheaf-bundle 方案落地成工程资源。

产出：
  AppScope/resources/base/media/{foreground,background}.png   1024x1024 分层图标两层
  entry/src/main/resources/base/media/{foreground,background}.png
  AppScope/resources/base/media/app_icon.png                  1024x1024 直角平面主图（README/AGC 用）
  entry/src/main/resources/base/media/app_icon.png            同上
  entry/src/main/resources/base/media/start_icon.png          144x144 启动页图标
  docs/icon-drafts/02-sheaf-bundle/agc-216.png                216x216 AGC 上架用直角图

layered_image.json 与 app.json5 / module.json5 的引用由人工（工具调用）改，脚本不碰配置。
用法：python docs/icon-drafts/apply_icon.py
"""

import os
import shutil

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(HERE, "02-sheaf-bundle")

APP_MEDIA = os.path.join(PROJ, "AppScope", "resources", "base", "media")
ENTRY_MEDIA = os.path.join(PROJ, "entry", "src", "main", "resources", "base", "media")

SAFE_BOX = (202, 202, 822, 822)   # 中心 620x620 安全区


def alpha_bbox(img):
    a = np.asarray(img.convert("RGBA"))[..., 3]
    ys, xs = np.nonzero(a > 4)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def main():
    fg = Image.open(os.path.join(SRC, "foreground.png")).convert("RGBA")
    bg = Image.open(os.path.join(SRC, "background.png")).convert("RGBA")
    assert fg.size == (1024, 1024) and bg.size == (1024, 1024), "分层图层必须是 1024x1024"

    bb = alpha_bbox(fg)
    print("foreground alpha bbox:", bb)
    assert bb and bb[0] >= SAFE_BOX[0] and bb[1] >= SAFE_BOX[1] \
        and bb[2] <= SAFE_BOX[2] and bb[3] <= SAFE_BOX[3], "前景主体越出 620x620 安全区"
    ba = np.asarray(bg)[..., 3]
    assert ba.min() == 255, "背景层必须完全不透明"
    assert np.asarray(fg)[..., 3].min() == 0, "前景层必须有透明区域"

    flat = bg.convert("RGB")
    flat.paste(fg, (0, 0), fg)                       # 直角平面主图（前景叠背景）
    flat_rgba = flat.convert("RGBA")

    for media in (APP_MEDIA, ENTRY_MEDIA):
        os.makedirs(media, exist_ok=True)
        shutil.copyfile(os.path.join(SRC, "foreground.png"), os.path.join(media, "foreground.png"))
        shutil.copyfile(os.path.join(SRC, "background.png"), os.path.join(media, "background.png"))
        flat_rgba.save(os.path.join(media, "app_icon.png"))
        print("ok", os.path.relpath(media, PROJ))

    flat_rgba.resize((144, 144), Image.LANCZOS).save(os.path.join(ENTRY_MEDIA, "start_icon.png"))
    print("ok start_icon.png 144x144")

    # 应用内标识（侧栏头部 / 关于页 / 加载页）由 make_inapp_mark.py 生成：
    # 透明底 + 元素按浅色/深色换色，不在这里产出。

    flat_rgba.resize((216, 216), Image.LANCZOS).save(os.path.join(SRC, "agc-216.png"))
    print("ok agc-216.png 216x216")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
