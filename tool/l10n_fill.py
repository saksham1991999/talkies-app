#!/usr/bin/env python3
"""Write translated values into one locale's ARB.

The file may be partial: keys it omits keep whatever they hold now (English,
for a fresh locale). Every value is checked before it lands: same placeholders
as English, the CLDR plural forms of the language, balanced braces, no em dash.

Usage:
  python3 tool/l10n_fill.py <locale> <translations.json>
  python3 tool/l10n_fill.py <locale> <translations.json> --check

translations.json is {"key": "text"}.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

import locales  # noqa: E402
import merge_arb  # noqa: E402


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    check = '--check' in sys.argv
    if len(args) != 2:
        print(__doc__)
        return 2
    code, path = args
    if code not in locales.BY_CODE:
        print(f'unknown locale {code}; add it to tool/locales.py')
        return 2
    english = json.loads(merge_arb.arb_path('en').read_text(encoding='utf-8'))
    target = merge_arb.arb_path(code)
    if not target.exists():
        print(f'{target.relative_to(ROOT)} is missing; run python3 tool/l10n_new.py first')
        return 1
    values = json.loads(Path(path).read_text(encoding='utf-8'))
    errors: list[str] = []
    for key, text in values.items():
        if key not in english:
            errors.append(f'{code}.{key}: not a key in app_en.arb')
            continue
        if not isinstance(text, str):
            errors.append(f'{code}.{key}: value is {type(text).__name__}, not text')
            continue
        errors += merge_arb.problems_in(text, f'{code}.{key}')
        errors += merge_arb.plural_problems(english[key], text, code, f'{code}.{key}')
        if merge_arb.placeholders(text) != merge_arb.placeholders(english[key]):
            errors.append(f'{code}.{key}: placeholders {sorted(merge_arb.placeholders(text))} '
                          f'differ from English {sorted(merge_arb.placeholders(english[key]))}')
    if errors:
        print('\n'.join(errors[:60]))
        print(f'{len(errors)} problem(s), nothing written')
        return 1
    if check:
        print(f'{len(values)} values ok')
        return 0
    for key, text in values.items():
        merge_arb.set_value(target, key, text)
    print(f'{len(values)} values written to {target.relative_to(ROOT)}')
    merge_arb.gen_l10n()
    return 0


if __name__ == '__main__':
    sys.exit(main())
