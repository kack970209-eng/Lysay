"""把模拟器截图做成 App Store 上架图（1320×2868，黑底 + 标题）。
用法：python scripts/make_store_shots.py <原始截图资料夹> <输出资料夹>
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC, DST = Path(sys.argv[1]), Path(sys.argv[2])
DST.mkdir(parents=True, exist_ok=True)
W, H = 1320, 2868
BOLD = "C:/Windows/Fonts/msjhbd.ttc"
REG = "C:/Windows/Fonts/msjh.ttc"

SHOTS = [
    ("dark-voice", "說話就能打字", "邊說邊出字，聲波即時回應"),
    ("dark-polish", "AI 幫你整理", "去掉口水音，整理成通順的一段話"),
    ("light-zhuyin", "完整注音鍵盤", "整句轉換，選字又快又準"),
    ("light-clipboard", "剪貼簿與收藏", "複製過的文字，點一下就輸入"),
    ("light-home", "全部離線運行", "語音與 AI 都在手機上，保護隱私"),
]


def background():
    bg = Image.new("RGB", (W, H), (0, 0, 0))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-200, -500, W + 200, 900), fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    blue = Image.new("RGB", (W, H), (10, 60, 140))
    return Image.composite(blue, bg, glow.point(lambda a: int(a * 0.55)))


for i, (name, title, sub) in enumerate(SHOTS, 1):
    img = background()
    d = ImageDraw.Draw(img)
    ft = ImageFont.truetype(BOLD, 112)
    fs = ImageFont.truetype(REG, 56)
    tw = d.textlength(title, font=ft)
    d.text(((W - tw) / 2, 190), title, font=ft, fill=(255, 255, 255))
    sw = d.textlength(sub, font=fs)
    d.text(((W - sw) / 2, 350), sub, font=fs, fill=(170, 200, 255))

    shot = Image.open(SRC / f"{name}.png").convert("RGB")
    sw_, sh_ = 1050, int(shot.height * 1050 / shot.width)
    shot = shot.resize((sw_, sh_), Image.LANCZOS)
    x, y = (W - sw_) // 2, 520
    mask = Image.new("L", (sw_, sh_), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw_, sh_), radius=70, fill=255)
    # 阴影与描边
    sh = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh).rounded_rectangle((x - 6, y - 6, x + sw_ + 6, y + sh_ + 6), radius=76, fill=255)
    sh = sh.filter(ImageFilter.GaussianBlur(30))
    img = Image.composite(Image.new("RGB", (W, H), (40, 90, 200)), img, sh.point(lambda a: int(a * 0.35)))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((x - 4, y - 4, x + sw_ + 4, y + sh_ + 4), radius=74, fill=(60, 60, 70))
    img.paste(shot, (x, y), mask)
    out = DST / f"{i:02d}-{name}.png"
    img.save(out)
    print("saved", out)
