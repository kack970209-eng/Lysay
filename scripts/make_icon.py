"""生成 Lysay 的 App 图标（1024x1024）。

设计：黑色底。L 的横笔一路延伸到 Y 的竖笔，把 “LY” 连成一笔；
L 与 Y 之间站着一排 iOS 系统蓝的声波条，文字和语音合成一个整体。
用法：python scripts/make_icon.py <输出路径>
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
SS = 4          # 超采样倍数，最后缩小以获得平滑边缘
S = 1024 * SS


def s(v):
    return int(round(v * SS))


# 1. 背景：近黑色，中间略亮
bg = Image.new("RGB", (S, S), (0, 0, 0))
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse((s(140), s(120), s(884), s(860)), fill=255)
glow = glow.filter(ImageFilter.GaussianBlur(s(180)))
img = Image.composite(Image.new("RGB", (S, S), (28, 28, 34)), bg, glow).convert("RGBA")

layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)

WHITE = (255, 255, 255, 255)
STROKE = 92                     # 主笔画粗细
TOP = 250
BASE = 772                      # 横笔中线
LX, YX = 236, 700               # L 竖笔、Y 竖笔的中线
ARM_DX, FORK_Y = 150, 470
SHIFT = 512 - ((LX - STROKE / 2) + (YX + ARM_DX + STROKE / 2)) / 2   # 整体水平居中


def thick_line(p0, p1, width, fill, draw):
    p0 = (p0[0] + SHIFT, p0[1])
    p1 = (p1[0] + SHIFT, p1[1])
    draw.line((s(p0[0]), s(p0[1]), s(p1[0]), s(p1[1])), fill=fill, width=s(width))
    for p in (p0, p1):
        draw.ellipse((s(p[0] - width / 2), s(p[1] - width / 2), s(p[0] + width / 2), s(p[1] + width / 2)), fill=fill)


# 2. L 和 Y 连成一笔：L 的竖笔 → 横笔一直延伸到 Y 的竖笔底部 → Y
thick_line((LX, TOP + STROKE / 2), (LX, BASE), STROKE, WHITE, d)
thick_line((LX, BASE), (YX, BASE), STROKE, WHITE, d)
thick_line((YX, BASE), (YX, FORK_Y), STROKE, WHITE, d)
thick_line((YX, FORK_Y), (YX - ARM_DX, TOP + STROKE / 2), STROKE, WHITE, d)
thick_line((YX, FORK_Y), (YX + ARM_DX, TOP + STROKE / 2), STROKE, WHITE, d)
img.alpha_composite(layer)

# 3. 声波：夹在 L 与 Y 之间，上下对称，像说话时的声波
BLUE_TOP = (110, 185, 255)
BLUE_BOTTOM = (10, 110, 255)
bar_w, gap = 38, 22
heights = [64, 150, 228, 132, 76]
inner_left = LX + STROKE / 2 + 30
inner_right = YX - STROKE / 2 - 30
total = len(heights) * bar_w + (len(heights) - 1) * gap
x0 = inner_left + (inner_right - inner_left - total) / 2 + SHIFT
center_y = 606

grad_mask = Image.new("L", (S, S), 0)
gm = ImageDraw.Draw(grad_mask)
for i, h in enumerate(heights):
    bx = x0 + i * (bar_w + gap)
    gm.rounded_rectangle((s(bx), s(center_y - h / 2), s(bx + bar_w), s(center_y + h / 2)), radius=s(bar_w / 2), fill=255)

grad = Image.new("RGB", (1, S))
for yy in range(S):
    t = min(1.0, max(0.0, (yy / SS - 500) / 220))
    grad.putpixel((0, yy), tuple(int(BLUE_TOP[i] + (BLUE_BOTTOM[i] - BLUE_TOP[i]) * t) for i in range(3)))
grad = grad.resize((S, S)).convert("RGBA")

blur = grad_mask.filter(ImageFilter.GaussianBlur(s(24)))
glow_layer = Image.new("RGBA", (S, S), (40, 130, 255, 0))
glow_layer.putalpha(blur.point(lambda a: int(a * 0.6)))
img.alpha_composite(glow_layer)
blue_bars = Image.new("RGBA", (S, S), (0, 0, 0, 0))
blue_bars.paste(grad, (0, 0), grad_mask)
img.alpha_composite(blue_bars)
yx = YX + SHIFT

# 5. 顶部极淡的玻璃高光
sheen = Image.new("L", (1, S), 0)
for yy in range(S):
    t = yy / S
    sheen.putpixel((0, yy), int(max(0.0, 1 - t / 0.5) ** 2 * 26))
sheen = sheen.resize((S, S))
sheen_layer = Image.new("RGBA", (S, S), (255, 255, 255, 0))
sheen_layer.putalpha(sheen)
img.alpha_composite(sheen_layer)

img = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")
img.save(OUT, "PNG")
print("saved", OUT, "Y stem x =", round(yx))
