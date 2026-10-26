import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/data/deck.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/state/providers.dart';

import 'helpers.dart';

final now = DateTime.utc(2026, 10, 1, 12);

/// Calls [fn] and returns the [CrewRefused] code it throws.
Future<String> refusal(Future<Object?> Function() fn) async {
  try {
    await fn();
  } on CrewRefused catch (e) {
    return e.code;
  }
  return 'no refusal';
}

Map<String, dynamic> memberJson2(String id, {required bool owner}) => memberJson(id, id, me: id == 'm1', owner: owner);

void main() {
  final stubs = <(Film, StubDraft, DateTime)>[];
  late LocalCrewRepo repo;

  setUp(() {
    stubs.clear();
    repo = LocalCrewRepo(
      addStub: (f, d, at) {
        stubs.add((f, d, at));
        return d.toStub(id: 's${stubs.length}', no: stubs.length, filmId: f.id, created: at);
      },
      now: () => now,
      random: Random(3),
    );
  });

  Future<Crew> crewOf(List<String> names) async {
    var c = await repo.create('Friday gang', myName: 'Me');
    for (final n in names) {
      c = await repo.addMember(c, n);
    }
    return c;
  }

  String idOf(Crew c, String name) => c.members.firstWhere((m) => m.name == name).id;

  group('group', () {
    test('create: I am the owner and a member; names are checked', () async {
      final c = await repo.create('  Friday gang ', myName: ' Saksham ');
      expect(c.name, 'Friday gang');
      expect(c.shared, isFalse);
      expect(c.members.single.me && c.members.single.owner && !c.members.single.guest, isTrue);
      expect(c.members.single.name, 'Saksham');
      expect(c.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(await refusal(() => repo.create('  ')), 'invalid_request');
      expect(await refusal(() => repo.create('x' * 41)), 'invalid_request');
      expect((await repo.rename(c, ' New ')).name, 'New');
      expect(await refusal(() => repo.rename(c, '')), 'invalid_request');
    });

    test('members are names: unique without case, at most 30, each with an ink', () async {
      var c = await crewOf(['Asha', 'Ben']);
      expect([for (final m in c.members) m.ink], [0, 1, 2]);
      expect(c.members.where((m) => m.guest).map((m) => m.name), ['Asha', 'Ben']);
      expect(await refusal(() => repo.addMember(c, 'asha ')), 'name_taken');
      expect(await refusal(() => repo.addMember(c, '   ')), 'invalid_request');
      for (var i = 0; i < 27; i++) {
        c = await repo.addMember(c, 'P$i');
      }
      expect(c.members, hasLength(30));
      expect(await refusal(() => repo.addMember(c, 'One more')), 'group_full');
      expect({for (final m in c.members) m.id}, hasLength(30));
    });

    test('the shared list: no repeats, at most 200', () async {
      var c = await crewOf([]);
      c = await repo.addFilm(c, film('Q1'));
      expect((await repo.addFilm(c, film('Q1'))).films, hasLength(1));
      for (var i = 2; i <= 200; i++) {
        c = await repo.addFilm(c, film('Q$i'));
      }
      expect(await refusal(() => repo.addFilm(c, film('Q201'))), 'list_full');
      expect((await repo.removeFilm(c, 'Q1')).films, hasLength(199));
    });

    test('a local group has no invite code', () async {
      expect(await refusal(() async => repo.rotateInvite(await crewOf([]))), 'forbidden');
    });
  });

  group('deck and swipes (pass the phone)', () {
    final catalog = catalogOf([
      for (var i = 0; i < 80; i++) film('a$i', dir: ['DA'], pop: 80 - i),
    ]);
    final env = DeckEnv(catalog: catalog, today: DateTime(2026, 10, 1), myTaste: tasteOf({'DA': 3.0}));

    test('the deck uses my taste and the shared list; the version counts up', () async {
      var c = await crewOf(['Asha']);
      c = await repo.addFilm(c, film('mine', dir: ['DA']));
      c = await repo.rebuildDeck(c, env);
      expect(c.deck!.version, 1);
      expect(c.deckVersion, 1);
      final cards = {for (final x in c.deck!.cards) x.id: x};
      expect(cards['mine']!.wishers, 1, reason: 'on the shared list once');
      expect(c.deck!.cards, hasLength(deckRecs + 1));
      expect((await repo.rebuildDeck(c, env)).deck!.version, 2);
    });

    test('films a member swiped seen are not recommended again; my diary films neither', () async {
      var c = await crewOf(['Asha']);
      c = await repo.rebuildDeck(c, env);
      final first = ids(c.deck!.cards).first;
      c = await repo.swipes(c, [Swipe(memberId: idOf(c, 'Asha'), filmId: first, vote: Vote.seen)]);
      final again = await repo.rebuildDeck(
        c,
        DeckEnv(catalog: catalog, today: env.today, myTaste: env.myTaste, mySeen: {'a70'}),
      );
      expect(ids(again.deck!.cards), isNot(contains(first)));
      expect(ids(again.deck!.cards), isNot(contains('a70')));
      expect(again.votes[idOf(c, 'Asha')]![first], Vote.seen, reason: 'votes survive a rebuild');
    });

    test('each member swipes in turn; every swipe is kept per member and a later one replaces it', () async {
      var c = await crewOf(['Asha', 'Ben']);
      c = await repo.rebuildDeck(c, env);
      final me = c.me!.id, asha = idOf(c, 'Asha'), ben = idOf(c, 'Ben');
      final cards = ids(c.deck!.cards).take(3).toList();

      Future<void> swipe(String member, List<Vote> votes) async {
        for (var i = 0; i < votes.length; i++) {
          c = await repo.swipes(c, [Swipe(memberId: member, filmId: cards[i], vote: votes[i])]);
          expect(c.votes[member]!.length, i + 1, reason: 'saved at once');
        }
      }

      await swipe(me, [Vote.want, Vote.skip, Vote.seen]);
      await swipe(asha, [Vote.want, Vote.want, Vote.skip]);
      expect(c.votes.keys, {me, asha}, reason: 'Ben has not played yet');
      await swipe(ben, [Vote.want, Vote.skip, Vote.seen]);
      expect((c.tallies[cards[0]]!.want, c.tallies[cards[1]]!.want, c.tallies[cards[1]]!.skip), (3, 1, 2));
      expect((c.tallies[cards[2]]!.seen, c.tallies[cards[2]]!.skip), (2, 1));

      c = await repo.swipes(c, [Swipe(memberId: me, filmId: cards[0], vote: Vote.skip)]);
      expect((c.tallies[cards[0]]!.want, c.tallies[cards[0]]!.skip), (2, 1));
      // A null member is me. An unknown member is ignored.
      c = await repo.swipes(c, [
        Swipe(filmId: cards[1], vote: Vote.want),
        Swipe(memberId: 'nobody', filmId: cards[1], vote: Vote.want),
      ]);
      expect(c.votes[me]![cards[1]], Vote.want);
      expect(c.votes.containsKey('nobody'), isFalse);
    });

    test('removing a member removes their swipes, votes and replies', () async {
      var c = await crewOf(['Asha']);
      c = await repo.rebuildDeck(c, env);
      final asha = idOf(c, 'Asha'), film0 = c.deck!.cards.first.id;
      c = await repo.swipes(c, [Swipe(memberId: asha, filmId: film0, vote: Vote.want)]);
      c = await repo.createNight(
        c,
        NightCreate(films: [film('f1'), film('f2')], slots: [now.add(const Duration(days: 2))]),
      );
      final night = c.nights.single;
      c = await repo.vote(c, night.id, asha, {night.films.first.id});
      expect(c.nights.single.films.first.approvals, 1);
      expect(await refusal(() => repo.removeMember(c, c.me!.id)), 'forbidden');

      c = await repo.removeMember(c, asha);
      expect(c.members.map((m) => m.name), ['Me']);
      expect(c.votes.containsKey(asha), isFalse);
      expect(c.tallies[film0]?.want ?? 0, 0);
      expect(c.nights.single.votes.containsKey(asha), isFalse);
      expect(c.nights.single.films.first.approvals, 0);
    });
  });

  group('nights', () {
    NightCreate draft({int films = 2, int slots = 2, String? place, int day = 3}) => NightCreate(
      films: [for (var i = 0; i < films; i++) film('f$i', title: 'Film $i')],
      slots: [for (var i = 0; i < slots; i++) now.add(Duration(days: day + i, hours: 2))],
      tzOffsetMin: 330,
      place: place,
    );

    test('one film and one time make a set night with its event; anything else is a poll', () async {
      final c = await crewOf(['Asha']);
      final set = (await repo.createNight(c, draft(films: 1, slots: 1, place: '  Home '))).nights.single;
      expect(set.status, NightStatus.set);
      expect(set.event!.film.id, 'f0');
      expect(set.event!.startsAt, now.add(const Duration(days: 3, hours: 2)));
      expect((set.event!.tzOffsetMin, set.event!.place, set.place, set.hostId), (330, 'Home', 'Home', c.me!.id));
      expect(set.options.map((o) => o.kind), [OptionKind.film, OptionKind.slot]);

      final poll = (await repo.createNight(c, draft())).nights.single;
      expect(poll.status, NightStatus.poll);
      expect(poll.event, isNull);
      expect([for (final o in poll.films) o.position], [0, 1]);
      expect([for (final o in poll.slots) o.position], [0, 1]);
      expect({for (final o in poll.options) o.id}, hasLength(4));

      final both = await repo.createNight(await repo.createNight(c, draft(films: 1, slots: 1)), draft());
      expect(both.nights.first.status, NightStatus.poll, reason: 'newest first');
    });

    test('limits: 1 to 3 films, 1 to 2 times, within a day before to 400 days after now', () async {
      final c = await crewOf([]);
      for (final bad in [
        draft(films: 0),
        draft(films: 4),
        draft(slots: 0),
        draft(slots: 3),
        draft(day: -2),
        draft(day: 401),
        NightCreate(films: [film('f0'), film('f0')], slots: [now.add(const Duration(days: 1))]),
        NightCreate(films: [film('f0')], slots: [now.add(const Duration(days: 1)), now.add(const Duration(days: 1))]),
      ]) {
        expect(await refusal(() => repo.createNight(c, bad)), 'invalid_request');
      }
      expect((await repo.createNight(c, draft(day: 0))).nights, hasLength(1));
      expect(draft().isValid(now), isTrue);
    });

    test('approval voting, then close: most approved wins, a tie goes to the lowest position', () async {
      var c = await crewOf(['Asha', 'Ben']);
      c = await repo.createNight(c, draft());
      final n = c.nights.single;
      final (me, asha, ben) = (c.me!.id, idOf(c, 'Asha'), idOf(c, 'Ben'));
      final (f0, f1) = (n.films[0].id, n.films[1].id);
      final (s0, s1) = (n.slots[0].id, n.slots[1].id);

      c = await repo.vote(c, n.id, me, {f1, s1});
      c = await repo.vote(c, n.id, asha, {f1, f0, s0});
      c = await repo.vote(c, n.id, ben, {s1});
      var night = c.nights.single;
      expect({for (final o in night.options) o.id: o.approvals}, {f0: 1, f1: 2, s0: 1, s1: 2});
      expect(night.votes[asha], {f1, f0, s0});

      // Voting again replaces the member's votes.
      c = await repo.vote(c, n.id, asha, {f0});
      expect(c.nights.single.films[1].approvals, 1);
      c = await repo.vote(c, n.id, asha, {});
      expect(c.nights.single.votes[asha], isEmpty);

      expect(await refusal(() => repo.vote(c, n.id, me, {'nope'})), 'invalid_request');
      expect(await refusal(() => repo.vote(c, n.id, 'nobody', {f0})), 'forbidden');
      expect(await refusal(() => repo.vote(c, 'missing', me, {f0})), 'not_found');
      expect(await refusal(() => repo.rsvp(c, n.id, me, Rsvp.yes)), 'not_set', reason: 'nothing to reply to yet');

      // f1: me. s1: me and Ben. Close without ids.
      final closed = (await repo.closePoll(c, n.id, place: ' Cinepolis ')).nights.single;
      expect(closed.status, NightStatus.set);
      expect(closed.event!.film.id, 'f1');
      expect(closed.event!.startsAt, n.slots[1].startsAt);
      expect((closed.event!.place, closed.event!.tzOffsetMin), ('Cinepolis', 330));

      // The host may pick: film 0 at slot 0, whatever the votes say.
      final picked = (await repo.closePoll(c, n.id, filmOptionId: f0, slotOptionId: s0)).nights.single;
      expect((picked.event!.film.id, picked.event!.startsAt), ('f0', n.slots[0].startsAt));
      expect(
        await refusal(() => repo.closePoll(c, n.id, filmOptionId: s0)),
        'invalid_request',
        reason: 'a slot is not a film',
      );
    });

    test('closing an empty poll takes the first film and slot', () async {
      var c = await crewOf([]);
      c = await repo.createNight(c, draft());
      final e = (await repo.closePoll(c, c.nights.single.id)).nights.single.event!;
      expect((e.film.id, e.startsAt), ('f0', now.add(const Duration(days: 3, hours: 2))));
    });

    test('votes and closing need a poll; replies need a set night', () async {
      var c = await crewOf(['Asha']);
      c = await repo.createNight(c, draft(films: 1, slots: 1));
      final n = c.nights.single, asha = idOf(c, 'Asha');
      expect(await refusal(() => repo.vote(c, n.id, asha, {n.options.first.id})), 'not_polling');
      expect(await refusal(() => repo.closePoll(c, n.id)), 'not_polling');
      c = await repo.rsvp(c, n.id, asha, Rsvp.yes);
      c = await repo.rsvp(c, n.id, c.me!.id, Rsvp.maybe);
      c = await repo.rsvp(c, n.id, asha, Rsvp.no);
      expect(c.nights.single.rsvps, {asha: Rsvp.no, c.me!.id: Rsvp.maybe});
      expect(await refusal(() => repo.rsvp(c, n.id, 'nobody', Rsvp.yes)), 'forbidden');
      expect((await repo.deleteNight(c, n.id)).nights, isEmpty);
    });

    test('wrap-up writes my stub, then the night is done and cannot be wrapped again', () async {
      var c = await crewOf(['Asha', 'Ben']);
      c = await repo.createNight(c, draft(films: 1, slots: 1, place: 'Home'));
      final n = c.nights.single;
      c = await repo.rsvp(c, n.id, idOf(c, 'Ben'), Rsvp.yes);
      c = await repo.rsvp(c, n.id, idOf(c, 'Asha'), Rsvp.no);

      c = await repo.wrapUp(c, n.id, seatRow: 'D', firstSeat: 9);
      expect(c.nights.single.status, NightStatus.done);
      final (f, d, at) = stubs.single;
      expect(f.id, 'f0');
      expect(at, now);
      expect((d.seat, d.company, d.place), ('D9', 'Ben', 'Home'));
      expect(d.date, DateTime(2026, 10, 4), reason: '14:00 UTC plus 5:30 is still the 4th at the group');

      expect(await refusal(() => repo.wrapUp(c, n.id)), 'not_set');
      expect(stubs, hasLength(1));
    });

    test('wrap-up picks a row and a first seat when none is given, and checks the row', () async {
      var c = await crewOf([]);
      c = await repo.createNight(c, draft(films: 1, slots: 1));
      expect(await refusal(() => repo.wrapUp(c, c.nights.single.id, seatRow: 'AB')), 'invalid_request');
      await repo.wrapUp(c, c.nights.single.id);
      expect(stubs.single.$2.seat, matches(RegExp(r'^[A-L]([1-9]|1\d|20)$')));
      // A poll cannot be wrapped up.
      var p = await crewOf([]);
      p = await repo.createNight(p, draft());
      expect(await refusal(() => repo.wrapUp(p, p.nights.single.id)), 'not_set');
    });
  });

  group('json', () {
    test('a whole local group survives the local file', () async {
      final catalog = catalogOf([
        for (var i = 0; i < 70; i++) film('a$i', dir: ['DA'], pop: 80 - i),
      ]);
      var c = await crewOf(['Asha', 'Ben']);
      c = await repo.addFilm(c, film('Q5', title: 'Pushpa, 2; "The Rule"', dir: ['DA']));
      c = await repo.rebuildDeck(
        c,
        DeckEnv(catalog: catalog, today: DateTime(2026, 10, 1), myTaste: tasteOf({'DA': 3.0})),
      );
      final cards = ids(c.deck!.cards);
      c = await repo.swipes(c, [
        Swipe(filmId: cards[0], vote: Vote.want),
        Swipe(memberId: idOf(c, 'Asha'), filmId: cards[0], vote: Vote.skip),
        Swipe(memberId: idOf(c, 'Ben'), filmId: cards[1], vote: Vote.seen),
      ]);
      c = await repo.createNight(
        c,
        NightCreate(
          films: [film('f0'), film('f1')],
          slots: [now.add(const Duration(days: 2))],
          tzOffsetMin: -300,
          place: 'Home',
        ),
      );
      c = await repo.vote(c, c.nights.single.id, idOf(c, 'Asha'), {c.nights.single.films[1].id});
      c = await repo.createNight(c, NightCreate(films: [film('f9')], slots: [now.add(const Duration(days: 3))]));
      c = await repo.rsvp(c, c.nights.first.id, idOf(c, 'Ben'), Rsvp.maybe);

      final json = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
      final back = Crew.fromJson(json, shared: false);
      expect(jsonEncode(back.toJson()), jsonEncode(c.toJson()));
      expect(back.shared, isFalse);
      expect(back.deck!.cards, hasLength(c.deck!.cards.length));
      expect(back.nights.last.votes.values.single, {c.nights.last.films[1].id});
      expect(back.nights.first.rsvps.values.single, Rsvp.maybe);
      expect(back.nights.first.event!.startsAt, c.nights.first.event!.startsAt);
      expect(back.nights.first.event!.startsAt.isUtc, isTrue);
      expect(back.films.single.film.title, 'Pushpa, 2; "The Rule"');
      expect(back.votes.length, 3);
      expect(tallies(back.votes)[cards[0]]!.want, 1);
    });

    test('server shapes: a group, a night with `mine`, a deck and a message parse', () {
      final detail = Crew.fromJson(
        groupJson(
          'g1',
          version: 4,
          members: [memberJson('m1', 'Asha', me: true, owner: true), memberJson('m2', 'Ben', guest: true)],
        ),
      );
      expect(detail.shared, isTrue);
      expect((detail.id, detail.deckVersion, detail.inviteCode), ('g1', 4, 'ABCD2345'));
      expect(detail.me!.name, 'Asha');
      expect(detail.isOwner, isTrue);
      expect(detail.members[1].guest, isTrue);
      final hosted = Night(id: 'n', crewId: 'g1', hostId: 'm2');
      expect(detail.isHost(hosted), isTrue, reason: 'the owner may host any night');
      final member = Crew(
        id: 'g1',
        name: 'x',
        members: [memberJson2('m1', owner: false), memberJson2('m2', owner: true)].map(Member.fromJson).toList(),
      );
      expect(member.isHost(Night(id: 'n', crewId: 'g1', hostId: 'm1')), isTrue);
      expect(member.isHost(Night(id: 'n', crewId: 'g1', hostId: 'm2')), isFalse);

      final night = Night.fromJson({
        'id': 'n1',
        'group_id': 'g1',
        'status': 'poll',
        'host_id': 'm1',
        'tz_offset_min': 330,
        'place': null,
        'options': [
          {
            'id': 'o1',
            'kind': 'film',
            'position': 0,
            'film_id': 'Q1',
            'film': film('Q1').toJson(),
            'starts_at': null,
            'approvals': 2,
          },
          {
            'id': 'o2',
            'kind': 'slot',
            'position': 0,
            'film_id': null,
            'film': null,
            'starts_at': '2026-10-03T14:00:00.000Z',
            'approvals': 1,
          },
        ],
        'mine': ['o1'],
        'event': null,
        'rsvps': [
          {'member_id': 'm2', 'response': 'yes'},
        ],
      }, mineFor: 'm1');
      expect(night.votes, {
        'm1': {'o1'},
      });
      expect(night.options[1].startsAt, DateTime.utc(2026, 10, 3, 14));
      expect(night.rsvps['m2'], Rsvp.yes);
      expect(night.when, DateTime.utc(2026, 10, 3, 14));
      expect(night.film!.id, 'Q1');

      final deck = Deck.fromJson({
        'version': 2,
        'items': [
          {'film_id': 'Q1', 'film': film('Q1').toJson(), 'seen_by': 3},
        ],
      });
      expect((deck.version, deck.cards.single.seenBy, deck.cards.single.wishers), (2, 3, 0));

      final msg = Message.fromJson({
        'id': 7,
        'kind': 'system',
        'sender': null,
        'body': null,
        'code': 'night_set',
        'args': {'night_id': 'n1'},
        'film_id': null,
        'film': null,
        'night_id': 'n1',
        'created_at': '2026-10-01T12:00:00.000Z',
      });
      expect((msg.kind, msg.code, msg.args!['night_id']), (MessageKind.system, 'night_set', 'n1'));
      expect(
        Message.fromJson({'id': 8, 'kind': 'from_the_future', 'created_at': '2026-10-01T12:00:00.000Z'}).kind,
        MessageKind.system,
      );
    });
  });
}
