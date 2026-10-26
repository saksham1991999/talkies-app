#!/usr/bin/env python3
"""Check the "What's New" text written for one app version, before it ships.

A release note is written once in English and then translated into every
storefront language, so the failure modes are structural, not stylistic: one
locale never got written, a translator left the English word for "stub" in a
Hindi sentence, or the file describes 1.1.0 while pubspec says 1.1.1.

store/whatsnew/<version>.json maps an App Store locale to one string. It is
kept apart from store/metadata/ on purpose: store/metadata/ is what is live in
App Store Connect, and rewriting it would push the next version's notes onto
the version that is currently in review.

Usage:
  python3 tool/whatsnew_check.py               check the newest / the version in pubspec.yaml
  python3 tool/whatsnew_check.py 1.1.1         check one version
  python3 tool/whatsnew_check.py --json        machine-readable dump

Exit code 1 on a structural problem. An English word left in a translation is
printed as a note: a few languages borrow one legitimately, so a person reads it.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tool'))

import locales  # noqa: E402

WHATSNEW = ROOT / 'store' / 'whatsnew'
PUBSPEC = ROOT / 'pubspec.yaml'

APPLE_LIMIT = 4000
SHORT_ENOUGH = 600

# English nouns a translator must not leave inside a translated sentence. These
# are the words this app's copy is made of, so a leak is easy to spot.
LEAKS = re.compile(r'\b(tickets?|stubs?|diar(?:y|ies)|accounts?|movies?|members?)\b', re.IGNORECASE)

ENGLISH = {'en-AU', 'en-CA', 'en-GB', 'en-US'}

# Languages that say the same thing in far fewer characters. Comparing their
# length to the English counts characters, not content, so the ratio says
# nothing and only produces noise.
DENSE = {'zh-Hans', 'zh-Hant', 'ja', 'ko'}


def pubspec_version() -> str:
    for line in PUBSPEC.read_text(encoding='utf-8').splitlines():
        if line.startswith('version:'):
            return line.split(':', 1)[1].strip().split('+')[0]
    return ''


def path(version: str) -> Path:
    return WHATSNEW / f'{version}.json'


def load(version: str) -> dict:
    return json.loads(path(version).read_text(encoding='utf-8'))


def problems(version: str, data: dict) -> list[str]:
    out: list[str] = []
    wanted = set(locales.store_codes())
    got = set(data)
    for code in sorted(wanted - got):
        out.append(f'{code}: no note')
    for code in sorted(got - wanted):
        out.append(f'{code}: not an App Store locale')
    for code, text in sorted(data.items()):
        if not isinstance(text, str):
            out.append(f'{code}: {type(text).__name__}, not a string')
            continue
        if not text.strip():
            out.append(f'{code}: empty')
            continue
        if text != text.strip():
            out.append(f'{code}: leading or trailing whitespace')
        if len(text) > APPLE_LIMIT:
            out.append(f'{code}: {len(text)}/{APPLE_LIMIT}')
        if '\u2014' in text or '\u2013' in text:
            out.append(f'{code}: dash, use a comma or a full stop')
        if '  ' in text:
            out.append(f'{code}: double space')
        if re.search(r'\{[^}]*\}|TODO|FIXME|XXX', text):
            out.append(f'{code}: placeholder left in the text')
    return out


def established(code: str) -> set[str]:
    """Latin words the live listing for this locale already uses.

    Dutch says "account" because Dutch has no other word for it. If the shipping
    listing in that language already uses the word, it is that language's word,
    not English left behind, so the checker stays quiet about it.
    """
    meta = ROOT / 'store' / 'metadata' / f'{code}.json'
    if not meta.exists():
        return set()
    try:
        data = json.loads(meta.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return set()
    words: set[str] = set()
    for field in data.values():
        if isinstance(field, str):
            words |= {w.lower() for w in re.findall(r'[A-Za-z]+', field)}
    return words


def notes(version: str, data: dict) -> list[str]:
    """Soft findings. A person decides; the checker only points."""
    out: list[str] = []
    for code, text in sorted(data.items()):
        if not isinstance(text, str):
            continue
        leak = LEAKS.search(text)
        if code not in ENGLISH and leak and leak.group(0).lower() not in established(code):
            out.append(f'{code}: English word {leak.group(0)!r} left in the text')
        if len(text) > SHORT_ENOUGH:
            out.append(f'{code}: {len(text)} characters, long for a release note')
        if '\n' in text and '\n\n' not in text:
            out.append(f'{code}: line break without a blank line, Apple joins the lines')
    english = {c: len(data[c]) for c in ENGLISH if isinstance(data.get(c), str)}
    if english:
        floor = min(english.values())
        for code, text in sorted(data.items()):
            if code in ENGLISH or code in DENSE or not isinstance(text, str):
                continue
            if len(text) < floor * 0.5:
                out.append(f'{code}: {len(text)} characters, half the English length, a fact may be missing')
    return out


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    version = args[0] if args else pubspec_version()
    if not version:
        print('cannot read version: from pubspec.yaml')
        return 1
    if not path(version).exists():
        print(f'no {path(version).relative_to(ROOT)}, write one note per App Store locale')
        return 1
    data = load(version)

    if '--json' in sys.argv:
        print(json.dumps(data, ensure_ascii=False, indent=1))
        return 0

    errors = problems(version, data)
    soft = notes(version, data)
    declared = pubspec_version()
    if declared and declared != version:
        errors.append(f'pubspec.yaml says {declared}, this file is {version}')

    print(f'{len(data)}/{len(locales.store_codes())} locales, {version} ' f'(pubspec {declared or "unknown"})')
    if errors:
        print(f'{len(errors)} problem(s)')
        for e in errors[:40]:
            print('  ' + e)
    if soft:
        print(f'{len(soft)} note(s), not failures:')
        for s in soft[:40]:
            print('  ' + s)
    if not errors and not soft:
        print('clean')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
