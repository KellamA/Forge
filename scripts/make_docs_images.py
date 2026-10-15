"""Build README images: rounded, downscaled screenshots plus a hero banner.

Usage: python3 -I make_docs_images.py <raw screenshots dir> <docs dir> <app icon png>
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW, DOCS, ICON = sys.argv[1], sys.argv[2], sys.argv[3]
SHOTS = os.path.join(DOCS, "screenshots")
FONT = "/System/Library/Fonts/SFNSRounded.ttf"

SKIP = {"today-done.png"}


def font(size, weight="Bold"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def rounded_mask(size, radius, scale=4):
    w, h = size
    big = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, w * scale - 1, h * scale - 1], radius * scale, fill=255)
    return big.resize(size, Image.LANCZOS)


def rounded(img, radius):
    out = img.convert("RGBA")
    out.putalpha(rounded_mask(out.size, radius))
    return out


# 1. Screenshots: half size with the iPhone's rounded display corners.
os.makedirs(SHOTS, exist_ok=True)
for name in sorted(os.listdir(RAW)):
    if not name.endswith(".png"):
        continue
    dest = os.path.join(SHOTS, name)
    if name in SKIP:
        if os.path.exists(dest):
            os.remove(dest)
        continue
    img = Image.open(os.path.join(RAW, name)).convert("RGB")
    w = 603
    h = round(img.height * w / img.width)
    img = img.resize((w, h), Image.LANCZOS)
    rounded(img, 82).save(dest, optimize=True)
    print("shot", name, os.path.getsize(dest) // 1024, "KB")


# 2. Hero banner.
def phone(path, height):
    shot = Image.open(path).convert("RGB")
    width = round(shot.width * height / shot.height)
    shot = shot.resize((width, height), Image.LANCZOS)
    radius = round(width / 402 * 55)
    bezel = round(width * 0.035)
    frame = Image.new("RGBA", (width + bezel * 2, height + bezel * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle([0, 0, frame.width - 1, frame.height - 1], radius + bezel, fill=(28, 28, 30, 255))
    d.rounded_rectangle([1, 1, frame.width - 2, frame.height - 2], radius + bezel - 1, outline=(70, 70, 74, 255), width=2)
    frame.alpha_composite(rounded(shot, radius), (bezel, bezel))
    return frame


def shadowed(canvas, img, x, y, blur=40, alpha=170):
    shadow = Image.new("RGBA", (img.width + blur * 4, img.height + blur * 4), (0, 0, 0, 0))
    mask = img.split()[3].point(lambda a: alpha if a > 0 else 0)
    black = Image.new("RGBA", img.size, (0, 0, 0, 255))
    shadow.paste(black, (blur * 2, blur * 2 + blur // 2), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow, (x - blur * 2, y - blur * 2))
    canvas.alpha_composite(img, (x, y))


W, H = 2560, 1280
hero = Image.new("RGBA", (W, H), (10, 8, 8, 255))

# Warm glows behind the phones.
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([1300, 150, 2600, 1450], fill=(255, 107, 26, 120))
gd.ellipse([-300, 800, 700, 1700], fill=(245, 61, 48, 60))
glow = glow.filter(ImageFilter.GaussianBlur(220))
hero.alpha_composite(glow)

# Phones: side phones behind, centre phone in front.
raw = lambda n: os.path.join(RAW, n)
left = phone(raw("workout.png"), 930)
right = phone(raw("progress.png"), 930)
centre = phone(raw("today.png"), 1060)
cx = 1880
shadowed(hero, left, cx - centre.width // 2 - left.width + 150, (H - left.height) // 2 + 60)
shadowed(hero, right, cx + centre.width // 2 - 150, (H - right.height) // 2 + 60)
shadowed(hero, centre, cx - centre.width // 2, (H - centre.height) // 2 + 20, blur=50, alpha=200)

# Text column.
d = ImageDraw.Draw(hero)
icon = Image.open(ICON).convert("RGBA").resize((210, 210), Image.LANCZOS)
icon = rounded(icon, 48)
shadowed(hero, icon, 150, 230, blur=30, alpha=160)
d.text((140, 470), "Forge", font=font(190, "Heavy"), fill=(255, 255, 255))
d.text((150, 700), "Plan it. Lift it. Watch yourself", font=font(56, "Semibold"), fill=(205, 205, 210))
d.text((150, 770), "get stronger.", font=font(56, "Semibold"), fill=(205, 205, 210))
d.text((150, 870), "A personal strength & fitness tracker for iPhone", font=font(38, "Medium"), fill=(150, 150, 158))

chips = ["SwiftUI", "SwiftData + iCloud", "Live Activities", "Apple Health"]
x, y = 150, 950
chip_font = font(32, "Semibold")
# Draw chips on their own layer so the translucent fill blends with the background.
chip_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(chip_layer)
for label in chips:
    tw = cd.textlength(label, font=chip_font)
    w = int(tw + 52)
    if x + w > 1180:
        x, y = 150, y + 76
    cd.rounded_rectangle([x, y, x + w, y + 60], 30, fill=(255, 107, 26, 46), outline=(255, 140, 70, 170), width=2)
    cd.text((x + 26, y + 11), label, font=chip_font, fill=(255, 196, 150, 255))
    x += w + 16
hero.alpha_composite(chip_layer)

out = hero.convert("RGB")
out.save(os.path.join(DOCS, "hero.png"), optimize=True)
out.resize((1280, 640), Image.LANCZOS).save(os.path.join(DOCS, "social-preview.png"), optimize=True)
print("hero", os.path.getsize(os.path.join(DOCS, "hero.png")) // 1024, "KB")
