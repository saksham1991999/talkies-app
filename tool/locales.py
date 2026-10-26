#!/usr/bin/env python3
"""The one list of languages Talkies ships.

App codes are Flutter/ARB codes: the file is `lib/l10n/app_<code>.arb`, with
underscores for subtags (`pt_BR`). Store codes are App Store Connect codes.

`plural` is the CLDR cardinal set the locale must provide for every plural
message. English only needs `other`; Arabic needs six forms, Russian four.
The ARB validator, the Dart test and the status tool all read this table.
"""

from __future__ import annotations

import re

# code, store codes, endonym, English name, rtl, indian, required plural forms
LOCALES = [
    ('ar',    ['ar'],              'العربية',            'Arabic',               True,  False, {'zero', 'one', 'two', 'few', 'many', 'other'}),
    ('bn',    ['bn'],              'বাংলা',              'Bangla',               False, True,  {'other'}),
    ('ca',    ['ca'],              'Català',             'Catalan',              False, False, {'other'}),
    ('zh',    ['zh-Hans'],         '简体中文',             'Chinese (Simplified)', False, False, {'other'}),
    ('zh_Hant', ['zh-Hant'],       '繁體中文',             'Chinese (Traditional)', False, False, {'other'}),
    ('hr',    ['hr'],              'Hrvatski',           'Croatian',             False, False, {'one', 'few', 'other'}),
    ('cs',    ['cs'],              'Čeština',            'Czech',                False, False, {'one', 'few', 'many', 'other'}),
    ('da',    ['da'],              'Dansk',              'Danish',               False, False, {'other'}),
    ('nl',    ['nl'],              'Nederlands',         'Dutch',                False, False, {'other'}),
    ('en',    ['en-US', 'en-GB', 'en-AU', 'en-CA'], 'English', 'English',    False, False, {'other'}),
    ('fi',    ['fi'],              'Suomi',              'Finnish',              False, False, {'other'}),
    ('fr',    ['fr-FR', 'fr-CA'],  'Français',            'French',               False, False, {'other'}),
    ('de',    ['de-DE'],           'Deutsch',            'German',               False, False, {'other'}),
    ('el',    ['el'],              'Ελληνικά',           'Greek',                False, False, {'other'}),
    ('gu',    ['gu'],              'ગુજરાતી',            'Gujarati',             False, True,  {'other'}),
    ('he',    ['he'],              'עברית',              'Hebrew',               True,  False, {'one', 'two', 'other'}),
    ('hi',    ['hi'],              'हिन्दी',              'Hindi',                False, True,  {'other'}),
    ('hu',    ['hu'],              'Magyar',             'Hungarian',            False, False, {'other'}),
    ('id',    ['id'],              'Bahasa Indonesia',   'Indonesian',           False, False, {'other'}),
    ('it',    ['it'],              'Italiano',           'Italian',              False, False, {'other'}),
    ('ja',    ['ja'],              '日本語',              'Japanese',             False, False, {'other'}),
    ('kn',    ['kn'],              'ಕನ್ನಡ',              'Kannada',              False, True,  {'other'}),
    ('ko',    ['ko'],              '한국어',              'Korean',               False, False, {'other'}),
    ('ms',    ['ms'],              'Bahasa Melayu',      'Malay',                False, False, {'other'}),
    ('ml',    ['ml'],              'മലയാളം',             'Malayalam',            False, True,  {'other'}),
    ('mr',    ['mr'],              'मराठी',               'Marathi',              False, True,  {'other'}),
    ('no',    ['no'],              'Norsk',              'Norwegian',            False, False, {'other'}),
    ('or',    ['or'],              'ଓଡ଼ିଆ',              'Odia',                 False, True,  {'other'}),
    ('pl',    ['pl'],              'Polski',             'Polish',               False, False, {'one', 'few', 'many', 'other'}),
    ('pt',    ['pt-BR'],           'Português (Brasil)', 'Portuguese (Brazil)',  False, False, {'other'}),
    ('pt_PT', ['pt-PT'],           'Português (Portugal)', 'Portuguese (Portugal)', False, False, {'other'}),
    ('pa',    ['pa'],              'ਪੰਜਾਬੀ',              'Punjabi',              False, True,  {'other'}),
    ('ro',    ['ro'],              'Română',             'Romanian',             False, False, {'one', 'few', 'other'}),
    ('ru',    ['ru'],              'Русский',            'Russian',              False, False, {'one', 'few', 'many', 'other'}),
    ('sk',    ['sk'],              'Slovenčina',         'Slovak',               False, False, {'one', 'few', 'many', 'other'}),
    ('sl',    ['sl'],              'Slovenščina',        'Slovenian',            False, False, {'one', 'two', 'few', 'other'}),
    ('es',    ['es-ES', 'es-MX'],  'Español',            'Spanish',              False, False, {'other'}),
    ('sv',    ['sv'],              'Svenska',            'Swedish',              False, False, {'other'}),
    ('ta',    ['ta'],              'தமிழ்',               'Tamil',                False, True,  {'other'}),
    ('te',    ['te'],              'తెలుగు',              'Telugu',               False, True,  {'other'}),
    ('th',    ['th'],              'ไทย',                'Thai',                 False, False, {'other'}),
    ('tr',    ['tr'],              'Türkçe',             'Turkish',              False, False, {'other'}),
    ('uk',    ['uk'],              'Українська',         'Ukrainian',            False, False, {'one', 'few', 'many', 'other'}),
    ('ur',    ['ur'],              'اردو',               'Urdu',                 True,  True,  {'other'}),
    ('vi',    ['vi'],              'Tiếng Việt',         'Vietnamese',           False, False, {'other'}),
]

BY_CODE = {row[0]: row for row in LOCALES}

# Languages written in the Latin alphabet. For these, a keyword list full of
# Latin letters is normal, not an untranslated listing.
LATIN = {
    'ca', 'cs', 'da', 'de', 'en', 'es', 'fi', 'fr', 'hr', 'hu', 'id', 'it', 'ms',
    'nl', 'no', 'pl', 'pt', 'pt_PT', 'ro', 'sk', 'sl', 'sv', 'tr', 'vi',
}


def latin_script(code: str) -> bool:
    return BY_CODE[code][0] in LATIN


# Keys whose value is the same in every language on purpose: the app name, the
# sample ticket data in a hint, and the words printed on the ticket graphic.
# Counting them as "untranslated" would ask a translator to change `H12` or the
# name of the app. tool/translate_ai.py and tool/l10n_status.py share this list.
NEUTRAL = {
    'appName', 'admitOne', 'seatHint', 'priceHint', 'acctEmailHint', 'batchExample',
    'placeNameHint', 'whatsNewTitle', 'friendsReasonSpam', 'venueTv',
}

ACCENT_PREFIX = 'accent_'


def neutral(code: str, key: str) -> bool:
    """True when the English value is also the right value for [code].

    The eleven ink names are Indian pigment words; a Latin-script language
    writes them as they are, while every other script transliterates them.
    """
    if key in NEUTRAL:
        return True
    return key.startswith(ACCENT_PREFIX) and latin_script(code)


# Words that stay Latin in every language: the product, the formats, the
# streaming services, and the two words the ticket stamp prints.
BRAND = {
    'talkies', 'imax', '4dx', 'screenx', 'dolby', 'netflix', 'prime', 'video',
    'jiohotstar', 'sonyliv', 'zee5', 'csv', 'watched', 'fdfs', 'admit', 'one',
    'app', 'ios', 'android', 'url', 'id', 'ok', 'imdb', 'tmdb', 'wikidata',
    'wikipedia', 'pvr', 'phoenix', 'maratha', 'mandir', 'sholay', 'panchayat',
    'rrr', 'hotstar', 'inet',
}

PLURAL_LABEL = re.compile(r'\b(plural|select|other|one|two|few|many|zero)\b')


def looks_english(code: str, text: str) -> bool:
    """True when a value in a non-Latin script is really still English.

    A byte comparison misses the copy that arrived with an extra plural branch
    and therefore stopped being equal to the English source, so the share of
    Latin letters is what decides: brand words and ICU syntax removed, more
    than half Latin letters left means nobody translated it.
    """
    if code == 'en' or latin_script(code):
        return False
    stripped = re.sub(r'\{\s*\w+\s*[,}]', ' ', text)
    stripped = re.sub(r'=\d+', ' ', PLURAL_LABEL.sub(' ', stripped))
    latin = [w for w in re.findall(r'[A-Za-z]{3,}', stripped) if w.lower() not in BRAND]
    if len(latin) < 2:
        return False
    letters = len(re.findall(r'[^\W\d_]', stripped))
    return sum(len(w) for w in latin) / max(letters, 1) > 0.6


# Store locales that share an app localization with another store locale.
STORE_TO_APP = {store: row[0] for row in LOCALES for store in row[1]}


def app_codes() -> list[str]:
    return [row[0] for row in LOCALES]


def store_codes() -> list[str]:
    return [store for row in LOCALES for store in row[1]]


def plural_required(code: str) -> set[str]:
    return set(BY_CODE[code][6])


def rtl(code: str) -> bool:
    return BY_CODE[code][4]


if __name__ == '__main__':
    print(len(LOCALES), 'app locales,', len(store_codes()), 'store locales')
    for row in LOCALES:
        print(f'  {row[0]:8} {row[3]:22} {"RTL " if row[4] else "    "} plural={",".join(sorted(row[6]))}')
