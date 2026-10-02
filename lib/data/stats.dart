import 'package:flutter/material.dart' show DateUtils;

import 'models.dart';

enum StatsScope { month, year, all }

class Period {
  const Period(this.scope, this.year, [this.month = 1]);
  final StatsScope scope;
  final int year, month;

  Period shift(int by) => switch (scope) {
    StatsScope.month => Period(scope, DateTime(year, month + by).year, DateTime(year, month + by).month),
    StatsScope.year => Period(scope, year + by),
    StatsScope.all => this,
  };

  bool contains(Stub s) {
    if (scope == StatsScope.all) return true;
    if (!s.hasDate || s.date!.year != year) return false;
    if (scope == StatsScope.year) return true;
    return s.precision != DatePrecision.year && s.date!.month == month;
  }

  @override
  bool operator ==(Object other) =>
      other is Period && other.scope == scope && other.year == year && other.month == month;
  @override
  int get hashCode => Object.hash(scope, year, month);
}

class Bucket {
  Bucket(this.key);
  final String key;
  final List<Stub> stubs = [];
  int get count => stubs.length;
}

class Stats {
  Stats({
    required this.stubs,
    required this.minutes,
    required this.spent,
    required this.paidCount,
    required this.fdfs,
    required this.rewatches,
    required this.avgRating,
    required this.timeline,
    required this.stars,
    required this.places,
    required this.venueTypes,
    required this.genres,
    required this.countries,
    required this.languages,
    required this.directors,
    required this.actors,
    required this.tags,
    required this.decades,
    required this.formats,
    required this.shows,
  });

  final List<Stub> stubs;
  int get count => stubs.length;

  /// Runtime of films only; series have no single runtime.
  final int minutes;

  /// Total ticket spend in rupees, and how many stubs had a price.
  final double spent;
  final int paidCount;
  final int fdfs;
  final int rewatches;
  final double? avgRating;

  /// Days of the month, months of the year, or years (all time), in order.
  final List<Bucket> timeline;

  /// Keys '5' to '1', then 'none'. A rating counts toward its rounded star.
  final List<Bucket> stars;

  /// Sorted by count, highest first.
  final List<Bucket> places, venueTypes, genres, countries, languages, directors, actors, tags, decades, formats, shows;
}

List<Bucket> _ranked(Map<String, Bucket> m) =>
    m.values.toList()..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.key.compareTo(b.key));

void _add(Map<String, Bucket> m, String key, Stub s) => (m[key] ??= Bucket(key)).stubs.add(s);

Stats computeStats(Diary d, Period p) {
  final stubs = d.stubs.where(p.contains).toList()..sort(byWatchOrder);

  final timeline = <Bucket>[];
  switch (p.scope) {
    case StatsScope.month:
      final days = DateUtils.getDaysInMonth(p.year, p.month);
      for (var i = 1; i <= days; i++) {
        timeline.add(Bucket('$i'));
      }
      for (final s in stubs) {
        if (s.precision == DatePrecision.day) timeline[s.date!.day - 1].stubs.add(s);
      }
    case StatsScope.year:
      for (var i = 1; i <= 12; i++) {
        timeline.add(Bucket('$i'));
      }
      for (final s in stubs) {
        if (s.precision != DatePrecision.year) timeline[s.date!.month - 1].stubs.add(s);
      }
    case StatsScope.all:
      final years = stubs.where((s) => s.hasDate).map((s) => s.date!.year).toList();
      if (years.isNotEmpty) {
        final lo = years.reduce((a, b) => a < b ? a : b), hi = years.reduce((a, b) => a > b ? a : b);
        for (var y = lo; y <= hi; y++) {
          timeline.add(Bucket('$y'));
        }
        for (final s in stubs) {
          if (s.hasDate) timeline[s.date!.year - lo].stubs.add(s);
        }
      }
  }

  final stars = {
    for (final k in ['5', '4', '3', '2', '1', 'none']) k: Bucket(k),
  };
  final places = <String, Bucket>{}, types = <String, Bucket>{}, genres = <String, Bucket>{};
  final countries = <String, Bucket>{}, languages = <String, Bucket>{}, directors = <String, Bucket>{};
  final actors = <String, Bucket>{}, tags = <String, Bucket>{}, decades = <String, Bucket>{};
  final formats = <String, Bucket>{}, shows = <String, Bucket>{};
  // First viewing of every film, across all time.
  final first = <String, Stub>{};
  for (final s in d.stubs) {
    final f = first[s.filmId];
    if (f == null || byWatchOrder(s, f) < 0) first[s.filmId] = s;
  }
  var minutes = 0, fdfs = 0, rewatches = 0, paid = 0, rated = 0;
  double spent = 0, ratingSum = 0;

  for (final s in stubs) {
    final f = d.films[s.filmId];
    final r = s.rating;
    if (r == null) {
      stars['none']!.stubs.add(s);
    } else {
      stars['${r.round().clamp(1, 5)}']!.stubs.add(s);
      ratingSum += r;
      rated++;
    }
    if (s.place != null) _add(places, s.place!, s);
    _add(types, d.venueType(s.place).name, s);
    for (final t in s.tags) {
      _add(tags, t, s);
    }
    if (s.format != null) _add(formats, s.format!, s);
    if (s.show != null) _add(shows, s.show!, s);
    if (s.fdfs) fdfs++;
    if (s.price != null) {
      spent += s.price!;
      paid++;
    }
    if (first[s.filmId]!.id != s.id) rewatches++;
    if (f == null) continue;
    if (!f.series) minutes += f.runtime ?? 0;
    // One viewing counts once per distinct genre: a synced snapshot may repeat
    // a value in its `g` list.
    for (final g in f.genres.toSet()) {
      _add(genres, g, s);
    }
    for (final c in f.countries) {
      _add(countries, c, s);
    }
    final lang = s.lang ?? f.mainLang;
    if (lang != null) _add(languages, lang, s);
    for (final x in f.directors) {
      _add(directors, x, s);
    }
    for (final x in f.cast) {
      _add(actors, x, s);
    }
    if (f.year != null) _add(decades, '${f.year! ~/ 10 * 10}', s);
  }

  return Stats(
    stubs: stubs,
    minutes: minutes,
    spent: spent,
    paidCount: paid,
    fdfs: fdfs,
    rewatches: rewatches,
    avgRating: rated == 0 ? null : ratingSum / rated,
    timeline: timeline,
    stars: stars.values.toList(),
    places: _ranked(places),
    venueTypes: _ranked(types),
    genres: _ranked(genres),
    countries: _ranked(countries),
    languages: _ranked(languages),
    directors: _ranked(directors),
    actors: _ranked(actors),
    tags: _ranked(tags),
    decades: _ranked(decades)..sort((a, b) => a.key.compareTo(b.key)),
    formats: _ranked(formats),
    shows: _ranked(shows),
  );
}
