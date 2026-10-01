import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../state/online.dart';

/// Everything [Api] throws. The UI never shows one: callers catch it, and the
/// backend status hides online features when the server cannot be reached.
sealed class ApiException implements Exception {
  const ApiException();
}

/// No network, timeout, 502/503/504, or a reply that does not come from a Talkies server.
class ApiOffline extends ApiException {
  const ApiOffline([this.cause]);
  final Object? cause;
  @override
  String toString() => 'ApiOffline($cause)';
}

/// 401 after one refresh attempt: the session is gone.
class ApiUnauthorized extends ApiException {
  const ApiUnauthorized();
  @override
  String toString() => 'ApiUnauthorized';
}

/// Any other non-2xx reply: status, the `error.code` of the body, its message and detail.
class ApiError extends ApiException {
  const ApiError(this.status, this.code, this.message, [this.detail]);
  final int status;
  final String code;
  final String message;
  final Object? detail;
  @override
  String toString() => 'ApiError($status $code)';
}

/// JSON over HTTP to the Talkies server (see backend/API.md). Every method
/// returns the decoded JSON (a Map or List), or null for 204, and throws an
/// [ApiException]. Paths start with `/v1/...`. The real client is `HttpApi`;
/// tests implement this class with a fake.
abstract class Api {
  Future<Object?> get(String path, {Map<String, String>? query});
  Future<Object?> post(String path, {Object? body});
  Future<Object?> put(String path, {Object? body});
  Future<Object?> patch(String path, {Object? body});
  Future<Object?> delete(String path);
}

/// The HTTP client. Tests replace it with a `MockClient`.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Base URL of the Talkies server. Empty means the app has no server. Tests override it.
final apiUrlProvider = Provider<String>((ref) => kApiUrl);

final apiProvider = Provider<Api>((ref) => HttpApi(ref));

const _healthTimeout = Duration(seconds: 4);
const _timeout = Duration(seconds: 15);

typedef _Reply = ({int status, String body});

/// The real [Api]. It enforces the gate itself, so no screen can bypass it:
/// - status `none` (no server in this build): [ApiOffline], no I/O at all;
/// - no session: only `/healthz` and `/v1/auth/*` may be called, else [ApiUnauthorized] with no I/O;
/// - a transport failure, 502/503/504, or a body that is not JSON: the backend is marked down and
///   [ApiOffline] is thrown.
class HttpApi implements Api {
  HttpApi(this._ref);
  final Ref _ref;

  @override
  Future<Object?> get(String path, {Map<String, String>? query}) => _call('GET', path, query: query);
  @override
  Future<Object?> post(String path, {Object? body}) => _call('POST', path, body: body);
  @override
  Future<Object?> put(String path, {Object? body}) => _call('PUT', path, body: body);
  @override
  Future<Object?> patch(String path, {Object? body}) => _call('PATCH', path, body: body);
  @override
  Future<Object?> delete(String path) => _call('DELETE', path);

  Future<Object?> _call(String method, String path, {Map<String, String>? query, Object? body}) async {
    _live();
    if (_ref.read(backendProvider) == Backend.none) throw const ApiOffline('no server in this build');
    // The probe needs no session, so it never reads one (or the disk behind it).
    if (path == '/healthz') return _decode(await _send(method, path, query, body, null), anonymous: true);

    final authPath = path.startsWith('/v1/auth/');
    final session = _ref.read(sessionProvider.notifier);
    final signedIn = _ref.read(sessionProvider) != null;
    if (!authPath && !signedIn) throw const ApiUnauthorized();

    // Tokens are read lazily: a signed-out user never touches secure storage.
    String? token = signedIn ? await session.accessToken() : null;
    _live();
    if (!authPath && token == null) {
      await session.expire();
      throw const ApiUnauthorized();
    }

    var reply = await _send(method, path, query, body, token);
    if (reply.status == 401 && !authPath) {
      // One refresh for every request that failed at the same time, then one retry.
      if (!await session.refresh(token)) throw const ApiUnauthorized();
      _live();
      token = await session.accessToken();
      _live();
      reply = await _send(method, path, query, body, token);
      if (reply.status == 401) {
        await session.expire();
        throw const ApiUnauthorized();
      }
    }
    return _decode(reply);
  }

  /// The provider is gone (tests, app teardown): fail like a lost connection.
  void _live() {
    if (!_ref.mounted) throw const ApiOffline('closed');
  }

  Uri _uri(String path, Map<String, String>? query) {
    var base = _ref.read(apiUrlProvider);
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final u = Uri.parse(base);
    // An http:// TALKIES_API_URL (config.dart) is a build misconfiguration, not a user action:
    // refused like a dead server, never sent to. In debug the assert names it.
    if (u.scheme == 'http') throw const ApiOffline('TALKIES_API_URL must be https');
    assert(u.scheme == 'https', 'TALKIES_API_URL must be https');
    return u.replace(path: '${u.path}$path', queryParameters: query == null || query.isEmpty ? null : query);
  }

  Future<_Reply> _send(String method, String path, Map<String, String>? query, Object? body, String? token) async {
    final request = http.Request(method, _uri(path, query))..headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final client = _ref.read(httpClientProvider);
    try {
      final res = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(path == '/healthz' ? _healthTimeout : _timeout);
      // Decode bytes as UTF-8 ourselves: `Response.body` falls back to Latin-1 without a charset.
      return (status: res.statusCode, body: utf8.decode(res.bodyBytes, allowMalformed: true));
    } on TimeoutException catch (e) {
      throw _down(e);
    } on IOException catch (e) {
      // SocketException, HandshakeException and friends.
      throw _down(e);
    } on http.ClientException catch (e) {
      throw _down(e);
    }
  }

  ApiOffline _down(Object cause) {
    if (_ref.mounted) _ref.read(backendProvider.notifier).markDown();
    return ApiOffline(cause);
  }

  Object? _decode(_Reply r, {bool anonymous = false}) {
    _live();
    final s = r.status;
    if (s == 502 || s == 503 || s == 504) throw _down('HTTP $s');
    Object? json;
    if (r.body.trim().isNotEmpty) {
      try {
        json = jsonDecode(r.body);
      } on FormatException {
        // An HTML page from a proxy or a captive portal is not our server.
        throw _down('not JSON (HTTP $s)');
      }
    }
    if (s >= 200 && s < 300) {
      // A call that worked proves the server is back. /healthz is judged by the probe.
      if (!anonymous && _ref.read(backendProvider) == Backend.down) _ref.read(backendProvider.notifier).markUp();
      return json;
    }
    final e = json is Map ? json['error'] : null;
    if (e is Map) {
      throw ApiError(
        s,
        e['code'] is String ? e['code'] as String : 'error',
        e['message']?.toString() ?? '',
        e['detail'],
      );
    }
    throw ApiError(s, 'http_$s', '', json);
  }
}
