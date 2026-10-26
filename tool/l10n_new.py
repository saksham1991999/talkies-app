#!/usr/bin/env python3
"""Create an ARB file for every locale in tool/locales.py that has none.

The new file holds the English text, in English key order, with no `@` metadata.
That is a placeholder, not a translation: tool/l10n_status.py counts how many
values still match English, and the app only offers a language whose text has
really been translated.

Usage:
  python3 tool/l10n_new.py            create the missing files
  python3 tool/l10n_new.py --check    list what is missing, write nothing
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
    check = '--check' in sys.argv
    english = json.loads(merge_arb.arb_path('en').read_text(encoding='utf-8'))
    order = [k for k in english if not k.startswith('@')]
    missing = [c for c in locales.app_codes() if not merge_arb.arb_path(c).exists()]
    if check:
        print('\n'.join(missing) or 'every locale has a file')
        return 0
    for code in missing:
        lines = ['{']
        for i, key in enumerate(order):
            comma = ',' if i < len(order) - 1 else ''
            lines.append(f'  {json.dumps(key)}: {json.dumps(english[key], ensure_ascii=False)}{comma}')
        lines.append('}')
        merge_arb.arb_path(code).write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'created {len(missing)} files')
    return 0


if __name__ == '__main__':
    sys.exit(main())
