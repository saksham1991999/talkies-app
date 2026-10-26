import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/recommend.dart';
import 'package:talkies/data/social.dart';
import 'package:talkies/data/wire.dart';
import 'package:talkies/state/providers.dart';

Stub stub(String id, {int no = 1, String film = 'Q1', DateTime? created, bool private = false, double? rating}) => Stub(
  id: id,
  no: no,
  filmId: film,
  created: created ?? DateTime(2026, 1, 1),
  date: DateTime(2026, 1, 1),
  rating: rating,
  private: private,
);

Film film(String id, {String? poster}) => Film(id: id, title: 'Film $id', poster: poster, date: '2020');

/// What `diary.json` looked like before the private flag and sync existed.
const oldDiary = {
  'version': 1,
  'films': [
    {
      'id': 'Q1',
      't': 'Sholay',
      'y': 1975,
      'l': ['hi'],
    },
    {'id': 'my:1', 't': 'Own', 'p': 'file:posters/1.jpg'},
  ],
  'stubs': [
    {
      'id': 'a',
      'no': 3,
      'film': 'Q1',
      'created': '2026-01-02T03:04:00.000',
      'date': '2026-01-02',
      'prec': 'day',
      'rating': 4.5,
    },
    {'id': 'b', 'no': 4, 'film': 'my:1', 'created': '2026-01-03T03:04:00.000', 'prec': 'none', 'memo': 'home'},
  ],
  'wishes': [
    {'film': 'Q1', 'added': '2026-01-01T00:00:00.000'},
  ],
  'tags': ['x'],
  'venues': [
    {'name': 'Home', 'type': 'home'},
  ],
  'nextNo': 5,
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('talkies_models'));
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer make() => ProviderContainer.test(overrides: [docsDirProvider.overrideWithValue(dir)]);

  group('private stubs', () {
    test('the flag is written only when true and survives a round trip', () {
      expect(stub('a').toJson().containsKey('priv'), isFalse);
      final j = stub('a', private: true).toJson();
      expect(j['priv'], isTrue);
      expect(Stub.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>).private, isTrue);
      expect(Stub.fromJson(stub('a').toJson()).private, isFalse);
    });

    test('drafts carry it, and edits that rewrite a stub keep it', () {
      final s = stub('a', private: true);
      expect(StubDraft.of(s).private, isTrue);
      expect(StubDraft.of(s).toStub(id: 'a', no: 1, filmId: 'Q1', created: DateTime(2026)).private, isTrue);

      final c = make();
      final n = c.read(diaryProvider.notifier);
      n.addStub(film('Q1'), const StubDraft(tags: ['old'], place: 'Home', private: true));
      n.renameTag('old', 'new'); // _retag
      n.updateVenue(const Venue('Home', VenueType.home), const Venue('Ghar', VenueType.home)); // _replace
      final kept = c.read(diaryProvider).stubs.single;
      expect(
        [kept.private, kept.tags, kept.place],
        [
          true,
          ['new'],
          'Ghar',
        ],
      );

      n.updateStub(kept, StubDraft.of(kept));
      expect(c.read(diaryProvider).stubs.single.private, isTrue);
    });

    test('setPrivate flips one stub, and publicView leaves private stubs out', () {
      final c = make();
      final n = c.read(diaryProvider.notifier);
      final a = n.addStub(film('Q1'), const StubDraft());
      final b = n.addStub(film('Q2'), const StubDraft());
      n.setPrivate(a.id, true);
      var d = c.read(diaryProvider);
      expect(d.stubs.map((s) => s.private), [true, false]);
      expect(d.publicView().stubs.map((s) => s.id), [b.id]);
      expect(identical(d.stubs.length, 2), isTrue);
      n.setPrivate(a.id, false);
      d = c.read(diaryProvider);
      expect(identical(d.publicView(), d), isTrue); // nothing private: the same diary
      expect(d.stubs.first.toJson().containsKey('priv'), isFalse);
    });
  });

  test('byWatchOrder breaks the last tie by id, so every phone sorts alike', () {
    final a = stub('a', no: 5), b = stub('b', no: 5), c = stub('c', no: 4);
    expect(([b, a, c]..sort(byWatchOrder)).map((s) => s.id), ['c', 'a', 'b']);
    expect(([a, c, b]..sort(byWatchOrder)).map((s) => s.id), ['c', 'a', 'b']);
  });

  group('old files still load', () {
    test('an old diary.json round-trips byte for byte', () {
      final d = Diary.fromJson(jsonDecode(jsonEncode(oldDiary)) as Map<String, dynamic>);
      expect(d.stubs.every((s) => !s.private), isTrue);
      expect(jsonEncode(d.toJson()), jsonEncode(oldDiary));
    });

    test('DiaryNotifier reads it from disk, and a backup written today loads too', () async {
      File('${dir.path}/diary.json').writeAsStringSync(jsonEncode(oldDiary));
      final c = make();
      final d = c.read(diaryProvider);
      expect(d.stubs.map((s) => s.id), ['a', 'b']);
      expect(d.nextNo, 5);
      expect(d.films['my:1']!.posterFile, 'posters/1.jpg');

      final n = c.read(diaryProvider.notifier);
      n.setPrivate('a', true);
      await n.flush();
      final backup = jsonDecode(File('${dir.path}/diary.json').readAsStringSync()) as Map<String, dynamic>;
      final back = Diary.fromJson(backup);
      expect(back.stubs.first.private, isTrue);
      expect(back.stubs.last.private, isFalse);
      expect(jsonEncode(Diary.fromJson(backup).toJson()), jsonEncode(backup));
    });
  });

  group('applyRemote', () {
    test(
      'a stub that arrives with no 0 gets the next ticket number, oldest first; nextNo moves above remote numbers',
      () {
        final c = make();
        final n = c.read(diaryProvider.notifier);
        n.addStub(film('Q1'), const StubDraft()); // local ticket 1
        var commits = 0;
        c.listen(diaryProvider, (_, _) => commits++);

        n.applyRemote(
          RemoteChanges(
            stubs: [
              stub('late', no: 0, film: 'Q2', created: DateTime(2026, 3)),
              stub('early', no: 0, film: 'Q2', created: DateTime(2026, 2)),
              stub('far', no: 40, film: 'Q3'),
            ],
            films: {'Q2': film('Q2'), 'Q3': film('Q3')},
          ),
        );
        final d = c.read(diaryProvider);
        expect(commits, 1);
        expect({for (final s in d.stubs) s.id: s.no}, {d.stubs.first.id: 1, 'early': 41, 'late': 42, 'far': 40});
        expect(d.nextNo, 43);
      },
    );

    test('a stub the phone already numbered keeps its number when the server copy still says 0', () {
      final c = make();
      final n = c.read(diaryProvider.notifier);
      final films = {'Q1': film('Q1')};
      n.applyRemote(RemoteChanges(stubs: [stub('w', no: 0)], films: films));
      final number = c.read(diaryProvider).stubs.single.no;
      expect(number, 1);
      n.applyRemote(RemoteChanges(stubs: [stub('w', no: 0, rating: 3)], films: films));
      final s = c.read(diaryProvider).stubs.single;
      expect([s.no, s.rating], [1, 3]);
      expect(c.read(diaryProvider).nextNo, 2);
    });

    test('deletes, wishes, meta and the film snapshots', () {
      final c = make();
      final n = c.read(diaryProvider.notifier);
      final local = film('Q1', poster: 'local/poster.jpg');
      n.addStub(local, const StubDraft());
      n.toggleWish(film('Q2'));
      n.addCustomFilm(title: 'Mine', posterFile: 'posters/1.jpg'); // my:1, no stub or wish uses it yet
      final first = c.read(diaryProvider).stubs.single;

      n.applyRemote(
        RemoteChanges(
          // A catalog snapshot never replaces the phone's own: a newer catalog may have filled it.
          films: {
            'Q1': film('Q1', poster: 'remote.jpg'),
            'Q3': film('Q3'),
            'my:zzz.2': const Film(id: 'my:zzz.2', title: 'Theirs'),
          },
          stubs: [
            stub('r1', no: 9, film: 'my:zzz.2'),
            stub('r2', no: 8, film: 'Q3'),
          ],
          deletedStubs: {first.id},
          wishes: [Wish(filmId: 'Q3', added: DateTime(2026, 5))],
          deletedWishes: {'Q2'},
          meta: const MetaDoc(tags: ['t'], venues: [Venue('V', VenueType.other)], hidden: ['Q9']),
        ),
      );
      var d = c.read(diaryProvider);
      expect(d.stubs.map((s) => s.id), ['r1', 'r2']);
      expect(d.wishes.map((w) => w.filmId), ['Q3']);
      // Q1 and Q2 lost their last stub and wish: pruned. my:1 is unused: pruned too.
      expect(d.films.keys.toSet(), {'Q3', 'my:zzz.2'});
      expect(
        [d.tags, d.venues.map((v) => v.name), d.hidden],
        [
          ['t'],
          ['V'],
          ['Q9'],
        ],
      );
      expect(d.nextNo, 10);

      // A custom film comes from the phone that edited it, but keeps this phone's photo.
      n.addCustomFilm(title: 'Mine', posterFile: 'posters/2.jpg'); // my:1 again
      n.addStub(c.read(diaryProvider).films['my:1']!, const StubDraft());
      n.applyRemote(
        RemoteChanges(
          films: {'my:1': const Film(id: 'my:1', title: 'Renamed')},
          stubs: [stub('x', film: 'my:1')],
        ),
      );
      d = c.read(diaryProvider);
      expect([d.films['my:1']!.title, d.films['my:1']!.posterFile], ['Renamed', 'posters/2.jpg']);
    });

    test('an empty change does not commit; hidden custom films stay local', () {
      final c = make();
      final n = c.read(diaryProvider.notifier);
      n.setHidden('my:1', true);
      var commits = 0;
      c.listen(diaryProvider, (_, _) => commits++);
      n.applyRemote(const RemoteChanges());
      expect(commits, 0);
      n.applyRemote(
        const RemoteChanges(
          meta: MetaDoc(tags: [], venues: [], hidden: ['Q5']),
        ),
      );
      expect(c.read(diaryProvider).hidden, ['Q5', 'my:1']);
    });
  });

  group('wire', () {
    test('custom film ids carry the device, and only on the wire', () {
      expect(wireFilmId('my:3', 'dev1'), 'my:dev1.3');
      expect(wireFilmId('Q5', 'dev1'), 'Q5');
      expect(wireFilmId('my:other.3', 'dev1'), 'my:other.3');
      expect(localFilmId('my:dev1.3', 'dev1'), 'my:3');
      expect(localFilmId('my:other.3', 'dev1'), 'my:other.3'); // another phone's film keeps its wire id
      expect(localFilmId('Q5', 'dev1'), 'Q5');
      expect(RegExp(r'^my:[A-Za-z0-9_.-]{1,40}$').hasMatch(wireFilmId('my:12', newDeviceId())), isTrue);
    });

    test('a film snapshot drops a file: poster and renames a custom id', () {
      const f = Film(id: 'my:1', title: 'Own', poster: 'file:posters/1.jpg', year: 2024);
      final w = filmToWire(f, 'dev1');
      expect(w, {'id': 'my:dev1.1', 't': 'Own', 'y': 2024});
      expect(filmFromWire(w, 'dev1').id, 'my:1');
      expect(filmToWire(film('Q1', poster: 'en/x.jpg'), 'dev1')['p'], 'en/x.jpg');
    });

    test('stub and wish records use the wire film id', () {
      final s = stub('a', film: 'my:2');
      expect(stubToWire(s, 'dev1')['film'], 'my:dev1.2');
      expect(stubFromWire(stubToWire(s, 'dev1'), 'dev1').filmId, 'my:2');
      final w = Wish(filmId: 'my:2', added: DateTime(2026));
      expect(wishFromWire(wishToWire(w, 'dev1'), 'dev1').filmId, 'my:2');
    });

    test('the hash is 10 bytes of SHA-1 over the JSON, and the snapshot counts only for a custom film', () {
      final s = stub('a', rating: 4);
      final expected = sha1
          .convert(utf8.encode(jsonEncode(s.toJson())))
          .bytes
          .take(10)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(stubHash(s, 'dev1', null), expected);
      expect(expected.length, 20);
      // A catalog film's snapshot never changes the hash: a catalog refresh is not an edit.
      expect(stubHash(s, 'dev1', film('Q1')), expected);
      expect(stubHash(s, 'dev1', film('Q1', poster: 'new.jpg')), expected);

      final mine = stub('b', film: 'my:1');
      final a = stubHash(mine, 'dev1', const Film(id: 'my:1', title: 'One'));
      expect(stubHash(mine, 'dev1', const Film(id: 'my:1', title: 'Two')), isNot(a));
      expect(
        stubHash(mine, 'dev1', const Film(id: 'my:1', title: 'One', poster: 'file:x.jpg')),
        a,
      ); // the photo stays here
    });

    test('meta documents compare by content and union once', () {
      final a = const MetaDoc(tags: ['x', 'y'], venues: [Venue('V', VenueType.cinema)], hidden: ['Q1']);
      final b = const MetaDoc(
        tags: ['y', 'z'],
        venues: [Venue('V', VenueType.home), Venue('W', VenueType.ott)],
        hidden: ['Q2'],
      );
      final u = a.union(b);
      expect(u.tags, ['x', 'y', 'z']);
      expect(u.venues.map((v) => '${v.name}:${v.type.name}'), ['V:cinema', 'W:ott']);
      expect(u.hidden, ['Q1', 'Q2']);
      expect(MetaDoc.fromJson(jsonDecode(jsonEncode(u.toJson())) as Map<String, dynamic>).hash, u.hash);
      expect(MetaDoc.of(const Diary()).hash, MetaDoc.defaults.hash);
    });

    test('times: milliseconds and Z, nothing else', () {
      expect(isoMs(DateTime.utc(2026, 10, 1, 12).millisecondsSinceEpoch), '2026-10-01T12:00:00.000Z');
      expect(parseMs('2026-10-01T12:00:00.123Z'), DateTime.utc(2026, 10, 1, 12, 0, 0, 123).millisecondsSinceEpoch);
      expect(() => parseMs('2026-10-01T12:00:00'), throwsFormatException);
    });
  });

  group('social wire models hold no diary date', () {
    // The claim at the top of lib/data/social.dart, now enforced: no response
    // model carries a diary date, so a shared profile can never leak one.
    const dateLike = {
      'date', 'created', 'created_at', 'updated_at', 'watched_on', 'watched_at', 'viewed_at',
      'added', 'planned', 'when', 'time', 'timestamp', 'sort_date',
    };

    final filmJson = {'id': 'Q1', 't': 'Sholay', 'y': 1975};
    const card = UserCard(id: 'u', handle: 'me', displayName: 'Me', avatarColor: 3);
    final stats = const ProfileStats(films: 1, viewings: 2, avgRating: 4, topGenres: ['action'], topLangs: ['hi']);
    final top = TopFilm(filmId: 'Q1', filmJson: filmJson, rating: 4);
    final watch = WatchItem(filmId: 'Q1', filmJson: filmJson);

    final tasteCat = Catalog([
      Film(
        id: 'Q1',
        title: 'Sholay',
        directors: const ['Ramesh Sippy'],
        genres: const ['action'],
        langs: const ['hi'],
        countries: const ['IN'],
        date: '1975-08-15',
        year: 1975,
        poster: 'Q1.jpg',
        pop: 48,
      ),
    ], '');
    final taste = buildTaste(tasteCat, Diary(stubs: [stub('a', film: 'Q1', rating: 5)]), DateTime(2026, 9, 30));

    final fixtures = <String, Map<String, dynamic>>{
      'FeedItem': FeedItem(
        id: 'w:1',
        kind: FeedKind.watched,
        user: card,
        filmId: 'Q1',
        filmJson: filmJson,
        rating: 4,
        reaction: 2,
        note: 'great',
        myReaction: 1,
      ).toJson(),
      'ProfileView': ProfileView(
        card: card,
        relation: Relation.friend,
        visible: true,
        match: const TasteMatch(both: 2, pct: 50),
        stats: stats,
        topFilms: [top],
        watchlist: [watch],
      ).toJson(),
      'ShelfItem': ShelfItem(filmId: 'Q1', filmJson: filmJson, rating: 4, viewings: 2).toJson(),
      'friends-watched': FriendsWhoWatched([const WatchedBy(user: card, rating: 4)]).toJson(),
      'taste doc': taste!.toJson(),
    };

    final allowed = <String, Set<String>>{
      'FeedItem': {'id', 'kind', 'user', 'film_id', 'film', 'rating', 'reaction', 'note', 'my_reaction'},
      'ProfileView': {
        'card', 'relation', 'visible', 'match', 'stats', 'top_films', 'watchlist',
      },
      'ShelfItem': {'film_id', 'film', 'rating', 'viewings'},
      'friends-watched': {'items'},
      'taste doc': {'v', 't', 'l', 'e', 'k', 's'},
    };

    final parse = <String, Map<String, dynamic> Function(Map<String, dynamic>)>{
      'FeedItem': (j) => FeedItem.fromJson(j).toJson(),
      'ProfileView': (j) => ProfileView.fromJson(j).toJson(),
      'ShelfItem': (j) => ShelfItem.fromJson(j).toJson(),
      'friends-watched': (j) => FriendsWhoWatched.fromJson(j).toJson(),
      'taste doc': (j) => Taste.tryFromJson(j)?.toJson() ?? const {},
    };

    void allKeys(Object? j, Set<String> out) {
      if (j is Map) {
        out.addAll(j.keys.cast<String>());
        for (final v in j.values) {
          allKeys(v, out);
        }
      } else if (j is List) {
        for (final v in j) {
          allKeys(v, out);
        }
      }
    }

    test('every fixture is listed here', () {
      expect(fixtures.keys.toSet(), allowed.keys.toSet());
    });

    for (final name in fixtures.keys) {
      test('$name: round trip, explicit keys, no date-like key anywhere', () {
        final j = fixtures[name]!;
        expect(j.keys.toSet(), allowed[name], reason: name); // the allowed key set, stated on purpose
        final back = parse[name]!(jsonDecode(jsonEncode(j)) as Map<String, dynamic>);
        expect(back, j, reason: name); // toJson of a parsed model gives back the same JSON

        final keys = <String>{};
        allKeys(j, keys);
        expect(keys.intersection(dateLike), isEmpty, reason: name);
      });
    }
  });
}
