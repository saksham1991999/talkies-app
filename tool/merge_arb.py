#!/usr/bin/env python3
"""Add new UI strings to the 8 ARB files. This is the only script that writes them.

Staging (see tool/l10n_staging/README.md):
  tool/l10n_staging/en/<area>.json   {"key": {"text": "...", "placeholders": {"name": "String"}}}   written by UI authors
  tool/l10n_staging/<lang>.json      {"key": "translated text"}   one file per language, written by translators
  tool/l10n_staging/drafted.json     keys whose non-English text is still an English draft (kept by this script)

Usage:
  python3 tool/merge_arb.py --check       validate the staged English strings
  python3 tool/merge_arb.py --draft       add new staged keys to all 8 ARBs, the 7 other languages with the English
                                          text as a draft, then run `flutter gen-l10n`. Safe to run again and from
                                          two shells at once (a lock queues them). A drafted key may change its text.
                                          If a translation already landed for a key whose English draft changed,
                                          the translation is kept and the key stays drafted (--force overwrites).
  python3 tool/merge_arb.py --translate   replace every draft with the text in tool/l10n_staging/<lang>.json,
                                          then run `flutter gen-l10n`

Checks: key style, no clash with a final key, the same {placeholders} in every language, plural forms have `other`,
braces balance, no em dash. ARB files are edited line by line, so diffs stay small.
"""

import fcntl
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get('TALKIES_ROOT', Path(__file__).resolve().parent.parent))
ARB = ROOT / 'lib' / 'l10n'
STAGE = ROOT / 'tool' / 'l10n_staging'
DRAFTED = STAGE / 'drafted.json'
LANGS = ['hi', 'ta', 'te', 'bn', 'mr', 'kn', 'ml']
FORCE = False
KEY = re.compile(r'^[a-z][A-Za-z0-9]*$')
PH_TYPES = {'String', 'int', 'double', 'num'}
BRANCH = re.compile(r'(?:=\d+|zero|one|two|few|many|other)\s*$')


def placeholders(text: str) -> set[str]:
    """Argument names in an ICU message. A one-word plural branch body, like `other{films}`, is text."""
    names = set()
    for m in re.finditer(r'\{\s*(\w+)\s*(\}|,\s*(?:plural|select))', text):
        if m.group(2) == '}' and BRANCH.search(text[: m.start()]):
            continue
        names.add(m.group(1))
    return names


def problems_in(text: str, where: str) -> list[str]:
    out = []
    if '—' in text:
        out.append(f'{where}: em dash')
    if text.count('{') != text.count('}'):
        out.append(f'{where}: unbalanced braces')
    if re.search(r'plural,', text) and 'other{' not in text:
        out.append(f'{where}: plural without other{{}}')
    if not text.strip():
        out.append(f'{where}: empty')
    return out


def arb_path(lang: str) -> Path:
    return ARB / f'app_{lang}.arb'


def key_line(key: str) -> re.Pattern:
    return re.compile(rf'^(\s*{re.escape(json.dumps(key))}:\s*)(.*?)(,?)[ \t]*$', re.M)


def meta_line(key: str) -> re.Pattern:
    return re.compile(rf'^[ \t]*{re.escape(json.dumps("@" + key))}:.*\n', re.M)


def has_key(text: str, key: str) -> bool:
    return bool(key_line(key).search(text))


def load_staged_en() -> dict[str, dict]:
    staged: dict[str, dict] = {}
    for f in sorted((STAGE / 'en').glob('*.json')):
        for k, v in json.loads(f.read_text(encoding='utf-8')).items():
            if k in staged:
                raise SystemExit(f'key {k} staged twice (again in {f.name})')
            staged[k] = v
    return staged


def drafted_keys() -> set[str]:
    return set(json.loads(DRAFTED.read_text(encoding='utf-8'))) if DRAFTED.exists() else set()


def save_drafted(keys: set[str]) -> None:
    DRAFTED.write_text(json.dumps(sorted(keys), indent=1) + '\n', encoding='utf-8')


def check_en(staged: dict[str, dict], existing: str, drafted: set[str]) -> list[str]:
    errors: list[str] = []
    for k, v in staged.items():
        if not KEY.match(k):
            errors.append(f'{k}: key must be lowerCamelCase')
        if has_key(existing, k) and k not in drafted:
            errors.append(f'{k}: already a final key in app_en.arb')
        text = v.get('text', '')
        errors += problems_in(text, f'en.{k}')
        declared = v.get('placeholders', {})
        if set(declared) != placeholders(text):
            errors.append(f'en.{k}: placeholders {sorted(declared)} do not match text {sorted(placeholders(text))}')
        for name, typ in declared.items():
            if typ not in PH_TYPES:
                errors.append(f'en.{k}: placeholder {name} has type {typ}')
    return errors


def meta_dict(v: dict) -> dict | None:
    if not v.get('placeholders'):
        return None
    return {'placeholders': {n: {'type': t} for n, t in v['placeholders'].items()}}


def meta_for(v: dict) -> str | None:
    m = meta_dict(v)
    return None if m is None else json.dumps(m, ensure_ascii=False)


def fix_tail(path: Path) -> None:
    """The last entry carries no trailing comma."""
    body = path.read_text(encoding='utf-8').rstrip()
    assert body.endswith('}'), path
    body = body[:-1].rstrip().rstrip(',')
    path.write_text(body + '\n}\n', encoding='utf-8')


def append_lines(path: Path, lines: list[str]) -> None:
    body = path.read_text(encoding='utf-8').rstrip()
    assert body.endswith('}'), path
    body = body[:-1].rstrip()
    if not body.endswith(','):
        body += ','
    path.write_text(body + '\n' + '\n'.join(lines).rstrip(',') + '\n}\n', encoding='utf-8')


def set_value(path: Path, key: str, value: str) -> None:
    text = path.read_text(encoding='utf-8')
    pat = key_line(key)
    if not pat.search(text):
        raise SystemExit(f'{path.name}: key {key} not found')
    text = pat.sub(lambda m: m.group(1) + json.dumps(value, ensure_ascii=False) + m.group(3), text, count=1)
    path.write_text(text, encoding='utf-8')


def set_meta(path: Path, key: str, meta: str | None) -> None:
    """Replace, insert, or remove the one-line @key block of an English key."""
    text = path.read_text(encoding='utf-8')
    text = meta_line(key).sub('', text, count=1)
    if meta is not None:
        pat = key_line(key)
        m = pat.search(text)
        end = text.index('\n', m.end()) + 1 if '\n' in text[m.end():] else len(text)
        text = text[:end] + f'  {json.dumps("@" + key)}: {meta},\n' + text[end:]
    path.write_text(text, encoding='utf-8')
    fix_tail(path)


def gen_l10n() -> None:
    if os.environ.get('NO_GEN'):
        return
    subprocess.run(['flutter', 'gen-l10n'], cwd=ROOT, check=True)


def locked(fn):
    def run(*a, **kw):
        STAGE.mkdir(parents=True, exist_ok=True)
        with open(STAGE / '.lock', 'w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            return fn(*a, **kw)

    return run


def cmd_check() -> int:
    staged = load_staged_en()
    if not staged:
        print('nothing staged in tool/l10n_staging/en/')
        return 0
    errors = check_en(staged, arb_path('en').read_text(encoding='utf-8'), drafted_keys())
    print('\n'.join(errors[:80]) if errors else f'{len(staged)} staged keys ok')
    return 1 if errors else 0


@locked
def cmd_draft() -> int:
    staged = load_staged_en()
    en_text = arb_path('en').read_text(encoding='utf-8')
    drafted = drafted_keys()
    errors = check_en(staged, en_text, drafted)
    if errors:
        print('\n'.join(errors[:80]) + f'\n{len(errors)} problem(s)')
        return 1
    en_json = json.loads(en_text)
    new = [k for k in staged if not has_key(en_text, k)]
    text_changed = [k for k in staged if k in drafted and k in en_json and en_json[k] != staged[k]['text']]
    meta_changed = [k for k in staged if k in drafted and k in en_json and en_json.get('@' + k) != meta_dict(staged[k])]

    en_lines: list[str] = []
    for k in new:
        en_lines.append(f'  {json.dumps(k)}: {json.dumps(staged[k]["text"], ensure_ascii=False)},')
        if (m := meta_for(staged[k])) is not None:
            en_lines.append(f'  {json.dumps("@" + k)}: {m},')
    if en_lines:
        append_lines(arb_path('en'), en_lines)
        for lang in LANGS:
            append_lines(arb_path(lang), [f'  {json.dumps(k)}: {json.dumps(staged[k]["text"], ensure_ascii=False)},' for k in new])
    for k in text_changed:
        set_value(arb_path('en'), k, staged[k]['text'])
        for lang in LANGS:
            # A drafted key still holds the English text until --translate runs.
            # If the ARB value differs from the old English text, a real
            # translation landed; keep it (or force) instead of clobbering it.
            cur = json.loads(arb_path(lang).read_text(encoding='utf-8')).get(k)
            if cur is not None and cur != en_json[k] and not FORCE:
                print(f'{lang}.{k}: kept translation for changed English draft (use --force to overwrite)')
                continue
            set_value(arb_path(lang), k, staged[k]['text'])
        # The English text moved on, so any kept translation is now stale and
        # must be re-translated; re-mark it as drafted.
        drafted.add(k)
    for k in meta_changed:
        set_meta(arb_path('en'), k, meta_for(staged[k]))
    save_drafted(drafted | set(new))
    print(f'{len(new)} new, {len(set(text_changed) | set(meta_changed))} updated drafts')
    gen_l10n()
    return 0


@locked
def cmd_translate() -> int:
    staged = load_staged_en()
    drafted = drafted_keys()
    if not drafted:
        print('no drafts to translate')
        return 0
    errors: list[str] = []
    translations: dict[str, dict[str, str]] = {}
    for lang in LANGS:
        f = STAGE / f'{lang}.json'
        if not f.exists():
            errors.append(f'missing {f.relative_to(ROOT)}')
            continue
        t = json.loads(f.read_text(encoding='utf-8'))
        translations[lang] = t
        for k in sorted(drafted - set(t)):
            errors.append(f'{lang}: missing {k}')
        for k in sorted(set(t) - drafted):
            errors.append(f'{lang}: extra {k}')
        for k in drafted & set(t):
            errors += problems_in(t[k], f'{lang}.{k}')
            if k in staged and placeholders(t[k]) != placeholders(staged[k]['text']):
                errors.append(f'{lang}.{k}: placeholders differ from English')
    if errors:
        print('\n'.join(errors[:80]) + f'\n{len(errors)} problem(s)')
        return 1
    for lang in LANGS:
        for k in sorted(drafted):
            set_value(arb_path(lang), k, translations[lang][k])
    save_drafted(set())
    print(f'translated {len(drafted)} keys in {len(LANGS)} languages')
    gen_l10n()
    return 0


def main() -> int:
    global FORCE
    modes = {'--check': cmd_check, '--draft': cmd_draft, '--translate': cmd_translate}
    args = sys.argv[1:]
    FORCE = '--force' in args
    args = [a for a in args if a != '--force']
    arg = args[0] if args else ''
    if arg not in modes:
        print(__doc__)
        return 2
    return modes[arg]()


if __name__ == '__main__':
    sys.exit(main())
