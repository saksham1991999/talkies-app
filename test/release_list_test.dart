import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';

void main() {
  List<ReleaseRow> read(String lang) =>
      parseReleaseList(File('test/fixtures/list_${lang}_2026.wiki').readAsStringSync(), 2026);

  test('Hindi list: rowspan days, inline cells, hlist cast', () {
    final rows = read('hindi');
    expect(rows.length, greaterThan(60));
    final ikkis = rows.firstWhere((r) => r.target == 'Ikkis');
    expect(ikkis.date, '2026-01-01');
    expect(ikkis.directors, ['Sriram Raghavan']);
    expect(ikkis.cast, containsAll(['Dharmendra', 'Agastya Nanda']));
    final rahu = rows.firstWhere((r) => r.target == 'Rahu Ketu (2026 film)');
    expect(rahu.label, 'Rahu Ketu');
    expect(rahu.date, '2026-01-16');
    // The second film on the same day inherits the rowspan day.
    expect(rows.firstWhere((r) => r.label.startsWith('Happy Patel')).date, '2026-01-16');
    // Newspaper links inside references never become films.
    expect(rows.map((r) => r.target), isNot(contains('Deccan Chronicle')));
    expect(rows.every((r) => RegExp(r'^2026-\d\d-\d\d$').hasMatch(r.date)), isTrue);
  });

  test('Malayalam list: vertical-text months and one cell per line', () {
    final rows = read('malayalam');
    expect(rows.length, greaterThan(20));
    expect(rows.map((r) => r.date.substring(5, 7)).toSet().length, greaterThan(3));
  });

  test('Telugu list: full month names in letters', () {
    final rows = read('telugu');
    final psych = rows.firstWhere((r) => r.target == 'Psych Siddhartha');
    expect(psych.date, '2026-01-01');
    expect(psych.directors, ['Varun Reddy']);
    expect(psych.cast.first, 'Nandu');
  });
}
