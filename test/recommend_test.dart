import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/recommend.dart';
import 'package:talkies/state/providers.dart';

final today = DateTime(2026, 9, 30);

Film film(
  String id, {
  String? title,
  List<String> dir = const [],
  List<String> cast = const [],
  List<String> g = const [],
  String lang = 'hi',
  String date = '2010-01-01',
  int pop = 10,
}) => Film(
  id: id,
  title: title ?? id,
  directors: dir,
  cast: cast,
  genres: g,
  langs: [lang],
  countries: const ['IN'],
  date: date,
  year: int.parse(date.substring(0, 4)),
  poster: '$id.jpg',
  pop: pop,
);

Stub stub(String filmId, double? rating) =>
    Stub(id: filmId, no: 1, filmId: filmId, created: DateTime(2026, 9), date: DateTime(2026, 9, 1), rating: rating);

List<String> ids(List<Film> films) => [for (final f in films) f.id];

void main() {
  test('likes pull, dislikes push; watched, wished, hidden and unreleased are skipped', () {
    final c = Catalog([
      film('A', dir: ['X'], g: ['action']),
      film('B', dir: ['Y'], g: ['horror']),
      film('C', dir: ['X']),
      film('D', dir: ['Y'], g: ['horror']),
      film('E', g: ['action'], lang: 'ta'),
      film('F', dir: ['X'], date: '2027-01-01'),
      film('G', dir: ['X']),
      film('H', dir: ['X']),
    ], '');
    final d = Diary(
      stubs: [stub('A', 5), stub('B', 1)],
      wishes: [Wish(filmId: 'G', added: DateTime(2026, 9))],
      hidden: const ['H'],
    );
    expect(ids(recommend(c, d, today).forYou), ['C', 'E']);
    expect(recommend(c, const Diary(), today).forYou, isEmpty);
    expect(recommend(c, Diary(stubs: [stub('B', 1)]), today).forYou, isEmpty);
  });

  test('ratings are read against the user own mean', () {
    final c = Catalog([
      film('A1', dir: ['P']),
      film('A2', dir: ['Q']),
      film('A3', dir: ['R']),
      film('cP', dir: ['P']),
      film('cQ', dir: ['Q']),
      film('cR', dir: ['R']),
    ], '');
    // 4.0 is below this user's mean of 4.7, so it counts as "meh".
    final d = Diary(stubs: [stub('A1', 5), stub('A2', 4), stub('A3', 5)]);
    final r = ids(recommend(c, d, today).forYou);
    expect(r, containsAll(['cP', 'cR']));
    expect(r, isNot(contains('cQ')));
  });

  test('sequels share a title stem', () {
    expect(titleStem('K.G.F: Chapter 2'), '#kgf');
    expect(titleStem('Baahubali 2: The Conclusion'), '#baahubali');
    expect(titleStem('Dhoom 3'), titleStem('Dhoom'));
    expect(titleStem('3 Idiots'), '#3idiots');
    expect(titleStem('X-Men'), '#xmen');
    expect(titleStem('Ra'), isNull);

    final c = Catalog([
      film('k1', title: 'K.G.F: Chapter 1', dir: ['Prashanth Neel'], cast: ['Yash'], g: ['action'], lang: 'kn'),
      film('k2', title: 'K.G.F: Chapter 2', dir: ['Prashanth Neel'], cast: ['Yash'], g: ['action'], lang: 'kn'),
      film('salaar', title: 'Salaar', dir: ['Prashanth Neel'], cast: ['Prabhas'], g: ['action'], lang: 'te'),
      film('kantara', title: 'Kantara', dir: ['Rishab Shetty'], g: ['action'], lang: 'kn', pop: 90),
    ], '');
    final r = recommend(c, Diary(stubs: [stub('k1', 5)]), today);
    expect(r.forYou.first.id, 'k2');
  });

  test('one loved director does not fill the whole row', () {
    final c = Catalog([
      film('L', dir: ['X'], cast: ['S1'], g: ['drama']),
      for (var i = 1; i <= 5; i++) film('X$i', dir: ['X'], g: ['drama'], pop: 6),
      film('O', cast: ['S1'], g: ['drama'], pop: 0),
    ], '');
    final r = ids(recommend(c, Diary(stubs: [stub('L', 5)]), today).forYou);
    expect(r, hasLength(6));
    expect(r.indexOf('O'), lessThan(3), reason: '$r');
  });

  test('"because you liked" rows follow their anchor, with no repeats', () {
    final c = Catalog([
      film('L1', dir: ['X']),
      film('L2', dir: ['Y']),
      for (var i = 1; i <= 12; i++) film('X$i', dir: ['X']),
      for (var i = 1; i <= 12; i++) film('Y$i', dir: ['Y']),
    ], '');
    final r = recommend(c, Diary(stubs: [stub('L1', 5), stub('L2', 5)]), today);
    expect(r.forYou, hasLength(12));
    expect(r.because, hasLength(2));
    final seen = {...ids(r.forYou)};
    for (final (anchor, films) in r.because) {
      expect(films.length, greaterThanOrEqualTo(4));
      expect(films.every((f) => f.directors.first == anchor.directors.first), isTrue);
      for (final f in films) {
        expect(seen.add(f.id), isTrue, reason: '${f.id} repeats');
      }
    }
  });

  test('a viewing outranks an older "Not interested"; watchlist films are never anchors', () {
    final c = Catalog([
      film('A', dir: ['X']),
      film('W', dir: ['Y']),
      for (var i = 1; i <= 20; i++) film('X$i', dir: ['X']),
      for (var i = 1; i <= 20; i++) film('Y$i', dir: ['Y']),
    ], '');
    // A was hidden, then watched and rated 5: it counts as liked.
    final d = Diary(
      stubs: [stub('A', 5)],
      wishes: [Wish(filmId: 'W', added: DateTime(2026, 9))],
      hidden: const ['A'],
    );
    final r = recommend(c, d, today);
    expect(r.forYou.first.directors, ['X']);
    expect(r.because.map((b) => b.$1.id), ['A']);
  });

  test('hidden films survive a save; venue names map to services', () {
    final d = Diary.fromJson(const Diary(hidden: ['Q1']).toJson());
    expect(d.hidden, ['Q1']);
    expect(const Diary().toJson().containsKey('hidden'), isFalse);
    expect(serviceKey('Prime Video'), 'prime');
    expect(serviceKey('aha'), 'aha');
    expect(serviceKey('PVR'), isNull);
  });

  test('provider: a watchlist tap keeps the row; a new viewing or hide recomputes it', () async {
    final c = Catalog([
      film('A', dir: ['X']),
      for (var i = 1; i <= 3; i++) film('X$i', dir: ['X'], pop: 10 * i),
      film('B'),
    ], '');
    final dir = Directory.systemTemp.createTempSync('talkies_recs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pc = ProviderContainer.test(
      overrides: [
        docsDirProvider.overrideWithValue(dir),
        catalogProvider.overrideWith((ref) async => c),
        todayProvider.overrideWithValue(today),
      ],
    );
    await pc.read(catalogProvider.future);
    pc.listen(recsProvider, (_, _) {});
    final n = pc.read(diaryProvider.notifier);
    n.addStub(c.byId['A']!, const StubDraft(rating: 5), now: DateTime(2026, 9));
    final first = pc.read(recsProvider);
    expect(ids(first.forYou), ['X3', 'X2', 'X1']);

    n.toggleWish(c.byId['X3']!);
    expect(pc.read(recsProvider), same(first));

    n.setHidden('X2', true);
    expect(ids(pc.read(recsProvider).forYou), ['X1']);
    n.setHidden('X2', false);
    expect(ids(pc.read(recsProvider).forYou), ['X2', 'X1']);
  });

  test('bundled catalog: a K.G.F fan gets Chapter 2', () {
    final c = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync(), null);
    final kgf1 = c.match('K.G.F: Chapter 1', 2018)!;
    final sw = Stopwatch()..start();
    final r = recommend(c, Diary(stubs: [stub(kgf1.id, 5)]), today);
    sw.stop();
    // ignore: avoid_print
    print(
      'recommend: ${sw.elapsedMilliseconds} ms\n'
      'for you: ${r.forYou.map((f) => '${f.title} (${f.year})').join(', ')}\n'
      '${[for (final (a, fs) in r.because) '${a.title}: ${fs.map((f) => f.title).join(', ')}'].join('\n')}',
    );
    expect(r.forYou.take(3).map((f) => f.title), contains('K.G.F: Chapter 2'));
  });
}
