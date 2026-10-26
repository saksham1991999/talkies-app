import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/sync.dart';
import 'package:talkies/ui/avatar.dart';
import 'package:talkies/ui/online_parts.dart';
import 'package:talkies/ui/online_widgets.dart';
import 'package:talkies/ui/screens/account_screen.dart';
import 'package:talkies/ui/screens/chat_screen.dart';
import 'package:talkies/ui/screens/friends_screen.dart';
import 'package:talkies/ui/screens/profile_screen.dart';
import 'package:talkies/ui/screens/search_screen.dart';

import '../support/fake_api.dart';
import 'online_account_test.dart' show accountApi;
import 'online_chat_test.dart' as chat show chatApi, gid, message;
import 'online_harness.dart';

class _AsksWhich extends SyncEngine {
  static final chosen = <AccountChoice>[];
  @override
  SyncState build() => SyncState.needsAccountChoice;
  @override
  Future<void> chooseAccount(AccountChoice choice) async {
    chosen.add(choice);
    state = SyncState.idle;
  }
}

/// Every control that the other files reach only in passing, and the things that must sit in the middle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  Phone phone(FakeApi api) => Phone(status: Backend.up, session: Session(meId, testMe()), api: api);

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  group('controls', () {
    testWidgets('Sign in with Apple signs in through the fake server', (t) async {
      final p = Phone(
        status: Backend.up,
        auth: ['email', 'apple'],
        overrides: [
          isIosProvider.overrideWithValue(true),
          appleConfiguredProvider.overrideWithValue(true),
          appleTokenProvider.overrideWithValue((hashed) async => 'apple-token'),
        ],
      );
      p.server.health = {
        'ok': true,
        'api': 1,
        'auth': ['email', 'apple'],
      };
      await p.pump(t, const AccountScreen());
      await t.tap(find.byKey(const Key('apple-sign-in')));
      await t.pumpAndSettle();
      expect(p.server.count('POST /v1/auth/id-token'), 1);
      expect(p.container(t).read(signedInProvider), isTrue);
    });

    testWidgets('a dismissed "which diary?" comes back with Choose, and Keep separate is passed on', (t) async {
      _AsksWhich.chosen.clear();
      final p = Phone(
        status: Backend.up,
        session: Session(meId, testMe()),
        api: accountApi(),
        overrides: [syncEngineProvider.overrideWith(_AsksWhich.new)],
      );
      await p.pump(t, const AccountScreen());
      await t.pumpAndSettle();
      expect(find.text('Two diaries'), findsOneWidget);
      await t.tapAt(const Offset(4, 4)); // outside the dialog
      await t.pumpAndSettle();
      expect(find.text('Two diaries'), findsNothing);
      expect(find.text('This phone has a diary from another account.'), findsOneWidget);
      await tapKey(t, 'choose-account');
      expect(find.text('Two diaries'), findsOneWidget);
      await t.tap(find.byKey(const Key('choice-separate')));
      await t.pumpAndSettle();
      expect(_AsksWhich.chosen, [AccountChoice.separate]);
    });

    testWidgets('the account opens your profile; the profile opens the account', (t) async {
      final p = phone(accountApi());
      await p.pump(t, const AccountScreen());
      await t.pumpAndSettle();
      await t.tap(find.text('Your profile'));
      await t.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      await t.tap(find.text('Visibility: Private'));
      await t.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget); // the new one, over the profile
      expect(find.byType(ProfileScreen), findsNothing); // offstage under it
    });

    testWidgets('an empty profile sends you to record a film', (t) async {
      final p = Phone(configured: false);
      await p.pump(t, const ProfileScreen());
      await t.pumpAndSettle();
      await t.tap(find.text('Record a film'));
      await t.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('Refresh asks for the feed again', (t) async {
      final api = socialApi();
      final p = phone(api);
      await p.pump(t, const Scaffold(body: FriendsSegment()), size: const Size(360, 3000));
      await t.pumpAndSettle();
      expect(api.count('GET /v1/feed'), 1);
      await t.tap(find.text('Refresh'));
      await t.pumpAndSettle();
      expect(api.count('GET /v1/feed'), 2);
    });

    testWidgets('with more than three friends the segment shows three and a row for all', (t) async {
      final api = socialApi();
      api.routes['GET /v1/friends'] = (_, _) => {
        'items': [
          for (var i = 0; i < 5; i++)
            {
              'card': cardJson('22222222-2222-4222-8222-0000000002$i$i', 'Friend $i', ink: i),
              'visible': true,
              'match': null,
            },
        ],
      };
      final p = phone(api);
      await p.pump(t, const Scaffold(body: FriendsSegment()), size: const Size(360, 3000));
      await t.pumpAndSettle();
      expect(find.text('Friend 2'), findsOneWidget);
      expect(find.text('Friend 3'), findsNothing);
      expect(find.text('All friends'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      await t.tap(find.text('All friends'));
      await t.pumpAndSettle();
      expect(find.byType(FriendsScreen), findsOneWidget);
      expect(find.text('Friend 4'), findsOneWidget); // the whole list is there
    });

    testWidgets('with no handle of my own, the row on the add screen opens the account', (t) async {
      final api = socialApi();
      await Phone(
        status: Backend.up,
        session: Session(meId, testMe(handle: null)),
        api: api,
      ).pump(t, const FriendsScreen(), size: const Size(360, 1200));
      await t.pumpAndSettle();
      await t.tap(find.text('Friends find you by your handle. Choose one in your account.'));
      await t.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
    });
  });

  group('centered', () {
    Offset center(WidgetTester t, Finder f) => t.getCenter(f);

    testWidgets('a chosen reaction sits in the middle of its slab', (t) async {
      final api = socialApi();
      final p = phone(api);
      api.routes['PUT /v1/reactions'] = (_, _) => null;
      await p.pump(t, const Scaffold(body: FriendsSegment()), size: const Size(360, 3000));
      await t.pumpAndSettle();
      await tapKey(t, 'react-3');
      final cell = find.byKey(const Key('react-3'));
      final slab = find.descendant(of: cell, matching: find.byType(Container)).first;
      final glyph = find.descendant(of: cell, matching: find.text(reactionEmoji[3]));
      expect((center(t, glyph) - center(t, slab)).distance, lessThan(0.5));
      // The slab is the middle of its cell.
      expect((center(t, slab) - center(t, cell)).distance, lessThan(0.5));
    });

    testWidgets('the arrow of a chat ticket is the middle of its counterfoil', (t) async {
      final p = phone(
        chat.chatApi(
          latest: [chat.message(1, body: 'Look', film: 'Q1')],
        ),
      );
      await p.pump(t, ChatScreen(crewId: chat.gid), size: const Size(360, 800));
      await t.pumpAndSettle();
      final ticket = find.byType(TicketRow);
      final box = t.getRect(ticket);
      final arrow = find.descendant(of: ticket, matching: find.byType(CustomPaint)).evaluate();
      expect(arrow, isNotEmpty);
      // The counterfoil is the last 46 dp of the ticket.
      final icons = find.descendant(
        of: ticket,
        matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 46 && w.child is Center),
      );
      final cf = t.getRect(icons);
      expect(cf.right, closeTo(box.right, 0.5));
      expect(cf.center.dy, closeTo(box.center.dy, 0.5));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a stamp in the ink picker is in the middle of its box', (t) async {
      final p = phone(accountApi());
      await p.pump(t, const AccountScreen(), size: const Size(360, 1600));
      await t.pumpAndSettle();
      for (var i = 0; i < 11; i++) {
        final cell = find.byKey(Key('ink-$i'));
        final stamp = find.descendant(of: cell, matching: find.byType(Avatar));
        expect((center(t, stamp) - center(t, cell)).distance, lessThan(0.5), reason: 'ink $i');
      }
    });

    testWidgets('a system line is in the middle of the screen', (t) async {
      final p = phone(
        chat.chatApi(
          latest: [
            chat.message(1, code: 'wrapped', args: {'night_id': 'n'}),
          ],
        ),
      );
      await p.pump(t, ChatScreen(crewId: chat.gid), size: const Size(360, 800));
      await t.pumpAndSettle();
      expect(center(t, find.text('The night is wrapped up')).dx, closeTo(180, 0.5));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the empty and loading notes are in the middle', (t) async {
      final p = phone(chat.chatApi(latest: const []));
      await p.pump(t, ChatScreen(crewId: chat.gid), size: const Size(360, 800));
      await t.pumpAndSettle();
      expect(center(t, find.text('No messages yet. Say hello.')).dx, closeTo(180, 0.5));
      await t.pumpWidget(const SizedBox());
    });
  });
}
