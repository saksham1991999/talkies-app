import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/social.dart' hide FriendsWhoWatched; // the model shares its name with the widget
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/online_widgets.dart';
import 'package:talkies/ui/screens/account_screen.dart';
import 'package:talkies/ui/screens/chat_screen.dart';
import 'package:talkies/ui/screens/friend_screen.dart';
import 'package:talkies/ui/screens/friends_screen.dart';
import 'package:talkies/ui/screens/profile_screen.dart';
import 'package:talkies/ui/screens/settings_screen.dart';

import '../support/fake_api.dart';
import 'online_chat_test.dart' as chat show chatApi, conversation, gid, message, me, ravi;
import 'online_friends_test.dart' as friends show asha;
import 'online_harness.dart';

/// Every online screen, light and dark, builds without an error. Run with `SHOTS=a-folder flutter test
/// test/ui/online_shots_test.dart` to get a PNG of each, to look at.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  FakeApi api() {
    final a = socialApi();
    final asha = friends.asha;
    a.routes['GET /v1/blocks'] = (_, _) => {
      'items': [cardJson(rohanId, 'Rohan', handle: 'rohan', ink: 2)],
    };
    a.routes['GET /v1/me'] = (_, _) => testMe(friends: true).toJson();
    a.routes['GET /v1/users/$ashaId'] = (_, _) => {
      'card': asha,
      'relation': 'friend',
      'visible': true,
      'match': {'both': 12, 'pct': 74},
      'stats': {
        'films': 128,
        'viewings': 212,
        'avg_rating': 4.1,
        'top_genres': ['drama', 'action'],
        'top_langs': ['hi', 'ta'],
      },
      'top_films': [
        {'film_id': 'Q1', 'film': filmJson('Q1'), 'rating': 4.5},
        {'film_id': 'Q2', 'film': filmJson('Q2'), 'rating': 4.0},
      ],
      'watchlist': [
        {'film_id': 'Q4', 'film': filmJson('Q4')},
      ],
    };
    a.routes['GET /v1/users/$ashaId/films'] = (_, _) => {
      'items': [
        {'film_id': 'Q3', 'film': filmJson('Q3'), 'rating': 3.5, 'viewings': 1},
        {'film_id': 'Q5', 'film': filmJson('Q5'), 'rating': null, 'viewings': 2},
      ],
      'next_cursor': null,
    };
    a.routes['GET /v1/films/Q1/friends'] = (_, _) => {
      'items': [
        {'user': asha, 'rating': 4.5},
        {'user': cardJson(taraId, 'Tara', ink: 6), 'rating': null},
      ],
    };
    return a;
  }

  // The narrowest phone with large text: the account, the friends and a chat.
  testWidgets('narrow: account, friends, chat at 320 dp and text scale 1.5', (t) async {
    final p = Phone(status: Backend.up, session: Session(meId, testMe(friends: true)), api: api());
    await p.pump(t, const AccountScreen(), size: const Size(320, 2200), textScale: 1.5);
    await t.pumpAndSettle();
    await p.shot(t, 'narrow-account');
    expect(t.takeException(), isNull);
    await p.pump(t, const Scaffold(body: FriendsSegment()), size: const Size(320, 3600), textScale: 1.5);
    await t.pumpAndSettle();
    await p.shot(t, 'narrow-friends');
    expect(t.takeException(), isNull);
    final q = Phone(status: Backend.up, session: Session(meId, testMe()), api: chat.chatApi());
    await t.pumpWidget(const SizedBox());
    await q.pump(t, ChatScreen(crewId: chat.gid), size: const Size(320, 1500), textScale: 1.5);
    await t.pumpAndSettle();
    await q.shot(t, 'narrow-chat');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    Phone phone({Locale locale = const Locale('en')}) => Phone(
      status: Backend.up,
      session: Session(meId, testMe(friends: true)),
      api: api(),
      dark: dark,
      locale: locale,
    );

    testWidgets('$mode: account', (t) async {
      final p = phone();
      await p.pump(t, const AccountScreen(), size: const Size(360, 1500));
      await t.pumpAndSettle();
      await p.shot(t, '$mode-account');
      expect(t.takeException(), isNull);
    });

    testWidgets('$mode: sign in', (t) async {
      final p = Phone(
        status: Backend.up,
        auth: ['email', 'google', 'apple'],
        dark: dark,
        overrides: [
          isIosProvider.overrideWithValue(true),
          googleConfiguredProvider.overrideWithValue(true),
          appleConfiguredProvider.overrideWithValue(true),
        ],
      );
      await p.pump(t, const AccountScreen());
      await t.pumpAndSettle();
      await p.shot(t, '$mode-signin');
      expect(t.takeException(), isNull);
    });

    testWidgets('$mode: settings', (t) async {
      final p = phone();
      await p.pump(t, const SettingsScreen());
      await t.pumpAndSettle();
      await p.shot(t, '$mode-settings');
      expect(t.takeException(), isNull);
    });

    testWidgets('$mode: friends', (t) async {
      final p = phone();
      await p.pump(t, const Scaffold(body: FriendsSegment()), size: const Size(360, 2600));
      await t.pumpAndSettle();
      await p.shot(t, '$mode-friends');
      expect(t.takeException(), isNull);
    });

    testWidgets('$mode: add a friend', (t) async {
      final p = phone();
      await p.pump(t, const FriendsScreen(), size: const Size(360, 900));
      await t.pumpAndSettle();
      await p.shot(t, '$mode-add');
      expect(t.takeException(), isNull);
    });

    testWidgets('$mode: a friend', (t) async {
      final p = phone();
      await p.pump(t, FriendScreen(card: UserCard.fromJson(friends.asha)), size: const Size(360, 1700));
      await t.pumpAndSettle();
      await p.shot(t, '$mode-friend');
      expect(t.takeException(), isNull);
    });

    testWidgets('$mode: my profile', (t) async {
      final p = phone();
      await p.pump(t, const SizedBox());
      final n = p.container(t).read(diaryProvider.notifier);
      n.addStub(p.catalog.byId['Q1']!, const StubDraft(rating: 4.5));
      n.addStub(p.catalog.byId['Q3']!, const StubDraft(rating: 3.0));
      n.toggleWish(p.catalog.byId['Q4']!);
      await p.pump(t, const ProfileScreen(), size: const Size(360, 1000));
      await t.pumpAndSettle();
      await p.shot(t, '$mode-profile');
      expect(t.takeException(), isNull);
    });

    testWidgets('$mode: chat', (t) async {
      final long = chat.message(
        20,
        sender: chat.ravi,
        body:
            'A long message that has to wrap over a few lines so the slip shows how wide it may get on a small phone.',
      );
      final p = Phone(
        status: Backend.up,
        session: Session(meId, testMe()),
        api: chat.chatApi(
          latest: [
            ...chat.conversation(),
            long,
            chat.message(21, sender: chat.me, body: 'Same here'),
          ],
        ),
        dark: dark,
      );
      await p.pump(t, ChatScreen(crewId: chat.gid), size: const Size(360, 900));
      await t.pumpAndSettle();
      await p.shot(t, '$mode-chat');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('$mode: friends who watched, and the send sheet', (t) async {
      final p = phone();
      final film = p.catalog.byId['Q1']!;
      await p.pump(
        t,
        Scaffold(
          body: ListView(
            children: [
              FriendsWhoWatched(film: film),
              SendFilmButton(film: film),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      await p.shot(t, '$mode-who');
      await t.tap(find.byKey(const Key('send-film')));
      await t.pumpAndSettle();
      await p.shot(t, '$mode-send');
      expect(t.takeException(), isNull);
    });
  }
}
