#!/usr/bin/env python3
"""Frames raw app captures as App Store and Play screenshots, plus the Play
feature graphic and icon. Writes store/.

1. Capture: flutter drive --driver=test_driver/integration_test.dart
     --target=integration_test/store_screens_test.dart -d <iPhone 6.9" sim>
   then copy build/screens/*.png to build/store_raw/iphone/ (and the same
   on an iPad 13" simulator into build/store_raw/ipad/).
2. Run: python3 tool/store_frames.py
"""
import os
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'build/store_raw')
OUT = os.path.join(ROOT, 'store')
TANKER = os.path.join(ROOT, 'assets/fonts/Tanker-Regular.otf')

GREEN = (31, 59, 54)      # peacock wall (icon "yellow" variant background)
PAPER = (242, 203, 193)   # cinema ticket paper
SERIAL = (226, 110, 96)   # stamp red, dark-mode tint

# (capture, caption). Order is the store order.
SHOTS = [
    ('01_home', 'Every film becomes\na ticket stub'),
    ('02_ticket', 'Hall, seat, show\nand price'),
    ('06_calendar', 'Your month\nin posters'),
    ('07_stats', 'Your year\nin films'),
    ('10_films_new', 'New releases,\nevery language'),
    ('11_film_page', 'See where\nit streams'),
    ('04_share', 'Share your\nticket'),
    ('13_home_hi_dark', '8 Indian\nlanguages'),
]
# On iPad the ticket screen is stretched wide; the poster grid uses the width.
IPAD_SWAP = {'02_ticket': ('09_stubs_grid', 'Every film\nyou have seen')}
# Blank status-bar band at the top of each capture.
TOP_CROP = {'iphone': 150, 'ipad': 60}

# name: (source, canvas w, h, side margin, caption size, corner radius)
TARGETS = {
    'appstore/iphone-6.9': ('iphone', 1320, 2868, 110, 118, 64),
    'appstore/iphone-6.5': ('iphone', 1284, 2778, 107, 115, 62),
    'appstore/ipad-13': ('ipad', 2064, 2752, 190, 132, 44),
    'play/phone': ('iphone', 1080, 1920, 150, 84, 44),
    'play/tablet': ('ipad', 1440, 2560, 120, 104, 32),
}


def grain(size, base, sigma=5):
    """Flat colour with fine monochrome noise (about +-5 levels), so it does not band."""
    noise = Image.effect_noise(size, sigma).convert('RGB')
    return ImageChops.add(Image.new('RGB', size, base), noise, 1.0, -128)


def rounded(im, radius):
    """Anti-aliased rounded corners (mask drawn at 4x, then scaled down)."""
    w, h = im.size
    m = Image.new('L', (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=radius * 4, fill=255)
    m = m.resize((w, h), Image.LANCZOS)
    out = Image.new('RGBA', (w, h))
    out.paste(im.convert('RGBA'), (0, 0), m)
    return out


def frame(src, W, H, margin, cap_size, radius, caption, serial):
    canvas = grain((W, H), GREEN)
    d = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(TANKER, cap_size)
    small = ImageFont.truetype(TANKER, int(cap_size * 0.42))

    # Caption block: left-aligned to the screen's left edge; serial on the right,
    # sharing the first line's cap top, like the head of a ticket.
    shot = Image.open(src).convert('RGB')
    shot = shot.crop((0, TOP_CROP[os.path.basename(os.path.dirname(src))], shot.width, shot.height))
    top = int(H * 0.055)
    lines = caption.upper().split('\n')
    lh = int(cap_size * 1.02)
    cap_h = lh * len(lines)
    avail_h = H - top - cap_h - int(H * 0.04) - int(H * 0.035)
    sw = W - 2 * margin
    sh = round(shot.height * sw / shot.width)
    if sh > avail_h:  # tall capture: fit height instead, stay centred
        sh = avail_h
        sw = round(shot.width * sh / shot.height)
    # Shrink the caption until every line clears the serial by 6% of the width.
    s_w = d.textbbox((0, 0), serial, font=small)[2]
    while max(d.textbbox((0, 0), ln, font=font)[2] for ln in lines) > sw - s_w - int(W * 0.06):
        cap_size -= 2
        font = ImageFont.truetype(TANKER, cap_size)
    lh = int(cap_size * 1.02)
    x0 = (W - sw) // 2
    for i, line in enumerate(lines):
        d.text((x0, top + i * lh), line, font=font, fill=PAPER)
    cap_top = d.textbbox((x0, top), lines[0], font=font)[1]
    s_box = d.textbbox((0, 0), serial, font=small)
    d.text((x0 + sw - (s_box[2] - s_box[0]) - s_box[0], cap_top - s_box[1]), serial, font=small, fill=SERIAL)

    y0 = top + cap_h + int(H * 0.04)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    canvas.paste(rounded(shot, radius), (x0, y0), rounded(shot, radius))
    return canvas


def feature_graphic():
    W, H = 1024, 500
    canvas = grain((W, H), GREEN)
    d = ImageDraw.Draw(canvas)
    d.text((64, 150), 'TALKIES', font=ImageFont.truetype(TANKER, 132), fill=PAPER)
    body = ImageFont.truetype(TANKER, 40)
    d.text((68, 300), 'EVERY FILM YOU WATCH', font=body, fill=SERIAL)
    d.text((68, 344), 'BECOMES A TICKET STUB', font=body, fill=SERIAL)
    # The real ticket screen, bleeding off the right and bottom edges.
    shot = Image.open(os.path.join(RAW, 'iphone/02_ticket.png')).convert('RGB').crop((0, 150, 1320, 2868))
    sw = 400
    shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
    r = rounded(shot, 26)
    canvas.paste(r, (W - sw - 60, 56), r)
    return canvas


def main():
    for name, (kind, W, H, margin, cap, radius) in TARGETS.items():
        out = os.path.join(OUT, name)
        os.makedirs(out, exist_ok=True)
        for i, (cap_name, caption) in enumerate(SHOTS, 1):
            if kind == 'ipad':
                cap_name, caption = IPAD_SWAP.get(cap_name, (cap_name, caption))
            im = frame(os.path.join(RAW, kind, cap_name + '.png'), W, H, margin, cap, radius, caption, f'NO. {i:04d}')
            im.save(os.path.join(out, f"{i:02d}_{cap_name.split('_', 1)[1]}.png"), optimize=True)
        print(name, len(SHOTS))
    os.makedirs(os.path.join(OUT, 'play'), exist_ok=True)
    feature_graphic().save(os.path.join(OUT, 'play/feature-graphic.png'), optimize=True)
    icon = Image.open(os.path.join(ROOT, 'assets/icons/big-t-master-1024.png')).convert('RGB')
    icon.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, 'play/icon-512.png'), optimize=True)
    print('feature graphic, icon')


if __name__ == '__main__':
    main()
