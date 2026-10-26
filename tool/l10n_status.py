#!/usr/bin/env python3
"""Report translation coverage and generate lib/l10n/locale_meta.dart.

Usage:
  python3 tool/l10n_status.py           print the table and rewrite locale_meta.dart
  python3 tool/l10n_status.py --check   exit 1 when a locale is missing keys, has a
                                        placeholder mismatch, or lacks a CLDR plural form

A locale counts as reviewed only when its code is listed in
tool/l10n/reviewed.json. Machine drafts ship, but the app marks them and the
App Store push refuses them unless told otherwise.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

import locales  # noqa: E402
import merge_arb  # noqa: E402

REVIEWED = ROOT / 'tool' / 'l10n' / 'reviewed.json'
OUT = ROOT / 'lib' / 'l10n' / 'locale_meta.dart'

# Values that are legitimately the same in every language: product names,
# formats, streaming services. A locale may keep this many and still count as
# translated. Hindi, the most complete existing file, keeps 8.
READY_ALLOWANCE = 30


def reviewed() -> set[str]:
    if not REVIEWED.exists():
        return {'en'}
    return set(json.loads(REVIEWED.read_text(encoding='utf-8')).get('reviewed', [])) | {'en'}


def strings(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding='utf-8'))
    return {k: v for k, v in data.items() if not k.startswith('@') and isinstance(v, str)}


def bcp47(code: str) -> str:
    """`pt_BR` becomes `pt-BR`; `zh_Hant` becomes `zh-Hant`."""
    parts = code.split('_')
    return parts[0] if len(parts) == 1 else f'{parts[0]}-{parts[1]}'


def platform_problems() -> list[str]:
    """Info.plist and locales_config.xml must list every language.

    The two files speak the platform tag, not the ARB code: `pt` is listed as
    `pt-BR` and `zh` as `zh-Hans`. Both spellings name the same language, so a
    tag is accepted when it is an app code or a store code of one.
    """
    def covered(have: set[str]) -> set[str]:
        out = {c for c in locales.app_codes() if c in have}
        return out | {locales.STORE_TO_APP[t] for t in have if t in locales.STORE_TO_APP}

    want = set(locales.app_codes())
    out: list[str] = []
    plist = ROOT / 'ios' / 'Runner' / 'Info.plist'
    text = plist.read_text(encoding='utf-8')
    block = re.search(r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>', text, re.S)
    have = set(re.findall(r'<string>([^<]+)</string>', block.group(1))) if block else set()
    if covered(have) != want:
        out.append(f'Info.plist CFBundleLocalizations differs: missing {sorted(want - covered(have))}')
    android = ROOT / 'android' / 'app' / 'src' / 'main' / 'res' / 'xml' / 'locales_config.xml'
    have = set(re.findall(r'android:name="([^"]+)"', android.read_text(encoding='utf-8'))) if android.exists() else set()
    if covered(have) != want:
        out.append(f'locales_config.xml differs: missing {sorted(want - covered(have))}')
    return out


def main() -> int:
    check = '--check' in sys.argv
    english = strings(merge_arb.arb_path('en'))
    known = reviewed()
    rows = []
    errors: list[str] = []

    for code, store, native, name, rtl, indian, _plural in locales.LOCALES:
        path = merge_arb.arb_path(code)
        if not path.exists():
            errors.append(f'{code}: missing {path.relative_to(ROOT)}')
            rows.append((code, name, 0, len(english), 0, False, False))
            continue
        text = strings(path)
        missing = sorted(set(english) - set(text))
        # `Talkies`, `H12`, `250`, the sample film titles: identical on purpose.
        # Counting those as untranslated would ask a translator to rename the app.
        # A value that kept a plural branch and so no longer equals English still
        # counts when what is left is an English sentence in another script.
        same = sum(1 for k in english
                   if not locales.neutral(code, k)
                   and (text.get(k) == english[k] or locales.looks_english(code, text.get(k) or '')))
        for key in missing:
            errors.append(f'{code}: missing key {key}')
        for key in sorted(set(english) & set(text)):
            if merge_arb.placeholders(english[key]) != merge_arb.placeholders(text[key]):
                errors.append(f'{code}.{key}: placeholders differ from English')
            errors += merge_arb.plural_problems(english[key], text[key], code, f'{code}.{key}')
        ready = not missing and same <= READY_ALLOWANCE
        rows.append((code, name, len(text), len(english), same, code in known, ready))

    write_dart(known, {r[0]: r[6] for r in rows})
    width = max(len(r[1]) for r in rows)
    print(f'{"locale":8} {"language":{width}}  keys   still-en  reviewed  ready')
    for code, name, have, want, same, ok, ready in rows:
        print(f'{code:8} {name:{width}}  {have:4}/{want:<4} {same:8}   {"yes" if ok else "no":8}  '
              f'{"yes" if ready else "no"}')
    ready_count = sum(1 for r in rows if r[6])
    print(f'\n{len(rows)} app locales, {ready_count} translated, {sum(1 for r in rows if r[5])} reviewed, '
          f'{len(locales.store_codes())} store locales')
    errors += platform_problems()
    if errors:
        print(f'{len(errors)} problem(s)')
        for e in errors[:40]:
            print('  ' + e)
        return 1 if check else 0
    return 0


def write_dart(known: set[str], ready: dict[str, bool]) -> None:
    lines = [
        '// Generated by tool/l10n_status.py. Do not edit.',
        '',
        "import 'package:flutter/widgets.dart';",
        '',
        '/// One UI language. [code] is the ARB code: `pt_BR`, `zh_Hans`.',
        '/// [ready] means the text is translated, so the picker offers it.',
        'class AppLanguage {',
        '  const AppLanguage(this.code, this.native, this.english, this.rtl, '
        'this.reviewed, this.indian, this.ready);',
        '  final String code;',
        '  final String native;',
        '  final String english;',
        '  final bool rtl;',
        '  final bool reviewed;',
        '  final bool indian;',
        '  final bool ready;',
        '',
        '  Locale get locale => localeFor(code);',
        '}',
        '',
        '/// `pt_BR` becomes `Locale(\'pt\', \'BR\')`; `zh_Hans` carries its script.',
        'Locale localeFor(String code) {',
        "  final parts = code.split('_');",
        '  if (parts.length == 1) return Locale(parts[0]);',
        '  if (parts[1].length == 4) return Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);',
        '  return Locale(parts[0], parts[1]);',
        '}',
        '',
        'const appLanguages = <AppLanguage>[',
    ]
    for code, _store, native, name, rtl, indian, _plural in locales.LOCALES:
        esc = lambda s: s.replace('\\', '\\\\').replace("'", "\\'")
        lines.append(
            f"  AppLanguage('{esc(code)}', '{esc(native)}', '{esc(name)}', "
            f'{"true" if rtl else "false"}, {"true" if code in known else "false"}, '
            f'{"true" if indian else "false"}, {"true" if ready.get(code) else "false"}),'
        )
    lines += ['];', '']
    OUT.write_text('\n'.join(lines), encoding='utf-8')


if __name__ == '__main__':
    sys.exit(main())
