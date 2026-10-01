import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config.dart';
import '../data/json_file.dart';
import '../data/social.dart';
import '../net/api.dart';
import 'providers.dart';
import 'sync.dart';

// ---------------------------------------------------------------------------
// Backend status

/// State of the optional Talkies server. Only [up] shows online features.
enum Backend { none, unknown, up, down }

/// Sign-in methods the server listed in its last good `/healthz`. Own provider, so the sign-in
/// buttons rebuild when the list changes while the status stays `up`.
class ServerAuth extends Notifier<List<String>> {
  @override
  List<String> build() => const [];
  void set(List<String> methods) => state = methods;
}

final serverAuthProvider = NotifierProvider<ServerAuth, List<String>>(ServerAuth.new, retry: (_, _) => null);

/// How many Settings screens are open. The retry schedule probes for a signed-out user only while one is.
class SettingsOpen extends Notifier<int> {
  @override
  int build() => 0;
  void opened() => state++;
  void closed() => state = max(0, state - 1);
}

final settingsOpenProvider = NotifierProvider<SettingsOpen, int>(SettingsOpen.new, retry: (_, _) => null);

const _probeCache = Duration(seconds: 30);

/// Status of the server. No timers live here: the triggers are Settings
/// ([ensureChecked]), the Shell and app resume, Retry, and the retry schedule
/// of [OnlineLoop]. One probe runs at a time; a result is reused for 30 seconds.
class BackendNotifier extends Notifier<Backend> {
  Future<void>? _probing;
  DateTime? _checkedAt;

  /// `none` when the build has no `TALKIES_API_URL`.
  @override
  Backend build() => ref.watch(apiUrlProvider).isEmpty ? Backend.none : Backend.unknown;

  /// Sign-in methods the server listed (`email`, `google`, `apple`).
  List<String> get auth => ref.read(serverAuthProvider);

  /// When the last probe ended. Null before the first one, and after a failed API call.
  DateTime? get checkedAt => _checkedAt;

  /// True while a Settings screen asks for the server: the retry schedule may probe for a signed-out user then.
  /// The Account group calls [settingsOpened] when it shows and [settingsClosed] when it goes.
  bool get settingsOpen => ref.read(settingsOpenProvider) > 0;
  // Deferred one microtask: a screen calls these from initState and dispose, where Riverpod forbids changes.
  void settingsOpened() => scheduleMicrotask(() {
    if (ref.mounted) ref.read(settingsOpenProvider.notifier).opened();
  });
  void settingsClosed() => scheduleMicrotask(() {
    if (ref.mounted) ref.read(settingsOpenProvider.notifier).closed();
  });

  /// `GET /healthz`. Valid only when the JSON says `ok: true` and the API version of this build.
  /// Never throws. Does nothing without a server in the build.
  Future<void> probe({bool force = false}) {
    if (state == Backend.none) return Future.value();
    final running = _probing;
    if (running != null) return running;
    final at = _checkedAt;
    if (!force && at != null && ref.read(nowProvider)().difference(at) < _probeCache) return Future.value();
    return _probing = _probe().whenComplete(() => _probing = null);
  }

  /// Settings calls this when its Account group shows. It is the one place that may probe for a
  /// signed-out user (once; the cache stops repeats).
  Future<void> ensureChecked() => probe();

  Future<void> _probe() async {
    try {
      final reply = await ref.read(apiProvider).get('/healthz');
      if (!ref.mounted) return;
      final h = Health.tryParse(reply);
      if (h == null) {
        state = Backend.down;
      } else {
        ref.read(serverAuthProvider.notifier).set(h.auth);
        state = Backend.up;
      }
    } catch (_) {
      // ApiOffline or anything unexpected: the server is not usable.
      if (ref.mounted) state = Backend.down;
    } finally {
      if (ref.mounted) _checkedAt = ref.read(nowProvider)();
    }
  }

  /// A call failed on the network or came back 502/503/504.
  void markDown() {
    if (state == Backend.none) return;
    _checkedAt = null;
    state = Backend.down;
  }

  /// A call worked while the status said `down`.
  void markUp() {
    if (state != Backend.none) state = Backend.up;
  }
}

final backendProvider = NotifierProvider<BackendNotifier, Backend>(BackendNotifier.new, retry: (_, _) => null);

// ---------------------------------------------------------------------------
// Tokens

const _kAccess = 'talkies.access';
const _kRefresh = 'talkies.refresh';

/// The access and refresh token. They live only in secure storage, read at the
/// first authenticated call, never before. If storage throws (no keychain,
/// no plugin), they stay in memory and the user signs in again after a restart.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          );

  final FlutterSecureStorage _storage;
  String? _access, _refresh;

  /// The initial read, while it is in flight, and every write queued behind it, so a slow keychain
  /// read can never put stale disk values over a newer save or clear. Once a save or clear has run,
  /// what we hold beats the disk: no further read starts.
  Future<void>? _loading, _tail;
  bool _loaded = false;

  Future<void> _load() {
    if (_loaded) return Future.value();
    return _loading ??= _read();
  }

  Future<void> _read() async {
    try {
      _access = await _storage.read(key: _kAccess);
      _refresh = await _storage.read(key: _kRefresh);
    } catch (_) {
      // Memory only.
    }
  }

  Future<void> _write(Future<void> Function() op) {
    _loaded = true;
    final next = (_tail ?? _loading ?? Future<void>.value()).then((_) => op());
    _tail = next;
    return next;
  }

  Future<String?> get access async {
    await _load();
    return _access;
  }

  Future<String?> get refresh async {
    await _load();
    return _refresh;
  }

  Future<void> save(String access, String refresh) => _write(() async {
    _access = access;
    _refresh = refresh;
    try {
      await _storage.write(key: _kAccess, value: access);
      await _storage.write(key: _kRefresh, value: refresh);
    } catch (_) {
      // Memory only.
    }
  });

  Future<void> clear() => _write(() async {
    _access = _refresh = null;
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
    } catch (_) {
      // Nothing to clear on disk.
    }
  });
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

// ---------------------------------------------------------------------------
// Session

/// Who is signed in. The tokens are not part of it; see [TokenStore].
class Session {
  const Session(this.userId, [this.me]);

  final String userId;

  /// The profile as of the last time the server answered. Shown at once, refreshed by the me controller.
  final Me? me;

  Session withMe(Me me) => Session(userId, me);

  Map<String, dynamic> toJson() => {'user': userId, if (me != null) 'me': me!.toJson()};

  static Session? tryFromJson(Map<String, dynamic>? j) {
    try {
      final id = j?['user'];
      if (id is! String) return null;
      return Session(id, j!['me'] == null ? null : Me.fromJson(j['me'] as Map<String, dynamic>));
    } catch (_) {
      return null;
    }
  }
}

/// What a sign-in or account call came to. The UI picks its own text for each.
enum AuthResult { ok, cancelled, badCode, badRequest, rateLimited, disabled, offline, failed }

AuthResult _authResult(Object e) => switch (e) {
  ApiOffline() => AuthResult.offline,
  ApiError(status: 429) => AuthResult.rateLimited,
  ApiError(code: 'otp_invalid') => AuthResult.badCode,
  ApiError(code: 'provider_disabled') => AuthResult.disabled,
  ApiError(code: 'id_token_invalid') => AuthResult.failed,
  ApiError(status: 400 || 422) => AuthResult.badRequest,
  _ => AuthResult.failed,
};

/// Native Google sign-in: the ID token, or null when the user cancels. Replaced in tests.
final googleTokenProvider = Provider<Future<String?> Function()>((ref) => _googleToken);

/// Native Apple sign-in. [hashedNonce] goes to Apple; the identity token comes back, or null when the user
/// cancels. Replaced in tests.
final appleTokenProvider = Provider<Future<String?> Function(String hashedNonce)>((ref) => _appleToken);

Future<void>? _googleInit;

Future<String?> _googleToken() async {
  final google = GoogleSignIn.instance;
  try {
    await (_googleInit ??= google.initialize(
      clientId: kGoogleClientId.isEmpty ? null : kGoogleClientId,
      serverClientId: kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
    ));
    final account = await google.authenticate();
    return account.authentication.idToken;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  } catch (_) {
    _googleInit = null; // let the next tap start over
    rethrow;
  }
}

/// The authorization code of the most recent Apple sign-in, set by [_appleToken].
/// The server trades it with Apple for a refresh token, so the grant can be
/// revoked when the account is deleted (App Store rule 4.8). Null when the
/// platform or a test fake returned only an identity token.
String? _appleAuthCode;

Future<String?> _appleToken(String hashedNonce) async {
  _appleAuthCode = null;
  try {
    final c = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email],
      nonce: hashedNonce,
    );
    _appleAuthCode = c.authorizationCode;
    return c.identityToken;
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) return null;
    rethrow;
  }
}

String _newNonce() {
  final r = Random.secure();
  return base64Url.encode([for (var i = 0; i < 32; i++) r.nextInt(256)]);
}

/// The signed-in user: loaded from `session.json` when the build has a server, and only then.
class SessionNotifier extends Notifier<Session?> {
  JsonFile? _file;
  Future<bool>? _refreshing;
  Future<Me?>? _loadingMe;

  @override
  Session? build() {
    if (ref.watch(apiUrlProvider).isEmpty) return null;
    final file = _file = JsonFile(File('${ref.watch(docsDirProvider).path}/session.json'));
    return Session.tryFromJson(file.read());
  }

  // Sign in -------------------------------------------------------------------

  /// Sends the one-time code to [email].
  Future<AuthResult> requestCode(String email) => _guard(() async {
    await ref.read(apiProvider).post('/v1/auth/otp', body: OtpRequest(email.trim()).toJson());
    return AuthResult.ok;
  });

  /// Signs in with the code from the email. A wrong code gives [AuthResult.badCode].
  Future<AuthResult> verifyCode(String email, String code) => _guard(() async {
    final body = VerifyRequest(email.trim(), code.replaceAll(RegExp(r'\s'), '')).toJson();
    return _complete(await ref.read(apiProvider).post('/v1/auth/verify', body: body));
  });

  Future<AuthResult> signInWithGoogle() async {
    final String? idToken;
    try {
      idToken = await ref.read(googleTokenProvider)();
    } catch (_) {
      return AuthResult.failed;
    }
    if (idToken == null) return AuthResult.cancelled;
    return _idToken(IdTokenRequest(provider: 'google', idToken: idToken));
  }

  /// The raw nonce goes to the server and its SHA-256 to Apple, which puts it into the token.
  Future<AuthResult> signInWithApple() async {
    final raw = _newNonce();
    final String? idToken;
    try {
      idToken = await ref.read(appleTokenProvider)(sha256.convert(utf8.encode(raw)).toString());
    } catch (_) {
      return AuthResult.failed;
    }
    if (idToken == null) return AuthResult.cancelled;
    // The code rides along so the server can revoke the Apple grant on deletion.
    return _idToken(
      IdTokenRequest(provider: 'apple', idToken: idToken, nonce: raw),
      authorizationCode: _appleAuthCode,
    );
  }

  Future<AuthResult> _idToken(IdTokenRequest r, {String? authorizationCode}) =>
      _guard(() async {
        final body = r.toJson();
        if (authorizationCode != null) body['authorization_code'] = authorizationCode;
        return _complete(await ref.read(apiProvider).post('/v1/auth/id-token', body: body));
      });

  Future<AuthResult> _guard(Future<AuthResult> Function() run) async {
    try {
      return await run();
    } catch (e) {
      return _authResult(e);
    }
  }

  Future<AuthResult> _complete(Object? reply) async {
    final s = AuthSession.fromJson(reply as Map<String, dynamic>);
    await ref.read(tokenStoreProvider).save(s.accessToken, s.refreshToken);
    if (!ref.mounted) return AuthResult.failed;
    state = Session(s.userId);
    _persist();
    // The server makes the profile on the first GET. A failure here is not one for the sign-in.
    await loadMe();
    return AuthResult.ok;
  }

  // Profile -------------------------------------------------------------------

  /// `GET /v1/me`, cached in the session. Null when the call fails. One call at a time.
  Future<Me?> loadMe() => _loadingMe ??= _loadMe().whenComplete(() => _loadingMe = null);

  Future<Me?> _loadMe() async {
    try {
      final me = Me.fromJson(await ref.read(apiProvider).get('/v1/me') as Map<String, dynamic>);
      if (ref.mounted) setMe(me);
      return me;
    } catch (_) {
      return null;
    }
  }

  /// True when the profile is known, loading it first if needed. The sync engine needs it: the server makes
  /// the profile row on the first call.
  Future<bool> ensureMe() async => state?.me != null || await loadMe() != null;

  void setMe(Me me) {
    final s = state;
    if (s == null || s.userId != me.id) return;
    state = s.withMe(me);
    _persist();
  }

  void _persist() {
    final s = state;
    if (s != null) _file?.write(s.toJson());
  }

  /// Waits for the pending `session.json` write.
  Future<void> flush() => _file?.flush() ?? Future.value();

  // Tokens --------------------------------------------------------------------

  /// The access token, read from secure storage the first time.
  Future<String?> accessToken() => ref.read(tokenStoreProvider).access;

  /// After a 401: trades the refresh token for a new pair. One call serves every request that failed
  /// together. [stale] is the access token the failed request used: if it is not the current one,
  /// somebody refreshed already. False means the server refused the refresh and the user is signed out.
  /// Throws [ApiOffline] when the server cannot be reached (the session stays).
  Future<bool> refresh(String? stale) => _refreshing ??= _refresh(stale).whenComplete(() => _refreshing = null);

  Future<bool> _refresh(String? stale) async {
    final tokens = ref.read(tokenStoreProvider);
    final current = await tokens.access;
    if (current != null && current != stale) return true;
    final token = await tokens.refresh;
    if (token == null) {
      await expire();
      return false;
    }
    final Object? reply;
    try {
      reply = await ref.read(apiProvider).post('/v1/auth/refresh', body: RefreshRequest(token).toJson());
    } on ApiError catch (e) {
      // The server is struggling: the session may be fine. Anything else means the token is dead.
      if (e.status >= 500 || e.status == 429) rethrow;
      await expire();
      return false;
    }
    final AuthSession s;
    try {
      s = AuthSession.fromJson(reply as Map<String, dynamic>);
    } catch (e) {
      throw ApiOffline(e); // not a Talkies reply
    }
    if (!ref.mounted) return false;
    await tokens.save(s.accessToken, s.refreshToken);
    return true;
  }

  // Sign out ------------------------------------------------------------------

  /// Signs out. The diary stays on the phone. Tokens and `session.json` go, and `sync.json` is reset to its
  /// device id. Works offline: the server is told on a best effort basis.
  Future<void> signOut() async {
    final clear = _teardown(resetSync: true);
    if (state == null) return;
    try {
      await ref.read(apiProvider).post('/v1/auth/logout').timeout(const Duration(seconds: 3));
    } catch (_) {
      // The tokens expire on their own.
    }
    await clear();
  }

  /// Deletes the account on the server, then signs out like [signOut]. The diary stays on the phone.
  /// The account is only gone when this returns [AuthResult.ok].
  Future<AuthResult> deleteAccount() async {
    final clear = _teardown(resetSync: true);
    try {
      await ref.read(apiProvider).delete('/v1/me');
    } catch (e) {
      // The reply can outlive the provider (app teardown): the server deleted the account,
      // so the sign-out still happens here.
      if (e is ApiOffline && e.cause == 'closed') {
        await clear();
        return AuthResult.ok;
      }
      return _authResult(e);
    }
    await clear();
    return AuthResult.ok;
  }

  /// The session is gone (the server refused the refresh, or the tokens are missing). `sync.json` stays, so
  /// the same account resumes where it stopped and another one is asked about.
  Future<void> expire() => _teardown(resetSync: false)();

  /// Everything the sign-out touches, captured before the first `await`: when the provider is torn down
  /// while the call above is in the air, the cleanup still runs. Only the state flip waits for `mounted`.
  Future<void> Function() _teardown({required bool resetSync}) {
    final file = _file;
    final tokens = ref.read(tokenStoreProvider);
    final sync = resetSync ? ref.read(syncStoreProvider) : null;
    final signedIn = state != null;
    return () async {
      if (!signedIn) return;
      sync?.reset(); // before the flip: the engine reads a clean store
      if (ref.mounted) state = null; // the UI and the engine react now
      try {
        if (_googleInit != null) await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Not signed in with Google.
      }
      await tokens.clear();
      if (file != null) {
        await file.flush();
        if (file.file.existsSync()) file.file.deleteSync();
      }
    };
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new, retry: (_, _) => null);

// ---------------------------------------------------------------------------
// Gates

final signedInProvider = Provider<bool>((ref) => ref.watch(sessionProvider) != null);

/// The one gate for online UI: the server answered and the user is signed in.
final onlineProvider = Provider<bool>((ref) => ref.watch(backendProvider) == Backend.up && ref.watch(signedInProvider));

/// The server answered and nobody is signed in: Settings may offer "Sign in".
final signInVisibleProvider = Provider<bool>(
  (ref) => ref.watch(backendProvider) == Backend.up && !ref.watch(signedInProvider),
);

/// iOS rules apply (Apple first, and Google only beside it). Replaced in tests.
final isIosProvider = Provider<bool>((ref) => Platform.isIOS);

/// The build has what Google needs: the server client id, and on iOS the client id too.
final googleConfiguredProvider = Provider<bool>(
  (ref) => kGoogleServerClientId.isNotEmpty && (!ref.watch(isIosProvider) || kGoogleClientId.isNotEmpty),
);

/// The Sign in with Apple capability was added in Xcode and the build says so.
final appleConfiguredProvider = Provider<bool>((ref) => kAppleSignIn);

final emailVisibleProvider = Provider<bool>(
  (ref) => ref.watch(signInVisibleProvider) && ref.watch(serverAuthProvider).contains('email'),
);

/// Apple shows on iOS only, when the server lists it and the build is set up for it.
final appleVisibleProvider = Provider<bool>(
  (ref) =>
      ref.watch(signInVisibleProvider) &&
      ref.watch(isIosProvider) &&
      ref.watch(appleConfiguredProvider) &&
      ref.watch(serverAuthProvider).contains('apple'),
);

/// Google shows when the server lists it and the build has the ids. On iOS only beside Apple (App Store rule 4.8).
final googleVisibleProvider = Provider<bool>(
  (ref) =>
      ref.watch(signInVisibleProvider) &&
      ref.watch(serverAuthProvider).contains('google') &&
      ref.watch(googleConfiguredProvider) &&
      (!ref.watch(isIosProvider) || ref.watch(appleVisibleProvider)),
);

// ---------------------------------------------------------------------------
// Start and retry schedule

const _resumeProbe = Duration(minutes: 2);

/// What runs in the background once the Shell starts it (see [startOnline]): a probe at start and on resume for a
/// signed-in user, the retry schedule after `down`, and the sync engine. Its timers stop with the provider.
///
/// The retry schedule is one timer that exists only while the status is `down` and a retry is allowed: in the
/// foreground, for a signed-in user or while Settings is open. When the timer fires and no retry is allowed it
/// stops, and the next resume, sign-in or Settings opening starts it again at 30 s.
class OnlineLoop {
  OnlineLoop(this._ref);
  final Ref _ref;
  bool _started = false;
  bool _foreground = true;
  int _attempt = 0;
  Timer? _timer;
  AppLifecycleListener? _life;

  void start() {
    if (_started) return;
    _started = true;
    // No server in the build, or a test that wants no background work: nothing starts.
    if (_ref.read(backendProvider) == Backend.none || !_ref.read(autoRefreshProvider)) return;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || _visible(state);
    _life = AppLifecycleListener(onStateChange: (s) => _foreground = _visible(s), onResume: _onResume);
    _ref.listen(backendProvider, _onBackend);
    _ref.listen(sessionProvider, (was, now) {
      if (now == null || was != null) return;
      _probe(force: false);
      _ensureArmed();
    });
    _ref.listen(settingsOpenProvider, (was, now) {
      if (now > 0 && (was ?? 0) == 0) _ensureArmed();
    });
    _ref.read(syncEngineProvider); // starts the engine
    if (_ref.read(signedInProvider)) _probe(force: true);
  }

  bool _visible(AppLifecycleState s) => s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;

  void _probe({required bool force}) => unawaited(_ref.read(backendProvider.notifier).probe(force: force));

  /// A signed-in user probes on resume, at most every 2 minutes, then the engine syncs.
  void _onResume() {
    if (!_ref.mounted || !_ref.read(signedInProvider)) return;
    final backend = _ref.read(backendProvider.notifier);
    final at = backend.checkedAt;
    final stale = at == null || _ref.read(nowProvider)().difference(at) >= _resumeProbe;
    unawaited(() async {
      if (stale) await backend.probe(force: true);
      if (!_ref.mounted) return;
      _ensureArmed();
      _ref.read(syncEngineProvider.notifier).kick();
    }());
  }

  void _onBackend(Backend? was, Backend now) {
    if (now == Backend.down) {
      if (was != Backend.down) {
        _attempt = 0;
        _arm();
      }
    } else {
      _timer?.cancel();
      _timer = null;
      _attempt = 0;
    }
  }

  /// After `down`: 30 s, 60 s, then every 10 minutes.
  void _arm() {
    _timer?.cancel();
    final delay = switch (_attempt) {
      0 => const Duration(seconds: 30),
      1 => const Duration(seconds: 60),
      _ => const Duration(minutes: 10),
    };
    _timer = Timer(delay, _retry);
  }

  /// Starts the schedule if the server is down and nothing is running it.
  void _ensureArmed() {
    if (!_ref.mounted || _timer != null || _ref.read(backendProvider) != Backend.down) return;
    _attempt = 0;
    _arm();
  }

  Future<void> _retry() async {
    _timer = null;
    if (!_ref.mounted || _ref.read(backendProvider) != Backend.down) return;
    final backend = _ref.read(backendProvider.notifier);
    if (!_foreground || !(_ref.read(signedInProvider) || backend.settingsOpen)) return; // stop until a trigger
    await backend.probe(force: true);
    if (!_ref.mounted || _ref.read(backendProvider) != Backend.down) return;
    _attempt++;
    _arm();
  }

  void dispose() {
    _timer?.cancel();
    _life?.dispose();
  }
}

final onlineLoopProvider = Provider<OnlineLoop>((ref) {
  final loop = OnlineLoop(ref);
  ref.onDispose(loop.dispose);
  return loop;
}, retry: (_, _) => null);

/// The Shell calls this once, after the first frame. Nothing online runs before it.
void startOnline(WidgetRef ref) => ref.read(onlineLoopProvider).start();
