#!/usr/bin/env python3
"""Draws the Talkies launcher icons (5 variants) and writes Android and iOS assets.

Run: python3 tool/make_icons.py
"""
import json
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INK, RED = (42, 19, 22), (176, 52, 43)
VARIANTS = {  # name: (background, paper, ink, serial)
    'default': ((58, 21, 25), (242, 203, 193), INK, RED),
    'yellow': ((31, 59, 54), (240, 220, 156), INK, RED),
    'green': ((30, 43, 69), (205, 224, 195), INK, RED),
    'blue': ((42, 35, 32), (199, 217, 232), INK, RED),
    'night': ((23, 13, 14), (46, 19, 22), (240, 220, 156), (226, 110, 96)),
}


def ticket(size, bg, paper, ink, serial, scale=1.0, transparent=False):
    S = 1024
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0) if transparent else bg + (255,))
    d = ImageDraw.Draw(im)
    # A kept stub, landscape: cream paper, side notches, two print bars, and the
    # sindoor ring landing over its corner. No text: readable at 29 pt.
    w, h = 640 * scale, 580 * scale
    x0, y0 = (S - w) / 2, (S - h) / 2 - 30 * scale
    x1, y1 = x0 + w, y0 + h
    cy = (y0 + y1) / 2
    d.rounded_rectangle([x0, y0, x1, y1], radius=64 * scale, fill=paper + (255,))
    r = 56 * scale
    cut = (0, 0, 0, 0) if transparent else bg + (255,)
    for cx in (x0, x1):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=cut)
    bx = x0 + 84 * scale
    d.rounded_rectangle(
        [bx, cy - 158 * scale, bx + 330 * scale, cy - 94 * scale],
        radius=28 * scale, fill=ink + (255,))
    d.rounded_rectangle(
        [bx, cy - 60 * scale, bx + 210 * scale, cy - 16 * scale],
        radius=22 * scale, fill=ink + (110,))
    ring_d, ring_w = 300 * scale, 34 * scale
    rx, ry = x1 - 120 * scale, y1 - 70 * scale
    d.ellipse([rx - ring_d / 2, ry - ring_d / 2, rx + ring_d / 2, ry + ring_d / 2],
              outline=serial + (255,), width=int(ring_w))
    return im.resize((size, size), Image.LANCZOS)


def main():
    res = os.path.join(ROOT, 'android/app/src/main/res')
    dens = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    fg_dens = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
    colors = []
    for name, (bg, paper, ink, serial) in VARIANTS.items():
        suffix = '' if name == 'default' else '_' + name
        ticket(192, bg, paper, ink, serial).save(os.path.join(ROOT, f'assets/icons/{name}.png'))
        for dn, px in dens.items():
            os.makedirs(f'{res}/mipmap-{dn}', exist_ok=True)
            ticket(px, bg, paper, ink, serial).save(f'{res}/mipmap-{dn}/ic_launcher{suffix}.png')
            # Adaptive foreground: ticket inside the 66% safe zone on a transparent layer.
            ticket(fg_dens[dn], bg, paper, ink, serial, scale=0.62, transparent=True).save(
                f'{res}/mipmap-{dn}/ic_launcher{suffix}_fg.png')
        os.makedirs(f'{res}/mipmap-anydpi-v26', exist_ok=True)
        with open(f'{res}/mipmap-anydpi-v26/ic_launcher{suffix}.xml', 'w') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                    f'    <background android:drawable="@color/icon_bg{suffix}"/>\n'
                    f'    <foreground android:drawable="@mipmap/ic_launcher{suffix}_fg"/>\n</adaptive-icon>\n')
        colors.append(f'    <color name="icon_bg{suffix}">#{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}</color>')
        # iOS: one universal 1024 icon per set; alternates are named AppIcon-<variant>.
        set_name = 'AppIcon' if name == 'default' else f'AppIcon-{name}'
        iset = os.path.join(ROOT, f'ios/Runner/Assets.xcassets/{set_name}.appiconset')
        os.makedirs(iset, exist_ok=True)
        for old in os.listdir(iset):
            os.remove(os.path.join(iset, old))
        ticket(1024, bg, paper, ink, serial).convert('RGB').save(os.path.join(iset, 'Icon-1024.png'))
        with open(os.path.join(iset, 'Contents.json'), 'w') as f:
            json.dump({'images': [{'filename': 'Icon-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
                       'info': {'author': 'xcode', 'version': 1}}, f, indent=2)
    os.makedirs(f'{res}/values', exist_ok=True)
    with open(f'{res}/values/icon_colors.xml', 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n' + '\n'.join(colors) + '\n</resources>\n')
    print('icons written')


if __name__ == '__main__':
    main()
