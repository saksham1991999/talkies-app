import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/csv_io.dart';
import 'package:talkies/data/json_file.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/stats.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/screens/manage_screens.dart' show splitTitleYear;
import 'package:talkies/ui/screens/stubs_screen.dart';

String fixture() => jsonEncode({
  'built': '2026-09-30',
  'items': [
    {
      'id': 'Q949228',
      't': 'Sholay',
      'o': 'शोले',
      'd': '1975-08-15',
      'y': 1975,
      'rt': 204,
      'dir': ['Ramesh Sippy'],
      'cast': ['Amitabh Bachchan', 'Dharmendra'],
      'g': ['action', 'drama'],
      'l': ['hi'],
      'c': ['IN'],
      'pop': 48,
    },
    {
      'id': 'Q1',
      't': 'K.G.F: Chapter 2',
      'd': '2022-04-14',
      'y': 2022,
      'rt': 168,
      'dir': ['Prashanth Neel'],
      'cast': ['Yash'],
      'g': ['action'],
      'l': ['kn'],
      'c': ['IN'],
      'pop': 30,
    },
    {
      'id': 'Q2',
      't': 'Dilwale Dulhania Le Jayenge',
      'd': '1995-10-20',
      'y': 1995,
      'rt': 189,
      'dir': ['Aditya Chopra'],
      'cast': ['Shah Rukh Khan', 'Kajol'],
      'g': ['romance'],
      'l': ['hi'],
      'c': ['IN'],
      'pop': 40,
    },
    {
      'id': 'Q3',
      't': 'Fresh Release',
      'd': '2026-09-20',
      'y': 2026,
      'l': ['ta'],
      'c': ['IN'],
      'pop': 5,
    },
    {
      'id': 'Q4',
      't': 'Next Month',
      'd': '2026-10',
      'y': 2026,
      'l': ['te'],
      'c': ['IN'],
      'pop': 5,
    },
    {
      'id': 'Q5',
      't': 'Foreign New',
      'd': '2026-09-25',
      'y': 2026,
      'l': ['en'],
      'c': ['US'],
      'pop': 90,
    },
    {
      'id': 'Q6',
      't': 'Panchayat',
      'd': '2020-04-03',
      'y': 2020,
      'l': ['hi'],
      'c': ['IN'],
      'k': 's',
      'sn': 4,
      'pop': 12,
    },
    {
      'id': 'Q7',
      't': 'Amélie',
      'd': '2001-04-25',
      'y': 2001,
      'l': ['fr'],
      'c': ['FR'],
      'pop': 60,
    },
  ],
});

void main() {
  final cat = Catalog.parse(fixture(), null);
  final today = DateTime(2026, 9, 30);

  group('search', () {
    test('ignores spaces, punctuation, accents and case', () {
      expect(cat.search('kgf').first.id, 'Q1');
      expect(cat.search('K G F chapter').first.id, 'Q1');
      expect(cat.search('amelie').first.id, 'Q7');
      expect(cat.search('dilwaledulhania').first.id, 'Q2');
    });
    test('matches people and native script', () {
      expect(cat.search('shahrukh').map((f) => f.id), contains('Q2'));
      expect(cat.search('शोले').first.id, 'Q949228');
      expect(cat.search('ramesh sippy').first.id, 'Q949228');
    });
    test('title match ranks above cast match; kind filter works', () {
      expect(cat.search('panchayat', series: false), isEmpty);
      expect(cat.search('panchayat', series: true).single.id, 'Q6');
    });
    test('match uses title and year', () {
      expect(cat.match('Sholay', 1975)?.id, 'Q949228');
      expect(cat.match('sholay', null)?.id, 'Q949228');
      expect(cat.match('Sholay', 2010), isNull);
    });
  });

  test('new and upcoming releases', () {
    expect(cat.newReleases(today).map((f) => f.id), ['Q3']);
    expect(cat.newReleases(today, worldwide: true).map((f) => f.id), ['Q5', 'Q3']);
    expect(cat.upcoming(today).map((f) => f.id), ['Q4']);
    expect(cat.newReleases(today, lang: 'te'), isEmpty);
  });

  test('delta merge keeps bundled fields and takes fresh dates', () {
    final delta = jsonEncode({
      'items': [
        {'id': 'Q4', 't': 'Next Month', 'd': '2026-10-02', 'y': 2026, 'p': 'en/a/ab/x.jpg', 'pop': 7},
        {
          'id': 'Q99',
          't': 'Brand New',
          'd': '2026-09-28',
          'y': 2026,
          'c': ['IN'],
          'l': ['hi'],
        },
      ],
    });
    final c = Catalog.parse(fixture(), delta);
    expect(c.byId['Q4']!.date, '2026-10-02');
    expect(c.byId['Q4']!.langs, ['te']);
    expect(c.byId['Q4']!.poster, 'en/a/ab/x.jpg');
    expect(c.newReleases(today).map((f) => f.id), containsAll(['Q99', 'Q3']));
  });

  test('refresh row parser handles precision and languages', () {
    final f = filmFromRefreshRow({
      'f': {'value': 'http://www.wikidata.org/entity/Q42'},
      'w': {'value': 'Some Film (2026 film)'},
      's': {'value': '9'},
      'date': {'value': '2026-12-01T00:00:00Z#10'},
      'rt': {'value': '151'},
      'dirs': {'value': 'A|B'},
      'langs': {'value': 'http://www.wikidata.org/entity/Q1568'},
      'gens': {'value': 'action film|romantic comedy'},
    });
    expect(f.id, 'Q42');
    expect(f.title, 'Some Film');
    expect(f.date, '2026-12');
    expect(f.langs, ['hi']);
    expect(f.genres, ['action', 'romance']);
    expect(f.runtime, 151);
  });

  group('csv', () {
    test('Indian and partial dates parse', () {
      expect(parseDate('15/08/1975'), (DateTime(1975, 8, 15), DatePrecision.day));
      expect(parseDate('2024-05'), (DateTime(2024, 5), DatePrecision.month));
      expect(parseDate('2019'), (DateTime(2019), DatePrecision.year));
      expect(parseDate('31/02/2020').$1, isNull);
      expect(parseDate('').$2, DatePrecision.none);
    });

    test('export then import round-trips every field', () {
      final sholay = cat.byId['Q949228']!;
      const own = Film(id: 'my:1', title: 'Home Video, "Part 1"', year: 2010);
      final d = Diary(
        films: {sholay.id: sholay, own.id: own},
        stubs: [
          Stub(
            id: 'a',
            no: 1,
            filmId: sholay.id,
            created: DateTime(2026),
            date: DateTime(2026, 8, 15),
            rating: 4.5,
            place: 'Maratha Mandir',
            memo: 'Line 1\nline, 2',
            tags: const ['classic', 'balcony'],
            show: 'matinee',
            format: '2d',
            seatClass: 'Balcony',
            seat: 'H12',
            price: 120,
            fdfs: true,
            lang: 'hi',
            company: 'Dadi',
          ),
          Stub(
            id: 'b',
            no: 2,
            filmId: own.id,
            created: DateTime(2026),
            date: DateTime(2011),
            precision: DatePrecision.year,
          ),
        ],
        venues: const [...defaultVenues, Venue('Maratha Mandir', VenueType.cinema)],
      );
      final csvText = exportCsv(d);
      final r = parseCsv(csvText, cat, const Diary());
      expect(r.rows, hasLength(2));
      expect(r.matched, 1);
      expect(r.custom, 1);
      expect(r.places, {'Maratha Mandir'});
      // Export is oldest first: the 2011 viewing, then 2026.
      final (f1, s1) = r.rows[1];
      expect(f1.id, 'Q949228');
      expect(s1.date, DateTime(2026, 8, 15));
      expect(s1.rating, 4.5);
      expect(s1.memo, 'Line 1\nline, 2');
      expect(s1.tags, ['classic', 'balcony']);
      expect(
        [s1.show, s1.format, s1.seatClass, s1.seat, s1.price, s1.fdfs, s1.lang, s1.company],
        ['matinee', '2d', 'Balcony', 'H12', 120.0, true, 'hi', 'Dadi'],
      );
      final (f2, s2) = r.rows[0];
      expect(f2.title, 'Home Video, "Part 1"');
      expect(f2.isCustom, isTrue);
      expect(s2.precision, DatePrecision.year);
    });

    test('Letterboxd diary import', () {
      const lb =
          'Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,Watched Date\n'
          '2024-01-02,Sholay,1975,https://boxd.it/x,4.5,,"classic, dharmendra",2023-12-31\n'
          '2024-01-03,Unknown Indie,2021,https://boxd.it/y,,,,\n';
      final r = parseCsv(lb, cat, const Diary());
      expect(r.letterboxd, isTrue);
      expect(r.rows[0].$1.id, 'Q949228');
      expect(r.rows[0].$2.date, DateTime(2023, 12, 31));
      expect(r.rows[0].$2.tags, ['classic', 'dharmendra']);
      expect(r.rows[1].$1.isCustom, isTrue);
      expect(r.rows[1].$2.date, DateTime(2024, 1, 3));
      expect(r.rows[1].$2.rating, isNull);
    });

    test('venue type guess', () {
      expect(guessVenueType('PVR Phoenix'), VenueType.cinema);
      expect(guessVenueType('JioHotstar'), VenueType.ott);
      expect(guessVenueType('Ghar'), VenueType.home);
    });
  });

  test('stats: counts, runtime, spend, rewatches, buckets', () {
    final sholay = cat.byId['Q949228']!, kgf = cat.byId['Q1']!;
    final d = Diary(
      films: {sholay.id: sholay, kgf.id: kgf},
      venues: const [Venue('PVR', VenueType.cinema), Venue('Netflix', VenueType.ott)],
      stubs: [
        Stub(id: '1', no: 1, filmId: sholay.id, created: DateTime(2026), date: DateTime(2025, 12, 1), rating: 5),
        Stub(
          id: '2',
          no: 2,
          filmId: sholay.id,
          created: DateTime(2026),
          date: DateTime(2026, 3, 4),
          rating: 4.6,
          place: 'PVR',
          price: 200,
          fdfs: true,
          format: 'imax',
        ),
        Stub(
          id: '3',
          no: 3,
          filmId: kgf.id,
          created: DateTime(2026),
          date: DateTime(2026, 3, 9),
          rating: 3.2,
          place: 'Netflix',
          lang: 'hi',
          tags: const ['mass'],
        ),
        Stub(
          id: '4',
          no: 4,
          filmId: kgf.id,
          created: DateTime(2026),
          date: DateTime(2026, 7),
          precision: DatePrecision.month,
        ),
        Stub(id: '5', no: 5, filmId: kgf.id, created: DateTime(2026)),
      ],
    );
    final y = computeStats(d, const Period(StatsScope.year, 2026));
    expect(y.count, 3);
    expect(y.minutes, 204 + 168 + 168);
    expect(y.spent, 200);
    expect(y.fdfs, 1);
    // The undated KGF viewing counts as the first, so KGF March and July are rewatches.
    expect(y.rewatches, 3);
    expect(y.timeline[2].count, 2);
    expect(y.timeline[6].count, 1);
    expect({for (final b in y.stars) b.key: b.count}, {'5': 1, '4': 0, '3': 1, '2': 0, '1': 0, 'none': 1});
    expect(y.languages.map((b) => (b.key, b.count)), [('kn', 1), ('hi', 2)]..sort((a, b) => b.$2 - a.$2));
    expect(y.venueTypes.first.key, 'cinema');
    expect(y.tags.single.key, 'mass');
    final m = computeStats(d, const Period(StatsScope.month, 2026, 3));
    expect(m.count, 2);
    expect(m.timeline, hasLength(31));
    final all = computeStats(d, const Period(StatsScope.all, 2026));
    expect(all.count, 5);
    expect(all.timeline.map((b) => b.key), ['2025', '2026']);
    expect(const Period(StatsScope.month, 2026, 1).shift(-1), const Period(StatsScope.month, 2025, 12));
  });

  test('stats: a snapshot that repeats a genre counts it once per viewing', () {
    const dup = Film(id: 'D', title: 'Dup', genres: ['action', 'action'], langs: ['hi', 'hi']);
    final d = Diary(
      films: const {'D': dup},
      stubs: [Stub(id: '1', no: 1, filmId: 'D', created: DateTime(2026), date: DateTime(2026, 1, 1))],
    );
    final s = computeStats(d, const Period(StatsScope.all, 2026));
    expect(s.genres.single.key, 'action');
    expect(s.genres.single.count, 1);
  });

  test('stubs query: sort and filter', () {
    final d = Diary(
      films: {for (final f in cat.items) f.id: f},
      stubs: [
        Stub(id: 'x', no: 1, filmId: 'Q1', created: DateTime(2026), date: DateTime(2026, 1, 1), rating: 2),
        Stub(
          id: 'y',
          no: 2,
          filmId: 'Q2',
          created: DateTime(2026),
          date: DateTime(2026, 2, 1),
          rating: 5,
          tags: const ['love'],
        ),
        Stub(id: 'z', no: 3, filmId: 'Q6', created: DateTime(2026), date: DateTime(2025, 2, 1)),
      ],
    );
    expect(queryStubs(d).map((s) => s.id), ['y', 'x', 'z']);
    expect(queryStubs(d, sort: StubSort.ratingHigh).map((s) => s.id), ['y', 'x', 'z']);
    expect(queryStubs(d, sort: StubSort.ratingLow).map((s) => s.id), ['x', 'y', 'z']);
    expect(queryStubs(d, filter: const StubFilter(series: true)).single.id, 'z');
    expect(queryStubs(d, filter: const StubFilter(year: 2026, minStars: 4)).single.id, 'y');
    expect(queryStubs(d, query: 'love').single.id, 'y');
    expect(queryStubs(d, query: 'dilwale').single.id, 'y');
  });

  test('backup JSON round-trips the whole diary', () {
    final sholay = cat.byId['Q949228']!;
    final d = Diary(
      films: {
        sholay.id: sholay,
        'my:1': const Film(id: 'my:1', title: 'Own', poster: 'file:posters/1.jpg', series: true),
      },
      stubs: [
        Stub(
          id: 'a',
          no: 7,
          filmId: sholay.id,
          created: DateTime(2026, 1, 2, 3, 4),
          date: DateTime(2026, 5),
          precision: DatePrecision.month,
          rating: 3.3,
          place: 'Regal',
          tags: const ['x'],
          fdfs: true,
          price: 99.5,
          lang: 'ta',
        ),
      ],
      wishes: [Wish(filmId: 'my:1', added: DateTime(2026, 2), planned: DateTime(2026, 12, 25))],
      tags: const ['x', 'y'],
      venues: const [Venue('Regal', VenueType.cinema)],
      nextNo: 8,
    );
    final back = Diary.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
    expect(back.films['my:1']!.posterFile, 'posters/1.jpg');
    expect(back.films['my:1']!.series, isTrue);
    expect(back.stubs.single.precision, DatePrecision.month);
    expect(back.wishes.single.planned, DateTime(2026, 12, 25));
  });

  test('review fixes: tags, own-film ids, prices, bad delta, title-only search, snapshot sync', () async {
    expect(cleanTag('#Must Watch'), 'Must_Watch');
    expect(cleanTag('a, b'), 'a_b');
    expect(cleanTag(' ,x, '), 'x');

    // A my:1 from another phone must not attach to this phone's different my:1.
    final mine = Diary(
      films: {'my:1': const Film(id: 'my:1', title: 'Nani Wedding')},
    );
    final r = parseCsv('film_id,title,watched_on,price_inr\nmy:1,Home Video,2024-01-02,"₹1,200"\n', cat, mine);
    expect(r.rows.single.$1.id, 'my:2');
    expect(r.rows.single.$1.title, 'Home Video');
    expect(r.rows.single.$2.price, 1200);
    final same = parseCsv('film_id,title\nmy:1,Nani Wedding\n', cat, mine);
    expect(same.rows.single.$1.id, 'my:1');

    // A damaged refresh file is ignored.
    final c = Catalog.parse(fixture(), '{"items": [ broken');
    expect(c.items, hasLength(cat.items.length));

    // Title-only search skips cast matches.
    expect(cat.search('amitabh').map((f) => f.id), contains('Q949228'));
    expect(cat.search('amitabh', titleOnly: true), isEmpty);

    // Snapshots gain what the catalog learns later; user fields stay.
    final dir = Directory.systemTemp.createTempSync('talkies_sync');
    final pc = ProviderContainer.test(overrides: [docsDirProvider.overrideWithValue(dir)]);
    final n = pc.read(diaryProvider.notifier);
    n.addStub(const Film(id: 'Q3', title: 'Fresh Release', date: '2026-09'), const StubDraft(rating: 4));
    final newer = Catalog.parse(
      jsonEncode({
        'items': [
          {
            'id': 'Q3',
            't': 'Fresh Release (renamed)',
            'd': '2026-09-20',
            'p': 'en/x/xy/poster.jpg',
            'rt': 140,
            'dir': ['A. Director'],
          },
        ],
      }),
      null,
    );
    n.syncFilms(newer);
    final f = pc.read(diaryProvider).films['Q3']!;
    expect(
      [f.title, f.date, f.poster, f.runtime, f.directors],
      [
        'Fresh Release',
        '2026-09-20',
        'en/x/xy/poster.jpg',
        140,
        ['A. Director'],
      ],
    );
    expect(pc.read(diaryProvider).stubs.single.rating, 4);
    await n.flush();
    dir.deleteSync(recursive: true);
  });

  test('posterPath drops the tracking query', () {
    expect(
      posterPath('https://upload.wikimedia.org/wikipedia/en/1/12/X.jpg?utm_source=en.wikipedia.org'),
      'en/1/12/X.jpg',
    );
    expect(posterPath('https://example.com/a.jpg'), isNull);
    expect(posterPath(null), isNull);
  });

  test('batch line parsing', () {
    expect(splitTitleYear('Sholay 1975'), ('Sholay', 1975));
    expect(splitTitleYear('RRR (2022)'), ('RRR', 2022));
    expect(splitTitleYear('1917'), ('1917', null));
    expect(splitTitleYear('Panchayat'), ('Panchayat', null));
  });

  group('diary persistence', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('talkies'));
    tearDown(() => dir.deleteSync(recursive: true));

    ProviderContainer make() => ProviderContainer.test(overrides: [docsDirProvider.overrideWithValue(dir)]);

    test('stubs, wishes, tags and venues survive a restart', () async {
      final c = make();
      final n = c.read(diaryProvider.notifier);
      final sholay = cat.byId['Q949228']!, ddlj = cat.byId['Q2']!;
      n.toggleWish(ddlj, planned: DateTime(2026, 10, 2));
      n.toggleWish(sholay);
      final s1 = n.addStub(sholay, const StubDraft(tags: ['classic'], place: 'Home', rating: 4.2));
      final s2 = n.addStub(sholay, StubDraft(date: DateTime(2026, 9, 1), place: 'Home'));
      n.addVenue(const Venue('Regal', VenueType.cinema));
      n.updateVenue(const Venue('Home', VenueType.home), const Venue('Ghar', VenueType.home));
      n.renameTag('classic', '#all time');
      await n.flush();

      final c2 = make();
      final d = c2.read(diaryProvider);
      expect(d.stubs.map((s) => s.no), [1, 2]);
      expect(d.nextNo, 3);
      expect(d.wishes.map((w) => w.filmId), ['Q2']); // recording removes the wish
      expect(d.wishes.single.planned, DateTime(2026, 10, 2));
      expect(d.tags, ['all_time']);
      expect(d.stubs.first.tags, ['all_time']);
      expect(d.stubs.every((s) => s.place == 'Ghar'), isTrue);
      expect(d.venues.map((v) => v.name), containsAll(['Ghar', 'Regal']));
      expect(d.viewingNumber(d.stubs.firstWhere((s) => s.id == s2.id)), 2);
      expect(d.stubs.firstWhere((s) => s.id == s1.id).rating, 4.2);

      final n2 = c2.read(diaryProvider.notifier);
      n2.deleteTag('all_time');
      n2.deleteStub(s1.id);
      n2.deleteStub(s2.id);
      expect(c2.read(diaryProvider).films.keys, ['Q2']); // unused snapshots pruned
      n2.restoreStub(c.read(diaryProvider).stubs.first, sholay);
      expect(c2.read(diaryProvider).stubs, hasLength(1));
      await n2.flush();
    });

    test('custom films get fresh ids; settings persist', () async {
      final c = make();
      final n = c.read(diaryProvider.notifier);
      final a = n.addCustomFilm(title: ' My Short ', year: 2024, lang: 'mr', posterFile: 'posters/1.jpg');
      final b = n.addCustomFilm(title: 'Another');
      expect(a.id, 'my:1');
      expect(b.id, 'my:2');
      expect(a.title, 'My Short');
      expect(a.posterFile, 'posters/1.jpg');
      c
          .read(settingsProvider.notifier)
          .set((s) => s.copyWith(accent: 4, weekStart: DateTime.monday, locale: () => 'hi'));
      await c.read(settingsProvider.notifier).flush();
      await n.flush();
      final s = make().read(settingsProvider);
      expect([s.accent, s.weekStart, s.locale], [4, DateTime.monday, 'hi']);
    });

    test('a failed write does not block later writes', () async {
      final f = File('${dir.path}/sub/state.json');
      final j = JsonFile(f);
      j.write({'a': 1}); // parent folder missing: this write fails
      await j.flush();
      expect(f.existsSync(), isFalse);
      Directory('${dir.path}/sub').createSync();
      j.write({'a': 2});
      await j.flush();
      expect(jsonDecode(f.readAsStringSync()), {'a': 2});
    });

    test('a corrupt file is set aside, not overwritten', () {
      final f = File('${dir.path}/diary.json')..writeAsStringSync('{broken');
      expect(JsonFile(f).read(), isNull);
      expect(f.existsSync(), isFalse);
      expect(dir.listSync().any((e) => e.path.contains('diary.json.corrupt-')), isTrue);
    });
  });

  group('online refresh', () {
    late Directory dir;
    late File delta;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('talkies_refresh');
      delta = File('${dir.path}/catalog_delta.json');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Map<String, dynamic> row(String id) => {
      'f': {'value': 'http://www.wikidata.org/entity/$id'},
      'w': {'value': 'Film $id'},
      's': {'value': '5'},
      'date': {'value': '2026-10-02T00:00:00Z#11'},
    };

    /// Wikidata answers from [sparql] in order. Wikipedia answers the Hindi
    /// 2026 list page when [lists] is true, and 404 for everything else.
    MockClient wiki(List<(int, List<String>)> sparql, {bool lists = false}) => MockClient((req) async {
      if (req.url.host == 'query.wikidata.org') {
        final (code, ids) = sparql.removeAt(0);
        return http.Response(
          jsonEncode({
            'results': {'bindings': ids.map(row).toList()},
          }),
          code,
        );
      }
      final p = req.url.queryParameters;
      if (lists && p['page'] == 'List of Hindi films of 2026') {
        final w = File('test/fixtures/list_hindi_2026.wiki').readAsStringSync();
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'parse': {'wikitext': w},
            }),
          ),
          200,
        );
      }
      if (lists && p['prop'] == 'pageprops|pageimages') {
        final pages = [
          for (final t in p['titles']!.split('|'))
            {
              'title': t,
              'pageprops': {'wikibase_item': 'L:$t'},
            },
        ];
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'query': {'pages': pages},
            }),
          ),
          200,
        );
      }
      return http.Response('', 404);
    });

    Set<String> ids() => deltaFilms(delta.readAsStringSync()).map((f) => f.id).toSet();
    final today = DateTime(2026, 9, 30);

    test('merges into the last refresh, retries 503, and never drops films', () async {
      expect(
        await refreshCatalog(
          delta,
          today,
          client: wiki([
            (200, ['Q1']),
          ]),
        ),
        1,
      );
      expect(ids(), {'Q1'});

      final retried = wiki([
        (503, []),
        (200, ['Q2']),
      ]);
      expect(await refreshCatalog(delta, today, client: retried), 1);
      expect(ids(), {'Q1', 'Q2'});

      await expectLater(refreshCatalog(delta, today, client: wiki([(500, [])])), throwsA(isA<HttpException>()));
      expect(ids(), {'Q1', 'Q2'});
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('saves Wikipedia list films when Wikidata fails, then reports it', () async {
      await refreshCatalog(
        delta,
        today,
        client: wiki([
          (200, ['Q1']),
        ]),
      );
      await expectLater(
        refreshCatalog(delta, today, client: wiki([(500, [])], lists: true)),
        throwsA(isA<PartialRefresh>()),
      );
      final films = {for (final f in deltaFilms(delta.readAsStringSync())) f.id: f};
      expect(films, contains('Q1'));
      expect(films['L:Ikkis']?.date, '2026-01-01');
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('drops films the sources no longer cover, keeps OTT found earlier', () async {
      delta.writeAsStringSync(
        jsonEncode({
          'items': [
            const Film(id: 'Q0', title: 'Old', date: '2025-06-01').toJson(),
            const Film(id: 'Q1', title: 'Film Q1', date: '2026-10-02', ott: ['netflix']).toJson(),
          ],
        }),
      );
      await refreshCatalog(
        delta,
        today,
        client: wiki([
          (200, ['Q1']),
        ]),
      );
      final films = {for (final f in deltaFilms(delta.readAsStringSync())) f.id: f};
      expect(films.keys, ['Q1']);
      expect(films['Q1']!.ott, ['netflix']);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  test('bundled catalog parses and finds Indian classics', () {
    final raw = File('assets/catalog/catalog.json').readAsStringSync();
    final c = Catalog.parse(raw, null);
    expect(c.items.length, greaterThan(30000));
    expect(c.search('sholay').first.title, 'Sholay');
    expect(c.search('rrr').map((f) => f.title), contains('RRR'));
    expect(c.search('3 idiots').first.year, 2009);
    expect(c.items.where((f) => f.series).length, greaterThan(3000));
    expect(c.items.where((f) => f.posterUrl != null).length, greaterThan(20000));
  });
}
