import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/recommend.dart';

// The Taste is what a phone uploads for group decks: traits and weights, no film.

final today = DateTime(2026, 9, 30);

Stub stubOf(Film f, int i, double? rating, {bool fdfs = false, String? place}) => Stub(
  id: '${f.id}-$i',
  no: i + 1,
  filmId: f.id,
  created: DateTime(2026, 9),
  date: DateTime(2026, 8, 1 + i % 28),
  rating: rating,
  fdfs: fdfs,
  place: place,
);

List<Film> pick(Catalog c, bool Function(Film) where, int n) =>
    c.items.where((f) => f.poster != null && where(f)).take(n).toList();

Map<String, Diary> diaries(Catalog c) {
  final hi = pick(c, (f) => f.langs.contains('hi') && f.year != null && f.year! < 2026, 10);
  final ta = pick(c, (f) => f.langs.contains('ta') && f.year != null && f.year! < 2026, 10);
  final any = pick(c, (f) => f.year != null && f.year! < 2026 && !f.series, 18);
  const hiRatings = [5.0, 4.5, 4.0, 3.0, 5.0, 2.0, 4.0, 3.5, 4.5, 1.0];
  const taRatings = [5.0, 5.0, 4.0, 4.0, 3.0, 3.0, 2.0, 4.5, 4.0, 3.5];
  // A very full diary: 700 viewings with ratings, wishes, and places.
  final big = pick(c, (f) => f.year != null && f.year! < 2026, 700);
  return {
    'hindi': Diary(stubs: [for (var i = 0; i < hi.length; i++) stubOf(hi[i], i, hiRatings[i])]),
    'tamil': Diary(stubs: [for (var i = 0; i < ta.length; i++) stubOf(ta[i], i, taRatings[i])]),
    'mixed': Diary(
      stubs: [for (var i = 0; i < 12; i++) stubOf(any[i], i, i.isEven ? null : 4.0)],
      wishes: [for (final f in any.skip(12).take(4)) Wish(filmId: f.id, added: DateTime(2026, 9))],
      hidden: [for (final f in any.skip(16)) f.id],
    ),
    'full': Diary(
      stubs: [
        for (var i = 0; i < big.length; i++)
          stubOf(
            big[i],
            i,
            [1.0, 2.5, 3.0, 4.0, 4.5, 5.0][i % 6],
            fdfs: i % 9 == 0,
            place: i.isEven ? 'Netflix' : 'Prime Video',
          ),
      ],
    ),
  };
}

Film film(String id, {List<String> dir = const [], List<String> cast = const [], List<String> g = const []}) => Film(
  id: id,
  title: id,
  directors: dir,
  cast: cast,
  genres: g,
  langs: const ['hi'],
  countries: const ['IN'],
  date: '2010-01-01',
  year: 2010,
  poster: '$id.jpg',
  pop: 10,
);

Stub stub(String filmId, double? rating) =>
    Stub(id: filmId, no: 1, filmId: filmId, created: DateTime(2026, 9), date: DateTime(2026, 9, 1), rating: rating);

void main() {
  final c = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync(), null);
  final tastes = {for (final e in diaries(c).entries) e.key: buildTaste(c, e.value, today)};

  test('every golden diary has a taste', () {
    for (final e in tastes.entries) {
      expect(e.value, isNotNull, reason: e.key);
    }
  });

  test('a taste is a few KB, under the 24 KB cap, however big the diary', () {
    for (final e in tastes.entries) {
      final json = e.value!.toJson();
      final bytes = utf8.encode(jsonEncode(json)).length;
      expect(bytes, lessThan(24 * 1024), reason: '${e.key}: $bytes bytes');
      expect((json['t'] as Map).length, lessThanOrEqualTo(150), reason: e.key);
      expect((json['l'] as Map).length, lessThanOrEqualTo(8), reason: e.key);
      expect((json['e'] as Map).length, lessThanOrEqualTo(12), reason: e.key);
      expect((json['s'] as List).length, lessThanOrEqualTo(10), reason: e.key);
    }
    // The full diary hits the trait cap: the cap is what keeps it small.
    expect((tastes['full']!.toJson()['t'] as Map).length, 150);
  });

  test('it carries no film: only traits, languages, eras, kinds and services', () {
    for (final e in tastes.entries) {
      final json = e.value!.toJson();
      expect(json.keys.toSet(), {'v', 't', 'l', 'e', 'k', 's'}, reason: e.key);
      final text = jsonEncode(json);
      for (final s in diaries(c)[e.key]!.stubs.take(50)) {
        expect(text, isNot(contains('"${s.filmId}"')), reason: '${e.key} leaks ${s.filmId}');
      }
    }
  });

  test('tryFromJson gives back what toJson wrote', () {
    for (final e in tastes.entries) {
      final json = jsonDecode(jsonEncode(e.value!.toJson())) as Map<String, dynamic>;
      final back = Taste.tryFromJson(json);
      expect(back, isNotNull, reason: e.key);
      // Equal as data. Keys of equal weight may change places once the weights are tenths.
      expect(jsonDecode(jsonEncode(back!.toJson())), json, reason: e.key);
    }
  });

  test('a parsed taste ranks nearly like the one it came from', () {
    final original = tastes['hindi']!;
    final parsed = Taste.tryFromJson(jsonDecode(jsonEncode(original.toJson())))!;
    List<String> top(Taste t) {
      final scored = [
        for (final f in c.items.take(3000))
          if (scoreFor(c, f, t) case final s?) (s, f.id),
      ]..sort((a, b) => b.$1.compareTo(a.$1));
      return [for (final (_, id) in scored.take(20)) id];
    }

    final a = top(original).toSet(), b = top(parsed).toSet();
    expect(a, hasLength(20));
    expect(a.intersection(b).length, greaterThanOrEqualTo(14), reason: 'tenths are enough');
  });

  test('anything that is not a taste gives null, never an exception', () {
    final good = tastes['hindi']!.toJson();
    final bad = <Object?>[
      null,
      'text',
      42,
      <String, dynamic>{},
      [1, 2],
      {'v': 2},
      {...good, 'v': 0},
      {...good, 't': 'x'},
      {
        ...good,
        't': {'a': 'x'},
      },
      {...good, 'l': null},
      {
        ...good,
        'e': {'abc': 1},
      },
      {...good, 'e': []},
      {
        ...good,
        'k': [1],
      },
      {
        ...good,
        'k': [1, 2, 3],
      },
      {
        ...good,
        'k': ['a', 'b'],
      },
      {...good, 's': 'netflix'},
      {
        ...good,
        's': [1],
      },
      {'v': 1},
    ];
    for (final b in bad) {
      expect(Taste.tryFromJson(b), isNull, reason: '$b');
    }
  });

  test('scoreFor puts a film that shares a liked director above an unrelated one', () {
    final cat = Catalog([
      film('liked', dir: ['X'], g: ['drama']),
      film('twin', dir: ['X'], g: ['drama']),
      film('other', dir: ['Y'], g: ['comedy']),
      film('bad', dir: ['Z'], g: ['horror']),
      film('badtwin', dir: ['Z'], g: ['horror']),
      film('stranger', dir: ['Q'], g: ['western']),
    ], '');
    final taste = buildTaste(cat, Diary(stubs: [stub('liked', 5), stub('bad', 1), stub('other', 4)]), today)!;
    final twin = scoreFor(cat, cat.byId['twin']!, taste);
    final stranger = scoreFor(cat, cat.byId['stranger']!, taste);
    expect(twin, isNotNull);
    expect(stranger, isNull, reason: 'shares nothing the viewer liked');
    expect(twin! > (stranger ?? 0), isTrue);
    // A film that shares only a disliked trait is not a match either.
    expect(scoreFor(cat, cat.byId['badtwin']!, taste), isNull);
    // Directors beat a lone genre.
    final byGenre = Catalog([
      film('seed', dir: ['X'], g: ['drama']),
      film('dirMatch', dir: ['X']),
      film('genreMatch', dir: ['W'], g: ['drama']),
    ], '');
    final t2 = buildTaste(byGenre, Diary(stubs: [stub('seed', 5)]), today)!;
    expect(
      scoreFor(byGenre, byGenre.byId['dirMatch']!, t2)!,
      greaterThan(scoreFor(byGenre, byGenre.byId['genreMatch']!, t2)!),
    );
  });

  test('no liked film, no taste', () {
    final cat = Catalog([
      film('a', dir: ['X']),
    ], '');
    expect(buildTaste(cat, const Diary(), today), isNull);
    expect(buildTaste(cat, Diary(stubs: [stub('a', 1)]), today), isNull);
  });

  test('the taste is built from the public view, so private stubs count for nothing', () {
    // SyncEngine.pushTaste passes diary.publicView(); the private stub must not
    // leak its traits even then. (ProfileView.fromDiary has the same rule in
    // test/online/social_test.dart.)
    final cat = Catalog([
      film('pub', dir: ['Pub Dir'], g: ['drama']),
      film('hid', dir: ['Hid Dir'], g: ['horror']),
    ], '');
    final full = Diary(
      stubs: [
        stub('pub', 5),
        Stub(
          id: 'hid',
          no: 2,
          filmId: 'hid',
          created: DateTime(2026, 9),
          date: DateTime(2026, 9, 2),
          rating: 5,
          private: true,
        ),
      ],
    );
    final t = buildTaste(cat, full.publicView(), today)!;
    final traits = (t.toJson()['t'] as Map).keys;
    expect(traits, contains('Pub Dir'));
    expect(traits, isNot(contains('Hid Dir')));
  });
}
