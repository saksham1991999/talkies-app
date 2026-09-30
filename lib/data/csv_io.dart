import 'package:csv/csv.dart';

import '../state/providers.dart';
import 'catalog.dart';
import 'models.dart';

const csvHeader = [
  'ticket_no', 'watched_on', 'date_precision', 'title', 'original_title', 'year', 'film_id', 'kind', //
  'rating', 'place', 'place_type', 'show', 'format', 'seat_class', 'seat', 'price_inr', 'fdfs',
  'language', 'watched_with', 'tags', 'memo',
];

String exportCsv(Diary d) {
  final rows = <List<Object?>>[csvHeader];
  for (final s in [...d.stubs]..sort(byWatchOrder)) {
    final f = d.films[s.filmId];
    rows.add([
      s.no,
      s.date == null ? '' : _dateText(s.date!, s.precision),
      s.precision.name,
      f?.title ?? '',
      f?.original ?? '',
      f?.year ?? '',
      s.filmId,
      (f?.series ?? false) ? 'series' : 'film',
      s.rating?.toStringAsFixed(1) ?? '',
      s.place ?? '',
      s.place == null ? '' : d.venueType(s.place).name,
      s.show ?? '',
      s.format ?? '',
      s.seatClass ?? '',
      s.seat ?? '',
      s.price == null ? '' : _num(s.price!),
      s.fdfs ? 'yes' : '',
      s.lang ?? '',
      s.company ?? '',
      s.tags.map((t) => '#$t').join(' '),
      s.memo,
    ]);
  }
  // BOM so Excel opens Devanagari and Tamil titles correctly.
  return '﻿${Csv(lineDelimiter: '\n').encode(rows)}';
}

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

String _dateText(DateTime d, DatePrecision p) => switch (p) {
  DatePrecision.day => ymd(d),
  DatePrecision.month => ymd(d).substring(0, 7),
  DatePrecision.year => '${d.year}',
  DatePrecision.none => '',
};

/// Accepts `YYYY-MM-DD`, `YYYY-MM`, `YYYY`, and Indian `DD/MM/YYYY` or `DD-MM-YYYY`.
(DateTime?, DatePrecision) parseDate(String raw) {
  final t = raw.trim();
  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
  if (m != null) return (_safe(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)), DatePrecision.day);
  m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$').firstMatch(t);
  if (m != null) return (_safe(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!)), DatePrecision.day);
  m = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(t);
  if (m != null) return (_safe(int.parse(m[1]!), int.parse(m[2]!), 1), DatePrecision.month);
  m = RegExp(r'^(\d{4})$').firstMatch(t);
  if (m != null) return (DateTime(int.parse(m[1]!)), DatePrecision.year);
  return (null, DatePrecision.none);
}

DateTime? _safe(int y, int mo, int d) {
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, mo, d);
  return dt.month == mo ? dt : null;
}

class CsvImport {
  CsvImport(this.rows, this.matched, this.custom, this.skipped, this.places, this.letterboxd);
  final List<(Film, StubDraft)> rows;
  final int matched, custom, skipped;

  /// Place names not yet in the venue list.
  final Set<String> places;
  final bool letterboxd;
}

/// Reads a Talkies export, a Letterboxd diary.csv / watched.csv, or any CSV
/// with a title column. Films are matched to the catalog by id, then by title
/// and year; anything else becomes the user's own film.
CsvImport parseCsv(String text, Catalog cat, Diary diary) {
  final table = Csv().decode(text.replaceFirst('﻿', ''));
  if (table.isEmpty) return CsvImport(const [], 0, 0, 0, const {}, false);
  final head = [for (final h in table.first) h.toString().trim().toLowerCase()];
  int col(List<String> names) => names.map(head.indexOf).firstWhere((i) => i >= 0, orElse: () => -1);
  List<int> cols(List<String> names) => names.map(head.indexOf).where((i) => i >= 0).toList();
  final lb = head.contains('letterboxd uri');
  final cTitle = col(['title', 'name', 'film', 'movie']);
  final cYear = col(['year']);
  final cId = col(['film_id']);
  // Letterboxd leaves "Watched Date" empty on some rows; fall back to "Date".
  final cDates = cols(['watched_on', 'watched date', 'date', 'watched']);
  final cPrec = col(['date_precision']);
  final cRating = col(['rating']);
  final cPlace = col(['place', 'venue']);
  final cTags = col(['tags']);
  final cMemo = col(['memo', 'review', 'notes']);
  final cShow = col(['show']), cFormat = col(['format']), cClass = col(['seat_class']), cSeat = col(['seat']);
  final cPrice = col(['price_inr', 'price']), cFdfs = col(['fdfs']), cLang = col(['language']);
  final cWith = col(['watched_with', 'with']), cKind = col(['kind']), cOrig = col(['original_title']);
  if (cTitle < 0 && cId < 0) return CsvImport(const [], 0, 0, table.length - 1, const {}, lb);

  final known = {...diary.venues.map((v) => v.name)};
  final places = <String>{};
  final customByKey = <String, Film>{};
  var nextCustom = 1;
  final out = <(Film, StubDraft)>[];
  var matched = 0, custom = 0, skipped = 0;

  for (final row in table.skip(1)) {
    String cell(int i) => i < 0 || i >= row.length ? '' : row[i].toString().trim();
    final title = cell(cTitle), id = cell(cId);
    final year = int.tryParse(cell(cYear));
    Film? film = cat.byId[id];
    // Own films (my:n) are numbered per phone: trust the id only if the title agrees.
    final own = diary.films[id];
    if (film == null && own != null && norm(own.title) == norm(title)) film = own;
    film ??= title.isEmpty ? null : cat.match(title, year);
    if (film != null) {
      matched++;
    } else if (title.isNotEmpty) {
      film = customByKey['${norm(title)}|$year'];
      if (film == null) {
        while (diary.films.containsKey('my:$nextCustom')) {
          nextCustom++;
        }
        film = Film(
          id: 'my:${nextCustom++}',
          title: title,
          original: cell(cOrig).isEmpty ? null : cell(cOrig),
          year: year,
          date: year?.toString(),
          series: cell(cKind) == 'series',
        );
        customByKey['${norm(title)}|$year'] = film;
      }
      custom++;
    } else {
      skipped++;
      continue;
    }

    var (date, prec) = parseDate(cDates.map(cell).firstWhere((v) => v.isNotEmpty, orElse: () => ''));
    if (date != null && cPrec >= 0) {
      prec = DatePrecision.values.asNameMap()[cell(cPrec)] ?? prec;
    }
    final rating = double.tryParse(cell(cRating));
    final place = cell(cPlace);
    if (place.isNotEmpty && !known.contains(place)) places.add(place);
    final tagText = cell(cTags);
    final tags = (lb ? tagText.split(',') : tagText.split(RegExp(r'[\s,]+')))
        .map(cleanTag)
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    out.add((
      film,
      StubDraft(
        date: date,
        precision: date == null ? DatePrecision.none : prec,
        rating: rating == null || rating <= 0 ? null : (rating.clamp(0.1, 5.0) * 10).round() / 10,
        place: place.isEmpty ? null : place,
        memo: cell(cMemo),
        tags: tags,
        show: cell(cShow).isEmpty ? null : cell(cShow),
        format: cell(cFormat).isEmpty ? null : cell(cFormat),
        seatClass: cell(cClass).isEmpty ? null : cell(cClass),
        seat: cell(cSeat).isEmpty ? null : cell(cSeat),
        price: double.tryParse(cell(cPrice).replaceAll(RegExp(r'[₹,\s]|Rs\.?', caseSensitive: false), '')),
        fdfs: const {'yes', 'true', '1', 'y'}.contains(cell(cFdfs).toLowerCase()),
        lang: cell(cLang).isEmpty ? null : cell(cLang),
        company: cell(cWith).isEmpty ? null : cell(cWith),
      ),
    ));
  }
  return CsvImport(out, matched, custom, skipped, places, lb);
}

/// Guesses the venue type of an imported place name.
VenueType guessVenueType(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'netflix|prime|hotstar|jio|sony|zee5|aha|sun ?nxt|mx|apple|hoichoi|mubi|youtube|ott').hasMatch(n)) {
    return VenueType.ott;
  }
  if (RegExp(r'home|ghar|laptop|phone').hasMatch(n)) return VenueType.home;
  if (RegExp(r'\btv\b|television|dd|doordarshan').hasMatch(n)) return VenueType.tv;
  if (RegExp(r'pvr|inox|cinepolis|cinema|theatre|theater|talkies|multiplex|imax|miraj|carnival').hasMatch(n)) {
    return VenueType.cinema;
  }
  return VenueType.other;
}
