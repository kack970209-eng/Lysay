"""生成 Lysay 的 App 图标（1024x1024）：蓝紫渐变底 + 白色声波。"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1]
S = 1024
img = Image.new("RGB", (S, S))
px = img.load()
c1 = (84, 102, 255)
c2 = (219, 92, 242)
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

# 柔光
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse((420, -200, 1180, 560), fill=110)
glow = glow.filter(ImageFilter.GaussianBlur(120))
img = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), img, glow)

# 声波条
d = ImageDraw.Draw(img)
heights = [0.22, 0.42, 0.66, 0.9, 0.66, 0.42, 0.22]
bar_w = 70
gap = 46
total = len(heights) * bar_w + (len(heights) - 1) * gap
x0 = (S - total) // 2
for i, h in enumerate(heights):
    bh = int(h * 560)
    x = x0 + i * (bar_w + gap)
    y = (S - bh) // 2
    d.rounded_rectangle((x, y, x + bar_w, y + bh), radius=bar_w // 2, fill=(255, 255, 255))

img.save(out, "PNG")
