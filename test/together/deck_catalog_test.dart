import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/data/deck.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/recommend.dart';

import 'helpers.dart';

// The deck on the real catalog: two people with different tastes, one phone.

final today = DateTime(2026, 9, 30);

Stub stubOf(Film f, int i, double rating) => Stub(
  id: '${f.id}-$i',
  no: i + 1,
  filmId: f.id,
  created: DateTime(2026, 9),
  date: DateTime(2026, 8, 1 + i % 28),
  rating: rating,
);

Diary diaryOf(Catalog c, String lang) {
  final films = c.items
      .where((f) => f.poster != null && f.langs.contains(lang) && f.year != null && f.year! < 2026)
      .take(12)
      .toList();
  return Diary(
    stubs: [
      for (var i = 0; i < films.length; i++) stubOf(films[i], i, [5.0, 4.5, 4.0, 3.0, 5.0, 4.0][i % 6]),
    ],
  );
}

void main() {
  final c = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync(), null);
  final hindi = buildTaste(c, diaryOf(c, 'hi'), today)!;
  final tamil = buildTaste(c, diaryOf(c, 'ta'), today)!;
  final seenByHindi = {for (final s in diaryOf(c, 'hi').stubs) s.filmId};

  List<DeckCard> deck(
    List<Taste> tastes, {
    Set<String> seen = const {},
    List<Wanted> wanted = const [],
    bool worldwide = false,
  }) {
    final sw = Stopwatch()..start();
    final d = buildDeck(
      catalog: c,
      tastes: tastes,
      members: tastes.length,
      wanted: wanted,
      seen: seen,
      today: today,
      worldwide: worldwide,
    );
    // ignore: avoid_print
    print('buildDeck for ${tastes.length} member(s): ${sw.elapsedMilliseconds} ms, ${d.length} cards');
    expect(
      sw.elapsedMilliseconds,
      lessThan(10000),
      reason: 'a few hundred ms on a phone; this only guards against a blow-up',
    );
    return d;
  }

  test('a deck for one person: 60 recommendations of their taste, none they have seen', () {
    final d = deck([hindi], seen: seenByHindi);
    expect(d, hasLength(deckRecs));
    expect(ids(d).toSet().intersection(seenByHindi), isEmpty);
    expect(
      d.take(20).where((x) => x.film.langs.contains('hi')).length,
      greaterThan(10),
      reason: 'a Hindi taste gets Hindi films first',
    );
  });

  test('every recommendation is released, regional and a film', () {
    final d = deck([hindi, tamil]);
    final t0 = ymd(today);
    for (final x in d) {
      final f = x.film;
      expect(f.series, isFalse, reason: f.title);
      expect(unreleased(f, t0), isFalse, reason: f.title);
      expect(isIndian(f), isTrue, reason: f.title);
      expect(f.year, isNotNull, reason: f.title);
    }
    expect(ids(d).toSet(), hasLength(d.length));
  });

  test('two different tastes: the middle ground comes first and the same inputs give the same deck', () {
    final both = deck([hindi, tamil]);
    expect(ids(deck([tamil, hindi])), ids(both), reason: 'member order does not matter');
    final onlyHindi = deck([hindi]);
    expect(ids(both.take(10)), isNot(ids(onlyHindi.take(10))));
  });

  test('a watchlist film from the catalog keeps its place and counts its wishers', () {
    final wanted = [
      for (final f in c.items.where((f) => f.langs.contains('te') && f.poster != null).take(5)) (film: f, n: 2),
    ];
    final d = deck([hindi, tamil], wanted: wanted);
    expect(d, hasLength(deckRecs + 5));
    final byId = {for (final x in d) x.id: x};
    for (final w in wanted) {
      expect(byId[w.film.id]!.wishers, 2);
    }
  });

  test('worldwide opens the catalog to films from anywhere', () {
    final local = deck([hindi]);
    final world = deck([hindi], worldwide: true);
    expect(local.every((x) => isIndian(x.film)), isTrue);
    expect(world, hasLength(deckRecs));
  });
}
