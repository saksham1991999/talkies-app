import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:talkies/data/models.dart';
import 'package:talkies/data/wire.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/sync.dart';

import '../support/device.dart';
import '../support/fake_backend.dart';

/// Phones of one account on one server, with clocks that start a millisecond apart (so stub ids never
/// collide) and move together.
class World {
  final server = FakeBackend();
  final phones = <Device>[];

  Future<Device> phone({String email = 'me@example.test', Duration clockOffset = Duration.zero}) async {
    final d = Device(server, at: server.now.add(clockOffset).add(Duration(milliseconds: phones.length)));
    phones.add(d);
    await d.signIn(email);
    return d;
  }

  void tick(Duration d) {
    server.now = server.now.add(d);
    for (final p in phones) {
      p.clock.advance(d);
    }
  }

  String user(Device d) => d.c.read(sessionProvider)!.userId;
}

List<Map<String, dynamic>> stubsOf(Device d) =>
    [for (final s in d.diary.stubs) s.toJson()]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

List<Map<String, dynamic>> wishesOf(Device d) =>
    [for (final w in d.diary.wishes) w.toJson()]..sort((a, b) => (a['film'] as String).compareTo(b['film'] as String));

void expectSame(Device a, Device b) {
  expect(stubsOf(a), stubsOf(b), reason: 'stubs');
  expect(wishesOf(a), wishesOf(b), reason: 'wishes');
  expect(a.diary.films.keys.toSet(), b.diary.films.keys.toSet(), reason: 'films');
  expect(a.diary.tags, b.diary.tags, reason: 'tags');
  expect([for (final v in a.diary.venues) v.toJson()], [for (final v in b.diary.venues) v.toJson()], reason: 'venues');
  expect(a.diary.hidden, b.diary.hidden, reason: 'hidden');
}

StubDraft draft(Stub s, {double? rating, String? memo}) => StubDraft(
  date: s.date,
  precision: s.precision,
  rating: rating ?? s.rating,
  memo: memo ?? s.memo,
  private: s.private,
);

/// An http client that can hold the answer to one POST back, so the test can
/// act while the request is on the wire.
class _HoldClient extends http.BaseClient {
  _HoldClient(this.inner, this.method);
  final http.Client inner;
  final String method;
  bool hold = false;
  final sent = Completer<void>();
  final release = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == method && hold) {
      hold = false;
      sent.complete();
      await release.future;
    }
    return inner.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('two and three phones', () {
    test('a new phone pulls everything: stubs, wishes, films, tags, venues', () async {
      final w = World();
      final a = await w.phone();
      a.watch('Q1', rating: 4);
      w.tick(const Duration(minutes: 1));
      a.watch('Q2', rating: 3);
      a.diaryN.toggleWish(a.film('Q3'), planned: DateTime(2026, 11, 1));
      a.diaryN.addTag('classic');
      a.diaryN.addVenue(const Venue('Regal', VenueType.cinema));
      await a.sync();
      final u = w.user(a);
      expect(w.server.rowsOf(u).map((r) => r['kind']).toSet(), {'stub', 'wish', 'meta'});
      expect(w.server.rowsOf(u), hasLength(4));

      final b = await w.phone();
      await b.sync();
      expectSame(a, b);
      expect(b.diary.films.keys.toSet(), {'Q1', 'Q2', 'Q3'});
      expect(b.diary.nextNo, 3); // raised above the ticket numbers that arrived
      expect(b.diary.tags, ['classic']);
      expect(b.diary.venues.map((v) => v.name), contains('Regal'));
      expect(b.syncState, SyncState.idle);

      // Nothing more to say: a second round is a pull only.
      final pushes = w.server.count('POST /v1/sync/push');
      await a.sync();
      await b.sync();
      expect(w.server.count('POST /v1/sync/push'), pushes);
      expectSame(a, b);
    });

    test('an edit, a delete and an undo travel both ways', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final s1 = a.watch('Q1', rating: 3), s2 = a.watch('Q2', rating: 3);
      await a.sync();
      await b.sync();
      w.tick(const Duration(minutes: 1));

      b.diaryN.updateStub(b.stub(s1.id), draft(s1, rating: 5, memo: 'again'));
      b.diaryN.deleteStub(s2.id);
      await b.sync();
      await a.sync();
      expectSame(a, b);
      expect(a.diary.stubs.single.rating, 5);
      expect(a.diary.stubs.single.memo, 'again');
      expect(a.diary.films.keys, ['Q1']); // the deleted stub's film is pruned

      w.tick(const Duration(minutes: 1));
      final deleted = b.stub(s1.id);
      b.diaryN.deleteStub(s1.id);
      b.diaryN.restoreStub(deleted, b.film('Q1')); // undo: back before the first sync of the delete
      await b.sync();
      await a.sync();
      expectSame(a, b);
      expect(a.diary.stubs.single.rating, 5);
    });

    test('three phones that each add a film end up with one diary', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone(), c = await w.phone();
      a.watch('Q1');
      b.watch('Q2');
      c.watch('Q3');
      c.diaryN.setHidden('Q5', true);
      for (final d in [a, b, c, a, b]) {
        await d.sync();
        w.tick(const Duration(seconds: 1));
      }
      expectSame(a, b);
      expectSame(b, c);
      expect(a.diary.stubs, hasLength(3));
      expect(a.diary.hidden, ['Q5']);
      // Each phone numbered its own first ticket 1: the numbers stay as they are.
      expect(a.diary.stubs.map((s) => s.no), [1, 1, 1]);
      expect([a, b, c].map((d) => d.diary.nextNo), [2, 2, 2]);
    });

    test('delete against edit: the later one wins, in both orders', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final x = a.watch('Q1', rating: 3), y = a.watch('Q2', rating: 3);
      await a.sync();
      await b.sync();

      // A deletes x first, B edits it half a minute later: the edit wins.
      w.tick(const Duration(minutes: 1));
      a.diaryN.deleteStub(x.id);
      w.tick(const Duration(seconds: 30));
      b.diaryN.updateStub(b.stub(x.id), draft(x, rating: 5));
      await a.sync();
      await b.sync();
      await a.sync();
      expectSame(a, b);
      expect(a.stub(x.id).rating, 5);

      // B edits y first, A deletes it later: the delete wins.
      w.tick(const Duration(minutes: 1));
      b.diaryN.updateStub(b.stub(y.id), draft(y, rating: 1));
      w.tick(const Duration(seconds: 30));
      a.diaryN.deleteStub(y.id);
      await a.sync();
      await b.sync();
      expectSame(a, b);
      expect(a.diary.stubs.map((s) => s.id), [x.id]);
    });

    test('a phone that was away cannot overwrite a newer edit when it comes back', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final s = a.watch('Q1', rating: 3);
      await a.sync();
      await b.sync();

      w.tick(const Duration(hours: 1));
      b.diaryN.updateStub(b.stub(s.id), draft(s, rating: 1)); // at 13:00, never synced
      w.tick(const Duration(minutes: 30));
      a.diaryN.updateStub(a.stub(s.id), draft(s, rating: 5)); // at 13:30
      await a.sync();
      w.tick(const Duration(minutes: 30));
      await b.sync(); // at 14:00: the edit was made at 13:00, so it loses
      expect(b.stub(s.id).rating, 5);
      expect(w.server.row(w.user(a), 'stub', s.id)!['data']['rating'], 5);
      expectSame(a, b);
    });

    test('clock skew is measured from the server, so a wrong clock cannot win either', () async {
      final w = World();
      final a = await w.phone();
      final b = await w.phone(clockOffset: const Duration(hours: -1)); // B's clock is an hour behind
      final s = a.watch('Q1', rating: 3);
      await a.sync();
      await b.sync();
      expect(b.store.skew, greaterThan(const Duration(minutes: 59).inMilliseconds));

      w.tick(const Duration(minutes: 30));
      a.diaryN.updateStub(a.stub(s.id), draft(s, rating: 5)); // 12:30 on the server clock
      await a.sync();
      w.tick(const Duration(minutes: 10));
      b.diaryN.updateStub(b.stub(s.id), draft(s, rating: 1)); // 12:40 on the server clock, 11:40 on B's
      await b.sync();
      expect(w.server.row(w.user(a), 'stub', s.id)!['data']['rating'], 1); // the later edit wins
      await a.sync();
      expect(a.stub(s.id).rating, 1);
    });

    test('a tie takes the server row', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final s = a.watch('Q1', rating: 3);
      await a.sync();
      await b.sync();
      w.tick(const Duration(minutes: 1));
      a.diaryN.updateStub(a.stub(s.id), draft(s, rating: 5));
      b.diaryN.updateStub(b.stub(s.id), draft(s, rating: 1)); // the same instant
      await a.sync();
      await b.sync();
      expect(b.stub(s.id).rating, 5);
      await a.sync();
      expectSame(a, b);
    });

    test('a push that loses applies the row the server kept', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final s = a.watch('Q1', rating: 3);
      await a.sync();
      await b.sync();
      w.tick(const Duration(minutes: 1));
      b.diaryN.updateStub(b.stub(s.id), draft(s, rating: 1));

      // Between B's pull and B's push, A's newer edit reaches the server.
      final user = w.user(a);
      w.server.onPush = () {
        w.server.onPush = null;
        final row = w.server.row(user, 'stub', s.id)!;
        w.server.putRow(
          user,
          'stub',
          s.id,
          w.server.now.add(const Duration(seconds: 5)),
          data: {...(row['data'] as Map<String, dynamic>), 'rating': 5.0},
          film: row['film'] as Map<String, dynamic>?,
        );
      };
      await b.sync();
      expect(b.stub(s.id).rating, 5);
      expect(w.server.row(user, 'stub', s.id)!['data']['rating'], 5);
      final pushes = w.server.count('POST /v1/sync/push');
      await b.sync();
      expect(w.server.count('POST /v1/sync/push'), pushes); // nothing left pending
    });

    test('an edit made while a push travels survives that push losing', () async {
      final w = World();
      final a = await w.phone();
      final wire = _HoldClient(
        w.server.client,
        'POST',
      );
      final b = Device(w.server, client: wire);
      w.phones.add(b);
      await b.signIn();
      final s = a.watch('Q1', rating: 3);
      await a.sync();
      await b.sync();
      w.tick(const Duration(minutes: 1));
      b.diaryN.updateStub(b.stub(s.id), draft(s, rating: 2)); // what the push sends

      final user = w.user(b);
      wire.hold = true;
      final run = b.sync();
      await wire.sent.future; // the push is on the wire
      // While it travels, A's edit lands on the server, and B edits the same stub again.
      final row = w.server.row(user, 'stub', s.id)!;
      w.server.putRow(
        user,
        'stub',
        s.id,
        w.server.now,
        data: {...(row['data'] as Map<String, dynamic>), 'rating': 1.0},
        film: row['film'] as Map<String, dynamic>?,
      );
      w.tick(const Duration(seconds: 1)); // B's second edit is a second later than A's row
      b.diaryN.updateStub(b.stub(s.id), draft(b.stub(s.id), rating: 9));
      await Future<void>.delayed(Duration.zero); // the edit is stamped now, while the push is still out
      wire.release.complete();
      await run;
      expect(b.stub(s.id).rating, 9); // the edit made during the push was not overwritten
      final pushes = w.server.count('POST /v1/sync/push');
      await b.sync(); // the same key goes again with its newer stamp, and wins
      expect(w.server.count('POST /v1/sync/push'), greaterThan(pushes));
      expect(w.server.row(user, 'stub', s.id)!['data']['rating'], 9);
      final settled = w.server.count('POST /v1/sync/push');
      await b.sync();
      expect(w.server.count('POST /v1/sync/push'), settled); // nothing left pending
      await a.sync();
      expectSame(a, b);
    });

    test('restore from a backup comes back everywhere, deleted stubs included', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final s1 = a.watch('Q1', rating: 4), s2 = a.watch('Q2', rating: 3);
      a.watch('Q3');
      await a.sync();
      await b.sync();
      final backup = jsonDecode(jsonEncode(a.diary.toJson())) as Map<String, dynamic>;

      w.tick(const Duration(minutes: 1));
      a.diaryN.deleteStub(s2.id);
      a.diaryN.updateStub(a.stub(s1.id), draft(s1, rating: 1));
      await a.sync();
      await b.sync();
      expect(b.diary.stubs, hasLength(2));
      expect(b.stub(s1.id).rating, 1);

      w.tick(const Duration(minutes: 1));
      a.diaryN.replaceAll(Diary.fromJson(backup)); // Settings > restore
      await a.sync();
      await b.sync();
      expectSame(a, b);
      expect(b.diary.stubs, hasLength(3));
      expect(b.stub(s1.id).rating, 4);
      expect(b.stub(s2.id).rating, 3);
    });

    test('a backup restored on a reinstalled phone wins over the older server copy', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final s1 = a.watch('Q1', rating: 4);
      final s2 = a.watch('Q2', rating: 3);
      await a.sync();
      await b.sync();
      final backup = jsonDecode(jsonEncode(a.diary.toJson())) as Map<String, dynamic>;
      w.tick(const Duration(minutes: 1));
      a.diaryN.updateStub(a.stub(s1.id), draft(s1, rating: 1));
      a.diaryN.deleteStub(s2.id);
      await a.sync();

      // A reinstalls: a new folder, a new device id, an empty keychain, then the backup, then sign-in.
      w.tick(const Duration(minutes: 1));
      final a2 = Device(w.server, at: w.server.now.add(const Duration(milliseconds: 9)));
      w.phones.add(a2);
      a2.diaryN.replaceAll(Diary.fromJson(backup));
      await a2.signIn();
      await a2.sync();
      await b.sync();
      expect(a2.store.deviceId, isNot(a.store.deviceId));
      expectSame(a2, b);
      expect(b.diary.stubs, hasLength(2));
      expect(b.stub(s1.id).rating, 4);
    });
  });

  group('offline', () {
    test('edits made without a connection are pushed when it returns, oldest stamp kept', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final s = a.watch('Q1', rating: 3);
      await a.sync();
      await b.sync();

      w.server.offline = true;
      w.tick(const Duration(minutes: 5));
      final extra = a.watch('Q2');
      a.diaryN.updateStub(a.stub(s.id), draft(s, rating: 5));
      await a.sync(); // the probe fails: no sync, no crash
      expect(a.c.read(backendProvider), Backend.down);
      expect(a.c.read(onlineProvider), isFalse);
      expect(a.store.meta['s:${extra.id}']!.s, 0); // waiting in sync.json

      // B edits the same stub later, while A is still offline.
      w.server.offline = false;
      w.tick(const Duration(minutes: 5));
      b.diaryN.updateStub(b.stub(s.id), draft(s, rating: 1));
      await b.sync();
      w.server.offline = true;
      w.tick(const Duration(minutes: 5));
      w.server.offline = false;

      await a.sync();
      expect(a.stub(s.id).rating, 1); // A's edit was older
      await b.sync();
      expectSame(a, b);
      expect(b.diary.stubs.map((x) => x.id).toSet(), {s.id, extra.id});
    });

    test('a run that dies in the middle leaves its work for the next run', () async {
      final w = World();
      final a = await w.phone();
      a.watch('Q1');
      a.watch('Q2');
      w.server.fail('POST /v1/sync/push', const Fault(error: SocketException('lost')));
      await a.sync();
      expect(a.syncState, SyncState.failed);
      expect(a.c.read(backendProvider), Backend.down);
      expect(w.server.rowsOf(w.user(a)), isEmpty);
      await a.sync();
      expect(a.syncState, SyncState.idle);
      expect(w.server.rowsOf(w.user(a)).where((r) => r['kind'] == 'stub'), hasLength(2));
    });

    test('nothing runs while the server is down or nobody is signed in', () async {
      final w = World();
      final a = await w.phone();
      a.watch('Q1');
      a.backend.markDown();
      final calls = w.server.total;
      await a.engine.run();
      await a.engine.pushTaste();
      expect(w.server.total, calls);
      a.backend.markUp();
      await a.session.signOut();
      final after = w.server.total;
      await a.engine.run();
      expect(w.server.total, after);
    });
  });

  group('records', () {
    test('custom films get the device id on the wire, and never collide with another phone\'s own', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final home = a.diaryN.addCustomFilm(title: 'Home Video', year: 2020, posterFile: 'posters/1.jpg');
      final s = a.diaryN.addStub(home, const StubDraft(), now: a.clock.now);
      a.diaryN.toggleWish(a.diaryN.addCustomFilm(title: 'Someday'));
      final mine = b.diaryN.addCustomFilm(title: 'B Film');
      b.diaryN.addStub(mine, const StubDraft(), now: b.clock.now);
      await a.sync();

      final row = w.server.row(w.user(a), 'stub', s.id)!;
      final wire = 'my:${a.store.deviceId}.1';
      expect((row['data'] as Map)['film'], wire);
      expect(row['film'], {'id': wire, 't': 'Home Video', 'y': 2020, 'd': '2020'}); // the photo stays on the phone
      expect(w.server.row(w.user(a), 'wish', 'my:${a.store.deviceId}.2'), isNotNull);

      await b.sync();
      await a.sync();
      // B has A's film under its wire id, and its own my:1 untouched.
      expect(b.diary.films['my:1']!.title, 'B Film');
      expect(b.diary.films[wire]!.title, 'Home Video');
      expect(b.diary.films[wire]!.posterFile, isNull);
      expect(b.stub(s.id).filmId, wire);
      // A kept its own id and its photo, and holds B's film under B's wire id.
      expect(a.diary.films['my:1']!.posterFile, 'posters/1.jpg');
      expect(a.stub(s.id).filmId, 'my:1');
      expect(a.diary.films['my:${b.store.deviceId}.1']!.title, 'B Film');
      expect(a.diary.stubs, hasLength(2));
      expect(b.diary.stubs, hasLength(2));
    });

    test('renaming a custom film reaches the other phone, though no stub changed', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final film = a.diaryN.addCustomFilm(title: 'Home Video');
      a.diaryN.addStub(film, const StubDraft(), now: a.clock.now);
      await a.sync();
      await b.sync();
      w.tick(const Duration(minutes: 1));
      a.diaryN.updateFilm(film.copyWith(title: 'Wedding'));
      await a.sync();
      await b.sync();
      expect(b.diary.films['my:${a.store.deviceId}.1']!.title, 'Wedding');
    });

    test('a catalog refresh of a film snapshot is not an edit', () async {
      final w = World();
      final a = await w.phone();
      a.watch('Q1');
      await a.sync();
      final pushes = w.server.count('POST /v1/sync/push');
      w.tick(const Duration(minutes: 1));
      a.diaryN.syncFilms(testCatalog()); // fills gaps from a newer catalog; no stub changes
      a.diaryN.updateFilm(a.film('Q1').copyWith(poster: 'en/x/poster.jpg'));
      expect(a.engine.scan(), isFalse);
      await a.sync();
      expect(w.server.count('POST /v1/sync/push'), pushes);
    });

    test('private stubs sync with their flag, and stay private on the other phone', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      final s = a.watch('Q1', private: true);
      await a.sync();
      expect((w.server.row(w.user(a), 'stub', s.id)!['data'] as Map)['priv'], isTrue);
      await b.sync();
      expect(b.stub(s.id).private, isTrue);

      w.tick(const Duration(minutes: 1));
      b.diaryN.setPrivate(s.id, false); // flipping the flag is an edit like any other
      await b.sync();
      await a.sync();
      expect(a.stub(s.id).private, isFalse);
      expect((w.server.row(w.user(a), 'stub', s.id)!['data'] as Map).containsKey('priv'), isFalse);
    });

    test(
      'a stub with no ticket number (a night wrap-up) gets this phone\'s next one, and keeps it everywhere',
      () async {
        final w = World();
        final a = await w.phone(), b = await w.phone();
        a.watch('Q1');
        await a.sync();
        await b.sync();
        final user = w.user(a);
        final film = filmToWire(a.film('Q2'), a.store.deviceId);
        w.server.putRow(
          user,
          'stub',
          'night-1',
          w.server.now.add(const Duration(minutes: 1)),
          film: film,
          data: {
            'id': 'night-1',
            'no': 0,
            'film': 'Q2',
            'created': '2026-10-01T12:00:00.000',
            'date': '2026-10-01',
            'prec': 'day',
            'with': 'Asha, Ravi',
          },
        );
        w.tick(const Duration(minutes: 2));
        await a.sync();
        expect(a.stub('night-1').no, 2);
        expect(a.diary.nextNo, 3);
        // The number A gave is pushed back, so every phone shows the same ticket.
        expect((w.server.row(user, 'stub', 'night-1')!['data'] as Map)['no'], 2);
        w.tick(const Duration(minutes: 1));
        await b.sync();
        expect(b.stub('night-1').no, 2);
        expect(b.diary.nextNo, 3);
        expectSame(a, b);
      },
    );

    test('a record this build cannot read is skipped without failing the run', () async {
      final w = World();
      final a = await w.phone();
      final user = w.user(a);
      // No snapshot and a film nobody knows: skipped. No snapshot but a catalog film: shown.
      w.server.putRow(
        user,
        'stub',
        'x1',
        w.server.now,
        data: {'id': 'x1', 'no': 1, 'film': 'Q999', 'created': '2026-10-01T10:00:00.000', 'prec': 'none'},
      );
      w.server.putRow(
        user,
        'stub',
        'x2',
        w.server.now,
        data: {'id': 'x2', 'no': 2, 'film': 'Q3', 'created': '2026-10-01T10:00:00.000', 'prec': 'none'},
      );
      w.server.putRow(
        user,
        'stub',
        'x3',
        w.server.now,
        data: {'id': 'x3', 'no': 3, 'film': 'Q3', 'prec': 'bogus'},
        film: {'id': 'Q3', 't': 'K'},
      );
      w.server.putRow(user, 'taste', 'taste', w.server.now, data: {'v': 1}); // ours alone: never applied
      w.server.putRow(user, 'future', 'f', w.server.now); // a kind from a newer server
      await a.sync();
      expect(a.syncState, SyncState.idle);
      expect(a.diary.stubs.map((s) => s.id), ['x2']);
      expect(a.diary.films['Q3']!.title, 'K.G.F: Chapter 2');
    });

    test('an unreadable record holds the cursor, is surfaced, and later records still sync', () async {
      final w = World();
      final a = await w.phone();
      a.watch('Q1');
      await a.sync();
      await a.sync(); // the second pull moves the cursor past what the first pushed
      final user = w.user(a);
      final before = a.store.cursor;
      expect(before, greaterThan(0));

      // A record the build cannot read, and a good one after it.
      w.server.putRow(
        user,
        'stub',
        'bad',
        w.server.now.add(const Duration(seconds: 1)),
        data: {'id': 'bad', 'no': 5, 'film': 'Q3', 'prec': 'bogus'},
        film: filmToWire(a.film('Q3'), a.store.deviceId),
      );
      w.server.putRow(
        user,
        'stub',
        'good',
        w.server.now.add(const Duration(seconds: 2)),
        data: {'id': 'good', 'no': 6, 'film': 'Q2', 'created': '2026-10-01T10:00:00.000', 'prec': 'none'},
        film: filmToWire(a.film('Q2'), a.store.deviceId),
      );
      await a.sync();
      expect(a.syncState, SyncState.idle);
      expect(a.engine.poison, 1);
      expect(a.store.cursor, before); // held: the bad record stays pending
      expect(a.diary.stubs.map((s) => s.id), contains('good')); // the record after it still synced
      expect(a.diary.stubs.map((s) => s.id), isNot(contains('bad')));

      await a.sync(); // the bad page comes again, and is counted again
      expect(a.engine.poison, 2);
      expect(a.store.cursor, before);
      expect(a.diary.stubs.map((s) => s.id), contains('good'));
    });
  });

  group('meta', () {
    test('the first sync of a filled phone unites tags, venues and hidden films once', () async {
      final w = World();
      final a = await w.phone();
      a.diaryN.addTag('x');
      a.diaryN.addVenue(const Venue('Regal', VenueType.cinema));
      a.diaryN.setHidden('Q1', true);
      await a.sync();

      final b = await w.phone();
      b.watch('Q2');
      b.diaryN.addTag('y');
      b.diaryN.addVenue(const Venue('PVR', VenueType.cinema));
      b.diaryN.setHidden('Q3', true);
      await b.sync();
      expect(b.diary.tags, ['y', 'x']);
      expect(b.diary.venues.map((v) => v.name), containsAll(['Regal', 'PVR']));
      expect(b.diary.hidden.toSet(), {'Q1', 'Q3'});
      w.tick(const Duration(minutes: 1));
      await a.sync();
      expectSame(a, b);

      // Once: a tag B deletes later stays deleted, it is not united back.
      w.tick(const Duration(minutes: 1));
      b.diaryN.deleteTag('x');
      await b.sync();
      await a.sync();
      expect(a.diary.tags, ['y']);
      expect(b.diary.tags, ['y']);
    });

    test('an empty phone takes the meta as it is, and an untouched meta says nothing', () async {
      final w = World();
      final a = await w.phone();
      a.diaryN.deleteVenue('Cinema hall');
      a.watch('Q1');
      await a.sync();
      final c = await w.phone();
      await c.sync();
      expect(c.diary.venues.map((v) => v.name), isNot(contains('Cinema hall')));
      expectSame(a, c);
      expect(c.store.meta['m']!.s, 1); // taken from the server, nothing to push

      // A phone with stubs but the untouched meta does not overwrite the server's.
      final d = await w.phone();
      d.watch('Q2');
      w.tick(const Duration(minutes: 1));
      await d.sync();
      expect(d.diary.venues.map((v) => v.name), isNot(contains('Cinema hall')));
    });

    test('a meta change alone is pushed', () async {
      final w = World();
      final a = await w.phone();
      a.watch('Q1');
      await a.sync();
      w.tick(const Duration(minutes: 1));
      a.diaryN.addTag('late');
      await a.sync();
      final doc = (w.server.row(w.user(a), 'meta', 'meta')!['data'] as Map<String, dynamic>);
      expect(doc['tags'], ['late']);
    });
  });

  group('sync.json', () {
    test(
      'the cursor and the acknowledged records survive a restart: no second push, a pull after the cursor',
      () async {
        final w = World();
        final a = await w.phone();
        a.watch('Q1');
        a.watch('Q2');
        await a.sync();
        await a.sync(); // the second pull brings this phone's own rows back and moves the cursor
        final pushes = w.server.count('POST /v1/sync/push');
        final cursor = a.store.cursor;
        expect(cursor, greaterThan(0));
        await a.restart();
        expect(a.store.cursor, cursor);
        await a.sync();
        expect(w.server.count('POST /v1/sync/push'), pushes);
        final pull = w.server.calls.lastWhere((c) => c.key == 'GET /v1/sync/pull');
        expect(int.parse(pull.query['after']!), cursor);
      },
    );

    test('a phone gets its device id once, and keeps it', () async {
      final w = World();
      final a = await w.phone();
      final id = a.store.deviceId;
      expect(id, matches(RegExp(r'^[a-z0-9]{8}$')));
      await a.restart();
      expect(a.store.deviceId, id);
    });

    test('acknowledged tombstones are forgotten, pending ones are kept', () async {
      final w = World();
      final a = await w.phone();
      final s = a.watch('Q1');
      await a.sync();
      a.diaryN.deleteStub(s.id);
      expect(a.store.meta['s:${s.id}']!.x, 1);
      await a.sync();
      expect(a.store.meta.containsKey('s:${s.id}'), isFalse);
    });

    test('records are sent in batches of 200', () async {
      final w = World();
      final a = await w.phone();
      a.diaryN.addStubs([for (var i = 0; i < 450; i++) (a.film('Q${i % 3 + 1}'), const StubDraft())], now: a.clock.now);
      await a.sync();
      expect(w.server.pushSizes, [200, 200, 50]);
      final b = await w.phone();
      final pulls = w.server.count('GET /v1/sync/pull');
      await b.sync();
      expect(w.server.count('GET /v1/sync/pull') - pulls, 3);
      expect(b.diary.stubs, hasLength(450));
    });

    test('a record the server refuses is not sent again until it changes', () async {
      final w = World();
      w.server.stubLimit = 1;
      final a = await w.phone();
      final s1 = a.watch('Q1');
      w.tick(const Duration(seconds: 1));
      final s2 = a.watch('Q2');
      await a.sync();
      expect(a.syncState, SyncState.idle);
      final refused = a.store.meta.entries.where((e) => e.value.s == 2).toList();
      expect(refused, hasLength(1));
      final pushes = w.server.pushSizes.length;
      await a.sync();
      expect(w.server.pushSizes.length, pushes); // nothing pending
      final key = refused.single.key;
      final stub = key == 's:${s1.id}' ? s1 : s2;
      a.diaryN.updateStub(a.stub(stub.id), draft(stub, memo: 'edited'));
      expect(a.store.meta[key]!.s, 0);
      await a.sync();
      expect(w.server.pushSizes.length, pushes + 1);
    });
  });

  group('accounts', () {
    test('another account on a phone with a diary asks first, and merge uploads it', () async {
      final w = World();
      final a = await w.phone(email: 'one@example.test');
      a.watch('Q1');
      a.diaryN.toggleWish(a.film('Q2'));
      await a.sync();
      final one = w.user(a);
      w.server.revokeAll();
      await expectLater(a.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiUnauthorized>()));
      expect(a.c.read(signedInProvider), isFalse);

      await a.signIn('two@example.test');
      final two = w.user(a);
      expect(a.syncState, SyncState.needsAccountChoice);
      final calls = w.server.total;
      await a.engine.run();
      expect(w.server.total, calls); // nothing syncs until the user chooses
      expect(w.server.rowsOf(two), isEmpty);
      a.watch('Q3'); // edits while the question is open are not stamped for either account
      expect(a.engine.scan(), isFalse);

      await a.engine.chooseAccount(AccountChoice.merge);
      expect(a.syncState, SyncState.idle);
      expect(w.server.rowsOf(two).where((r) => r['kind'] == 'stub'), hasLength(2));
      expect(w.server.rowsOf(two).where((r) => r['kind'] == 'wish'), hasLength(1));
      expect(w.server.rowsOf(one).where((r) => r['kind'] == 'stub'), hasLength(1)); // account one is untouched
      expect(a.store.lastUser, two);
    });

    test('keeping them separate replaces the diary with the new account\'s', () async {
      final w = World();
      final a = await w.phone(email: 'one@example.test');
      a.watch('Q1');
      await a.sync();
      final b = await w.phone(email: 'two@example.test');
      b.watch('Q2', rating: 5);
      await b.sync();
      w.server.revokeAll();
      await expectLater(a.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiUnauthorized>()));

      await a.signIn('two@example.test');
      expect(a.syncState, SyncState.needsAccountChoice);
      await a.engine.chooseAccount(AccountChoice.separate);
      expect(a.syncState, SyncState.idle);
      expect(a.diary.stubs.map((s) => s.filmId), ['Q2']);
      expect(w.server.rowsOf(w.user(w.phones.first)).where((r) => r['kind'] == 'stub'), hasLength(1));
      expectSame(a, b);
    });

    test('the same account signing back in after an expired session resumes, no question', () async {
      final w = World();
      final a = await w.phone();
      a.watch('Q1');
      await a.sync();
      await a.sync();
      w.server.revokeAll();
      await expectLater(a.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiUnauthorized>()));
      a.watch('Q2'); // an edit while signed out is still stamped when the account returns
      await a.signIn();
      expect(a.syncState, SyncState.idle);
      final pulls = w.server.count('GET /v1/sync/pull');
      await a.sync();
      expect(w.server.rowsOf(w.user(a)).where((r) => r['kind'] == 'stub'), hasLength(2));
      expect(int.parse(w.server.calls.lastWhere((c) => c.key == 'GET /v1/sync/pull').query['after']!), greaterThan(0));
      expect(w.server.count('GET /v1/sync/pull'), pulls + 1);
    });

    test('an empty phone does not ask: it starts clean with whoever signs in', () async {
      final w = World();
      final a = await w.phone(email: 'one@example.test');
      a.watch('Q1');
      await a.sync();
      final b = await w.phone(email: 'two@example.test');
      b.watch('Q2');
      await b.sync();
      w.server.revokeAll();
      await expectLater(a.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiUnauthorized>()));
      a.diaryN.replaceAll(const Diary());
      await a.signIn('two@example.test');
      expect(a.syncState, SyncState.idle);
      await a.sync();
      expectSame(a, b);
    });

    test('signing out on purpose and signing in as someone else needs no question (sync.json was reset)', () async {
      final w = World();
      final a = await w.phone(email: 'one@example.test');
      a.watch('Q1');
      await a.sync();
      await a.session.signOut();
      await a.signIn('two@example.test');
      expect(a.syncState, SyncState.idle);
      await a.sync();
      expect(w.server.rowsOf(w.user(a)).where((r) => r['kind'] == 'stub'), hasLength(1));
    });

    test('a profile call comes first: the server makes the profile row before any record', () async {
      final w = World();
      final a = await w.phone();
      a.watch('Q1');
      // Sign-in could not load the profile (the server was busy), so the engine does it before it pushes.
      final user = w.user(a);
      await a.session.signOut();
      w.server.fail('GET /v1/me', const Fault(status: 500));
      await a.signIn();
      expect(a.c.read(sessionProvider)!.me, isNull);
      await a.sync();
      expect(w.server.rowsOf(user).where((r) => r['kind'] == 'stub'), hasLength(1));
      expect(a.c.read(sessionProvider)!.me, isNotNull);
    });
  });

  group('taste', () {
    test('uploaded when it changed, skipped when it did not, and built from the public view only', () async {
      final w = World();
      final a = await w.phone();
      final user = w.user(a);
      a.watch('Q1', rating: 5);
      await a.engine.pushTaste();
      final first = w.server.row(user, 'taste', 'taste')!;
      expect((first['data'] as Map)['v'], 1);
      expect(w.server.pushSizes, [1]);

      await a.engine.pushTaste();
      await a.engine.pushTaste();
      expect(w.server.pushSizes, [1]); // unchanged: no request

      // A private stub counts for nothing: its film's director is not in the document.
      w.tick(const Duration(minutes: 1));
      a.watch('Q3', rating: 5, private: true);
      await a.engine.pushTaste();
      expect(w.server.pushSizes, [1]);
      final traits = ((w.server.row(user, 'taste', 'taste')!['data'] as Map)['t'] as Map).keys;
      expect(traits, contains('Ramesh Sippy'));
      expect(traits, isNot(contains('Prashanth Neel')));
      expect(first['data'], w.server.row(user, 'taste', 'taste')!['data']);

      // Making the stub public changes the document.
      a.diaryN.setPrivate(a.diary.stubs.last.id, false);
      await a.engine.pushTaste();
      expect(w.server.pushSizes, [1, 1]);
      expect(((w.server.row(user, 'taste', 'taste')!['data'] as Map)['t'] as Map).keys, contains('Prashanth Neel'));
    });

    test('nothing public left: the taste document is withdrawn', () async {
      final w = World();
      final a = await w.phone();
      final user = w.user(a);
      final s = a.watch('Q1', rating: 5);
      await a.engine.pushTaste();
      expect(w.server.row(user, 'taste', 'taste')!['deleted'], isFalse);
      w.tick(const Duration(minutes: 1));
      a.diaryN.setPrivate(s.id, true);
      await a.engine.pushTaste();
      expect(w.server.row(user, 'taste', 'taste')!['deleted'], isTrue);
      await a.engine.pushTaste();
      expect(w.server.pushSizes, [1, 1]);
    });

    test('a refused upload is tried again at the next change', () async {
      final w = World();
      final a = await w.phone();
      a.watch('Q1', rating: 5);
      w.server.fail('POST /v1/sync/push', const Fault(status: 500));
      await a.engine.pushTaste();
      expect(a.store.tasteHash, isEmpty);
      await a.engine.pushTaste();
      expect(a.store.tasteHash, isNotEmpty);
    });

    test('the taste record does not travel with the diary records, and is not applied on another phone', () async {
      final w = World();
      final a = await w.phone(), b = await w.phone();
      a.watch('Q1', rating: 5);
      await a.engine.pushTaste();
      await a.sync();
      await b.sync();
      expect(b.diary.stubs, hasLength(1));
      expect(w.server.rowsOf(w.user(a)).map((r) => r['kind']).toSet(), {'stub', 'taste'});
    });
  });

  group('timers (fake time)', () {
    // A run takes a few event-loop turns; a pump of no time lets them happen.
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 4; i++) {
        await t.pump();
      }
    }

    testWidgets('a failed run is retried after 5 s, 15 s, 1 min, 5 min, 15 min; a good run starts over', (
      tester,
    ) async {
      final server = FakeBackend();
      final d = Device(server, auto: true);
      await d.signIn();
      await settle(tester); // the run that sign-in starts
      int pulls() => server.count('GET /v1/sync/pull');
      final base = pulls();
      expect(base, 1);
      for (var i = 0; i < 6; i++) {
        server.fail('GET /v1/sync/pull', const Fault(status: 500));
      }

      d.engine.kick();
      await settle(tester);
      expect(pulls() - base, 1);
      expect(d.syncState, SyncState.failed);

      var seen = 1;
      for (final wait in const [5, 15, 60, 300, 900]) {
        await tester.pump(Duration(seconds: wait) - const Duration(milliseconds: 1));
        await settle(tester);
        expect(pulls() - base, seen, reason: 'not before $wait s');
        await tester.pump(const Duration(milliseconds: 1));
        await settle(tester);
        seen++;
        expect(pulls() - base, seen, reason: 'at $wait s');
      }
      // The sixth failure waits 15 minutes again; the retry after it works.
      await tester.pump(const Duration(minutes: 15));
      await settle(tester);
      expect(pulls() - base, seen + 1);
      expect(d.syncState, SyncState.idle);
      // A good run reset the delay: the next failure retries after 5 s.
      server.fail('GET /v1/sync/pull', const Fault(status: 500));
      d.engine.kick();
      await settle(tester);
      final n = pulls();
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(pulls(), n + 1);
      d.c.dispose();
    });

    testWidgets('an edit starts a run after 2 seconds, many edits one run; the taste follows after 30 seconds', (
      tester,
    ) async {
      final server = FakeBackend();
      final d = Device(server, auto: true);
      await d.signIn();
      await settle(tester);
      final pulls = server.count('GET /v1/sync/pull');
      final pushes = server.count('POST /v1/sync/push');

      d.watch('Q1', rating: 4);
      await tester.pump(const Duration(milliseconds: 1500));
      d.watch('Q2');
      await tester.pump(const Duration(milliseconds: 1500));
      await settle(tester);
      expect(server.count('GET /v1/sync/pull'), pulls); // the second edit restarted the 2 seconds
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(server.count('GET /v1/sync/pull'), pulls + 1);
      expect(server.count('POST /v1/sync/push'), pushes + 1);
      expect(server.pushSizes.last, 2);

      await tester.pump(const Duration(seconds: 29));
      await settle(tester);
      expect(server.row(d.c.read(sessionProvider)!.userId, 'taste', 'taste'), isNotNull);
      d.c.dispose();
    });

    testWidgets('a phone that comes back online pushes without waiting', (tester) async {
      final server = FakeBackend();
      final d = Device(server, auto: true);
      await d.signIn();
      await settle(tester);
      d.backend.markDown();
      d.watch('Q1');
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      final user = d.c.read(sessionProvider)!.userId;
      expect(server.rowsOf(user).where((r) => r['kind'] == 'stub'), isEmpty);
      await d.backend.probe(force: true); // the status turns up
      await settle(tester);
      expect(server.rowsOf(user).where((r) => r['kind'] == 'stub'), hasLength(1));
      d.c.dispose();
    });

    testWidgets('sign-in and a status that turns up in the same moment make one run', (tester) async {
      final server = FakeBackend();
      final d = Device(server, auto: true);
      await d.signIn();
      await settle(tester);
      expect(server.count('GET /v1/sync/pull'), 1);
      expect(server.count('GET /v1/me'), 1); // and the profile is fetched once
      d.c.dispose();
    });
  });
}
