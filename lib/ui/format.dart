import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../l10n/gen/app_localizations.dart';

const appVersion = '1.0.0';
const privacyUrl = 'https://saksham1991999.github.io/talkies-app/privacy.html';

extension L10nX on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);

  /// Locale for intl formatting, always with the Indian region.
  String get fmtLocale => '${Localizations.localeOf(this).languageCode}_IN';
}

String fmtDay(BuildContext c, DateTime d) => DateFormat('EEE, d MMM yyyy', c.fmtLocale).format(d);
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

/// Indian grouping: ₹1,23,456.
String rupees(double v) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: v == v.roundToDouble() ? 0 : 2).format(v);

String fmtCount(int n) => NumberFormat.decimalPattern('en_IN').format(n);

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
