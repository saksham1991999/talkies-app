import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/social.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/sync.dart';
import 'package:talkies/ui/screens/account_screen.dart';
import 'package:talkies/ui/screens/settings_screen.dart';

import '../support/fake_api.dart';
import '../support/fake_backend.dart';
import 'online_harness.dart';

/// A sync engine that sits in "which diary?" until the screen answers.
class _AsksWhich extends SyncEngine {
  static AccountChoice? chosen;
  @override
  SyncState build() => SyncState.needsAccountChoice;
  @override
  Future<void> chooseAccount(AccountChoice choice) async {
    chosen = choice;
    state = SyncState.idle;
  }
}

Map<String, dynamic> card(String id, String name, {String? handle, int ink = 0}) => {
  'id': id,
  'handle': handle,
  'display_name': name,
  'avatar_color': ink,
};

/// The routes a signed-in account screen calls, over a profile that PATCH changes.
FakeApi accountApi({Me? me, List<Map<String, dynamic>> blocked = const []}) {
  final profile = (me ?? testMe()).toJson();
  final blocks = [...blocked];
  return FakeApi()
    ..routes['GET /healthz'] = ((_, _) => {
      'ok': true,
      'api': 1,
      'auth': ['email'],
    })
    ..routes['GET /v1/me'] = ((_, _) => profile)
    ..routes['PATCH /v1/me'] = ((_, body) {
      profile.addAll((body as Map).cast<String, dynamic>());
      return profile;
    })
    ..routes['GET /v1/blocks'] = ((_, _) => {'items': blocks})
    ..routes['POST /v1/auth/logout'] = ((_, _) => null)
    ..routes['DELETE /v1/me'] = ((_, _) => null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  Future<void> type(WidgetTester t, String key, String text) async {
    await t.enterText(find.byKey(Key(key)), text);
    await t.pump();
  }

  /// Scrolls the long account list until [f] is built and on screen.
  Future<void> reveal(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(f);
    await t.pump();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await reveal(t, f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester t, String text) async {
    final f = find.text(text);
    await reveal(t, f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  group('signed out', () {
    testWidgets('Settings, Sign in, email, code: the fake server signs the person in', (t) async {
      final phone = Phone();
      await phone.pump(t, const SettingsScreen());
      await t.pumpAndSettle();
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('apple-sign-in')), findsNothing); // not iOS
      expect(find.byKey(const Key('google-sign-in')), findsNothing); // no client ids in the build
      await type(t, 'email', 'meena@example.test');
      await tapKey(t, 'send-code');
      expect(phone.server.count('POST /v1/auth/otp'), 1);
      expect(find.text('We sent a code to meena@example.test.'), findsOneWidget);

      // The sign-in button waits for six digits.
      await type(t, 'code', '1234');
      expect(
        t
            .widget<TextButton>(find.descendant(of: find.byKey(const Key('verify')), matching: find.byType(TextButton)))
            .onPressed,
        isNull,
      );
      await type(t, 'code', phone.server.code);
      await tapKey(t, 'verify');

      expect(phone.server.count('POST /v1/auth/verify'), 1);
      expect(phone.container(t).read(signedInProvider), isTrue);
      expect(find.byKey(const Key('handle')), findsOneWidget);
      await reveal(t, find.text('Sign out'));
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('a wrong code gets a calm line and the form stays', (t) async {
      final phone = Phone(status: Backend.up, auth: ['email']);
      await phone.pump(t, const AccountScreen());
      await type(t, 'email', 'meena@example.test');
      await tapKey(t, 'send-code');
      await type(t, 'code', '000000');
      await tapKey(t, 'verify');
      expect(find.text('That code is not right. Check it and try again.'), findsOneWidget);
      expect(find.byKey(const Key('code')), findsOneWidget);
      expect(phone.container(t).read(signedInProvider), isFalse);
    });

    testWidgets('a bad email is caught on the phone', (t) async {
      final phone = Phone(status: Backend.up, auth: ['email']);
      await phone.pump(t, const AccountScreen());
      await type(t, 'email', 'meena');
      await tapKey(t, 'send-code');
      expect(find.text('Check the email address and try again.'), findsOneWidget);
      expect(phone.server.total, 0);
    });

    testWidgets('the server limit gives a calm message, and sending again later works', (t) async {
      final phone = Phone(status: Backend.up, auth: ['email']);
      phone.server.fail(
        'POST /v1/auth/otp',
        const Fault(
          status: 429,
          body: {
            'error': {'code': 'rate_limited', 'message': 'slow', 'detail': null},
          },
        ),
      );
      await phone.pump(t, const AccountScreen());
      await type(t, 'email', 'meena@example.test');
      await tapKey(t, 'send-code');
      expect(find.text('Too many tries. Wait a few minutes, then try again.'), findsOneWidget);
      expect(find.byKey(const Key('send-code')), findsOneWidget); // still on the first step
      await tapKey(t, 'send-code');
      expect(find.text('Too many tries. Wait a few minutes, then try again.'), findsNothing);
      expect(find.text('We sent a code to meena@example.test.'), findsOneWidget);

      // Resend, and use another email, both from the code step.
      phone.server.fail(
        'POST /v1/auth/otp',
        const Fault(
          status: 429,
          body: {
            'error': {'code': 'rate_limited', 'message': 'slow', 'detail': null},
          },
        ),
      );
      await tapKey(t, 'resend');
      expect(find.text('Too many tries. Wait a few minutes, then try again.'), findsOneWidget);
      await tapKey(t, 'other-email');
      expect(find.byKey(const Key('email')), findsOneWidget);
    });

    testWidgets('no network: the screen turns into the quiet "Can\'t reach Talkies" with Retry', (t) async {
      final phone = Phone();
      await phone.pump(t, const SettingsScreen());
      await t.pumpAndSettle();
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      await type(t, 'email', 'meena@example.test');
      phone.server.offline = true;
      await tapKey(t, 'send-code');
      expect(find.textContaining("Can't reach Talkies"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      phone.server.offline = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('email')), findsOneWidget);
    });

    testWidgets('Google and Apple show only when the server lists them and the build can use them', (t) async {
      Future<void> shows(Phone phone, {required bool google, required bool apple}) async {
        await t.pumpWidget(const SizedBox()); // a fresh scope: the overrides differ from the last phone's
        await phone.pump(t, const AccountScreen());
        expect(find.byKey(const Key('google-sign-in')), google ? findsOneWidget : findsNothing, reason: 'google');
        expect(find.byKey(const Key('apple-sign-in')), apple ? findsOneWidget : findsNothing, reason: 'apple');
      }

      final listed = ['email', 'google', 'apple'];
      // Android with Google ids: Google, no Apple.
      await shows(
        Phone(
          status: Backend.up,
          auth: listed,
          overrides: [isIosProvider.overrideWithValue(false), googleConfiguredProvider.overrideWithValue(true)],
        ),
        google: true,
        apple: false,
      );
      // iOS with both set up: both.
      await shows(
        Phone(
          status: Backend.up,
          auth: listed,
          overrides: [
            isIosProvider.overrideWithValue(true),
            googleConfiguredProvider.overrideWithValue(true),
            appleConfiguredProvider.overrideWithValue(true),
          ],
        ),
        google: true,
        apple: true,
      );
      // iOS with Google ids only: Apple first, or no Google either (App Store rule 4.8).
      await shows(
        Phone(
          status: Backend.up,
          auth: listed,
          overrides: [isIosProvider.overrideWithValue(true), googleConfiguredProvider.overrideWithValue(true)],
        ),
        google: false,
        apple: false,
      );
      // The server lists email only.
      await shows(Phone(status: Backend.up, auth: ['email']), google: false, apple: false);
    });

    testWidgets('Google signs in through the fake server', (t) async {
      final phone = Phone(
        auth: ['email', 'google'],
        status: Backend.up,
        overrides: [
          googleConfiguredProvider.overrideWithValue(true),
          googleTokenProvider.overrideWithValue(() async => 'google-token'),
        ],
      );
      phone.server.health = {
        'ok': true,
        'api': 1,
        'auth': ['email', 'google'],
      };
      await phone.pump(t, const AccountScreen());
      await tapKey(t, 'google-sign-in');
      expect(phone.server.count('POST /v1/auth/id-token'), 1);
      expect(phone.container(t).read(signedInProvider), isTrue);
    });

    testWidgets('cancelling the Google sheet is not an error', (t) async {
      final phone = Phone(
        auth: ['email', 'google'],
        status: Backend.up,
        overrides: [
          googleConfiguredProvider.overrideWithValue(true),
          googleTokenProvider.overrideWithValue(() async => null),
        ],
      );
      await phone.pump(t, const AccountScreen());
      await tapKey(t, 'google-sign-in');
      expect(phone.server.total, 0);
      expect(find.textContaining('Something went wrong'), findsNothing);
      expect(find.byKey(const Key('google-sign-in')), findsOneWidget);
    });
  });

  group('signed in', () {
    Future<(Phone, FakeApi)> open(WidgetTester t, {Me? me, List<Map<String, dynamic>> blocked = const []}) async {
      final api = accountApi(me: me, blocked: blocked);
      final phone = Phone(status: Backend.up, session: Session(meId, me ?? testMe()), api: api);
      await phone.pump(t, const SettingsScreen());
      await t.pumpAndSettle();
      await t.tap(find.text('Meena'));
      await t.pumpAndSettle();
      return (phone, api);
    }

    testWidgets('the header, the fields and what the server holds', (t) async {
      await open(t);
      expect(find.text('@meena'), findsWidgets);
      expect(t.widget<TextField>(find.byKey(const Key('name'))).controller!.text, 'Meena');
      expect(t.widget<TextField>(find.byKey(const Key('handle'))).controller!.text, 'meena');
      expect(find.text('Your diary is in sync.'), findsOneWidget);
    });

    testWidgets('Save is off until something changes; a valid change goes to the server', (t) async {
      final (_, api) = await open(t);
      TextButton save() => t.widget<TextButton>(
        find.descendant(of: find.byKey(const Key('save-profile')), matching: find.byType(TextButton)),
      );
      expect(save().onPressed, isNull);
      await type(t, 'name', 'Meena K');
      await type(t, 'handle', 'MEENA_K');
      expect(t.widget<TextField>(find.byKey(const Key('handle'))).controller!.text, 'meena_k'); // lower case
      expect(save().onPressed, isNotNull);
      await tapKey(t, 'save-profile');
      expect(api.count('PATCH /v1/me'), 1);
      expect(api.bodies.last, {'handle': 'meena_k', 'display_name': 'Meena K'});
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('a handle that breaks the rule is refused on the phone', (t) async {
      final (_, api) = await open(t);
      await type(t, 'handle', 'ab');
      await tapKey(t, 'save-profile');
      expect(find.text('Use 3 to 20 letters, numbers or underscores.'), findsOneWidget);
      expect(api.count('PATCH /v1/me'), 0);
    });

    testWidgets('a taken handle says so under the field', (t) async {
      final (_, api) = await open(t);
      api.routes['PATCH /v1/me'] = (_, _) => throw const ApiError(409, 'handle_taken', 'taken');
      await type(t, 'handle', 'asha');
      await tapKey(t, 'save-profile');
      expect(find.text('That handle is taken. Try another.'), findsOneWidget);
    });

    testWidgets('a stamp ink is one tap, and the chosen one is marked', (t) async {
      final (_, api) = await open(t);
      await tapKey(t, 'ink-3');
      expect(api.bodies.last, {'avatar_color': 3});
      expect(find.byKey(const Key('ink-3')), findsOneWidget);
    });

    testWidgets('Friends only asks first; Private does not', (t) async {
      final (_, api) = await open(t);
      await tapKey(t, 'vis-friends');
      expect(find.text('SWITCH TO FRIENDS ONLY?'), findsOneWidget);
      expect(api.count('PATCH /v1/me'), 0);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(api.count('PATCH /v1/me'), 0);

      await tapKey(t, 'vis-friends');
      await tapKey(t, 'confirm-friends-only');
      expect(api.bodies.last, {'visibility': 'friends'});
      expect(find.text('Friends can see your films and watchlist. Nobody sees a date.'), findsOneWidget);

      await tapKey(t, 'vis-private');
      expect(api.bodies.last, {'visibility': 'private'});
      expect(find.text('Only you can see your films.'), findsOneWidget);
    });

    testWidgets('the ratings switch', (t) async {
      final (_, api) = await open(t);
      await tapKey(t, 'share-ratings');
      expect(api.bodies.last, {'share_ratings': true});
    });

    testWidgets('blocked people list, with Unblock', (t) async {
      final other = card('22222222-2222-4222-8222-000000000002', 'Rohan', handle: 'rohan', ink: 2);
      final (_, api) = await open(t, blocked: [other]);
      await reveal(t, find.text('Rohan'));
      expect(find.text('Rohan'), findsOneWidget);
      api.routes['GET /v1/blocks'] = (_, _) => {'items': <Object>[]};
      api.routes['DELETE /v1/blocks/${other['id']}'] = (_, _) => null;
      await tapKey(t, 'unblock-${other['id']}');
      expect(api.count('DELETE /v1/blocks/${other['id']}'), 1);
      expect(find.text('You have not blocked anyone.'), findsOneWidget);
    });

    testWidgets('Sign out leaves the screen and says so', (t) async {
      final (phone, api) = await open(t);
      await tapText(t, 'Sign out');
      expect(api.count('POST /v1/auth/logout'), 1);
      expect(phone.container(t).read(signedInProvider), isFalse);
      expect(find.text('Signed out. Your diary stays on this phone.'), findsOneWidget);
      expect(find.byKey(const Key('handle')), findsNothing);
    });

    testWidgets('Delete account asks first, then deletes and says so', (t) async {
      final (phone, api) = await open(t);
      await tapText(t, 'Delete account');
      expect(find.text('Delete your account?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(api.count('DELETE /v1/me'), 0);

      await tapText(t, 'Delete account');
      await t.tap(find.byKey(const Key('confirm-delete')));
      await t.pumpAndSettle();
      expect(api.count('DELETE /v1/me'), 1);
      expect(phone.container(t).read(signedInProvider), isFalse);
      expect(find.text('Your account is deleted. Your diary stays on this phone.'), findsOneWidget);
    });

    testWidgets('a failed delete keeps the account and says so', (t) async {
      final (phone, api) = await open(t);
      api.routes['DELETE /v1/me'] = (_, _) => throw const ApiError(500, 'oops', 'oops');
      await tapText(t, 'Delete account');
      await t.tap(find.byKey(const Key('confirm-delete')));
      await t.pumpAndSettle();
      expect(phone.container(t).read(signedInProvider), isTrue);
      expect(find.text('Could not delete your account. Try again.'), findsOneWidget);
    });

    testWidgets('another account on a filled phone: the choice dialog calls chooseAccount', (t) async {
      _AsksWhich.chosen = null;
      final api = accountApi();
      final phone = Phone(
        status: Backend.up,
        session: Session(meId, testMe()),
        api: api,
        overrides: [syncEngineProvider.overrideWith(_AsksWhich.new)],
      );
      await phone.pump(t, const AccountScreen());
      await t.pumpAndSettle();
      expect(find.text('Two diaries'), findsOneWidget);
      await t.tap(find.byKey(const Key('choice-merge')));
      await t.pumpAndSettle();
      expect(_AsksWhich.chosen, AccountChoice.merge);
      expect(find.text('Two diaries'), findsNothing);
    });

    testWidgets('server down: one quiet panel with Retry and Sign out, nothing else', (t) async {
      final api = accountApi();
      final phone = Phone(status: Backend.down, session: Session(meId, testMe()), api: api);
      api.routes['GET /healthz'] = (_, _) => throw const ApiOffline('down');
      await phone.pump(t, const AccountScreen());
      await t.pumpAndSettle();
      expect(find.text('Your diary is safe on this phone. Talkies cannot be reached right now.'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.byKey(const Key('name')), findsNothing);
      expect(find.text('Delete account'), findsNothing);
      expect(api.count('GET /v1/me'), 0);

      api.routes['GET /healthz'] = (_, _) => {
        'ok': true,
        'api': 1,
        'auth': ['email'],
      };
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('name')), findsOneWidget); // the server is back: the whole account
    });
  });
}
