import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/sync.dart';

import '../support/device.dart';
import '../support/fake_backend.dart';

class Who extends SessionNotifier {
  Who(this.session);
  final Session? session;
  @override
  Session? build() => session;
  void set(Session? s) => state = s;
}

/// An engine that only counts kicks: these tests are about the start and the retry schedule.
class CountingEngine extends SyncEngine {
  int kicks = 0;
  @override
  SyncState build() => SyncState.idle;
  @override
  void kick() => kicks++;
}

class Rig {
  Rig(WidgetTester tester, {bool signedIn = true, bool auto = true, int health = 200}) : _tester = tester {
    server.healthStatus = health;
    who = Who(signedIn ? const Session('u1') : null);
    c = ProviderContainer.test(
      overrides: [
        apiUrlProvider.overrideWithValue('https://talkies.test'),
        httpClientProvider.overrideWithValue(server.client),
        autoRefreshProvider.overrideWithValue(auto),
        nowProvider.overrideWithValue(clock.call),
        sessionProvider.overrideWith(() => who),
        syncEngineProvider.overrideWith(() => engine),
      ],
    );
  }

  final WidgetTester _tester;
  final server = FakeBackend();
  final clock = Clock(DateTime(2026, 10, 1, 12));
  final engine = CountingEngine();
  late final Who who;
  late final ProviderContainer c;

  BackendNotifier get backend => c.read(backendProvider.notifier);
  int get probes => server.count('GET /healthz');

  /// Time passes for the timers and for the clock the app reads.
  Future<void> elapse(Duration d) async {
    clock.advance(d);
    await _tester.pump(d);
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await _tester.pump();
    }
  }

  /// The app goes to the background and comes back, through the states a device passes.
  void background() {
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      _tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  void foreground() {
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      _tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  Future<void> start() async {
    c.read(onlineLoopProvider).start();
    await settle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('with autoRefresh off nothing starts, even for a signed-in user', (tester) async {
    final r = Rig(tester, auto: false);
    await r.start();
    await r.elapse(const Duration(hours: 1));
    expect(r.server.total, 0);
    expect(r.engine.kicks, 0);
  });

  testWidgets('a signed-in user probes at start, and the engine starts', (tester) async {
    final r = Rig(tester);
    await r.start();
    expect(r.probes, 1);
    expect(r.c.read(backendProvider), Backend.up);
    expect(r.c.read(onlineProvider), isTrue);
    // Starting twice changes nothing.
    r.c.read(onlineLoopProvider).start();
    await r.settle();
    expect(r.probes, 1);
  });

  testWidgets('a signed-out user makes no request at start or ever after, until Settings asks', (tester) async {
    final r = Rig(tester, signedIn: false);
    await r.start();
    await r.elapse(const Duration(hours: 3));
    expect(r.server.total, 0);
    await r.backend.ensureChecked();
    expect(r.probes, 1);
  });

  testWidgets('after down a signed-in user probes at 30 s, 60 s later, then every 10 minutes, and stops when up', (
    tester,
  ) async {
    final r = Rig(tester, health: 503);
    await r.start();
    expect(r.probes, 1);
    expect(r.c.read(backendProvider), Backend.down);

    await r.elapse(const Duration(seconds: 29));
    expect(r.probes, 1);
    await r.elapse(const Duration(seconds: 1)); // 30 s
    expect(r.probes, 2);
    await r.elapse(const Duration(seconds: 59));
    expect(r.probes, 2);
    await r.elapse(const Duration(seconds: 1)); // 90 s
    expect(r.probes, 3);
    await r.elapse(const Duration(minutes: 9, seconds: 59));
    expect(r.probes, 3);
    await r.elapse(const Duration(seconds: 1)); // 10 minutes after the last
    expect(r.probes, 4);
    await r.elapse(const Duration(minutes: 10));
    expect(r.probes, 5);

    r.server.healthStatus = 200;
    await r.elapse(const Duration(minutes: 10));
    expect(r.probes, 6);
    expect(r.c.read(backendProvider), Backend.up);
    expect(r.engine.kicks, 0); // the real engine listens for the status itself
    await r.elapse(const Duration(hours: 2));
    expect(r.probes, 6); // up: no timer left
  });

  testWidgets('a signed-out user is retried only while Settings is open', (tester) async {
    final r = Rig(tester, signedIn: false, health: 503);
    await r.start();
    await r.backend.ensureChecked(); // Settings opens: the one probe
    expect(r.probes, 1);
    await r.elapse(const Duration(minutes: 5));
    expect(r.probes, 1); // the 30 s timer fired, found no reason to probe, and stopped

    r.backend.settingsOpened(); // starts the schedule again, at 30 s
    await r.elapse(const Duration(seconds: 29));
    expect(r.probes, 1);
    await r.elapse(const Duration(seconds: 1));
    expect(r.probes, 2);
    await r.elapse(const Duration(seconds: 60));
    expect(r.probes, 3);
    r.backend.settingsClosed();
    await r.elapse(const Duration(minutes: 30)); // the next timer fires, finds Settings closed, and stops
    expect(r.probes, 3);

    r.backend.settingsOpened();
    r.backend.settingsOpened();
    r.backend.settingsClosed(); // one screen is still open
    await r.elapse(const Duration(seconds: 30));
    expect(r.probes, 4);
    r.c.dispose(); // the schedule is still running: stop it before the test ends
  });

  testWidgets('Settings opening for a signed-out user starts the schedule at 30 s', (tester) async {
    final r = Rig(tester, signedIn: false, health: 503);
    await r.start();
    r.backend.settingsOpened();
    await r.backend.ensureChecked();
    await r.elapse(const Duration(seconds: 30));
    expect(r.probes, 2);
    r.server.healthStatus = 200;
    await r.elapse(const Duration(seconds: 60));
    expect(r.probes, 3);
    expect(r.c.read(signInVisibleProvider), isTrue); // the server came back while Settings was open
  });

  testWidgets('in the background nothing is retried; coming back probes at once', (tester) async {
    final r = Rig(tester, health: 503);
    await r.start();
    expect(r.probes, 1);
    r.background();
    await r.elapse(const Duration(minutes: 30));
    expect(r.probes, 1);
    r.server.healthStatus = 200;
    r.foreground();
    await r.settle();
    expect(r.probes, 2); // more than 2 minutes since the last probe
    expect(r.c.read(backendProvider), Backend.up);
    expect(r.engine.kicks, 1); // and the engine syncs after it
  });

  testWidgets('resume probes at most every 2 minutes', (tester) async {
    final r = Rig(tester);
    await r.start();
    expect(r.probes, 1);

    Future<void> resume(Duration after) async {
      await r.elapse(after);
      r.background();
      r.foreground();
      await r.settle();
    }

    await resume(const Duration(seconds: 40));
    expect(r.probes, 1);
    expect(r.engine.kicks, 1); // the engine is still asked to sync
    await resume(const Duration(seconds: 40));
    expect(r.probes, 1);
    await resume(const Duration(seconds: 45)); // 125 s since the probe
    expect(r.probes, 2);
    await resume(const Duration(seconds: 119));
    expect(r.probes, 2);
    await resume(const Duration(seconds: 2));
    expect(r.probes, 3);
  });

  testWidgets('back in the foreground with the server still down, the schedule starts again at 30 s', (tester) async {
    final r = Rig(tester, health: 503);
    await r.start();
    r.background();
    await r.elapse(const Duration(minutes: 5)); // the timer fired in the background and stopped
    expect(r.probes, 1);
    r.foreground(); // more than 2 minutes since the last probe: probe at once, still down, schedule again
    await r.settle();
    expect(r.probes, 2);
    await r.elapse(const Duration(seconds: 30));
    expect(r.probes, 3);
    r.c.dispose();
  });

  testWidgets('signing in while the server is down starts the schedule', (tester) async {
    final r = Rig(tester, signedIn: false, health: 503);
    await r.start();
    await r.backend.ensureChecked();
    await r.elapse(const Duration(minutes: 1)); // stopped: signed out, Settings closed
    expect(r.probes, 1);
    r.who.set(const Session('u1'));
    await r.settle();
    await r.elapse(const Duration(seconds: 30));
    expect(r.probes, greaterThanOrEqualTo(2));
    r.c.dispose();
  });

  testWidgets('a signed-out user does nothing on resume', (tester) async {
    final r = Rig(tester, signedIn: false);
    await r.start();
    r.background();
    r.foreground();
    await r.settle();
    expect(r.server.total, 0);
    expect(r.engine.kicks, 0);
  });

  testWidgets('the timers stop with the provider', (tester) async {
    final r = Rig(tester, health: 503);
    await r.start();
    r.c.dispose(); // a pending retry timer would fail this test
    await r.elapse(const Duration(hours: 1));
    expect(r.probes, 1);
  });
}
