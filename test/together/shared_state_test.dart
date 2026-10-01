import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/data/deck.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/state/crews_remote.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/reminders.dart';
import 'package:talkies/state/sync.dart';

import 'helpers.dart';

/// The server side of one group, as far as these tests need.
class Group {
  String name = 'Friday gang';
  int deckVersion = 0;
  List<String> deckIds = [];
  List<Map<String, dynamic>> nights = [];
  Map<String, dynamic> tallies = emptyTallies();
  bool owner = true;

  List<Map<String, dynamic>> get members => [
    memberJson('m1', 'Me', me: true, owner: owner),
    memberJson('m2', 'Ben', guest: true),
    if (!owner) memberJson('m3', 'Chitra', owner: true),
  ];

  void install(FakeApi api) {
    api.routes['GET /v1/groups'] = (_, _) => {
      'items': [groupJson('g1', name: name, version: deckVersion)],
    };
    api.routes['GET /v1/groups/g1'] = (_, _) => groupJson('g1', name: name, version: deckVersion, members: members);
    api.routes['GET /v1/groups/g1/nights'] = (_, _) => {'items': nights};
    api.routes['GET /v1/groups/g1/films'] = (_, _) => {'items': <dynamic>[]};
    api.routes['GET /v1/groups/g1/deck'] = (_, _) => deckJson(deckVersion, deckIds);
    api.routes['GET /v1/groups/g1/tallies'] = (_, _) => tallies;
    api.routes['PATCH /v1/groups/g1'] = (_, b) {
      name = (b as Map)['name'] as String;
      return groupJson('g1', name: name, version: deckVersion);
    };
  }
}

/// [FakeApi] whose `PATCH /v1/groups/g1` waits for a gate, so a test can swipe
/// while a queued action is in flight.
class GatedApi extends FakeApi {
  GatedApi(this.gate, FakeApi inner) {
    routes.addAll(inner.routes);
    log.addAll(inner.log);
  }

  final Completer<void> gate;

  @override
  Future<Object?> patch(String path, {Object? body}) async {
    await gate.future;
    return super.patch(path, body: body);
  }
}

class Flag extends Notifier<bool> {
  Flag(this.start);
  final bool start;
  @override
  bool build() => start;
  void set(bool v) => state = v;
}

final flagProvider = NotifierProvider<Flag, bool>(() => Flag(true));

final now = DateTime.utc(2026, 10, 1, 12);
final catalog = catalogOf([
  for (var i = 0; i < 80; i++) film('a$i', dir: ['DA'], pop: 80 - i),
]);
late Directory dir;

ProviderContainer make(
  FakeApi api, {
  bool online = true,
  FakeReminders? reminders,
  Future<void> Function()? sync,
  Future<void> Function()? syncRun,
  DateTime Function()? clock,
}) => ProviderContainer.test(
  overrides: [
    docsDirProvider.overrideWithValue(dir),
    nowProvider.overrideWithValue(clock ?? () => now),
    todayProvider.overrideWithValue(DateTime(2026, 10, 1)),
    remindersProvider.overrideWithValue(reminders ?? FakeReminders()),
    catalogProvider.overrideWith((ref) async => catalog),
    apiProvider.overrideWithValue(api),
    flagProvider.overrideWith(() => Flag(online)),
    onlineProvider.overrideWith((ref) => ref.watch(flagProvider)),
    if (sync != null) wrapupSyncProvider.overrideWithValue(sync),
    if (syncRun != null) syncRunProvider.overrideWithValue(syncRun),
  ],
);

/// Opens the shared group the way the app does: the list loads, then the screen.
Future<CrewController> openShared(ProviderContainer c) async {
  c.listen(groupsProvider, (_, _) {});
  await pumpEventQueue();
  c.listen(crewProvider('g1'), (_, _) {});
  await pumpEventQueue();
  return c.read(crewProvider('g1').notifier);
}

CrewState shared(ProviderContainer c) => c.read(crewProvider('g1'));

void main() {
  late FakeApi api;
  late Group server;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('talkies_shared');
    api = FakeApi();
    server = Group()..install(api);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('the gate', () {
    test('without the server nothing is called, and local groups show alone', () async {
      final c = make(api, online: false);
      final made = await c.read(crewsProvider.notifier).create('Mine');
      c.listen(groupsProvider, (_, _) {});
      await pumpEventQueue();
      expect(c.read(groupsProvider).map((g) => g.id), [made.value!.id]);
      expect(c.read(nightsProvider), isEmpty);
      expect(api.log, isEmpty);
    });

    test('with the server and a sign-in: local groups, then shared ones with members and nights', () async {
      server.nights = [nightJson(status: 'set')];
      final c = make(api);
      await c.read(crewsProvider.notifier).create('Mine');
      c.listen(groupsProvider, (_, _) {});
      expect(c.read(groupsProvider), hasLength(1), reason: 'the shared list is still loading');
      await pumpEventQueue();
      final list = c.read(groupsProvider);
      expect(list.map((g) => (g.name, g.shared)), [('Mine', false), ('Friday gang', true)]);
      expect(list.last.members, hasLength(2));
      expect(list.last.nights.single.status, NightStatus.set);
      expect(c.read(nightsProvider).single.night.id, 'n1');
      expect(api.log.map((x) => '${x.method} ${x.path}'), [
        'GET /v1/groups',
        'GET /v1/groups/g1',
        'GET /v1/groups/g1/nights',
      ]);
    });

    test('server down or signed out: shared groups and nights vanish at once; back up: they return', () async {
      server.nights = [nightJson(status: 'set')];
      final c = make(api);
      c.listen(groupsProvider, (_, _) {});
      await pumpEventQueue();
      expect(c.read(groupsProvider), hasLength(1));
      expect(c.read(nightsProvider), hasLength(1));
      final before = api.log.length;

      c.read(flagProvider.notifier).set(false);
      expect(c.read(groupsProvider), isEmpty);
      expect(c.read(nightsProvider), isEmpty);
      expect(c.read(sharedCrewsProvider).crews, isEmpty, reason: 'memory only, empty unless online');
      await pumpEventQueue();
      expect(api.log.length, before, reason: 'no call while down');

      c.read(flagProvider.notifier).set(true);
      await pumpEventQueue();
      expect(c.read(groupsProvider), hasLength(1));
      expect(api.log.length, greaterThan(before));
    });

    test('refresh on demand; a failed refresh keeps what was known and says so', () async {
      final c = make(api);
      c.listen(groupsProvider, (_, _) {});
      await pumpEventQueue();
      final s = c.read(sharedCrewsProvider.notifier);
      server.name = 'Renamed elsewhere';
      await s.refresh();
      expect(c.read(groupsProvider).single.name, 'Renamed elsewhere');
      api.routes['GET /v1/groups'] = (_, _) => throw const ApiOffline();
      await s.refresh();
      expect(c.read(sharedCrewsProvider).offline, isTrue);
      expect(c.read(groupsProvider).single.name, 'Renamed elsewhere');
    });

    test('a refresh does not wipe what a group screen loaded', () async {
      server.deckVersion = 1;
      server.deckIds = ['Q1', 'Q2'];
      final c = make(api);
      await openShared(c);
      expect(shared(c).crew.deck!.cards, hasLength(2));
      await c.read(sharedCrewsProvider.notifier).refresh();
      expect(c.read(sharedCrewsProvider).crew('g1')!.deck!.cards, hasLength(2));
    });

    test('reminders of shared nights that are gone from the server are cancelled by a refresh', () async {
      final fake = FakeReminders();
      server.nights = [nightJson(id: 'live', status: 'set')];
      final c = make(api, reminders: fake);
      final store = c.read(crewsProvider.notifier);
      for (final id in ['live', 'gone']) {
        await fake.schedule(id: reminderId(id, 0), title: id, body: '', when: now);
        store.remind(id, shared: true);
      }
      c.listen(groupsProvider, (_, _) {});
      await pumpEventQueue();
      expect(c.read(crewsProvider).reminders.keys, ['live']);
      expect(fake.scheduled.values.map((x) => x.title), ['live']);
    });
  });

  group('a shared group through the controller', () {
    test('opening it fetches the list, deck, my votes and nights', () async {
      server.deckVersion = 2;
      server.deckIds = ['Q1', 'Q2'];
      server.tallies = {
        'tallies': {
          'Q1': {'want': 1, 'skip': 0, 'seen': 0},
        },
        'mine': {'Q1': 'want'},
      };
      final c = make(api);
      await openShared(c);
      final s = shared(c);
      expect((s.loading, s.offline, s.gone), (false, false, false));
      expect(s.crew.shared, isTrue);
      expect(s.crew.deck!.cards.map((x) => x.id), ['Q1', 'Q2']);
      expect(s.crew.votes['m1'], {'Q1': Vote.want});
      expect(s.unswiped('m1').map((x) => x.id), ['Q2']);
      expect(s.topMatch!.id, 'Q1');
      expect(s.seenBy(s.crew.deck!.cards.first), 0, reason: 'the server counts a shared deck');
    });

    test('a group opened before the list loaded appears when it does', () async {
      final c = make(api);
      c.listen(crewProvider('g1'), (_, _) {});
      expect(shared(c).gone, isTrue, reason: 'not known yet');
      await pumpEventQueue();
      expect((shared(c).gone, shared(c).crew.name), (false, 'Friday gang'));
      expect(api.calls('GET', '/v1/groups/g1/films'), hasLength(1), reason: 'and it loads its content');
    });

    test('actions pick the repository by the group: shared goes to the server, local does not', () async {
      final c = make(api);
      final local = (await c.read(crewsProvider.notifier).create('Mine')).value!;
      c.listen(crewProvider(local.id), (_, _) {});
      final ctrl = await openShared(c);
      final calls = api.log.length;
      expect((await c.read(crewProvider(local.id).notifier).rename('Local new')).ok, isTrue);
      expect(api.log.length, calls, reason: 'a local group never calls the server');
      expect((await ctrl.rename('Shared new')).ok, isTrue);
      expect(api.calls('PATCH', '/v1/groups/g1').single.body, {'name': 'Shared new'});
      expect(shared(c).crew.name, 'Shared new');
      expect(c.read(sharedCrewsProvider).crew('g1')!.name, 'Shared new', reason: 'the store follows');
      expect(c.read(crewsProvider).crews.single.name, 'Local new');
    });

    test('offline: the action says offline, the state says so, and the next success clears it', () async {
      final c = make(api);
      final ctrl = await openShared(c);
      api.routes['PATCH /v1/groups/g1'] = (_, _) => throw const ApiOffline();
      final r = await ctrl.rename('X');
      expect((r.ok, r.refusal), (false, Refusal.offline));
      expect(shared(c).offline, isTrue);
      expect(shared(c).crew.name, 'Friday gang', reason: 'nothing changed');
      server.install(api);
      expect((await ctrl.rename('X')).ok, isTrue);
      expect(shared(c).offline, isFalse);
    });

    test('Retry (refresh) after the server was down loads again', () async {
      api.routes['GET /v1/groups/g1'] = (_, _) => throw const ApiOffline();
      final c = make(api);
      c.listen(groupsProvider, (_, _) {});
      await pumpEventQueue();
      expect(c.read(sharedCrewsProvider).offline, isTrue);
      final ctrl = await openShared(c);
      expect(shared(c).gone, isTrue);
      server.install(api);
      await c.read(sharedCrewsProvider.notifier).refresh();
      await pumpEventQueue();
      expect((shared(c).gone, shared(c).offline), (false, false));
      await ctrl.refresh();
      expect(shared(c).crew.name, 'Friday gang');
    });

    test('the server says no: the refusal tells why, and the state stays', () async {
      final c = make(api);
      final ctrl = await openShared(c);
      api.routes['POST /v1/groups/g1/guests'] = (_, _) => throw const ApiError(409, 'name_taken', 'x');
      expect((await ctrl.addMember('Ben')).refusal, Refusal.nameTaken);
      api.routes['PUT /v1/groups/g1/films/Q1'] = (_, _) => throw const ApiError(409, 'list_full', 'x');
      expect((await ctrl.addFilm(film('Q1'))).refusal, Refusal.listFull);
      expect((await ctrl.addFilm(film('my:1'))).refusal, Refusal.invalid, reason: 'a custom film is never shared');
      expect(shared(c).crew.members, hasLength(2));
      expect(shared(c).offline, isFalse, reason: 'the server answered');
    });

    test('only the owner adds guests, rotates the code or deletes; others are refused without a call', () async {
      server.owner = false;
      final c = make(api);
      final ctrl = await openShared(c);
      final calls = api.log.length;
      expect((await ctrl.addMember('Dev')).refusal, Refusal.notAllowed);
      expect((await ctrl.removeMember('m2')).refusal, Refusal.notAllowed);
      expect((await ctrl.rotateInvite()).refusal, Refusal.notAllowed);
      expect((await ctrl.delete()).refusal, Refusal.notAllowed);
      expect(api.log.length, calls);
      expect(
        (await ctrl.swipe('m2', 'Q1', Vote.want)).refusal,
        Refusal.notAllowed,
        reason: 'a guest\'s swipes are the owner\'s',
      );
    });

    test('a night that someone else closed: the vote is refused and the group is read again', () async {
      server.nights = [nightJson()];
      final c = make(api);
      final ctrl = await openShared(c);
      api.routes['PUT /v1/nights/n1/votes'] = (_, _) => throw const ApiError(409, 'not_polling', 'closed');
      server.nights = [nightJson(status: 'set')];
      final r = await ctrl.vote('n1', 'm1', {'o1'});
      expect(r.refusal, Refusal.closed);
      await pumpEventQueue();
      expect(shared(c).crew.nights.single.status, NightStatus.set);
    });

    test('leaving: the group goes from the list and the screen is told to close', () async {
      server.nights = [nightJson(status: 'set')];
      final fake = FakeReminders();
      final c = make(api, reminders: fake);
      final ctrl = await openShared(c);
      await ctrl.setReminder('n1', true, title: 't', dayBody: 'd', hourBody: 'h');
      expect(c.read(reminderOnProvider('n1')), isTrue);
      api.routes['DELETE /v1/groups/g1/members/me'] = (_, _) => null;
      expect((await ctrl.leave()).ok, isTrue);
      expect(shared(c).gone, isTrue);
      expect(c.read(groupsProvider), isEmpty);
      expect(c.read(reminderOnProvider('n1')), isFalse);
      expect(fake.scheduled, isEmpty);
    });

    test('the group is gone on the server: gone; going offline is not gone', () async {
      final c = make(api);
      await openShared(c);
      c.read(flagProvider.notifier).set(false);
      await pumpEventQueue();
      expect((shared(c).gone, shared(c).offline), (false, true), reason: 'Can\'t reach Talkies, with Retry');
      c.read(flagProvider.notifier).set(true);
      await pumpEventQueue();
      expect((shared(c).gone, shared(c).offline), (false, false));
      api.routes['GET /v1/groups'] = (_, _) => {'items': <dynamic>[]};
      await c.read(sharedCrewsProvider.notifier).refresh();
      expect(shared(c).gone, isTrue);
    });
  });

  group('deck of a shared group', () {
    test('ensureDeck builds when there is none: inputs, one write, the winner read back', () async {
      api.routes['GET /v1/groups/g1/deck-inputs'] = (_, _) => {
        'tastes': [
          tasteOf({'DA': 3.0}).toJson(),
        ],
        'seen': <String>[],
        'wanted': <dynamic>[],
      };
      api.routes['PUT /v1/groups/g1/deck'] = (_, _) {
        server.deckVersion = 1;
        server.deckIds = ['a0', 'a1'];
        return {'version': 1};
      };
      var t = now;
      final c = make(api, clock: () => t);
      final ctrl = await openShared(c);
      expect(shared(c).crew.deck!.cards, isEmpty);
      expect((await ctrl.ensureDeck()).ok, isTrue);
      expect((shared(c).crew.deck!.version, shared(c).crew.deckVersion), (1, 1));
      expect(api.calls('PUT', '/v1/groups/g1/deck'), hasLength(1));
      expect((api.calls('PUT', '/v1/groups/g1/deck').single.body as Map)['base_version'], 0);
      expect((await ctrl.ensureDeck()).ok, isTrue);
      expect(api.calls('PUT', '/v1/groups/g1/deck'), hasLength(1), reason: 'a deck that exists is kept');

      // A rebuild right away does not write (10 s rule); later it does.
      await ctrl.rebuildDeck();
      expect(api.calls('PUT', '/v1/groups/g1/deck'), hasLength(1));
      t = t.add(const Duration(seconds: 11));
      await ctrl.rebuildDeck();
      expect(api.calls('PUT', '/v1/groups/g1/deck'), hasLength(2));
    });

    test('swipes show at once and go up together; the tallies come back', () async {
      server.deckVersion = 1;
      server.deckIds = ['Q1', 'Q2', 'Q3'];
      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => {'saved': 2};
      final c = make(api);
      final ctrl = await openShared(c);
      expect((await ctrl.swipe('m1', 'Q1', Vote.want)).ok, isTrue);
      expect((await ctrl.swipe('m1', 'Q2', Vote.skip)).ok, isTrue);
      expect(shared(c).unswiped('m1').map((x) => x.id), ['Q3']);
      expect(shared(c).crew.tallies['Q1']!.want, 1, reason: 'counted before the server answers');
      expect(api.calls('PUT', '/v1/groups/g1/swipes'), isEmpty, reason: 'they wait to go together');

      server.tallies = {
        'tallies': {
          'Q1': {'want': 3, 'skip': 0, 'seen': 0},
        },
        'mine': <String, dynamic>{},
      };
      expect((await ctrl.flushSwipes()).ok, isTrue);
      final sent = api.calls('PUT', '/v1/groups/g1/swipes').single.body as Map;
      expect(
        [for (final s in sent['swipes']) (s['film_id'], s['vote'], s['member_id'])],
        [('Q1', 'want', null), ('Q2', 'skip', null)],
      );
      expect(shared(c).crew.tallies['Q1']!.want, 3, reason: 'the server\'s counts replace the guess');
      expect(shared(c).crew.votes['m1'], {'Q1': Vote.want, 'Q2': Vote.skip});
      await ctrl.flushSwipes();
      expect(api.calls('PUT', '/v1/groups/g1/swipes'), hasLength(1), reason: 'nothing left to send');
    });

    test('the owner swipes for a guest with the guest\'s member id; changing a mind moves the count', () async {
      server.deckVersion = 1;
      server.deckIds = ['Q1'];
      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => {'saved': 1};
      final c = make(api);
      final ctrl = await openShared(c);
      await ctrl.swipe('m2', 'Q1', Vote.want);
      expect(shared(c).crew.tallies['Q1']!.want, 1);
      await ctrl.swipe('m2', 'Q1', Vote.skip);
      expect((shared(c).crew.tallies['Q1']!.want, shared(c).crew.tallies['Q1']!.skip), (0, 1));
      await ctrl.flushSwipes();
      final sent = (api.calls('PUT', '/v1/groups/g1/swipes').single.body as Map)['swipes'] as List;
      // Inside one batch the last swipe on a film wins.
      expect([for (final s in sent) (s['member_id'], s['vote'])], [('m2', 'skip')]);
      expect(shared(c).crew.votes['m2'], {'Q1': Vote.skip});
    });

    test('swipes that cannot be sent stay and go with the next flush; a refusal drops them', () async {
      server.deckVersion = 1;
      server.deckIds = ['Q1', 'Q2'];
      final c = make(api);
      final ctrl = await openShared(c);
      await ctrl.swipe('m1', 'Q1', Vote.want);
      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => throw const ApiOffline();
      expect((await ctrl.flushSwipes()).refusal, Refusal.offline);
      expect(shared(c).offline, isTrue);
      expect(shared(c).crew.votes['m1'], {'Q1': Vote.want}, reason: 'still shown as swiped');

      await ctrl.swipe('m1', 'Q2', Vote.want);
      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => {'saved': 2};
      expect((await ctrl.flushSwipes()).ok, isTrue);
      final last = (api.calls('PUT', '/v1/groups/g1/swipes').last.body as Map)['swipes'] as List;
      expect([for (final s in last) s['film_id']], ['Q1', 'Q2']);
      expect(shared(c).offline, isFalse);

      await ctrl.swipe('m1', 'Q1', Vote.skip);
      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => throw const ApiError(403, 'forbidden', 'no');
      expect((await ctrl.flushSwipes()).refusal, Refusal.notAllowed);
      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => {'saved': 0};
      final before = api.calls('PUT', '/v1/groups/g1/swipes').length;
      await ctrl.flushSwipes();
      expect(api.calls('PUT', '/v1/groups/g1/swipes').length, before, reason: 'dropped, not retried for ever');
    });

    test('rate limited: the swipes wait as a note is shown, and the next flush commits them', () async {
      server.deckVersion = 1;
      server.deckIds = ['Q1', 'Q2'];
      server.tallies = {
        'tallies': {
          'Q1': {'want': 1, 'skip': 0, 'seen': 0},
        },
        'mine': {'Q1': 'want'},
      };
      final c = make(api);
      final ctrl = await openShared(c);
      await ctrl.swipe('m1', 'Q1', Vote.want);
      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => throw const ApiError(429, 'rate_limited', 'slow');
      expect((await ctrl.flushSwipes()).refusal, Refusal.rateLimited);
      expect(shared(c).note, Refusal.rateLimited, reason: 'the screen can show it');
      expect(shared(c).offline, isFalse);
      expect(shared(c).crew.votes['m1'], {'Q1': Vote.want}, reason: 'kept, not dropped');

      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => {'saved': 1};
      expect((await ctrl.flushSwipes()).ok, isTrue);
      expect(shared(c).crew.tallies['Q1']!.want, 1, reason: 'the kept batch was committed');
      expect(shared(c).note, isNull, reason: 'a good flush clears the note');

      await ctrl.swipe('m1', 'Q2', Vote.skip);
      await ctrl.flushSwipes();
      final last = (api.calls('PUT', '/v1/groups/g1/swipes').last.body as Map)['swipes'] as List;
      expect([for (final s in last) s['film_id']], ['Q2'], reason: 'Q1 was committed, not sent again');
    });

    test('a queued action that finishes after a swipe does not wipe the swipe', () async {
      server.deckVersion = 1;
      server.deckIds = ['Q1'];
      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => {'saved': 1};
      final gate = Completer<void>();
      final slow = GatedApi(gate, api);
      final c = make(slow);
      final ctrl = await openShared(c);
      final renamed = ctrl.rename('Slow');
      await pumpEventQueue();
      await ctrl.swipe('m1', 'Q1', Vote.want);
      expect(shared(c).crew.tallies['Q1']!.want, 1);
      gate.complete();
      await renamed;
      expect(shared(c).crew.name, 'Slow');
      expect(shared(c).crew.votes['m1'], {'Q1': Vote.want});
      expect(shared(c).crew.tallies['Q1']!.want, 1, reason: 'the older result is corrected with the waiting swipe');
    });

    test('a reload while swipes wait cannot undo them', () async {
      server.deckVersion = 1;
      server.deckIds = ['Q1', 'Q2'];
      final c = make(api);
      final ctrl = await openShared(c);
      await ctrl.swipe('m1', 'Q1', Vote.want);
      await ctrl.refresh();
      expect(shared(c).crew.votes['m1'], {'Q1': Vote.want});
      expect(shared(c).unswiped('m1').map((x) => x.id), ['Q2']);
    });

    test('50 waiting swipes go at once; later ones after', () async {
      server.deckVersion = 1;
      server.deckIds = [for (var i = 0; i < 60; i++) 'Q$i'];
      api.routes['PUT /v1/groups/g1/swipes'] = (_, b) => {'saved': ((b as Map)['swipes'] as List).length};
      final c = make(api);
      final ctrl = await openShared(c);
      for (var i = 0; i < 49; i++) {
        await ctrl.swipe('m1', 'Q$i', Vote.want);
      }
      expect(api.calls('PUT', '/v1/groups/g1/swipes'), isEmpty);
      await ctrl.swipe('m1', 'Q49', Vote.want);
      await pumpEventQueue();
      expect(
        [for (final x in api.calls('PUT', '/v1/groups/g1/swipes')) ((x.body as Map)['swipes'] as List).length],
        [50],
      );
      await ctrl.swipe('m1', 'Q50', Vote.want);
      await ctrl.flushSwipes();
      expect(
        [for (final x in api.calls('PUT', '/v1/groups/g1/swipes')) ((x.body as Map)['swipes'] as List).length],
        [50, 1],
      );
    });
  });

  group('nights of a shared group', () {
    test('create, vote, close and reply go through; the store sees the night', () async {
      final c = make(api);
      final ctrl = await openShared(c);
      api.routes['POST /v1/groups/g1/nights'] = (_, _) => nightJson();
      final made = await ctrl.createNight(
        NightCreate(films: [film('Q1'), film('Q2')], slots: [DateTime.utc(2026, 10, 3, 14)]),
      );
      expect(made.value!.id, 'n1');
      expect(c.read(nightsProvider).single.night.id, 'n1');

      api.routes['PUT /v1/nights/n1/votes'] = (_, _) => {
        'approvals': {'o1': 1},
      };
      expect((await ctrl.vote('n1', 'm1', {'o1'})).ok, isTrue);
      expect(shared(c).crew.nights.single.films.first.approvals, 1);
      api.routes['POST /v1/nights/n1/close'] = (_, _) => nightJson(status: 'set');
      expect((await ctrl.closePoll('n1')).ok, isTrue);
      api.routes['PUT /v1/nights/n1/rsvp'] = (_, _) => null;
      expect((await ctrl.rsvp('n1', 'm1', Rsvp.yes)).ok, isTrue);
      expect(shared(c).crew.nights.single.rsvps, {'m1': Rsvp.yes});
      expect(c.read(sharedCrewsProvider).crew('g1')!.nights.single.status, NightStatus.set);
    });

    test('a night outside the limits is refused before any call', () async {
      final c = make(api);
      final ctrl = await openShared(c);
      final calls = api.log.length;
      final r = await ctrl.createNight(NightCreate(films: [film('Q1')], slots: [DateTime.utc(2024)]));
      expect(r.refusal, Refusal.invalid);
      expect(api.log.length, calls);
    });

    test('wrap-up asks the server, then runs the sync the lead wired; reminders end', () async {
      server.nights = [nightJson(status: 'set')];
      var synced = 0;
      final fake = FakeReminders();
      final c = make(api, reminders: fake, sync: () async => synced++);
      final ctrl = await openShared(c);
      await ctrl.setReminder('n1', true, title: 't', dayBody: 'd', hourBody: 'h');
      expect(fake.scheduled, isNotEmpty);
      api.routes['POST /v1/nights/n1/wrapup'] = (_, _) => {'created': 2, 'skipped': 0};
      expect((await ctrl.wrapUp('n1', seatRow: 'B', firstSeat: 3)).ok, isTrue);
      expect(synced, 1);
      expect(api.calls('POST', '/v1/nights/n1/wrapup').single.body, {
        'seat_row': 'B',
        'first_seat': 3,
        'member_ids': null,
      });
      expect(shared(c).crew.nights.single.status, NightStatus.done);
      expect(fake.scheduled, isEmpty);

      // A refused or unreachable wrap-up does not sync.
      api.routes['POST /v1/nights/n1/wrapup'] = (_, _) => throw const ApiOffline();
      expect((await ctrl.wrapUp('n1')).ok, isFalse);
      expect(synced, 1);
    });

    test('a sync that fails does not fail the wrap-up', () async {
      server.nights = [nightJson(status: 'set')];
      final c = make(api, sync: () async => throw StateError('sync broke'));
      final ctrl = await openShared(c);
      api.routes['POST /v1/nights/n1/wrapup'] = (_, _) => {'created': 1, 'skipped': 0};
      expect((await ctrl.wrapUp('n1')).ok, isTrue);
    });

    test('without an override, wrap-up runs the default hook: a sync run', () async {
      server.nights = [nightJson(status: 'set')];
      var runs = 0;
      final c = make(api, syncRun: () async => runs++);
      final ctrl = await openShared(c);
      api.routes['POST /v1/nights/n1/wrapup'] = (_, _) => {'created': 2, 'skipped': 0};
      expect((await ctrl.wrapUp('n1', seatRow: 'B', firstSeat: 3)).ok, isTrue);
      expect(runs, 1, reason: 'wrapupSyncProvider defaults to syncRunProvider, not a no-op');
    });

    test('a guest\'s votes are read on demand for the owner', () async {
      server.nights = [nightJson()];
      final c = make(api);
      final ctrl = await openShared(c);
      api.routes['GET /v1/nights/n1'] = (_, _) => nightJson(mine: ['o2']);
      await ctrl.loadNightVotes('n1', 'm2');
      expect(shared(c).crew.nights.single.votes['m2'], {'o2'});
    });
  });

  group('joining and creating', () {
    test('a code is normalized; a wrong one never reaches the server', () async {
      expect(normalizeCode(' abcd-2345 '), 'ABCD2345');
      expect(normalizeCode('ABCD234'), isNull);
      expect(normalizeCode('ABCD234O'), isNull, reason: 'O is not in the alphabet');
      expect(normalizeCode('ABCD2341'), isNull, reason: '1 is not in the alphabet');
      final c = make(api);
      final s = c.read(sharedCrewsProvider.notifier);
      expect((await s.joinGroup('nope')).refusal, Refusal.invalidCode);
      expect(api.calls('POST', '/v1/groups/join'), isEmpty);
    });

    test('joining puts the group in the list and clears the waiting code', () async {
      api.routes['POST /v1/groups/join'] = (_, _) => groupJson('g1');
      final c = make(api);
      c.listen(groupsProvider, (_, _) {});
      await pumpEventQueue();
      c.read(pendingJoinProvider.notifier).set('abcd 2345');
      expect(c.read(pendingJoinProvider), 'ABCD2345');
      final r = await c.read(sharedCrewsProvider.notifier).joinGroup('abcd 2345');
      expect(r.ok, isTrue);
      expect(r.value!.members, hasLength(2));
      expect(api.calls('POST', '/v1/groups/join').single.body, {'code': 'ABCD2345'});
      expect(c.read(pendingJoinProvider), isNull);
      expect(c.read(groupsProvider).single.id, 'g1', reason: 'once, not twice');
    });

    test('the server may refuse: bad code, full group, too many tries, no network', () async {
      final c = make(api);
      final s = c.read(sharedCrewsProvider.notifier);
      for (final (error, want) in [
        (const ApiError(404, 'invalid_code', 'x'), Refusal.invalidCode),
        (const ApiError(409, 'group_full', 'x'), Refusal.groupFull),
        (const ApiError(429, 'rate_limited', 'x'), Refusal.rateLimited),
        (const ApiOffline(), Refusal.offline),
      ]) {
        api.routes['POST /v1/groups/join'] = (_, _) => throw error;
        c.read(pendingJoinProvider.notifier).set('ABCD2345');
        expect((await s.joinGroup('ABCD2345')).refusal, want);
        expect(c.read(pendingJoinProvider), 'ABCD2345', reason: 'the code waits for another try');
      }
    });

    test('the waiting code takes only real codes', () {
      final c = make(api);
      final p = c.read(pendingJoinProvider.notifier);
      p.set('hello world');
      expect(c.read(pendingJoinProvider), isNull);
      p.set('WXYZ2345');
      expect(c.read(pendingJoinProvider), 'WXYZ2345');
      p.set(null);
      expect(c.read(pendingJoinProvider), isNull);
    });

    test('creating a shared group, and the limit of groups', () async {
      api.routes['POST /v1/groups'] = (_, _) => groupJson('g1');
      final c = make(api);
      c.listen(groupsProvider, (_, _) {});
      final r = await c.read(sharedCrewsProvider.notifier).create('Friday gang');
      expect(r.value!.shared, isTrue);
      expect(c.read(groupsProvider).map((g) => g.id), ['g1']);
      api.routes['POST /v1/groups'] = (_, _) => throw const ApiError(409, 'group_limit', 'x');
      expect((await c.read(sharedCrewsProvider.notifier).create('One more')).refusal, Refusal.groupLimit);
    });
  });

  group('chat', () {
    Map<String, dynamic> msg(int id) => {
      'id': id,
      'kind': 'text',
      'sender': {'id': 'u1', 'handle': 'asha', 'display_name': 'Asha', 'avatar_color': 1},
      'body': 'message $id',
      'code': null,
      'args': null,
      'film_id': null,
      'film': null,
      'night_id': null,
      'created_at': '2026-10-01T12:00:00.000Z',
    };

    int polls() => api.calls('GET', '/v1/groups/g1/messages').length;

    testWidgets('polls every 4 seconds with after=<last id>, only while active and online', (tester) async {
      var last = 2;
      api.routes['GET /v1/groups/g1/messages'] = (q, _) {
        final after = q?['after'];
        if (after == null) {
          return {
            'items': [msg(1), msg(2)],
            'has_more': true,
          };
        }
        return {
          'items': [msg(++last)],
          'has_more': false,
        };
      };
      final c = make(api);
      c.listen(chatProvider('g1'), (_, _) {});
      final chat = c.read(chatProvider('g1').notifier);
      List<int> got() => [for (final m in c.read(chatProvider('g1')).messages) m.id];

      await tester.pump(const Duration(seconds: 30));
      expect(polls(), 0, reason: 'closed chat: no polling');

      chat.setActive(true);
      await tester.pump();
      expect(got(), [1, 2]);
      expect(c.read(chatProvider('g1')).hasOlder, isTrue);
      expect(api.calls('GET', '/v1/groups/g1/messages').first.query, {'limit': '50'});

      await tester.pump(chatEvery - const Duration(milliseconds: 1));
      expect(polls(), 1, reason: 'not before 4 s');
      await tester.pump(const Duration(milliseconds: 1));
      expect(got(), [1, 2, 3]);
      expect(api.calls('GET', '/v1/groups/g1/messages').last.query, {'after': '2', 'limit': '50'});
      await tester.pump(chatEvery);
      expect(got(), [1, 2, 3, 4]);
      expect(api.calls('GET', '/v1/groups/g1/messages').last.query!['after'], '3');

      chat.setActive(false);
      final n = polls();
      await tester.pump(const Duration(seconds: 40));
      expect(polls(), n, reason: 'a hidden chat stops asking');

      // The server goes away: no polls; it returns: polling resumes.
      chat.setActive(true);
      await tester.pump();
      expect(polls(), n + 1);
      c.read(flagProvider.notifier).set(false);
      await tester.pump(const Duration(seconds: 40));
      expect(polls(), n + 1);
      c.read(flagProvider.notifier).set(true);
      await tester.pump(chatEvery);
      expect(polls(), greaterThan(n + 1), reason: 'asks again once the server is back');
      final back = polls();
      await tester.pump(chatEvery);
      expect(polls(), back + 1);
      chat.setActive(false);
    });

    testWidgets('an unreachable server marks the chat offline and the next poll recovers', (tester) async {
      var down = true;
      api.routes['GET /v1/groups/g1/messages'] = (_, _) {
        if (down) throw const ApiOffline();
        return {
          'items': [msg(1)],
          'has_more': false,
        };
      };
      final c = make(api);
      c.listen(chatProvider('g1'), (_, _) {});
      final chat = c.read(chatProvider('g1').notifier);
      chat.setActive(true);
      await tester.pump();
      expect(c.read(chatProvider('g1')).offline, isTrue);
      down = false;
      await tester.pump(chatEvery);
      expect((c.read(chatProvider('g1')).offline, c.read(chatProvider('g1')).messages.length), (false, 1));
      chat.setActive(false);
    });

    testWidgets('a quiet chat slows to 15 s, and a message speeds it up again', (tester) async {
      api.routes['GET /v1/groups/g1/messages'] = (_, _) => {'items': [], 'has_more': false};
      var at = DateTime.utc(2026, 10, 1, 12);
      final c = make(api, clock: () => at);
      c.listen(chatProvider('g1'), (_, _) {});
      final chat = c.read(chatProvider('g1').notifier);
      chat.setActive(true);
      await tester.pump();
      final n = polls();

      // Two quiet minutes pass at the fast rate (the 30th fire sits exactly on the two-minute mark).
      for (var i = 1; i <= 29; i++) {
        at = at.add(chatEvery);
        await tester.pump(chatEvery);
      }
      at = at.add(chatEvery);
      await tester.pump(chatEvery);
      final quiet = polls();
      expect(quiet, n + 30, reason: 'every 4 s for the first two minutes');

      // The chat has gone quiet: the next ask waits fifteen seconds, not four.
      at = at.add(chatEvery);
      await tester.pump(chatEvery);
      expect(polls(), quiet, reason: 'a quiet chat no longer asks every 4 s');
      at = at.add(chatIdleEvery - chatEvery);
      await tester.pump(chatIdleEvery - chatEvery);
      expect(polls(), quiet + 1, reason: 'the quiet chat asks every 15 s');

      // A message arrives: the fast rate comes back.
      api.routes['GET /v1/groups/g1/messages'] = (_, _) => {'items': [msg(5)], 'has_more': false};
      at = at.add(chatIdleEvery);
      await tester.pump(chatIdleEvery);
      final live = polls();
      at = at.add(chatEvery);
      await tester.pump(chatEvery);
      expect(polls(), live + 1, reason: 'a message brings the 4 s rate back');
      chat.setActive(false);
    });

    testWidgets('a page with more waiting is read to the end in one go', (tester) async {
      api.routes['GET /v1/groups/g1/messages'] = (q, _) {
        final after = int.tryParse(q?['after'] ?? '');
        if (after == null) {
          return {
            'items': [msg(10)],
            'has_more': false,
          };
        }
        return {
          'items': [msg(after + 1), msg(after + 2)],
          'has_more': after < 14,
        };
      };
      final c = make(api);
      c.listen(chatProvider('g1'), (_, _) {});
      final chat = c.read(chatProvider('g1').notifier);
      chat.setActive(true);
      await tester.pump();
      await tester.pump(chatEvery);
      expect([for (final m in c.read(chatProvider('g1')).messages) m.id], [10, 11, 12, 13, 14, 15, 16]);
      chat.setActive(false);
    });

    testWidgets('send adds the message once even if a poll brings it too; older pages load; report posts', (
      tester,
    ) async {
      api.routes['GET /v1/groups/g1/messages'] = (q, _) {
        if (q?['before'] != null) {
          return {
            'items': [msg(1), msg(2)],
            'has_more': false,
          };
        }
        return {
          'items': [msg(3), msg(4)],
          'has_more': true,
        };
      };
      api.routes['POST /v1/groups/g1/messages'] = (_, b) => msg(5)..['body'] = (b as Map)['body'];
      api.routes['POST /v1/reports'] = (_, _) => {'id': 'r1'};
      final c = make(api);
      c.listen(chatProvider('g1'), (_, _) {});
      final chat = c.read(chatProvider('g1').notifier);
      List<int> got() => [for (final m in c.read(chatProvider('g1')).messages) m.id];
      chat.setActive(true);
      await tester.pump();
      expect(got(), [3, 4]);
      chat.setActive(false);

      expect((await chat.send('  ')).refusal, Refusal.invalid);
      expect((await chat.send('x' * 1001)).refusal, Refusal.invalid);
      final sent = await chat.send(' hello ');
      expect(sent.value!.body, 'hello');
      expect(got(), [3, 4, 5]);
      expect(api.calls('POST', '/v1/groups/g1/messages').single.body, containsPair('body', 'hello'));

      await chat.poll();
      await chat.loadOlder();
      expect(got(), [1, 2, 3, 4, 5]);
      expect(c.read(chatProvider('g1')).hasOlder, isFalse);
      expect(api.calls('GET', '/v1/groups/g1/messages').last.query, {'before': '3', 'limit': '50'});

      expect((await chat.report(sent.value!, 'spam')).ok, isTrue);
      expect(api.calls('POST', '/v1/reports').single.body, containsPair('target_id', '5'));
    });
  });

  group('model', () {
    test('deck cards of a shared group carry no wisher count', () {
      expect(DeckCard.fromJson({'film_id': 'Q1', 'film': film('Q1').toJson(), 'seen_by': 1}).wishers, 0);
      expect(deckCap, 100);
    });
  });
}
