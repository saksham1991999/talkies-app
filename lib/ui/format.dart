import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../l10n/gen/app_localizations.dart';

/// Version shown in Settings and used to gate the "what's new" sheet: bumping it
/// is what makes an update show the sheet again, so it must match the
/// `version:` line in pubspec.yaml. `test/l10n_format_test.dart` enforces that.
const appVersion = '1.1.0';
const privacyUrl = 'https://saksham1991999.github.io/talkies-app/privacy.html';

extension L10nX on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);

  /// Locale for intl formatting. `zh_Hans` and `zh_Hant` have no date symbols of
  /// their own, and a region such as `es_ES` may be missing, so fall back to the
  /// language before giving up.
  String get fmtLocale => intlLocaleOf(Localizations.localeOf(this));
}

String intlLocaleOf(Locale l) {
  if (l.languageCode == 'zh') return l.scriptCode == 'Hant' ? 'zh_TW' : 'zh_CN';
  final region = l.countryCode;
  final name = region == null ? l.languageCode : '${l.languageCode}_$region';
  return DateFormat.localeExists(name) ? name : l.languageCode;
}

/// "Tue, 8 Sep 2026". The skeleton, not a fixed pattern: Japanese, Chinese and
/// Korean write the date year first (2026年9月8日), and a literal `d MMM yyyy`
/// produced "火, 8 9月 2026" there. English uses en_GB so the day still comes
/// before the month, which is the app's own style and the Indian convention;
/// plain `en` is US order.
String fmtDay(BuildContext c, DateTime d) {
  final locale = c.fmtLocale == 'en' ? 'en_GB' : c.fmtLocale;
  return DateFormat.yMMMEd(locale).format(d);
}
String fmtShort(BuildContext c, DateTime d) => DateFormat('d MMM', c.fmtLocale).format(d);
String fmtMonthYear(BuildContext c, DateTime d) => DateFormat('MMMM yyyy', c.fmtLocale).format(d);
String fmtMonth(BuildContext c, DateTime d) => DateFormat('MMMM', c.fmtLocale).format(d);

/// Printed on stamps and counterfoils: 08.09.26
String fmtTicketDate(DateTime d) => DateFormat('dd.MM.yy').format(d);

String fmtStubDate(BuildContext c, Stub s) => switch (s.date == null ? DatePrecision.none : s.precision) {
  DatePrecision.day => fmtDay(c, s.date!),
  DatePrecision.month => fmtMonthYear(c, s.date!),
  DatePrecision.year => '${s.date!.year}',
  DatePrecision.none => c.l.dateUnknown,
};

/// Short form for list rows: "8 Sep", "Sep 2024", "2019", "-".
String fmtStubShort(BuildContext c, Stub s) => switch (s.date == null ? DatePrecision.none : s.precision) {
  DatePrecision.day =>
    s.date!.year == DateTime.now().year ? fmtShort(c, s.date!) : DateFormat('d MMM yy', c.fmtLocale).format(s.date!),
  DatePrecision.month => DateFormat('MMM yyyy', c.fmtLocale).format(s.date!),
  DatePrecision.year => '${s.date!.year}',
  DatePrecision.none => '-',
};

String fmtRelease(BuildContext c, Film f) {
  final d = f.date;
  if (d == null) return f.year?.toString() ?? '';
  return switch (d.length) {
    10 => DateFormat('d MMM yyyy', c.fmtLocale).format(DateTime.parse(d)),
    7 => DateFormat('MMM yyyy', c.fmtLocale).format(DateTime.parse('$d-01')),
    _ => d,
  };
}

/// Ticket price symbols. The amount is never converted: it is printed as the
/// user typed it, only the symbol and the grouping change.
const currencySymbols = <String, String>{
  'INR': '₹', 'USD': r'$', 'GBP': '£', 'EUR': '€', 'AED': 'AED', 'AUD': r'A$', //
  'CAD': r'C$', 'SGD': r'S$', 'JPY': '¥', 'BRL': r'R$', 'MXN': r'MX$', 'TRY': '₺',
  'ZAR': 'R', 'CHF': 'CHF',
};

/// Indian grouping (₹1,23,456) for rupees; the locale's grouping for the rest.
String money(BuildContext c, String currency, double v) {
  final digits = v == v.roundToDouble() ? 0 : 2;
  final locale = c.fmtLocale;
  if (currency == 'INR') {
    // Rupees group in lakhs, which is a property of the amount and not of the
    // reader's locale, so this cannot go through `NumberFormat.currency`: its
    // Marathi pattern regroups in thousands and its Bengali pattern prints the
    // symbol after the number. The locale's own decimal pattern gets both the
    // lakh grouping and the native numerals right in every Indian language.
    final amount = NumberFormat.decimalPattern(locale == 'en' ? 'en_IN' : locale)
      ..minimumFractionDigits = digits
      ..maximumFractionDigits = digits;
    return '₹${amount.format(v)}';
  }
  return NumberFormat.currency(
    locale: locale,
    symbol: currencySymbols[currency] ?? currency,
    decimalDigits: digits,
  ).format(v);
}

/// Counts group the Indian way in English too: the stub count sits next to a
/// rupee price, and 1,234,567 next to ₹12,34,567 reads as two number systems.
String fmtCount(BuildContext c, int n) {
  final locale = c.fmtLocale == 'en' ? 'en_IN' : c.fmtLocale;
  return NumberFormat.decimalPattern(locale).format(n);
}
String fmtRuntime(BuildContext c, int minutes) =>
    minutes >= 60 ? c.l.hoursMinutes(minutes ~/ 60, minutes % 60) : c.l.minutesOnly(minutes);

/// Hour and minute unit words of the UI language, read from its "{h}h {m}m" pattern.
(String, String) hourMinuteUnits(BuildContext c) {
  final s = c.l.hoursMinutes(111, 222);
  final i = s.indexOf('111'), j = s.indexOf('222');
  if (i < 0 || j < i) return ('h', 'm');
  return (s.substring(i + 3, j).trim(), s.substring(j + 3).trim());
}

/// How much larger than normal the user's system text is (1.0 = default).
double textGrowth(BuildContext c) => MediaQuery.textScalerOf(c).scale(100) / 100;

/// A height that holds text: [base] at normal size, growing with larger text.
double textHeight(BuildContext c, double base, double textPart) =>
    base + textPart * (textGrowth(c) - 1).clamp(0.0, 2.0);

String ticketNo(int no) => no.toString().padLeft(4, '0');

String fmtRating(double r) => r.toStringAsFixed(1);

/// Default place names are stored in English; show them in the UI language.
String placeName(BuildContext c, String name) => switch (name) {
  'Cinema hall' => c.l.venueCinema,
  'Home' => c.l.venueHome,
  'TV' => c.l.venueTv,
  _ => name,
};

String venueTypeName(BuildContext c, VenueType t) => switch (t) {
  VenueType.cinema => c.l.venueCinema,
  VenueType.ott => c.l.venueOtt,
  VenueType.home => c.l.venueHome,
  VenueType.tv => c.l.venueTv,
  VenueType.other => c.l.venueOther,
};
