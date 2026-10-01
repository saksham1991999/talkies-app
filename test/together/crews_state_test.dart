import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/state/crews_remote.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/reminders.dart';

import 'helpers.dart';

final now = DateTime.utc(2026, 10, 1, 12);
final catalog = catalogOf([
  for (var i = 0; i < 80; i++) film('a$i', dir: ['DA'], pop: 80 - i),
]);

late Directory dir;

ProviderContainer make({
  FakeReminders? reminders,
  Api? api,
  bool online = false,
  DateTime? at,
  Future<void> Function()? sync,
}) => ProviderContainer.test(
  overrides: [
    docsDirProvider.overrideWithValue(dir),
    nowProvider.overrideWithValue(() => at ?? now),
    todayProvider.overrideWithValue(DateTime(2026, 10, 1)),
    remindersProvider.overrideWithValue(reminders ?? FakeReminders()),
    catalogProvider.overrideWith((ref) async => catalog),
    if (api != null) apiProvider.overrideWithValue(api),
    onlineProvider.overrideWithValue(online),
    if (sync != null) wrapupSyncProvider.overrideWithValue(sync),
  ],
);

/// A local group with Asha and Ben, held by the container.
Future<Crew> localCrew(ProviderContainer c) async {
  final made = await c.read(crewsProvider.notifier).create('Friday gang', myName: 'Me');
  final id = made.value!.id;
  c.listen(crewProvider(id), (_, _) {});
  final ctrl = c.read(crewProvider(id).notifier);
  await ctrl.addMember('Asha');
  await ctrl.addMember('Ben');
  return c.read(crewProvider(id)).crew;
}

String idOf(Crew crew, String name) => crew.members.firstWhere((m) => m.name == name).id;

void main() {
  setUp(() => dir = Directory.systemTemp.createTempSync('talkies_crews'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('local group through the controller', () {
    test('pass the phone: each member swipes in turn, nothing leaks between members, all saved at once', () async {
      final c = make();
      final crew = await localCrew(c);
      final ctrl = c.read(crewProvider(crew.id).notifier);
      expect((await ctrl.ensureDeck()).ok, isTrue);
      final deck = c.read(crewProvider(crew.id)).crew.deck!;
      expect(deck.cards, hasLength(60));
      expect((await ctrl.ensureDeck()).value!.deck!.version, 1, reason: 'a deck that exists is not rebuilt');

      final (me, asha, ben) = (crew.me!.id, idOf(crew, 'Asha'), idOf(crew, 'Ben'));
      final cards = ids(deck.cards);
      CrewState s() => c.read(crewProvider(crew.id));
      for (final (member, votes) in [
        (me, [Vote.want, Vote.skip, Vote.seen]),
        (asha, [Vote.want, Vote.want, Vote.skip]),
        (ben, [Vote.want, Vote.skip, Vote.seen]),
      ]) {
        expect(s().unswiped(member), hasLength(60), reason: 'earlier picks are not this member\'s picks');
        for (var i = 0; i < votes.length; i++) {
          expect((await ctrl.swipe(member, cards[i], votes[i])).ok, isTrue);
          expect(s().unswiped(member), hasLength(59 - i));
        }
      }
      expect(s().unswiped(me).first.id, cards[3]);

      // Results: want down, then seen up, then skip up, then deck order.
      // Films nobody swiped keep the deck order; the one two members saw goes after them.
      expect(ids(s().results.take(4)), [cards[0], cards[1], cards[3], cards[4]]);
      expect(s().results.last.id, cards[2]);
      expect(s().topMatch!.id, cards[0]);
      expect(ids(s().topThree), [cards[0], cards[1], cards[3]]);
      expect(ids(s().tonight(Random(1))).first, cards[0], reason: 'one film leads, so it wins');
      // A local deck counts "seen" swipes.
      expect(s().seenBy(s().crew.deck!.cards[2]), 2);

      // A new member sees every card; a swipe for an unknown member is refused.
      expect((await ctrl.swipe('nobody', cards[0], Vote.want)).refusal, Refusal.notFound);

      // Saved at once: a fresh container reads the same file.
      await c.read(crewsProvider.notifier).flush();
      final again = make();
      final back = again.read(crewsProvider).crews.single;
      expect(back.votes[ben], {cards[0]: Vote.want, cards[1]: Vote.skip, cards[2]: Vote.seen});
      expect(back.tallies[cards[0]]!.want, 3, reason: 'tallies are derived on load');
      expect(jsonEncode(back.toJson()), jsonEncode(s().crew.toJson()));
    });

    test('wrap-up writes my stub with the people who came, and cancels the reminders', () async {
      final fake = FakeReminders();
      final c = make(reminders: fake);
      final crew = await localCrew(c);
      final ctrl = c.read(crewProvider(crew.id).notifier);
      final made = await ctrl.createNight(
        NightCreate(
          films: [catalog.byId['a1']!],
          slots: [DateTime.utc(2026, 10, 3, 14)],
          tzOffsetMin: 330,
          place: 'Home',
        ),
      );
      final night = made.value!;
      expect(night.status, NightStatus.set);
      await ctrl.rsvp(night.id, idOf(crew, 'Ben'), Rsvp.yes);
      await ctrl.rsvp(night.id, idOf(crew, 'Asha'), Rsvp.no);
      expect(
        await ctrl.setReminder(night.id, true, title: 'Movie night', dayBody: 'Tomorrow', hourBody: 'Soon'),
        isTrue,
      );
      expect(fake.scheduled, hasLength(2));

      final r = await ctrl.wrapUp(night.id, seatRow: 'C', firstSeat: 4);
      expect(r.ok, isTrue);
      expect(c.read(crewProvider(crew.id)).crew.nights.single.status, NightStatus.done);
      final stub = c.read(diaryProvider).stubs.single;
      expect(stub.filmId, 'a1');
      expect(stub.company, 'Ben');
      expect(stub.seat, 'C4');
      expect(stub.place, 'Home');
      expect(stub.date, DateTime(2026, 10, 3));
      expect(stub.created, now);
      expect(c.read(diaryProvider).films.containsKey('a1'), isTrue);
      expect(fake.scheduled, isEmpty, reason: 'the night is over');
      expect(c.read(reminderOnProvider(night.id)), isFalse);

      expect((await ctrl.wrapUp(night.id)).refusal, Refusal.closed);
      expect(c.read(diaryProvider).stubs, hasLength(1));
    });

    test('a local group does not need the server, and leaving it removes it', () async {
      // apiProvider is not overridden: touching it would throw.
      final c = make();
      final crew = await localCrew(c);
      final ctrl = c.read(crewProvider(crew.id).notifier);
      expect((await ctrl.rename('Saturday gang')).ok, isTrue);
      expect(c.read(crewsProvider).crews.single.name, 'Saturday gang');
      expect((await ctrl.rotateInvite()).refusal, Refusal.notAllowed);
      expect(c.read(groupsProvider), hasLength(1));
      expect((await ctrl.leave()).ok, isTrue);
      expect(c.read(crewsProvider).crews, isEmpty);
      expect(c.read(crewProvider(crew.id)).gone, isTrue);
      expect(c.read(groupsProvider), isEmpty);
    });

    test('errors become refusals, never exceptions', () async {
      final c = make();
      final crew = await localCrew(c);
      final ctrl = c.read(crewProvider(crew.id).notifier);
      expect((await ctrl.addMember('asha')).refusal, Refusal.nameTaken);
      expect((await ctrl.addMember('')).refusal, Refusal.invalid);
      expect((await ctrl.removeMember(crew.me!.id)).refusal, Refusal.notAllowed);
      expect((await ctrl.vote('nope', crew.me!.id, {})).refusal, Refusal.notFound);
      expect((await ctrl.createNight(NightCreate(films: const [], slots: [now]))).refusal, Refusal.invalid);
      // A failed action leaves the state as it was, and the queue keeps working.
      expect(c.read(crewProvider(crew.id)).crew.members, hasLength(3));
      expect((await ctrl.addMember('Chitra')).ok, isTrue);
    });

    test('actions queue: quick taps all land on the result of the one before', () async {
      final c = make();
      final crew = await localCrew(c);
      final ctrl = c.read(crewProvider(crew.id).notifier);
      final results = await Future.wait([for (var i = 0; i < 8; i++) ctrl.addMember('P$i')]);
      expect(results.every((r) => r.ok), isTrue);
      expect(c.read(crewProvider(crew.id)).crew.members, hasLength(11));
    });
  });

  group('crews.json', () {
    test('survives a restart: groups, deck, nights, reminders', () async {
      final c = make();
      final crew = await localCrew(c);
      final ctrl = c.read(crewProvider(crew.id).notifier);
      await ctrl.rebuildDeck();
      final night = (await ctrl.createNight(NightCreate(films: [film('f1')], slots: [DateTime.utc(2026, 10, 3, 14)])))
          .value!;
      await ctrl.setReminder(night.id, true, title: 't', dayBody: 'd', hourBody: 'h');
      await c.read(crewsProvider.notifier).flush();

      final again = make();
      final s = again.read(crewsProvider);
      expect(s.crews.single.name, 'Friday gang');
      expect(s.crews.single.deck!.cards, hasLength(60));
      expect(s.crews.single.nights.single.id, night.id);
      expect(s.reminders, {night.id: false});
      expect(again.read(reminderOnProvider(night.id)), isTrue);
    });

    test('a file that is not JSON is kept for recovery and the app starts empty', () async {
      File('${dir.path}/crews.json').writeAsStringSync('{{{ not json');
      final c = make();
      expect(c.read(crewsProvider).crews, isEmpty);
      expect(dir.listSync().map((e) => e.path.split('/').last), contains(startsWith('crews.json.corrupt-')));
      await c.read(crewsProvider.notifier).create('New');
      await c.read(crewsProvider.notifier).flush();
      expect(File('${dir.path}/crews.json').existsSync(), isTrue);
    });

    test('JSON of the wrong shape is kept for recovery too', () async {
      File('${dir.path}/crews.json').writeAsStringSync(
        jsonEncode({
          'crews': [
            {'id': 5},
          ],
        }),
      );
      final c = make();
      expect(c.read(crewsProvider).crews, isEmpty);
      expect(dir.listSync().map((e) => e.path.split('/').last), contains(startsWith('crews.json.corrupt-')));
    });

    test('reading it needs no other file and no network', () {
      // Only docsDirProvider is set: crewsProvider must not read the diary, the catalog or the api.
      final c = ProviderContainer.test(overrides: [docsDirProvider.overrideWithValue(dir)]);
      expect(c.read(crewsProvider).crews, isEmpty);
      expect(c.read(groupsProvider), isEmpty);
      expect(c.read(nightsProvider), isEmpty);
    });
  });

  group('reminders', () {
    final start = DateTime.utc(2026, 10, 10, 18);

    Future<(ProviderContainer, FakeReminders, CrewController, Night)> night({DateTime? at, bool granted = true}) async {
      final fake = FakeReminders(granted: granted);
      final c = make(reminders: fake, at: at);
      final crew = await localCrew(c);
      final ctrl = c.read(crewProvider(crew.id).notifier);
      final n = (await ctrl.createNight(NightCreate(films: [film('f1')], slots: [start]))).value!;
      return (c, fake, ctrl, n);
    }

    test('on: one a day before and one two hours before, with the caller\'s texts; off cancels both', () async {
      final (c, fake, ctrl, n) = await night();
      expect(
        await ctrl.setReminder(n.id, true, title: 'Dune tonight', dayBody: 'Tomorrow 6 PM', hourBody: 'In 2 hours'),
        isTrue,
      );
      expect(fake.permissionAsks, 1);
      expect(fake.scheduled.keys.toSet(), {reminderId(n.id, 0), reminderId(n.id, 1)});
      final day = fake.scheduled[reminderId(n.id, 0)]!;
      expect((day.title, day.body, day.when), ('Dune tonight', 'Tomorrow 6 PM', DateTime.utc(2026, 10, 9, 18)));
      final hour = fake.scheduled[reminderId(n.id, 1)]!;
      expect((hour.body, hour.when), ('In 2 hours', DateTime.utc(2026, 10, 10, 16)));
      expect(c.read(reminderOnProvider(n.id)), isTrue);

      expect(await ctrl.setReminder(n.id, false, title: '', dayBody: '', hourBody: ''), isTrue);
      expect(fake.scheduled, isEmpty);
      expect(c.read(reminderOnProvider(n.id)), isFalse);
    });

    test('past times are dropped', () async {
      final (_, fake, ctrl, n) = await night(at: start.subtract(const Duration(hours: 10)));
      await ctrl.setReminder(n.id, true, title: 't', dayBody: 'd', hourBody: 'h');
      expect(fake.scheduled.keys, [reminderId(n.id, 1)]);
    });

    test('no permission: nothing is scheduled and nothing is remembered', () async {
      final (c, fake, ctrl, n) = await night(granted: false);
      expect(await ctrl.setReminder(n.id, true, title: 't', dayBody: 'd', hourBody: 'h'), isFalse);
      expect(fake.scheduled, isEmpty);
      expect(c.read(reminderOnProvider(n.id)), isFalse);
    });

    test('a poll has no date yet, so no reminder', () async {
      final fake = FakeReminders();
      final c = make(reminders: fake);
      final crew = await localCrew(c);
      final ctrl = c.read(crewProvider(crew.id).notifier);
      final poll = (await ctrl.createNight(NightCreate(films: [film('f1'), film('f2')], slots: [start]))).value!;
      expect(await ctrl.setReminder(poll.id, true, title: 't', dayBody: 'd', hourBody: 'h'), isFalse);
      expect(fake.permissionAsks, 0, reason: 'no prompt for nothing');
    });

    test('deleting the night cancels its reminders', () async {
      final (c, fake, ctrl, n) = await night();
      await ctrl.setReminder(n.id, true, title: 't', dayBody: 'd', hourBody: 'h');
      expect((await ctrl.deleteNight(n.id)).ok, isTrue);
      expect(fake.scheduled, isEmpty);
      expect(c.read(crewsProvider).reminders, isEmpty);
    });

    test('sign-out drops only the reminders of shared nights; reconcile drops vanished ones', () async {
      final fake = FakeReminders();
      final c = make(reminders: fake);
      final store = c.read(crewsProvider.notifier);
      for (final (id, shared) in [('local', false), ('shared1', true), ('shared2', true)]) {
        await fake.schedule(id: reminderId(id, 0), title: id, body: '', when: start);
        await fake.schedule(id: reminderId(id, 1), title: id, body: '', when: start);
        store.remind(id, shared: shared);
      }
      await store.reconcile({'shared1'});
      expect(c.read(crewsProvider).reminders.keys, {'local', 'shared1'});
      expect(fake.scheduled.values.map((s) => s.title).toSet(), {'local', 'shared1'});
      await store.dropShared();
      expect(c.read(crewsProvider).reminders.keys, {'local'});
      expect(fake.scheduled.values.map((s) => s.title).toSet(), {'local'});
    });

    test('ids are stable and fit a 32-bit notification id', () {
      expect(reminderId('abc', 0), reminderId('abc', 0));
      expect(reminderId('abc', 0), isNot(reminderId('abc', 1)));
      expect(reminderId('abc', 1) - reminderId('abc', 0), 1);
      for (final id in ['abc', newId(), newId(), '']) {
        for (final slot in [0, 1]) {
          expect(reminderId(id, slot), inInclusiveRange(0, 0x7fffffff));
        }
      }
    });
  });

  group('lists of groups and nights', () {
    test('nights: still to come first (soonest on top), then the past (latest on top)', () async {
      final c = make(at: DateTime.utc(2026, 10, 10, 12));
      final store = c.read(crewsProvider.notifier);
      final made = (await store.create('A', myName: 'Me')).value!;
      Night n(String id, DateTime at) => Night(
        id: id,
        crewId: made.id,
        status: NightStatus.set,
        event: NightEvent(film: film('Q$id'), startsAt: at),
      );
      store.put(
        made.copyWith(
          nights: [
            n('past-old', DateTime.utc(2026, 10, 1, 18)),
            n('later', DateTime.utc(2026, 10, 12, 18)),
            n('past-new', DateTime.utc(2026, 10, 9, 18)),
            n('soon', DateTime.utc(2026, 10, 10, 18)),
            n('just-started', DateTime.utc(2026, 10, 10, 11)),
          ],
        ),
      );
      expect(
        [for (final e in c.read(nightsProvider)) e.night.id],
        ['just-started', 'soon', 'later', 'past-new', 'past-old'],
      );
      expect(c.read(nightsProvider).first.crew.name, 'A');

      // The Home row: the soonest night still to come that is not wrapped up.
      expect(c.read(nextNightProvider)!.night.id, 'just-started');
      final crew = c.read(crewsProvider).crews.single;
      store.put(
        crew.copyWith(
          nights: [for (final x in crew.nights) x.id == 'just-started' ? x.copyWith(status: NightStatus.done) : x],
        ),
      );
      expect(c.read(nextNightProvider)!.night.id, 'soon');
      store.put(
        crew.copyWith(
          nights: [
            for (final x in crew.nights)
              if (x.id.startsWith('past')) x,
          ],
        ),
      );
      expect(c.read(nextNightProvider), isNull, reason: 'only past nights are left');
    });

    test('a poll counts by its earliest slot', () async {
      final c = make(at: DateTime.utc(2026, 10, 10, 12));
      final store = c.read(crewsProvider.notifier);
      final made = (await store.create('A')).value!;
      final repo = c.read(localCrewRepoProvider);
      var crew = await repo.createNight(
        made,
        NightCreate(
          films: [film('f1'), film('f2')],
          slots: [DateTime.utc(2026, 10, 20, 18), DateTime.utc(2026, 10, 12, 18)],
        ),
      );
      crew = await repo.createNight(crew, NightCreate(films: [film('f3')], slots: [DateTime.utc(2026, 10, 11, 18)]));
      store.put(crew);
      expect(
        [for (final e in c.read(nightsProvider)) e.night.when],
        [DateTime.utc(2026, 10, 11, 18), DateTime.utc(2026, 10, 12, 18)],
      );
    });
  });
}
