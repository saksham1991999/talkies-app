import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/data/models.dart';

// The shared examples of the groups, deck, night and chat models: the exact
// wire JSON in backend/tests/examples/<model>.<case>.json. The backend validates
// each file against its Pydantic model; this test parses the same files with the
// client. A model with no example passes (the file may not exist yet). An
// example the client cannot parse fails. A request model must encode back to the
// same JSON (a missing key and a null mean the same).

// EXAMPLES_DIR points the test at another folder of examples (to try it before the backend writes its own).
final dir = Directory(Platform.environment['EXAMPLES_DIR'] ?? 'backend/tests/examples');

Map<String, dynamic> obj(Object? j) => j as Map<String, dynamic>;

/// [j] without null values, keys sorted, and every film snapshot written the way the client writes it.
Object? canon(Object? j, [String? key]) {
  if (j is Map) {
    if (key == 'film') return canon(Film.fromJson(obj(j)).toJson());
    return {
      for (final k in (j.keys.cast<String>().toList()..sort()))
        if (j[k] != null) k: canon(j[k], k),
    };
  }
  if (j is List) return [for (final e in j) canon(e)];
  return j;
}

typedef Check = void Function(Map<String, dynamic> json);

/// A request: the client builds the body from the parsed values and must get the same JSON.
Check request(Map<String, dynamic> Function(Map<String, dynamic> j) encode) =>
    (j) => expect(canon(encode(j)), canon(j));

Film filmOf(Object? j) => Film.fromJson(obj(j));

final models = <String, Check>{
  // -- requests
  'group_create': request((j) => groupCreateBody(j['name'] as String)),
  'group_patch': request((j) => groupPatchBody(j['name'] as String)),
  'join_post': request((j) => joinPostBody(j['code'] as String)),
  'guest_post': request((j) => guestPostBody(j['name'] as String)),
  'group_film_put': request((j) => groupFilmPutBody(filmOf(j['film']))),
  'deck_put': request(
    (j) => deckPutBody(j['base_version'] as int, [
      for (final i in j['items'] as List) DeckCard(film: filmOf(obj(i)['film'])),
    ]),
  ),
  'swipes_put': request(
    (j) => swipesPutBody([
      for (final s in j['swipes'] as List)
        Swipe(
          memberId: obj(s)['member_id'] as String?,
          filmId: obj(s)['film_id'] as String,
          vote: Vote.values.byName(obj(s)['vote'] as String),
        ),
    ]),
  ),
  'night_create': request(
    (j) => NightCreate(
      films: [for (final f in j['films'] as List) filmOf(obj(f)['film'])],
      slots: [for (final s in j['slots'] as List) parseTime(s)],
      tzOffsetMin: j['tz_offset_min'] as int,
      place: j['place'] as String?,
    ).toJson(),
  ),
  'votes_put': request((j) => votesPutBody((j['option_ids'] as List).cast<String>(), j['member_id'] as String?)),
  'close_post': request(
    (j) => closePostBody(
      filmOptionId: j['film_option_id'] as String?,
      slotOptionId: j['slot_option_id'] as String?,
      place: j['place'] as String?,
    ),
  ),
  'rsvp_put': request((j) => rsvpPutBody(Rsvp.values.byName(j['response'] as String), j['member_id'] as String?)),
  'message_post': request(
    (j) => messagePostBody(
      j['body'] as String,
      film: j['film'] == null ? null : filmOf(j['film']),
      nightId: j['night_id'] as String?,
    ),
  ),
  'wrapup_post': request(
    (j) => wrapupPostBody(
      seatRow: j['seat_row'] as String?,
      firstSeat: j['first_seat'] as int?,
      memberIds: (j['member_ids'] as List?)?.cast<String>(),
    ),
  ),
  'send_film': request((j) => sendFilmBody(j['user_id'] as String, filmOf(j['film']), note: j['note'] as String?)),

  // -- replies
  'group': (j) {
    final c = Crew.fromJson(j);
    expect((c.id, c.name, c.inviteCode, c.deckVersion), (j['id'], j['name'], j['invite_code'], j['deck_version']));
    expect(c.inviteCode, matches(RegExp(r'^[A-HJ-KM-NP-Z2-9]{8}$')));
  },
  'group_list': (j) {
    final list = Crew.listFromJson(j);
    expect(list.map((c) => c.id), [for (final g in j['items'] as List) obj(g)['id']]);
  },
  'group_detail': (j) {
    final c = Crew.fromJson(j);
    expect(c.members.map((m) => m.id), [for (final m in j['members'] as List) obj(m)['id']]);
    expect(c.members.where((m) => m.me), hasLength(1), reason: 'exactly one member is me');
    final again = Crew.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
    expect(canon(again.toJson()), canon(c.toJson()));
  },
  'member': (j) {
    final m = Member.fromJson(j);
    expect(
      (m.id, m.name, m.ink, m.handle, m.guest, m.owner, m.me),
      (j['id'], j['name'], j['avatar_color'], j['handle'], j['guest'], j['owner'], j['me']),
    );
    expect(canon(m.toJson()), canon(j));
  },
  'invite_code': (j) {
    expect(parseInviteCode(j), j['invite_code']);
    expect(parseInviteCode(j), matches(RegExp(r'^[A-HJ-KM-NP-Z2-9]{8}$')));
  },
  'group_films': (j) {
    final items = WatchItem.listFromJson(j);
    expect(items.map((w) => w.filmId), [for (final i in j['items'] as List) obj(i)['film_id']]);
  },
  'deck': (j) {
    final d = Deck.fromJson(j);
    final items = j['items'] as List;
    expect(d.version, j['version']);
    expect(d.cards.map((c) => c.id), [for (final i in items) obj(i)['film_id']]);
    expect(d.cards.map((c) => c.seenBy), [for (final i in items) obj(i)['seen_by']]);
    expect(
      canon(Deck.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>).toJson()),
      canon(d.toJson()),
    );
  },
  'deck_put_result': (j) => expect(parseDeckPutResult(j), j['version']),
  'deck_inputs': (j) {
    final i = DeckInputs.fromJson(j);
    expect(i.tastes, hasLength((j['tastes'] as List).length), reason: 'every example taste must be a valid Taste');
    expect(i.seen, (j['seen'] as List).toSet());
    expect(i.wanted.map((w) => (w.film.id, w.n)), [
      for (final w in j['wanted'] as List) (obj(w)['film_id'], obj(w)['n']),
    ]);
  },
  'swipes_result': (j) => expect(parseSwipesResult(j), j['saved']),
  'tallies': (j) {
    final t = TalliesReply.fromJson(j);
    expect(t.tallies.keys.toSet(), obj(j['tallies']).keys.toSet());
    for (final e in obj(j['tallies']).entries) {
      final v = obj(e.value);
      expect(
        (t.tallies[e.key]!.want, t.tallies[e.key]!.skip, t.tallies[e.key]!.seen),
        (v['want'], v['skip'], v['seen']),
      );
    }
    expect(
      {for (final e in t.mine.entries) e.key: e.value.name},
      obj(j['mine']),
      reason: 'mine holds want, skip or seen',
    );
  },
  'night': (j) => checkNight(j),
  'night_list': (j) {
    final items = j['items'] as List;
    final nights = Night.listFromJson(j, mineFor: 'me');
    expect(nights.map((n) => n.id), [for (final n in items) obj(n)['id']]);
    for (final n in items) {
      checkNight(obj(n));
    }
  },
  'votes_result': (j) => expect(parseVotesResult(j), obj(j['approvals'])),
  'message': (j) => checkMessage(j),
  'message_list': (j) {
    final page = MessagePage.fromJson(j);
    expect(page.items.map((m) => m.id), [for (final m in j['items'] as List) obj(m)['id']]);
    expect(page.hasMore, j['has_more']);
    for (final m in j['items'] as List) {
      checkMessage(obj(m));
    }
  },
  'wrapup_result': (j) => expect(parseWrapupResult(j), (created: j['created'], skipped: j['skipped'])),
};

void checkNight(Map<String, dynamic> j) {
  final n = Night.fromJson(j, mineFor: 'me');
  expect(
    (n.id, n.crewId, n.status.name, n.hostId, n.tzOffsetMin, n.place),
    (j['id'], j['group_id'], j['status'], j['host_id'], j['tz_offset_min'], j['place']),
  );
  final options = j['options'] as List;
  expect(n.options.map((o) => (o.id, o.kind.name, o.position, o.approvals)), [
    for (final o in options) (obj(o)['id'], obj(o)['kind'], obj(o)['position'], obj(o)['approvals']),
  ]);
  for (final (i, o) in options.indexed) {
    final x = obj(o);
    expect(n.options[i].film?.id, x['film_id'], reason: 'film_id and film belong together');
    expect(n.options[i].startsAt, x['starts_at'] == null ? isNull : parseTime(x['starts_at']));
  }
  expect(n.votes['me'] ?? <String>{}, ((j['mine'] as List?) ?? const []).toSet());
  expect(n.event == null, j['event'] == null);
  if (n.event != null) {
    final e = obj(j['event']);
    expect(
      (n.event!.film.id, n.event!.startsAt, n.event!.tzOffsetMin, n.event!.place),
      (e['film_id'], parseTime(e['starts_at']), e['tz_offset_min'], e['place']),
    );
  }
  expect(
    {for (final e in n.rsvps.entries) e.key: e.value.name},
    {for (final r in j['rsvps'] as List) obj(r)['member_id']: obj(r)['response']},
  );
  // What this phone stores comes back the same.
  final again = Night.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>);
  expect(canon(again.toJson()), canon(n.toJson()));
}

void checkMessage(Map<String, dynamic> j) {
  final m = Message.fromJson(j);
  expect(
    (m.id, m.kind.name, m.body, m.code, m.nightId, m.filmId),
    (j['id'], j['kind'], j['body'], j['code'], j['night_id'], j['film_id']),
  );
  expect(m.createdAt, parseTime(j['created_at']));
  expect(m.sender?.id, j['sender'] == null ? isNull : obj(j['sender'])['id']);
  expect(m.args, j['args']);
  if (m.kind == MessageKind.text) {
    expect(m.body, isNotEmpty);
  } else {
    expect(m.code, isNotEmpty, reason: 'a system message has a code and args');
  }
}

void main() {
  final files = dir.existsSync()
      ? (dir.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  for (final entry in models.entries) {
    final mine = [
      for (final f in files)
        if (f.path.split('/').last.split('.').first == entry.key && f.path.endsWith('.json')) f,
    ];
    if (mine.isEmpty) {
      test('${entry.key}: no example yet', () {});
      continue;
    }
    for (final f in mine) {
      test('${entry.key}: ${f.path.split('/').last}', () {
        entry.value(obj(jsonDecode(f.readAsStringSync())));
      });
    }
  }

  test('the checks themselves catch a wrong example', () {
    // A guard for this file: a request that drops a key, or a reply with a wrong key, must fail.
    expect(() => models['join_post']!({'code': 'ABCD2345', 'extra': 1}), throwsA(isA<TestFailure>()));
    expect(() => models['night']!({'id': 'n'}), throwsA(anything));
    expect(
      () => models['deck_inputs']!({
        'tastes': [
          {'v': 1},
        ],
        'seen': [],
        'wanted': [],
      }),
      throwsA(isA<TestFailure>()),
    );
    models['rsvp_put']!({'response': 'yes', 'member_id': null});
    models['rsvp_put']!({'response': 'maybe', 'member_id': 'm2'});
    models['votes_put']!({
      'option_ids': ['a'],
      'member_id': null,
    });
    models['swipes_put']!({
      'swipes': [
        {'film_id': 'Q1', 'vote': 'want', 'member_id': null},
      ],
    });
    models['wrapup_post']!({'seat_row': null, 'first_seat': null, 'member_ids': null});
  });
}
