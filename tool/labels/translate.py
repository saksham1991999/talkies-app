#!/usr/bin/env python3
"""Writes tool/labels/labels_<code>.json for the app's locales.

`labels_en.json` is the key registry and the source text. Every other file
carries the same keys, translated. One agnes text call per language, then a
repair call for whatever came back empty, in the wrong script, or missing, so a
partial or half-transliterated answer never lands on disk.

Usage:
  python3 tool/labels/translate.py                 # every locale still missing
  python3 tool/labels/translate.py ja ta ar        # just these
  python3 tool/labels/translate.py --force ja      # redo an existing file
  python3 tool/labels/translate.py --jobs 4        # parallel calls (default 4)
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
import unicodedata
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tool'))
from locales import LOCALES, LATIN  # noqa: E402

AGNES = os.path.expanduser('~/.claude/skills/agnes-ai/scripts/agnes.py')
EN_PATH = os.path.join(HERE, 'labels_en.json')
EN = json.load(open(EN_PATH, encoding='utf-8'))
KEYS = sorted(EN)

# Extra context for the words whose English label is a shorthand.
GLOSS = {
    'genre:legal': 'Courtroom (a legal drama, films set in a court of law)',
    'genre:biography': "Biopic (a film based on a real person's life)",
    'genre:historical': 'Historical (a period film, set in the past)',
    'genre:coming_of_age': 'Coming of age (a teenager growing up)',
    'genre:scifi': 'Sci-fi (science fiction)',
    'show:matinee': 'Matinee (the afternoon show)',
    'show:late': 'Late night (the last show, after midnight)',
    'country:AE': 'United Arab Emirates',
    'country:GB': 'United Kingdom',
    'country:US': 'United States of America',
    'country:KR': 'South Korea',
    'country:HK': 'Hong Kong',
    'country:TW': 'Taiwan',
}

SYSTEM = (
    'You are a professional localiser for an Indian movie ticket app. '
    'You translate vocabulary lists into a target language and return JSON only.'
)

PROMPT = """Translate this movie-app vocabulary into NATIVE (ENGLISH, locale code `CODE`).

The app is a movie ticket diary for Indian filmgoers. These strings are chips, filter rows, ticket lines and picker rows. The reader sees the app entirely in ENGLISH; every value below must read as ENGLISH to them.

Input, English source: a JSON object of [[N]] keys.
SOURCE
GLOSS
Rules:
1. Reply with one JSON object, nothing else, no markdown fence, no commentary.
2. Same [[N]] keys, exactly as spelled, no additions, no omissions.
3. Values for `lang:*` are the name of that language written in NATIVE, the way a dictionary or a film catalogue writes it (Japanese writes Hindi as ヒンディー語). Use the conventional name, never a description.
4. Values for `genre:*` are the ordinary noun film critics use for that genre in NATIVE. In a Latin script write it lowercase unless the language capitalises nouns (German does).
5. Values for `show:*` are the show time slot printed on an Indian cinema ticket. Translate the meaning; keep a borrowed "show" word only where ENGLISH genuinely uses it. `show:late` is the show after midnight and must not repeat `show:night`.
6. Values for `country:*` are the ordinary country name in NATIVE.
7. Never leave an English word in a non-Latin script, and never transliterate an English word into the target script where ENGLISH has its own word. Proper names with no local form keep their usual local spelling.
8. Write only characters of the NATIVE writing system. Never mix in a second script. No em dash. No trailing punctuation. No explanations.
"""

# The writing system each locale must come back in. A value that drifts into
# another one (Arabic with a Cyrillic letter, Japanese in Latin letters) is a
# broken label, not a translation.
SCRIPTS = {
    'Arabic': [(0x0600, 0x06FF), (0x0750, 0x077F), (0x08A0, 0x08FF), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF)],
    'Hebrew': [(0x0590, 0x05FF)],
    'Cyrillic': [(0x0400, 0x04FF), (0x0500, 0x052F)],
    'Greek': [(0x0370, 0x03FF), (0x1F00, 0x1FFF)],
    'Devanagari': [(0x0900, 0x097F)],
    'Bengali': [(0x0980, 0x09FF)],
    'Gurmukhi': [(0x0A00, 0x0A7F)],
    'Gujarati': [(0x0A80, 0x0AFF)],
    'Odia': [(0x0B00, 0x0B7F)],
    'Tamil': [(0x0B80, 0x0BFF)],
    'Telugu': [(0x0C00, 0x0C7F)],
    'Kannada': [(0x0C80, 0x0CFF)],
    'Malayalam': [(0x0D00, 0x0D7F)],
    'Sinhala': [(0x0D80, 0x0DFF)],
    'Thai': [(0x0E00, 0x0E7F)],
    'Han': [(0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF)],
    'Kana': [(0x3040, 0x30FF)],
    'Hangul': [(0x1100, 0x11FF), (0x3130, 0x318F), (0xAC00, 0xD7AF)],
}
LATIN_RANGES = [(0x0041, 0x005A), (0x0061, 0x007A), (0x00C0, 0x024F), (0x1E00, 0x1EFF)]

EXPECTED = {
    'ar': {'Arabic'}, 'ur': {'Arabic'}, 'he': {'Hebrew'},
    'hi': {'Devanagari'}, 'mr': {'Devanagari'},
    'bn': {'Bengali'}, 'gu': {'Gujarati'}, 'or': {'Odia'}, 'pa': {'Gurmukhi'},
    'ta': {'Tamil'}, 'te': {'Telugu'}, 'kn': {'Kannada'}, 'ml': {'Malayalam'},
    'th': {'Thai'}, 'ja': {'Han', 'Kana'}, 'zh': {'Han'}, 'zh_Hant': {'Han'},
    'ko': {'Hangul'}, 'ru': {'Cyrillic'}, 'uk': {'Cyrillic'}, 'el': {'Greek'},
    'fa': {'Arabic'},
}


def expected(code: str) -> set[str]:
    """The writing systems a value for [code] must use."""
    return EXPECTED.get(code, {'Latin'})


def scripts(text: str) -> set[str]:
    """The writing systems a value actually uses (combining marks ignored)."""
    found = set()
    for ch in text:
        cp = ord(ch)
        if ch.isdigit() or ch.isspace() or unicodedata.category(ch).startswith('M'):
            continue
        if any(a <= cp <= b for a, b in LATIN_RANGES):
            found.add('Latin')
            continue
        for name, ranges in SCRIPTS.items():
            if any(a <= cp <= b for a, b in ranges):
                found.add(name)
                break
    return found


def write(path: str, data: dict[str, str]) -> None:
    body = json.dumps(dict(sorted(data.items())), ensure_ascii=False, indent=2)
    open(path, 'w', encoding='utf-8').write(body + '\n')


def parse(text: str) -> dict[str, str] | None:
    """The JSON object in the reply, or None when the model wrapped or broke it."""
    text = re.sub(r'^```(?:json)?|```$', '', text.strip(), flags=re.MULTILINE).strip()
    i, j = text.find('{'), text.rfind('}')
    if i < 0 or j < i:
        return None
    try:
        data = json.loads(text[i:j + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    return {str(k): str(v).strip() for k, v in data.items()}


def call(prompt: str) -> tuple[str | None, str]:
    """One agnes text call. Returns (reply, error)."""
    try:
        p = subprocess.run(
            [sys.executable, AGNES, 'text', '-', '--system', SYSTEM,
             '--max-tokens', '12000', '--temperature', '0.2'],
            input=prompt, capture_output=True, text=True, timeout=420,
        )
    except subprocess.TimeoutExpired:
        return None, 'timeout'
    if p.returncode != 0:
        return None, (p.stderr or p.stdout).strip()[-400:] or f'exit {p.returncode}'
    return p.stdout, ''


def bad_values(code: str, data: dict[str, str]) -> dict[str, str]:
    """key -> why it cannot ship. Structural only; taste is a human read."""
    want = expected(code)
    out = {}
    for k, v in data.items():
        if not v.strip():
            out[k] = 'empty'
        elif '\u2014' in v or '\u2013' in v:
            out[k] = 'contains a dash'
        elif v.endswith(('.', ';')):
            out[k] = 'trailing punctuation'
        else:
            got = scripts(v)
            stray = got - want
            if stray:
                out[k] = 'mixed script (found ' + ', '.join(sorted(stray)) + ')'
            elif not (got & want):
                out[k] = 'not written in ' + ', '.join(sorted(want))
    return out


def echoed(code: str, data: dict[str, str]) -> list[str]:
    """Latin-script keys that came back byte-identical to the English source.

    Some are correct (Spanish `drama` is `drama`) so this is a warning to read,
    not a failure. A whole file echoing is the failure mode worth catching.
    """
    if code not in LATIN:
        return []
    return [k for k, v in data.items() if v == EN[k]]


def translate(code: str, native: str, english: str, force: bool) -> str:
    path = os.path.join(HERE, f'labels_{code}.json')
    if code == 'en':
        write(path, EN)
        return f'{code}: wrote the English reference'
    if os.path.exists(path) and not force:
        have = json.load(open(path, encoding='utf-8'))
        if sorted(have) == KEYS and not bad_values(code, have):
            echo = echoed(code, have)
            note = f' ({len(echo)} values match English)' if echo else ''
            return f'{code}: already complete, skipped{note}'

    source = json.dumps(EN, ensure_ascii=False, indent=0)
    gloss = '\n'.join(f'Note: `{k}` means {v}.' for k, v in GLOSS.items())
    prompt = (PROMPT.replace('NATIVE', native).replace('ENGLISH', english)
              .replace('CODE', code).replace('SOURCE', source).replace('GLOSS', gloss))
    prompt = re.sub(r'\[\[N\]\]', str(len(EN)), prompt)

    data: dict[str, str] = {}
    for attempt in range(1, 6):
        reply, err = call(prompt)
        if reply is None:
            rate = any(w in err.lower() for w in ('429', 'rate', 'quota', 'limit'))
            wait = 30 * attempt if rate else 5 * attempt
            print(f'{code}: attempt {attempt} failed ({err[:80]}), waiting {wait}s', flush=True)
            threading.Event().wait(wait)
            continue
        got = parse(reply)
        if got is None:
            print(f'{code}: attempt {attempt} was not JSON, retrying', flush=True)
            continue
        data.update({k: v for k, v in got.items() if k in EN})
        missing = [k for k in KEYS if k not in data]
        bad = bad_values(code, data)
        if not missing and not bad:
            break
        print(f'{code}: attempt {attempt}: {len(missing)} missing, {len(bad)} bad', flush=True)
        rest = {k: EN[k] for k in missing + [k for k in bad if k not in missing]}
        why = '\n'.join(f'{k}: {v}' for k, v in bad.items())
        prompt = (
            f'Translate these {len(rest)} terms of a movie app into {native} ({english}).\n'
            'Reply with one JSON object only and the same keys as the input.\n'
            f'Use only {", ".join(sorted(expected(code)))} characters.\n'
            + (f'Fix these problems:\n{why}\n' if why else '')
            + json.dumps(rest, ensure_ascii=False, indent=0)
        )

    bad = bad_values(code, data)
    write(path, {k: data[k] for k in KEYS if k in data})
    dups = [k for k in data if list(data.values()).count(data[k]) > 1]
    extra = f', {len(dups)} repeated values ({", ".join(sorted(dups)[:4])})' if dups else ''
    if bad:
        print(f'{code}: unfinished keys: ' + ', '.join(f'{k} ({v})' for k, v in bad.items()), flush=True)
        return f'{code}: wrote {len(data)} keys, {len(bad)} to fix{extra}'
    return f'{code}: wrote {len(data)} keys{extra}'


def main(argv: list[str]) -> int:
    force = '--force' in argv
    jobs = 4
    if '--jobs' in argv:
        jobs = int(argv[argv.index('--jobs') + 1])
    skip = {'--force', '--jobs', str(jobs)}
    wanted = [a for a in argv if not a.startswith('-') and a not in skip]

    rows = [r for r in LOCALES if not wanted or r[0] in wanted]
    if wanted:
        unknown = set(wanted) - {r[0] for r in rows}
        if unknown:
            print('unknown locale codes:', ', '.join(sorted(unknown)), file=sys.stderr)
            return 2

    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        futures = [pool.submit(translate, r[0], r[2], r[3], force) for r in rows]
        for f in futures:
            print(f.result(), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
