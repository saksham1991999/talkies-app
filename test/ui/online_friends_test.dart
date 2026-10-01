import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/social.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/online_widgets.dart';
import 'package:talkies/ui/profile_body.dart';
import 'package:talkies/ui/screens/friend_screen.dart';
import 'package:talkies/ui/screens/friends_screen.dart';
import 'package:talkies/ui/screens/profile_screen.dart';

import '../support/fake_api.dart';
import 'online_harness.dart';

final asha = cardJson(ashaId, 'Asha', handle: 'asha_k', ink: 3);

Phone online(FakeApi api, {Me? me}) => Phone(status: Backend.up, session: Session(meId, me ?? testMe()), api: api);

/// The body of the last call to [key] (a later GET has none, so `bodies.last` is not it).
Object? bodyOf(FakeApi api, String key) => api.bodies[api.calls.lastIndexOf(key)];

/// A window tall enough to build every row of the list.
const tall = Size(360, 4000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  group('Friends segment', () {
    Future<(Phone, FakeApi)> open(WidgetTester t, {FakeApi? api}) async {
      final a = api ?? socialApi();
      final phone = online(a);
      await phone.pump(t, const Scaffold(body: FriendsSegment()), size: tall);
      await t.pumpAndSettle();
      return (phone, a);
    }

    testWidgets('renders requests, a friend row with the match, and the feed', (t) async {
      await open(t);
      // Requests, both ways.
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Rohan'), findsOneWidget);
      expect(find.text('Wants to be your friend'), findsOneWidget);
      expect(find.text('Tara'), findsOneWidget);
      expect(find.text('Waiting for a reply'), findsOneWidget);
      // Friends: the match is a figure; a friend who keeps films private has none.
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('You both watched 12'), findsOneWidget);
      expect(find.text('74%'), findsOneWidget);
      expect(find.text('Kabir'), findsOneWidget);
      expect(find.text('Keeps films private'), findsOneWidget);
      // The feed: watched, sent (with its note) and a reaction to mine. No date anywhere.
      expect(find.text('What friends watched'), findsOneWidget);
      expect(find.text('Asha watched'), findsOneWidget);
      expect(find.text('Sholay'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('Asha sent you a film'), findsOneWidget);
      expect(find.text('Watch this with chai'), findsOneWidget);
      expect(find.text('Kabir reacted to your film'), findsOneWidget);
      expect(find.text('🔥'), findsWidgets);
      expect(find.textContaining(RegExp(r'\b(19|20)\d\d-\d\d-\d\d\b')), findsNothing);
    });

    testWidgets('only a watched film takes a reaction: eight, one tap each', (t) async {
      await open(t);
      expect(find.byKey(const Key('react-0')), findsOneWidget); // one watched item: one grid
      expect(find.byKey(const Key('react-7')), findsOneWidget);
    });

    testWidgets('Accept, Decline and Cancel go to the server and refresh the lists', (t) async {
      final (_, api) = await open(t);
      api.routes['POST /v1/friends/requests/$rohanId/accept'] = (_, _) => null;
      api.routes['DELETE /v1/friends/requests/$rohanId'] = (_, _) => null;
      api.routes['DELETE /v1/friends/requests/$taraId'] = (_, _) => null;
      await tapKey(t, 'accept-$rohanId');
      expect(api.count('POST /v1/friends/requests/$rohanId/accept'), 1);
      expect(api.count('GET /v1/friends/requests'), 2); // opened, then refreshed
      await tapKey(t, 'decline-$rohanId');
      expect(api.count('DELETE /v1/friends/requests/$rohanId'), 1);
      await tapKey(t, 'cancel-$taraId');
      expect(api.count('DELETE /v1/friends/requests/$taraId'), 1);
    });

    testWidgets('a reaction is one tap, shows as mine, and a second tap takes it back', (t) async {
      final (_, api) = await open(t);
      api.routes['PUT /v1/reactions'] = (_, _) => null;
      await tapKey(t, 'react-1');
      expect(api.bodies.last, {'user_id': ashaId, 'film_id': 'Q1', 'reaction': 1});
      await tapKey(t, 'react-1');
      expect(api.bodies.last, {'user_id': ashaId, 'film_id': 'Q1', 'reaction': null});
    });

    testWidgets('a reaction the server refuses is taken back, with a calm line', (t) async {
      final (_, api) = await open(t);
      api.routes['PUT /v1/reactions'] = (_, _) => throw const ApiError(500, 'oops', 'oops');
      await tapKey(t, 'react-2');
      expect(find.text('Could not send the reaction.'), findsOneWidget);
      api.routes['PUT /v1/reactions'] = (_, _) => null;
      await tapKey(t, 'react-2'); // not selected any more, so this sends 2 again, not null
      expect(api.bodies.last, {'user_id': ashaId, 'film_id': 'Q1', 'reaction': 2});
    });

    testWidgets('one tap puts the film on the watchlist', (t) async {
      final (phone, _) = await open(t);
      final key = const Key('want-w:30');
      expect(find.descendant(of: find.byKey(key), matching: find.text('Want to watch')), findsOneWidget);
      await t.ensureVisible(find.byKey(key));
      await t.pump();
      await t.tap(find.byKey(key));
      await t.pump();
      expect(phone.container(t).read(diaryProvider).wishFor('Q1'), isNotNull);
      expect(find.text('Added to watchlist'), findsOneWidget);
      expect(find.descendant(of: find.byKey(key), matching: find.text('In watchlist')), findsOneWidget);
    });

    testWidgets('paging: Show more asks for the next cursor and adds its items', (t) async {
      final api = socialApi(feedNext: 'p2');
      final phone = online(api);
      await phone.pump(t, const Scaffold(body: FriendsSegment()), size: tall);
      await t.pumpAndSettle();
      api.routes['GET /v1/feed'] = (q, _) => q?['cursor'] == 'p2'
          ? {
              'items': [feedItem('w:10', 'watched', asha, 'Q5')],
              'next_cursor': null,
            }
          : throw StateError('first page again');
      expect(find.text('Panchayat'), findsNothing);
      await tapKey(t, 'feed-more');
      expect(api.queries.last, {'cursor': 'p2'});
      expect(find.text('Panchayat'), findsOneWidget);
      expect(find.byKey(const Key('feed-more')), findsNothing); // the end
    });

    testWidgets('an empty feed and no friends say so, in one line each', (t) async {
      final api = socialApi(feed: const []);
      api.routes['GET /v1/friends'] = (_, _) => {'items': <Object>[]};
      api.routes['GET /v1/friends/requests'] = (_, _) => {'incoming': <Object>[], 'outgoing': <Object>[]};
      final phone = online(api);
      await phone.pump(t, const Scaffold(body: FriendsSegment()), size: tall);
      await t.pumpAndSettle();
      expect(find.text('Requests'), findsNothing);
      expect(find.text('No friends yet. Add a friend to see what they watch.'), findsOneWidget);
      expect(find.text('Nothing yet. When friends record a film, it shows here.'), findsOneWidget);
    });

    testWidgets('server away: Can\'t reach Talkies with Retry, and no call is made', (t) async {
      final api = socialApi();
      final phone = Phone(status: Backend.down, session: Session(meId, testMe()), api: api);
      api.routes['GET /healthz'] = (_, _) => throw const ApiOffline('down');
      await phone.pump(t, const Scaffold(body: FriendsSegment()));
      await t.pumpAndSettle();
      expect(find.textContaining("Can't reach Talkies"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(api.count('GET /v1/feed'), 0);
      expect(api.count('GET /v1/friends'), 0);
    });

    testWidgets('a failing friends call shows Can\'t reach in its own section', (t) async {
      final api = socialApi();
      api.routes['GET /v1/friends'] = (_, _) => throw const ApiOffline('down');
      final phone = online(api);
      await phone.pump(t, const Scaffold(body: FriendsSegment()), size: tall);
      await t.pumpAndSettle();
      expect(find.textContaining("Can't reach Talkies"), findsOneWidget);
      expect(find.text('What friends watched'), findsOneWidget);
    });

    testWidgets('a parent that scrolls gets a column that takes its height', (t) async {
      final api = socialApi();
      final phone = online(api);
      await phone.pump(
        t,
        Scaffold(body: ListView(children: const [FriendsSegment()])),
        size: tall,
      );
      await t.pumpAndSettle();
      expect(find.text('You both watched 12'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a friend row opens the friend, an Add row opens the add screen', (t) async {
      final (phone, api) = await open(t);
      api.routes['GET /v1/users/$ashaId'] = (_, _) => throw const ApiError(404, 'not_found', 'x');
      api.routes['GET /v1/users/$ashaId/films'] = (_, _) => throw const ApiError(404, 'not_found', 'x');
      await t.tap(find.text('You both watched 12'));
      await t.pumpAndSettle();
      expect(find.byType(FriendScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Add a friend').first);
      await t.pumpAndSettle();
      expect(find.byType(FriendsScreen), findsOneWidget);
      expect(phone.server.total, 0);
    });
  });

  group('Add a friend', () {
    Future<FakeApi> open(WidgetTester t, {Me? me}) async {
      final api = socialApi();
      api.routes['GET /v1/users/lookup'] = (q, _) => {'card': asha, 'relation': 'none'};
      await online(api, me: me).pump(t, const FriendsScreen(), size: tall);
      await t.pumpAndSettle();
      return api;
    }

    Future<void> find_(WidgetTester t, String handle) async {
      await t.enterText(find.byKey(const Key('friend-handle')), handle);
      await t.pump();
      await tapKey(t, 'find-friend');
    }

    testWidgets('an exact handle finds a person and a request goes out', (t) async {
      final api = await open(t);
      api.routes['POST /v1/friends/requests'] = (_, _) => {'status': 'pending'};
      await find_(t, '@Asha_K');
      expect(api.queries.last, {'handle': 'asha_k'});
      expect(find.byWidgetPredicate((w) => w is Text && w.data == '@asha_k'), findsOneWidget);
      await tapKey(t, 'send-request');
      expect(bodyOf(api, 'POST /v1/friends/requests'), {'user_id': ashaId});
      expect(find.text('Request sent.'), findsOneWidget);
      expect(find.text('Waiting for a reply'), findsWidgets);
      expect(find.byKey(const Key('send-request')), findsNothing);
    });

    testWidgets('a mutual request makes friends at once', (t) async {
      final api = await open(t);
      api.routes['POST /v1/friends/requests'] = (_, _) => {'status': 'friends'};
      await find_(t, 'asha_k');
      await tapKey(t, 'send-request');
      expect(find.text('You are now friends.'), findsOneWidget);
    });

    testWidgets('nobody has that handle', (t) async {
      final api = await open(t);
      api.routes['GET /v1/users/lookup'] = (_, _) => throw const ApiError(404, 'not_found', 'x');
      await find_(t, 'nobody');
      expect(find.text('No one has that handle. Check the spelling.'), findsOneWidget);
    });

    testWidgets('a handle that cannot exist is not sent to the server', (t) async {
      final api = await open(t);
      await find_(t, 'ab');
      expect(find.text('No one has that handle. Check the spelling.'), findsOneWidget);
      expect(api.count('GET /v1/users/lookup'), 0);
    });

    testWidgets('too many lookups, and a request that is already waiting, get calm lines', (t) async {
      final api = await open(t);
      api.routes['GET /v1/users/lookup'] = (_, _) => throw const ApiError(429, 'rate_limited', 'x');
      await find_(t, 'asha_k');
      expect(find.text('Too many tries. Wait a few minutes, then try again.'), findsOneWidget);

      api.routes['GET /v1/users/lookup'] = (_, _) => {'card': asha, 'relation': 'none'};
      api.routes['POST /v1/friends/requests'] = (_, _) => throw const ApiError(409, 'already_pending', 'x');
      await find_(t, 'asha_k');
      await tapKey(t, 'send-request');
      expect(find.text('A request is already waiting.'), findsOneWidget);
    });

    testWidgets('the person found already relates to me: friend, self, they asked first', (t) async {
      final api = await open(t);
      api.routes['GET /v1/users/lookup'] = (_, _) => {'card': asha, 'relation': 'friend'};
      await find_(t, 'asha_k');
      expect(find.text('You are already friends.'), findsOneWidget);

      api.routes['GET /v1/users/lookup'] = (_, _) => {'card': asha, 'relation': 'self'};
      await find_(t, 'asha_k');
      expect(find.text('That is your own handle.'), findsOneWidget);

      api.routes['GET /v1/users/lookup'] = (_, _) => {'card': asha, 'relation': 'incoming'};
      api.routes['POST /v1/friends/requests/$ashaId/accept'] = (_, _) => null;
      await find_(t, 'asha_k');
      await tapKey(t, 'accept-found');
      expect(find.text('You are now friends.'), findsOneWidget);
    });

    testWidgets('with no handle of my own, a row sends me to the account', (t) async {
      await open(t, me: testMe(handle: null));
      expect(find.text('Friends find you by your handle. Choose one in your account.'), findsOneWidget);
    });

    testWidgets('the whole list of friends is here', (t) async {
      await open(t);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Kabir'), findsOneWidget);
    });
  });

  group('A friend', () {
    Map<String, dynamic> profile({bool films = true}) => {
      'card': asha,
      'relation': 'friend',
      'visible': true,
      'match': {'both': 12, 'pct': 74},
      'stats': films
          ? {
              'films': 128,
              'viewings': 212,
              'avg_rating': 4.1,
              'top_genres': ['drama', 'action'],
              'top_langs': ['hi'],
            }
          : {'films': 0, 'viewings': 0, 'avg_rating': null, 'top_genres': <Object>[], 'top_langs': <Object>[]},
      'top_films': films
          ? [
              {'film_id': 'Q1', 'film': filmJson('Q1'), 'rating': 4.5},
            ]
          : <Object>[],
      'watchlist': films
          ? [
              {'film_id': 'Q4', 'film': filmJson('Q4')},
            ]
          : <Object>[],
    };

    FakeApi friendApi({bool films = true, String? shelfNext}) {
      final api = socialApi();
      api.routes['GET /v1/users/$ashaId'] = (_, _) => profile(films: films);
      api.routes['GET /v1/users/$ashaId/films'] = (q, _) => {
        'items': q?['cursor'] == null
            ? [
                {'film_id': 'Q2', 'film': filmJson('Q2'), 'rating': 3.5, 'viewings': 2},
              ]
            : [
                {'film_id': 'Q5', 'film': filmJson('Q5'), 'rating': null, 'viewings': 1},
              ],
        'next_cursor': q?['cursor'] == null ? shelfNext : null,
      };
      return api;
    }

    Future<FakeApi> open(WidgetTester t, {FakeApi? api, bool visible = true}) async {
      final a = api ?? friendApi();
      await online(a).pumpPushed(
        t,
        FriendScreen(card: UserCard.fromJson(asha), visible: visible),
        size: tall,
      );
      return a;
    }

    testWidgets('the stats ticket, top films, watchlist and the shelf with ratings and no dates', (t) async {
      await open(t);
      expect(find.text('@asha_k'), findsOneWidget);
      expect(find.text('You both watched 12'), findsOneWidget);
      expect(find.text('74%'), findsOneWidget);
      // The ticket: figures, top genres and languages.
      expect(find.text('128'), findsOneWidget);
      expect(find.text('212'), findsOneWidget);
      expect(find.text('4.1'), findsOneWidget);
      expect(find.text('Drama  ·  Action'), findsOneWidget);
      expect(find.descendant(of: find.byType(StatsTicket), matching: find.text('Hindi')), findsOneWidget);
      expect(find.text('Top films'), findsOneWidget);
      expect(find.text('Watchlist'), findsOneWidget);
      expect(find.text('Kantara'), findsOneWidget);
      // The shelf: a film with the rating the friend shares.
      expect(find.text('Films watched'), findsOneWidget);
      expect(find.text('Dilwale Dulhania Le Jayenge'), findsOneWidget);
      expect(find.text('3.5'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\b(19|20)\d\d-\d\d-\d\d\b')), findsNothing);
    });

    testWidgets('the shelf pages by cursor', (t) async {
      final api = await open(t, api: friendApi(shelfNext: 'o1'));
      expect(find.text('Panchayat'), findsNothing);
      await tapKey(t, 'shelf-more');
      expect(api.queries.last, {'cursor': 'o1'});
      expect(find.text('Panchayat'), findsOneWidget);
      expect(find.byKey(const Key('shelf-more')), findsNothing);
    });

    testWidgets('a friend who keeps films private shows one quiet line and asks for nothing', (t) async {
      final api = await open(t, visible: false);
      expect(find.text('Asha keeps their films private.'), findsOneWidget);
      expect(api.count('GET /v1/users/$ashaId'), 0);
      expect(find.text('Top films'), findsNothing);
    });

    testWidgets('a profile the server will not show says so, with Retry', (t) async {
      final api = friendApi();
      api.routes['GET /v1/users/$ashaId'] = (_, _) => throw const ApiError(404, 'not_found', 'x');
      await open(t, api: api);
      expect(find.text('You cannot see the films of Asha right now. They may be private.'), findsOneWidget);
      api.routes['GET /v1/users/$ashaId'] = (_, _) => profile();
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('128'), findsOneWidget);
    });

    testWidgets('a friend with nothing shared yet gets one line, not an empty page', (t) async {
      await open(t, api: friendApi(films: false));
      expect(find.text('Asha has not shared any films yet.'), findsOneWidget);
    });

    testWidgets('the server goes away: Can\'t reach Talkies', (t) async {
      final api = friendApi();
      api.routes['GET /v1/users/$ashaId'] = (_, _) => throw const ApiOffline('down');
      await open(t, api: api);
      expect(find.textContaining("Can't reach Talkies"), findsOneWidget);
    });

    Future<void> menu(WidgetTester t, String item) async {
      await t.tap(find.byKey(const Key('friend-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text(item));
      await t.pumpAndSettle();
    }

    testWidgets('Remove friend asks, then removes, leaves and says so', (t) async {
      final api = await open(t);
      api.routes['DELETE /v1/friends/$ashaId'] = (_, _) => null;
      await menu(t, 'Remove friend');
      expect(find.text('Remove Asha from your friends?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(api.count('DELETE /v1/friends/$ashaId'), 0);

      await menu(t, 'Remove friend');
      await t.tap(find.byKey(const Key('confirm-unfriend')));
      await t.pumpAndSettle();
      expect(api.count('DELETE /v1/friends/$ashaId'), 1);
      expect(find.byType(FriendScreen), findsNothing);
      expect(find.text('Asha is not your friend any more.'), findsOneWidget);
    });

    testWidgets('Block asks, then blocks, leaves and says so', (t) async {
      final api = await open(t);
      api.routes['POST /v1/blocks'] = (_, _) => null;
      api.routes['GET /v1/blocks'] = (_, _) => {'items': <Object>[]};
      await menu(t, 'Block');
      expect(find.text('Block Asha?'), findsOneWidget);
      await t.tap(find.byKey(const Key('confirm-block')));
      await t.pumpAndSettle();
      expect(bodyOf(api, 'POST /v1/blocks'), {'user_id': ashaId});
      expect(find.byType(FriendScreen), findsNothing);
      expect(find.text('Asha is blocked.'), findsOneWidget);
    });

    testWidgets('Report offers the five reasons and sends the one picked', (t) async {
      final api = await open(t);
      api.routes['POST /v1/reports'] = (_, _) => {'id': 'r1'};
      await menu(t, 'Report');
      for (final reason in ['Spam', 'Abuse', 'Harassment', 'Inappropriate content', 'Something else']) {
        expect(find.text(reason), findsOneWidget);
      }
      await t.tap(find.text('Harassment'));
      await t.pumpAndSettle();
      expect(api.bodies.last, {'kind': 'user', 'target_id': ashaId, 'reason': 'harassment', 'note': null});
      expect(find.text('Report sent. Thank you.'), findsOneWidget);
      expect(find.byType(FriendScreen), findsOneWidget); // still here
    });
  });

  group('Your profile', () {
    Future<void> record(Phone phone, WidgetTester t, {bool privateOne = false}) async {
      await phone.pump(t, const SizedBox());
      final c = phone.container(t);
      final n = c.read(diaryProvider.notifier);
      n.addStub(phone.catalog.byId['Q1']!, const StubDraft(rating: 4.5));
      n.addStub(phone.catalog.byId['Q2']!, const StubDraft(rating: 3.0, private: true));
      n.toggleWish(phone.catalog.byId['Q4']!);
    }

    testWidgets('works with no server: the figures leave out the private stub, and there is no sign-in line', (
      t,
    ) async {
      final phone = Phone(configured: false);
      await record(phone, t);
      await phone.pump(t, const ProfileScreen(), size: tall);
      await t.pumpAndSettle();
      expect(find.text('Your profile'.toUpperCase()), findsOneWidget);
      expect(find.text('1'), findsWidgets); // one film, one viewing: the private one is not counted
      expect(find.text('Top films'), findsOneWidget);
      expect(find.text('Sholay'), findsOneWidget);
      expect(find.text('Dilwale Dulhania Le Jayenge'), findsNothing);
      expect(find.text('Watchlist'), findsOneWidget);
      expect(find.text('Kantara'), findsOneWidget);
      expect(find.text('Sign in to share this with friends'), findsNothing);
      expect(phone.server.total, 0);
    });

    testWidgets('an empty diary says how to start', (t) async {
      final phone = Phone(configured: false);
      await phone.pump(t, const ProfileScreen());
      await t.pumpAndSettle();
      expect(find.text('Record a film to build your profile.'), findsOneWidget);
      expect(find.text('Record a film'), findsOneWidget);
    });

    testWidgets('signed out with the server up: the footer line opens the sign-in', (t) async {
      final phone = Phone(status: Backend.up, auth: ['email']);
      await record(phone, t);
      await phone.pump(t, const ProfileScreen(), size: tall);
      await t.pumpAndSettle();
      expect(find.text('Sign in to share this with friends'), findsOneWidget);
      await t.tap(find.text('Sign in to share this with friends'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('email')), findsOneWidget);
    });

    testWidgets('signed in: the header, and the visibility word links to the account', (t) async {
      final phone = Phone(status: Backend.up, session: Session(meId, testMe(friends: true)), api: socialApi());
      await record(phone, t);
      await phone.pump(t, const ProfileScreen(), size: tall);
      await t.pumpAndSettle();
      expect(find.text('Meena'), findsOneWidget);
      expect(find.text('@meena'), findsOneWidget);
      expect(find.text('Visibility: Friends only'), findsOneWidget);
      expect(find.text('Sign in to share this with friends'), findsNothing);
    });

    testWidgets('signed in with ratings hidden from friends: the preview hides them too', (t) async {
      final phone = Phone(status: Backend.up, session: Session(meId, testMe()), api: socialApi());
      await record(phone, t);
      await phone.pump(t, const ProfileScreen(), size: tall);
      await t.pumpAndSettle();
      expect(find.text('Average rating'), findsNothing);
      expect(find.text('4.5'), findsNothing);
    });

    testWidgets('Share as image opens the share sheet', (t) async {
      final phone = Phone(configured: false);
      await record(phone, t);
      await phone.pump(t, const ProfileScreen());
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Share as image'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('share-image')), findsOneWidget);
    });
  });
}
