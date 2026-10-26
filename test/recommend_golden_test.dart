import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/recommend.dart';

// Pins the output of recommend() on the bundled catalog, so a refactor of the
// scoring code cannot change what Home shows. Change it on purpose with:
//   UPDATE_GOLDEN=1 flutter test test/recommend_golden_test.dart

final today = DateTime(2026, 9, 30);
const goldenPath = 'test/fixtures/recommend_golden.json';

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

List<Film> pick(Catalog c, bool Function(Film) where, int n, [int skip = 0]) =>
    c.items.where((f) => f.poster != null && where(f)).skip(skip).take(n).toList();

Map<String, Diary> diaries(Catalog c) {
  final hi = pick(c, (f) => f.langs.contains('hi') && f.year != null && f.year! < 2026, 10);
  final ta = pick(c, (f) => f.langs.contains('ta') && f.year != null && f.year! < 2026, 10);
  final te = pick(c, (f) => f.langs.contains('te') && f.year != null && f.year! < 2026, 3);
  final any = pick(c, (f) => f.year != null && f.year! < 2026 && !f.series, 18);
  const hiRatings = [5.0, 4.5, 4.0, 3.0, 5.0, 2.0, 4.0, 3.5, 4.5, 1.0];
  const taRatings = [5.0, 5.0, 4.0, 4.0, 3.0, 3.0, 2.0, 4.5, 4.0, 3.5];
  return {
    'hindi': Diary(stubs: [for (var i = 0; i < hi.length; i++) stubOf(hi[i], i, hiRatings[i])]),
    'tamil': Diary(stubs: [for (var i = 0; i < ta.length; i++) stubOf(ta[i], i, taRatings[i])]),
    'mixed': Diary(
      stubs: [for (var i = 0; i < 12; i++) stubOf(any[i], i, i.isEven ? null : 4.0)],
      wishes: [for (final f in any.skip(12).take(4)) Wish(filmId: f.id, added: DateTime(2026, 9))],
      hidden: [for (final f in any.skip(16)) f.id],
    ),
    'rewatch': Diary(
      stubs: [
        for (var i = 0; i < te.length * 3; i++)
          stubOf(te[i % te.length], i, 5.0, fdfs: i < te.length, place: i.isEven ? 'Netflix' : 'Prime Video'),
      ],
    ),
  };
}

Map<String, Object> shape(Recs r) => {
  'forYou': [for (final f in r.forYou) f.id],
  'because': [
    for (final (a, fs) in r.because)
      {
        'anchor': a.id,
        'films': [for (final f in fs) f.id],
      },
  ],
};

void main() {
  final c = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync(), null);

  test('recommend() output on the bundled catalog is unchanged', () {
    final actual = {for (final e in diaries(c).entries) e.key: shape(recommend(c, e.value, today))};
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      File(goldenPath).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(actual)}\n');
      return;
    }
    final golden = jsonDecode(File(goldenPath).readAsStringSync()) as Map<String, dynamic>;
    expect(jsonDecode(jsonEncode(actual)), golden);
  });

  test('every golden diary gets recommendations', () {
    for (final e in diaries(c).entries) {
      expect(recommend(c, e.value, today).forYou, isNotEmpty, reason: e.key);
    }
  });
}
