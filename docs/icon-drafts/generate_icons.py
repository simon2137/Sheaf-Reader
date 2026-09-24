#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sheaf Reader 束阅 —— 应用图标设计稿生成器（6 版方案）。

输出（每版一个目录）：
    background.png   1024x1024 不透明背景层
    foreground.png   1024x1024 透明背景前景层（只含图标主体）
    preview.png      1024x1024 合成效果（未遮罩，方图）
    masked.png       1024x1024 套用系统超椭圆遮罩后的示意
另输出 overview.png（全部方案总览）与 _guides.png（安全区说明）。

依赖：Pillow + numpy（本机已装，无网络依赖）。
用法：python docs/icon-drafts/generate_icons.py
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

N = 1024          # 成品边长
S = 4             # 超采样倍数
W = N * S         # 工作画布边长
ROOT = os.path.dirname(os.path.abspath(__file__))

FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"
FONT_REG = "C:/Windows/Fonts/msyh.ttc"
FONT_SEMI = "C:/Windows/Fonts/seguisb.ttf"

BRAND = "#0078D4"
BRAND_DARK = "#106EBE"
STAR = "#FFB900"

# ---------------------------------------------------------------- 基础工具


def hx(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def gradient(c0, c1, angle=45.0):
    """线性渐变（工作画布尺寸的 float 数组 HxWx3）。"""
    y, x = np.mgrid[0:W, 0:W]
    a = math.radians(angle)
    t = x * math.cos(a) + y * math.sin(a)
    t = (t - t.min()) / (t.max() - t.min())
    return hx(c0)[None, None, :] * (1 - t[..., None]) + hx(c1)[None, None, :] * t[..., None]


def glow(arr, color, center, radius, alpha):
    """叠加一团柔光。"""
    y, x = np.mgrid[0:W, 0:W]
    d = np.sqrt((x - center[0] * S) ** 2 + (y - center[1] * S) ** 2) / (radius * S)
    g = np.clip(1.0 - d, 0, 1) ** 2 * alpha
    return arr * (1 - g[..., None]) + hx(color)[None, None, :] * g[..., None]


def to_bg(arr):
    """渐变数组 -> 1024 背景图（RGB）。"""
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    return img.resize((N, N), Image.LANCZOS)


def premul_downsample(layer):
    """带 alpha 的工作画布 -> 1024 RGBA（预乘后缩放，避免透明边灰边）。"""
    a = np.asarray(layer).astype(np.float32)
    al = a[..., 3:4] / 255.0
    pm = np.concatenate([a[..., :3] * al, a[..., 3:4]], axis=2)
    small = np.asarray(
        Image.fromarray(np.clip(pm, 0, 255).astype(np.uint8), "RGBA").resize((N, N), Image.LANCZOS)
    ).astype(np.float32)
    al2 = small[..., 3:4] / 255.0
    rgb = np.where(al2 > 1e-6, small[..., :3] / np.maximum(al2, 1e-6), 0)
    return Image.fromarray(
        np.concatenate([np.clip(rgb, 0, 255), small[..., 3:4]], axis=2).astype(np.uint8), "RGBA"
    )


def bez(p0, p1, p2, p3, n=140):
    """三次贝塞尔采样。"""
    t = np.linspace(0.0, 1.0, n)[:, None]
    P = ((1 - t) ** 3) * np.array(p0) + 3 * ((1 - t) ** 2) * t * np.array(p1) \
        + 3 * (1 - t) * (t ** 2) * np.array(p2) + (t ** 3) * np.array(p3)
    return [(float(v[0]), float(v[1])) for v in P]


def arc(cx, cy, r, a0, a1, n=110):
    """圆心角采样；角度为屏幕坐标（y 向下），-90 度=正上方，0 度=正右方。"""
    out = []
    for a in np.linspace(a0, a1, n):
        rad = math.radians(a)
        out.append((cx + r * math.cos(rad), cy + r * math.sin(rad)))
    return out


class Layer:
    """工作画布上的绘制层；fill 传 (0,0,0,0) 即为擦除（ImageDraw 不做混合）。"""

    def __init__(self):
        self.img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    @staticmethod
    def _p(pts):
        return [(float(x) * S, float(y) * S) for x, y in pts]

    def stroke(self, pts, width, fill, caps=True, joins=True):
        """粗折线：用偏移多边形 + 逐点圆头/圆角绘制。

        不用 ImageDraw.line(joint="curve")：采样点很密时它的关节算法会在大线宽下
        产生毛刺（实测弧线外缘出现梳齿），多边形法在任何曲率下都干净。
        """
        n = len(pts)
        hw = width / 2.0
        left, right = [], []
        for i, p in enumerate(pts):
            if i == 0:
                dx, dy = pts[1][0] - p[0], pts[1][1] - p[1]
            elif i == n - 1:
                dx, dy = p[0] - pts[n - 2][0], p[1] - pts[n - 2][1]
            else:
                dx, dy = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
            L = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / L * hw, dx / L * hw
            left.append((p[0] + nx, p[1] + ny))
            right.append((p[0] - nx, p[1] - ny))
        self.poly(left + right[::-1], fill)
        if joins:
            for p in pts:
                self.circle(p, hw, fill)
        if caps:
            self.circle(pts[0], hw, fill)
            self.circle(pts[-1], hw, fill)

    def circle(self, c, r, fill):
        x, y = c[0] * S, c[1] * S
        rr = r * S
        self.d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=fill)

    def rrect(self, box, radius, fill):
        self.d.rounded_rectangle(
            [box[0] * S, box[1] * S, box[2] * S, box[3] * S], radius=radius * S, fill=fill
        )

    def poly(self, pts, fill):
        self.d.polygon(self._p(pts), fill=fill)

    def band(self, p0, p1, width, fill):
        """两端圆头的斜带（用于字标镂空切割）。"""
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        L = math.hypot(dx, dy)
        nx, ny = -dy / L * width / 2.0, dx / L * width / 2.0
        self.poly(
            [(p0[0] + nx, p0[1] + ny), (p1[0] + nx, p1[1] + ny),
             (p1[0] - nx, p1[1] - ny), (p0[0] - nx, p0[1] - ny)],
            fill,
        )
        self.circle(p0, width / 2.0, fill)
        self.circle(p1, width / 2.0, fill)

    def text(self, xy, s, font_path, size, fill, anchor="la"):
        f = ImageFont.truetype(font_path, int(size * S))
        self.d.text((xy[0] * S, xy[1] * S), s, font=f, fill=fill, anchor=anchor)


WHITE = (255, 255, 255, 255)


def composed(bg_img, fg_img):
    out = bg_img.convert("RGBA")
    out.alpha_composite(fg_img)
    return out


# ------------------------------------------------- 系统超椭圆（squircle）遮罩


def squircle_alpha(size, inset=0.055, n=4.0):
    y, x = np.mgrid[0:size, 0:size]
    c = (size - 1) / 2.0
    r = (size / 2.0) * (1 - 2 * inset)
    u = (x - c) / r
    v = (y - c) / r
    e = (np.abs(u) ** n + np.abs(v) ** n) ** (1.0 / n)
    return np.clip((1.0 - e) * r / 1.6 + 0.5, 0, 1)


def apply_mask(img, size=N):
    a = (np.asarray(img.convert("RGBA")).astype(np.float32))
    a[..., 3] *= squircle_alpha(size).astype(np.float32)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ 6 版方案
# 安全区：所有主体都画在 1024 画布中心 620x620 范围内（系统裁切/留白更保险）。


def v1_rss_arcs():
    """经典 RSS 弧线：识别度最高，最稳妥。"""
    bg = to_bg(glow(gradient("#0A8AF0", "#00509E", 55), "#FFFFFF", (400, 320), 900, 0.10))
    L = Layer()
    ox, oy = 343, 681
    L.circle((ox, oy), 62, WHITE)
    for r in (219, 400):
        L.stroke(arc(ox, oy, r, -90, 0), 64, WHITE)
    return bg, premul_downsample(L.img)


def v2_sheaf_bundle():
    """麦束 / 纸束：三张纸扇形叠放、被一条束带扎起 —— 呼应 “Sheaf（束）”。"""
    bg = to_bg(glow(gradient("#26333F", "#141C24", 60), BRAND, (512, 320), 780, 0.22))
    L = Layer()
    CW, CH = 600, 620
    PIVOT = (300, 560)          # 纸张底边中点：三张纸在此收拢

    def sheet(angle, alpha, h=440, lines=False):
        img = Image.new("RGBA", (CW * S, CH * S), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([150 * S, (560 - h) * S, 450 * S, 560 * S], radius=38 * S,
                            fill=(255, 255, 255, alpha))
        if lines:
            for y, x1 in ((232, 402), (290, 372)):
                d.rounded_rectangle([232 * S, (y - 17) * S, x1 * S, (y + 17) * S],
                                    radius=17 * S, fill=(0, 110, 196, 235))
        return img.rotate(angle, resample=Image.BICUBIC, center=(PIVOT[0] * S, PIVOT[1] * S))

    px, py = (512 - PIVOT[0]) * S, (700 - PIVOT[1]) * S
    for angle, alpha in ((-17, 150), (17, 150)):
        L.img.alpha_composite(sheet(angle, alpha, h=390), (px, py))
    L.img.alpha_composite(sheet(0, 255, lines=True), (px, py))
    L.rrect((292, 570, 732, 642), 36, (76, 179, 255, 255))   # 束带
    return bg, premul_downsample(L.img)


def _fit_font(text, font_path, target_h):
    lo, hi, best = 20, 4000, None
    for _ in range(24):
        mid = (lo + hi) // 2
        f = ImageFont.truetype(font_path, mid)
        b = f.getbbox(text)
        if b[3] - b[1] < target_h:
            lo = mid
        else:
            hi = mid
        best = (f, mid)
    f = ImageFont.truetype(font_path, lo)
    return f, lo, f.getbbox(text)


def v3_monogram_s():
    """字标 S：加粗字母 + 深蓝投影，纯粹的字母标。"""
    bg = to_bg(glow(gradient(BRAND, "#004E8C", 90), "#FFFFFF", (512, 300), 900, 0.10))
    L = Layer()
    f, size, box = _fit_font("S", FONT_SEMI, 560 * S)
    x = W / 2.0 - (box[0] + box[2]) / 2.0
    y = W / 2.0 - (box[1] + box[3]) / 2.0
    L.d.text((x + 18 * S, y + 18 * S), "S", font=f, fill=(0, 62, 112, 130))
    L.d.text((x, y), "S", font=f, fill=WHITE)
    return bg, premul_downsample(L.img)


def v4_doc_feed():
    """文档 + 折角 + 订阅弧：文章与订阅两件事一次说清。"""
    bg = to_bg(glow(gradient(BRAND_DARK, "#00386B", 60), "#FFFFFF", (512, 300), 900, 0.10))
    L = Layer()
    white = WHITE
    L.rrect((302, 262, 722, 762), 56, white)
    L.poly([(566, 262), (722, 262), (722, 418)], (0, 0, 0, 0))       # 切出折角
    L.poly([(566, 268), (716, 418), (566, 418)], (207, 231, 255, 255))  # 翻起的纸角
    blue = (0, 120, 212, 255)
    L.stroke([(366, 364), (566, 364)], 40, blue)
    L.stroke([(366, 436), (636, 436)], 40, blue)
    ox, oy = 440, 676
    L.circle((ox, oy), 38, blue)
    for r in (106, 178):
        L.stroke(arc(ox, oy, r, -90, 0), 40, blue)
    return bg, premul_downsample(L.img)


def v5_fluent_flow():
    """流线：从一点发散的信息流，呼应 Fluent 设计语言的曲线。"""
    bg = to_bg(glow(gradient("#00B7C3", "#0067B8", 70), "#FFFFFF", (380, 300), 800, 0.12))
    L = Layer()
    for p1, p2, p3 in (
        ((420, 610), (560, 560), (742, 470)),
        ((378, 548), (508, 470), (688, 352)),
        ((338, 470), (466, 368), (620, 238)),
    ):
        L.stroke(bez((322, 706), p1, p2, p3), 52, WHITE)
    L.circle((322, 706), 62, WHITE)
    return bg, premul_downsample(L.img)


def v6_card_list():
    """卡片流 + 未读徽标：直白的“阅读列表 + 有新内容”。"""
    bg = to_bg(glow(gradient("#0A8AF0", "#004C99", 60), "#FFFFFF", (420, 300), 900, 0.10))
    L = Layer()
    L.rrect((300, 286, 700, 420), 38, (255, 255, 255, 255))
    L.rrect((300, 464, 700, 598), 38, (255, 255, 255, 170))
    L.rrect((300, 642, 700, 776), 38, (255, 255, 255, 92))
    L.circle((702, 353), 54, (255, 185, 0, 255))
    return bg, premul_downsample(L.img)


VARIANTS = [
    ("01-rss-arcs", "RSS 弧线", "白色信号弧 + 圆点，蓝底渐变",
     "识别度最高的通用解：任何用户一眼就知道是订阅/阅读器。\n风险是“太标准”，缺少品牌个性。", v1_rss_arcs),
    ("02-sheaf-bundle", "麦束 / 纸束", "三张纸扇形叠放、被蓝色束带扎起，深色底",
     "呼应品牌名 Sheaf Reader / 束阅 —— “把信息扎成一束”。\n深色底在深色桌面与浅色桌面上都稳。", v2_sheaf_bundle),
    ("03-monogram-s", "字标 S", "加粗 S + 深蓝投影，品牌蓝底",
     "字标路线，小尺寸下轮廓最清晰。\n缺点：单字母与“订阅”语义无关。", v3_monogram_s),
    ("04-doc-feed", "文档 + 订阅弧", "折角文档 + 正文线 + RSS 弧，深蓝底",
     "把“读文章”和“订源”两个核心动作放进一张图，信息量最大。\n元素较多，16x16 级别的极小尺寸下会糊。", v4_doc_feed),
    ("05-fluent-flow", "流线", "一点发散的三条流线，青蓝渐变",
     "抽象路线，和 Fluent 设计语言同源，动态感强。\n语义最弱，需要配合应用名使用。", v5_fluent_flow),
    ("06-card-list", "卡片流 + 未读点", "三层半透明卡片 + 琥珀色未读徽标",
     "直译应用主界面（列表 + 未读），与 App 内的列表布局自洽。\n卡片堆叠在小尺寸下易粘连。", v6_card_list),
]


# --------------------------------------------------------------------- 输出


def dashed_rect(d, box, dash=26, gap=18, width=5, fill=(255, 255, 255, 170)):
    x0, y0, x1, y1 = box
    for x in np.arange(x0, x1, dash + gap):
        d.line([(x, y0), (min(x + dash, x1), y0)], fill=fill, width=width)
        d.line([(x, y1), (min(x + dash, x1), y1)], fill=fill, width=width)
    for y in np.arange(y0, y1, dash + gap):
        d.line([(x0, y), (x0, min(y + dash, y1))], fill=fill, width=width)
        d.line([(x1, y), (x1, min(y + dash, y1))], fill=fill, width=width)


def build_overview(items, path):
    cols, pad, th = 1, 48, 244
    row_h = 300
    width = 1400
    head = 200
    height = head + row_h * len(items) + 40
    sheet = Image.new("RGB", (width, height), (244, 245, 247))
    d = ImageDraw.Draw(sheet)
    f_title = ImageFont.truetype(FONT_BOLD, 48)
    f_sub = ImageFont.truetype(FONT_REG, 25)
    f_name = ImageFont.truetype(FONT_BOLD, 36)
    f_tag = ImageFont.truetype(FONT_REG, 24)
    f_desc = ImageFont.truetype(FONT_REG, 24)

    d.text((pad, 46), "Sheaf Reader 束阅 · 应用图标 6 版设计稿", font=f_title, fill=(28, 30, 33))
    d.text((pad, 116), "1024×1024 分层图标（前景 / 背景分离）· 缩略图已套用系统超椭圆遮罩示意 · 主体均在中心 620×620 安全区内",
           font=f_sub, fill=(96, 100, 106))

    for i, (slug, name, tag, desc, _) in enumerate(items):
        y = head + i * row_h
        thumb = Image.open(os.path.join(ROOT, slug, "masked.png")).convert("RGBA").resize((th, th), Image.LANCZOS)
        card = Image.new("RGB", (th + 36, th + 36), (231, 233, 236))
        card.paste(thumb, (18, 18), thumb)
        sheet.paste(card, (pad, y))
        tx = pad + th + 76
        d.text((tx, y + 18), f"{slug}   {name}", font=f_name, fill=(20, 22, 26))
        d.text((tx, y + 74), tag, font=f_tag, fill=(0, 120, 212))
        d.text((tx, y + 122), desc, font=f_desc, fill=(90, 94, 100), spacing=12)

    sheet.save(path)
    return path


def make_guides(src, path):
    img = Image.open(src).convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    dashed_rect(d, (202, 202, 822, 822), fill=(255, 255, 255, 190))
    d.ellipse([202, 202, 822, 822], outline=(255, 255, 255, 90), width=4)
    alpha = squircle_alpha(N)[..., None]
    edge = np.zeros((N, N, 4), np.uint8)
    g = np.asarray(
        Image.fromarray((alpha[..., 0] * 255).astype(np.uint8), "L").filter(ImageFilter.FIND_EDGES)
    ).astype(np.float32)
    edge[..., 0] = 255
    edge[..., 1] = 255
    edge[..., 2] = 255
    edge[..., 3] = np.clip(g * 6, 0, 200).astype(np.uint8)
    img.alpha_composite(Image.fromarray(edge, "RGBA"))
    f = ImageFont.truetype(FONT_BOLD, 30)
    d.text((232, 838), "虚线 = 中心 620×620 安全区（主体不越界）", font=f, fill=(255, 255, 255, 235))
    d.text((232, 150), "细线 = 系统超椭圆遮罩边界（示意）", font=f, fill=(255, 255, 255, 235))
    img.convert("RGB").save(path)
    return path


def main():
    made = []
    for slug, name, tag, desc, fn in VARIANTS:
        bg, fg = fn()
        outdir = os.path.join(ROOT, slug)
        os.makedirs(outdir, exist_ok=True)
        bg.save(os.path.join(outdir, "background.png"))
        fg.save(os.path.join(outdir, "foreground.png"))
        prev = composed(bg, fg)
        prev.convert("RGB").save(os.path.join(outdir, "preview.png"))
        apply_mask(prev).save(os.path.join(outdir, "masked.png"))
        made.append(slug)
        print("ok", slug)

    items = [(s, n, t, d, None) for (s, n, t, d, _) in VARIANTS]
    ov = build_overview(items, os.path.join(ROOT, "overview.png"))
    gd = make_guides(os.path.join(ROOT, "02-sheaf-bundle", "preview.png"),
                     os.path.join(ROOT, "_guides.png"))
    print("ok overview ->", ov)
    print("ok guides ->", gd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
