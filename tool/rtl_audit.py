#!/usr/bin/env python3
"""Static right-to-left audit for lib/ui/**.

The app ships 44 UI languages, three of them right-to-left (Arabic, Hebrew,
Urdu). A layout call that names a physical side (`left`, `right`,
`TextAlign.left`, `Alignment.centerLeft`, `Positioned(left:)`) cannot follow
the reading direction, so the sweep from physical to directional widgets is
easy to leave half done. This scan finds the leftovers.

Usage:
  python3 tool/rtl_audit.py            audit lib/ui and exit 1 on any finding
  python3 tool/rtl_audit.py --info     also list the entries that need a human
                                       eye (`EdgeInsets.fromLTRB`, symmetric
                                       `Alignment.topLeft` corners); they never
                                       fail the run
  python3 tool/rtl_audit.py PATH ...   audit other files or folders

Rules that fail the run
  insets        EdgeInsets.only(left:/right:)           use EdgeInsetsDirectional.only(start/end)
  radius        BorderRadius.only(topLeft: … )          use BorderRadiusDirectional.only(topStart/topEnd)
                BorderRadius.horizontal(left:/right:)
  textalign     TextAlign.left / TextAlign.right        use TextAlign.start / end
  alignment     Alignment.centerLeft / centerRight      use AlignmentDirectional.centerStart / centerEnd
  positioned    Positioned(left:) or Positioned(right:) use PositionedDirectional(start:/end:)
                (both sides pinned is a mirror-safe span: reported as info)
  direction     textDirection: TextDirection.ltr/rtl    never hardcode the reading direction
  material-icon Icons.chevron_right, Icon(Icons.arrow_back), …  the house set is `Tk` (lib/ui/icons.dart),
                which mirrors Tk.back/left/right/send under RTL; a Material directional icon does not
  row-icon      a Row that starts with an icon and spaces it with a physical inset — the gap stops
                flipping the moment the icon does

Everything is matched on source with comments and string literals masked out,
so a rule named in a comment (this file's own docstring, for instance) is not a
finding. Code inside `${…}` string interpolation is masked with its string, so
a layout call built inside an interpolation is not seen; nothing in lib/ui does
that today and the widget tests cover the assembled screens.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROOT = ROOT / 'lib' / 'ui'


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    rule: str
    detail: str

    def sort_key(self):
        return (self.path, self.line, self.rule)


# ---------------------------------------------------------------- source masking


def mask(text: str) -> str:
    """Blank out comments and string literals, keeping every newline and offset.

    Positions in the masked text are positions in the real file, so a match
    offset maps straight back to a line number.
    """
    out = list(text)
    i, n = 0, len(text)

    def blank(a: int, b: int) -> None:
        for k in range(a, b):
            if out[k] != '\n':
                out[k] = ' '

    while i < n:
        c = text[i]
        two = text[i : i + 2]
        three = text[i : i + 3]
        if two == '//':
            j = text.find('\n', i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif two == '/*':
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            blank(i, j)
            i = j
        elif three in ("'''", '"""'):
            j = text.find(three, i + 3)
            j = n if j < 0 else j + 3
            blank(i, j)
            i = j
        elif c in "'\"":
            # Raw strings (r'...') have no escapes; plain strings do.
            raw = i > 0 and text[i - 1] == 'r'
            j = i + 1
            while j < n:
                if text[j] == '\\' and not raw:
                    j += 2
                    continue
                if text[j] == c:
                    j += 1
                    break
                if text[j] == '\n':  # unterminated: stop at the line end
                    break
                j += 1
            blank(i, j)
            i = j
        else:
            i += 1
    return ''.join(out)


def line_of(masked: str, offset: int) -> int:
    return masked.count('\n', 0, offset) + 1


def matching_paren(masked: str, open_at: int) -> int:
    """Index of the `)` that closes the `(` at [open_at], or len(masked)."""
    depth = 0
    for k in range(open_at, len(masked)):
        c = masked[k]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return k
    return len(masked)


def calls(masked: str, name: str) -> list[tuple[int, int]]:
    """Every `name(` call as (name offset, open paren offset), skipping `X.name(`."""
    out = []
    for m in re.finditer(r'(?<![A-Za-z0-9_$.])' + re.escape(name) + r'\s*\(', masked):
        out.append((m.start(), masked.index('(', m.start())))
    return out


# ---------------------------------------------------------------- rules


def scan_insets(masked: str, findings: list[Finding], rel: str) -> None:
    for start, open_at in calls(masked, 'EdgeInsets.only'):
        close = matching_paren(masked, open_at)
        body = masked[open_at + 1 : close]
        for side in ('left', 'right'):
            for m in re.finditer(r'(?<![A-Za-z_])' + side + r'\s*:', body):
                findings.append(
                    Finding(
                        rel,
                        line_of(masked, open_at + 1 + m.start()),
                        'insets',
                        f'EdgeInsets.only({side}: …) — use EdgeInsetsDirectional.only('
                        f'{"start" if side == "left" else "end"}: …)',
                    )
                )


def scan_radius(masked: str, findings: list[Finding], rel: str) -> None:
    for name in ('BorderRadius.only', 'BorderRadiusDirectional.only'):
        for start, open_at in calls(masked, name):
            close = matching_paren(masked, open_at)
            body = masked[open_at + 1 : close]
            physical = {
                'topLeft': 'topStart',
                'topRight': 'topEnd',
                'bottomLeft': 'bottomStart',
                'bottomRight': 'bottomEnd',
            }
            for corner, directional in physical.items():
                for m in re.finditer(r'(?<![A-Za-z_])' + corner + r'\s*:', body):
                    findings.append(
                        Finding(
                            rel,
                            line_of(masked, open_at + 1 + m.start()),
                            'radius',
                            f'{name}({corner}: …) — use BorderRadiusDirectional.only({directional}: …)',
                        )
                    )
    # BorderRadius.horizontal(left: …) is physical too.
    for start, open_at in calls(masked, 'BorderRadius.horizontal'):
        close = matching_paren(masked, open_at)
        body = masked[open_at + 1 : close]
        for side, directional in (('left', 'start'), ('right', 'end')):
            for m in re.finditer(r'(?<![A-Za-z_])' + side + r'\s*:', body):
                findings.append(
                    Finding(
                        rel,
                        line_of(masked, open_at + 1 + m.start()),
                        'radius',
                        f'BorderRadius.horizontal({side}: …) — use BorderRadiusDirectional.horizontal('
                        f'{directional}: …)',
                    )
                )


def scan_textalign(masked: str, findings: list[Finding], rel: str) -> None:
    for m in re.finditer(r'TextAlign\.(left|right)\b', masked):
        side = m.group(1)
        findings.append(
            Finding(
                rel,
                line_of(masked, m.start()),
                'textalign',
                f'TextAlign.{side} — use TextAlign.{"start" if side == "left" else "end"}',
            )
        )


def scan_alignment(masked: str, findings: list[Finding], infos: list[Finding], rel: str) -> None:
    for m in re.finditer(r'(?<![A-Za-z_])Alignment\.(centerLeft|centerRight)\b', masked):
        side = m.group(1)
        findings.append(
            Finding(
                rel,
                line_of(masked, m.start()),
                'alignment',
                f'Alignment.{side} — use AlignmentDirectional.'
                f'{"centerStart" if side == "centerLeft" else "centerEnd"}',
            )
        )
    # A corner anchor is physical as well, but it is often used for decoration that
    # is meant to sit in one corner in every language: review by hand, never fail.
    for m in re.finditer(r'(?<![A-Za-z_])Alignment\.(topLeft|topRight|bottomLeft|bottomRight)\b', masked):
        infos.append(
            Finding(
                rel,
                line_of(masked, m.start()),
                'alignment-corner',
                f'Alignment.{m.group(1)} is physical — AlignmentDirectional.*Start/*End mirrors it',
            )
        )


def scan_positioned(masked: str, findings: list[Finding], infos: list[Finding], rel: str) -> None:
    for name in ('Positioned', 'AnimatedPositioned', 'AnimatedPositionedDirectional'):
        for start, open_at in calls(masked, name):
            close = matching_paren(masked, open_at)
            body = masked[open_at + 1 : close]
            sides = {}
            for side in ('left', 'right'):
                m = re.search(r'(?<![A-Za-z_])' + side + r'\s*:', body)
                if m:
                    sides[side] = m
            if not sides:
                continue
            if len(sides) == 2:
                # Pinned to both edges: a full-width span, identical mirrored.
                infos.append(
                    Finding(
                        rel,
                        line_of(masked, start),
                        'positioned-both',
                        f'{name}(left: …, right: …) — a mirrored span, no action unless the intent is one side',
                    )
                )
                continue
            side, m = next(iter(sides.items()))
            findings.append(
                Finding(
                    rel,
                    line_of(masked, open_at + 1 + m.start()),
                    'positioned',
                    f'{name}({side}: …) — use PositionedDirectional('
                    f'{"start" if side == "left" else "end"}: …)',
                )
            )


def scan_direction(masked: str, findings: list[Finding], infos: list[Finding], rel: str) -> None:
    # A `TextPainter` has no ambient Directionality to inherit: its
    # `textDirection` is a required argument, not a hardcoded override. Painting
    # Latin (the WATCHED stamp, a serial) or a single glyph (an avatar initial)
    # with LTR is correct. Painting a whole localised sentence with it is not, so
    # these stay in the report for a human, as info.
    painters = [(open_at, matching_paren(masked, open_at)) for _, open_at in calls(masked, 'TextPainter')]

    for m in re.finditer(r'textDirection\s*:\s*TextDirection\.(ltr|rtl)\b', masked):
        in_painter = any(a <= m.start() <= b for a, b in painters)
        if in_painter:
            infos.append(
                Finding(
                    rel,
                    line_of(masked, m.start()),
                    'direction-painter',
                    f'TextPainter(textDirection: TextDirection.{m.group(1)}) — required, there is no ambient '
                    'direction; fine for one glyph or a Latin-only stamp, a bug for a localised sentence',
                )
            )
            continue
        findings.append(
            Finding(
                rel,
                line_of(masked, m.start()),
                'direction',
                f'textDirection: TextDirection.{m.group(1)} is hardcoded — read it from Directionality',
            )
        )


MATERIAL_DIRECTIONAL = (
    'arrow_back',
    'arrow_back_ios',
    'arrow_back_ios_new',
    'arrow_forward',
    'arrow_forward_ios',
    'arrow_left',
    'arrow_right',
    'chevron_left',
    'chevron_right',
    'keyboard_arrow_left',
    'keyboard_arrow_right',
    'keyboard_backspace',
    'navigate_before',
    'navigate_next',
    'first_page',
    'last_page',
    'subdirectory_arrow_left',
    'subdirectory_arrow_right',
    'trending_flat',
    'send',
    'reply',
    'reply_all',
    'format_indent_increase',
    'format_indent_decrease',
    'exit_to_app',
    'login',
    'logout',
    'double_arrow',
    'swipe_left',
    'swipe_right',
    'redo',
    'undo',
)


def scan_material_icons(masked: str, findings: list[Finding], rel: str) -> None:
    names = '|'.join(MATERIAL_DIRECTIONAL)
    for m in re.finditer(r'(?<![A-Za-z_$])(?:Icons|CupertinoIcons)\.(' + names + r')\b', masked):
        findings.append(
            Finding(
                rel,
                line_of(masked, m.start()),
                'material-icon',
                f'{m.group(0)} does not follow the reading direction — use the Tk set (lib/ui/icons.dart)',
            )
        )


PHYSICAL_INSIDE_ROW = re.compile(
    r'(?<![A-Za-z_])(?:left|right)\s*:|TextAlign\.(?:left|right)\b|Alignment\.(?:centerLeft|centerRight)\b'
)


def scan_row_icons(masked: str, findings: list[Finding], rel: str) -> None:
    """A Row that leads with an icon and spaces it physically.

    A Row's children already mirror under RTL, so a leading icon alone is fine.
    What breaks is a leading icon pushed away by a physical inset or aligned to
    a physical side: the icon flips (or does not) and the gap stays put.
    """
    for start, open_at in calls(masked, 'Row'):
        close = matching_paren(masked, open_at)
        body = masked[open_at + 1 : close]
        child = re.search(r'children\s*:\s*(?:const\s*)?\[', body)
        if not child:
            continue
        after = body[child.end() :]
        stripped = after.lstrip()
        stripped = re.sub(r'^(?:const|key:\s*[^,]+,\s*)?', '', stripped).lstrip()
        if not (stripped.startswith('TkIcon(') or stripped.startswith('Icon(')):
            continue
        if 'textDirection:' in body:
            continue
        m = PHYSICAL_INSIDE_ROW.search(body)
        if m:
            findings.append(
                Finding(
                    rel,
                    line_of(masked, open_at + 1 + m.start()),
                    'row-icon',
                    'a Row that leads with an icon and spaces it on a physical side — '
                    'the icon mirrors and the gap does not; use a directional inset',
                )
            )


def scan_fromltrb(masked: str, infos: list[Finding], rel: str) -> None:
    """`fromLTRB` with equal left and right is symmetric and needs no review.

    Only the asymmetric ones are worth a human's time, so only those are listed.
    """
    for _, open_at in calls(masked, 'EdgeInsets.fromLTRB'):
        close = matching_paren(masked, open_at)
        args = _split_args(masked[open_at + 1 : close])
        if len(args) != 4:
            continue
        left, right = args[0].strip(), args[2].strip()
        if left == right:
            continue
        infos.append(
            Finding(
                rel,
                line_of(masked, open_at),
                'fromLTRB',
                f'EdgeInsets.fromLTRB(… {left} … {right} …) has unequal sides — '
                f'EdgeInsetsDirectional.fromSTEB({left}, …, {right}, …) if the difference is meant as a lead',
            )
        )


def _split_args(body: str) -> list[str]:
    """Top-level comma split, so nested calls stay with their argument."""
    args, depth, start = [], 0, 0
    for i, c in enumerate(body):
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            args.append(body[start:i])
            start = i + 1
    args.append(body[start:])
    return [a for a in args if a.strip()]


# ---------------------------------------------------------------- driver


def audit(paths: list[Path]) -> tuple[list[Finding], list[Finding], int]:
    findings: list[Finding] = []
    infos: list[Finding] = []
    files = 0
    for path in paths:
        for file in sorted(path.rglob('*.dart')) if path.is_dir() else [path]:
            files += 1
            try:
                rel = str(file.relative_to(ROOT))
            except ValueError:
                rel = str(file)
            masked = mask(file.read_text(encoding='utf-8'))
            scan_insets(masked, findings, rel)
            scan_radius(masked, findings, rel)
            scan_textalign(masked, findings, rel)
            scan_alignment(masked, findings, infos, rel)
            scan_positioned(masked, findings, infos, rel)
            scan_direction(masked, findings, infos, rel)
            scan_material_icons(masked, findings, rel)
            scan_row_icons(masked, findings, rel)
            scan_fromltrb(masked, infos, rel)
    findings.sort(key=Finding.sort_key)
    infos.sort(key=Finding.sort_key)
    return findings, infos, files


def main(argv: list[str]) -> int:
    show_info = '--info' in argv
    args = [a for a in argv[1:] if not a.startswith('--')]
    paths = [Path(a).resolve() for a in args] or [DEFAULT_ROOT]
    findings, infos, files = audit(paths)

    rules = {}
    for f in findings:
        rules[f.rule] = rules.get(f.rule, 0) + 1

    if findings:
        print(f'{len(findings)} RTL finding(s) in {files} file(s):\n')
        for f in findings:
            print(f'{f.path}:{f.line}: [{f.rule}] {f.detail}')
        print('\nby rule: ' + ', '.join(f'{k} {v}' for k, v in sorted(rules.items())))
    else:
        print(f'No RTL findings in {files} file(s).')

    if infos and show_info:
        print(f'\n{len(infos)} entry/entries to review by hand (not failures):')
        for f in infos:
            print(f'{f.path}:{f.line}: [{f.rule}] {f.detail}')

    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
