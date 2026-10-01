import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/data/deck.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/recommend.dart';

import 'helpers.dart';

final today = DateTime(2026, 10, 1);

/// 30 films of director DA, 30 of DB, 10 with lead S, and three that never qualify
/// as recommendations: a series, an unreleased film and a foreign one.
List<Film> films() => [
  for (var i = 1; i <= 30; i++) film('a$i', dir: ['DA'], pop: 40 - i),
  for (var i = 1; i <= 30; i++) film('b$i', dir: ['DB'], pop: 40 - i),
  for (var i = 1; i <= 10; i++) film('s$i', cast: ['S'], pop: 20 - i),
  film('series', dir: ['DA'], series: true),
  film('future', dir: ['DA'], date: '2030-01-01'),
  const Film(
    id: 'foreign',
    title: 'foreign',
    directors: ['DA'],
    langs: ['en'],
    countries: ['US'],
    year: 2015,
    date: '2015-01-01',
  ),
];

List<DeckCard> build(
  List<Taste> tastes, {
  Catalog? catalog,
  int? members,
  List<Wanted> wanted = const [],
  Set<String> seen = const {},
  bool worldwide = false,
}) => buildDeck(
  catalog: catalog ?? catalogOf(films()),
  tastes: tastes,
  members: members ?? max(1, tastes.length),
  wanted: wanted,
  seen: seen,
  today: today,
  worldwide: worldwide,
);

final tasteA = tasteOf({'DA': 3.0, 'S': 3.0});
final tasteB = tasteOf({'DB': 3.0, 'S': 3.0});
final tasteC = tasteOf({'DC': 3.0, 'S': 1.0});

void main() {
  group('buildDeck', () {
    test('is the same for any order of members, wanted films and catalog', () {
      final wanted = [
        (film: film('w1', dir: ['DA']), n: 2),
        (film: film('w2', dir: ['DB']), n: 1),
        (film: film('w3', cast: ['S']), n: 3),
      ];
      final base = build([tasteA, tasteB, tasteC], members: 4, wanted: wanted);
      expect(base.length, greaterThan(10));
      final shapes = <String>{};
      for (final tastes in [
        [tasteA, tasteB, tasteC],
        [tasteC, tasteB, tasteA],
        [tasteB, tasteA, tasteC],
      ]) {
        for (final w in [wanted, wanted.reversed.toList()]) {
          for (final c in [films(), films().reversed.toList()]) {
            final deck = build(tastes, catalog: catalogOf(c), members: 4, wanted: w);
            shapes.add([for (final x in deck) '${x.id}:${x.wishers}:${x.seenBy}'].join(','));
          }
        }
      }
      expect(shapes, hasLength(1));
      expect(shapes.single, [for (final x in base) '${x.id}:${x.wishers}:${x.seenBy}'].join(','));
    });

    test('keeps every watchlist film, even custom, unreleased, series, foreign or seen', () {
      final wanted = [
        (film: film('my:1', dir: ['DA']), n: 1),
        (film: films().firstWhere((f) => f.id == 'future'), n: 1),
        (film: films().firstWhere((f) => f.id == 'series'), n: 2),
        (film: films().firstWhere((f) => f.id == 'foreign'), n: 1),
        (film: films().firstWhere((f) => f.id == 'a1'), n: 2),
        (film: film('x9', dir: ['Nobody']), n: 1),
      ];
      final deck = build([tasteA], members: 2, wanted: wanted, seen: {'a1', 'x9'});
      final byId = {for (final c in deck) c.id: c};
      for (final w in wanted) {
        expect(byId.keys, contains(w.film.id), reason: w.film.id);
        expect(byId[w.film.id]!.wishers, w.n);
      }
      expect(deck.map((c) => c.id).toSet(), hasLength(deck.length), reason: 'no film twice');
      expect(byId['a1']!.seenBy, 1, reason: 'a seen film stays when someone wants it');
      expect(byId['my:1']!.seenBy, 0);
    });

    test('never recommends a film that is seen, wanted, unreleased, a series or not regional', () {
      final deck = build([tasteA], seen: {'s1', 's2'}, wanted: [(film: films().firstWhere((f) => f.id == 'a3'), n: 1)]);
      final recs = [
        for (final c in deck)
          if (c.wishers == 0) c.id,
      ];
      expect(recs, isNot(contains('s1')));
      expect(recs, isNot(contains('s2')));
      expect(recs, isNot(contains('a3')));
      expect(recs.toSet().intersection({'series', 'future', 'foreign'}), isEmpty);
      expect(recs, hasLength(deckRecs));
      // Worldwide lets the foreign film in.
      final world = build([tasteA], worldwide: true);
      expect(ids(world), contains('foreign'));
    });

    test('a member who dislikes a film pulls it down (half the minimum)', () {
      // S is liked by both members, DA only by A and DB only by B.
      final both = build([tasteA, tasteB]);
      expect(ids(both.take(10)), everyElement(startsWith('s')), reason: 'liked by both beats loved by one');
      final alone = build([tasteA]);
      expect(ids(alone.take(10)).any((id) => id.startsWith('a')), isTrue);
    });

    test('a member without a taste neither counts nor pulls scores to zero', () {
      expect(ids(build([tasteA], members: 3)), ids(build([tasteA], members: 1)));
      // Nobody has a taste: the most popular regional films, popularity then id.
      final cold = build(const [], members: 3);
      final expected = ([...films()]..sort((a, b) => b.pop != a.pop ? b.pop.compareTo(a.pop) : a.id.compareTo(b.id)))
          .where((f) => f.id.startsWith(RegExp('[abs]')) && !{'series', 'future', 'foreign'}.contains(f.id))
          .take(deckRecs);
      expect(ids(cold), [for (final f in expected) f.id]);
    });

    test('keeps 100 cards and at least 20 recommendations', () {
      final many = [
        for (var i = 0; i < 130; i++) (film: film('w$i', dir: ['DA'], pop: 100 + i % 7), n: 3),
      ];
      final catalog = catalogOf([...films(), for (final w in many) w.film]);
      final deck = build([tasteA], catalog: catalog, members: 3, wanted: many);
      expect(deck, hasLength(deckCap));
      final recs = deck.where((c) => c.wishers == 0).toList();
      // Every watchlist film outscores every recommendation here, so the minimum is what keeps 20 of them.
      expect(recs, hasLength(deckMinRecs));
      // The order is still by score.
      final again = build([tasteA], catalog: catalog, members: 3, wanted: many.reversed.toList());
      expect(ids(again), ids(deck));
    });

    test('without a cap problem it holds 60 recommendations and the whole watchlist', () {
      final deck = build(
        [tasteA],
        wanted: [
          (film: film('w1', dir: ['DA']), n: 1),
        ],
      );
      expect(deck, hasLength(deckRecs + 1));
    });

    test('fewer films than the limit: all of them, none twice', () {
      final deck = build(
        [tasteA],
        catalog: catalogOf([
          film('only', dir: ['DA']),
          film('also', dir: ['DA']),
        ]),
      );
      expect(ids(deck).toSet(), {'only', 'also'});
    });
  });

  group('results', () {
    final cards = [
      for (final id in ['c1', 'c2', 'c3', 'c4', 'c5']) DeckCard(film: film(id)),
    ];

    test('tallies sums votes over members', () {
      final t = tallies({
        'm1': {'c1': Vote.want, 'c2': Vote.skip},
        'm2': {'c1': Vote.want, 'c2': Vote.seen, 'c3': Vote.want},
        'm3': {'c1': Vote.skip},
      });
      expect((t['c1']!.want, t['c1']!.skip, t['c1']!.seen), (2, 1, 0));
      expect((t['c2']!.want, t['c2']!.skip, t['c2']!.seen), (0, 1, 1));
      expect(t['c3']!.want, 1);
      expect(t.containsKey('c4'), isFalse);
      expect(tallies({}), isEmpty);
    });

    test('resultsOrder: want down, seen up, skip up, then deck order', () {
      final t = {
        'c1': const Tally(want: 1, seen: 2),
        'c2': const Tally(want: 1, skip: 3),
        'c3': const Tally(want: 1, skip: 1),
        'c4': const Tally(),
        'c5': const Tally(want: 2, seen: 1),
      };
      expect(ids(resultsOrder(cards, t)), ['c5', 'c3', 'c2', 'c1', 'c4']);
      // No votes at all: the deck order, unchanged.
      expect(ids(resultsOrder(cards, {})), ids(cards));
      expect(ids(resultsOrder(cards.reversed.toList(), {})), ids(cards.reversed));
    });

    test('tonightPick: random among the top tie, then the next best, up to three', () {
      final t = {
        'c1': const Tally(want: 2),
        'c2': const Tally(want: 2, skip: 1),
        'c3': const Tally(want: 2, skip: 2),
        'c4': const Tally(want: 1),
        'c5': const Tally(skip: 4),
      };
      final ranked = resultsOrder(cards, t);
      expect(ids(ranked), ['c1', 'c2', 'c3', 'c4', 'c5']);

      final first = ids(tonightPick(ranked, t, Random(7)));
      expect(first, hasLength(3));
      expect(ids(tonightPick(ranked, t, Random(7))), first, reason: 'same seed, same pick');
      expect(['c1', 'c2', 'c3'], contains(first.first));
      // The rest of the three follows the ranking without the winner.
      final rest = [
        for (final id in ids(ranked))
          if (id != first.first) id,
      ].take(2);
      expect(first.skip(1), rest);

      final winners = {for (var seed = 0; seed < 60; seed++) ids(tonightPick(ranked, t, Random(seed))).first};
      expect(winners, {'c1', 'c2', 'c3'}, reason: 'every film tied at the top can win, no other can');

      // A single leader always wins and is padded from the next best.
      final one = {...t, 'c1': const Tally(want: 5)};
      expect(ids(tonightPick(resultsOrder(cards, one), one, Random(1))), ['c1', 'c2', 'c3']);
    });

    test('tonightPick: nobody wants anything, or too few cards', () {
      expect(tonightPick(cards, {'c1': const Tally(skip: 2)}, Random(1)), isEmpty);
      expect(tonightPick(const [], {}, Random(1)), isEmpty);
      final two = cards.take(2).toList();
      final t = {'c2': const Tally(want: 1)};
      expect(ids(tonightPick(resultsOrder(two, t), t, Random(1))), ['c2', 'c1']);
    });
  });
}
