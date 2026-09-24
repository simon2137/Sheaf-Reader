#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成应用内品牌标识：透明底 + 元素重新配色，浅色/深色各一套。

为什么不直接把 App 图标的方块底抠掉：图标里三张纸是白色、文字线是蓝色，
放到浅色侧栏（#FAFAFA）上会直接消失。所以做成**透明底 + 元素换色**：

  浅色底那套：纸 = 深蓝 / 蓝灰，文字线 = 浅蓝，束带 = 品牌蓝
  深色底那套：纸 = near-white，文字线 = 深蓝，束带 = 亮蓝

图形与 App 图标同源（三张扇形叠放的纸 + 束带），但只保留标识本身，不含任何背景。

输出（256x256，透明底）：
  entry/src/main/resources/base/media/app_mark_light.png
  entry/src/main/resources/base/media/app_mark_dark.png
另出对比预览：docs/icon-drafts/02-sheaf-bundle/inapp-mark-preview.png
用法：python docs/icon-drafts/make_inapp_mark.py
"""

import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
ENTRY_MEDIA = os.path.join(PROJ, "entry", "src", "main", "resources", "base", "media")

S = 4                 # 超采样
OUT = 256             # 成品边长
FILL = 0.88           # 墨迹占成品的比例（与原来那个 Material 字形的视觉重量接近）
PAD = 140             # 旋转留白，避免裁掉角

SHEET_W, SHEET_H, SHEET_R = 300, 440, 38      # 与 02-sheaf-bundle 同一套设计坐标
SIDE_H = 390
SIDE_DEG = 17
PIVOT = (512, 700)                            # 三张纸收拢的底边中点
STRAP = (292, 570, 732, 642, 36)
LINES = ((82, 112, 252), (82, 170, 222))      # 纸内文字线：x0, y, x1（纸局部坐标）
LINE_T = 34

VARIANTS = {
    "light": {"back": (143, 163, 184), "front": (31, 58, 95),
              "line": (220, 233, 247), "strap": (0, 120, 212)},
    "dark": {"back": (110, 124, 140), "front": (237, 242, 247),
             "line": (42, 74, 107), "strap": (76, 194, 255)},
}


def sheet_layer(h, colors, with_lines):
    w = SHEET_W + 2 * PAD
    hh = h + 2 * PAD
    img = Image.new("RGBA", (w * S, hh * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([PAD * S, PAD * S, (PAD + SHEET_W) * S - 1, (PAD + h) * S - 1],
                        radius=SHEET_R * S, fill=colors["front"] + (255,))
    if with_lines:
        for (x0, y, x1) in LINES:
            d.rounded_rectangle([(PAD + x0) * S, (PAD + y - LINE_T / 2) * S,
                                 (PAD + x1) * S, (PAD + y + LINE_T / 2) * S],
                                radius=LINE_T / 2 * S, fill=colors["line"] + (255,))
    pivot = (PAD + SHEET_W / 2.0, PAD + h)     # 纸张底边中点
    return img, pivot


def build(colors):
    canvas = Image.new("RGBA", (1024 * S, 1024 * S), (0, 0, 0, 0))

    def place(layer, pivot, deg):
        px = (pivot[0] * S, pivot[1] * S)          # layer.rotate 要的是像素坐标
        rot = layer.rotate(deg, resample=Image.BICUBIC, center=px)
        canvas.alpha_composite(
            rot, (int(PIVOT[0] * S - px[0]), int(PIVOT[1] * S - px[1])))

    for deg in (-SIDE_DEG, SIDE_DEG):
        layer, pivot = sheet_layer(SIDE_H, {"front": colors["back"], "line": colors["line"]}, False)
        place(layer, pivot, deg)
    layer, pivot = sheet_layer(SHEET_H, colors, True)
    place(layer, pivot, 0)

    x0, y0, x1, y1, r = STRAP
    ImageDraw.Draw(canvas).rounded_rectangle(
        [x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S, fill=colors["strap"] + (255,))

    art = canvas.crop(canvas.getbbox())
    scale = (OUT * FILL) / max(art.width, art.height)
    art = art.resize((max(1, round(art.width * scale)), max(1, round(art.height * scale))),
                     Image.LANCZOS)
    out = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
    out.alpha_composite(art, ((OUT - art.width) // 2, (OUT - art.height) // 2))
    return out


def preview(made):
    cw, ch = 360, 250
    canvas = Image.new("RGB", (cw * 2, ch), (250, 250, 250))
    d = ImageDraw.Draw(canvas)
    for i, (variant, bg) in enumerate((("light", (250, 250, 250)), ("dark", (27, 26, 25)))):
        x = i * cw
        d.rectangle([x, 0, x + cw - 1, ch - 1], fill=bg)
        img = made[variant]
        big = img.resize((110, 110), Image.LANCZOS)
        canvas.paste(big, (x + 30, 30), big)
        for k, px in enumerate((22, 32)):
            th = img.resize((px, px), Image.LANCZOS)
            canvas.paste(th, (x + 175, 40 + k * 60), th)
            z = img.resize((px * 4, px * 4), Image.LANCZOS)
            canvas.paste(z, (x + 210, 20 + k * 100), z)
        d.text((x + 30, 215), "%s variant  (110px, 22px, 32px, 4x)" % variant,
               fill=(130, 130, 130))
    p = os.path.join(HERE, "02-sheaf-bundle", "inapp-mark-preview.png")
    canvas.save(p)
    return p


def main():
    made = {}
    for name, colors in VARIANTS.items():
        img = build(colors)
        out = os.path.join(ENTRY_MEDIA, "app_mark_%s.png" % name)
        img.save(out)
        made[name] = img
        print("ok", out, img.size)
    print("preview", preview(made))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
