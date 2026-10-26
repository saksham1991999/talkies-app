#!/usr/bin/env python3
"""Frames raw app captures as App Store and Play screenshots, plus the Play
feature graphic and icon. Writes store/.

1. Capture: flutter drive --driver=test_driver/integration_test.dart
     --target=integration_test/store_screens_test.dart -d <iPhone 6.9" sim>
   then copy build/screens/<locale>/*.png to build/store_raw/iphone/ (and the
   same on an iPad 13" simulator into build/store_raw/ipad/).
2. Run: python3 tool/store_frames.py
   One storefront: python3 tool/store_frames.py --locale de-DE
   (an app code works too: --locale de writes de-DE)
   which reads build/store_raw_de/ and writes
   store/appstore-localized/de-DE/{iphone-6.9,ipad-13}, leaving store/appstore/ alone.
   Every localized storefront at once: python3 tool/store_frames.py --all-stores
   Directories are named by App Store Connect storefront code, not by ARB code,
   because tool/asc.py looks them up by storefront code.
3. New screenshots for a locale cannot be committed without proofreading its
   caption, so each localized run prints the caption it used.

Captions are set in Tanker, which is Latin only. A caption with a glyph Tanker
cannot draw falls back to the system font for its script (Noto, ITF, Hiragino,
Geeza, Thonburi, SF Pro), and a right-to-left locale is set right-aligned with
the serial on the left, mirrored like the head of a ticket.
"""
import argparse
import os
import sys
from concurrent.futures import ProcessPoolExecutor

from fontTools.ttLib import TTCollection, TTFont
from PIL import Image, ImageChops, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import locales  # noqa: E402  the one list of languages, for RTL and store codes

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'build/store_raw')
OUT = os.path.join(ROOT, 'store')
TANKER = os.path.join(ROOT, 'assets/fonts/Tanker-Regular.otf')

GREEN = (31, 59, 54)      # peacock wall (icon "yellow" variant background)
PAPER = (242, 203, 193)   # cinema ticket paper
SERIAL = (226, 110, 96)   # stamp red, dark-mode tint

SYS = '/System/Library/Fonts/'
SUP = SYS + 'Supplemental/'

# Fallback faces, by script. Each entry is (path, face name fragments, variable
# name). The first face whose name matches a fragment and whose cmap draws every
# glyph of the caption wins; a fragment list of None takes the default face.
# Fragments prefer a bold or black cut, so a fallback keeps Tanker's weight.
FALLBACKS = {
    'deva': [(SUP + 'ITFDevanagari.ttc', ['Bold', 'Demi', 'Book']),
             (SUP + 'Devanagari Sangam MN.ttc', ['Bold', None])],
    'beng': [(SUP + 'Bangla Sangam MN.ttc', ['Bold', None]),
             (SUP + 'Bangla MN.ttc', ['Bold', None])],
    'taml': [(SUP + 'Tamil Sangam MN.ttc', ['Bold', 'MN']),
             (SUP + 'Tamil MN.ttc', ['Bold', None])],
    'telu': [(SUP + 'Telugu Sangam MN.ttc', ['Bold', None]),
             (SYS + 'NotoSansTelugu.ttc', ['Bold', None])],
    'knda': [(SYS + 'NotoSansKannada.ttc', ['Bold', 'SemiBold', 'Medium']),
             (SUP + 'Kannada Sangam MN.ttc', ['Bold', None])],
    'mlym': [(SUP + 'Malayalam Sangam MN.ttc', ['Bold', None]),
             (SUP + 'Malayalam MN.ttc', ['Bold', None])],
    'guru': [(SUP + 'Gurmukhi Sangam MN.ttc', ['Bold', None]),
             (SUP + 'Gurmukhi MN.ttc', ['Bold', None])],
    'gujr': [(SUP + 'Gujarati Sangam MN.ttc', ['Bold', None])],
    'orya': [(SUP + 'Oriya Sangam MN.ttc', ['Bold', None]),
             (SYS + 'NotoSansOriya.ttc', ['Bold', None])],
    # Urdu is normally written in Nastaliq, but Nastaliq cannot share a deck with
    # itself: it is so tall and so sloped that it needs a 25% larger point size
    # and a 1.72 line height, so the cards end up at three different sizes and
    # the deck jumps while swiping. Geeza Pro's Naskh covers every Urdu letter
    # (ٹ ڈ ڑ ں ے ھ ۓ) and the Arabic-Indic digits, so the whole ur deck is set in
    # one face at one size, like every other deck.
    'urdu': [(SYS + 'GeezaPro.ttc', ['Geeza Pro Bold', 'Geeza Pro Regular'])],
    'arab': [(SYS + 'GeezaPro.ttc', ['Geeza Pro Bold', 'Geeza Pro Regular']),
             (SUP + 'NotoNaskhArabic.ttc', ['Bold', None])],
    'hebr': [(SYS + 'ArialHB.ttc', ['Arial Hebrew Bold', 'Arial Hebrew']),
             (SUP + 'NotoSansHebrew.ttf', [None])],
    'hans': [(SYS + 'Hiragino Sans GB.ttc', ['W6', 'W3']),
             (SYS + 'STHeiti Medium.ttc', ['Heiti SC'])],
    'hant': [(SYS + 'STHeiti Medium.ttc', ['Heiti TC']),
             (SYS + 'Hiragino Sans GB.ttc', ['W6'])],
    'kana': [(SYS + 'ヒラギノ角ゴシック W6.ttc', [None]),
             (SYS + 'HiraMinProN-W6.otf', [None])],
    'hangul': [(SYS + 'AppleSDGothicNeo.ttc', ['Neo Bold', 'Neo SemiBold', 'Neo Medium'])],
    'thai': [(SUP + 'Thonburi.ttc', ['Thonburi Bold', 'Thonburi'])],
    # Latin with diacritics, Cyrillic and Greek: SF Pro, the app's own UI face.
    # Bold, not expanded: a condensed fallback keeps the caption near the size
    # Tanker sets, where an expanded one would force a 40% shrink to fit.
    'latin': [(SYS + 'SFNS.ttf', [None], 'Heavy'),
              (SYS + 'HelveticaNeue.ttc', ['Helvetica Neue Bold'])],
}
# Last resort, one face that has been known to draw everything.
FALLBACK_ANY = [(SUP + 'Arial Unicode.ttf', [None])]

# Codepoint ranges per script tag, so a caption is matched to a font by what it
# is written in rather than by its locale.
RANGES = [
    (0x0900, 0x097F, 'deva'), (0x0980, 0x09FF, 'beng'), (0x0A00, 0x0A7F, 'guru'),
    (0x0A80, 0x0AFF, 'gujr'), (0x0B00, 0x0B7F, 'orya'), (0x0B80, 0x0BFF, 'taml'),
    (0x0C00, 0x0C7F, 'telu'), (0x0C80, 0x0CFF, 'knda'), (0x0D00, 0x0D7F, 'mlym'),
    (0x0E00, 0x0E7F, 'thai'), (0x0590, 0x05FF, 'hebr'), (0x0600, 0x06FF, 'arab'),
    (0x0750, 0x077F, 'arab'), (0xFB50, 0xFDFF, 'arab'), (0xFE70, 0xFEFF, 'arab'),
    (0x0400, 0x052F, 'cyrillic'), (0x0370, 0x03FF, 'greek'), (0x1F00, 0x1FFF, 'greek'),
    (0x3040, 0x30FF, 'kana'), (0x4E00, 0x9FFF, 'han'), (0x3400, 0x4DBF, 'han'),
    (0xAC00, 0xD7AF, 'hangul'), (0x1100, 0x11FF, 'hangul'),
]
# Letters only Urdu uses. A caption containing one is set in Nastaliq.
URDU_ONLY = set('ٹڈڑںےھۓ')

# Line height per script, as a multiple of caption size. Latin is the shipped
# 1.02; a script with marks above and below the baseline needs more air or the
# marks collide with the line above.
LINE_HEIGHT = {
    'latin': 1.02, 'cyrillic': 1.08, 'greek': 1.08,
    'deva': 1.34, 'beng': 1.36, 'taml': 1.34, 'telu': 1.42, 'knda': 1.40,
    'mlym': 1.44, 'guru': 1.34, 'gujr': 1.34, 'orya': 1.36,
    'arab': 1.44, 'urdu': 1.44, 'hebr': 1.30,
    'kana': 1.16, 'han': 1.14, 'hangul': 1.18, 'thai': 1.36,
}

# Captions per App Store locale. An unlisted locale falls back to the English
# set, which is the safe default: an English caption over a translated screen
# still reads, a wrong translation does not.
# Last caption is the reach line, kept as "44 languages" everywhere.
CAPTIONS = {
    'en': ['Every film becomes\na ticket stub', 'Hall, seat, show\nand price', 'Your month\nin posters',
           'Your year\nin films', 'New releases,\nevery language', 'See where\nit streams',
           'Share your\nticket', '44 languages'],
    'hi': ['हर फ़िल्म एक\nटिकट बनती है', 'हॉल, सीट, शो\nऔर दाम', 'पोस्टर में\nआपका महीना',
           'फ़िल्मों में\nआपका साल', 'हर भाषा की\nनई फ़िल्में', 'कहाँ स्ट्रीम\nहोती है',
           'टिकट शेयर\nकरें', '44 भाषाएँ'],
    'ta': ['ஒவ்வொரு படமும்\nஒரு டிக்கெட்', 'ஹால், இருக்கை,\nஷோ, விலை', 'சுவரொட்டிகளில்\nஉங்கள் மாதம்',
           'படங்களில்\nஉங்கள் ஆண்டு', 'எல்லா மொழிகளிலும்\nபுதிய படங்கள்', 'எங்கே\nஸ்ட்ரீம் ஆகிறது',
           'டிக்கெட்டைப்\nபகிருங்கள்', '44 மொழிகள்'],
    'te': ['ప్రతి సినిమా\nఒక టికెట్', 'హాల్, సీటు,\nషో, ధర', 'పోస్టర్లలో\nమీ నెల',
           'సినిమాల్లో\nమీ సంవత్సరం', 'అన్ని భాషల్లో\nకొత్త సినిమాలు', 'ఎక్కడ\nస్ట్రీమ్ అవుతుంది',
           'టికెట్\nపంచుకోండి', '44 భాషలు'],
    'bn': ['প্রতিটি ছবি\nএকটি টিকিট', 'হল, সিট,\nশো ও দাম', 'পোস্টারে\nআপনার মাস',
           'ছবিতে\nআপনার বছর', 'সব ভাষায়\nনতুন ছবি', 'কোথায়\nস্ট্রিম হয়',
           'টিকিট\nশেয়ার করুন', '44 ভাষা'],
    'mr': ['प्रत्येक चित्रपट\nएक तिकीट', 'हॉल, सीट,\nशो आणि किंमत', 'पोस्टरमध्ये\nतुमचा महिना',
           'चित्रपटांमध्ये\nतुमचं वर्ष', 'प्रत्येक भाषेत\nनवे चित्रपट', 'कुठे\nस्ट्रीम होतो',
           'तिकीट\nशेअर करा', '44 भाषा'],
    'kn': ['ಪ್ರತಿ ಸಿನಿಮಾವೂ\nಒಂದು ಟಿಕೆಟ್', 'ಹಾಲ್, ಸೀಟ್,\nಶೋ ಮತ್ತು ಬೆಲೆ', 'ಪೋಸ್ಟರ್‌ಗಳಲ್ಲಿ\nನಿಮ್ಮ ತಿಂಗಳು',
           'ಸಿನಿಮಾಗಳಲ್ಲಿ\nನಿಮ್ಮ ವರ್ಷ', 'ಎಲ್ಲ ಭಾಷೆಗಳಲ್ಲಿ\nಹೊಸ ಸಿನಿಮಾಗಳು', 'ಎಲ್ಲಿ\nಸ್ಟ್ರೀಮ್ ಆಗುತ್ತದೆ',
           'ಟಿಕೆಟ್\nಹಂಚಿಕೊಳ್ಳಿ', '44 ಭಾಷೆಗಳು'],
    'ml': ['ഓരോ സിനിമയും\nഒരു ടിക്കറ്റ്', 'ഹാൾ, സീറ്റ്,\nഷോ, വില', 'പോസ്റ്ററുകളിൽ\nനിങ്ങളുടെ മാസം',
           'സിനിമകളിൽ\nനിങ്ങളുടെ വർഷം', 'എല്ലാ ഭാഷകളിലും\nപുതിയ സിനിമകൾ', 'എവിടെ\nസ്ട്രീം ചെയ്യുന്നു',
           'ടിക്കറ്റ്\nപങ്കിടുക', '44 ഭാഷകൾ'],
    'gu': ['દરેક ફિલ્મ\nએક ટિકિટ', 'હોલ, સીટ,\nશો અને ભાવ', 'પોસ્ટરમાં\nતમારો મહિનો',
           'ફિલ્મોમાં\nતમારું વર્ષ', 'દરેક ભાષામાં\nનવી ફિલ્મો', 'ક્યાં\nસ્ટ્રીમ થાય',
           'ટિકિટ\nશેર કરો', '44 ભાષાઓ'],
    'or': ['ପ୍ରତ୍ୟେକ ଫିଲ୍ମ\nଏକ ଟିକେଟ୍', 'ହଲ୍, ସିଟ୍,\nଶୋ ଓ ଦାମ୍', 'ପୋଷ୍ଟରରେ\nଆପଣଙ୍କ ମାସ',
           'ଫିଲ୍ମରେ\nଆପଣଙ୍କ ବର୍ଷ', 'ସବୁ ଭାଷାରେ\nନୂଆ ଫିଲ୍ମ', 'କେଉଁଠି\nଷ୍ଟ୍ରିମ୍ ହୁଏ',
           'ଟିକେଟ୍\nସେୟାର କରନ୍ତୁ', '44 ଭାଷା'],
    'pa': ['ਹਰ ਫ਼ਿਲਮ ਇੱਕ\nਟਿਕਟ ਬਣਦੀ ਹੈ', 'ਹਾਲ, ਸੀਟ,\nਸ਼ੋ ਅਤੇ ਕੀਮਤ', 'ਪੋਸਟਰਾਂ ਵਿੱਚ\nਤੁਹਾਡਾ ਮਹੀਨਾ',
           'ਫ਼ਿਲਮਾਂ ਵਿੱਚ\nਤੁਹਾਡਾ ਸਾਲ', 'ਹਰ ਭਾਸ਼ਾ ਵਿੱਚ\nਨਵੀਆਂ ਫ਼ਿਲਮਾਂ', 'ਕਿੱਥੇ\nਸਟ੍ਰੀਮ ਹੁੰਦੀ',
           'ਟਿਕਟ\nਸਾਂਝੀ ਕਰੋ', '44 ਭਾਸ਼ਾਵਾਂ'],
    'ja': ['観た映画は\nすべて切符に', '劇場、座席、\n上映回、料金', 'ポスターで\n振り返る一か月',
           '映画で振り返る\n一年', 'あらゆる言語の\n新作', 'どこで\n配信中',
           '切符を\nシェア', '44言語'],
    'ko': ['모든 영화가\n티켓이 됩니다', '상영관, 좌석,\n회차, 가격', '포스터로 보는\n한 달',
           '영화로 보는\n한 해', '모든 언어의\n신작', '어디서\n스트리밍',
           '티켓을\n공유', '44개 언어'],
    'zh-Hans': ['每部电影\n都是一张票', '影院、座位\n场次、票价', '用海报\n记录这个月',
                '用电影\n记录这一年', '各语种\n新片', '在哪里\n可以看',
                '分享你的\n电影票', '44 种语言'],
    'zh-Hant': ['每部電影\n都是一張票', '影院、座位\n場次、票價', '用海報\n記錄這個月',
                '用電影\n記錄這一年', '各語言\n新片', '在哪裡\n可以看',
                '分享你的\n電影票', '44 種語言'],
    'de-DE': ['Jeder Film wird\nein Ticket', 'Saal, Sitz,\nVorstellung, Preis', 'Dein Monat\nin Postern',
              'Dein Jahr\nin Filmen', 'Neue Filme,\njede Sprache', 'Wo er\nstreamt',
              'Teil dein\nTicket', '44 Sprachen'],
    'fr-FR': ['Chaque film\ndevient un ticket', 'Salle, siège,\nséance et prix', 'Ton mois\nen affiches',
              'Ton année\nen films', 'Des sorties\ndans chaque langue', 'Où le\nregarder',
              'Partage\nton ticket', '44 langues'],
    'it': ['Ogni film diventa\nun biglietto', 'Sala, posto,\nspettacolo, prezzo', 'Il tuo mese\nin locandine',
           'Il tuo anno\nin film', 'Novità in\nogni lingua', 'Dove\nsi vede',
           'Condividi\nil biglietto', '44 lingue'],
    'nl': ['Elke film wordt\neen ticket', 'Zaal, stoel,\nvoorstelling, prijs', 'Je maand\nin posters',
           'Je jaar\nin films', 'Nieuw, in\nelke taal', 'Waar je\nhet streamt',
           'Deel je\nticket', '44 talen'],
    'pl': ['Każdy film staje się\nbiletem', 'Sala, miejsce,\nseans i cena', 'Twój miesiąc\nna plakatach',
           'Twój rok\nw filmach', 'Nowości w\nkażdym języku', 'Gdzie\nobejrzysz',
           'Podziel się\nbiletem', '44 języki'],
    'cs': ['Každý film se stane\nlístkem', 'Sál, sedadlo,\nčas a cena', 'Tvůj měsíc\nna plakátech',
           'Tvůj rok\nve filmech', 'Novinky v\nkaždém jazyce', 'Kde\nse hraje',
           'Sdílej\nlístek', '44 jazyků'],
    'sk': ['Každý film sa stane\nlístkom', 'Sála, sedadlo,\nčas a cena', 'Tvoj mesiac\nna plagátoch',
           'Tvoj rok\nvo filmoch', 'Novinky v\nkaždom jazyku', 'Kde\nsa hrá',
           'Zdieľaj\nlístok', '44 jazykov'],
    'sl': ['Vsak film postane\nvstopnica', 'Dvorana, sedež,\ntermin in cena', 'Tvoj mesec\nna plakatih',
           'Tvoje leto\nv filmih', 'Novosti v\nvsakem jeziku', 'Kje\nse predvaja',
           'Deli\nvstopnico', '44 jezikov'],
    'hr': ['Svaki film postaje\nulaznica', 'Dvorana, sjedalo,\ntermin i cijena', 'Tvoj mjesec\nna plakatima',
           'Tvoja godina\nu filmovima', 'Novo na\nsvakom jeziku', 'Gdje se\nprikazuje',
           'Podijeli\nulaznicu', '44 jezika'],
    'ro': ['Fiecare film devine\nun bilet', 'Sală, loc,\nspectacol, preț', 'Luna ta\nîn afișe',
           'Anul tău\nîn filme', 'Noutăți în\norice limbă', 'Unde se\npoate vedea',
           'Împărtășește\nbiletul', '44 de limbi'],
    'hu': ['Minden film\njeggyé válik', 'Terem, hely,\nelőadás, ár', 'A hónapod\nplakátokon',
           'Az éved\nfilmekben', 'Újdonságok\nminden nyelven', 'Hol\nnézhető',
           'Oszd meg\na jegyed', '44 nyelv'],
    'fi': ['Jokainen elokuva\non lippu', 'Sali, paikka,\nnäytös ja hinta', 'Kuukautesi\njulisteina',
           'Vuotesi\nelokuvina', 'Uutuudet\njoka kielellä', 'Mistä sen\nvoi katsoa',
           'Jaa\nlippusi', '44 kieltä'],
    'sv': ['Varje film blir\nen biljett', 'Salong, plats,\nföreställning, pris', 'Din månad\ni affischer',
           'Ditt år\ni filmer', 'Nytt på\nvarje språk', 'Var den\nströmmas',
           'Dela din\nbiljett', '44 språk'],
    'da': ['Hver film bliver\nen billet', 'Sal, plads,\nvisning og pris', 'Din måned\ni plakater',
           'Dit år\ni film', 'Nyt på\nhvert sprog', 'Hvor den\nstreames',
           'Del din\nbillet', '44 sprog'],
    'no': ['Hver film blir\nen billett', 'Sal, sete,\nforestilling, pris', 'Måneden din\ni plakater',
           'Året ditt\ni filmer', 'Nytt på\nhvert språk', 'Hvor den\nstrømmes',
           'Del\nbilletten', '44 språk'],
    'ca': ['Cada pel·lícula és\nuna entrada', 'Sala, seient,\nsessió i preu', 'El teu mes\nen cartells',
           'El teu any\nen pel·lícules', 'Estrenes en\ntots els idiomes', 'On es\npot veure',
           'Comparteix\nl’entrada', '44 idiomes'],
    'es-ES': ['Cada película\nse vuelve una entrada', 'Sala, butaca,\nsesión y precio', 'Tu mes\nen carteles',
              'Tu año\nen películas', 'Estrenos en\ntodos los idiomas', 'Dónde se\npuede ver',
              'Comparte tu\nentrada', '44 idiomas'],
    'pt-BR': ['Cada filme vira\num ingresso', 'Sala, poltrona,\nsessão e preço', 'Seu mês\nem cartazes',
              'Seu ano\nem filmes', 'Lançamentos em\ntodos os idiomas', 'Onde\nassistir',
              'Compartilhe seu\ningresso', '44 idiomas'],
    'pt-PT': ['Cada filme torna-se\num bilhete', 'Sala, lugar,\nsessão e preço', 'O teu mês\nem cartazes',
              'O teu ano\nem filmes', 'Estreias em\ntodas as línguas', 'Onde está\nem exibição',
              'Partilha o teu\nbilhete', '44 idiomas'],
    'id': ['Setiap film jadi\nsebuah tiket', 'Studio, kursi,\njadwal, harga', 'Bulanmu\ndi poster',
           'Tahunmu\ndi film', 'Rilis baru,\nsemua bahasa', 'Di mana\nstreaming',
           'Bagikan\ntiketmu', '44 bahasa'],
    'ms': ['Setiap filem jadi\ntiket', 'Panggung, tempat,\ntayangan, harga', 'Bulan anda\ndalam poster',
           'Tahun anda\ndalam filem', 'Filem baharu,\nsemua bahasa', 'Di mana\nboleh tonton',
           'Kongsi\ntiket anda', '44 bahasa'],
    'vi': ['Mỗi phim thành\nmột tấm vé', 'Rạp, ghế,\nsuất, giá', 'Tháng của bạn\nqua poster',
           'Năm của bạn\nqua phim', 'Phim mới, đủ\nmọi ngôn ngữ', 'Xem ở\nđâu',
           'Chia sẻ\nvé', '44 ngôn ngữ'],
    'th': ['ทุกหนังกลายเป็น\nตั๋วหนึ่งใบ', 'โรง ที่นั่ง\nรอบ ราคา', 'เดือนของคุณ\nในโปสเตอร์',
           'ปีของคุณ\nในหนัง', 'หนังใหม่\nทุกภาษา', 'สตรีม\nที่ไหน',
           'แชร์ตั๋ว\nของคุณ', '44 ภาษา'],
    'tr': ['Her film bir\nbilete dönüşür', 'Salon, koltuk,\nseans ve fiyat', 'Ayın\nafişlerde',
           'Yılın\nfilmlerde', 'Her dilde\nyeni filmler', 'Nerede\nizlenir',
           'Biletini\npaylaş', '44 dil'],
    'ru': ['Любой фильм —\nэто билет', 'Зал, место,\nсеанс и цена', 'Твой месяц\nв афишах',
           'Твой год\nв кино', 'Новинки на\nлюбом языке', 'Где\nсмотреть',
           'Поделись\nбилетом', '44 языка'],
    'uk': ['Кожен фільм —\nце квиток', 'Зала, місце,\nсеанс і ціна', 'Твій місяць\nв афішах',
           'Твій рік\nу кіно', 'Новинки\nвсіма мовами', 'Де\nдивитися',
           'Поділись\nквитком', '44 мови'],
    'el': ['Κάθε προβολή\nένα εισιτήριο', 'Αίθουσα, θέση,\nπροβολή, τιμή', 'Ο μήνας σου\nσε αφίσες',
           'Η χρονιά σου\nσε ταινίες', 'Νέες ταινίες σε\nκάθε γλώσσα', 'Πού\nπαίζεται',
           'Μοιράσου\nτο εισιτήριο', '44 γλώσσες'],
    'he': ['כל סרט הופך\nלכרטיס', 'אולם, מושב,\nהקרנה ומחיר', 'החודש שלך\nבפוסטרים',
           'השנה שלך\nבסרטים', 'חדשים בכל\nשפה', 'איפה\nזה זורם',
           'שתף את\nהכרטיס', '44 שפות'],
    # Arabic storefronts print Arabic-Indic digits: Geeza Pro has no Latin ones,
    # and ٤٤ لغة reads as Arabic rather than as a barcode.
    'ar': ['كل فيلم يصبح\nتذكرة', 'القاعة والمقعد\nوالعرض والسعر', 'شهرك\nفي الملصقات',
           'عامك\nفي الأفلام', 'أفلام جديدة\nبكل لغة', 'أين\nيُبث',
           'شارك\nتذكرتك', '٤٤ لغة'],
    'ur': ['ہر فلم ایک\nٹکٹ بنتی ہے', 'ہال، نشست،\nشو اور قیمت', 'پوسٹروں میں\nآپ کا مہینہ',
           'فلموں میں\nآپ کا سال', 'ہر زبان میں\nنئی فلمیں', 'کہاں\nاسٹریم ہوتی ہے',
           'ٹکٹ\nشیئر کریں', '۴۴ زبانیں'],
}
# Storefronts that share another storefront's language. Reusing the copy keeps a
# single line to proofread per language.
CAPTION_ALIAS = {
    'en-US': 'en', 'en-GB': 'en', 'en-AU': 'en', 'en-CA': 'en',
    'es-MX': 'es-ES', 'fr-CA': 'fr-FR',
}

# (capture, caption). Order is the store order.
SHOTS = [
    ('01_home', 0),
    ('02_ticket', 1),
    ('06_calendar', 2),
    ('07_stats', 3),
    ('10_films_new', 4),
    ('11_film_page', 5),
    ('04_share', 6),
    ('13_home_hi_dark', 7),
]
# On iPad the ticket screen is stretched wide; the poster grid uses the width.
IPAD_SWAP = {'02_ticket': ('09_stubs_grid', 0)}
# Blank status-bar band at the top of each capture.
TOP_CROP = {'iphone': 150, 'ipad': 60}

# name: (source, canvas w, h, side margin, caption size, corner radius)
TARGETS = {
    'appstore/iphone-6.9': ('iphone', 1320, 2868, 110, 118, 64),
    'appstore/iphone-6.5': ('iphone', 1284, 2778, 107, 115, 62),
    'appstore/ipad-13': ('ipad', 2064, 2752, 190, 132, 44),
    'play/phone': ('iphone', 1080, 1920, 150, 84, 44),
    'play/tablet': ('ipad', 1440, 2560, 120, 104, 32),
}
# A localized run writes the two App Store sizes: Play is served from the English
# set, and the same two capture folders produce both.
LOCAL_TARGETS = ['appstore/iphone-6.9', 'appstore/ipad-13']

# ---------------------------------------------------------------------------
# Fonts

_CMAP = {}
_CHOSEN = {}


def _cmap(path: str, index: int) -> dict:
    key = (path, index)
    if key not in _CMAP:
        try:
            if path.endswith('.ttc'):
                face = TTCollection(path).fonts[index]
            else:
                face = TTFont(path, fontNumber=index, lazy=True)
            _CMAP[key] = face.getBestCmap() or {}
        except Exception:  # unreadable collection: treat as no coverage
            _CMAP[key] = {}
    return _CMAP[key]


def face_covers(path: str, index: int, chars) -> bool:
    """True when this face's cmap draws every character (no .notdef boxes)."""
    cmap = _cmap(path, index)
    return bool(cmap) and all(ord(c) in cmap for c in chars)


def missing_glyphs(path: str, index: int, text: str) -> str:
    cmap = _cmap(path, index)
    return ''.join(sorted({c for c in text if not c.isspace() and ord(c) not in cmap}))


def _faces(path: str) -> list[tuple[int, str]]:
    """(index, full face name) for every face in a font file."""
    try:
        if path.endswith('.ttc'):
            return [(i, f['name'].getDebugName(4) or '') for i, f in enumerate(TTCollection(path).fonts)]
        return [(0, TTFont(path, fontNumber=0, lazy=True)['name'].getDebugName(4) or '')]
    except Exception:
        return []


def _load(path: str, index: int, size: int, variation=None) -> ImageFont.FreeTypeFont | None:
    try:
        font = ImageFont.truetype(path, size, index=index, layout_engine=ImageFont.Layout.RAQM)
    except OSError:
        return None
    if variation:
        try:
            font.set_variation_by_name(variation)
        except Exception:
            pass
    return font


def _pick(candidates, text: str, size: int):
    chars = {c for c in text if not c.isspace()}
    for entry in candidates:
        path, hints = entry[0], entry[1]
        variation = entry[2] if len(entry) > 2 else None
        if not os.path.exists(path):
            continue
        faces = _faces(path)
        ordered = []
        for hint in hints:
            if hint is None:
                continue
            ordered += [i for i, name in faces if hint.lower() in name.lower()]
        ordered += [i for i, _ in faces]  # then any face that covers
        for index in dict.fromkeys(ordered):
            if not face_covers(path, index, chars):
                continue
            font = _load(path, index, size, variation)
            if font is None:
                continue
            return font, path, index
    return None, None, None


def script_of(text: str) -> list[str]:
    """Script tags present in the text, Han folded to the locale's variant later."""
    tags = []
    for ch in text:
        for lo, hi, tag in RANGES:
            if lo <= ord(ch) <= hi:
                if tag not in tags:
                    tags.append(tag)
                break
    if not tags:
        return ['latin']
    # Latin runs ride along with every script; only a pure-Latin caption needs them.
    return tags


def chain_for(text: str, script: str | None = None) -> list[str]:
    tags = script_of(text)
    if script:
        tags = [script] + [t for t in tags if t != script]
    if any(c in URDU_ONLY for c in text) and 'arab' in tags:
        tags = ['urdu'] + [t for t in tags if t != 'arab']
    order = []
    for tag in tags:
        key = tag
        if tag == 'han':
            key = script or 'hans'
        if key in FALLBACKS and key not in order:
            order.append(key)
    if 'cyrillic' in tags or 'greek' in tags:
        order.append('latin')
    return order + ['latin']


def font_for(text: str, size: int, script: str | None = None) -> ImageFont.FreeTypeFont:
    """Tanker when it can draw the whole caption, the script fallback otherwise.

    `script` names a writing system the text cannot reveal on its own: 'hans' or
    'hant' for Chinese, since Simplified and Traditional share codepoints.
    """
    key = (text, size, script)
    if key in _CHOSEN:
        return _CHOSEN[key][0]
    chosen = None
    if face_covers(TANKER, 0, {c for c in text if not c.isspace()}):
        chosen = (_load(TANKER, 0, size), TANKER, 0)
    if chosen is None:
        for tag in chain_for(text, script):
            chosen = _pick(FALLBACKS.get(tag, []), text, size)
            if chosen[0] is not None:
                break
    if chosen is None or chosen[0] is None:
        chosen = _pick(FALLBACK_ANY, text, size, )
    if chosen is None or chosen[0] is None:
        chosen = (_load(TANKER, 0, size), TANKER, 0)
    _CHOSEN[key] = chosen
    return chosen[0]


def font_source(text: str, size: int, script: str | None = None) -> tuple[str, int]:
    """Path and face index the caption actually renders with (after font_for)."""
    font_for(text, size, script)
    _, path, index = _CHOSEN[(text, size, script)]
    return path, index


def line_height(text: str, size: int) -> int:
    tags = script_of(text)
    mult = max((LINE_HEIGHT.get(t, 1.02) for t in tags), default=1.02)
    if any(c in URDU_ONLY for c in text):
        mult = LINE_HEIGHT['urdu']
    return int(size * mult)


# ---------------------------------------------------------------------------
# Locale helpers


def captions_for(locale: str) -> list[str]:
    if locale in CAPTIONS:
        return CAPTIONS[locale]
    alias = CAPTION_ALIAS.get(locale)
    if alias and alias in CAPTIONS:
        return CAPTIONS[alias]
    return CAPTIONS['en']


def app_code(locale: str) -> str:
    return locales.STORE_TO_APP.get(locale, 'en')


def rtl_locale(locale: str) -> bool:
    return locales.rtl(app_code(locale))


def cjk_script(locale: str) -> str | None:
    code = app_code(locale)
    return {'zh': 'hans', 'zh_Hant': 'hant', 'ja': 'kana'}.get(code)


# No script gets a size boost any more. A boost applied to the captions that
# happen to contain one letter and not to the rest is what broke the Urdu deck:
# seven cards at 147 and one at 118. If a script looks small at the shared deck
# size, change the face, not the size.
SIZE_BOOST = {}


def display_size(caption: str, cap_size: int) -> int:
    """The size the caption starts at, before any shrink to fit the width."""
    for tag, boost in SIZE_BOOST.items():
        if tag == 'urdu' and any(c in URDU_ONLY for c in caption):
            return int(cap_size * boost)
    return cap_size


def upper_case(caption: str, locale: str) -> str:
    """Uppercase for display, with Turkish i/ı casings kept correct."""
    if app_code(locale) == 'tr':
        return caption.replace('i', 'İ').replace('ı', 'I').upper()
    return caption.upper()


# ---------------------------------------------------------------------------
# Frame


def grain(size, base, sigma=5):
    """Flat colour with fine monochrome noise (about +-5 levels), so it does not band."""
    noise = Image.effect_noise(size, sigma).convert('RGB')
    return ImageChops.add(Image.new('RGB', size, base), noise, 1.0, -128)


def rounded(im, radius):
    """Anti-aliased rounded corners (mask drawn at 4x, then scaled down)."""
    w, h = im.size
    m = Image.new('L', (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=radius * 4, fill=255)
    m = m.resize((w, h), Image.LANCZOS)
    out = Image.new('RGBA', (w, h))
    out.paste(im.convert('RGBA'), (0, 0), m)
    return out


def caption_layout(W, H, margin, cap_size, caption, serial, sw, rtl=False, locale='en'):
    """Where every line and the serial sit. Shared by frame() and check_captions.py.

    Left-aligned to the screen's left edge for a left-to-right locale; mirrored to
    the right edge for an RTL one, with the serial on the left, so the block reads
    like the head of a ticket in both directions.
    """
    probe = ImageDraw.Draw(Image.new('RGB', (1, 1)))
    direction = 'rtl' if rtl else None  # None lets Raqm read the direction off the text
    script = cjk_script(locale)
    font = font_for(caption, cap_size, script)
    lines = upper_case(caption, locale).split('\n')
    x0 = (W - sw) // 2
    small = ImageFont.truetype(TANKER, int(cap_size * 0.42))  # serial keeps its size

    # Shrink the caption until every line clears the serial by 6% of the width.
    s_w = probe.textbbox((0, 0), serial, font=small)[2]
    while max(probe.textbbox((0, 0), ln, font=font, direction=direction)[2] for ln in lines) \
            > sw - s_w - int(W * 0.06) and cap_size > 24:
        cap_size -= 2
        font = font_for(caption, cap_size, script)

    lh = line_height(upper_case(caption, locale), cap_size)
    top = int(H * 0.055)
    boxes = [probe.textbbox((0, 0), line, font=font, direction=direction) for line in lines]
    # The shipped leading is the floor; a script whose accents run past it, or a
    # line ending in a comma above a capital with an accent, opens the leading
    # just enough that no ink touches the next line.
    if len(boxes) > 1:
        need = max(b[3] - nb[1] for b, nb in zip(boxes, boxes[1:]))
        lh = max(lh, need + max(2, int(cap_size * 0.03)))
    placed = []
    for i, line in enumerate(lines):
        l, t, r, b = boxes[i]
        # Left-aligned: draw at the block's left edge, exactly as shipped.
        # Right-aligned: the same box mirrored so its ink ends at the right edge.
        x = x0 + sw - r if rtl else x0
        placed.append((line, x, top + i * lh, (l, t, r, b)))
    sl, st, sr, sb = probe.textbbox((0, 0), serial, font=small)
    cap_top = probe.textbbox((x0, top), lines[0], font=font, direction=direction)[1]
    sx = x0 - sl if rtl else x0 + sw - sr
    sy = cap_top - st
    return {
        'font': font, 'lines': placed, 'lh': lh, 'top': top, 'x0': x0, 'sw': sw,
        'cap_size': cap_size, 'cap_h': lh * len(lines), 'direction': direction,
        'serial': (serial, sx, sy, (sl, st, sr, sb), small), 'rtl': rtl,
    }


def caption_ink_box(layout):
    """Ink bounds of the caption lines and of the serial, for overlap checks."""
    boxes = [(x + b[0], y + b[1], x + b[2], y + b[3]) for _, x, y, b in layout['lines']]
    _, sx, sy, b, _ = layout['serial']
    serial = (sx + b[0], sy + b[1], sx + b[2], sy + b[3])
    return boxes, serial


def open_shot(src, kind=None):
    """The capture, with its blank status-bar band cut off."""
    if src is None:  # caption card: keep the real geometry with a blank screen
        return Image.new('RGB', (1320, 2718), (36, 21, 23))
    shot = Image.open(src).convert('RGB')
    kind = kind or os.path.basename(os.path.dirname(src))
    return shot.crop((0, TOP_CROP[kind], shot.width, shot.height))


def layout_for(shot, target, caption, serial, locale='en', size=None):
    """Caption block and screen placement for one framed shot.

    Shared with tool/check_captions.py, so the checks measure the geometry that
    ships rather than a copy of it.
    """
    kind, W, H, margin, cap_size, radius = TARGETS[target]
    cap_size = display_size(caption, size or cap_size)
    top = int(H * 0.055)
    text = upper_case(caption, locale)
    # Room for the screen comes from the caption size that was asked for, not the
    # shrunk one, as shipped.
    reserved = line_height(text, cap_size) * len(text.split('\n'))
    avail_h = H - top - reserved - int(H * 0.04) - int(H * 0.035)
    sw = W - 2 * margin
    sh = round(shot.height * sw / shot.width)
    if sh > avail_h:  # tall capture: fit height instead, stay centred
        sh = avail_h
        sw = round(shot.width * sh / shot.height)
    L = caption_layout(W, H, margin, cap_size, caption, serial, sw,
                       rtl=rtl_locale(locale), locale=locale)
    L.update({'W': W, 'H': H, 'margin': margin, 'radius': radius, 'target': target,
              'sw': sw, 'sh': sh, 'reserved': reserved,
              # A block whose leading opened up needs its extra height back, or
              # the screen would ride up under the caption.
              'y0': top + max(reserved, L['lh'] * len(text.split('\n'))) + int(H * 0.04)})
    return L


_DECK = {}


def deck_size(locale, target, raw_dir=None, kind=None):
    """One caption size for the whole deck of eight.

    A per-caption shrink would set the long captions smaller than the short ones,
    and the type would jump while swiping. The deck takes the size every caption
    fits at, so all eight match. English never shrinks, so it stays as shipped.
    """
    key = (locale, target, raw_dir)
    if key in _DECK:
        return _DECK[key]
    kind = kind or TARGETS[target][0]
    src = None
    if raw_dir:
        first = shots_for(locale, kind)[0][1]
        path = os.path.join(raw_dir, kind, first + '.png')
        if os.path.exists(path):
            src = path
    shot = open_shot(src, kind)
    fit = TARGETS[target][4]
    for _, _, caption in shots_for(locale, kind):
        fit = min(fit, layout_for(shot, target, caption, 'NO. 0001', locale, size=fit)['cap_size'])
    _DECK[key] = fit
    return fit


def frame(src, target, caption, serial, locale='en', size=None):
    kind, W, H, margin, cap_size, radius = TARGETS[target]
    canvas = grain((W, H), GREEN)
    d = ImageDraw.Draw(canvas)
    shot = open_shot(src, kind)
    L = layout_for(shot, target, caption, serial, locale, size=size)

    for line, x, y, _ in L['lines']:
        d.text((x, y), line, font=L['font'], fill=PAPER, direction='rtl' if L['rtl'] else None)
    text, sx, sy, _, small = L['serial']
    d.text((sx, sy), text, font=small, fill=SERIAL)

    shot = shot.resize((L['sw'], L['sh']), Image.LANCZOS)
    canvas.paste(rounded(shot, radius), (L['x0'], L['y0']), rounded(shot, radius))
    return canvas


def feature_graphic():
    W, H = 1024, 500
    canvas = grain((W, H), GREEN)
    d = ImageDraw.Draw(canvas)
    d.text((64, 150), 'TALKIES', font=ImageFont.truetype(TANKER, 132), fill=PAPER)
    body = ImageFont.truetype(TANKER, 40)
    d.text((68, 300), 'EVERY FILM YOU WATCH', font=body, fill=SERIAL)
    d.text((68, 344), 'BECOMES A TICKET STUB', font=body, fill=SERIAL)
    # The real ticket screen, bleeding off the right and bottom edges.
    shot = Image.open(os.path.join(RAW, 'iphone/02_ticket.png')).convert('RGB').crop((0, 150, 1320, 2868))
    sw = 400
    shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
    r = rounded(shot, 26)
    canvas.paste(r, (W - sw - 60, 56), r)
    return canvas


def shots_for(locale: str, kind: str):
    caps = captions_for(locale)
    out = []
    for i, (cap_name, cap_index) in enumerate(SHOTS, 1):
        if kind == 'ipad':
            cap_name, cap_index = IPAD_SWAP.get(cap_name, (cap_name, cap_index))
        out.append((i, cap_name, caps[cap_index]))
    return out


def render_locale(job):
    """One (locale, target) pass: every shot for a locale at one canvas size."""
    locale, target, raw_dir, dest = job
    kind = TARGETS[target][0]
    os.makedirs(dest, exist_ok=True)
    # English keeps the per-caption shrink it shipped with; each new deck is set
    # at one size so the type does not jump between shots while swiping.
    size = None if locale == 'en' else deck_size(locale, target, raw_dir, kind)
    for i, cap_name, caption in shots_for(locale, kind):
        src = os.path.join(raw_dir, kind, cap_name + '.png')
        im = frame(src, target, caption, f'NO. {i:04d}', locale=locale, size=size)
        im.save(os.path.join(dest, f"{i:02d}_{cap_name.split('_', 1)[1]}.png"), optimize=True)
    return locale, dest, len(SHOTS)


def stores_for(locale: str) -> list[str]:
    """The App Store Connect codes one language writes to.

    A store code is itself; an app code (de, zh, pt, es, fr, en) is every
    storefront that language serves, since asc.py and the folder names use the
    storefront code and never the ARB code.
    """
    if locale in locales.STORE_TO_APP:
        return [locale]
    if locale in locales.BY_CODE:
        return list(locales.BY_CODE[locale][1])
    raise SystemExit(f'unknown locale {locale!r}: not an app code or a store code')


def main(argv=None):
    p = argparse.ArgumentParser(description='Frame raw captures as store screenshots.')
    p.add_argument('--locale', default='en',
                   help='app code (de, zh, es) or store code (de-DE, zh-Hans): reads '
                        'build/store_raw_<locale>/ and writes store/appstore-localized/<store code>/ '
                        '(default en: build/store_raw, store/appstore)')
    p.add_argument('--all-stores', action='store_true',
                   help='every non-English storefront that has captions, in one pass')
    p.add_argument('--raw', help='override the raw capture folder')
    p.add_argument('--out', help='override the output folder')
    p.add_argument('--jobs', type=int, default=4, help='parallel (locale, size) renders (default 4)')
    args = p.parse_args(argv)

    english = args.locale == 'en' and not args.all_stores
    if english:
        args.jobs = 1  # the English pass owns the shipped bytes: one process, shipped order
        codes = ['en']
    elif args.all_stores:
        # English storefronts are served from store/appstore by asc.py, so they
        # are not duplicated here.
        codes = [c for c in locales.store_codes() if not c.startswith('en')]
    else:
        codes = stores_for(args.locale)

    raw_dir = args.raw or (RAW if english else os.path.join(ROOT, f'build/store_raw_{args.locale}'))
    targets = list(TARGETS) if english else LOCAL_TARGETS
    if not os.path.isdir(raw_dir):
        raise SystemExit(f'no raw captures at {raw_dir}: capture them first '
                         f'(see the docstring), then rerun.')

    def out_for(code):
        if args.out:
            return os.path.join(args.out, code) if not english else args.out
        return OUT if english else os.path.join(OUT, 'appstore-localized', code)

    print(f'{args.locale}: {raw_dir} -> '
          f'{os.path.relpath(OUT if english else os.path.join(OUT, "appstore-localized"), ROOT)}'
          f'  ({len(codes)} storefront{"s" if len(codes) > 1 else ""})')
    for code in codes:
        if not captions_for(code):
            raise SystemExit(f'no captions for {code}')
        if code not in CAPTIONS and code not in CAPTION_ALIAS:
            print(f'  no captions for {code}: falling back to the English set')
        if len(codes) == 1:
            for i, line in enumerate(captions_for(code), 1):
                path, index = font_source(upper_case(line, code), TARGETS['appstore/iphone-6.9'][4],
                                          cjk_script(code))
                print(f'  {i}. {line.replace(chr(10), " / "):44} {os.path.basename(path)}#{index}')

    jobs = [(code, t, raw_dir, os.path.join(out_for(code), t.split('/', 1)[1]) if not english
             else os.path.join(out_for(code), t))
            for code in codes for t in targets]
    if args.jobs > 1 and len(jobs) > 1:
        with ProcessPoolExecutor(max_workers=args.jobs) as pool:
            for locale, dest, n in pool.map(render_locale, jobs):
                print(' ', os.path.relpath(dest, ROOT), n)
    else:
        for job in jobs:
            locale, dest, n = render_locale(job)
            print(' ', os.path.relpath(dest, ROOT), n)

    if english:
        os.makedirs(os.path.join(OUT, 'play'), exist_ok=True)
        feature_graphic().save(os.path.join(OUT, 'play/feature-graphic.png'), optimize=True)
        icon = Image.open(os.path.join(ROOT, 'assets/icons/big-t-master-1024.png')).convert('RGB')
        icon.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, 'play/icon-512.png'), optimize=True)
        print('feature graphic, icon')


if __name__ == '__main__':
    main()
