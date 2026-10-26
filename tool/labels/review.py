#!/usr/bin/env python3
"""Second pass over tool/labels/labels_<code>.json: a copy-edit, not a retranslate.

Asks a native reader to find only the values that are wrong (a language name in
the wrong form, a bogus word, two keys that came back identical when they mean
different things) and returns corrections for those keys alone. Anything the
review leaves alone is untouched, so a good file cannot regress wholesale.

Usage:
  python3 tool/labels/review.py                 # every locale
  python3 tool/labels/review.py ar ja ta        # just these
  python3 tool/labels/review.py --jobs 6 ta
"""
from __future__ import annotations

import json
import os
import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from translate import EN, KEYS, call, expected, parse, scripts, write  # noqa: E402
from locales import LOCALES  # noqa: E402

PROMPT = """You are a native COPY-EDITOR of NATIVE (ENGLISH, locale code `CODE`).

Below is a list of movie-app labels already translated into NATIVE. Read it the way a NATIVE-speaking film fan would.

Return ONLY the keys that are wrong, as one JSON object of key -> corrected value. Do not return a key that is already right. If every value is right, return {}.

Wrong means:
1. The language name is not the name NATIVE actually uses for that language. `lang:ur`, `lang:hi`, `lang:bn` and the other Indian language names are the ones readers will use most, so check them hardest.
2. The genre, show slot or country is not the word NATIVE film listings and cinema tickets print. A literal translation that no NATIVE reader would recognise is wrong.
3. A value is not a real word in NATIVE, or is the wrong word, or mixes two ideas.
4. Two different keys carry the identical value when they mean different things (for example `show:night` and `show:late` are two different slots, and `genre:mystery` is not `genre:thriller`).
5. A proper name is spelled in a way no NATIVE publication uses.
The same word for a country and its language (`country:DE` and `lang:de`) is normal and NOT a mistake.

Rules: correct values only, spelled the way NATIVE writes them, only NATIVE characters, no em dash, no trailing punctuation, no commentary outside the JSON object.

[[COLLISIONS]]
LABELS
"""


def collisions(data: dict[str, str]) -> str:
    """Same value under keys that must differ: show slots and genre pairs."""
    families = ('show', 'genre')
    seen: dict[str, list[str]] = {}
    for k, v in data.items():
        if k.split(':')[0] in families:
            seen.setdefault(v, []).append(k)
    hits = [f'{v} is used for both {", ".join(sorted(ks))}'
            for v, ks in seen.items() if len(ks) > 1]
    if not hits:
        return 'No two keys share a value.'
    return 'These keys collide and must differ:\n' + '\n'.join(hits)


def review(code: str, native: str, english: str) -> str:
    path = os.path.join(HERE, f'labels_{code}.json')
    if not os.path.exists(path):
        return f'{code}: no file, skipped'
    data = json.load(open(path, encoding='utf-8'))
    listable = {k: data[k] for k in KEYS if k in data}
    prompt = (PROMPT.replace('NATIVE', native).replace('ENGLISH', english)
              .replace('CODE', code).replace('[[COLLISIONS]]', collisions(data)))
    prompt = prompt.replace('LABELS', json.dumps(listable, ensure_ascii=False, indent=0))

    for attempt in range(1, 4):
        reply, err = call(prompt)
        if reply is None:
            print(f'{code}: attempt {attempt} failed ({err[:80]})', flush=True)
            threading.Event().wait(10 * attempt)
            continue
        fixed = parse(reply)
        if fixed is None:
            print(f'{code}: attempt {attempt} was not JSON', flush=True)
            continue
        fixed = {k: v for k, v in fixed.items() if k in listable and isinstance(v, str) and v.strip()}
        keep = {}
        for k, v in fixed.items():
            v = v.strip()
            if '\u2014' in v or '\u2013' in v or v == listable[k]:
                continue
            if scripts(v) - expected(code):
                continue
            keep[k] = v
        if not keep:
            return f'{code}: no corrections'
        data.update(keep)
        write(path, data)
        return f'{code}: corrected {len(keep)}: ' + ', '.join(f'{k}={keep[k]}' for k in sorted(keep)[:6])
    return f'{code}: review failed'


def main(argv: list[str]) -> int:
    jobs = 4
    if '--jobs' in argv:
        jobs = int(argv[argv.index('--jobs') + 1])
    skip = {'--jobs', str(jobs)}
    wanted = [a for a in argv if not a.startswith('-') and a not in skip]
    rows = [r for r in LOCALES if r[0] != 'en' and (not wanted or r[0] in wanted)]
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        futures = [pool.submit(review, r[0], r[2], r[3]) for r in rows]
        for f in futures:
            print(f.result(), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
