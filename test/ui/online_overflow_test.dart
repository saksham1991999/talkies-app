import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/social.dart' hide FriendsWhoWatched; // the model shares its name with the widget
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/online_widgets.dart';
import 'package:talkies/ui/screens/account_screen.dart';
import 'package:talkies/ui/screens/chat_screen.dart';
import 'package:talkies/ui/screens/friend_screen.dart';
import 'package:talkies/ui/screens/friends_screen.dart';
import 'package:talkies/ui/screens/profile_screen.dart';
import 'package:talkies/ui/screens/search_screen.dart';
import 'package:talkies/ui/screens/settings_screen.dart';

import '../support/fake_api.dart';
import 'online_chat_test.dart' as chat show chatApi, conversation, gid, message, ravi;
import 'online_harness.dart';

/// The narrowest phone and the largest text most people use: 320 dp wide, text scale 1.5, in English and in Tamil
/// (the Tamil file holds English drafts until the translators merge theirs; this test then covers the real
/// text with no change). A screen that overflows throws, and the test fails.
/// The whole report of every error a screen raised. An overflow names the widget that overflowed.
final reports = <String>[];

/// Fails with the whole report of the error a screen raised.
void noError(WidgetTester t) {
  final e = t.takeException();
  if (e != null) fail(reports.isEmpty ? '$e' : reports.join('\n----\n'));
}

const narrow = 320.0;
const scale = 1.5;

/// 320 wide and tall enough to build every row, so every row is laid out at that width.
const tall = Size(narrow, 3200);

final longName = 'Venkatasubramanian Raghunathan-Iyer';
const longTitle = 'Dilwale Dulhania Le Jayenge: the Complete Director\'s Cut';

FakeApi everything() {
  final api = socialApi(
    feed: [
      {
        ...feedItem(
          'w:30',
          'watched',
          cardJson(ashaId, longName, handle: 'asha_k', ink: 3),
          'Q2',
          rating: 4.5,
          mine: 2,
        ),
        'film': {...filmJson('Q2'), 't': longTitle},
      },
      feedItem(
        's:29',
        'sent',
        cardJson(taraId, 'Tara', ink: 6),
        'Q1',
        note: 'Watch this one with chai and a long note that goes on for two or three lines',
      ),
      feedItem('r:28', 'reaction', cardJson(kabirId, 'Kabir', ink: 5), 'Q3', reaction: 0),
    ],
  );
  final asha = cardJson(ashaId, longName, handle: 'asha_k', ink: 3);
  api.routes['GET /v1/blocks'] = (_, _) => {
    'items': [cardJson(rohanId, longName, handle: 'rohan', ink: 2)],
  };
  api.routes['GET /v1/me'] = (_, _) => testMe(name: longName, friends: true).toJson();
  api.routes['GET /v1/users/lookup'] = (_, _) => {'card': asha, 'relation': 'none'};
  api.routes['GET /v1/users/$ashaId'] = (_, _) => {
    'card': asha,
    'relation': 'friend',
    'visible': true,
    'match': {'both': 12, 'pct': 74},
    'stats': {
      'films': 12345,
      'viewings': 54321,
      'avg_rating': 4.1,
      'top_genres': ['drama', 'action', 'romance'],
      'top_langs': ['hi', 'ta', 'ml'],
    },
    'top_films': [
      {'film_id': 'Q2', 'film': filmJson('Q2'), 'rating': 4.5},
    ],
    'watchlist': [
      {'film_id': 'Q4', 'film': filmJson('Q4')},
    ],
  };
  api.routes['GET /v1/users/$ashaId/films'] = (_, _) => {
    'items': [
      {'film_id': 'Q2', 'film': filmJson('Q2'), 'rating': 3.5, 'viewings': 2},
    ],
    'next_cursor': 'more',
  };
  api.routes['GET /v1/films/Q2/friends'] = (_, _) => {
    'items': [
      for (var i = 0; i < 7; i++)
        {'user': cardJson('22222222-2222-4222-8222-0000000001$i$i', 'Friend $i', ink: i), 'rating': 4.0},
    ],
  };
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  for (final locale in [const Locale('en'), const Locale('ta')]) {
    for (final dark in [false, true]) {
      final where = '${locale.languageCode} ${dark ? 'dark' : 'light'}';

      Phone signedIn({FakeApi? api, Backend status = Backend.up}) => Phone(
        status: status,
        session: Session(meId, testMe(name: longName, friends: true)),
        api: api ?? everything(),
        locale: locale,
        dark: dark,
      );

      Future<void> fits(WidgetTester t, Phone phone, Widget screen, {Size size = tall}) async {
        reports.clear();
        final before = FlutterError.onError;
        FlutterError.onError = (d) {
          reports.add(d.toString());
          before?.call(d);
        };
        addTearDown(() => FlutterError.onError = before);
        await phone.pump(t, screen, size: size, textScale: scale);
        await t.pumpAndSettle();
        noError(t);
      }

      testWidgets('$where: sign in, the email step, the code step and the other methods', (t) async {
        final phone = Phone(
          status: Backend.up,
          auth: ['email', 'google', 'apple'],
          locale: locale,
          dark: dark,
          overrides: [
            isIosProvider.overrideWithValue(true),
            googleConfiguredProvider.overrideWithValue(true),
            appleConfiguredProvider.overrideWithValue(true),
          ],
        );
        await fits(t, phone, const AccountScreen(), size: const Size(narrow, 900));
        expect(find.byKey(const Key('apple-sign-in')), findsOneWidget);
        await t.enterText(find.byKey(const Key('email')), 'a.very.long.address.for.a.narrow.phone@example.test');
        await t.pump();
        await t.tap(find.byKey(const Key('send-code')));
        await t.pumpAndSettle();
        noError(t);
      });

      testWidgets('$where: the code step', (t) async {
        final phone = Phone(status: Backend.up, auth: ['email'], locale: locale, dark: dark);
        await fits(t, phone, const AccountScreen(), size: const Size(narrow, 900));
        await t.enterText(find.byKey(const Key('email')), 'a.very.long.address.for.a.narrow.phone@example.test');
        await t.pump();
        await t.tap(find.byKey(const Key('send-code')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('code')), findsOneWidget);
        noError(t);
      });

      testWidgets('$where: account, signed in', (t) async {
        await fits(t, signedIn(), const AccountScreen());
      });

      testWidgets('$where: account with the server away', (t) async {
        final api = everything()..routes['GET /healthz'] = ((_, _) => throw const ApiOffline('down'));
        await fits(
          t,
          signedIn(api: api, status: Backend.down),
          const AccountScreen(),
          size: const Size(narrow, 900),
        );
      });

      testWidgets('$where: settings with the account row', (t) async {
        await fits(t, signedIn(), const SettingsScreen(), size: const Size(narrow, 900));
      });

      testWidgets('$where: friends segment', (t) async {
        await fits(t, signedIn(), const Scaffold(body: FriendsSegment()));
      });

      testWidgets('$where: friends segment inside a parent that scrolls', (t) async {
        await fits(t, signedIn(), Scaffold(body: ListView(children: const [FriendsSegment()])));
      });

      testWidgets('$where: add a friend, with a person found', (t) async {
        final phone = signedIn();
        await fits(t, phone, const FriendsScreen());
        await t.enterText(find.byKey(const Key('friend-handle')), 'asha_k');
        await t.pump();
        await t.tap(find.byKey(const Key('find-friend')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('send-request')), findsOneWidget);
        noError(t);
      });

      testWidgets('$where: a friend', (t) async {
        await fits(t, signedIn(), FriendScreen(card: UserCard.fromJson(cardJson(ashaId, longName, handle: 'asha_k'))));
      });

      testWidgets('$where: my profile', (t) async {
        final phone = signedIn();
        await phone.pump(t, const SizedBox());
        final n = phone.container(t).read(diaryProvider.notifier);
        n.addStub(phone.catalog.byId['Q1']!, const StubDraft(rating: 4.5));
        n.addStub(phone.catalog.byId['Q3']!, const StubDraft(rating: 3.0));
        await fits(t, phone, const ProfileScreen());
      });

      testWidgets('$where: friends who watched, the strip and the send sheet', (t) async {
        final phone = signedIn();
        final film = phone.catalog.byId['Q2']!;
        await fits(
          t,
          phone,
          Scaffold(
            body: ListView(
              children: [
                FriendsWhoWatched(film: film),
                const FriendsStrip(),
                SendFilmButton(film: film),
              ],
            ),
          ),
          size: const Size(narrow, 900),
        );
        await t.tap(find.byKey(const Key('send-film')));
        await t.pumpAndSettle();
        noError(t);
        expect(find.byKey(const Key('send-other')), findsOneWidget);
      });

      testWidgets('$where: chat with long names, a long word, a film and a night', (t) async {
        final api = chat.chatApi(
          latest: [
            ...chat.conversation(),
            chat.message(
              20,
              sender: {...chat.ravi, 'display_name': longName},
              body: 'https://example.com/${'a-very-long-link' * 6}',
            ),
            chat.message(
              21,
              sender: chat.ravi,
              body: 'Look',
              film: 'Q2',
              night: 'c0ffee00-1111-4222-8333-444455556666',
            ),
          ],
        );
        final phone = signedIn(api: api);
        await fits(t, phone, ChatScreen(crewId: chat.gid), size: const Size(narrow, 1400));
        // A film attached to the message being written.
        await t.tap(find.byKey(const Key('chat-attach')));
        await t.pumpAndSettle();
        t.widget<SearchScreen>(find.byType(SearchScreen)).onPick!(phone.catalog.byId['Q2']!);
        // Not pageBack: it looks for the English tooltip of the back button.
        t.state<NavigatorState>(find.byType(Navigator).first).pop();
        await t.pumpAndSettle();
        noError(t);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
