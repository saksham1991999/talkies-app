import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/social.dart' hide FriendsWhoWatched; // the model shares its name with the widget
import 'package:talkies/state/online.dart';
import 'package:talkies/ui/online_widgets.dart';
import 'package:talkies/ui/screens/account_screen.dart';
import 'package:talkies/ui/screens/chat_screen.dart';
import 'package:talkies/ui/screens/friend_screen.dart';

import 'online_chat_test.dart' as chat show chatApi, gid, raviId;
import 'online_harness.dart';

/// Every control of the online screens is at least 44 by 44, at the normal text size and at 1.5 times it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  for (final scale in [1.0, 1.5]) {
    Phone phone({dynamic api}) =>
        Phone(status: Backend.up, session: Session(meId, testMe(friends: true)), api: api ?? socialApi());

    Future<void> big(WidgetTester t, Phone p, Widget screen) async {
      await p.pump(t, screen, size: const Size(320, 3200), textScale: scale);
      await t.pumpAndSettle();
    }

    void atLeast44(WidgetTester t, Iterable<String> keys) {
      for (final k in keys) {
        final f = find.byKey(Key(k));
        expect(f, findsWidgets, reason: k);
        final size = t.getSize(f.first);
        expect(size.width, greaterThanOrEqualTo(44), reason: '$k is ${size.width} wide at text scale $scale');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$k is ${size.height} high at text scale $scale');
      }
    }

    testWidgets('account, text scale $scale', (t) async {
      final api = socialApi()
        ..routes['GET /v1/me'] = ((_, _) => testMe(friends: true).toJson())
        ..routes['GET /v1/blocks'] = ((_, _) => {
          'items': [cardJson(rohanId, 'Rohan', handle: 'rohan')],
        });
      await big(t, phone(api: api), const AccountScreen());
      atLeast44(t, [
        'save-profile',
        for (var i = 0; i < 11; i++) 'ink-$i',
        'vis-private',
        'vis-friends',
        'share-ratings',
        'unblock-$rohanId',
      ]);
    });

    testWidgets('sign in, text scale $scale', (t) async {
      final p = Phone(status: Backend.up, auth: ['email', 'google', 'apple']);
      await p.pump(t, const AccountScreen(), size: const Size(320, 900), textScale: scale);
      await t.pumpAndSettle();
      atLeast44(t, ['email', 'send-code']);
      await t.enterText(find.byKey(const Key('email')), 'me@example.test');
      await t.pump();
      await t.tap(find.byKey(const Key('send-code')));
      await t.pumpAndSettle();
      atLeast44(t, ['code', 'verify', 'resend', 'other-email']);
    });

    testWidgets('friends, text scale $scale', (t) async {
      await big(t, phone(), const Scaffold(body: FriendsSegment()));
      atLeast44(t, [
        'accept-$rohanId',
        'decline-$rohanId',
        'cancel-$taraId',
        for (var i = 0; i < 8; i++) 'react-$i',
        'want-w:30',
      ]);
    });

    testWidgets('a friend, text scale $scale', (t) async {
      final api = socialApi()
        ..routes['GET /v1/users/$ashaId'] = ((_, _) => {
          'card': cardJson(ashaId, 'Asha'),
          'relation': 'friend',
          'visible': true,
          'match': null,
          'stats': {'films': 1, 'viewings': 1, 'avg_rating': null, 'top_genres': <Object>[], 'top_langs': <Object>[]},
          'top_films': <Object>[],
          'watchlist': [
            {'film_id': 'Q4', 'film': filmJson('Q4')},
          ],
        })
        ..routes['GET /v1/users/$ashaId/films'] = ((_, _) => {
          'items': [
            {'film_id': 'Q2', 'film': filmJson('Q2'), 'rating': null, 'viewings': 1},
          ],
          'next_cursor': 'x',
        });
      await big(t, phone(api: api), FriendScreen(card: UserCard.fromJson(cardJson(ashaId, 'Asha'))));
      atLeast44(t, ['friend-menu', 'shelf-more']);
    });

    testWidgets('chat, text scale $scale', (t) async {
      await big(t, phone(api: chat.chatApi()), ChatScreen(crewId: chat.gid));
      atLeast44(t, ['chat-attach', 'chat-send', 'sender-${chat.raviId}']);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('film pieces, text scale $scale', (t) async {
      final p = phone(
        api: socialApi()
          ..routes['GET /v1/films/Q1/friends'] = ((_, _) => {
            'items': [
              {'user': cardJson(ashaId, 'Asha'), 'rating': null},
            ],
          }),
      );
      final film = p.catalog.byId['Q1']!;
      await big(
        t,
        p,
        Scaffold(
          body: ListView(
            children: [
              FriendsWhoWatched(film: film),
              SendFilmButton(film: film),
            ],
          ),
        ),
      );
      atLeast44(t, ['who-$ashaId', 'send-film']);
      await t.tap(find.byKey(const Key('send-film')));
      await t.pumpAndSettle();
      atLeast44(t, ['send-to-$ashaId', 'send-other']);
    });
  }
}
