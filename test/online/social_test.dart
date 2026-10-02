import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/social.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/social.dart';

import '../support/device.dart';
import '../support/fake_api.dart';

class _Status extends BackendNotifier {
  _Status(this.status);
  final Backend status;
  @override
  Backend build() => status;
}

class Who extends SessionNotifier {
  Who(this.session);
  final Session? session;
  @override
  Session? build() => session;
  void set(Session? s) => state = s;
}

Map<String, dynamic> card(String id, {String? handle, String? name, int color = 0}) => {
  'id': id,
  'handle': handle,
  'display_name': name,
  'avatar_color': color,
};

Map<String, dynamic> film(String id, [String title = 'Film']) => {'id': id, 't': title, 'y': 2020};

const meJson = {
  'id': 'u1',
  'handle': 'me',
  'display_name': 'Me',
  'avatar_color': 3,
  'visibility': 'private',
  'share_ratings': false,
};

/// Controllers against a fake [Api], with the user online (server up, signed in) unless said otherwise.
class Env {
  Env({Backend status = Backend.up, Session? session = const Session('u1', Me(id: 'u1', handle: 'me'))}) {
    dir = Directory.systemTemp.createTempSync('talkies_social');
    addTearDown(() => dir.deleteSync(recursive: true));
    who = Who(session);
    c = ProviderContainer.test(
      overrides: [
        apiUrlProvider.overrideWithValue('https://talkies.test'),
        docsDirProvider.overrideWithValue(dir),
        backendProvider.overrideWith(() => _Status(status)),
        sessionProvider.overrideWith(() => who),
        apiProvider.overrideWithValue(api),
        nowProvider.overrideWithValue(clock.call),
      ],
    );
  }

  final api = FakeApi();
  final clock = Clock(DateTime(2026, 10, 1, 12));
  late final Directory dir;
  late final Who who;
  late final ProviderContainer c;
}

void main() {
  group('me', () {
    test('shows the cached profile at once, then the server\'s', () async {
      final e = Env();
      expect(e.c.read(meProvider).value!.handle, 'me');
      expect(e.c.read(meProvider).status, Fetch.ready);
      e.api.routes['GET /v1/me'] = (_, _) => {...meJson, 'display_name': 'Asha'};
      await e.c.read(meProvider.notifier).load();
      expect(e.c.read(meProvider).value!.displayName, 'Asha');
      expect(e.c.read(sessionProvider)!.me!.displayName, 'Asha'); // cached for the next start
    });

    test('a failed load keeps the old value and says offline or failed', () async {
      final e = Env();
      e.api.routes['GET /v1/me'] = (_, _) => throw const ApiOffline();
      await e.c.read(meProvider.notifier).load();
      expect(e.c.read(meProvider).status, Fetch.offline);
      expect(e.c.read(meProvider).value!.handle, 'me');
      e.api.routes['GET /v1/me'] = (_, _) => throw const ApiError(500, 'boom', '');
      await e.c.read(meProvider.notifier).load();
      expect(e.c.read(meProvider).status, Fetch.failed);
      e.api.routes['GET /v1/me'] = (_, _) => {'garbage': true}; // a reply that does not parse
      await e.c.read(meProvider.notifier).load();
      expect(e.c.read(meProvider).status, Fetch.failed);
    });

    test('patch sends what is set, clears with the flags, and reports a taken handle', () async {
      final e = Env();
      e.api.routes['PATCH /v1/me'] = (_, b) => {...meJson, ...(b as Map<String, dynamic>)};
      final me = e.c.read(meProvider.notifier);
      var r = await me.patch(
        const MePatch(displayName: 'Asha', visibility: ProfileVisibility.friends, shareRatings: true),
      );
      expect(r.ok, isTrue);
      expect(e.api.bodies.last, {'display_name': 'Asha', 'visibility': 'friends', 'share_ratings': true});
      expect(e.c.read(meProvider).value!.visibility, ProfileVisibility.friends);
      expect(e.c.read(sessionProvider)!.me!.shareRatings, isTrue);

      await me.patch(const MePatch(clearHandle: true, clearDisplayName: true));
      expect(e.api.bodies.last, {'handle': null, 'display_name': null});

      e.api.routes['PATCH /v1/me'] = (_, _) => throw const ApiError(409, 'handle_taken', 'taken');
      r = await me.patch(const MePatch(handle: 'asha'));
      expect([r.outcome, r.code], [CallOutcome.conflict, 'handle_taken']);
      expect(e.c.read(meProvider).value!.handle, isNull); // unchanged by the failure
    });
  });

  group('friends', () {
    test('lists and requests load, with the match', () async {
      final e = Env();
      e.api.routes['GET /v1/friends'] = (_, _) => {
        'items': [
          {
            'card': card('u2', handle: 'asha', name: 'Asha'),
            'visible': true,
            'match': {'both': 4, 'pct': 62},
          },
          {'card': card('u3', handle: 'ravi'), 'visible': false, 'match': null},
        ],
      };
      e.api.routes['GET /v1/friends/requests'] = (_, _) => {
        'incoming': [card('u4', handle: 'kiran')],
        'outgoing': <Object>[],
      };
      await e.c.read(friendsProvider.notifier).refresh();
      final s = e.c.read(friendsProvider);
      expect(s.friends.status, Fetch.ready);
      expect(s.friends.value!.map((f) => [f.card.handle, f.visible, f.match?.pct]), [
        ['asha', true, 62],
        ['ravi', false, null],
      ]);
      expect(s.requests.value!.incoming.single.handle, 'kiran');
    });

    test('lookup trims the @ and lowercases, and tells found, unknown and limited apart', () async {
      final e = Env();
      e.api.routes['GET /v1/users/lookup'] = (q, _) => q!['handle'] == 'asha_k'
          ? {'card': card('u2', handle: 'asha_k'), 'relation': 'none'}
          : throw const ApiError(404, 'not_found', '');
      final f = e.c.read(friendsProvider.notifier);
      var r = await f.lookup('  @Asha_K ');
      expect(r.value!.card.id, 'u2');
      expect(r.value!.relation, Relation.none);
      expect(e.api.queries.last, {'handle': 'asha_k'});
      r = await f.lookup('nobody');
      expect(r.outcome, CallOutcome.notFound);
      e.api.routes['GET /v1/users/lookup'] = (_, _) => throw const ApiError(429, 'rate_limited', '');
      expect((await f.lookup('asha_k')).outcome, CallOutcome.rateLimited);
    });

    test('send, accept, decline and remove call the right paths and refresh the lists', () async {
      final e = Env();
      e.api.routes['GET /v1/friends'] = (_, _) => {'items': <Object>[]};
      e.api.routes['GET /v1/friends/requests'] = (_, _) => {'incoming': <Object>[], 'outgoing': <Object>[]};
      e.api.routes['POST /v1/friends/requests'] = (_, b) => {
        'status': (b as Map)['user_id'] == 'mutual' ? 'friends' : 'pending',
      };
      e.api.routes['POST /v1/friends/requests/u2/accept'] = (_, _) => null;
      e.api.routes['DELETE /v1/friends/requests/u2'] = (_, _) => null;
      e.api.routes['DELETE /v1/friends/u2'] = (_, _) => null;
      final f = e.c.read(friendsProvider.notifier);

      var r = await f.send('u5');
      expect(r.value!.status, RequestStatus.pending);
      expect(e.api.bodies[0], {'user_id': 'u5'});
      await pumpEventQueue();
      expect(e.api.count('GET /v1/friends/requests'), 1);
      expect(e.api.count('GET /v1/friends'), 0);

      r = await f.send('mutual'); // they asked first: now friends, and the friend list changes
      expect(r.value!.status, RequestStatus.friends);
      await pumpEventQueue();
      expect(e.api.count('GET /v1/friends'), 1);

      expect((await f.accept('u2')).ok, isTrue);
      expect((await f.decline('u2')).ok, isTrue);
      expect((await f.remove('u2')).ok, isTrue);
      await pumpEventQueue();
      expect(
        e.api.calls,
        containsAll(['POST /v1/friends/requests/u2/accept', 'DELETE /v1/friends/requests/u2', 'DELETE /v1/friends/u2']),
      );

      e.api.routes['POST /v1/friends/requests'] = (_, _) => throw const ApiError(409, 'already_pending', '');
      final dup = await f.send('u5');
      expect([dup.outcome, dup.code], [CallOutcome.conflict, 'already_pending']);
      e.api.routes['DELETE /v1/friends/u2'] = (_, _) => throw const ApiOffline();
      expect((await f.remove('u2')).outcome, CallOutcome.offline);
    });
  });

  group('profiles', () {
    test('a profile loads, a hidden one fails with its last value kept', () async {
      final e = Env();
      e.api.routes['GET /v1/users/u2'] = (_, _) => {
        'card': card('u2', handle: 'asha'),
        'relation': 'friend',
        'visible': true,
        'match': {'both': 1, 'pct': 30},
        'stats': {
          'films': 3,
          'viewings': 4,
          'avg_rating': 4.5,
          'top_genres': ['drama'],
          'top_langs': ['hi'],
        },
        'top_films': [
          {'film_id': 'Q1', 'film': film('Q1', 'Sholay'), 'rating': 5.0},
        ],
        'watchlist': [
          {'film_id': 'Q2', 'film': film('Q2')},
        ],
      };
      final p = e.c.read(profileProvider('u2').notifier);
      await p.load();
      final v = e.c.read(profileProvider('u2')).value!;
      expect(v.stats!.avgRating, 4.5);
      expect(v.topFilms.single.film.title, 'Sholay');
      expect(v.match!.pct, 30);
      e.api.routes['GET /v1/users/u2'] = (_, _) => throw const ApiError(404, 'not_found', '');
      await p.load();
      expect(e.c.read(profileProvider('u2')).status, Fetch.failed);
      expect(e.c.read(profileProvider('u2')).value, isNotNull);
      expect(e.c.read(profileProvider('u3')).status, Fetch.idle); // another person, another state
    });

    test('a shelf pages by cursor, and a failed page leaves the list alone', () async {
      final e = Env();
      Map<String, dynamic> item(String id) => {'film_id': id, 'film': film(id), 'rating': null, 'viewings': 1};
      e.api.routes['GET /v1/users/u2/films'] = (q, _) => q == null || q.isEmpty
          ? {
              'items': [item('Q1'), item('Q2')],
              'next_cursor': 'c1',
            }
          : {
              'items': [item('Q3')],
              'next_cursor': null,
            };
      final s = e.c.read(shelfProvider('u2').notifier);
      await s.more(); // nothing loaded yet: nothing to page
      expect(e.api.calls, isEmpty);
      await s.load();
      expect(e.c.read(shelfProvider('u2')).items.map((i) => i.filmId), ['Q1', 'Q2']);
      expect(e.c.read(shelfProvider('u2')).next, 'c1');
      await s.more();
      expect(e.api.queries.last, {'cursor': 'c1'});
      expect(e.c.read(shelfProvider('u2')).items.map((i) => i.filmId), ['Q1', 'Q2', 'Q3']);
      expect(e.c.read(shelfProvider('u2')).next, isNull);
      await s.more(); // the end
      expect(e.api.count('GET /v1/users/u2/films'), 2);
    });

    test('a failed second page keeps the cursor for another try', () async {
      final e = Env();
      var fail = true;
      e.api.routes['GET /v1/users/u2/films'] = (q, _) {
        if (q == null || q.isEmpty) {
          return {'items': <Object>[], 'next_cursor': 'c1'};
        }
        if (fail) throw const ApiOffline();
        return {'items': <Object>[], 'next_cursor': null};
      };
      final s = e.c.read(shelfProvider('u2').notifier);
      await s.load();
      await s.more();
      expect(e.c.read(shelfProvider('u2')).next, 'c1');
      expect(e.c.read(shelfProvider('u2')).loadingMore, isFalse);
      fail = false;
      await s.more();
      expect(e.c.read(shelfProvider('u2')).next, isNull);
    });
  });

  group('friends who watched', () {
    Env env() {
      final e = Env();
      e.api.routes['GET /v1/films/Q1/friends'] = (_, _) => {
        'items': [
          {'user': card('u2', handle: 'asha'), 'rating': 4.0},
          {'user': card('u3', handle: 'ravi'), 'rating': null},
        ],
      };
      return e;
    }

    test('a film is asked about once; the answer is cached for 10 minutes', () async {
      final e = env();
      final w = e.c.read(friendsWhoWatchedProvider.notifier);
      await w.ensure('Q1');
      await w.ensure('Q1');
      expect(e.api.count('GET /v1/films/Q1/friends'), 1);
      expect(e.c.read(friendsWhoWatchedProvider)['Q1']!.map((x) => x.user.handle), ['asha', 'ravi']);
      e.clock.advance(const Duration(minutes: 11));
      await w.ensure('Q1');
      expect(e.api.count('GET /v1/films/Q1/friends'), 2);
    });

    test('custom films are skipped, failures are silent and wait a minute', () async {
      final e = env();
      final w = e.c.read(friendsWhoWatchedProvider.notifier);
      await w.ensure('my:1');
      await w.ensure('my:abc.2');
      expect(e.api.calls, isEmpty);
      e.api.routes['GET /v1/films/Q9/friends'] = (_, _) => throw const ApiOffline();
      await w.ensure('Q9');
      await w.ensure('Q9');
      expect(e.api.count('GET /v1/films/Q9/friends'), 1);
      expect(e.c.read(friendsWhoWatchedProvider).containsKey('Q9'), isFalse);
      e.clock.advance(const Duration(seconds: 61));
      await w.ensure('Q9');
      expect(e.api.count('GET /v1/films/Q9/friends'), 2);
    });

    test('nothing is asked when the user is not online, and another account starts empty', () async {
      final down = Env(status: Backend.down);
      await down.c.read(friendsWhoWatchedProvider.notifier).ensure('Q1');
      expect(down.api.calls, isEmpty);

      final e = env();
      await e.c.read(friendsWhoWatchedProvider.notifier).ensure('Q1');
      expect(e.c.read(friendsWhoWatchedProvider), isNotEmpty);
      e.who.set(const Session('u9'));
      expect(e.c.read(friendsWhoWatchedProvider), isEmpty);
    });
  });

  group('feed', () {
    Map<String, dynamic> item(
      String id, {
      String kind = 'watched',
      String user = 'u2',
      String filmId = 'Q1',
      int? mine,
    }) => {
      'id': id,
      'kind': kind,
      'user': card(user, handle: 'asha'),
      'film_id': filmId,
      'film': film(filmId, 'Sholay'),
      'rating': null,
      'reaction': null,
      'note': null,
      'my_reaction': mine,
    };

    Env env() {
      final e = Env();
      e.api.routes['GET /v1/feed'] = (q, _) => q == null || q.isEmpty
          ? {
              'items': [item('w:5'), item('r:4', kind: 'reaction'), item('w:3', filmId: 'Q2')],
              'next_cursor': 'cur',
            }
          : {
              'items': [item('w:1', filmId: 'Q3')],
              'next_cursor': null,
            };
      return e;
    }

    test('pages by cursor and stops at the end', () async {
      final e = env();
      final f = e.c.read(feedProvider.notifier);
      await f.load();
      expect(e.c.read(feedProvider).items.map((i) => i.id), ['w:5', 'r:4', 'w:3']);
      await f.more();
      expect(e.api.queries.last, {'cursor': 'cur'});
      expect(e.c.read(feedProvider).items.map((i) => i.id), ['w:5', 'r:4', 'w:3', 'w:1']);
      await f.more();
      expect(e.api.count('GET /v1/feed'), 2);
      expect(e.c.read(feedProvider).status, Fetch.ready);
    });

    test('a reaction shows at once and is taken back if the server says no', () async {
      final e = env();
      final f = e.c.read(feedProvider.notifier);
      await f.load();
      int? during;
      e.api.routes['PUT /v1/reactions'] = (_, _) {
        during = e.c.read(feedProvider).items.first.myReaction;
        return null;
      };
      final first = e.c.read(feedProvider).items.first;
      var r = await f.react(first, 3);
      expect(r.ok, isTrue);
      expect(during, 3);
      expect(e.api.bodies.last, {'user_id': 'u2', 'film_id': 'Q1', 'reaction': 3});
      expect(e.c.read(feedProvider).items.first.myReaction, 3);

      r = await f.react(e.c.read(feedProvider).items.first, null); // clears
      expect(e.api.bodies.last, {'user_id': 'u2', 'film_id': 'Q1', 'reaction': null});
      expect(e.c.read(feedProvider).items.first.myReaction, isNull);

      e.api.routes['PUT /v1/reactions'] = (_, _) => throw const ApiOffline();
      r = await f.react(e.c.read(feedProvider).items.first, 5);
      expect(r.outcome, CallOutcome.offline);
      expect(e.c.read(feedProvider).items.first.myReaction, isNull); // taken back
    });

    test('only watched items take a reaction, and only 0 to 7', () async {
      final e = env();
      final f = e.c.read(feedProvider.notifier);
      await f.load();
      final items = e.c.read(feedProvider).items;
      expect((await f.react(items[1], 2)).outcome, CallOutcome.invalid); // a reaction item
      expect((await f.react(items[0], 8)).outcome, CallOutcome.invalid);
      expect((await f.react(items[0], -1)).outcome, CallOutcome.invalid);
      expect(e.api.calls.where((c) => c.startsWith('PUT')), isEmpty);
    });

    test('add to my watchlist adds once; hide drops an item for good', () async {
      final e = env();
      final f = e.c.read(feedProvider.notifier);
      await f.load();
      final first = e.c.read(feedProvider).items.first;
      expect(f.addToWatchlist(first), isTrue);
      expect(f.addToWatchlist(first), isFalse); // not toggled off
      expect(e.c.read(diaryProvider).wishes.map((w) => w.filmId), ['Q1']);
      expect(e.c.read(diaryProvider).films['Q1']!.title, 'Sholay');

      f.hide(first);
      expect(e.c.read(feedProvider).items.map((i) => i.id), ['r:4', 'w:3']);
      await f.load(); // the server sends it again; it stays hidden
      expect(e.c.read(feedProvider).items.map((i) => i.id), ['r:4', 'w:3']);
    });

    test('a failed load keeps the list; a new account starts empty', () async {
      final e = env();
      final f = e.c.read(feedProvider.notifier);
      await f.load();
      e.api.routes['GET /v1/feed'] = (_, _) => throw const ApiOffline();
      await f.load();
      expect(e.c.read(feedProvider).status, Fetch.offline);
      expect(e.c.read(feedProvider).items, hasLength(3));
      e.who.set(const Session('u9'));
      expect(e.c.read(feedProvider).items, isEmpty);
      expect(e.c.read(feedProvider).status, Fetch.idle);
    });
  });

  group('blocks and reports', () {
    test('blocking resets the friend list and the feed, and reloads the block list', () async {
      final e = Env();
      e.api.routes['GET /v1/friends'] = (_, _) => {'items': <Object>[]};
      e.api.routes['GET /v1/blocks'] = (_, _) => {
        'items': [card('u7', handle: 'spam')],
      };
      e.api.routes['POST /v1/blocks'] = (_, _) => null;
      e.api.routes['DELETE /v1/blocks/u7'] = (_, _) => null;
      await e.c.read(friendsProvider.notifier).loadFriends();
      expect(e.c.read(friendsProvider).friends.status, Fetch.ready);

      final b = e.c.read(blocksProvider.notifier);
      expect((await b.block('u7')).ok, isTrue);
      expect(e.api.bodies[e.api.calls.indexOf('POST /v1/blocks')], {'user_id': 'u7'});
      await pumpEventQueue();
      expect(e.c.read(friendsProvider).friends.status, Fetch.idle);
      expect(e.c.read(blocksProvider).value!.single.handle, 'spam');

      expect((await b.unblock('u7')).ok, isTrue);
      await pumpEventQueue();
      expect(e.api.count('GET /v1/blocks'), 2);
    });

    test('a report goes out with its fields and says how it went', () async {
      final e = Env();
      e.api.routes['POST /v1/reports'] = (_, _) => {'id': 'r1'};
      final r = await e.c
          .read(reportProvider.notifier)
          .submit(const ReportPost(kind: ReportKind.message, targetId: '42', reason: ReportReason.abuse, note: 'rude'));
      expect(r.value!.id, 'r1');
      expect(e.api.bodies.last, {'kind': 'message', 'target_id': '42', 'reason': 'abuse', 'note': 'rude'});
      expect(e.c.read(reportProvider), Fetch.idle);

      e.api.routes['POST /v1/reports'] = (_, _) => throw const ApiError(429, 'rate_limited', '');
      final limited = await e.c
          .read(reportProvider.notifier)
          .submit(const ReportPost(kind: ReportKind.user, targetId: 'u7', reason: ReportReason.spam));
      expect(limited.outcome, CallOutcome.rateLimited);
    });
  });

  group('not online', () {
    test('every controller answers offline and calls nothing while the server is down', () async {
      final e = Env(status: Backend.down);
      await e.c.read(friendsProvider.notifier).refresh();
      await e.c.read(feedProvider.notifier).load();
      await e.c.read(meProvider.notifier).load();
      await e.c.read(profileProvider('u2').notifier).load();
      expect(e.c.read(friendsProvider).friends.status, Fetch.offline);
      expect(e.c.read(feedProvider).status, Fetch.offline);
      expect((await e.c.read(friendsProvider.notifier).send('u2')).outcome, CallOutcome.offline);
      expect((await e.c.read(blocksProvider.notifier).block('u2')).outcome, CallOutcome.offline);
      expect(e.api.calls, isEmpty);
    });

    test('a reply that does not parse is a failure, never an exception', () async {
      final e = Env();
      e.api.routes['GET /v1/friends'] = (_, _) => 'not json';
      await e.c.read(friendsProvider.notifier).loadFriends();
      expect(e.c.read(friendsProvider).friends.status, Fetch.failed);
    });
  });

  group('ProfileView.fromDiary', () {
    final cat = testCatalog();
    Stub st(String id, String film, {double? rating, int day = 2, bool private = false}) => Stub(
      id: id,
      no: 1,
      filmId: film,
      created: DateTime(2026, 1, 1),
      date: DateTime(2026, 1, day),
      rating: rating,
      private: private,
    );

    Diary diary({List<Stub>? stubs, List<Wish>? wishes}) => Diary(
      films: {
        for (final f in cat.items) f.id: f,
        'my:1': const Film(id: 'my:1', title: 'Own'),
      },
      stubs: stubs ?? const [],
      wishes: wishes ?? const [],
    );

    test('top films by rating, then viewings, then the latest watch; ten at most', () {
      final d = diary(
        stubs: [
          st('a', 'Q1', rating: 5),
          st('b', 'Q2', rating: 5, day: 3),
          st('c', 'Q2', rating: 4, day: 4),
          st('d', 'Q3', rating: 4.5),
          st('e', 'Q4', rating: 3),
          st('f', 'Q5', day: 9), // no rating
        ],
      );
      final v = ProfileView.fromDiary(d, cat);
      expect(v.topFilms.map((f) => f.filmId), ['Q2', 'Q1', 'Q3', 'Q4', 'Q5']);
      expect(v.topFilms.map((f) => f.rating), [5.0, 5.0, 4.5, 3.0, null]);
      expect(v.relation, Relation.self);
      expect(v.stats!.films, 5);
      expect(v.stats!.viewings, 6);
      expect(v.stats!.avgRating, closeTo((5 + 5 + 4 + 4.5 + 3) / 5, 1e-9));
      expect(v.stats!.topGenres.length, lessThanOrEqualTo(3));
      expect(v.stats!.topLangs, ['hi', 'kn']);
    });

    test('without ratings: by viewings, and no rating anywhere', () {
      final d = diary(stubs: [st('a', 'Q1', rating: 5), st('b', 'Q2', rating: 1), st('c', 'Q2', rating: 1, day: 5)]);
      final v = ProfileView.fromDiary(d, cat, ratings: false);
      expect(v.topFilms.map((f) => f.filmId), ['Q2', 'Q1']);
      expect(v.topFilms.every((f) => f.rating == null), isTrue);
      expect(v.stats!.avgRating, isNull);
    });

    test('rewatches do not break a rating tie: the most recent watch wins', () {
      // Q2 has more viewings, but its last watch is older than Q1's: with
      // ratings shown the server reads the rating, then the last watch.
      final d = diary(
        stubs: [st('a', 'Q1', rating: 5, day: 5), st('b', 'Q2', rating: 5, day: 2), st('c', 'Q2', rating: 4, day: 1)],
      );
      expect(ProfileView.fromDiary(d, cat).topFilms.map((f) => f.filmId), ['Q1', 'Q2']);
      // Without ratings the viewings still decide.
      expect(ProfileView.fromDiary(d, cat, ratings: false).topFilms.map((f) => f.filmId), ['Q2', 'Q1']);
    });

    test('genres and languages count each film once, not each viewing', () {
      // Three viewings of a romance cannot outrank two action films.
      final romance = ProfileView.fromDiary(
        diary(
          stubs: [
            st('a', 'Q1'),
            st('b', 'Q3'),
            st('c', 'Q4'),
            st('d', 'Q2'),
            st('e', 'Q2', day: 3),
            st('f', 'Q2', day: 4),
          ],
        ),
        cat,
      );
      expect(romance.stats!.topGenres, ['action', 'drama', 'romance']);
      // ... nor can three viewings of a Kannada film outrank two Hindi films.
      final kannada = ProfileView.fromDiary(
        diary(
          stubs: [
            st('a', 'Q1'),
            st('b', 'Q2'),
            st('c', 'Q3'),
            st('d', 'Q3', day: 3),
            st('e', 'Q3', day: 4),
            st('f', 'Q4'),
          ],
        ),
        cat,
      );
      expect(kannada.stats!.topLangs, ['hi', 'kn']);
    });

    test('private stubs and custom films count for nothing', () {
      final d = diary(
        stubs: [st('a', 'Q1', rating: 4), st('b', 'Q3', rating: 5, private: true), st('c', 'my:1', rating: 5)],
        wishes: [
          Wish(filmId: 'my:1', added: DateTime(2026, 2)),
          Wish(filmId: 'Q2', added: DateTime(2026, 2)),
        ],
      );
      final v = ProfileView.fromDiary(d, cat);
      expect(v.topFilms.map((f) => f.filmId), ['Q1']);
      expect(v.stats!.films, 1);
      expect(v.stats!.viewings, 1);
      expect(v.watchlist.map((w) => w.filmId), ['Q2']);
    });

    test('the watchlist shows the newest first, at most 50, and the card is the one given', () {
      final wishes = [
        for (var i = 0; i < 60; i++)
          Wish(
            filmId: 'Q${i + 100}',
            added: DateTime(2026, 1, 1).add(Duration(days: i)),
          ),
      ];
      final big = Diary(
        films: {for (var i = 0; i < 60; i++) 'Q${i + 100}': Film(id: 'Q${i + 100}', title: 'F$i')},
        wishes: wishes,
      );
      final v = ProfileView.fromDiary(
        big,
        cat,
        card: const UserCard(id: 'u1', handle: 'me', avatarColor: 4),
      );
      expect(v.watchlist, hasLength(50));
      expect(v.watchlist.first.filmId, 'Q159');
      expect(v.card.handle, 'me');
    });

    test('an empty diary gives an empty profile, and the JSON holds no diary date or private field', () {
      final empty = ProfileView.fromDiary(const Diary(), cat);
      expect(empty.topFilms, isEmpty);
      expect(empty.stats!.films, 0);
      expect(empty.stats!.avgRating, isNull);

      final d = diary(
        stubs: [
          Stub(
            id: 'a',
            no: 1,
            filmId: 'Q1',
            created: DateTime(2026, 1, 1),
            date: DateTime(2026, 1, 2),
            rating: 4,
            memo: 'secret memo',
            place: 'Regal',
            seat: 'A1',
            price: 300,
            company: 'Asha',
            tags: const ['x'],
          ),
        ],
        wishes: [Wish(filmId: 'Q2', added: DateTime(2026, 2), planned: DateTime(2026, 3))],
      );
      final json = ProfileView.fromDiary(d, cat).toJson();
      const forbidden = {
        'date',
        'created',
        'memo',
        'place',
        'seat',
        'price',
        'with',
        'tags',
        'no',
        'planned',
        'added',
        'priv',
      };
      void scan(Object? v) {
        if (v is Map) {
          for (final e in v.entries) {
            expect(forbidden.contains(e.key), isFalse, reason: '${e.key} in the profile');
            scan(e.value);
          }
        } else if (v is List) {
          v.forEach(scan);
        }
      }

      scan(json);
      expect(json.toString(), isNot(contains('secret memo')));
      // And the preview parses like a server reply.
      expect(ProfileView.fromJson(json).topFilms.single.film.title, 'Sholay');
    });
  });
}
