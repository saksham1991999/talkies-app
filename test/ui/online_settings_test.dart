import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/screens/record_screen.dart';
import 'package:talkies/ui/screens/settings_screen.dart';
import 'package:talkies/ui/screens/stub_screen.dart';

import 'online_harness.dart';

/// The lock beside a private stub's number: its label is what a screen reader says.
final lockMark = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Private stub');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  group('Settings', () {
    testWidgets('no server address: no Account group, and not one request', (t) async {
      final phone = Phone(configured: false);
      await phone.pump(t, const SettingsScreen());
      await t.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Account'), findsNothing);
      expect(find.text('Sign in'), findsNothing);
      expect(phone.server.total, 0);
      // The same screen with a server shows the same rows below the Account group.
      expect(t.takeException(), isNull);
    });

    testWidgets('server up, signed out: one health check, then a Sign in row that opens the account screen', (t) async {
      final phone = Phone();
      await phone.pump(t, const SettingsScreen());
      await t.pumpAndSettle();
      expect(phone.server.count('GET /healthz'), 1);
      expect(phone.server.total, 1);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      // The Account group sits above Appearance.
      expect(t.getTopLeft(find.text('Account')).dy, lessThan(t.getTopLeft(find.text('Appearance')).dy));

      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('email')), findsOneWidget);
    });

    testWidgets('server down, signed out: no Account group', (t) async {
      final phone = Phone();
      phone.server.offline = true;
      await phone.pump(t, const SettingsScreen());
      await t.pumpAndSettle();
      expect(find.text('Account'), findsNothing);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('signed in: the account row shows, also while the server is down', (t) async {
      final phone = Phone(status: Backend.down, session: Session(meId, testMe()));
      phone.server.offline = true; // opening Settings asks the server once more: no answer
      await phone.pump(t, const SettingsScreen());
      await t.pumpAndSettle();
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Meena'), findsOneWidget);
      expect(find.text('Your diary is safe on this phone'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);

      await t.tap(find.text('Meena'));
      await t.pumpAndSettle();
      // The account screen shows the quiet panel and Sign out, and nothing else of the account.
      expect(find.textContaining('Your diary is safe on this phone.'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.byKey(const Key('name')), findsNothing);
      expect(find.text('Delete account'), findsNothing);
    });

    testWidgets('signed in and the server answers: the row names the person', (t) async {
      final phone = Phone(status: Backend.up, session: Session(meId, testMe()));
      await phone.pump(t, const SettingsScreen());
      await t.pumpAndSettle();
      expect(find.text('Meena'), findsOneWidget);
      expect(find.text('@meena'), findsOneWidget);
    });
  });

  group('Private stub', () {
    Future<void> openRecord(WidgetTester t, Phone phone) async {
      await phone.pump(t, RecordScreen(film: phone.catalog.byId['Q1']!));
    }

    testWidgets('the switch is not there for a signed-out user', (t) async {
      final phone = Phone(configured: false);
      await openRecord(t, phone);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await t.pump();
      expect(find.byKey(const Key('private-stub')), findsNothing);
      expect(find.text('Private: keep this stub off my profile'), findsNothing);
    });

    testWidgets('signed in with the server down it is there, and a new stub keeps what it says', (t) async {
      final phone = Phone(status: Backend.down, session: Session(meId, testMe()));
      await openRecord(t, phone);
      await t.scrollUntilVisible(find.byKey(const Key('private-stub')), 300, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('private-stub')));
      await t.pump();
      await t.tap(find.byKey(const Key('stamp-it')));
      await t.pumpAndSettle();
      final diary = phone.container(t).read(diaryProvider);
      expect(diary.stubs, hasLength(1));
      expect(diary.stubs.single.private, isTrue);
      // The ticket shows the lock next to its number.
      expect(lockMark, findsOneWidget);
    });

    testWidgets('on the stub page a signed-in user flips it, and the lock follows', (t) async {
      final phone = Phone(status: Backend.up, session: Session(meId, testMe()));
      await phone.pump(t, const SizedBox());
      final c = phone.container(t);
      final stub = c.read(diaryProvider.notifier).addStub(phone.catalog.byId['Q1']!, const StubDraft());
      await phone.pump(t, StubScreen(stubId: stub.id));
      expect(lockMark, findsNothing);
      final toggle = find.byKey(const Key('private-stub'));
      await t.scrollUntilVisible(toggle, 200, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(toggle);
      await t.pump();
      await t.tap(toggle);
      await t.pump();
      expect(c.read(diaryProvider).stubs.single.private, isTrue);
      expect(lockMark, findsOneWidget);
      await t.tap(toggle);
      await t.pump();
      expect(c.read(diaryProvider).stubs.single.private, isFalse);
    });

    testWidgets('on the stub page a signed-out user has no switch, and a private stub still shows its lock', (t) async {
      final phone = Phone(configured: false);
      await phone.pump(t, const SizedBox());
      final c = phone.container(t);
      final stub = c.read(diaryProvider.notifier).addStub(phone.catalog.byId['Q1']!, const StubDraft(private: true));
      await phone.pump(t, StubScreen(stubId: stub.id));
      expect(find.byKey(const Key('private-stub')), findsNothing);
      expect(lockMark, findsOneWidget);
    });
  });
}
