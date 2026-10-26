#!/usr/bin/env python3
"""Translate the App Store listing into every storefront language.

Apple accepts 50 metadata locales. Each one is store/metadata/<code>.json. This
script fills the missing ones from the English master and refuses to write a
field that breaks Apple's limit, repeats a keyword from the name or subtitle, or
contains an em dash.

Usage:
  python3 tool/translate_store.py --all
  python3 tool/translate_store.py --locales ja,ko,zh-Hans
  python3 tool/translate_store.py --all --dry-run

Progress is kept in store/translations/<code>.json, so a run resumes.
"""

from __future__ import annotations

import concurrent.futures
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tool'))
sys.path.insert(0, str(ROOT / 'store'))

import locales  # noqa: E402
import listing_data  # noqa: E402

AGNES = Path.home() / '.claude' / 'skills' / 'agnes-ai' / 'scripts' / 'agnes.py'
OUT = ROOT / 'store' / 'translations'
MASTER = ROOT / 'store' / 'metadata' / 'en-US.json'
WORKERS = 4
ATTEMPTS = 3
DRY = False
# The upstream thinking pass returns HTTP 500 or an empty reply often enough that
# it cannot be relied on, so it is off. The prompt carries the terminology rules
# instead, and the validator rejects what still comes back broken.
THINK = False

SYSTEM = (
    'You are a professional App Store listing localizer and a native copy editor. You write concise, honest '
    'marketing copy that reads as if a native speaker wrote it, never as a literal gloss. You answer with JSON '
    'only, no prose, no code fences.'
)

FIELDS = ['name', 'subtitle', 'keywords', 'promotionalText', 'description', 'whatsNew']


def target(code: str) -> tuple[str, str]:
    app = locales.STORE_TO_APP[code]
    row = locales.BY_CODE[app]
    return row[3], row[2]


def read_master() -> dict[str, str]:
    global MASTER_BULLETS
    data = json.loads(MASTER.read_text(encoding='utf-8'))
    MASTER_BULLETS = data['description'].count('•')
    return {f: data[f] for f in FIELDS}


SCRIPT_NAMES = {
    'devanagari': 'Devanagari (U+0900 to U+097F)',
    'bengali': 'Bengali (U+0980 to U+09FF)',
    'gurmukhi': 'Gurmukhi (U+0A00 to U+0A7F)',
    'gujarati': 'Gujarati (U+0A80 to U+0AFF)',
    'oriya': 'Odia (U+0B00 to U+0B7F)',
    'tamil': 'Tamil (U+0B80 to U+0BFF)',
    'telugu': 'Telugu (U+0C00 to U+0C7F)',
    'kannada': 'Kannada (U+0C80 to U+0CFF)',
    'malayalam': 'Malayalam (U+0D00 to U+0D7F)',
    'thai': 'Thai (U+0E00 to U+0E7F)',
    'arabic': 'Arabic (U+0600 to U+06FF)',
    'hebrew': 'Hebrew (U+0590 to U+05FF)',
    'cyrillic': 'Cyrillic (U+0400 to U+04FF)',
    'greek': 'Greek (U+0370 to U+03FF)',
    'hangul': 'Hangul (U+AC00 to U+D7AF)',
    'kana': 'kana (U+3040 to U+30FF)',
    'han': 'Han (U+4E00 to U+9FFF)',
}


def script_rule(code: str) -> str:
    """A hard statement of the alphabet, appended to the prompt.

    Without it the model drops single letters from a neighbouring script into
    the middle of a word (Arabic inside Tamil, Thai inside Marathi).
    """
    app = locales.STORE_TO_APP[code]
    names = SCRIPTS.get(app)
    if not names:
        return ''
    allowed = ' and '.join(SCRIPT_NAMES.get(n, n) for n in names)
    return (
        f'- Write only in {allowed}, plus Latin letters, digits and punctuation. A single letter from '
        'any other alphabet is a failed answer.'
    )


# UI strings the app already ships in a human translation. They are the
# authority for vocabulary: "hall" is whatever hallDetails says, "ticket" is
# whatever ticket says. A listing that invents its own words for these reads as
# machine output next to the app itself.
GLOSSARY_KEYS = (
    'ticket', 'tabStubs', 'allStubs', 'hallDetails', 'show', 'seat', 'price',
    'labelClass', 'labelFormat', 'labelRating', 'tags', 'watchedAgain',
    'wantToWatch', 'statsTitle', 'totalStubs', 'rewatches', 'tabStats',
    'tabCalendar', 'calendarSection', 'share', 'backup', 'exportCsv',
    'importCsv', 'themeDark', 'appIcon', 'friendsTitle', 'nightTitle',
    'profileTitle', 'chatTitle', 'togetherGroups', 'byLanguage',
)


def glossary(code: str) -> str:
    """The app's own translations of the core UI words, for the prompt."""
    app = locales.STORE_TO_APP[code]
    path = ROOT / 'lib' / 'l10n' / f'app_{app}.arb'
    if not path.exists():
        return ''
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        return ''
    pairs = [(k, data[k]) for k in GLOSSARY_KEYS if isinstance(data.get(k), str) and data[k].strip()]
    # A value holding a plural or a placeholder is a sentence, not a term.
    pairs = [(k, v) for k, v in pairs if '{' not in v]
    if not pairs:
        return ''
    lines = '\n'.join(f'- {k}: {v}' for k, v in pairs)
    return (
        '\n\nVocabulary. The app already ships these UI words in this language. Use exactly these:\n'
        + lines
    )


def prompt_for(code: str, english: dict[str, str], fields: list[str], complaint: str = '') -> str:
    name, native = target(code)
    limits = '\n'.join(f'- {f}: at most {listing_data.LIMITS[f]} characters' for f in fields)
    return (
        'Translate this App Store listing from English into '
        f'{name} ({native}). Talkies is a movie diary app: every film you watch becomes a paper ticket stub. '
        'It is free, offline, ad-free, and needs no account.\n\n'
        'Rules:\n'
        '- Keep the product name "Talkies" in Latin letters, then translate the rest of the name.\n'
        '- Keep brand and format names unchanged: Talkies, IMAX, 4DX, 3D, ScreenX, Dolby Cinema, FDFS, WATCHED, '
        'Netflix, Prime Video, JioHotstar, SonyLIV, ZEE5, Wikidata, Wikipedia, Google, Apple, CSV.\n'
        '- keywords: 10 to 14 comma-separated search terms in the script of this language, with no spaces after '
        'the commas. Prefer terms that do not repeat a word from the name or subtitle. Never repeat a term.\n'
        '- Never leave an English common noun in the text.\n'
        '- promotionalText is one or two sentences. whatsNew is one short paragraph.\n'
        '- Keep the description structure: the same sections in capitals, the same bullet points, the same order. '
        'Translate it fully, do not shorten it.\n'
        '- Plain, warm, specific. No em dash. No emoji. No invented features.\n\n'
        'Word choice. These are the mistakes a literal translation makes, so read this twice:\n'
        '- "ticket stub" is the counterfoil of a cinema ticket. Use the everyday word a local cinema uses for '
        'the ticket itself. Do not coin a compound, do not translate "stub" on its own, do not use the word for '
        'a train, bus or cloakroom ticket, and do not use a word for a paper scrap.\n'
        '- "watchlist" is the list of films you mean to see. Never translate it as a listening list, a wish list '
        'for shopping, or a favourites list.\n'
        '- "a rewatch" is seeing the same film again. Use the ordinary phrase, not an invented noun.\n'
        '- "hall" is the cinema auditorium, "show" is the screening time, "class" is the seat tier, '
        '"format" is IMAX/4DX/3D. Use the words an Indian cinema-goer would see on a ticket, localised naturally.\n'
        '- "Stats", "your year in films", "make it yours" are section headings. Write what a local app would '
        'print, not a word-for-word gloss.\n'
        '- Use the standard local word for a dubbed version, a bar in a chart, new releases, and the native '
        'script of a title. Do not invent or misspell language names.\n'
        '- Read your draft once as a native speaker of ' + native + '. Fix every word that a native speaker '
        'would never write, every grammar slip, and every word that is spelled wrong.\n'
        + script_rule(code) + '\n'
        f'Character limits:\n{limits}\n\n'
        + (f'The previous attempt was rejected. Fix this and nothing else:\n{complaint}\n\n' if complaint else '')
        + glossary(code) + '\n\n'
        + 'Return a JSON object with exactly these keys: ' + ', '.join(fields) + '.\n\n'
        'English:\n' + json.dumps({f: english[f] for f in fields}, ensure_ascii=False)
    )


def ask(prompt: str, think: bool, system: str = '') -> str:
    if DRY:
        print(prompt)
        raise SystemExit(0)
    cmd = ['python3', str(AGNES), 'text', prompt, '--system', system or SYSTEM,
           '--max-tokens', '6000', '--temperature', '0.2']
    # Thinking mode removes the broken vocabulary the plain model invents in
    # smaller languages, but it spends the token budget on the reasoning trace.
    # On the long description the reply comes back empty, so it is only used for
    # the short fields and the caller passes the flag.
    if THINK and think:
        cmd.append('--think')
    run = subprocess.run(cmd, capture_output=True, text=True, timeout=400)
    if run.returncode != 0:
        raise RuntimeError(run.stderr.strip()[-400:] or 'agnes failed')
    return run.stdout


def parse(text: str, keep: tuple[str, ...] = ()) -> dict[str, str]:
    """The JSON object in a reply, tolerant of fences and of echoed input.

    Only the listing fields are kept by default, because a model sometimes echoes
    the prompt back. Pass `keep` for any other key the caller asked for.
    """
    wanted = set(FIELDS) | set(keep)
    body = text.strip()
    if body.startswith('```'):
        body = re.sub(r'^```[a-z]*\s*|\s*```$', '', body, flags=re.I).strip()
    try:
        data = json.loads(body)
        if isinstance(data, dict):
            return {k: str(v) for k, v in data.items() if k in wanted}
    except json.JSONDecodeError:
        pass
    best: dict | None = None
    for start, ch in enumerate(body):
        if ch != '{':
            continue
        depth = 0
        for end in range(start, len(body)):
            if body[end] == '{':
                depth += 1
            elif body[end] == '}':
                depth -= 1
                if depth == 0:
                    try:
                        obj = json.loads(body[start:end + 1])
                    except json.JSONDecodeError:
                        break
                    if isinstance(obj, dict) and (best is None or len(obj) > len(best)):
                        best = obj
                    break
    if best is None:
        raise ValueError('no JSON object in the reply')
    return {k: str(v) for k, v in best.items() if k in wanted}


# A description under this length is almost always a reply that got cut off
# mid-sentence, not a short listing.
MIN_DESCRIPTION = 900
# Filled by read_master(): how many bullets the English description carries.
MASTER_BULLETS = 0
# Languages that may keep a Latin loanword in the copy or in the keywords.
CJK = {'zh-Hans', 'zh-Hant', 'ja'}
# Locales written by a person, not by the generator. They may condense the
# master, so the shape checks (bullet count) do not apply to them.
HAND_WRITTEN = {'hi'}

# The script a listing is written in. Latin letters are always allowed (brand
# names: Talkies, IMAX, Netflix), so only the other non-Latin blocks are
# forbidden: a Telugu listing that suddenly holds Arabic letters is a broken
# model reply, not a translation.
SCRIPTS: dict[str, tuple[str, ...]] = {
    'ar': ('arabic',), 'ur': ('arabic',), 'he': ('hebrew',),
    'ru': ('cyrillic',), 'uk': ('cyrillic',), 'el': ('greek',), 'th': ('thai',),
    'hi': ('devanagari',), 'mr': ('devanagari',),
    'bn': ('bengali',), 'gu': ('gujarati',), 'pa': ('gurmukhi',), 'or': ('oriya',),
    'ta': ('tamil',), 'te': ('telugu',), 'kn': ('kannada',), 'ml': ('malayalam',),
    'ko': ('hangul', 'han'), 'ja': ('kana', 'han'), 'zh': ('han',), 'zh_Hant': ('han',),
}

BLOCKS: dict[str, tuple[tuple[int, int], ...]] = {
    'devanagari': ((0x0900, 0x097F),),
    'bengali': ((0x0980, 0x09FF),),
    'gurmukhi': ((0x0A00, 0x0A7F),),
    'gujarati': ((0x0A80, 0x0AFF),),
    'oriya': ((0x0B00, 0x0B7F),),
    'tamil': ((0x0B80, 0x0BFF),),
    'telugu': ((0x0C00, 0x0C7F),),
    'kannada': ((0x0C80, 0x0CFF),),
    'malayalam': ((0x0D00, 0x0D7F),),
    'thai': ((0x0E00, 0x0E7F),),
    'arabic': ((0x0600, 0x06FF), (0x0750, 0x077F), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF)),
    'hebrew': ((0x0590, 0x05FF), (0xFB1D, 0xFB4F)),
    'cyrillic': ((0x0400, 0x04FF), (0x0500, 0x052F)),
    'greek': ((0x0370, 0x03FF), (0x1F00, 0x1FFF)),
    'hangul': ((0x1100, 0x11FF), (0x3130, 0x318F), (0xAC00, 0xD7AF)),
    'kana': ((0x3040, 0x30FF), (0x31F0, 0x31FF)),
    'han': ((0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF)),
}

# Shared punctuation: danda and double danda sit inside the Devanagari block but
# every Indic script uses them, so they are never a wrong-script signal.
SHARED = {0x0964, 0x0965, 0x0970, 0x200C, 0x200D, 0x2018, 0x2019, 0x201C, 0x201D}


def foreign_scripts(code: str, text: str) -> list[str]:
    app = locales.STORE_TO_APP[code]
    allowed = SCRIPTS.get(app)
    if not allowed:
        return []
    ok = {name for name in allowed}
    seen: dict[str, str] = {}
    for ch in text:
        point = ord(ch)
        if point < 0x0370 or point in SHARED:
            continue  # Latin, digits, punctuation, spaces
        for name, ranges in BLOCKS.items():
            if name in ok:
                continue
            if any(low <= point <= high for low, high in ranges):
                seen.setdefault(name, ch)
    return [f'{name} letters such as "{ch}"' for name, ch in seen.items()]


def _words(code: str, data: dict[str, str]) -> set[str]:
    raw = (data.get('name', '') + ' ' + data.get('subtitle', '')).replace(':', ' ')
    return {w.lower().strip('.,:&') for w in raw.split()}


# Words a model invents when it translates "ticket stub", "watchlist" or
# "WATCHED" literally. Each entry was read off a shipped file and confirmed
# wrong by hand, so the checker rejects only what is provably broken.
BAD_TERMS: dict[str, tuple[str, ...]] = {
    'it': ('ritagliett', 'bigliel', 'visio ', 'rivedut', 'matineo', 'lista di ascolto'),
    'ja': ('切符', 'ドビング', 'カニーダ', 'マラヤーティ', '漢字表記', '新刊'),
    'ko': ('잔여물', '구독', '볼람우드', '필름 줄', '시청 대기열'),
    # Read off a Tamil draft: "football" and "this is not a shirt" appeared in the
    # copy, which is what the model produces when the term list runs dry.
    'ta': ('கால்பந்து', 'சட்டையல்லாது', 'நோட்டுப் பதிவகம்'),
    # Read off a German draft: "ZU EDER KARTE" is a mangled article, "Ansehdauer"
    # is misspelled, and "Erinnert sich das Datum nicht" has the wrong subject.
    'de': ('zu eder', 'ansehdauer', 'erinnert sich das datum', 'jeden gefilmten film',
           'deine bleiben bei dir', 'kartinummer'),
}

# Locales whose description ends in a keyword dump instead of listing copy.
KEYWORD_STUFFING = ('关键词', '關鍵詞', 'キーワード', '키워드')
# Any of these words introducing a comma list means the model appended the
# keywords field to the description, which Apple rejects.
KEYWORD_LINE = re.compile(
    r'^\s*(keywords?|kunci|mot-?cl[eé]s?|schl[üu]sselw[öo]rter|palabras?\s*clave|parole\s*chiave|'
    r'キーワード|키워드|关键词|關鍵詞|كلمات\s*مفتاحية|מילות\s*מפתח)\s*[:：]',
    re.I | re.M,
)
# A line that is nothing but capital Latin words is a section heading the model
# forgot to translate ("CALENDAR AND WATCHLIST" in the middle of Tamil).
ENGLISH_HEADING = re.compile(r'^[A-Z][A-Z0-9 &,\'\-]{5,}$', re.M)
# The English word "stub", transliterated into a local script, is the same
# unfinished translation as leaving it in Latin letters.
STUB_LOAN = re.compile('ஸ்டப்|ಸ್ಟಬ್|స్టబ్|സ്റ്റബ്|ਸਟਬ|સ્ટબ|ଷ୍ଟବ|স্টব|स्टब|ستب|סטאב', re.I)


def repeated_phrase(text: str) -> str:
    """A phrase repeated five times is a model looping, not prose.

    Four words repeated five times cannot happen by accident in a 3,000
    character listing; two-word phrases do repeat naturally ("una pel·lícula"),
    so short phrases are not checked.
    """
    words = re.findall(r'[^\s\u00a0]+', text)
    for size in (6, 5, 4):
        if len(words) < size:
            continue
        grams = [' '.join(words[i:i + size]) for i in range(len(words) - size + 1)]
        for gram in set(grams):
            if grams.count(gram) >= 5:
                return gram
    return ''


def glossary_word(code: str, key: str) -> str:
    app = locales.STORE_TO_APP[code]
    path = ROOT / 'lib' / 'l10n' / f'app_{app}.arb'
    if not path.exists():
        return ''
    try:
        value = json.loads(path.read_text(encoding='utf-8')).get(key, '')
    except json.JSONDecodeError:
        return ''
    return value if isinstance(value, str) and '{' not in value else ''


def shape_problems(code: str, data: dict[str, str]) -> list[str]:
    """Replies that are technically filled but structurally broken."""
    out: list[str] = []
    desc = data.get('description', '')
    bullets = [b.strip() for b in desc.split('\n') if b.strip().startswith('•')]
    for bullet in set(bullets):
        if bullets.count(bullet) > 1:
            out.append(f'description: the same bullet repeats {bullets.count(bullet)} times')
            break
    loop = repeated_phrase(desc)
    if loop:
        out.append(f'description: the phrase "{loop}" repeats, the model looped')
    # Only meaningful where the body is not Latin: Italian or Dutch headings are
    # correctly written in capitals, Tamil ones should not be written in English.
    if not locales.latin_script(locales.STORE_TO_APP[code]):
        heading = ENGLISH_HEADING.search(desc)
        if heading:
            out.append(f'description: untranslated English heading "{heading.group(0).strip()}"')
    if STUB_LOAN.search(desc):
        out.append('description: "stub" transliterated instead of translated')
    # The shipped spelling of "ticket" is fed to the model in the prompt. It is
    # deliberately not a hard check: a good translation legitimately uses a
    # second word in some sentences (Japanese 上映券 next to チケット), so failing
    # on the count would reject correct copy.
    # A prose field that is a comma list with no sentences is a keyword dump.
    for field in ('promotionalText', 'whatsNew'):
        text = data.get(field, '')
        if text and text.count(',') >= 5 and text.count(' ') <= text.count(',') // 2:
            out.append(f'{field}: keyword list instead of a sentence')
        if text and repeated_phrase(text):
            out.append(f'{field}: repeated phrase, the model looped')
    return out


def bad_terms(code: str, data: dict[str, str]) -> list[str]:
    app = locales.STORE_TO_APP[code]
    terms = BAD_TERMS.get(app, ())
    body = json.dumps(data, ensure_ascii=False).lower()
    out = [f'bad term "{t}": literal or misspelled translation' for t in terms if t.lower() in body]
    desc = data.get('description', '')
    if any(mark in desc for mark in KEYWORD_STUFFING) or KEYWORD_LINE.search(desc):
        out.append('description: keyword list appended to the body')
    return out


def field_notes(code: str, data: dict[str, str]) -> list[str]:
    """Soft findings: printed for a human, never a reason to retry the model.

    Apple asks that keywords not repeat the app name or subtitle, but a natural
    translation cannot always avoid it (Italian "cinema", "diario"). Rejecting
    the reply just loops forever, so these are reported and accepted.
    """
    out: list[str] = []
    words = _words(code, data)
    for term in data.get('keywords', '').split(','):
        term = term.strip()
        if term and term.lower() in words:
            out.append(f'{code}.keywords: repeats "{term}" from name/subtitle')
    if not code.startswith('en') and not locales.latin_script(locales.STORE_TO_APP[code]):
        latin = [k for k in data.get('keywords', '').split(',') if k.strip() and k.strip().isascii()]
        if latin:
            out.append(f'{code}.keywords: {len(latin)} Latin-script term(s): {", ".join(k.strip() for k in latin)}')
    if code in CJK and re.search(r'\bstubs?\b', json.dumps(data, ensure_ascii=False), re.I):
        out.append(f'{code}: keep the Latin word "stub": read it as the local loanword')
    return out


def field_problems(code: str, data: dict[str, str]) -> list[str]:
    """Hard failures. Only these make the caller retry the model."""
    out: list[str] = []
    for f in [x for x in FIELDS if x in data]:
        text = data.get(f, '')
        if not text.strip():
            out.append(f'{f}: empty')
        elif len(text) > listing_data.LIMITS[f]:
            out.append(f'{f}: {len(text)} characters, limit {listing_data.LIMITS[f]}')
        elif '—' in text:
            out.append(f'{f}: em dash')
        elif f == 'description' and not code.startswith('en') and len(text) < MIN_DESCRIPTION:
            out.append(f'{f}: {len(text)} characters, under {MIN_DESCRIPTION} (reply was cut off)')
        elif f == 'description' and not code.startswith('en') and code not in HAND_WRITTEN:
            # Every bullet in the master must survive. A couple merged into one
            # line is fine; a big shortfall means the reply stopped early even
            # when it is still above the length floor.
            want = MASTER_BULLETS
            got = text.count('•')
            if want and got < want - 2:
                out.append(f'{f}: {got} bullet points, the master has {want} (reply was cut off)')
    # An English common noun left in the copy reads as an unfinished translation.
    # Chinese and Japanese borrow the word instead of translating it, so those
    # two are inspected by hand rather than rejected here.
    if not code.startswith('en') and code not in CJK:
        if re.search(r'\bstubs?\b', json.dumps(data, ensure_ascii=False), re.I):
            out.append('stub: English word left in the text')
    # Brand names (IMAX, FDFS, Netflix) are legitimately Latin in any script, so
    # the cap is loose: at most 5 terms, and only outside Latin-script locales.
    if not code.startswith('en') and not locales.latin_script(locales.STORE_TO_APP[code]):
        latin = [k for k in data.get('keywords', '').split(',') if k.strip() and k.strip().isascii()]
        if len(latin) > 5:
            out.append(f'keywords: {len(latin)} Latin terms, at most 5')
    # A letter from the wrong alphabet is a corrupted reply, never a translation.
    if not code.startswith('en'):
        foreign = foreign_scripts(code, json.dumps(data, ensure_ascii=False))
        if foreign:
            out.append('wrong script: ' + ', '.join(foreign))
        out += bad_terms(code, data)
        out += shape_problems(code, data)
    return out


def _bullets(text: str) -> list[str]:
    return [b.strip() for b in text.split('\n') if b.strip().startswith('•')]


def translate_description(code: str, english: dict[str, str]) -> str:
    """The description, one blank-line block at a time.

    Handing the whole 2,400 character text to a small model in one call produces
    a flat gloss in the weaker languages. Block by block it keeps the structure
    and reads like the local copy. Each block is checked on its own, so a block
    that picks up a letter from another alphabet is retried instead of shipped.
    """
    name, native = target(code)
    blocks = [b for b in english['description'].split('\n\n') if b.strip()]
    system = (
        f'You are a professional App Store listing localizer for {name} ({native}), and a native '
        'copy editor. You answer with JSON only, no prose, no code fences.'
    )
    done: list[str] = []
    for block in blocks:
        prompt = (
            f'Translate this block of the App Store description into {name} ({native}).\n'
            'Rules:\n'
            '- Keep every • bullet and every line break of the block. Do not merge or drop one.\n'
            '- Translate the capitalised section heading into this language. Never leave an English\n'
            '  heading such as "HALL DETAILS, THE INDIAN WAY" in Latin capitals.\n'
            '- Never repeat a bullet or a sentence. If a bullet is unclear, translate it once.\n'
            '- Keep brand names in Latin: Talkies, IMAX, 4DX, 3D, ScreenX, Dolby Cinema, FDFS, WATCHED, '
            'Netflix, Prime Video, JioHotstar, SonyLIV, ZEE5, Wikidata, Wikipedia, Google, Apple, CSV.\n'
            '- "ticket stub" is the cinema ticket itself. Use the everyday local word for it. Never the word '
            'for a screen, a scrap of paper, a train ticket or a programme, and never the English word '
            'transliterated into this script.\n'
            '- Do not append a keyword list. No em dash. No emoji. Do not add a feature that is not here.\n'
            + script_rule(code) + '\n'
            + glossary(code) + '\n'
            'Return JSON with one key: "text".\n\n'
            'Block:\n' + block
        )
        last = ''
        for attempt in range(ATTEMPTS * 2):
            try:
                got = parse(ask(prompt, False, system), keep=('text',))
                text = got.get('text', '').strip()
                if not text:
                    last = 'empty text'
                elif '—' in text:
                    last = 'em dash'
                elif foreign_scripts(code, text) and not code.startswith('en'):
                    last = 'wrong script: ' + ', '.join(foreign_scripts(code, text))
                elif code not in CJK and re.search(r'\bstubs?\b', text, re.I) and not code.startswith('en'):
                    last = 'stub left in English'
                elif KEYWORD_LINE.search(text):
                    last = 'keyword list appended'
                elif not locales.latin_script(locales.STORE_TO_APP[code]) and ENGLISH_HEADING.search(text):
                    last = 'English heading left untranslated'
                elif STUB_LOAN.search(text):
                    last = '"stub" transliterated instead of translated'
                elif len(set(_bullets(text))) != len(_bullets(text)):
                    last = 'a bullet is repeated'
                else:
                    done.append(text)
                    last = ''
                    break
            except Exception as exc:  # noqa: BLE001 - retry any failure
                last = str(exc)
            time.sleep(1 + attempt)
        if last:
            raise ValueError(f'description block failed: {last}')
    return '\n\n'.join(done)


def translate(code: str, english: dict[str, str]) -> tuple[str, dict[str, str], list[str]]:
    path = OUT / f'{code}.json'
    done: dict[str, str] = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    problems: list[str] = []
    notes: list[str] = []
    seen: set[str] = set()
    # The description is long; asking for it in the same reply as the short
    # fields truncates the answer on some languages.
    groups = [
        ['name', 'subtitle', 'keywords', 'promotionalText', 'whatsNew'],
        ['description'],
    ]
    for group in groups:
        todo = [f for f in group if f not in done]
        if todo == ['description']:
            # Block by block, not one long call: see translate_description().
            for attempt in range(1, ATTEMPTS + 1):
                try:
                    got = {'description': translate_description(code, english)}
                    bad = field_problems(code, got)
                    if bad:
                        problems += [f'{code}.{p}' for p in bad]
                        raise ValueError('; '.join(bad))
                    done.update(got)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(json.dumps(done, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
                    todo = []
                    break
                except Exception as exc:  # noqa: BLE001 - retry any failure
                    if attempt >= ATTEMPTS:
                        problems.append(f'{code}: description: {exc}')
                    else:
                        time.sleep(2 * attempt)
            if todo:
                problems.append(f'{code}: still missing description')
            continue
        # Think only while the answer is short. The description would come back
        # empty because the reasoning trace uses up max-tokens.
        think = 'description' not in group
        tries = 0
        complaint = ''
        while todo and tries < ATTEMPTS * 2:
            tries += 1
            try:
                got = parse(ask(prompt_for(code, english, todo, complaint), think))
                if 'keywords' in got:
                    terms = [k.strip() for k in got['keywords'].split(',') if k.strip()]
                    unique = list({k.lower(): k for k in reversed(terms)}.values())[::-1]
                    if len(unique) != len(terms):
                        print(f'  note: {code}.keywords: dropped {len(terms) - len(unique)} duplicate term(s)')
                    got['keywords'] = ','.join(unique)
                if set(got) < set(todo):
                    raise ValueError('reply is missing ' + ','.join(sorted(set(todo) - set(got))))
                bad = field_problems(code, got)
                for note in field_notes(code, got):
                    if note not in seen:
                        seen.add(note)
                        notes.append(note)
                        print(f'  note: {note}')
                if bad:
                    problems += [f'{code}.{p}' for p in bad]
                    # A problem whose prefix is not a field name (wrong script,
                    # stub left in, bad term) cannot be pinned to one field, so
                    # nothing from this reply is kept: saving the "good" fields
                    # would write the very text the check just rejected.
                    named = all(p.split(':')[0] in FIELDS for p in bad)
                    bad_fields = {p.split(':')[0] for p in bad if named} or set(todo)
                    # Keep the fields that passed: a retry only re-asks for the
                    # ones that failed, and dropping the good ones left a file
                    # stuck at zero fields forever.
                    good = [f for f in todo if f not in bad_fields]
                    if good:
                        done.update({f: got[f] for f in good})
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_text(json.dumps(done, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
                    todo = [f for f in todo if f in bad_fields] or todo
                    # Tell the next attempt exactly what broke, with the length
                    # it reached. Without this the model repeats the same answer.
                    complaint = '\n'.join(
                        f'- {p}' + (f' (your answer was {len(got.get(p.split(":")[0], ""))} characters)'
                                    if p.split(':')[0] in got else '')
                        for p in bad
                    )
                    continue
                done.update({f: got[f] for f in todo})
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(done, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
                problems = [p for p in problems if not p.startswith(code + '.')]
                todo = []
            except Exception as exc:  # noqa: BLE001 - any failure means retry
                if tries >= ATTEMPTS * 2:
                    problems.append(f'{code}: {exc}')
                else:
                    time.sleep(2 * tries)
        if todo:
            problems.append(f'{code}: still missing {",".join(todo)}')
    return code, done, problems


def main() -> int:
    global DRY, WORKERS, THINK
    args = sys.argv[1:]
    DRY = '--dry-run' in args
    THINK = '--think' in args
    if '--workers' in args:
        WORKERS = int(args[args.index('--workers') + 1])
    english = read_master()
    codes = locales.store_codes()
    if '--locales' in args:
        codes = args[args.index('--locales') + 1].split(',')
    todo = [c for c in codes if '--force' in args or not listing_data.path(c).exists()]
    if '--force' in args:
        for c in todo:
            (OUT / f'{c}.json').unlink(missing_ok=True)
    if not todo:
        print('every locale has a file')
        return 0
    print(f'{len(todo)} locales to write')
    OUT.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = [pool.submit(translate, code, english) for code in todo]
        for future in concurrent.futures.as_completed(futures):
            code, done, bad = future.result()
            failures += bad
            if set(done) == set(FIELDS) and not bad:
                listing_data.path(code).write_text(json.dumps(done, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
                print(f'  {code}: ok')
            else:
                print(f'  {code}: {len(done)}/6 fields' + (f', {len(bad)} problem(s)' if bad else ''))
    if failures:
        print(f'{len(failures)} problem(s):')
        for f in failures[:30]:
            print('  ' + f)
    left = [c for c in locales.store_codes() if not listing_data.path(c).exists()]
    print(f'{len(locales.store_codes()) - len(left)}/{len(locales.store_codes())} locales written')
    return 0 if not left else 1


if __name__ == '__main__':
    sys.exit(main())
