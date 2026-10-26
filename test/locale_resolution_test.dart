import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/l10n/gen/app_localizations.dart';
import 'package:talkies/l10n/resolution.dart';

// Which language the app opens in, for a phone whose language is not the one
// the app is being read in. This is the bug that nearly shipped as 1.1.0: with
// no explicit resolution, Flutter falls back to `supportedLocales.first`, and
// the generated list is alphabetical, so it starts with Arabic. Every phone in
// a language outside the shipped 44 opened in Arabic, right to left.

void main() {
  test('a shipped language resolves to itself', () {
    for (final locale in AppLocalizations.supportedLocales) {
      expect(resolveAppLocale([locale]), locale, reason: '${locale.toLanguageTag()} must not move');
    }
  });

  test('a language outside the 44 falls back to English, never Arabic', () {
    // Swahili, Nepali, Khmer, Burmese, Zulu, Uzbek, Amharic, Azerbaijani,
    // Sinhala: all real device languages, none of them shipped.
    for (final code in ['sw', 'ne', 'km', 'my', 'zu', 'uz', 'am', 'az', 'si', 'ka']) {
      expect(resolveAppLocale([Locale(code)]).languageCode, 'en', reason: '$code phone');
    }
  });

  test('no preference at all is English', () {
    expect(resolveAppLocale(null).languageCode, 'en');
    expect(resolveAppLocale(const []).languageCode, 'en');
  });

  test('the phone\'s ordered preference is respected', () {
    // A phone set to French then English reads in French.
    expect(resolveAppLocale(const [Locale('fr'), Locale('en')]).languageCode, 'fr');
    // An unshipped first choice falls through to the shipped second one.
    expect(resolveAppLocale(const [Locale('sw'), Locale('ta')]).languageCode, 'ta');
  });

  test('region and script still pick the right variant', () {
    expect(resolveAppLocale(const [Locale('pt', 'PT')]).toLanguageTag(), 'pt-PT');
    expect(resolveAppLocale(const [Locale('pt', 'BR')]).languageCode, 'pt');
    expect(resolveAppLocale(const [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')]).toLanguageTag(),
        'zh-Hant');
    expect(resolveAppLocale(const [Locale('zh', 'CN')]).toLanguageTag(), 'zh');
    // A Chinese phone with no region or script gets Simplified, the majority.
    expect(resolveAppLocale(const [Locale('zh')]).toLanguageTag(), 'zh');
  });

  testWidgets('the app really renders in English for a Swahili phone', (t) async {
    late Locale resolved;
    await t.pumpWidget(MaterialApp(
      locale: const Locale('sw'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      localeListResolutionCallback: (locales, _) => resolveAppLocale(locales),
      home: Builder(builder: (c) {
        resolved = Localizations.localeOf(c);
        return const SizedBox();
      }),
    ));
    expect(resolved.languageCode, 'en');
    // And the strings really load, not just the locale tag.
    expect(AppLocalizations.of(t.element(find.byType(SizedBox))), isNotNull);
  });
}
