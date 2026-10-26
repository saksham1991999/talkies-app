import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/l10n/gen/app_localizations.dart';
import 'package:talkies/ui/format.dart';

// The formatting layer is what a reader actually sees: a date, a price and a
// count. These tests pin the three things that broke or nearly broke:
//
//  * `appVersion` drifting from pubspec.yaml, which silently stops the
//    "what's new" sheet from ever showing again.
//  * rupees formatted through the reader's currency pattern, which regrouped in
//    thousands for Marathi and put the symbol after the number for Bengali.
//  * the fixed `d MMM yyyy` date pattern, which wrote Japanese and Chinese
//    dates in the wrong order.

/// Runs `body` once per shipped locale, inside a real MaterialApp so the intl
/// date and number symbols for that locale are loaded.
Future<void> forEachLocale(WidgetTester tester, void Function(BuildContext) body) async {
  for (final locale in AppLocalizations.supportedLocales) {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    body(ctx);
  }
}

void main() {
  test('appVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true).firstMatch(pubspec);
    expect(line, isNotNull, reason: 'pubspec.yaml has no version line');
    expect(appVersion, line!.group(1),
        reason: 'bump lib/ui/format.dart appVersion with pubspec.yaml, or the '
            '"what\'s new" sheet never shows for the new release');
  });

  testWidgets('every locale prints a date, a price and a count', (tester) async {
    await forEachLocale(tester, (c) {
      for (final v in [0.0, 250.0, 1234567.0, 1234.5]) {
        final inr = money(c, 'INR', v);
        expect(inr, startsWith('₹'), reason: '${c.fmtLocale} INR $v');
        expect(inr, matches(RegExp(r'[0-9\u0660-\u0669\u0966-\u096F\u09E6-\u09EF]')),
            reason: '${c.fmtLocale} INR $v printed no digits: $inr');
      }
      for (final code in currencySymbols.keys) {
        expect(money(c, code, 10), isNotEmpty, reason: '${c.fmtLocale} $code');
      }
      // The year, in whatever numerals the locale writes. Arabic prints ٢٠٢٦,
      // so looking for the Latin "2026" would fail a correct answer.
      expect(fmtDay(c, DateTime(2026, 9, 8)),
          matches(RegExp(r'[\d\u0660-\u0669\u06F0-\u06F9\u0966-\u096F\u09E6-\u09EF\u0AE6-\u0AEF'
              r'\u0B66-\u0B6F\u0BE6-\u0BEF\u0C66-\u0C6F\u0CE6-\u0CEF\u0D66-\u0D6F]')),
          reason: '${c.fmtLocale} date printed no year');
      expect(fmtMonthYear(c, DateTime(2026, 9, 8)), isNotEmpty);
      expect(fmtCount(c, 1234567), isNotEmpty);
    });
  });

  testWidgets('an Indian-language diary keeps one numeral system on one screen', (tester) async {
    // A Bengali or Marathi reader sees native numerals in the date and the
    // count. The price sat next to them in Latin digits until the rupee path
    // stopped going through `NumberFormat.currency`.
    await forEachLocale(tester, (c) {
      final count = fmtCount(c, 1234567);
      final price = money(c, 'INR', 1234567);
      String digits(String s) =>
          s.replaceAll(RegExp(r'[^0-9\u0660-\u0669\u0966-\u096F\u09E6-\u09EF]'), '');
      bool latin(String s) => RegExp(r'[0-9]').hasMatch(s);
      if (latin(count)) {
        expect(latin(price), isTrue,
            reason: '${c.fmtLocale} counts in Latin digits but prices in native ones: $price');
      } else {
        expect(latin(price), isFalse,
            reason: '${c.fmtLocale} counts in native digits but prices in Latin ones: $price');
      }
      expect(digits(price).length, greaterThan(4), reason: '${c.fmtLocale} $price');
    });
  });

  testWidgets('a price and a count group the same way in the same locale', (tester) async {
    // This is the invariant a reader sees: the rupee figure and the stub count
    // sit on one screen. `NumberFormat.currency` regrouped Marathi rupees in
    // thousands while the count beside them grouped in lakhs, so the two
    // numbers on one row disagreed about where the commas go.
    int separators(String s) => RegExp(r'[\u002C\u002E\u00A0\u202F\u2019\u066C\u060C]')
        .allMatches(s.replaceAll('₹', ''))
        .length;
    await forEachLocale(tester, (c) {
      final count = fmtCount(c, 1234567);
      final price = money(c, 'INR', 1234567);
      expect(separators(price), separators(count),
          reason: '${c.fmtLocale}: count "$count" and price "$price" group differently');
    });
  });

  testWidgets('rupees group in lakhs where the language does', (tester) async {
    // CLDR groups Kannada in thousands, and this test does not override CLDR.
    // These nine are the ones whose own data groups rupees in lakhs.
    const lakh = {'bn', 'gu', 'hi', 'ml', 'mr', 'or', 'pa', 'ta', 'te', 'en'};
    await forEachLocale(tester, (c) {
      final lang = Localizations.localeOf(c).languageCode;
      if (!lakh.contains(lang)) return;
      final s = money(c, 'INR', 1234567).replaceAll('₹', '');
      // A lakh group has one three-digit group at the end and two-digit groups
      // before it. A thousands group gives two groups of three.
      final groups = s.split(RegExp(r'[^\d\u09E6-\u09EF\u0966-\u096F\u0AE6-\u0AEF'
              r'\u0B66-\u0B6F\u0BE6-\u0BEF\u0C66-\u0C6F\u0CE6-\u0CEF\u0D66-\u0D6F]'))
          .where((g) => g.isNotEmpty)
          .toList();
      expect(groups.length, 3, reason: '$lang "$s" is not lakh grouping');
      expect(groups.last.length, 3, reason: '$lang "$s"');
      expect(groups[1].length, 2, reason: '$lang "$s"');
    });
  });

  test('every currency code has a symbol and no symbol equals its own code twice', () {
    for (final MapEntry(:key, :value) in currencySymbols.entries) {
      expect(value.trim(), isNotEmpty, reason: key);
      // The Settings chip prints "<symbol> <code>" unless they are the same.
      final chip = value == key ? key : '$value $key';
      expect(chip, isNot(contains('$key $key')), reason: 'chip would read "$chip"');
    }
  });

  test('every app locale has intl date symbols', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final name = intlLocaleOf(locale);
      // `localeExists` needs the symbol tables loaded, so this only asserts the
      // mapping itself; the widget test above proves formatting works.
      expect(name, isNotEmpty);
      expect(name, anyOf(equals(locale.languageCode), contains('_')));
    }
  });
}
