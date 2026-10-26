#!/usr/bin/env python3
"""Machine-translate ARB values with agnes-3.0-flash, validating every string.

Every batch is checked before it is kept: the same keys, the same
{placeholders}, the CLDR plural forms of the language, no em dash. A batch that
fails is retried with the specific complaint; nothing invalid is written.

Usage:
  python3 tool/translate_ai.py --all                 every locale that is not done
  python3 tool/translate_ai.py --locales es,pt,ja    just these
  python3 tool/translate_ai.py --locales ar --force  redo a finished locale
  python3 tool/translate_ai.py --all --dry-run       print the first prompt, send nothing

Progress is kept in tool/translations/<code>.json, so a run resumes where it
stopped. The ARB is written when a locale finishes, then `flutter gen-l10n`
runs once at the end.
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

import locales  # noqa: E402
import merge_arb  # noqa: E402

AGNES = Path.home() / '.claude' / 'skills' / 'agnes-ai' / 'scripts' / 'agnes.py'
OUT = ROOT / 'tool' / 'translations'
BATCH = 24
WORKERS = 6
ATTEMPTS = 3
DRY = False

SYSTEM = (
    'You are a professional UI localizer for mobile apps. You translate short interface strings. '
    'You answer with JSON only, no prose, no code fences.'
)

# Printed in the Tanker display face, which carries Latin only. Translating these
# paints empty boxes on the ticket.
SKIP = {'stampWatched', 'fdfs', 'fdfsCount'}

# Values that read exactly like English on purpose now live in locales.NEUTRAL,
# shared with tool/l10n_status.py so the coverage table agrees with the check.

GLOSSARY = (
    'This is Talkies, a diary where every film you watch becomes a paper ticket stub.\n'
    '- Stub: the ticket that records one viewing of a film. Never a placeholder or a schematic.\n'
    '- Film: a movie. Hall: a cinema or single-screen theatre. Show: the screening time slot.\n'
    '- Watchlist: films the user plans to watch. Crew: the friends they watch films with.\n'
    '- FDFS: first day, first show. WATCHED: the stamp on a ticket. Both stay in Latin letters.\n'
)


def prompt_for(code: str, items: dict[str, str]) -> str:
    _c, _s, native, english, _rtl, _indian, plural = locales.BY_CODE[code]
    extra = sorted(set(plural) - {'other'})
    plural_rule = (
        '- Values containing `{count, plural, ...}` are ICU messages. Translate every branch body, keep the syntax. '
        'Keep any `=1` branch. '
        + (f'Also include these branches: {", ".join(extra)}. ' if extra else '')
        + 'Every plural message must contain `other`.'
    )
    return (
        GLOSSARY + '\n'
        f'Translate the VALUES of this JSON from English into {english} ({native}), '
        f'the language of the app UI.\n\n'
        'Rules:\n'
        '- Keep the JSON keys unchanged. Output a JSON object with the same keys, nothing else.\n'
        '- Preserve every {placeholder} exactly, including its letters. Never translate a placeholder name.\n'
        f'{plural_rule}\n'
        '- Keep brand names and format names unchanged: Talkies, IMAX, 4DX, 3D, ScreenX, Dolby Cinema, Netflix, '
        'Prime Video, JioHotstar, SonyLIV, ZEE5.\n'
        '- "Stub" always means the paper cinema ticket that records one viewing. A value that is only "Stubs" '
        'means the list of saved tickets: translate it as the local word for cinema tickets, never as a '
        'schematic, a placeholder, or a piece of code.\n'
        '- Short, plain, warm interface copy. Match the length of the English where you can.\n'
        '- Never use an em dash.\n'
        '- Use the script and spelling of this language. Do not transliterate into Latin letters.\n\n'
        'JSON:\n' + json.dumps(items, ensure_ascii=False)
    )


def ask(prompt: str) -> str:
    if DRY:
        print(prompt)
        raise SystemExit(0)
    run = subprocess.run(
        ['python3', str(AGNES), 'text', prompt, '--system', SYSTEM, '--max-tokens', '4000', '--temperature', '0.2'],
        capture_output=True,
        text=True,
        timeout=240,
    )
    if run.returncode != 0:
        raise RuntimeError(run.stderr.strip()[-400:] or 'agnes failed')
    return run.stdout


def parse(text: str, want: set[str]) -> dict[str, str]:
    start, end = text.find('{'), text.rfind('}')
    if start < 0 or end < start:
        raise ValueError('no JSON object in the reply')
    data = json.loads(text[start:end + 1])
    if not isinstance(data, dict):
        raise ValueError('reply is not a JSON object')
    out = {k: v for k, v in data.items() if k in want}
    if not out:
        raise ValueError('reply has no requested keys')
    return {k: str(v) for k, v in out.items()}


def same_ok(code: str, key: str, english: str) -> bool:
    return locales.neutral(code, key)


def prose_length(english: str) -> int:
    """Letters of translatable text, with the ICU scaffolding taken out.

    `{count, plural, other{films}one{film}}` is ten letters of prose, not fifty:
    measuring the raw string would call French `films` an unfinished draft.
    """
    stripped = re.sub(r'\{\s*\w+\s*[,}]', ' ', english)
    stripped = re.sub(r'=\d+', ' ', re.sub(r'\b(plural|select|other|one|two|few|many|zero)\b', ' ', stripped))
    return len(re.findall(r'[A-Za-z]', stripped))


def is_echo(code: str, key: str, text: str, english: str) -> bool:
    """True when the reply repeated the English source instead of translating it.

    A Latin-script language shares short loanwords with English on purpose
    (`Streaming`, `Format`, `Chat`), so only a long unchanged value there counts
    as a missed translation. Any other script has no excuse for leaving a whole
    sentence in English.
    """
    if text != english or same_ok(code, key, english):
        return False
    return not locales.latin_script(code) or prose_length(english) >= 12


def validate(code: str, english: dict[str, str], got: dict[str, str], want: set[str]) -> list[str]:
    problems: list[str] = []
    for key in sorted(want - set(got)):
        problems.append(f'missing key {key}')
    for key in sorted(set(got) - want):
        problems.append(f'unexpected key {key}')
    for key in sorted(want & set(got)):
        text = got[key]
        problems += merge_arb.problems_in(text, f'{code}.{key}')
        problems += merge_arb.plural_problems(english[key], text, code, f'{code}.{key}')
        if merge_arb.placeholders(text) != merge_arb.placeholders(english[key]):
            problems.append(
                f'{code}.{key}: placeholders {sorted(merge_arb.placeholders(text))} must be '
                f'{sorted(merge_arb.placeholders(english[key]))}'
            )
        if is_echo(code, key, text, english[key]):
            problems.append(f'{code}.{key}: still the English text, translate it')
    return problems


def plural_branches(text: str) -> list[tuple[str, int, int, int]]:
    """`(name, label_start, body_start, body_end)` for every branch of every plural block."""
    out: list[tuple[str, int, int, int]] = []
    for m in re.finditer(r'\{\s*\w+\s*,\s*plural\s*,', text):
        close = merge_arb.block_end(text, m.start())
        if close < 0:
            continue
        j = m.end()
        while j < close:
            label = merge_arb.LABEL.match(text, j)
            body = label.end() - 1 if label else -1
            end = merge_arb.block_end(text, body) if label else -1
            if end < 0 or end > close:
                j += 1
                continue
            out.append((label.group(0).split('{')[0].strip(), j, body + 1, end))
            j = end + 1
    return out


def clone_other(code: str, english: str, text: str) -> str:
    """Last resort for a plural the model refuses to finish.

    Every branch ICU needs gets the `other` body. The wording is not ideal for
    `one`, but the alternative is English copy or a broken message, and ICU
    would otherwise fall back to `other` anyway.
    """
    if 'plural,' not in english:
        return text
    need = locales.plural_required(code) - {'other'}
    # Right to left, so an insertion never moves a label still to be handled.
    for name, label_start, body_start, body_end in reversed(plural_branches(text)):
        if name != 'other':
            continue
        have = {n for n, _l, _s, _e in plural_branches(text)}
        missing = sorted(need - have)
        if not missing:
            continue
        body = text[body_start:body_end]
        text = text[:label_start] + ''.join(f'{c}{{{body}}}' for c in missing) + text[label_start:]
    return text


def plural_prompt(code: str, key: str, english: str, current: str) -> str:
    _c, _s, native, name, _rtl, _indian, plural = locales.BY_CODE[code]
    forms = ', '.join(sorted(plural))
    note = (
        f'Write the message with exactly these branches: {forms}. '
        f'Every branch is required by {name}, even where a branch body repeats another. '
        'The word inside the braces of each branch is the text the user reads.'
    )
    return (
        GLOSSARY + '\n'
        f'One ICU plural message of the Talkies app, in {name} ({native}).\n'
        f'English: {json.dumps({key: english}, ensure_ascii=False)}\n'
        f'A previous attempt: {json.dumps({key: current}, ensure_ascii=False)}\n\n'
        f'{note}\n'
        '- Keep the ICU syntax exactly: {argument, plural, one{...}other{...}}.\n'
        '- Keep every {placeholder} name intact.\n'
        '- Translate the branch bodies, never the branch labels.\n'
        '- Never use an em dash.\n\n'
        'Answer with one JSON object holding just this key.'
    )


def dedupe_plurals(text: str, code: str = '') -> str:
    """Drop a repeated branch, keeping the last one, which is the one ICU uses.

    An exact branch (`=1`) that only repeats a category the language already
    has (`one`) goes too: keeping both makes `flutter gen-l10n` warn that the
    later part overrides the earlier one.
    """
    exact = {'=0': 'zero', '=1': 'one', '=2': 'two'}
    need = locales.plural_required(code) if code in locales.BY_CODE else set()
    for m in reversed(list(re.finditer(r'\{\s*\w+\s*,\s*plural\s*,', text))):
        close = merge_arb.block_end(text, m.start())
        if close < 0:
            continue
        spans = [b for b in plural_branches(text) if m.start() < b[1] < close]
        seen: set[str] = set()
        for name, label_start, _body_start, body_end in reversed(spans):
            redundant = name in seen or exact.get(name, '') in need
            if redundant:
                text = text[:label_start] + text[body_end + 1:]
            else:
                seen.add(name)
    return text


def repair_plural(code: str, key: str, english: str, text: str) -> str:
    """Ask once for the missing CLDR branches, then fall back to cloning `other`."""
    text = dedupe_plurals(text, code)
    if text == english or not merge_arb.plural_problems(english, text, code, f'{code}.{key}'):
        # Copy that is still English needs a translator, not extra branches.
        return text
    for attempt in range(1, ATTEMPTS + 1):
        try:
            got = parse(ask(plural_prompt(code, key, english, text)), {key})
        except Exception:  # noqa: BLE001 - fall through to the clone
            time.sleep(attempt)
            continue
        fixed = got.get(key, '')
        if not merge_arb.problems_in(fixed, key) and not merge_arb.plural_problems(english, fixed, code, key) \
                and merge_arb.placeholders(fixed) == merge_arb.placeholders(english):
            return fixed
    return clone_other(code, english, text)


def translate_one(code: str, english: dict[str, str], todo: list[str]) -> tuple[str, dict[str, str], list[str]]:
    """Translate [todo] for one locale. Returns the accepted values and leftovers."""
    path = OUT / f'{code}.json'
    cached: dict[str, str] = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    # A cached English sentence is not progress: drop it so this run redoes it.
    done: dict[str, str] = {k: v for k, v in cached.items() if not is_echo(code, k, v, english.get(k, ''))}
    pending = [k for k in todo if k not in done]
    failures: list[str] = []

    def save() -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(done, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')

    for i in range(0, len(pending), BATCH):
        chunk = pending[i:i + BATCH]
        remaining = list(chunk)
        for attempt in range(1, ATTEMPTS + 1):
            try:
                reply = ask(prompt_for(code, {k: english[k] for k in remaining}))
                got = parse(reply, set(remaining))
            except Exception as exc:  # noqa: BLE001 - any failure means retry
                if attempt == ATTEMPTS:
                    failures.append(f'{code}: batch at {chunk[0]} failed: {exc}')
                else:
                    time.sleep(2 * attempt)
                continue
            problems = validate(code, english, got, set(remaining))
            if not problems:
                done.update(got)
                save()
                break
            bad = {p.split('.')[-1].split(':')[0].strip() for p in problems if '.' in p}
            if attempt < ATTEMPTS:
                remaining = [k for k in remaining if k in bad or k not in got] or remaining[:1]
                time.sleep(1.5 * attempt)
                continue
            # Last attempt: keep every value that passed and finish the plurals
            # that are only missing branches, so one hard key cannot cost the
            # other twenty-three strings in its batch.
            for key, text in got.items():
                if key in bad:
                    continue
                done[key] = text
            for key in sorted(bad & set(got)):
                fixed = repair_plural(code, key, english[key], got[key])
                if fixed != got[key]:
                    done[key] = fixed
            save()
            failures += [p for p in problems if 'plural missing' not in p]
            break
    return code, done, failures


# The tab label must match the heading it opens. A model that sees the key
# `tabStubs` alone tends to read "stub" as a code stub; the heading it already
# translated is the safer source.
COHERENT = {'tabStubs': 'showStubs'}


def apply_locale(code: str, done: dict[str, str], only: set[str] | None = None) -> int:
    """Write this locale's finished strings into its ARB.

    `done` is the whole resume cache, which is much larger than any one run:
    with `--keys` it holds every string ever translated for the locale. Writing
    all of it back meant a targeted run silently overwrote unrelated keys with
    the cache's older text, undoing hand fixes made to the ARB since. `only`
    limits the write to the keys this run actually worked on, which is what a
    command that names keys should do.
    """
    for alias, source in COHERENT.items():
        if source in done:
            done[alias] = done[source]
    target = merge_arb.arb_path(code)
    written = 0
    for key, text in done.items():
        if only is not None and key not in only:
            continue
        merge_arb.set_value(target, key, text)
        written += 1
    return written


def repair_locale(code: str, en: dict[str, str]) -> int:
    """Give every plural message the CLDR branches its language needs.

    Runs on the ARB, not the prompt, so it also fixes copy an earlier run left
    without `few` or `many` and keeps the result in the resume file.
    """
    target = merge_arb.arb_path(code)
    current = {k: v for k, v in json.loads(target.read_text(encoding='utf-8')).items() if not k.startswith('@')}
    path = OUT / f'{code}.json'
    cached: dict[str, str] = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    fixed = 0
    for key, text in current.items():
        if key in SKIP or key not in en or 'plural,' not in text:
            continue
        tidy = dedupe_plurals(text, code)
        needs = merge_arb.plural_problems(en[key], tidy, code, key)
        if not needs and tidy == text:
            continue
        new = repair_plural(code, key, en[key], text) if needs else tidy
        if new != text:
            merge_arb.set_value(target, key, new)
            cached[key] = new
            fixed += 1
    if fixed:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(cached, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    return fixed


def apply_cached(code: str, en: dict[str, str]) -> list[str]:
    """Validate the resume file and write every value that passes into the ARB.

    The same checks as a live batch, so a value from any translator source has
    to earn its place: placeholders, CLDR branches, no em dash, no English echo.
    """
    path = OUT / f'{code}.json'
    if not path.exists():
        return [f'{code}: no resume file']
    cached: dict[str, str] = json.loads(path.read_text(encoding='utf-8'))
    bad: list[str] = []
    good: dict[str, str] = {}
    for key, text in cached.items():
        if key in SKIP or key not in en:
            continue
        problems = validate(code, en, {key: text}, {key})
        if problems:
            bad += problems
        else:
            good[key] = text
    for alias, source in COHERENT.items():
        if source in good:
            good[alias] = good[source]
    target = merge_arb.arb_path(code)
    for key, text in good.items():
        merge_arb.set_value(target, key, text)
    return bad


def main() -> int:
    global DRY, WORKERS, BATCH
    args = sys.argv[1:]
    DRY = '--dry-run' in args
    if '--workers' in args:
        WORKERS = int(args[args.index('--workers') + 1])
    if '--batch' in args:
        BATCH = int(args[args.index('--batch') + 1])
    force = '--force' in args
    limit = int(args[args.index('--limit') + 1]) if '--limit' in args else 0
    only = set(args[args.index('--keys') + 1].split(',')) if '--keys' in args else None
    english = json.loads(merge_arb.arb_path('en').read_text(encoding='utf-8'))
    en = {k: v for k, v in english.items() if not k.startswith('@')}

    if '--locales' in args:
        codes = args[args.index('--locales') + 1].split(',')
    else:
        codes = [c for c in locales.app_codes() if c != 'en']

    for code in codes:
        if code not in locales.BY_CODE:
            print(f'unknown locale {code}')
            return 2
        if not merge_arb.arb_path(code).exists():
            print(f'{code}: no ARB; run python3 tool/l10n_new.py')
            return 1

    OUT.mkdir(parents=True, exist_ok=True)
    if '--apply-cache' in args:
        total = 0
        for code in codes:
            bad = apply_cached(code, en)
            if bad:
                print(f'{code}: {len(bad)} value(s) rejected')
                for b in bad[:10]:
                    print('  ' + b)
            total += 1
        if total:
            merge_arb.gen_l10n()
        return 0
    if '--repair' in args:
        total = 0
        for code in codes:
            fixed = repair_locale(code, en)
            total += fixed
            if fixed:
                print(f'  {code}: {fixed} plural message(s) completed')
        print(f'repaired {total} message(s)')
        if total:
            merge_arb.gen_l10n()
        return 0

    jobs = []
    for code in codes:
        current = json.loads(merge_arb.arb_path(code).read_text(encoding='utf-8'))
        # A neutral key belongs in English everywhere: never spend a call on it.
        # A value that gained a plural branch stopped equalling English without
        # being translated, so the English detector decides the rest.
        todo = [k for k in en if k not in SKIP and not locales.neutral(code, k)
                and (force or current.get(k) == en[k] or locales.looks_english(code, current.get(k) or ''))]
        if only is not None:
            todo = [k for k in todo if k in only]
        if limit:
            todo = todo[:limit]
        if todo:
            jobs.append((code, todo))
    if not jobs:
        print('nothing to translate')
        return 0
    print(f'{len(jobs)} locales, {sum(len(t) for _, t in jobs)} strings')

    written: dict[str, dict[str, str]] = {}
    failures: list[str] = []
    total = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = [pool.submit(translate_one, code, en, todo) for code, todo in jobs]
        for future in concurrent.futures.as_completed(futures):
            code, done, bad = future.result()
            written[code] = done
            failures += bad
            # Apply as each locale finishes, so a stopped run keeps its work.
            # Only the keys this run was asked for: the rest of `done` is cache.
            count = apply_locale(code, done, only=set(todo)) if not DRY else 0
            total += count
            print(f'  {code}: {count} strings' + (f', {len(bad)} problem(s)' if bad else ''))

    print(f'wrote {total} strings into {len(written)} ARB files')
    if failures:
        print(f'{len(failures)} problem(s) kept as English:')
        for f in failures[:20]:
            print('  ' + f)
    if total:
        merge_arb.gen_l10n()
    return 0


if __name__ == '__main__':
    sys.exit(main())
