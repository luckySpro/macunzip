"""生成 MacUnZip 应用图标（macOS 圆角方形模板，1024×1024 及各尺寸）。
用法：python3 scripts/make-icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import json

S = 4096  # 先按 4 倍画，再缩小以获得平滑边缘
k = S / 1024

def box(x0, y0, x1, y1):
    return [int(x0 * k), int(y0 * k), int(x1 * k), int(y1 * k)]

def vertical_gradient(size, top, bottom):
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((w, h))

icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# 阴影
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle(box(100, 112, 924, 936), radius=int(185 * k), fill=(0, 0, 0, 90))
icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14 * k)))

# 底板：蓝色渐变圆角方形
plate_mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(plate_mask).rounded_rectangle(box(100, 100, 924, 924), radius=int(185 * k), fill=255)
plate = vertical_gradient((S, S), (74, 158, 255), (16, 92, 224)).convert("RGBA")
icon.paste(plate, (0, 0), plate_mask)

d = ImageDraw.Draw(icon)

# 文件卡片：白色，右上角折角
card_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(card_shadow).rounded_rectangle(box(282, 222, 742, 842), radius=int(44 * k), fill=(0, 30, 90, 110))
icon.alpha_composite(card_shadow.filter(ImageFilter.GaussianBlur(18 * k)))
d = ImageDraw.Draw(icon)
d.rounded_rectangle(box(282, 204, 742, 824), radius=int(44 * k), fill=(250, 251, 253, 255))
fold = [(742 - 120, 204), (742, 204 + 120)]
d.polygon([(fold[0][0] * k, 204 * k), (742 * k, 204 * k), (742 * k, fold[1][1] * k)], fill=(16, 92, 224, 0))
d.polygon([(fold[0][0] * k, 204 * k), (742 * k, fold[1][1] * k), (fold[0][0] * k, fold[1][1] * k)], fill=(212, 224, 242, 255))
# 擦掉折角外的白色
corner = Image.new("L", (S, S), 0)
ImageDraw.Draw(corner).polygon([(fold[0][0] * k, 196 * k), (750 * k, 196 * k), (750 * k, fold[1][1] * k)], fill=255)
icon.paste(plate, (0, 0), corner)

# 拉链：中线两侧交错的齿
cx = 512
teeth_color = (40, 52, 72, 255)
y = 220
i = 0
while y < 560:
    if i % 2 == 0:
        d.rounded_rectangle(box(cx - 34, y, cx + 2, y + 22), radius=int(6 * k), fill=teeth_color)
    else:
        d.rounded_rectangle(box(cx - 2, y, cx + 34, y + 22), radius=int(6 * k), fill=teeth_color)
    y += 30
    i += 1
# 拉开的部分：两排齿向两侧张开
for j in range(5):
    yy = 560 + j * 34
    off = 8 + j * 12
    d.rounded_rectangle(box(cx - 34 - off, yy, cx + 2 - off - 8, yy + 22), radius=int(6 * k), fill=teeth_color)
    d.rounded_rectangle(box(cx - 2 + off + 8, yy + 15, cx + 34 + off, yy + 37), radius=int(6 * k), fill=teeth_color)

# 拉头
d.rounded_rectangle(box(cx - 46, 530, cx + 46, 600), radius=int(20 * k), fill=(255, 176, 32, 255))
d.rounded_rectangle(box(cx - 22, 588, cx + 22, 700), radius=int(18 * k), fill=(255, 176, 32, 255))
d.rounded_rectangle(box(cx - 9, 612, cx + 9, 680), radius=int(9 * k), fill=(250, 251, 253, 255))

out = icon.resize((1024, 1024), Image.LANCZOS)

root = Path(__file__).resolve().parent.parent
iconset = root / "App" / "Assets.xcassets" / "AppIcon.appiconset"
iconset.mkdir(parents=True, exist_ok=True)
(root / "App" / "Assets.xcassets" / "Contents.json").write_text(
    json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))

images = []
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        out.resize((px, px), Image.LANCZOS).save(iconset / name)
        images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
(iconset / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))
out.save(root / "docs" / "icon.png")
print("ok")
