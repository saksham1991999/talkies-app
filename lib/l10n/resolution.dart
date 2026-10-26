import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

/// The locale the app should run in, given the phone's preferred languages.
///
/// Flutter's default resolution returns `supportedLocales.first` when nothing
/// matches, and the generated list is alphabetical, so it starts with Arabic. A
/// phone set to Swahili, Nepali, Khmer, Burmese or any other language the app
/// does not ship opened in Arabic and right to left, which is a hard read for
/// someone whose language is written left to right.
///
/// English is the honest fallback: it is the language every string is authored
/// in, and it is one of the two the store listing leads with. Resolution itself
/// stays Flutter's own algorithm, which already handles script and region
/// (`zh-Hant` → Traditional, `pt-PT` → European Portuguese); only the fallback
/// changes, by putting English first in the list it searches.
Locale resolveAppLocale(List<Locale>? preferred) => basicLocaleListResolution(preferred, _englishFirst);

final List<Locale> _englishFirst = [
  const Locale('en'),
  ...AppLocalizations.supportedLocales.where((l) => l.languageCode != 'en'),
];
