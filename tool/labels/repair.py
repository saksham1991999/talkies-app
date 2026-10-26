#!/usr/bin/env python3
"""Fixes the two failure modes an AI translation leaves behind.

1. Collisions: two keys in the same family (language, genre, show slot, country)
   carrying the same value. `show:night` and `show:late` are different slots and
   a picker that prints the same word twice is broken, so the offender is
   re-translated with the siblings already in use as context.
2. Impossible values: a term that is not the word the language actually uses.
   A conservative audit returns those keys with a reason; only the flagged ones
   are re-translated, so a good file cannot be rewritten wholesale.

Usage:
  python3 tool/labels/repair.py               # collisions only
  python3 tool/labels/repair.py --audit       # collisions + the audit pass
  python3 tool/labels/repair.py --audit ar ja ta
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

FAMILIES = ('lang', 'genre', 'show', 'country')

AUDIT = """Below are movie-app labels written in NATIVE (ENGLISH, locale code `CODE`).

Flag ONLY the keys whose value is unusable. Be strict about what counts:
- the value is not a real NATIVE word, or the wrong word
- the value is a name no NATIVE film listing, cinema ticket or dictionary uses for that thing
- the value says something else entirely (a show slot named after a different slot, a language named after another language)
- the value keeps an English word in the wrong script

Do NOT flag: a translation you would have worded differently, a borrowed international word that NATIVE genuinely uses (action, thriller, Netflix, IMAX), a country name that is also the language name, or a value that is merely plain.

Reply with one JSON object of key -> short reason, and {} when nothing is unusable.

LABELS
"""

FIX = """Translate these movie-app terms into NATIVE (ENGLISH). Reply with one JSON object only, the same keys as the input, no commentary.

Every value must be a real, ordinary word a NATIVE film fan sees on a cinema site or ticket. Use only NATIVE characters. No em dash, no trailing punctuation.

Context: these sit in a list, so no two terms in the same family may share a value.
[[SIBLINGS]]
TERMS
"""


def groups(data: dict[str, str]) -> dict[str, dict[str, str]]:
    out = {f: {} for f in FAMILIES}
    for k, v in data.items():
        head = k.split(':')[0]
        if head in out:
            out[head][k] = v
    return out


def collisions(data: dict[str, str]) -> dict[str, str]:
    """key -> why it collides, for the second and later member of a family clash."""
    bad = {}
    for family, entries in groups(data).items():
        seen: dict[str, str] = {}
        for k in sorted(entries):
            v = entries[k]
            if v in seen:
                bad[k] = f'{v} is already used for {seen[v]}'
            else:
                seen[v] = k
    return bad


def fix(code: str, native: str, english: str, want: dict[str, str], data: dict[str, str],
        siblings: bool) -> dict[str, str]:
    """Re-translate [want] (key -> reason) in one call. Returns the keys accepted."""
    if not want:
        return {}
    sample = {k: EN[k] for k in want}
    sib = ''
    if siblings:
        for family, entries in groups(data).items():
            used = sorted({v for k, v in entries.items() if k not in want})
            own = sorted(k for k in want if k.startswith(family + ':'))
            if own and used:
                sib += f'{family}: already used, do not repeat: ' + ', '.join(used) + '\n'
    why = '\n'.join(f'{k}: {v}' for k, v in want.items())
    prompt = (FIX.replace('NATIVE', native).replace('ENGLISH', english)
              .replace('[[SIBLINGS]]', sib))
    prompt = prompt.replace('TERMS', json.dumps(sample, ensure_ascii=False, indent=0) + f'\nWhy these are flagged:\n{why}')

    accepted = {}
    for attempt in range(1, 4):
        reply, err = call(prompt)
        if reply is None:
            print(f'{code}: fix attempt {attempt} failed ({err[:80]})', flush=True)
            threading.Event().wait(10 * attempt)
            continue
        got = parse(reply) or {}
        for k, v in got.items():
            v = (v or '').strip()
            if k not in want or not v or v == data.get(k):
                continue
            if '\u2014' in v or '\u2013' in v or v.endswith(('.', ';')):
                continue
            if scripts(v) - expected(code):
                continue
            accepted[k] = v
        if accepted:
            return accepted
    return accepted


def audit(code: str, native: str, english: str, data: dict[str, str]) -> dict[str, str]:
    """key -> reason for the values a native reader calls unusable."""
    prompt = (AUDIT.replace('NATIVE', native).replace('ENGLISH', english).replace('CODE', code))
    prompt = prompt.replace('LABELS', json.dumps({k: data[k] for k in KEYS if k in data},
                                                 ensure_ascii=False, indent=0))
    for attempt in range(1, 3):
        reply, err = call(prompt)
        if reply is None:
            print(f'{code}: audit attempt {attempt} failed ({err[:80]})', flush=True)
            continue
        got = parse(reply) or {}
        return {k: str(v) for k, v in got.items() if k in data}
    return {}


def repair(code: str, native: str, english: str, do_audit: bool) -> str:
    path = os.path.join(HERE, f'labels_{code}.json')
    if not os.path.exists(path):
        return f'{code}: no file, skipped'
    data = json.load(open(path, encoding='utf-8'))
    notes, changed = [], 0

    if do_audit:
        flagged = audit(code, native, english, data)
        if flagged:
            accepted = fix(code, native, english, flagged, data, siblings=True)
            data.update(accepted)
            changed += len(accepted)
            notes.append(f'audit flagged {len(flagged)}, fixed {len(accepted)}')

    for _ in range(3):
        bad = collisions(data)
        if not bad:
            break
        accepted = fix(code, native, english, bad, data, siblings=True)
        data.update(accepted)
        changed += len(accepted)
        notes.append(f'collisions {len(bad)}, fixed {len(accepted)}')
        if not accepted:
            break

    if changed:
        write(path, data)
    left = collisions(data)
    if left:
        notes.append('still colliding: ' + ', '.join(sorted(left)))
    return f'{code}: ' + ('; '.join(notes) if notes else 'clean')


def main(argv: list[str]) -> int:
    do_audit = '--audit' in argv
    jobs = 4
    if '--jobs' in argv:
        jobs = int(argv[argv.index('--jobs') + 1])
    skip = {'--audit', '--jobs', str(jobs)}
    wanted = [a for a in argv if not a.startswith('-') and a not in skip]
    rows = [r for r in LOCALES if r[0] != 'en' and (not wanted or r[0] in wanted)]
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        futures = [pool.submit(repair, r[0], r[2], r[3], do_audit) for r in rows]
        for f in futures:
            print(f.result(), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
