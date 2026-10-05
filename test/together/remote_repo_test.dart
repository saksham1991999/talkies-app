import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/data/deck.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/state/crews_remote.dart';

import 'helpers.dart';

const me = Member(id: 'm1', name: 'Me', me: true, owner: true);
const ben = Member(id: 'm2', name: 'Ben', guest: true);

Crew crew({int deck = 2, List<Night> nights = const []}) => Crew(
  id: 'g1',
  name: 'Friday gang',
  shared: true,
  members: const [me, ben],
  deckVersion: deck,
  deck: Deck(version: deck),
  nights: nights,
);

/// What a call throws, or 'nothing'.
Future<Object> thrown(Future<Object?> Function() f) async {
  try {
    await f();
  } catch (e) {
    return e;
  }
  return 'nothing';
}

void main() {
  late FakeApi api;
  late RemoteCrewRepo repo;
  var clock = DateTime.utc(2026, 10, 1, 12);

  setUp(() {
    api = FakeApi();
    clock = DateTime.utc(2026, 10, 1, 12);
    repo = RemoteCrewRepo(api, now: () => clock);
  });

  group('errors', () {
    test('no network and a lost session become CrewOffline', () async {
      api.routes['PATCH /v1/groups/g1'] = (_, _) => throw const ApiOffline('timeout');
      expect(await thrown(() => repo.rename(crew(), 'x')), isA<CrewOffline>());
      api.routes['PATCH /v1/groups/g1'] = (_, _) => throw const ApiUnauthorized();
      expect(await thrown(() => repo.rename(crew(), 'x')), isA<CrewOffline>());
    });

    test('a refusal of the server keeps its code and status', () async {
      api.routes['POST /v1/groups/g1/guests'] = (_, _) => throw const ApiError(409, 'name_taken', 'taken');
      final e = await thrown(() => repo.addMember(crew(), 'Ben')) as CrewRefused;
      expect((e.code, e.status), ('name_taken', 409));
    });

    test('a reply that is not shaped like API.md is a refusal, not a crash', () async {
      api.routes['GET /v1/groups'] = (_, _) => ['not', 'a', 'map'];
      expect(((await thrown(repo.groups)) as CrewRefused).code, 'bad_reply');
      api.routes['PATCH /v1/groups/g1'] = (_, _) => {'name': 5};
      expect(((await thrown(() => repo.rename(crew(), 'x'))) as CrewRefused).code, 'bad_reply');
      api.routes['GET /v1/groups/g1/messages'] = (_, _) => {'items': 'x'};
      expect(await thrown(() => repo.messages('g1')), isA<CrewRefused>());
      // A status or time this app cannot read.
      api.routes['POST /v1/groups/g1/nights'] = (_, _) => nightJson(status: 'weird');
      final draft = NightCreate(films: [film('Q1')], slots: [DateTime.utc(2026, 10, 3)]);
      expect(((await thrown(() => repo.createNight(crew(), draft))) as CrewRefused).code, 'bad_reply');
      api.routes['POST /v1/groups/g1/nights'] = (_, _) => nightJson()..['options'][2]['starts_at'] = 'yesterday-ish';
      expect(((await thrown(() => repo.createNight(crew(), draft))) as CrewRefused).code, 'bad_reply');
    });

    test('the controller words each one as a refusal', () async {
      expect(await outcomeOf(() async => throw const CrewOffline()).then((o) => o.refusal), Refusal.offline);
      for (final (code, status, want) in [
        ('name_taken', 409, Refusal.nameTaken),
        ('group_full', 409, Refusal.groupFull),
        ('list_full', 409, Refusal.listFull),
        ('group_limit', 409, Refusal.groupLimit),
        ('invalid_code', 404, Refusal.invalidCode),
        ('not_polling', 409, Refusal.closed),
        ('not_set', 409, Refusal.closed),
        ('rate_limited', 429, Refusal.rateLimited),
        ('forbidden', 403, Refusal.notAllowed),
        ('not_found', 404, Refusal.notFound),
        ('invalid_request', 422, Refusal.invalid),
        ('bad_reply', 0, Refusal.other),
        ('upstream_unavailable', 502, Refusal.other),
      ]) {
        final o = await outcomeOf<void>(() async => throw CrewRefused(code, status));
        expect(o.refusal, want, reason: '$code $status');
        expect(o.ok, isFalse);
      }
    });
  });

  group('groups', () {
    test('load: the group, its list, deck, my votes and nights in one read', () async {
      api.routes['GET /v1/groups/g1'] = (_, _) => groupJson(
        'g1',
        version: 3,
        members: [memberJson('m1', 'Me', me: true, owner: true), memberJson('m2', 'Ben', guest: true)],
      );
      api.routes['GET /v1/groups/g1/films'] = (_, _) => {
        'items': [
          {'film_id': 'Q7', 'film': film('Q7').toJson()},
        ],
      };
      api.routes['GET /v1/groups/g1/deck'] = (_, _) => deckJson(3, ['Q1', 'Q2'], seenBy: 2);
      api.routes['GET /v1/groups/g1/tallies'] = (_, _) => {
        'tallies': {
          'Q1': {'want': 2, 'skip': 0, 'seen': 1},
        },
        'mine': {'Q1': 'want', 'Q2': 'from_the_future'},
      };
      api.routes['GET /v1/groups/g1/nights'] = (_, _) => {
        'items': [
          nightJson(mine: ['o1']),
        ],
      };
      // Guest votes read earlier survive; mine are replaced.
      final before = crew().copyWith(
        votes: {
          'm2': {'Q9': Vote.skip},
          'm1': {'Qold': Vote.want},
        },
      );
      final c = await repo.load(before);
      expect(c.shared, isTrue);
      expect((c.name, c.inviteCode, c.deckVersion, c.deck!.version), ('Friday gang', 'ABCD2345', 3, 3));
      expect(c.films.single.filmId, 'Q7');
      expect(c.deck!.cards.map((x) => (x.id, x.seenBy)), [('Q1', 2), ('Q2', 2)]);
      expect(c.tallies['Q1']!.want, 2);
      expect(c.votes, {
        'm1': {'Q1': Vote.want},
        'm2': {'Q9': Vote.skip},
      });
      expect(c.nights.single.votes, {
        'm1': {'o1'},
      });
      expect(c.members.map((m) => m.id), ['m1', 'm2']);
      expect(api.log.map((x) => x.method), everyElement('GET'));
    });

    test('groups: every group with its members and nights (1 + 2N reads)', () async {
      api.routes['GET /v1/groups'] = (_, _) => {
        'items': [groupJson('g1'), groupJson('g2', name: 'Other')],
      };
      for (final g in ['g1', 'g2']) {
        api.routes['GET /v1/groups/$g'] = (_, _) =>
            groupJson(g, name: g, members: [memberJson('m1', 'Me', me: true, owner: true)]);
        api.routes['GET /v1/groups/$g/nights'] = (_, _) => {
          'items': [
            nightJson(id: 'n-$g', gid: g, mine: ['o2']),
          ],
        };
      }
      final list = await repo.groups();
      expect(list.map((c) => c.id), ['g1', 'g2']);
      expect(list[1].nights.single.id, 'n-g2');
      expect(list[1].nights.single.votes['m1'], {'o2'});
      expect(list.every((c) => c.shared && c.members.length == 1), isTrue);
      expect(api.log, hasLength(5));
    });

    test('create, rename, guests, members, invite code, delete and leave hit the right paths', () async {
      api.routes['POST /v1/groups'] = (_, b) => groupJson('g9', name: (b as Map)['name'] as String);
      api.routes['GET /v1/groups/g9'] = (_, _) =>
          groupJson('g9', members: [memberJson('m1', 'Me', me: true, owner: true)]);
      api.routes['GET /v1/groups/g9/nights'] = (_, _) => {'items': <dynamic>[]};
      final made = await repo.create('  New one ');
      expect((made.id, made.members.single.owner), ('g9', true));
      expect(api.calls('POST', '/v1/groups').single.body, {'name': 'New one'});

      api.routes['PATCH /v1/groups/g1'] = (_, b) => groupJson('g1', name: (b as Map)['name'] as String);
      expect((await repo.rename(crew(), ' Saturday ')).name, 'Saturday');
      expect(api.calls('PATCH', '/v1/groups/g1').single.body, {'name': 'Saturday'});

      api.routes['POST /v1/groups/g1/guests'] = (_, b) => memberJson('m3', (b as Map)['name'] as String, guest: true);
      final withGuest = await repo.addMember(crew(), ' Chitra ');
      expect(withGuest.members.map((m) => m.name), ['Me', 'Ben', 'Chitra']);
      expect(withGuest.members.last.guest, isTrue);
      expect(api.calls('POST', '/v1/groups/g1/guests').single.body, {'name': 'Chitra'});

      api.routes['POST /v1/groups/g1/invite/rotate'] = (_, _) => {'invite_code': 'ZZZZ2222'};
      expect((await repo.rotateInvite(crew())).inviteCode, 'ZZZZ2222');

      api.routes['DELETE /v1/groups/g1'] = (_, _) => null;
      await repo.delete(crew());
      api.routes['DELETE /v1/groups/g1/members/me'] = (_, _) => null;
      await repo.leave(crew());
      expect(api.log.map((x) => '${x.method} ${x.path}').toList().sublist(api.log.length - 2), [
        'DELETE /v1/groups/g1',
        'DELETE /v1/groups/g1/members/me',
      ]);
    });

    test('removing a member deletes them, then reads the group again', () async {
      api.routes['DELETE /v1/groups/g1/members/m2'] = (_, _) => null;
      api.routes['GET /v1/groups/g1'] = (_, _) =>
          groupJson('g1', members: [memberJson('m1', 'Me', me: true, owner: true)]);
      api.routes['GET /v1/groups/g1/films'] = (_, _) => {'items': <dynamic>[]};
      api.routes['GET /v1/groups/g1/deck'] = (_, _) => deckJson(2, []);
      api.routes['GET /v1/groups/g1/tallies'] = (_, _) => emptyTallies();
      api.routes['GET /v1/groups/g1/nights'] = (_, _) => {'items': <dynamic>[]};
      final c = await repo.removeMember(
        crew().copyWith(
          votes: {
            'm2': {'Q1': Vote.want},
          },
        ),
        'm2',
      );
      expect(c.members.map((m) => m.id), ['m1']);
      expect(c.votes.containsKey('m2'), isFalse);
    });

    test('the shared list: custom films stay on this phone, the id is escaped, a full list is refused', () async {
      expect(((await thrown(() => repo.addFilm(crew(), film('my:3')))) as CrewRefused).status, 422);
      expect(api.log, isEmpty, reason: 'no request for a film nobody else could show');

      api.routes['PUT /v1/groups/g1/films/Q42'] = (_, b) => null;
      final c = await repo.addFilm(
        crew().copyWith(films: [WatchItem(film('Q42')), WatchItem(film('Q1'))]),
        film('Q42', title: 'Newer'),
      );
      expect(c.films.map((w) => w.filmId), ['Q1', 'Q42'], reason: 'no repeat; the new snapshot is last');
      expect(c.films.last.film.title, 'Newer');
      expect((api.calls('PUT', '/v1/groups/g1/films/Q42').single.body as Map)['film']['t'], 'Newer');

      api.routes['PUT /v1/groups/g1/films/Q43'] = (_, _) => throw const ApiError(409, 'list_full', 'full');
      expect(((await thrown(() => repo.addFilm(crew(), film('Q43')))) as CrewRefused).code, 'list_full');

      api.routes['DELETE /v1/groups/g1/films/Q42'] = (_, _) => null;
      expect((await repo.removeFilm(c, 'Q42')).films.map((w) => w.filmId), ['Q1']);
    });
  });

  group('deck', () {
    final env = DeckEnv(
      catalog: catalogOf([
        for (var i = 0; i < 80; i++) film('a$i', dir: ['DA'], pop: 80 - i),
      ]),
      today: DateTime(2026, 10, 1),
    );

    void inputs() {
      api.routes['GET /v1/groups/g1/deck-inputs'] = (_, _) => {
        'tastes': [
          tasteOf({'DA': 3.0}).toJson(),
          'garbage',
          {'v': 99},
        ],
        'seen': ['a1'],
        'wanted': [
          {
            'film_id': 'w1',
            'film': film('w1', dir: ['DA']).toJson(),
            'n': 2,
          },
        ],
      };
    }

    test('builds from the inputs and writes with the version it read; the answer is read back', () async {
      inputs();
      api.routes['PUT /v1/groups/g1/deck'] = (_, _) => {'version': 3};
      api.routes['GET /v1/groups/g1/deck'] = (_, _) => deckJson(3, ['w1', 'a0'], seenBy: 1);
      final c = await repo.rebuildDeck(crew(deck: 2), env);
      final put = api.calls('PUT', '/v1/groups/g1/deck').single.body as Map;
      expect(put.keys, {'base_version', 'items'});
      expect(put['base_version'], 2);
      final items = put['items'] as List;
      expect(items.length, lessThanOrEqualTo(deckCap));
      expect(items.first.keys, {'film_id', 'film'}, reason: 'no seen_by or wishers go up');
      final sent = [for (final i in items) i['film_id']];
      expect(sent, contains('w1'));
      expect(sent, isNot(contains('a1')), reason: 'the server said it is seen');
      expect(sent.length, deckRecs + 1);
      expect((c.deck!.version, c.deckVersion, c.deck!.cards.first.seenBy), (3, 3, 1));
    });

    test('someone else wrote first (409): their deck is adopted, none written over it', () async {
      inputs();
      api.routes['PUT /v1/groups/g1/deck'] = (_, _) =>
          throw const ApiError(409, 'deck_conflict', 'stale', {'current_version': 5});
      api.routes['GET /v1/groups/g1/deck'] = (_, _) => deckJson(5, ['Q5']);
      final c = await repo.rebuildDeck(crew(deck: 2), env);
      expect((c.deck!.version, c.deckVersion, c.deck!.cards.single.id), (5, 5, 'Q5'));
      expect(api.calls('PUT', '/v1/groups/g1/deck'), hasLength(1));
      expect(api.calls('GET', '/v1/groups/g1/deck'), hasLength(1));
    });

    test('at most one write every 10 seconds: in between the server\'s deck is read', () async {
      inputs();
      api.routes['PUT /v1/groups/g1/deck'] = (_, _) => {'version': 3};
      api.routes['GET /v1/groups/g1/deck'] = (_, _) => deckJson(3, ['Q1']);
      await repo.rebuildDeck(crew(), env);
      clock = clock.add(const Duration(seconds: 9));
      final again = await repo.rebuildDeck(crew(deck: 3), env);
      expect(api.calls('PUT', '/v1/groups/g1/deck'), hasLength(1));
      expect(
        api.calls('GET', '/v1/groups/g1/deck-inputs'),
        hasLength(1),
        reason: 'no work for a write that cannot happen',
      );
      expect(again.deck!.version, 3);
      clock = clock.add(const Duration(seconds: 1));
      await repo.rebuildDeck(crew(deck: 3), env);
      expect(api.calls('PUT', '/v1/groups/g1/deck'), hasLength(2));
      expect(((api.calls('PUT', '/v1/groups/g1/deck').last.body) as Map)['base_version'], 3);
    });

    test('a refused write that is not a conflict stays an error', () async {
      inputs();
      api.routes['PUT /v1/groups/g1/deck'] = (_, _) => throw const ApiError(429, 'rate_limited', 'slow down');
      expect(((await thrown(() => repo.rebuildDeck(crew(), env))) as CrewRefused).status, 429);
      expect(api.calls('GET', '/v1/groups/g1/deck'), isEmpty);
    });
  });

  group('swipes', () {
    test('50 to a request; inside a batch the last swipe on a film wins; I go without a member id', () async {
      final batch = [
        for (var f = 0; f < 60; f++) ...[
          Swipe(memberId: 'm1', filmId: 'Q$f', vote: Vote.want),
          Swipe(memberId: 'm2', filmId: 'Q$f', vote: Vote.skip),
        ],
        // Ten changes of mind: these replace the first ten of mine.
        for (var f = 0; f < 10; f++) Swipe(filmId: 'Q$f', vote: Vote.seen),
      ];
      api.routes['PUT /v1/groups/g1/swipes'] = (_, b) => {'saved': ((b as Map)['swipes'] as List).length};
      api.routes['GET /v1/groups/g1/tallies'] = (_, _) => {
        'tallies': {
          'Q0': {'want': 0, 'skip': 1, 'seen': 1},
        },
        'mine': <String, dynamic>{},
      };
      final c = await repo.swipes(crew(), batch);
      final puts = [for (final p in api.calls('PUT', '/v1/groups/g1/swipes')) (p.body as Map)['swipes'] as List];
      expect(puts.map((p) => p.length), [50, 50, 20]);
      final all = [for (final p in puts) ...p];
      expect(all, hasLength(120));
      expect({for (final s in all) '${s['member_id']}|${s['film_id']}'}, hasLength(120));
      expect(all.every((s) => s.keys.length == 3 && {'want', 'skip', 'seen'}.contains(s['vote'])), isTrue);
      expect(all.where((s) => s['member_id'] == null), hasLength(60));
      expect(all.where((s) => s['member_id'] == 'm2'), hasLength(60));
      expect(all.firstWhere((s) => s['member_id'] == null && s['film_id'] == 'Q3')['vote'], 'seen');
      expect(all.firstWhere((s) => s['member_id'] == null && s['film_id'] == 'Q30')['vote'], 'want');
      expect(all.firstWhere((s) => s['member_id'] == 'm2' && s['film_id'] == 'Q3')['vote'], 'skip');
      expect(c.tallies['Q0']!.seen, 1, reason: 'the tallies are read after the last write');
      expect(api.log.last.method, 'GET');
    });

    test('exactly 50 is one request; none is no request', () async {
      api.routes['PUT /v1/groups/g1/swipes'] = (_, _) => {'saved': 50};
      api.routes['GET /v1/groups/g1/tallies'] = (_, _) => emptyTallies();
      await repo.swipes(crew(), [for (var f = 0; f < 50; f++) Swipe(filmId: 'Q$f', vote: Vote.want)]);
      expect(api.calls('PUT', '/v1/groups/g1/swipes'), hasLength(1));
      await repo.swipes(crew(), const []);
      expect(api.calls('PUT', '/v1/groups/g1/swipes'), hasLength(1));
    });

    test('a guest\'s votes are read with member_id; mine without', () async {
      api.routes['GET /v1/groups/g1/tallies'] = (q, _) {
        final who = q?['member_id'];
        return {
          'tallies': <String, dynamic>{},
          'mine': {who == 'm2' ? 'Qguest' : 'Qme': 'want'},
        };
      };
      var c = await repo.loadVotes(crew(), 'm2');
      c = await repo.loadVotes(c, 'm1');
      expect(c.votes, {
        'm2': {'Qguest': Vote.want},
        'm1': {'Qme': Vote.want},
      });
      expect(
        [for (final x in api.calls('GET', '/v1/groups/g1/tallies')) x.query],
        [
          {'member_id': 'm2'},
          null,
        ],
      );
    });
  });

  group('nights', () {
    final slot = DateTime.utc(2026, 10, 3, 14);

    test('create sends the films, the slots in UTC with milliseconds, the offset and a clean place', () async {
      api.routes['POST /v1/groups/g1/nights'] = (_, _) => nightJson(mine: []);
      final c = await repo.createNight(
        crew(),
        NightCreate(films: [film('Q1'), film('Q2')], slots: [slot], tzOffsetMin: 330, place: '  '),
      );
      final body = api.calls('POST', '/v1/groups/g1/nights').single.body as Map;
      expect(body.keys, {'films', 'slots', 'tz_offset_min', 'place'});
      expect(body['slots'], ['2026-10-03T14:00:00.000Z']);
      expect(body['place'], isNull);
      expect(body['tz_offset_min'], 330);
      expect([for (final f in body['films']) f['film_id']], ['Q1', 'Q2']);
      expect(c.nights.single.status, NightStatus.poll);
      expect(c.nights.single.hostId, 'm1');
    });

    test('vote: my votes go without a member id, a guest\'s with it; the counts come back', () async {
      var c = crew(nights: [Night.fromJson(nightJson(), mineFor: 'm1')]);
      api.routes['PUT /v1/nights/n1/votes'] = (_, _) => {
        'approvals': {'o1': 2, 'o3': 1},
      };
      c = await repo.vote(c, 'n1', 'm1', {'o1', 'o3'});
      c = await repo.vote(c, 'n1', 'm2', {'o1'});
      final bodies = [for (final x in api.calls('PUT', '/v1/nights/n1/votes')) x.body as Map];
      expect(bodies[0]['member_id'], isNull);
      expect(bodies[1]['member_id'], 'm2');
      expect(bodies[0]['option_ids'], unorderedEquals(['o1', 'o3']));
      final n = c.nights.single;
      expect(
        {for (final o in n.options) o.id: o.approvals},
        {'o1': 2, 'o2': 0, 'o3': 1},
        reason: 'an option the server leaves out has none',
      );
      expect(n.votes, {
        'm1': {'o1', 'o3'},
        'm2': {'o1'},
      });
      expect(((await thrown(() => repo.vote(c, 'missing', 'm1', {}))) as CrewRefused).status, 404);
    });

    test('close sends the chosen options and a clean place and keeps the votes read earlier', () async {
      final start = crew(nights: [Night.fromJson(nightJson(), mineFor: 'm2')]);
      api.routes['POST /v1/nights/n1/close'] = (_, _) => nightJson(status: 'set', mine: ['o1']);
      final c = await repo.closePoll(start, 'n1', filmOptionId: 'o2', place: ' Home ');
      expect(api.calls('POST', '/v1/nights/n1/close').single.body, {
        'film_option_id': 'o2',
        'slot_option_id': null,
        'place': 'Home',
      });
      expect(c.nights.single.status, NightStatus.set);
      expect(c.nights.single.event!.film.id, 'Q1');
      expect(c.nights.single.votes.keys, {'m2', 'm1'}, reason: 'the guest\'s votes stay');
    });

    test('rsvp, delete, wrap-up and a guest\'s votes hit the right paths', () async {
      var c = crew(
        nights: [Night.fromJson(nightJson(status: 'set'), mineFor: 'm1')],
      );
      api.routes['PUT /v1/nights/n1/rsvp'] = (_, _) => null;
      c = await repo.rsvp(c, 'n1', 'm1', Rsvp.yes);
      c = await repo.rsvp(c, 'n1', 'm2', Rsvp.maybe);
      expect(
        [for (final x in api.calls('PUT', '/v1/nights/n1/rsvp')) x.body],
        [
          {'response': 'yes', 'member_id': null},
          {'response': 'maybe', 'member_id': 'm2'},
        ],
      );
      expect(c.nights.single.rsvps, {'m1': Rsvp.yes, 'm2': Rsvp.maybe});

      api.routes['GET /v1/nights/n1'] = (q, _) => nightJson(status: 'set', mine: [if (q?['member_id'] == 'm2') 'o2']);
      c = await repo.loadNightVotes(c, 'n1', 'm2');
      expect(api.calls('GET', '/v1/nights/n1').single.query, {'member_id': 'm2'});
      expect(c.nights.single.votes['m2'], {'o2'});
      expect(c.nights.single.votes['m1'], isEmpty, reason: 'the earlier votes of m1 are kept');

      api.routes['POST /v1/nights/n1/wrapup'] = (_, _) => {'created': 2, 'skipped': 1};
      c = await repo.wrapUp(c, 'n1', seatRow: 'C', firstSeat: 4);
      expect(api.calls('POST', '/v1/nights/n1/wrapup').single.body, {
        'seat_row': 'C',
        'first_seat': 4,
        'member_ids': null,
      });
      expect(c.nights.single.status, NightStatus.done);
      await repo.wrapUp(c, 'n1');
      expect(api.calls('POST', '/v1/nights/n1/wrapup').last.body, {
        'seat_row': null,
        'first_seat': null,
        'member_ids': null,
      });

      api.routes['DELETE /v1/nights/n1'] = (_, _) => null;
      expect((await repo.deleteNight(c, 'n1')).nights, isEmpty);
    });
  });

  group('chat and sending', () {
    test('messages: the latest page, then after the last id, or before the first', () async {
      api.routes['GET /v1/groups/g1/messages'] = (_, _) => {
        'items': [
          {
            'id': 5,
            'kind': 'text',
            'sender': {'id': 'u1', 'handle': 'asha', 'display_name': 'Asha', 'avatar_color': 4},
            'body': 'hi',
            'code': null,
            'args': null,
            'film_id': null,
            'film': null,
            'night_id': null,
            'created_at': '2026-10-01T12:00:00.000Z',
          },
        ],
        'has_more': true,
      };
      final page = await repo.messages('g1');
      expect(
        (page.hasMore, page.items.single.id, page.items.single.sender!.name, page.items.single.sender!.ink),
        (true, 5, 'Asha', 4),
      );
      await repo.messages('g1', after: 5, limit: 20);
      await repo.messages('g1', before: 5);
      expect(
        [for (final x in api.calls('GET', '/v1/groups/g1/messages')) x.query],
        [
          {'limit': '50'},
          {'after': '5', 'limit': '20'},
          {'before': '5', 'limit': '50'},
        ],
      );
    });

    test('send, report and send-a-film bodies', () async {
      api.routes['POST /v1/groups/g1/messages'] = (_, b) => {
        'id': 6,
        'kind': 'text',
        'sender': null,
        'body': (b as Map)['body'],
        'code': null,
        'args': null,
        'film_id': b['film_id'],
        'film': b['film'],
        'night_id': b['night_id'],
        'created_at': '2026-10-01T12:00:01.000Z',
      };
      final m = await repo.sendMessage('g1', 'Watch this', film: film('Q3'), nightId: 'n1');
      expect((m.id, m.film!.id, m.nightId), (6, 'Q3', 'n1'));
      expect((api.calls('POST', '/v1/groups/g1/messages').single.body as Map).keys, {
        'body',
        'film_id',
        'film',
        'night_id',
      });

      api.routes['POST /v1/reports'] = (_, _) => {'id': 'r1'};
      await repo.report('message', '6', 'spam', note: '  ');
      expect(api.calls('POST', '/v1/reports').single.body, {
        'kind': 'message',
        'target_id': '6',
        'reason': 'spam',
        'note': null,
      });

      api.routes['POST /v1/films/send'] = (_, _) => <String, dynamic>{};
      await repo.sendFilm('u1', film('Q3'), note: ' hi ');
      final body = api.calls('POST', '/v1/films/send').single.body as Map;
      expect((body['user_id'], body['film_id'], body['note']), ('u1', 'Q3', 'hi'));
    });

    test('join: by code, then the group with members and nights', () async {
      api.routes['POST /v1/groups/join'] = (_, _) => groupJson('g7');
      api.routes['GET /v1/groups/g7'] = (_, _) =>
          groupJson('g7', members: [memberJson('m1', 'Me', me: true), memberJson('m2', 'Asha', owner: true)]);
      api.routes['GET /v1/groups/g7/nights'] = (_, _) => {'items': <dynamic>[]};
      final c = await repo.join('ABCD2345');
      expect(api.calls('POST', '/v1/groups/join').single.body, {'code': 'ABCD2345'});
      expect((c.id, c.members.length, c.isOwner), ('g7', 2, false));
    });
  });
}
