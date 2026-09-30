import 'package:flutter/widgets.dart';

import 'labels_more.dart';

/// Names for catalog codes (languages, genres, services, ...). Kept out of the
/// ARB files because they are data vocabulary, not UI copy.
/// Each entry: code -> [English, Hindi].
const _langs = {
  'hi': ['Hindi', 'हिन्दी'], 'ta': ['Tamil', 'तमिल'], 'te': ['Telugu', 'तेलुगु'], 'ml': ['Malayalam', 'मलयालम'], //
  'kn': ['Kannada', 'कन्नड़'], 'bn': ['Bengali', 'बांग्ला'], 'mr': ['Marathi', 'मराठी'], 'pa': ['Punjabi', 'पंजाबी'],
  'gu': ['Gujarati', 'गुजराती'], 'or': ['Odia', 'ओड़िया'], 'as': ['Assamese', 'असमिया'], 'bho': ['Bhojpuri', 'भोजपुरी'],
  'ur': ['Urdu', 'उर्दू'], 'en': ['English', 'अंग्रेज़ी'], 'tcy': ['Tulu', 'तुलु'], 'kok': ['Konkani', 'कोंकणी'],
  'sa': ['Sanskrit', 'संस्कृत'], 'mni': ['Manipuri', 'मणिपुरी'], 'raj': ['Rajasthani', 'राजस्थानी'],
  'bgc': ['Haryanvi', 'हरियाणवी'],
  'mai': ['Maithili', 'मैथिली'],
  'ne': ['Nepali', 'नेपाली'],
  'si': ['Sinhala', 'सिंहली'],
  'ko': ['Korean', 'कोरियाई'],
  'ja': ['Japanese', 'जापानी'],
  'zh': ['Chinese', 'चीनी'],
  'yue': ['Cantonese', 'कैंटोनीज़'],
  'fr': ['French', 'फ़्रेंच'], 'es': ['Spanish', 'स्पैनिश'], 'de': ['German', 'जर्मन'], 'it': ['Italian', 'इतालवी'],
  'ru': ['Russian', 'रूसी'], 'fa': ['Persian', 'फ़ारसी'], 'ar': ['Arabic', 'अरबी'], 'tr': ['Turkish', 'तुर्की'],
  'th': ['Thai', 'थाई'], 'pt': ['Portuguese', 'पुर्तगाली'], 'sv': ['Swedish', 'स्वीडिश'], 'da': ['Danish', 'डेनिश'],
  'no': ['Norwegian', 'नॉर्वेजियन'], 'nl': ['Dutch', 'डच'], 'pl': ['Polish', 'पोलिश'], 'fi': ['Finnish', 'फ़िनिश'],
  'he': ['Hebrew', 'हिब्रू'], 'cs': ['Czech', 'चेक'],
};

const _genres = {
  'action': ['Action', 'एक्शन'], 'drama': ['Drama', 'ड्रामा'], 'comedy': ['Comedy', 'कॉमेडी'], //
  'romance': ['Romance', 'रोमांस'], 'thriller': ['Thriller', 'थ्रिलर'], 'horror': ['Horror', 'हॉरर'],
  'crime': ['Crime', 'क्राइम'], 'musical': ['Musical', 'संगीतमय'], 'family': ['Family', 'पारिवारिक'],
  'fantasy': ['Fantasy', 'फ़ैंटेसी'], 'scifi': ['Sci-fi', 'साइंस फ़िक्शन'], 'historical': ['Historical', 'ऐतिहासिक'],
  'biography': ['Biopic', 'बायोपिक'],
  'animation': ['Animation', 'एनिमेशन'],
  'documentary': ['Documentary', 'डॉक्यूमेंट्री'],
  'war': ['War', 'युद्ध'],
  'mystery': ['Mystery', 'रहस्य'],
  'sports': ['Sports', 'खेल'],
  'adventure': ['Adventure', 'रोमांच'],
  'spy': ['Spy', 'जासूसी'], 'political': ['Political', 'राजनीतिक'], 'legal': ['Courtroom', 'अदालती'],
  'coming_of_age': ['Coming of age', 'किशोरावस्था'], 'superhero': ['Superhero', 'सुपरहीरो'],
  'mythology': ['Mythology', 'पौराणिक'], 'western': ['Western', 'वेस्टर्न'],
};

const _ott = {
  'netflix': 'Netflix', 'prime': 'Prime Video', 'jiohotstar': 'JioHotstar', 'sonyliv': 'SonyLIV', 'zee5': 'ZEE5', //
  'aha': 'aha', 'sunnxt': 'Sun NXT', 'mxplayer': 'MX Player', 'appletv': 'Apple TV+', 'hoichoi': 'hoichoi',
  'erosnow': 'Eros Now', 'altbalaji': 'ALTBalaji', 'manoramamax': 'ManoramaMAX', 'mubi': 'MUBI',
  'lionsgateplay': 'Lionsgate Play', 'chaupal': 'Chaupal', 'planetmarathi': 'Planet Marathi',
};

/// Show slots, as printed on Indian hall tickets.
const showKeys = ['morning', 'matinee', 'evening', 'night', 'late'];
const _shows = {
  'morning': ['Morning show', 'मॉर्निंग शो'], 'matinee': ['Matinee', 'मैटिनी'], //
  'evening': ['Evening show', 'इवनिंग शो'], 'night': ['Night show', 'नाइट शो'], 'late': ['Late night', 'लेट नाइट'],
};

const formatKeys = ['2d', '3d', 'imax', '4dx', 'screenx', 'dolby', 'ice', 'mx4d', 'pxl', 'onyx'];
const _formats = {
  '2d': '2D', '3d': '3D', 'imax': 'IMAX', '4dx': '4DX', 'screenx': 'ScreenX', 'dolby': 'Dolby Cinema', //
  'ice': 'ICE', 'mx4d': 'MX4D', 'pxl': 'P[XL]', 'onyx': 'Onyx LED',
};

/// Seat classes: old single-screen names first, multiplex names after.
const seatClasses = ['Balcony', 'Dress Circle', 'Box', 'Stall', 'Recliner', 'Gold', 'Premium', 'Executive', 'Normal'];

const _countries = {
  'IN': ['India', 'भारत'], 'US': ['United States', 'अमेरिका'], 'GB': ['United Kingdom', 'ब्रिटेन'], //
  'KR': ['South Korea', 'दक्षिण कोरिया'], 'JP': ['Japan', 'जापान'], 'CN': ['China', 'चीन'], 'FR': ['France', 'फ़्रांस'],
  'DE': ['Germany', 'जर्मनी'], 'IT': ['Italy', 'इटली'], 'ES': ['Spain', 'स्पेन'], 'CA': ['Canada', 'कनाडा'],
  'AU': ['Australia', 'ऑस्ट्रेलिया'], 'NZ': ['New Zealand', 'न्यूज़ीलैंड'], 'HK': ['Hong Kong', 'हांगकांग'],
  'TW': ['Taiwan', 'ताइवान'], 'RU': ['Russia', 'रूस'], 'IR': ['Iran', 'ईरान'], 'MX': ['Mexico', 'मेक्सिको'],
  'BR': ['Brazil', 'ब्राज़ील'], 'SE': ['Sweden', 'स्वीडन'], 'DK': ['Denmark', 'डेनमार्क'], 'NO': ['Norway', 'नॉर्वे'],
  'BD': ['Bangladesh', 'बांग्लादेश'],
  'PK': ['Pakistan', 'पाकिस्तान'],
  'LK': ['Sri Lanka', 'श्रीलंका'],
  'NP': ['Nepal', 'नेपाल'],
  'AE': ['UAE', 'यूएई'], 'IE': ['Ireland', 'आयरलैंड'], 'BE': ['Belgium', 'बेल्जियम'], 'NL': ['Netherlands', 'नीदरलैंड'],
  'TH': ['Thailand', 'थाईलैंड'],
  'TR': ['Turkey', 'तुर्की'],
  'PL': ['Poland', 'पोलैंड'],
  'AR': ['Argentina', 'अर्जेंटीना'],
};

/// Hindi comes from the [English, Hindi] pairs above; other Indian languages
/// from [moreLabels] (generated by tool/gen_labels.py). English is the fallback.
String _pick(BuildContext c, String key, List<String>? enHi, String fallback) {
  final code = Localizations.localeOf(c).languageCode;
  if (code == 'hi') return enHi?[1] ?? fallback;
  return moreLabels[code]?[key] ?? enHi?[0] ?? fallback;
}

String langName(BuildContext c, String code) => _pick(c, 'lang:$code', _langs[code], code);
String genreName(BuildContext c, String key) => _pick(c, 'genre:$key', _genres[key], key);
String ottName(String key) => _ott[key] ?? key;
String showName(BuildContext c, String key) => _pick(c, 'show:$key', _shows[key], key);
String formatName(String key) => _formats[key] ?? key;
String countryName(BuildContext c, String iso) => _pick(c, 'country:$iso', _countries[iso], iso);

/// UI languages, each named in its own script.
const uiLanguages = [
  ('en', 'English'), ('hi', 'हिन्दी'), ('ta', 'தமிழ்'), ('te', 'తెలుగు'), ('bn', 'বাংলা'), //
  ('mr', 'मराठी'), ('kn', 'ಕನ್ನಡ'), ('ml', 'മലയാളം'),
];
