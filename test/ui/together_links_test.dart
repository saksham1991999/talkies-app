import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/state/crews_remote.dart';
import 'package:talkies/state/links.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/format.dart' show appVersion;
import 'package:talkies/ui/screens/settings_screen.dart';
import 'package:talkies/ui/shell.dart';

import '../together/helpers.dart' show FakeApi;
import 'together_harness.dart';

/// A link source the test feeds by hand.
class _Links implements LinkSource {
  _Links([this.first]);
  final Uri? first;
  final stream$ = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initial() async => first;

  @override
  Stream<Uri> get stream => stream$.stream;
}

void main() {
  setUpAll(loadFonts);

  test('only a talkies://join link with a good code is read', () {
    expect(joinCodeOf(Uri.parse('talkies://join?code=ABCD2345')), 'ABCD2345');
    expect(joinCodeOf(Uri.parse('talkies://join?code=abcd-2345')), 'ABCD2345');
    expect(joinCodeOf(Uri.parse('talkies://JOIN?code=ABCD2345')), 'ABCD2345');
    expect(joinCodeOf(Uri.parse('talkies://join?code=ABCD234')), isNull, reason: 'seven characters');
    expect(joinCodeOf(Uri.parse('talkies://join?code=ABCD234O')), isNull, reason: 'no letter O in a code');
    expect(joinCodeOf(Uri.parse('talkies://join')), isNull);
    expect(joinCodeOf(Uri.parse('talkies://settings?code=ABCD2345')), isNull);
    expect(joinCodeOf(Uri.parse('https://talkies.test/j/ABCD2345')), isNull);
    expect(joinCodeOf(Uri.parse('https://join?code=ABCD2345')), isNull);
  });

  group('the listener', () {
    test('keeps the code of the link that started the app and of each link after it, and nothing else', () async {
      final links = _Links(Uri.parse('talkies://join?code=ABCD2345'));
      final c = ProviderContainer(
        overrides: [autoRefreshProvider.overrideWithValue(true), linkSourceProvider.overrideWithValue(links)],
      );
      addTearDown(c.dispose);
      c.read(linksProvider).start();
      await pumpEventQueue();
      expect(c.read(pendingJoinProvider), 'ABCD2345');

      for (final other in [
        'https://talkies.test/j/WXYZ9876',
        'talkies://join?code=short',
        'talkies://chat?code=WXYZ9876',
      ]) {
        links.stream$.add(Uri.parse(other));
        await pumpEventQueue();
        expect(c.read(pendingJoinProvider), 'ABCD2345', reason: other);
      }
      links.stream$.addError(Exception('the plugin hiccuped'));
      links.stream$.add(Uri.parse('talkies://join?code=WXYZ9876'));
      await pumpEventQueue();
      expect(c.read(pendingJoinProvider), 'WXYZ9876');
    });

    test('does not start when background work is off, as in tests', () async {
      final links = _Links(Uri.parse('talkies://join?code=ABCD2345'));
      final c = ProviderContainer(
        overrides: [autoRefreshProvider.overrideWithValue(false), linkSourceProvider.overrideWithValue(links)],
      );
      addTearDown(c.dispose);
      c.read(linksProvider).start();
      await pumpEventQueue();
      expect(links.stream$.hasListener, isFalse);
      expect(c.read(pendingJoinProvider), isNull);
    });

    test('a link source that fails is not an error', () async {
      final c = ProviderContainer(
        overrides: [autoRefreshProvider.overrideWithValue(true), linkSourceProvider.overrideWithValue(_Broken())],
      );
      addTearDown(c.dispose);
      c.read(linksProvider).start();
      await pumpEventQueue();
      expect(c.read(pendingJoinProvider), isNull);
    });
  });

  group('what the app does with a waiting code', () {
    Future<Rig> shell(WidgetTester t, {required String apiUrl, FakeApi? api}) async {
      phoneSize(t);
      final fake = api ?? FakeApi();
      fake.routes['GET /healthz'] = (_, _) => {
        'ok': true,
        'api': 1,
        'auth': ['email'],
      };
      fake.routes['GET /v1/groups'] = (_, _) => {'items': <dynamic>[]};
      final r = rig(apiUrl: apiUrl, api: fake);
      r.container.read(settingsProvider.notifier).set((s) => s.copyWith(seenVersion: appVersion));
      await t.pumpWidget(r.app(const Shell()));
      await t.pumpAndSettle();
      return r;
    }

    testWidgets('without a server in the build the link does nothing', (t) async {
      final r = await shell(t, apiUrl: '');
      r.container.read(pendingJoinProvider.notifier).set('ABCD2345');
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(r.container.read(tabProvider), 0);
      expect(r.requests, isEmpty);
    });

    testWidgets('signed out with a server in the build, it waits in Settings, the one place that may ask the server', (
      t,
    ) async {
      final r = await shell(t, apiUrl: 'https://talkies.test');
      r.container.read(pendingJoinProvider.notifier).set('ABCD2345');
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(r.container.read(pendingJoinProvider), 'ABCD2345', reason: 'kept for after sign-in');
    });
  });
}

class _Broken implements LinkSource {
  @override
  Future<Uri?> initial() => Future.error(StateError('no plugin'));

  @override
  Stream<Uri> get stream => Stream.error(StateError('no plugin'));
}
