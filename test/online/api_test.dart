import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:talkies/data/social.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/social.dart';
import 'package:talkies/state/sync.dart';

import '../support/device.dart';
import '../support/fake_backend.dart';

const _url = 'https://talkies.test';

/// A container with a server URL and the fake server, and nothing else (no documents folder).
ProviderContainer probeOnly(FakeBackend server, {Clock? clock}) {
  final c = ProviderContainer.test(
    overrides: [
      apiUrlProvider.overrideWithValue(_url),
      httpClientProvider.overrideWithValue(server.client),
      if (clock != null) nowProvider.overrideWithValue(clock.call),
    ],
  );
  return c;
}

Future<Device> signedIn(FakeBackend server, {List<Override> overrides = const []}) async {
  final d = Device(server, overrides: overrides);
  await d.signIn();
  return d;
}

/// An http client whose [method] requests wait for [gate]: the server answer is in the air.
class _GatedClient extends http.BaseClient {
  _GatedClient(this.inner, this.gate, this.method);
  final http.Client inner;
  final Completer<void> gate;
  final String method;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == method) await gate.future;
    return inner.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a build pointed at http:// is a misconfiguration: refused like a dead server', () async {
    final server = FakeBackend();
    final c = probeOnly(server);
    addTearDown(c.dispose);
    c.updateOverrides([
      apiUrlProvider.overrideWithValue('http://talkies.test'),
      httpClientProvider.overrideWithValue(server.client),
    ]);
    await c.read(backendProvider.notifier).probe(force: true);
    expect(c.read(backendProvider), Backend.down);
    expect(server.calls, isEmpty); // nothing went to the wire
  });

  group('a build with no server', () {    test('makes no request, whatever the app does', () async {
      final server = FakeBackend();
      final dir = Directory.systemTemp.createTempSync('talkies_none');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = ProviderContainer.test(
        overrides: [
          apiUrlProvider.overrideWithValue(''),
          httpClientProvider.overrideWithValue(server.client),
          docsDirProvider.overrideWithValue(dir),
          autoRefreshProvider.overrideWithValue(true),
          googleTokenProvider.overrideWithValue(() async => 'google-token'),
          appleTokenProvider.overrideWithValue((_) async => 'apple-token'),
        ],
      );
      final b = c.read(backendProvider.notifier);
      c.read(onlineLoopProvider).start();
      await b.probe();
      await b.probe(force: true);
      await b.ensureChecked();
      await expectLater(c.read(apiProvider).get('/healthz'), throwsA(isA<ApiOffline>()));
      await expectLater(c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiOffline>()));
      await expectLater(c.read(apiProvider).post('/v1/auth/otp', body: {'email': 'a@b.c'}), throwsA(isA<ApiOffline>()));

      final s = c.read(sessionProvider.notifier);
      expect(await s.requestCode('a@b.c'), AuthResult.offline);
      expect(await s.verifyCode('a@b.c', '123456'), AuthResult.offline);
      expect(await s.signInWithGoogle(), AuthResult.offline);
      expect(await s.signInWithApple(), AuthResult.offline);

      await c.read(syncEngineProvider.notifier).run();
      await c.read(syncRunProvider)();
      await c.read(syncEngineProvider.notifier).pushTaste();
      await c.read(friendsProvider.notifier).refresh();
      await c.read(feedProvider.notifier).load();
      await c.read(meProvider.notifier).load();
      await c.read(blocksProvider.notifier).load();
      await c.read(profileProvider('x').notifier).load();
      await c.read(shelfProvider('x').notifier).load();
      await c.read(friendsWhoWatchedProvider.notifier).ensure('Q1');
      final report = await c
          .read(reportProvider.notifier)
          .submit(const ReportPost(kind: ReportKind.user, targetId: 'x', reason: ReportReason.spam));
      expect(report.outcome, CallOutcome.offline);

      expect(server.total, 0);
      expect(c.read(backendProvider), Backend.none);
      expect(c.read(onlineProvider), isFalse);
    });
  });

  group('signed out', () {
    test('no request until Settings asks, then exactly one anonymous GET /healthz', () async {
      final server = FakeBackend();
      final d = Device(server);
      d.c.read(onlineLoopProvider).start();
      for (final ProviderListenable<Object?> p in [
        backendProvider,
        signedInProvider,
        onlineProvider,
        signInVisibleProvider,
        googleVisibleProvider,
        appleVisibleProvider,
        emailVisibleProvider,
      ]) {
        d.c.read(p);
      }
      await d.engine.run();
      await d.c.read(friendsProvider.notifier).refresh();
      expect(server.total, 0);
      expect(d.c.read(backendProvider), Backend.unknown);
      expect(d.c.read(signInVisibleProvider), isFalse);

      await d.backend.ensureChecked();
      expect(server.calls.map((c) => c.key), ['GET /healthz']);
      expect(server.calls.single.headers.containsKey('authorization'), isFalse);
      expect(d.c.read(backendProvider), Backend.up);
      expect(d.c.read(signInVisibleProvider), isTrue);
      expect(d.backend.auth, ['email', 'google', 'apple']);

      await d.backend.ensureChecked(); // the result is fresh
      expect(server.total, 1);
    });

    test('only /healthz and /v1/auth/* may be called; the rest throws with no I/O', () async {
      final server = FakeBackend();
      final d = Device(server);
      final api = d.c.read(apiProvider);
      await expectLater(api.get('/v1/me'), throwsA(isA<ApiUnauthorized>()));
      await expectLater(api.get('/v1/sync/pull', query: {'after': '0'}), throwsA(isA<ApiUnauthorized>()));
      await expectLater(api.delete('/v1/me'), throwsA(isA<ApiUnauthorized>()));
      expect(server.total, 0);
      await api.post('/v1/auth/otp', body: {'email': 'a@b.c'});
      await api.get('/healthz');
      expect(server.calls.map((c) => c.key), ['POST /v1/auth/otp', 'GET /healthz']);
      expect(d.storage.reads, 0); // a signed-out user never touches secure storage
    });
  });

  test('the base URL may carry a path and a trailing slash, and the query is encoded', () async {
    final server = FakeBackend();
    final c = ProviderContainer.test(
      overrides: [
        apiUrlProvider.overrideWithValue('https://talkies.test/prefix/'),
        httpClientProvider.overrideWithValue(server.client),
      ],
    );
    final api = c.read(apiProvider);
    await expectLater(
      api.get('/healthz', query: {'q': 'a b&c', 'x': 'é'}),
      throwsA(isA<ApiError>()),
    ); // 404: no such route
    final call = server.calls.single;
    expect(call.path, '/prefix/healthz');
    expect(call.query, {'q': 'a b&c', 'x': 'é'});
    expect(call.headers.containsKey('authorization'), isFalse);
  });

  group('probe', () {
    final cases = <(String, void Function(FakeBackend), bool)>[
      ('ok and the right version', (s) {}, true),
      ('ok:true without api', (s) => s.health = {'ok': true}, false),
      ('api 2', (s) => s.health = {'ok': true, 'api': 2, 'auth': []}, false),
      ('ok:false on a 200', (s) => s.health = {'ok': false, 'api': 1, 'auth': []}, false),
      ('a JSON list', (s) => s.fail('GET /healthz', const Fault(status: 200, body: [1, 2])), false),
      (
        '503 from the database check',
        (s) {
          s.healthStatus = 503;
          s.health = {'ok': false, 'api': 1, 'auth': []};
        },
        false,
      ),
      ('an HTML page', (s) => s.fail('GET /healthz', const Fault(raw: '<html>Sign in to Wi-Fi</html>')), false),
      ('a socket error', (s) => s.fail('GET /healthz', const Fault(error: SocketException('no route'))), false),
      ('a TLS error', (s) => s.fail('GET /healthz', Fault(error: HandshakeException('bad certificate'))), false),
      ('502 from a proxy', (s) => s.fail('GET /healthz', const Fault(status: 502, body: {'x': 1})), false),
    ];
    for (final (name, setup, ok) in cases) {
      test('${ok ? 'up' : 'down'}: $name', () async {
        final server = FakeBackend();
        setup(server);
        final c = probeOnly(server);
        await c.read(backendProvider.notifier).probe();
        expect(c.read(backendProvider), ok ? Backend.up : Backend.down);
        expect(server.total, 1);
      });
    }

    testWidgets('down: a server that never answers, after 4 seconds', (tester) async {
      final server = FakeBackend()..fail('GET /healthz', const Fault(hang: true));
      final c = probeOnly(server);
      final done = c.read(backendProvider.notifier).probe();
      await tester.pump(const Duration(seconds: 3));
      expect(c.read(backendProvider), Backend.unknown);
      await tester.pump(const Duration(seconds: 2));
      await done;
      expect(c.read(backendProvider), Backend.down);
    });

    test('the sign-in methods come from the reply, and a new reply replaces them', () async {
      final server = FakeBackend();
      server.health = {
        'ok': true,
        'api': 1,
        'auth': ['email'],
      };
      final c = probeOnly(server);
      final b = c.read(backendProvider.notifier);
      await b.probe();
      expect(b.auth, ['email']);
      server.health = {
        'ok': true,
        'api': 1,
        'auth': ['email', 'google'],
      };
      await b.probe(force: true);
      expect(c.read(backendProvider), Backend.up);
      expect(c.read(serverAuthProvider), ['email', 'google']);
    });

    test('a result is reused for 30 seconds, force skips that, and one probe runs at a time', () async {
      final server = FakeBackend();
      final clock = Clock(DateTime(2026, 10, 1, 12));
      final c = probeOnly(server, clock: clock);
      final b = c.read(backendProvider.notifier);
      await b.probe();
      clock.advance(const Duration(seconds: 29));
      await b.probe();
      expect(server.total, 1);
      clock.advance(const Duration(seconds: 2));
      await b.probe();
      expect(server.total, 2);
      await b.probe(force: true);
      expect(server.total, 3);
      await Future.wait([b.probe(force: true), b.probe(force: true), b.probe()]);
      expect(server.total, 4);
    });

    test('a failed probe is not retried by anything: one request, then silence', () async {
      final server = FakeBackend()..healthStatus = 503;
      final c = probeOnly(server);
      await c.read(backendProvider.notifier).probe();
      await c.read(backendProvider.notifier).ensureChecked();
      await pumpEventQueue();
      expect(server.total, 1);
      expect(c.read(backendProvider), Backend.down);
    });
  });

  group('every failure to reach the server marks it down', () {
    final faults = <String, Fault>{
      'a socket error': const Fault(error: SocketException('gone')),
      'a timeout': Fault(error: TimeoutException('slow')),
      'a TLS error': Fault(error: HandshakeException('bad certificate')),
      '502': const Fault(
        status: 502,
        body: {
          'error': {'code': 'upstream_unavailable', 'message': 'x', 'detail': null},
        },
      ),
      '503': const Fault(status: 503, body: {'ok': false}),
      '504': const Fault(status: 504, body: {}),
      'an HTML page on a 200': const Fault(raw: '<html></html>', status: 200),
      'an HTML 404': const Fault(raw: '<h1>404</h1>', status: 404),
    };
    for (final e in faults.entries) {
      test(e.key, () async {
        final server = FakeBackend();
        final d = await signedIn(server);
        expect(d.c.read(onlineProvider), isTrue);
        server.fail('GET /v1/me', e.value);
        await expectLater(d.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiOffline>()));
        expect(d.c.read(backendProvider), Backend.down);
        expect(d.c.read(onlineProvider), isFalse);
        expect(d.c.read(signedInProvider), isTrue); // the account stays
      });
    }

    test('other errors parse the envelope and leave the status alone', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      final api = d.c.read(apiProvider);
      server.fail(
        'GET /v1/me',
        const Fault(
          status: 429,
          body: {
            'error': {
              'code': 'rate_limited',
              'message': 'slow down',
              'detail': {'n': 1},
            },
          },
        ),
      );
      await expectLater(
        api.get('/v1/me'),
        throwsA(
          isA<ApiError>().having((e) => [e.status, e.code, e.message, e.detail], 'fields', [
            429,
            'rate_limited',
            'slow down',
            {'n': 1},
          ]),
        ),
      );
      server.fail(
        'GET /v1/me',
        const Fault(
          status: 500,
          body: {
            'error': {'code': 'boom', 'message': 'm', 'detail': null},
          },
        ),
      );
      await expectLater(api.get('/v1/me'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 500)));
      server.fail('GET /v1/me', const Fault(status: 404, body: {'detail': 'Not Found'})); // not our envelope, but JSON
      await expectLater(api.get('/v1/me'), throwsA(isA<ApiError>().having((e) => e.code, 'code', 'http_404')));
      expect(d.c.read(backendProvider), Backend.up);
    });

    test('a call that works while the status says down brings it back, a probe is not needed', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      d.backend.markDown();
      expect(d.c.read(onlineProvider), isFalse);
      await d.c.read(apiProvider).get('/v1/me');
      expect(d.c.read(backendProvider), Backend.up);
    });

    test('the request carries the bearer token, JSON headers and a UTF-8 body', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      await d.c.read(meProvider.notifier).patch(const MePatch(displayName: 'அசோக்'));
      final call = server.calls.lastWhere((c) => c.key == 'PATCH /v1/me');
      expect(call.headers['authorization'], startsWith('Bearer at.'));
      expect(call.headers['content-type'], contains('application/json'));
      expect(call.headers['accept'], 'application/json');
      expect(jsonDecode(call.body), {'display_name': 'அசோக்'});
      expect(d.c.read(meProvider).value!.displayName, 'அசோக்'); // and the reply decodes as UTF-8
    });
  });

  group('a 401', () {
    test('refreshes once and retries once', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      final before = [...d.storage.data.values];
      server.expireAccess();
      final me = await d.c.read(apiProvider).get('/v1/me') as Map<String, dynamic>;
      expect(me['id'], d.c.read(sessionProvider)!.userId);
      expect(server.calls.map((c) => c.key).where((k) => k != 'GET /healthz' && k != 'POST /v1/auth/verify'), [
        'GET /v1/me', // sign-in
        'GET /v1/me', // 401
        'POST /v1/auth/refresh',
        'GET /v1/me',
      ]);
      expect(d.storage.data.values.toList(), isNot(before)); // new tokens are saved
      expect(d.c.read(signedInProvider), isTrue);
    });

    test('three requests that fail together share one refresh', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      server.expireAccess();
      final api = d.c.read(apiProvider);
      final results = await Future.wait([api.get('/v1/me'), api.get('/v1/me'), api.get('/v1/me')]);
      expect(results.every((r) => r is Map), isTrue);
      expect(server.count('POST /v1/auth/refresh'), 1);
    });

    test('a refused refresh signs out and throws; the diary and sync.json stay', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      d.watch('Q1', rating: 4);
      await d.sync();
      await d.flush();
      server.revokeAll();
      await expectLater(d.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiUnauthorized>()));
      expect(d.c.read(signedInProvider), isFalse);
      expect(d.storage.data, isEmpty);
      expect(File('${d.dir.path}/session.json').existsSync(), isFalse);
      expect(d.diary.stubs, hasLength(1));
      // sync.json keeps the account and the acknowledged records: the same account resumes, another is asked.
      final sync = jsonDecode(File('${d.dir.path}/sync.json').readAsStringSync()) as Map<String, dynamic>;
      expect(sync['lastUser'], isNotNull);
      expect((sync['meta'] as Map).isNotEmpty, isTrue);
      expect(d.c.read(backendProvider), Backend.up);
    });

    test('a refresh that cannot reach the server is offline, not a sign-out', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      server.expireAccess();
      server.fail('POST /v1/auth/refresh', const Fault(error: SocketException('gone')));
      await expectLater(d.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiOffline>()));
      expect(d.c.read(signedInProvider), isTrue);
      expect(d.c.read(backendProvider), Backend.down);
      // Back online: the next call refreshes and works.
      await d.c.read(apiProvider).get('/v1/me');
      expect(d.c.read(signedInProvider), isTrue);
    });

    test('a refresh that fails on the server keeps the session', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      server.expireAccess();
      server.fail(
        'POST /v1/auth/refresh',
        const Fault(
          status: 500,
          body: {
            'error': {'code': 'boom', 'message': 'm', 'detail': null},
          },
        ),
      );
      await expectLater(d.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiError>()));
      expect(d.c.read(signedInProvider), isTrue);
    });

    test('a second 401 after a good refresh means the account is gone: sign out', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      const gone = Fault(
        status: 401,
        body: {
          'error': {'code': 'account_deleted', 'message': 'm', 'detail': null},
        },
      );
      server.fail('GET /v1/me', gone);
      server.fail('GET /v1/me', gone);
      await expectLater(d.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiUnauthorized>()));
      expect(server.count('POST /v1/auth/refresh'), 1);
      expect(d.c.read(signedInProvider), isFalse);
    });
  });

  group('tokens', () {
    test('secure storage is read at the first authenticated call, not at start', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      // The profile call at sign-in used the tokens held in memory.
      expect(d.storage.reads, 0);
      await d.restart();
      expect(d.c.read(signedInProvider), isTrue); // from session.json
      d.c.read(onlineLoopProvider).start();
      d.c.read(onlineProvider);
      expect(d.storage.reads, 0);
      await d.c.read(apiProvider).get('/v1/me');
      expect(d.storage.reads, greaterThan(0));
    });

    test('a keychain that throws still signs in, until the app restarts', () async {
      final server = FakeBackend();
      final d = Device(server);
      d.storage.failing = true;
      await d.signIn();
      expect(d.c.read(signedInProvider), isTrue);
      await d.c.read(apiProvider).get('/v1/me'); // tokens live in memory
      await d.restart();
      expect(d.c.read(signedInProvider), isTrue); // session.json is there
      await expectLater(d.c.read(apiProvider).get('/v1/me'), throwsA(isA<ApiUnauthorized>()));
      expect(d.c.read(signedInProvider), isFalse);
    });

    test('session.json and the cached profile survive a restart without a request', () async {
      final server = FakeBackend();
      final d = await signedIn(server);
      final user = d.c.read(sessionProvider)!.userId;
      final calls = server.total;
      await d.restart();
      expect(d.c.read(sessionProvider)!.userId, user);
      expect(d.c.read(sessionProvider)!.me!.id, user);
      expect(d.c.read(meProvider).value!.id, user);
      expect(d.c.read(onlineProvider), isFalse); // the status is unknown until the first probe
      expect(server.total, calls);
    });
  });

  group('signing in', () {
    test('email code: sent, wrong, right with spaces; the profile is made and cached', () async {
      final server = FakeBackend();
      final d = Device(server);
      await d.backend.probe();
      expect(await d.session.requestCode(' me@example.test '), AuthResult.ok);
      expect(jsonDecode(server.calls.last.body), {'email': 'me@example.test'});
      expect(await d.session.verifyCode('me@example.test', '000000'), AuthResult.badCode);
      expect(d.c.read(signedInProvider), isFalse);
      expect(await d.session.verifyCode('me@example.test', ' 123 456 '), AuthResult.ok);
      expect(d.c.read(signedInProvider), isTrue);
      expect(d.c.read(sessionProvider)!.me, isNotNull);
      expect(server.count('GET /v1/me'), 1);
      expect(d.c.read(onlineProvider), isTrue);
      await d.flush();
      expect(
        jsonDecode(File('${d.dir.path}/session.json').readAsStringSync())['user'],
        d.c.read(sessionProvider)!.userId,
      );
    });

    test('server answers: rate limit, offline, a failed profile call is not a failed sign-in', () async {
      final server = FakeBackend();
      final d = Device(server);
      await d.backend.probe();
      server.fail(
        'POST /v1/auth/otp',
        const Fault(
          status: 429,
          body: {
            'error': {'code': 'rate_limited', 'message': 'm', 'detail': null},
          },
        ),
      );
      expect(await d.session.requestCode('a@b.c'), AuthResult.rateLimited);
      server.fail(
        'POST /v1/auth/otp',
        const Fault(
          status: 422,
          body: {
            'error': {'code': 'invalid_request', 'message': 'm', 'detail': null},
          },
        ),
      );
      expect(await d.session.requestCode('nope'), AuthResult.badRequest);
      server.offline = true;
      expect(await d.session.requestCode('a@b.c'), AuthResult.offline);
      expect(d.c.read(backendProvider), Backend.down);
      server.offline = false;
      d.backend.markUp();
      server.fail('GET /v1/me', const Fault(status: 500));
      expect(await d.session.verifyCode('a@b.c', server.code), AuthResult.ok);
      expect(d.c.read(signedInProvider), isTrue);
      expect(d.c.read(sessionProvider)!.me, isNull); // loaded later by the me controller
    });

    test('Google sends the ID token with no nonce; cancel and failure are not sign-ins', () async {
      final server = FakeBackend();
      var answer = 'g-token';
      final d = Device(
        server,
        overrides: [
          googleTokenProvider.overrideWithValue(() async {
            if (answer == 'boom') throw StateError('boom');
            return answer == 'cancel' ? null : answer;
          }),
        ],
      );
      await d.backend.probe();
      answer = 'cancel';
      expect(await d.session.signInWithGoogle(), AuthResult.cancelled);
      answer = 'boom';
      expect(await d.session.signInWithGoogle(), AuthResult.failed);
      expect(server.count('POST /v1/auth/id-token'), 0);
      answer = 'g-token';
      expect(await d.session.signInWithGoogle(), AuthResult.ok);
      expect(jsonDecode(server.calls.firstWhere((c) => c.path == '/v1/auth/id-token').body), {
        'provider': 'google',
        'id_token': 'g-token',
        'access_token': null,
        'nonce': null,
        'authorization_code': null,
      });
      expect(d.c.read(signedInProvider), isTrue);
    });

    test('Apple: the raw nonce goes to the server, its SHA-256 to Apple, a new one every time', () async {
      final server = FakeBackend();
      final hashed = <String>[];
      final d = Device(
        server,
        overrides: [
          appleTokenProvider.overrideWithValue((h) async {
            hashed.add(h);
            return 'apple-token';
          }),
        ],
      );
      await d.backend.probe();
      expect(await d.session.signInWithApple(), AuthResult.ok);
      await d.session.signOut();
      expect(await d.session.signInWithApple(), AuthResult.ok);
      final raws = [
        for (final c in server.calls.where((c) => c.path == '/v1/auth/id-token')) jsonDecode(c.body)['nonce'] as String,
      ];
      expect(raws, hasLength(2));
      expect(raws[0], isNot(raws[1]));
      for (var i = 0; i < 2; i++) {
        expect(raws[i].length, greaterThanOrEqualTo(32));
        expect(hashed[i], sha256.convert(utf8.encode(raws[i])).toString());
        expect(hashed[i], isNot(raws[i]));
      }
      expect(jsonDecode(server.calls.firstWhere((c) => c.path == '/v1/auth/id-token').body)['provider'], 'apple');
    });

    test('a provider the server switched off is disabled, not failed', () async {
      final server = FakeBackend();
      server.health = {
        'ok': true,
        'api': 1,
        'auth': ['email'],
      };
      final d = Device(server, overrides: [appleTokenProvider.overrideWithValue((_) async => 'token')]);
      await d.backend.probe();
      expect(await d.session.signInWithApple(), AuthResult.disabled);
    });
  });

  group('token storage', () {
    test('a slow keychain read cannot put stale tokens over a save that lands during it', () async {
      final storage = MemoryStorage();
      storage.data['talkies.access'] = 'stale';
      storage.data['talkies.refresh'] = 'stale-r';
      final gate = Completer<void>();
      storage.gate = gate;
      final t = TokenStore(storage);
      final first = t.access; // the slow read starts and blocks
      final saved = t.save('fresh', 'fresh-r'); // queues behind it, then wins
      gate.complete();
      await first;
      await saved;
      expect(await t.access, 'fresh');
      expect(await t.refresh, 'fresh-r');
    });

    test('a slow keychain read cannot resurrect a token after a clear', () async {
      final storage = MemoryStorage();
      storage.data['talkies.access'] = 'stale';
      final gate = Completer<void>();
      storage.gate = gate;
      final t = TokenStore(storage);
      final first = t.access;
      final wiped = t.clear();
      gate.complete();
      await first;
      await wiped;
      expect(await t.access, isNull);
      expect(storage.data, isEmpty);
    });
  });

  group('signing out and deleting the account', () {
    Future<Device> filled(FakeBackend server) async {
      final d = await signedIn(server);
      d.watch('Q1', rating: 4);
      d.watch('Q2');
      d.diaryN.toggleWish(d.film('Q3'));
      await d.sync();
      await d.flush();
      return d;
    }

    test('sign out keeps the diary, drops the session and tokens, and resets sync.json to the device id', () async {
      final server = FakeBackend();
      final d = await filled(server);
      final device = d.store.deviceId;
      expect(File('${d.dir.path}/session.json').existsSync(), isTrue);
      await d.session.signOut();
      await d.flush();

      expect(server.count('POST /v1/auth/logout'), 1);
      expect(d.c.read(signedInProvider), isFalse);
      expect(d.diary.stubs, hasLength(2));
      expect(d.diary.wishes, hasLength(1));
      expect(d.storage.data, isEmpty);
      expect(File('${d.dir.path}/session.json').existsSync(), isFalse);
      expect(jsonDecode(File('${d.dir.path}/sync.json').readAsStringSync()), {'deviceId': device});
      expect(d.c.read(signInVisibleProvider), isTrue); // the Account row offers "Sign in" again
    });

    test('sign out works offline', () async {
      final server = FakeBackend();
      final d = await filled(server);
      server.offline = true;
      await d.session.signOut();
      expect(d.c.read(signedInProvider), isFalse);
      expect(d.storage.data, isEmpty);
      expect(d.diary.stubs, hasLength(2));
    });

    test('delete account removes the server data and signs out; the diary stays', () async {
      final server = FakeBackend();
      final d = await filled(server);
      final user = d.c.read(sessionProvider)!.userId;
      expect(server.rowsOf(user), isNotEmpty);
      expect(await d.session.deleteAccount(), AuthResult.ok);
      await d.flush();
      expect(server.rowsOf(user), isEmpty);
      expect(d.c.read(signedInProvider), isFalse);
      expect(d.diary.stubs, hasLength(2));
      expect(jsonDecode(File('${d.dir.path}/sync.json').readAsStringSync()), {'deviceId': d.store.deviceId});
      expect(File('${d.dir.path}/session.json').existsSync(), isFalse);
    });

    test('delete account that cannot reach the server leaves everything as it was', () async {
      final server = FakeBackend();
      final d = await filled(server);
      server.offline = true;
      expect(await d.session.deleteAccount(), AuthResult.offline);
      expect(d.c.read(signedInProvider), isTrue);
      expect(d.storage.data, isNotEmpty);
    });

    test('after a delete the same phone can sign in as a new account and upload its diary', () async {
      final server = FakeBackend();
      final d = await filled(server);
      expect(await d.session.deleteAccount(), AuthResult.ok);
      await d.signIn('other@example.test');
      await d.sync();
      expect(d.syncState, SyncState.idle);
      expect(server.rowsOf(d.c.read(sessionProvider)!.userId).where((r) => r['kind'] == 'stub'), hasLength(2));
    });

    test('delete account finishes its cleanup even when the session dies during the call', () async {
      final server = FakeBackend();
      final gate = Completer<void>();
      final d = Device(server, client: _GatedClient(server.client, gate, 'DELETE'));
      await d.signIn();
      d.watch('Q1');
      await d.sync();
      await d.flush();
      final device = d.store.deviceId;
      final sync = d.c.read(syncStoreProvider);
      final done = d.session.deleteAccount();
      d.c.dispose(); // the app tears the session down while DELETE /v1/me is in the air
      gate.complete();
      expect(await done, AuthResult.ok);
      await sync.flush();
      expect(d.storage.data, isEmpty); // the tokens are gone from the keychain
      expect(File('${d.dir.path}/session.json').existsSync(), isFalse);
      expect(jsonDecode(File('${d.dir.path}/sync.json').readAsStringSync()), {'deviceId': device});
    });
  });

  test('a private stub reaches the server with its flag', () async {
    final server = FakeBackend();
    final d = await signedIn(server);
    final s = d.watch('Q1', private: true);
    await d.sync();
    final row = server.row(d.c.read(sessionProvider)!.userId, 'stub', s.id)!;
    expect((row['data'] as Map)['priv'], isTrue);
  });
}
