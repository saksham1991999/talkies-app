import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'models.dart';
import 'recommend.dart';

/// Wikimedia asks API clients for contact details in the User-Agent. The app
/// store page is the default; builds can set their own:
/// `flutter build apk --dart-define=TALKIES_CONTACT=https://your.site`
const _contact = String.fromEnvironment(
  'TALKIES_CONTACT',
  defaultValue: 'https://play.google.com/store/apps/details?id=in.talkies.talkies',
);
const userAgent = 'Talkies/1.0 ($_contact) movie ticket diary for India';

final _strip = RegExp(r'[^\p{L}\p{M}\p{N}]', unicode: true);
final _accented = RegExp('[àáâãäåāèéêëēìíîïīòóôõöøōùúûüūñçýÿ]');
const _plain = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'è': 'e', 'é': 'e', 'ê': 'e', //
  'ë': 'e', 'ē': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ò': 'o', 'ó': 'o', 'ô': 'o',
  'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ñ': 'n',
  'ç': 'c', 'ý': 'y', 'ÿ': 'y',
};

/// Lowercase, drop accents, drop spaces and punctuation. Keeps Indic vowel
/// signs (Unicode marks), so Devanagari and Tamil titles still match.
String norm(String s) {
  var t = s.toLowerCase();
  if (_accented.hasMatch(t)) t = t.split('').map((c) => _plain[c] ?? c).join();
  return t.replaceAll(_strip, '');
}

bool isIndian(Film f) => f.countries.contains('IN') || f.langs.any(indianLangs.contains);

/// Release date after [today] (`YYYY-MM-DD`). Month-only and year-only dates
/// count by their period. No date counts as released.
bool unreleased(Film f, String today) {
  final d = f.date;
  if (d == null) return false;
  return switch (d.length) {
    10 => d.compareTo(today) > 0,
    7 => d.compareTo(today.substring(0, 7)) > 0,
    _ => d.compareTo(today.substring(0, 4)) > 0,
  };
}

class Catalog {
  Catalog(List<Film> items, String built) : this._(items, built, stemsOf(items));

  // Runs inside the loadCatalog isolate, so the recommender's trait counts
  // cost the UI thread nothing.
  Catalog._(this.items, this.built, this.stems)
    : df = traitCounts(items, stems),
      byId = {for (final f in items) f.id: f},
      _t = [for (final f in items) norm(f.title)],
      _o = [for (final f in items) f.original == null ? '' : norm(f.original!)],
      _p = [
        for (final f in items) [...f.directors, ...f.cast].map(norm).join(' '),
      ];

  final List<Film> items;
  final Map<String, Film> byId;
  final String built;

  /// Shared title stem of each film in [items], for sequels. See [titleStem].
  final List<String?> stems;

  /// Films per trait, for the recommender's IDF. See [traitCounts].
  final Map<String, int> df;
  final List<String> _t, _o, _p;

  late final Map<String, int> _index = {for (var i = 0; i < items.length; i++) items[i].id: i};

  /// Sequel stem of [f]: the shared one for a catalog film, else the plain title stem.
  String? stemOf(Film f) {
    final i = _index[f.id];
    return i == null ? titleStem(f.title) : stems[i];
  }

  /// Normalized title (and original title) to films, most popular first.
  late final Map<String, List<Film>> _exact = () {
    final m = <String, List<Film>>{};
    for (var i = 0; i < items.length; i++) {
      (m[_t[i]] ??= []).add(items[i]);
      if (_o[i].isNotEmpty && _o[i] != _t[i]) (m[_o[i]] ??= []).add(items[i]);
    }
    return m;
  }();

  static Catalog parse(String bundled, String? delta) {
    final j = jsonDecode(bundled) as Map<String, dynamic>;
    final byId = <String, Film>{
      for (final e in j['items'] as List) (e['id'] as String): Film.fromJson(e as Map<String, dynamic>),
    };
    final fresh = delta == null ? const <Film>[] : deltaFilms(delta);
    for (final f in fresh) {
      final old = byId[f.id];
      byId[f.id] = old == null ? f : _merge(old, f);
    }
    final items = byId.values.toList()..sort((a, b) => b.pop.compareTo(a.pop));
    return Catalog(items, j['built'] as String? ?? '');
  }

  /// Bundled data is richer (native titles, OTT); fresh data has newer dates.
  static Film _merge(Film old, Film fresh) => Film(
    id: old.id,
    title: old.title,
    original: old.original ?? fresh.original,
    year: fresh.year ?? old.year,
    date: fresh.date ?? old.date,
    runtime: fresh.runtime ?? old.runtime,
    directors: fresh.directors.isNotEmpty ? fresh.directors : old.directors,
    cast: old.cast.isNotEmpty ? old.cast : fresh.cast,
    genres: old.genres.isNotEmpty ? old.genres : fresh.genres,
    langs: old.langs.isNotEmpty ? old.langs : fresh.langs,
    countries: old.countries.isNotEmpty ? old.countries : fresh.countries,
    ott: {...old.ott, ...fresh.ott}.toList(),
    poster: fresh.poster ?? old.poster,
    wiki: old.wiki ?? fresh.wiki,
    pop: math.max(old.pop, fresh.pop),
    series: old.series,
    seasons: old.seasons,
  );

  /// [snapshot] with empty fields filled from [fresh]; set fields stay.
  static Film fillGaps(Film snapshot, Film fresh) => Film(
    id: snapshot.id,
    title: snapshot.title,
    original: snapshot.original ?? fresh.original,
    year: snapshot.year ?? fresh.year,
    date: (snapshot.date?.length ?? 0) >= (fresh.date?.length ?? 0) ? snapshot.date : fresh.date,
    runtime: snapshot.runtime ?? fresh.runtime,
    directors: snapshot.directors.isNotEmpty ? snapshot.directors : fresh.directors,
    cast: snapshot.cast.isNotEmpty ? snapshot.cast : fresh.cast,
    genres: snapshot.genres.isNotEmpty ? snapshot.genres : fresh.genres,
    langs: snapshot.langs.isNotEmpty ? snapshot.langs : fresh.langs,
    countries: snapshot.countries.isNotEmpty ? snapshot.countries : fresh.countries,
    ott: snapshot.ott.isNotEmpty ? snapshot.ott : fresh.ott,
    poster: snapshot.poster ?? fresh.poster,
    wiki: snapshot.wiki ?? fresh.wiki,
    pop: snapshot.pop,
    series: snapshot.series,
    seasons: snapshot.seasons ?? fresh.seasons,
  );

  /// Title, original title, director or cast. Ignores spaces and punctuation,
  /// so "shahrukh" finds "Shah Rukh Khan" and "kgf" finds "K.G.F: Chapter 2".
  List<Film> search(String query, {bool? series, String? lang, int limit = 80, bool titleOnly = false}) {
    final q = norm(query);
    if (q.isEmpty) return const [];
    final hits = <(double, Film)>[];
    for (var i = 0; i < items.length; i++) {
      final f = items[i];
      if (series != null && f.series != series) continue;
      if (lang != null && !f.langs.contains(lang)) continue;
      final t = _t[i], o = _o[i];
      double s;
      if (t == q || o == q) {
        s = 100;
      } else if (t.startsWith(q) || o.startsWith(q)) {
        s = 70;
      } else if (t.contains(q) || o.contains(q)) {
        s = 45;
      } else if (!titleOnly && _p[i].contains(q)) {
        s = 25;
      } else {
        continue;
      }
      hits.add((s + math.log(f.pop + 1) * 4, f));
    }
    hits.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final h in hits.take(limit)) h.$2];
  }

  /// Films whose exact release day falls in the last [days] days.
  List<Film> newReleases(DateTime today, {bool worldwide = false, String? lang, int days = 60}) {
    final from = today.subtract(Duration(days: days));
    return items.where((f) {
      final d = f.releaseDay;
      return !f.series && d != null && !d.isBefore(from) && !d.isAfter(today) && _region(f, worldwide, lang);
    }).toList()..sort((a, b) => b.releaseSortKey.compareTo(a.releaseSortKey));
  }

  /// Films dated after today. Month-only and year-only dates count by their period.
  List<Film> upcoming(DateTime today, {bool worldwide = false, String? lang}) {
    final t = ymd(today);
    return items.where((f) => !f.series && unreleased(f, t) && _region(f, worldwide, lang)).toList()
      ..sort((a, b) => a.releaseSortKey.compareTo(b.releaseSortKey));
  }

  /// Best catalog match for an imported title and optional year.
  Film? match(String title, int? year) {
    final q = norm(title);
    if (q.isEmpty) return null;
    Film? best;
    for (final f in _exact[q] ?? const <Film>[]) {
      if (year == null || f.year == null || (f.year! - year).abs() <= 1) {
        if (year != null && f.year == year) return f;
        best ??= f;
      }
    }
    return best;
  }

  bool _region(Film f, bool worldwide, String? lang) =>
      (worldwide || isIndian(f)) && (lang == null || f.langs.contains(lang));
}

/// Films in a refresh file. A damaged file gives none, so it never takes the
/// bundled list down with it.
List<Film> deltaFilms(String delta) {
  try {
    return [
      for (final e in (jsonDecode(delta) as Map<String, dynamic>)['items'] as List)
        Film.fromJson(e as Map<String, dynamic>),
    ];
  } catch (_) {
    return const [];
  }
}

Future<Catalog> loadCatalog(String bundled, File delta) async {
  final d = delta.existsSync() ? await delta.readAsString() : null;
  return Isolate.run(() => Catalog.parse(bundled, d));
}

// ---------------------------------------------------------------------------
// Online refresh: recent and upcoming Indian films from Wikidata (no API key).

const _langQ = {
  'Q1568': 'hi', 'Q5885': 'ta', 'Q8097': 'te', 'Q36236': 'ml', 'Q33673': 'kn', 'Q9610': 'bn', //
  'Q1571': 'mr', 'Q58635': 'pa', 'Q5137': 'gu', 'Q33810': 'or', 'Q29401': 'as', 'Q1860': 'en',
  'Q1617': 'ur', 'Q33268': 'bho',
};

const _genreRules = [
  ('superhero', 'superhero'),
  ('mythology', 'mytholog|devotional|religious'),
  ('scifi', 'science fiction'),
  ('animation', 'anim'),
  ('documentary', 'documentar'),
  ('biography', 'biograph|biopic'),
  ('historical', 'histor|period|epic'),
  ('musical', 'musical|music|dance'),
  ('horror', 'horror|supernatural'),
  ('crime', 'crime|gangster|heist'),
  ('mystery', 'myster|detective'),
  ('thriller', 'thriller|suspense|psycholog'),
  ('action', 'action|martial|masala'),
  ('war', r'\bwar\b'),
  ('sports', 'sport'),
  ('romance', 'roman'),
  ('comedy', 'comed|satire'),
  ('family', 'family|children'),
  ('fantasy', 'fantasy'),
  ('adventure', 'adventure'),
  ('spy', 'spy|espionage'),
  ('political', 'politic'),
  ('legal', 'legal|courtroom'),
  ('coming_of_age', 'coming-of-age|teen'),
  ('drama', 'drama|social'),
];

String? genreKey(String label) {
  final l = label.toLowerCase();
  for (final (k, rx) in _genreRules) {
    if (RegExp(rx).hasMatch(l)) return k;
  }
  return null;
}

String _refreshQuery(DateTime today) {
  final from = ymd(today.subtract(const Duration(days: 90)));
  final to = ymd(DateTime(today.year + 1, today.month, today.day));
  return '''
SELECT ?f ?w ?s (SAMPLE(?lab) AS ?t) (MIN(CONCAT(STR(?d), "#", STR(?pr))) AS ?date) (SAMPLE(?dur) AS ?rt)
  (GROUP_CONCAT(DISTINCT ?dirL; separator="|") AS ?dirs) (GROUP_CONCAT(DISTINCT ?castL; separator="|") AS ?casts)
  (GROUP_CONCAT(DISTINCT STR(?lq); separator="|") AS ?langs) (GROUP_CONCAT(DISTINCT ?gl; separator="|") AS ?gens)
WHERE {
  ?f wdt:P31 wd:Q11424; wdt:P495 wd:Q668; wikibase:sitelinks ?s.
  ?f p:P577/psv:P577 [ wikibase:timeValue ?d; wikibase:timePrecision ?pr ].
  FILTER(?d >= "${from}T00:00:00Z"^^xsd:dateTime && ?d <= "${to}T00:00:00Z"^^xsd:dateTime)
  ?a schema:about ?f; schema:isPartOf <https://en.wikipedia.org/>; schema:name ?w.
  OPTIONAL { ?f rdfs:label ?lab FILTER(LANG(?lab) = "en") }
  OPTIONAL { ?f wdt:P2047 ?dur }
  OPTIONAL { ?f wdt:P57 ?dq. ?dq rdfs:label ?dirL FILTER(LANG(?dirL) = "en") }
  OPTIONAL { ?f wdt:P161 ?cq. ?cq rdfs:label ?castL FILTER(LANG(?castL) = "en") }
  OPTIONAL { ?f wdt:P364 ?lq }
  OPTIONAL { ?f wdt:P136 ?gq. ?gq rdfs:label ?gl FILTER(LANG(?gl) = "en") }
} GROUP BY ?f ?w ?s''';
}

/// Poster path under [wikimediaBase], without the tracking query Wikipedia adds.
String? posterPath(String? src) =>
    src != null && src.startsWith(wikimediaBase) ? src.substring(wikimediaBase.length).split('?').first : null;

Future<http.Response> _get(http.Client c, Uri uri) =>
    _polite(() => c.get(uri, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 30)));

/// Sends with Wikimedia manners: spaced out, and retried when rate limited.
Future<http.Response> _polite(Future<http.Response> Function() send) async {
  for (var attempt = 0; ; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final res = await send();
    if ((res.statusCode != 429 && res.statusCode != 503) || attempt == 3) return res;
    final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? (1 << attempt);
    await Future<void>.delayed(Duration(seconds: wait.clamp(1, 10)));
  }
}

/// Parses one SPARQL row of [_refreshQuery] into a film.
Film filmFromRefreshRow(Map<String, dynamic> r) {
  String? v(String k) => (r[k] as Map<String, dynamic>?)?['value'] as String?;
  List<String> split(String k) => (v(k) ?? '').split('|').where((s) => s.isNotEmpty).toList();
  final id = v('f')!.split('/').last;
  final wiki = v('w')!;
  String? date;
  final raw = v('date');
  if (raw != null) {
    final parts = raw.split('#');
    final iso = parts[0].replaceFirst('+', '');
    final pr = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 11;
    if (iso.length >= 10) {
      date = pr >= 11 ? iso.substring(0, 10) : (pr == 10 ? iso.substring(0, 7) : iso.substring(0, 4));
    }
  }
  final langs = <String>[];
  for (final q in split('langs')) {
    final code = _langQ[q.split('/').last];
    if (code != null && !langs.contains(code)) langs.add(code);
  }
  final genres = <String>[];
  for (final g in split('gens')) {
    final k = genreKey(g);
    if (k != null && !genres.contains(k)) genres.add(k);
  }
  final rt = double.tryParse(v('rt') ?? '');
  return Film(
    id: id,
    title: v('t') ?? wiki.replaceAll(RegExp(r'\s*\([^)]*\)$'), ''),
    year: date == null ? null : int.tryParse(date.substring(0, 4)),
    date: date,
    runtime: rt?.round(),
    directors: split('dirs').take(3).toList(),
    cast: split('casts').take(8).toList(),
    genres: genres.take(4).toList(),
    langs: langs,
    countries: const ['IN'],
    wiki: wiki,
    pop: int.tryParse(v('s') ?? '') ?? 0,
  );
}

/// Wikidata failed, but films from the Wikipedia lists were saved.
class PartialRefresh implements Exception {
  const PartialRefresh(this.cause);
  final Object cause;

  @override
  String toString() => 'Partial refresh: $cause';
}

/// Downloads recent and upcoming Indian films and merges them into [delta].
/// Returns the number of films fetched. Throws [PartialRefresh] after saving
/// when only the Wikipedia lists answered.
Future<int> refreshCatalog(File delta, DateTime today, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    // Start from the last refresh, so a bad network day never drops films. Keep
    // only films the sources below still cover (this year's lists, the last 90
    // days); older ones leave, as before, so they never mask a newer bundled list.
    final from = ymd(today.subtract(const Duration(days: 90)));
    final keep = from.startsWith('${today.year}') ? '${today.year}' : from;
    final byId = {
      for (final f in delta.existsSync() ? deltaFilms(await delta.readAsString()) : const <Film>[])
        if ((f.date ?? '').compareTo(keep) >= 0) f.id: f,
    };
    final got = <String>{};
    Object? failure;
    try {
      final res = await _polite(
        () => c
            .post(
              Uri.parse('https://query.wikidata.org/sparql'),
              headers: {'Accept': 'application/sparql-results+json', 'User-Agent': userAgent},
              body: {'query': _refreshQuery(today)},
            )
            .timeout(const Duration(seconds: 60)),
      );
      if (res.statusCode != 200) throw HttpException('Wikidata ${res.statusCode}');
      final rows = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['results']['bindings'] as List)
          .cast<Map<String, dynamic>>();
      final fresh = {for (final f in rows.map(filmFromRefreshRow)) f.id: f};
      final posters = await _posters(c, fresh.values.map((f) => f.wiki!).toList());
      for (final f in fresh.values) {
        final old = byId[f.id];
        // Wikidata rows carry no poster or OTT: keep what earlier refreshes found.
        final n = f.copyWith(poster: posters[f.wiki] ?? old?.poster);
        byId[f.id] = old == null || old.ott.isEmpty ? n : n.withOtt(old.ott);
      }
      got.addAll(fresh.keys);
    } catch (e) {
      failure = e;
    }
    // List pages are India release lists: their day wins over Wikidata's
    // earliest date, which is often a festival premiere.
    for (final f in await fetchReleaseLists(c, today)) {
      final w = byId[f.id];
      byId[f.id] = w == null
          ? f
          : Catalog._merge(w, Film(id: w.id, title: w.title, year: f.year, date: f.date, poster: w.poster ?? f.poster));
      got.add(f.id);
    }
    if (got.isEmpty) throw failure ?? const HttpException('No films fetched');
    // Where this refresh's films stream, read from their articles: OTT releases
    // follow cinemas by weeks, so this also fills in films from earlier refreshes.
    final ott = await fetchStreaming(c, {for (final id in got) ?byId[id]?.wiki}.toList());
    for (final id in got) {
      final f = byId[id]!;
      final found = ott[f.wiki] ?? const <String>[];
      if (found.isNotEmpty) byId[id] = f.withOtt({...f.ott, ...found}.toList());
    }
    final tmp = File('${delta.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'fetched': today.toIso8601String(), 'items': byId.values.map((f) => f.toJson()).toList()}),
      flush: true,
    );
    await tmp.rename(delta.path);
    if (failure != null) throw PartialRefresh(failure);
    return got.length;
  } finally {
    if (client == null) c.close();
  }
}

Future<Map<String, String>> _posters(http.Client c, List<String> titles) async {
  final out = <String, String>{};
  for (var i = 0; i < titles.length; i += 50) {
    final batch = titles.sublist(i, math.min(i + 50, titles.length));
    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query', 'prop': 'pageimages', 'piprop': 'thumbnail', 'pithumbsize': '330', //
      'pilicense': 'any', 'titles': batch.join('|'), 'format': 'json', 'formatversion': '2',
    });
    final http.Response res;
    try {
      res = await _get(c, uri);
    } catch (_) {
      continue;
    }
    if (res.statusCode != 200) continue;
    final q = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['query'] as Map? ?? const {};
    final alias = <String, String>{
      for (final n in (q['normalized'] as List? ?? const [])) n['to'] as String: n['from'] as String,
    };
    for (final p in (q['pages'] as List? ?? const [])) {
      final path = posterPath((p['thumbnail'] as Map?)?['source'] as String?);
      if (path != null) {
        final t = p['title'] as String;
        out[alias[t] ?? t] = path;
      }
    }
  }
  return out;
}

/// Plot summary from Wikipedia, for the "Synopsis" button. Needs network.
Future<String?> fetchSynopsis(String wikiTitle, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final uri = Uri.https(
      'en.wikipedia.org',
      '/api/rest_v1/page/summary/${Uri.encodeComponent(wikiTitle.replaceAll(' ', '_'))}',
    );
    final res = await c.get(uri, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    return (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['extract'] as String?;
  } finally {
    if (client == null) c.close();
  }
}

// ---------------------------------------------------------------------------
// Wikipedia release lists ("List of Hindi films of 2026", ...). Wikidata lags
// behind on new Indian films; these pages are updated within days.

const releaseListLangs = {
  'hi': 'Hindi', 'ta': 'Tamil', 'te': 'Telugu', 'ml': 'Malayalam', 'kn': 'Kannada', 'bn': 'Bengali', 'mr': 'Marathi', //
};

class ReleaseRow {
  const ReleaseRow(this.target, this.label, this.date, this.directors, this.cast);
  final String target, label, date;
  final List<String> directors, cast;
}

const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
final _ref = RegExp(r'<ref[^>/]*/>|<ref[^>]*>.*?</ref>', dotAll: true);
final _titleLink = RegExp(r"''\s*\[\[([^\]|]+)(?:\|([^\]]+))?\]\]\s*''");

/// Splits at the first '|' that is outside [[...]] and {{...}}.
int _topPipe(String s) {
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    if (s.startsWith('[[', i) || s.startsWith('{{', i)) {
      depth++;
      i++;
    } else if (s.startsWith(']]', i) || s.startsWith('}}', i)) {
      depth--;
      i++;
    } else if (s[i] == '|' && depth == 0) {
      return i;
    }
  }
  return -1;
}

/// Cell text without its `style=... |` attribute prefix.
String _content(String cell) {
  final i = _topPipe(cell);
  if (i >= 0 && cell.substring(0, i).contains('=') && !cell.substring(0, i).contains('[[')) {
    return cell.substring(i + 1).trim();
  }
  return cell.trim();
}

/// Plain names from a director or cast cell.
List<String> _names(String cell) {
  final t = cell
      .replaceAll(RegExp(r'\{\{\s*(?:hlist|ubl|plainlist|unbulleted list)\s*\|', caseSensitive: false), '')
      .replaceAll('}}', '')
      .replaceAllMapped(RegExp(r'\[\[([^\]|]+)\|([^\]]+)\]\]'), (m) => m[2]!)
      .replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) => m[1]!)
      .replaceAll(RegExp(r'<br\s*/?>|\*'), ',')
      .replaceAll(RegExp(r"'{2,}"), '');
  return t
      .split(RegExp(r'[,|]|\band\b'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s.length < 60 && !s.contains('{{') && !s.contains('='))
      .toList();
}

/// Reads the release tables of one list page. Only titles with an article count.
List<ReleaseRow> parseReleaseList(String wikitext, int year) {
  final text = wikitext.replaceAll(_ref, '');
  final out = <ReleaseRow>[];
  for (final table in text.split('{|').skip(1)) {
    final body = table.split('\n|}').first;
    if (!body.contains('Opening')) continue;
    int? month, day;
    for (final row in body.split(RegExp(r'\n\|-[^\n]*'))) {
      final cells = <String>[];
      for (final line in row.split('\n')) {
        if (line.startsWith('|') && !line.startsWith('|+')) {
          cells.addAll(line.substring(1).split('||'));
        } else if (line.startsWith('!')) {
          cells.clear();
          break;
        } else if (cells.isNotEmpty) {
          cells[cells.length - 1] += '\n$line';
        }
      }
      final rest = <String>[];
      for (final c in cells.map(_content)) {
        final bold = RegExp(r"^'''(.*)'''$", dotAll: true).firstMatch(c);
        if (bold != null && rest.isEmpty) {
          final inner = bold[1]!
              .replaceAll(RegExp(r'<br\s*/?>'), '')
              .replaceAll(RegExp(r'\{\{\s*vertical text\s*\|', caseSensitive: false), '')
              .replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
          final d = int.tryParse(inner);
          if (d != null) {
            day = d;
          } else if (inner.length >= 3) {
            final m = _months.indexOf(inner.substring(0, 3).toUpperCase());
            if (m >= 0) month = m + 1;
          }
        } else {
          rest.add(c);
        }
      }
      if (month == null || day == null || rest.isEmpty) continue;
      final link = _titleLink.firstMatch(rest.first);
      if (link == null) continue;
      final target = link[1]!.trim();
      final label = (link[2] ?? target.replaceAll(RegExp(r'\s*\([^)]*\)$'), '')).trim();
      out.add(
        ReleaseRow(
          target,
          label,
          '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
          rest.length > 1 ? _names(rest[1]).take(3).toList() : const [],
          rest.length > 2 ? _names(rest[2]).take(6).toList() : const [],
        ),
      );
    }
  }
  return out;
}

/// Films from the current and next year's list pages, resolved to Wikidata ids.
Future<List<Film>> fetchReleaseLists(http.Client c, DateTime today) async {
  final rows = <(String, ReleaseRow)>[];
  for (final year in [today.year, today.year + 1]) {
    for (final MapEntry(key: code, value: name) in releaseListLangs.entries) {
      final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'parse', 'page': 'List of $name films of $year', 'prop': 'wikitext', //
        'format': 'json', 'formatversion': '2', 'redirects': '1',
      });
      final http.Response res;
      try {
        res = await _get(c, uri);
      } catch (_) {
        continue;
      }
      if (res.statusCode != 200) continue;
      final w = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['parse'] as Map?)?['wikitext'] as String?;
      if (w == null) continue;
      rows.addAll(parseReleaseList(w, year).map((r) => (code, r)));
    }
  }
  final info = await _pageInfo(c, rows.map((r) => r.$2.target).toSet().toList());
  final films = <String, Film>{};
  for (final (code, r) in rows) {
    final i = info[r.target];
    if (i == null) continue;
    films.putIfAbsent(
      i.$1,
      () => Film(
        id: i.$1,
        title: r.label,
        year: int.parse(r.date.substring(0, 4)),
        date: r.date,
        directors: r.directors,
        cast: r.cast,
        langs: [code],
        countries: const ['IN'],
        poster: i.$3,
        wiki: i.$2,
        pop: 1,
      ),
    );
  }
  return films.values.toList();
}

/// Title -> (Wikidata id, canonical title, poster path) for article titles.
Future<Map<String, (String, String, String?)>> _pageInfo(http.Client c, List<String> titles) async {
  final out = <String, (String, String, String?)>{};
  for (var i = 0; i < titles.length; i += 50) {
    final batch = titles.sublist(i, math.min(i + 50, titles.length));
    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query', 'prop': 'pageprops|pageimages', 'ppprop': 'wikibase_item', 'piprop': 'thumbnail', //
      'pithumbsize': '330', 'pilicense': 'any', 'titles': batch.join('|'), 'redirects': '1',
      'format': 'json', 'formatversion': '2',
    });
    final http.Response res;
    try {
      res = await _get(c, uri);
    } catch (_) {
      continue;
    }
    if (res.statusCode != 200) continue;
    final q = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['query'] as Map? ?? const {};
    final back = <String, List<String>>{};
    for (final t in batch) {
      back[t] = [t];
    }
    for (final n in [...(q['normalized'] as List? ?? const []), ...(q['redirects'] as List? ?? const [])]) {
      final from = n['from'] as String, to = n['to'] as String;
      (back[to] ??= []).addAll(back[from] ?? [from]);
    }
    for (final p in (q['pages'] as List? ?? const [])) {
      final qid = (p['pageprops'] as Map?)?['wikibase_item'] as String?;
      if (qid == null) continue;
      final poster = posterPath((p['thumbnail'] as Map?)?['source'] as String?);
      final title = p['title'] as String;
      for (final t in back[title] ?? [title]) {
        out[t] = (qid, title, poster);
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Streaming services, read from Wikipedia articles ("streamed on Netflix",
// "digital rights were acquired by Amazon Prime Video", "| network = ...").

/// Service key to the names Wikipedia uses for it (link targets or text).
const _serviceNames = {
  'netflix': ['Netflix'],
  'prime': ['Amazon Prime Video', 'Prime Video', 'Amazon Prime'],
  'jiohotstar': ['JioHotstar', 'Disney+ Hotstar', 'Disney+Hotstar', 'Hotstar', 'JioCinema', 'Voot'],
  'sonyliv': ['SonyLIV', 'Sony LIV'],
  'zee5': ['ZEE5', 'Zee5'],
  'aha': ['Aha (streaming service)', 'Aha (OTT platform)', 'Aha (streaming platform)', 'Aha Video', 'aha video'],
  'sunnxt': ['Sun NXT', 'SunNXT'],
  'manoramamax': ['ManoramaMAX', 'Manorama Max', 'manoramaMAX'],
  'hoichoi': ['Hoichoi', 'hoichoi'],
  'appletv': ['Apple TV+'],
  'mxplayer': ['MX Player'],
  'erosnow': ['Eros Now'],
  'altbalaji': ['ALTBalaji', 'ALT Balaji', 'ALTT'],
  'mubi': ['Mubi', 'MUBI'],
  'lionsgateplay': ['Lionsgate Play'],
  'chaupal': ['Chaupal'],
  'planetmarathi': ['Planet Marathi'],
};

/// Service key for a venue name, such as `prime` for "Prime Video".
String? serviceKey(String venue) {
  final v = norm(venue);
  for (final MapEntry(key: k, value: names) in _serviceNames.entries) {
    if (k == v || names.any((n) => norm(n) == v)) return k;
  }
  return null;
}

final _serviceRx = {
  for (final e in _serviceNames.entries)
    e.key: RegExp('(?<![A-Za-z0-9])(?:${e.value.map(RegExp.escape).join('|')})(?![A-Za-z0-9])'),
};

/// "on Aha" and "by aha": the bare word needs a preposition to be the service.
final _ahaBare = RegExp(r'\b(?:on|by|to|via)\s+[Aa]ha\b');
final _streamWords = RegExp(r'stream|premier|digital|\bOTT\b|direct-to|web series|rights', caseSensitive: false);
final _infoboxService = RegExp(r'^\s*\|\s*(?:network|distributor|distributors|platform)\s*=(.*)$', multiLine: true);

List<String> _servicesIn(String text, {bool bareAha = false}) => [
  for (final e in _serviceRx.entries)
    if (e.value.hasMatch(text) || (bareAha && e.key == 'aha' && _ahaBare.hasMatch(text))) e.key,
];

/// Streaming services an article says the film or series is on.
List<String> ottInWikitext(String wikitext) {
  final text = wikitext.replaceAll(_ref, '').replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final found = <String>{};
  for (final m in _infoboxService.allMatches(text)) {
    found.addAll(_servicesIn(m[1]!));
  }
  for (final sentence in text.split(RegExp(r'(?<=[.!?])\s+|\n'))) {
    if (_streamWords.hasMatch(sentence)) found.addAll(_servicesIn(sentence, bareAha: true));
  }
  return [
    for (final k in _serviceNames.keys)
      if (found.contains(k)) k,
  ];
}

/// Article title -> streaming services, 50 articles per request.
Future<Map<String, List<String>>> fetchStreaming(http.Client c, List<String> titles) async {
  final out = <String, List<String>>{};
  for (var i = 0; i < titles.length; i += 50) {
    final batch = titles.sublist(i, math.min(i + 50, titles.length));
    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query', 'prop': 'revisions', 'rvprop': 'content', 'rvslots': 'main', //
      'titles': batch.join('|'), 'redirects': '1', 'format': 'json', 'formatversion': '2',
    });
    final http.Response res;
    try {
      res = await _get(c, uri);
    } catch (_) {
      continue;
    }
    if (res.statusCode != 200) continue;
    final q = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['query'] as Map? ?? const {};
    final back = <String, List<String>>{
      for (final t in batch) t: [t],
    };
    for (final n in [...(q['normalized'] as List? ?? const []), ...(q['redirects'] as List? ?? const [])]) {
      (back[n['to'] as String] ??= []).addAll(back[n['from'] as String] ?? [n['from'] as String]);
    }
    for (final p in (q['pages'] as List? ?? const [])) {
      final w = ((((p['revisions'] as List?)?.firstOrNull as Map?)?['slots'] as Map?)?['main'] as Map?)?['content'];
      if (w is! String) continue;
      final found = ottInWikitext(w);
      final title = p['title'] as String;
      for (final t in back[title] ?? [title]) {
        out[t] = found;
      }
    }
  }
  return out;
}
