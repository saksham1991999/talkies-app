#!/usr/bin/env python3
"""Prove every store caption renders before one screenshot is uploaded.

No device and no App Store Connect: the cards are drawn with the same fonts,
grain and layout that tool/store_frames.py ships, so a caption that would ship
with a box, a clipped word or a collision shows up here first.

For each App Store locale that has captions, for every one of the eight shots:

  1. glyphs   every non-space character is in the chosen font's cmap, so no
              .notdef box can reach a screenshot, and every character inks
              something (combining marks are excused: they ink only with a base)
  2. width    each line fits inside the safe width, serial excluded, after the
              shrink store_frames.py applies
  3. serial   the caption ink never touches the serial ink
  4. lines    consecutive lines do not collide
  5. align    an RTL locale is right-aligned (its ink ends at the right margin,
              the serial sits on the left); an LTR locale starts at the left
  6. deck     every card in a deck is set in the same face at the same size,
              because a deck whose type changes size or face between cards
              looks broken on the store and jumps while swiping

Cards: build/caption_check/<locale>.png is the real first screenshot, and
build/caption_check/<locale>_sheet.png stacks all eight captions of that locale.
Exit code is 1 if any check fails. `--strict` also fails when a storefront with
metadata in store/metadata/ has no caption set of its own and would silently
ship the English captions.
"""
import argparse
import os
import sys
import unicodedata

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import locales  # noqa: E402
import store_frames as sf  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

ROOT = sf.ROOT
CARDS = os.path.join(ROOT, 'build/caption_check')
TARGET = 'appstore/iphone-6.9'
SHOT = os.path.join(ROOT, 'build/store_raw/iphone/01_home.png')
SERIAL = 'NO. 0001'


def marks(ch: str) -> bool:
    """True for a character that legitimately inks nothing on its own."""
    return unicodedata.category(ch) in {'Mn', 'Mc', 'Me', 'Cf'} or ch.isspace()


def line_masks(L) -> list:
    """One ink mask per caption line, on a canvas tall enough for the block."""
    W, h = L['W'], L['y0']
    out = []
    for line, x, y, _ in L['lines']:
        im = Image.new('L', (W, h), 0)
        ImageDraw.Draw(im).text((x, y), line, font=L['font'], fill=255,
                                direction='rtl' if L['rtl'] else None)
        out.append(np.asarray(im) > 0)
    return out


def line_collisions(L) -> list[tuple[int, int]]:
    """(pixels, x) for each pair of consecutive lines whose ink actually touches."""
    masks = line_masks(L)
    hits = []
    for a, b in zip(masks, masks[1:]):
        and_ = a & b
        n = int(and_.sum())
        if n:
            hits.append((n, int(np.nonzero(and_)[1].min())))
    return hits


def check_locale(locale: str, shot) -> dict:
    caps = sf.captions_for(locale)
    W = sf.TARGETS[TARGET][1]
    size = None if locale == 'en' else sf.deck_size(
        locale, TARGET, os.path.join(ROOT, 'build/store_raw'))
    fails = []
    font_name = ''
    sizes = set()
    fonts = set()
    for i, caption in enumerate(caps, 1):
        text = sf.upper_case(caption, locale)
        L = sf.layout_for(shot, TARGET, caption, f'NO. {i:04d}', locale=locale, size=size)
        size = size or L['cap_size']
        script = sf.cjk_script(locale)
        path, index = sf.font_source(text, L['cap_size'], script)
        font_name = f'{os.path.basename(path)}#{index}'
        sizes.add(L['cap_size'])
        fonts.add(font_name)

        # 1. glyphs: cmap first, then ink.
        missing = sf.missing_glyphs(path, index, text)
        if missing:
            fails.append(f'#{i} {font_name} has no glyph for {missing!r}')
        for ch in sorted({c for c in text if not c.isspace()}):
            if marks(ch):
                continue
            if L['font'].getmask(ch).getbbox() is None:
                fails.append(f'#{i} {ch!r} renders empty in {font_name}')

        # 2. width: the same safe width the layout aims at.
        s_w = ImageDraw.Draw(Image.new('RGB', (1, 1))).textbbox(
            (0, 0), f'NO. {i:04d}', font=L['serial'][4])[2]
        safe = L['sw'] - s_w - int(W * 0.06)
        for line, x, y, b in L['lines']:
            if b[2] - b[0] > safe + 2:
                fails.append(f'#{i} line {line[:18]!r} is {b[2] - b[0]}px wide, safe width {safe}')

        boxes, serial = sf.caption_ink_box(L)
        # 3. serial: caption ink and serial ink must not touch.
        cb = (min(b[0] for b in boxes), min(b[1] for b in boxes),
              max(b[2] for b in boxes), max(b[3] for b in boxes))
        if not (cb[2] < serial[0] or serial[2] < cb[0] or cb[3] < serial[1] or serial[3] < cb[1]):
            fails.append(f'#{i} caption ink {cb} overlaps serial ink {serial}')

        # 4. lines: no colliding ink between consecutive lines. Two lines can
        # share a vertical band (a comma tail, an accent) as long as no ink
        # actually touches, so the test is a mask intersection, not a bbox one.
        collide = line_collisions(L)
        for j, (n, where) in enumerate(collide):
            fails.append(f'#{i} lines {j + 1} and {j + 2} overlap on {n} pixels near x={where}')

        # 5. alignment.
        left = min(b[0] for b in boxes)
        right = max(b[2] for b in boxes)
        slack = int(W * 0.02)  # a negative side bearing may overhang by a hair
        if L['rtl']:
            if abs(right - (L['x0'] + L['sw'])) > 3:
                fails.append(f'#{i} RTL caption ends at x={right}, right margin is {L["x0"] + L["sw"]}')
            if abs(serial[0] - L['x0']) > 3:
                fails.append(f'#{i} RTL serial starts at x={serial[0]}, left margin is {L["x0"]}')
        else:
            if left < L['x0'] - slack or left > L['x0'] + int(W * 0.08):
                fails.append(f'#{i} LTR caption ink starts at x={left}, margin is {L["x0"]}')
            if serial[2] < L['x0'] + L['sw'] / 2:
                fails.append(f'#{i} LTR serial at x={serial[0]} is not on the right')

    if len(sizes) > 1:  # the deck must not change type size between shots
        fails.append(f'caption size varies across the deck: {sorted(sizes)}')
    if len(fonts) > 1:  # nor the face: all eight cards are one deck
        fails.append(f'caption face varies across the deck: {sorted(fonts)}')
    return {'locale': locale, 'font': font_name, 'fonts': sorted(fonts),
            'rtl': sf.rtl_locale(locale),
            'size': max(sizes), 'fails': fails, 'requested': sf.TARGETS[TARGET][4]}


def band(shot, locale: str, caption: str, serial: str, size: int) -> Image.Image:
    """The caption area of a framed shot, without resizing the screen under it."""
    L = sf.layout_for(shot, TARGET, caption, serial, locale=locale, size=size)
    W = L['W']
    h = L['y0']
    im = sf.grain((W, h), sf.GREEN)
    d = ImageDraw.Draw(im)
    for line, x, y, _ in L['lines']:
        d.text((x, y), line, font=L['font'], fill=sf.PAPER, direction='rtl' if L['rtl'] else None)
    text, sx, sy, _, small = L['serial']
    d.text((sx, sy), text, font=small, fill=sf.SERIAL)
    return im


def sheet(shot, locale: str, size: int) -> Image.Image:
    caps = sf.captions_for(locale)
    bands = [band(shot, locale, c, f'NO. {i:04d}', size).resize((660, 330), Image.LANCZOS)
             for i, c in enumerate(caps, 1)]
    out = Image.new('RGB', (660, 330 * len(bands)), sf.GREEN)
    for i, b in enumerate(bands):
        out.paste(b, (0, i * 330))
    return out


def main(argv=None):
    p = argparse.ArgumentParser(description='Prove every store caption renders.')
    p.add_argument('--strict', action='store_true',
                   help='also fail when a storefront that has metadata in store/metadata/ '
                        'has no caption set of its own and no declared alias, which means it '
                        'would silently ship the English captions')
    args = p.parse_args(argv)
    os.makedirs(CARDS, exist_ok=True)
    shot = sf.open_shot(SHOT)

    # Every language the app ships must have a store locale with real captions:
    # the whole point is that no storefront inherits the English set by accident.
    covered = {sf.app_code(loc) for loc in list(sf.CAPTIONS) + list(sf.CAPTION_ALIAS)}
    uncovered = [row[3] for row in locales.LOCALES if row[0] not in covered]
    rows, failures = [], 0
    for locale in sf.CAPTIONS:
        r = check_locale(locale, shot)
        rows.append(r)
        failures += len(r['fails'])
        sf.frame(SHOT, TARGET, sf.captions_for(locale)[0], SERIAL, locale=locale,
                 size=r['size']).save(os.path.join(CARDS, f'{locale}.png'), optimize=True)
        sheet(shot, locale, r['size']).save(os.path.join(CARDS, f'{locale}_sheet.png'), optimize=True)

    print(f'{"locale":8} {"font":30} {"size":>8} {"rtl":4} checks')
    for r in rows:
        size = str(r['requested']) if r['size'] == r['requested'] else f'{r["requested"]}->{r["size"]}'
        state = 'ok' if not r['fails'] else f'{len(r["fails"])} FAIL'
        print(f'{r["locale"]:8} {r["font"]:30} {size:>8} {"rtl" if r["rtl"] else "":4} {state}')
        for f in r['fails']:
            print('   ', f)
    if uncovered:
        print('\napp language with no store captions:', ', '.join(uncovered))
        failures += len(uncovered)

    # A storefront whose code is in store/metadata/ is one App Store Connect will
    # receive, so it needs a caption set or a declared alias.
    storefronts = locales.store_codes()
    if args.strict:
        meta = {f[:-5] for f in os.listdir(os.path.join(ROOT, 'store/metadata'))
                if f.endswith('.json')}
        silent = sorted(s for s in storefronts
                        if s in meta and s not in sf.CAPTIONS and s not in sf.CAPTION_ALIAS)
        for s in silent:
            print(f'\n{s}: has metadata, no caption set and no alias: it would ship the English deck')
        failures += len(silent)

    shared = {}
    for s in storefronts:
        shared.setdefault(s if s in sf.CAPTIONS else sf.CAPTION_ALIAS.get(s), []).append(s)
    print(f'\n{len(rows)} caption sets, {len(storefronts)} storefronts, '
          f'{len(rows) * 8} captions, {failures} failures')
    for key, codes in shared.items():
        if len(codes) > 1:
            print(f'  {key} set is shared by {", ".join(codes)}')
    print('cards in', os.path.relpath(CARDS, ROOT))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
