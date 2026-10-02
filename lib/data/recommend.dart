import 'dart:math' as math;

import 'catalog.dart';
import 'models.dart';

// Recommendations from the diary alone: no network, no other users. Each
// catalog film gets a score from the traits (people, genres, franchise) it
// shares with films the user liked, then language, era and kind preferences.
// The constants below are the tuning knobs.

// Trait weights.
const _dirW = 3.0;
const _castW = [2.0, 1.6, 1.3, 1.0, 0.8, 0.6]; // by position, most famous first
const _genreW = 1.0;
const _stemW = 4.0;

// Signal per diary film.
const _unrated = 0.5;
const _rewatch = 0.5, _rewatchMax = 1.5;
const _fdfsBonus = 0.25;
const _halfLifeDays = 540.0, _minRecency = 0.35;
const _wishW = 0.6;
const _hiddenW = -0.5;

// Candidate factors.
const _noPoster = 0.6;
const _serviceBoost = 1.15;
const _jitterW = 0.08;

// Rows.
const _forYouSize = 12, _rowSize = 10, _rowMin = 4, _anchorPool = 5;
const _pool = 300;
const _sameness = 0.7; // score factor per picked film that shares a director, franchise or lead

/// Home recommendations: one blended row, and up to two rows that each follow
/// one film the user loved.
class Recs {
  const Recs({this.forYou = const [], this.because = const []});
  final List<Film> forYou;
  final List<(Film, List<Film>)> because;

  static const none = Recs();
}

final _sequelMark = RegExp(r'\s*[:(–—]|\s+(?:\d{1,2}|ii|iii|iv|part|chapter|returns)\b', caseSensitive: false);

/// Normalized title before a sequel mark, as a trait key: "K.G.F: Chapter 2"
/// and "K.G.F: Chapter 1" both give `#kgf`. Null when shorter than 3 letters.
// ponytail: title heuristic; Wikidata P179 (part of the series) in build_catalog.py would be exact
String? titleStem(String title) => _stem(title).$1;

(String?, bool) _stem(String title) {
  final m = _sequelMark.firstMatch(title);
  final s = norm(m == null ? title : title.substring(0, m.start));
  return (s.length < 3 ? null : '#$s', m != null);
}

/// [titleStem] for each film, kept only when another film shares it and one
/// of them has a sequel mark: Dhoom and Dhoom 2 are linked, but two unrelated
/// films both named Kaithi are not.
List<String?> stemsOf(List<Film> items) {
  final all = [for (final f in items) _stem(f.title)];
  final n = <String, int>{};
  final marked = <String>{};
  for (final (s, m) in all) {
    if (s == null) continue;
    n[s] = (n[s] ?? 0) + 1;
    if (m) marked.add(s);
  }
  return [for (final (s, _) in all) s != null && n[s]! > 1 && marked.contains(s) ? s : null];
}

/// How many films carry each trait, for the IDF. Traits of one film only are
/// left out; the IDF reads a missing trait as a count of 1.
Map<String, int> traitCounts(List<Film> items, List<String?> stems) {
  final df = <String, int>{};
  final seen = <String>{};
  for (var i = 0; i < items.length; i++) {
    seen.clear();
    _traits(items[i], stems[i], (t, _) {
      if (seen.add(t)) df[t] = (df[t] ?? 0) + 1;
    });
  }
  df.removeWhere((_, n) => n < 2);
  return df;
}

/// Calls [visit] with each trait of [f] and its weight. Directors and cast
/// share one key space, so a director who also acts is one person. Genre keys
/// do not collide with names; stems start with `#`.
void _traits(Film f, String? stem, void Function(String t, double w) visit) {
  for (final x in f.directors) {
    visit(x, _dirW);
  }
  for (var i = 0; i < f.cast.length && i < _castW.length; i++) {
    visit(f.cast[i], _castW[i]);
  }
  for (final x in f.genres) {
    visit(x, _genreW);
  }
  if (stem != null) visit(stem, _stemW);
}

double _idf(Catalog c, String t) => math.log(1 + c.items.length / (c.df[t] ?? 1));

/// What the diary says about one viewer, in the terms [scoreFor] needs: weights
/// of traits (people, genres, franchises), languages, eras, kinds and services.
/// It holds no film, so a group can share it as [toJson].
class Taste {
  Taste({required this.traits, required this.lang, required this.era, required this.kind, required this.services})
    : langMax = lang.values.fold(0.0, math.max),
      eraMax = era.values.fold(0.0, math.max),
      kindMax = math.max(kind[0], kind[1]);

  /// Trait to weight (idf included). Below 0 for traits of disliked films.
  final Map<String, double> traits;
  final Map<String, double> lang;

  /// Decade (`year ~/ 10`) to weight, each smoothed with its neighbours.
  final Map<int, double> era;

  /// Film weight, series weight.
  final List<double> kind;
  final Set<String> services;
  final double langMax, eraMax, kindMax;

  static const _version = 1;

  static int _q(double w) => (w * 10).round();

  static List<MapEntry<K, double>> _top<K>(Map<K, double> m, int n) {
    final e = m.entries.toList()
      ..sort((a, b) {
        final c = b.value.abs().compareTo(a.value.abs());
        return c != 0 ? c : '${a.key}'.compareTo('${b.key}');
      });
    return e.take(n).toList();
  }

  /// The strongest traits, weights in tenths: a few KB however big the diary.
  Map<String, dynamic> toJson({int maxTraits = 150}) => {
    'v': _version,
    't': {
      for (final e in _top(traits, maxTraits))
        if (_q(e.value) != 0) e.key: _q(e.value),
    },
    'l': {
      for (final e in _top(lang, 8))
        if (_q(e.value) != 0) e.key: _q(e.value),
    },
    'e': {
      for (final e in _top(era, 12))
        if (_q(e.value) != 0) '${e.key}': _q(e.value),
    },
    'k': [_q(kind[0]), _q(kind[1])],
    's': (services.toList()..sort()).take(10).toList(),
  };

  /// Null for anything that is not a Taste: one bad upload must not break a deck.
  static Taste? tryFromJson(Object? j) {
    try {
      if (j is! Map || j['v'] != _version) return null;
      Map<String, double> weights(Object? o) => {
        for (final e in (o as Map).entries) e.key as String: (e.value as num) / 10,
      };
      final k = [for (final x in j['k'] as List) (x as num) / 10];
      if (k.length != 2) return null;
      return Taste(
        traits: weights(j['t']),
        lang: weights(j['l']),
        era: {for (final e in (j['e'] as Map).entries) int.parse(e.key as String): (e.value as num) / 10},
        kind: k,
        services: {for (final x in j['s'] as List) x as String},
      );
    } catch (_) {
      return null;
    }
  }
}

/// The viewer's taste, or null when the diary holds no liked film.
Taste? buildTaste(Catalog c, Diary d, DateTime today) {
  final signal = _signals(d, today);
  return signal.values.any((w) => w > 0) ? _taste(c, d, today, signal) : null;
}

Taste _taste(Catalog c, Diary d, DateTime today, Map<String, double> signal) {
  final traits = <String, double>{};
  final lang = <String, double>{};
  final decade = <int, double>{};
  final kind = [0.0, 0.0]; // film, series
  for (final MapEntry(key: id, value: w) in signal.entries) {
    final f = c.byId[id] ?? d.films[id];
    if (f == null) continue;
    _traits(f, titleStem(f.title), (t, tw) => traits[t] = (traits[t] ?? 0) + w * tw * _idf(c, t));
    if (w <= 0) continue;
    if (f.mainLang case final l?) lang[l] = (lang[l] ?? 0) + w;
    if (f.year case final y?) decade[y ~/ 10] = (decade[y ~/ 10] ?? 0) + w;
    kind[f.series ? 1 : 0] += w;
  }
  for (final s in d.stubs) {
    final w = signal[s.filmId]!;
    if (s.lang case final l? when w > 0) lang[l] = (lang[l] ?? 0) + w;
  }
  final era = {
    for (final k in decade.keys.expand((k) => [k - 1, k, k + 1]))
      k: (decade[k] ?? 0) + 0.5 * ((decade[k - 1] ?? 0) + (decade[k + 1] ?? 0)),
  };

  final yearAgo = today.subtract(const Duration(days: 365));
  final places = {
    for (final s in d.stubs)
      if (s.place != null && (s.date ?? s.created).isAfter(yearAgo)) s.place!,
  };
  return Taste(traits: traits, lang: lang, era: era, kind: kind, services: {for (final p in places) ?serviceKey(p)});
}

typedef _Fit = ({double rel, double damp, double base, double score});

/// One film against one taste. [visit] sees each trait of the film with its
/// idf-weighted value. A null [day] leaves out the daily jitter.
_Fit? _fit(Catalog c, Film f, String? stem, Taste t, int? day, [void Function(String trait, double x)? visit]) {
  var rel = 0.0, len = 0.0;
  _traits(f, stem, (tr, w) {
    final x = w * _idf(c, tr);
    len += x * x;
    rel += x * (t.traits[tr] ?? 0);
    visit?.call(tr, x);
  });
  if (len == 0) return null;
  final damp = math.pow(len, 0.25); // |c|^0.5
  final base = _langF(f, t.lang, t.langMax) * _quality(f) * (day == null ? 1.0 : _jitter(f.id, day));
  final era = t.eraMax == 0 || f.year == null ? 1.0 : 0.7 + 0.3 * (t.era[f.year! ~/ 10] ?? 0) / t.eraMax;
  final kind = t.kindMax == 0 ? 1.0 : 0.3 + 0.7 * t.kind[f.series ? 1 : 0] / t.kindMax;
  final service = f.ott.any(t.services.contains) ? _serviceBoost : 1.0;
  return (rel: rel, damp: damp.toDouble(), base: base, score: rel / damp * base * era * kind * service);
}

/// How well [f] fits [t]: higher is better, null when it shares no liked trait.
/// Scores only compare within one taste. Release, region and "already seen"
/// are the caller's business.
double? scoreFor(Catalog c, Film f, Taste t) {
  final fit = _fit(c, f, c.stemOf(f), t, null);
  return fit == null || fit.rel <= 0 ? null : fit.score;
}

Recs recommend(Catalog c, Diary d, DateTime today, {bool worldwide = false}) {
  final signal = _signals(d, today);
  if (!signal.values.any((w) => w > 0)) return Recs.none;
  final taste = _taste(c, d, today, signal);
  Map<String, double> vector(Film f, String? stem) {
    final v = <String, double>{};
    _traits(f, stem, (t, w) => v[t] = (v[t] ?? 0) + w * _idf(c, t));
    return v;
  }

  final day = today.difference(DateTime(2000)).inDays;

  // Up to 2 anchors from the top 5 liked catalog films, rotating by day.
  // Watched only: a watchlist film is not one the user "liked".
  final watched = {for (final s in d.stubs) s.filmId};
  final liked = [
    for (final e in signal.entries)
      if (e.value > 0 && watched.contains(e.key) && c.byId[e.key] != null) e,
  ]..sort((a, b) => b.value.compareTo(a.value));
  final top = [for (final e in liked.take(_anchorPool)) c.byId[e.key]!];
  final anchors = [if (top.isNotEmpty) top[day % top.length], if (top.length > 1) top[(day + 1) % top.length]];
  final anchorTraits = [for (final a in anchors) vector(a, titleStem(a.title))];

  // One pass over the catalog.
  final t0 = ymd(today);
  final forYouPool = <(double, int)>[];
  final rowPools = [for (final _ in anchors) <(double, int)>[]];
  for (var i = 0; i < c.items.length; i++) {
    final f = c.items[i];
    // No year, or this year with no date, is mostly an announced film.
    if (f.year == null || (f.date == null && f.year! >= today.year)) continue;
    if (signal.containsKey(f.id) || unreleased(f, t0) || !(worldwide || isIndian(f))) continue;
    final ar = List.filled(anchors.length, 0.0);
    final fit = _fit(c, f, c.stems[i], taste, day, (t, x) {
      for (var k = 0; k < ar.length; k++) {
        ar[k] += x * (anchorTraits[k][t] ?? 0);
      }
    });
    if (fit == null) continue;
    if (fit.rel > 0) forYouPool.add((fit.score, i));
    for (var k = 0; k < ar.length; k++) {
      if (ar[k] > 0 && fit.rel > 0) rowPools[k].add((ar[k] / fit.damp * fit.base, i));
    }
  }

  final taken = <int>{};
  final forYou = diverse(c, forYouPool, _forYouSize, taken);
  final because = <(Film, List<Film>)>[];
  for (var k = 0; k < anchors.length; k++) {
    final row = diverse(c, rowPools[k], _rowSize, taken);
    if (row.length >= _rowMin) {
      because.add((anchors[k], [for (final i in row) c.items[i]]));
    } else {
      // A dropped row must not reserve its films: a later anchor may fill the
      // row with them.
      taken.removeAll(row);
    }
  }
  return Recs(forYou: [for (final i in forYou) c.items[i]], because: because);
}

/// How much each diary film says about taste: above 0 for liked, below for
/// disliked. Ratings are read against the user's own mean and spread.
Map<String, double> _signals(Diary d, DateTime today) {
  final best = <String, double>{};
  final views = <String, int>{};
  final last = <String, DateTime>{};
  final fdfs = <String>{};
  for (final s in d.stubs) {
    views[s.filmId] = (views[s.filmId] ?? 0) + 1;
    if (s.rating case final r? when r > (best[s.filmId] ?? -1)) best[s.filmId] = r;
    final t = s.date ?? s.created;
    if (!(last[s.filmId]?.isAfter(t) ?? false)) last[s.filmId] = t;
    if (s.fdfs) fdfs.add(s.filmId);
  }
  var mean = 3.0, spread = 1.0;
  if (best.length >= 3) {
    mean = best.values.reduce((a, b) => a + b) / best.length;
    final v = best.values.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / best.length;
    // Every film rated the same: the diary has no scale of its own, so centering
    // would make every rating 0 and leave the diary with no taste at all. Read
    // the ratings against the app's own 0.1-5 scale instead.
    if (v < 1e-9) {
      mean = 3.0;
    } else {
      spread = math.max(0.5, math.sqrt(v));
    }
  }
  double recency(DateTime t) =>
      math.pow(0.5, today.difference(t).inDays / _halfLifeDays).toDouble().clamp(_minRecency, 1.0);

  final out = <String, double>{};
  for (final MapEntry(key: id, value: n) in views.entries) {
    final r = best[id];
    var z = r == null ? _unrated : ((r - mean) / spread).clamp(-2.0, 2.0);
    z += math.min(_rewatchMax, _rewatch * (n - 1));
    if (fdfs.contains(id)) z += _fdfsBonus;
    out[id] = z * recency(last[id]!);
  }
  for (final w in d.wishes) {
    out.putIfAbsent(w.filmId, () => _wishW * recency(w.added));
  }
  // A later viewing or watchlist entry outranks "Not interested".
  for (final id in d.hidden) {
    out.putIfAbsent(id, () => _hiddenW);
  }
  return out;
}

double _langF(Film f, Map<String, double> lang, double max) {
  if (max == 0) return 1;
  if (f.langs.isEmpty) return 0.5;
  final best = f.langs.map((l) => lang[l] ?? 0).fold(0.0, math.max);
  return 0.15 + 0.85 * best / max;
}

double _quality(Film f) => (1 + math.log(f.pop + 1) / 4) * (f.poster == null ? _noPoster : 1);

/// Stable for a day, different the next: FNV-1a over the id, seeded by the day.
double _jitter(String id, int day) {
  var h = 0x811c9dc5 ^ day;
  for (final u in id.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xffffffff;
  }
  return 1 + _jitterW * (h & 0xffff) / 0xffff;
}

/// Best [n] of [scored] (catalog index), not in [taken], each one scored down
/// by [_sameness] per earlier pick with the same director, franchise or lead.
/// Adds the picks to [taken]. Sorts [scored] in place; equal scores keep no
/// promised order, so callers that need one give each film a distinct score.
List<int> diverse(Catalog c, List<(double, int)> scored, int n, Set<int> taken) {
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  final pool = [
    for (final e in scored.take(_pool + taken.length))
      if (!taken.contains(e.$2)) e,
  ];
  final picked = <int>[];
  while (picked.length < n && pool.isNotEmpty) {
    var bj = 0;
    var bs = -1.0;
    for (var j = 0; j < pool.length; j++) {
      final (s, i) = pool[j];
      if (s <= bs) break; // sorted, and the factor is at most 1
      final p = s * math.pow(_sameness, overlap(c, i, picked));
      if (p > bs) (bs, bj) = (p.toDouble(), j);
    }
    picked.add(pool.removeAt(bj).$2);
  }
  taken.addAll(picked);
  return picked;
}

int overlap(Catalog c, int i, List<int> picked) {
  final f = c.items[i], stem = c.stems[i];
  var n = 0;
  for (final j in picked) {
    final g = c.items[j];
    if ((stem != null && stem == c.stems[j]) ||
        f.directors.any(g.directors.contains) ||
        (f.cast.isNotEmpty && g.cast.isNotEmpty && f.cast.first == g.cast.first)) {
      n++;
    }
  }
  return n;
}
