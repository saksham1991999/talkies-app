#!/usr/bin/env python3
"""Validate the App Store listing text for every storefront language.

Each locale is one file, store/metadata/<asc-locale>.json, with the fields App
Store Connect accepts. Apple's limits differ per field, so a translation cannot
be checked by eye.

Usage:
  python3 store/listing_data.py            table for every locale
  python3 store/listing_data.py --missing  list locales without a file
  python3 store/listing_data.py --json     machine-readable dump

Exit code 1 when any file breaks a limit or holds an em dash. A keyword that
repeats a word from the name or subtitle is printed as a note, not a failure.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tool'))

import locales  # noqa: E402

META = ROOT / 'store' / 'metadata'

LIMITS = {'name': 30, 'subtitle': 30, 'keywords': 100, 'promotionalText': 170, 'description': 4000, 'whatsNew': 4000}
REQUIRED = list(LIMITS)

URLS = {
    'supportUrl': 'https://saksham1991999.github.io/talkies-app/support.html',
    'marketingUrl': 'https://saksham1991999.github.io/talkies-app/',
    'privacyPolicyUrl': 'https://saksham1991999.github.io/talkies-app/privacy.html',
}


def path(code: str) -> Path:
    return META / f'{code}.json'


def load(code: str) -> dict:
    return json.loads(path(code).read_text(encoding='utf-8'))


def problems(code: str, data: dict) -> list[str]:
    out: list[str] = []
    for field in REQUIRED:
        text = data.get(field, '')
        if not isinstance(text, str) or not text.strip():
            out.append(f'{code}.{field}: empty')
            continue
        if len(text) > LIMITS[field]:
            out.append(f'{code}.{field}: {len(text)}/{LIMITS[field]}')
        if '—' in text:
            out.append(f'{code}.{field}: em dash')
    if len(data.get('keywords', '').split(',')) > 100:
        out.append(f'{code}.keywords: more than 100 terms')
    return out


def notes(code: str, data: dict) -> list[str]:
    """Soft findings, printed but not fatal.

    Apple asks that keywords not repeat a word from the name or subtitle, but a
    natural translation cannot always avoid it (Italian "cinema", "diario"), and
    English itself breaks the rule in en-US.json. Reporting it as a failure only
    produced endless rewrites, so it is a note.
    """
    out: list[str] = []
    name = data.get('name', '')
    subtitle = data.get('subtitle', '')
    words = {w.lower().strip('.,:&') for w in (name + ' ' + subtitle).replace(':', ' ').split()}
    repeated = [k for k in data.get('keywords', '').split(',') if k.strip().lower() in words]
    if repeated:
        out.append(f'{code}.keywords: repeats {",".join(repeated)}')
    return out


def main() -> int:
    args = sys.argv[1:]
    codes = locales.store_codes()
    missing = [c for c in codes if not path(c).exists()]
    if '--missing' in args:
        print('\n'.join(missing) or 'every locale has a file')
        return 0
    errors: list[str] = []
    soft: list[str] = []
    rows = []
    for code in codes:
        if not path(code).exists():
            errors.append(f'{code}: missing {path(code).relative_to(ROOT)}')
            continue
        data = load(code)
        errors += problems(code, data)
        soft += notes(code, data)
        rows.append((code, len(data.get('description', '')), len(data.get('name', '')), len(data.get('subtitle', ''))))
    if '--json' in args:
        print(json.dumps({c: load(c) for c in codes if path(c).exists()}, ensure_ascii=False, indent=1))
    else:
        print(f'{"locale":8} {"name":>5} {"sub":>5} {"desc":>6}')
        for code, desc, name, sub in rows:
            print(f'{code:8} {name:5} {sub:5} {desc:6}')
        print(f'\n{len(rows)}/{len(codes)} locales written')
        if errors:
            print(f'{len(errors)} problem(s)')
            for e in errors[:40]:
                print('  ' + e)
        if soft and '--quiet' not in args:
            print(f'{len(soft)} note(s), not failures:')
            for s in soft[:40]:
                print('  ' + s)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
