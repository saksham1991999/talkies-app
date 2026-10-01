import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:talkies/data/wire.dart';

/// One request the fake server saw.
class Call {
  const Call(this.method, this.path, this.query, this.headers, this.body);
  final String method, path;
  final Map<String, String> query, headers;
  final String body;

  /// `GET /healthz`.
  String get key => '$method $path';
}

/// What the next call to a path does instead of the normal reply.
class Fault {
  const Fault({this.status, this.body, this.raw, this.error, this.hang = false});

  /// Replies with this status and the JSON [body] (an error envelope by default).
  final int? status;
  final Object? body;

  /// Replies with this raw text (an HTML page, for example).
  final String? raw;

  /// Throws this (a SocketException, for example).
  final Object? error;

  /// Never answers, so the client's timeout fires.
  final bool hang;
}

class _Row {
  _Row(this.kind, this.id, this.ms, this.deleted, this.film, this.data, this.seq);
  final String kind, id;
  final int ms;
  final bool deleted;
  final Map<String, dynamic>? film;
  final Map<String, dynamic> data;
  final int seq;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'updated_at': isoMs(ms),
    'deleted': deleted,
    'film': film,
    'data': data,
    'seq': seq,
  };
}

/// A small Talkies server that lives in memory: `/healthz`, `/v1/auth/*`, `/v1/me`, and `/v1/sync/*` with the
/// real rules (last write wins by `updated_at`, a tie keeps the server row, `updated_at` clamped to now plus 5
/// minutes, one `seq` sequence, conflicts and rejections). Every call is recorded. Errors are injected with
/// [fail], [offline], [health] and [rejectRefresh].
class FakeBackend {
  FakeBackend() {
    client = MockClient(_handle);
  }

  late final MockClient client;

  /// The server clock. Tests move it.
  DateTime now = DateTime.utc(2026, 10, 1, 12);

  final calls = <Call>[];
  int count(String key) => calls.where((c) => c.key == key).length;
  int get total => calls.length;

  /// Number of records in each push request, in order.
  final pushSizes = <int>[];

  /// Runs at the start of every push, before it is judged: a test puts a competing row in here, as if
  /// another phone had pushed between this phone's pull and push.
  void Function()? onPush;

  // Knobs.
  bool offline = false;
  Map<String, dynamic> health = {
    'ok': true,
    'api': 1,
    'auth': ['email', 'google', 'apple'],
  };
  int healthStatus = 200;
  String code = '123456';
  bool rejectRefresh = false;
  int stubLimit = 20000;
  final _faults = <String, List<Fault>>{};

  /// The next call of [key] (`GET /v1/me`) gets [fault].
  void fail(String key, Fault fault) => (_faults[key] ??= []).add(fault);

  // Accounts.
  final _userIds = <String, String>{};
  final _profiles = <String, Map<String, dynamic>>{};
  final _refresh = <String, String>{};
  int _gen = 0, _minGen = 0, _tokens = 0, _next = 0;

  /// All access tokens issued so far stop working (a 401), refresh tokens keep working.
  void expireAccess() => _minGen = ++_gen;

  /// The refresh tokens stop working too.
  void revokeAll() {
    expireAccess();
    _refresh.clear();
  }

  String userIdOf(String email) => _userIds[email.trim().toLowerCase()]!;

  // Sync rows.
  int _seq = 0;
  final _rows = <String, Map<String, _Row>>{};

  List<Map<String, dynamic>> rowsOf(String uid) => [for (final r in (_rows[uid] ?? {}).values) r.toJson()];

  Map<String, dynamic>? row(String uid, String kind, String id) => _rows[uid]?['$kind:$id']?.toJson();

  /// Puts a row in as if another phone had pushed it.
  void putRow(
    String uid,
    String kind,
    String id,
    DateTime at, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? film,
    bool deleted = false,
  }) {
    (_rows[uid] ??= {})['$kind:$id'] = _Row(
      kind,
      id,
      at.millisecondsSinceEpoch,
      deleted,
      film,
      data ?? const {},
      ++_seq,
    );
  }

  // ---------------------------------------------------------------------------

  http.Response _json(int status, [Object? body]) => body == null
      ? http.Response('', status)
      : http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  http.Response _error(int status, String code) => _json(status, {
    'error': {'code': code, 'message': code, 'detail': null},
  });

  String _time() => isoMs(now.millisecondsSinceEpoch);

  Future<http.Response> _handle(http.Request req) async {
    final path = req.url.path;
    final call = Call(req.method, path, req.url.queryParameters, req.headers, req.body);
    calls.add(call);
    if (offline) throw const SocketException('offline');
    final faults = _faults[call.key];
    if (faults != null && faults.isNotEmpty) {
      final f = faults.removeAt(0);
      if (f.error != null) throw f.error!;
      if (f.hang) return Completer<http.Response>().future;
      if (f.raw != null) return http.Response(f.raw!, f.status ?? 200, headers: {'content-type': 'text/html'});
      return _json(
        f.status ?? 500,
        f.body ??
            {
              'error': {'code': 'injected', 'message': 'injected', 'detail': null},
            },
      );
    }

    if (path == '/healthz') return _json(healthStatus, health);
    final Object? body = req.body.isEmpty ? null : jsonDecode(req.body);
    if (path.startsWith('/v1/auth/')) return _auth(path, body, req);
    final uid = _who(req);
    if (uid == null) return _error(401, 'unauthorized');

    switch ('${req.method} $path') {
      case 'GET /v1/me':
        return _json(200, _profiles[uid] ??= _newProfile(uid));
      case 'PATCH /v1/me':
        return _patchMe(uid, body as Map<String, dynamic>);
      case 'DELETE /v1/me':
        _userIds.removeWhere((_, v) => v == uid);
        _profiles.remove(uid);
        _rows.remove(uid);
        _refresh.removeWhere((_, v) => v == uid);
        return _json(204);
      case 'POST /v1/sync/push':
        return _profiles[uid] == null ? _error(409, 'no_profile') : _push(uid, body as Map<String, dynamic>);
      case 'GET /v1/sync/pull':
        return _profiles[uid] == null ? _error(409, 'no_profile') : _pull(uid, call.query);
    }
    return _error(404, 'not_found');
  }

  // Auth.

  Map<String, dynamic> _newProfile(String uid) => {
    'id': uid,
    'handle': null,
    'display_name': null,
    'avatar_color': uid.hashCode.abs() % 11,
    'visibility': 'private',
    'share_ratings': false,
  };

  http.Response _session(String uid) {
    final refresh = 'rt.$uid.${++_tokens}';
    _refresh[refresh] = uid;
    return _json(200, {
      'access_token': 'at.$uid.$_gen',
      'refresh_token': refresh,
      'expires_at': now.millisecondsSinceEpoch ~/ 1000 + 3600,
      'user': {'id': uid},
    });
  }

  http.Response _auth(String path, Object? body, http.Request req) {
    final b = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    switch (path) {
      case '/v1/auth/otp':
        return b['email'] is String ? _json(204) : _error(422, 'invalid_request');
      case '/v1/auth/verify':
        if (b['code'] != code) return _error(400, 'otp_invalid');
        final email = (b['email'] as String).trim().toLowerCase();
        final uid = _userIds[email] ??= '11111111-1111-4111-8111-${(++_next).toString().padLeft(12, '0')}';
        return _session(uid);
      case '/v1/auth/id-token':
        final provider = b['provider'];
        if (provider == 'google' || provider == 'apple') {
          if (!(health['auth'] as List).contains(provider)) return _error(404, 'provider_disabled');
          final uid = _userIds['$provider:${b['id_token']}'] ??=
              '11111111-1111-4111-8111-${(++_next).toString().padLeft(12, '0')}';
          return _session(uid);
        }
        return _error(422, 'invalid_request');
      case '/v1/auth/refresh':
        final uid = rejectRefresh ? null : _refresh.remove(b['refresh_token']);
        return uid == null ? _error(400, 'refresh_invalid') : _session(uid);
      case '/v1/auth/logout':
        return _json(204);
    }
    return _error(404, 'not_found');
  }

  String? _who(http.Request req) {
    final h = req.headers['authorization'];
    if (h == null || !h.startsWith('Bearer at.')) return null;
    final parts = h.substring(10).split('.');
    if (parts.length != 2) return null;
    final uid = parts[0], gen = int.tryParse(parts[1]);
    if (gen == null || gen < _minGen || !_userIds.containsValue(uid)) return null;
    return uid;
  }

  http.Response _patchMe(String uid, Map<String, dynamic> patch) {
    final me = _profiles[uid] ??= _newProfile(uid);
    final handle = patch['handle'];
    if (handle is String) {
      if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(handle)) return _error(422, 'invalid_request');
      final taken = _profiles.entries.any((e) => e.key != uid && e.value['handle'] == handle);
      if (taken) return _error(409, 'handle_taken');
    }
    for (final k in const ['handle', 'display_name', 'avatar_color', 'visibility', 'share_ratings']) {
      if (patch.containsKey(k)) me[k] = patch[k];
    }
    return _json(200, me);
  }

  // Sync.

  http.Response _push(String uid, Map<String, dynamic> body) {
    onPush?.call();
    final records = (body['records'] as List).cast<Map<String, dynamic>>();
    pushSizes.add(records.length);
    if (records.length > 200) return _error(413, 'too_large');
    final conflicts = <Map<String, dynamic>>[];
    final rejected = <Map<String, dynamic>>[];
    final mine = _rows[uid] ??= {};
    final ceiling = now.millisecondsSinceEpoch + const Duration(minutes: 5).inMilliseconds;
    for (final r in records) {
      final kind = r['kind'], id = r['id'];
      String? bad;
      if (!const {'stub', 'wish', 'meta', 'taste'}.contains(kind) || id is! String || id.isEmpty) {
        bad = 'invalid_record';
      } else if (r['updated_at'] is! String || !(r['updated_at'] as String).endsWith('Z') || r['deleted'] is! bool) {
        bad = 'invalid_record';
      } else if (r['data'] is! Map || (r['film'] != null && r['film'] is! Map)) {
        bad = 'invalid_record';
      } else if (r['film'] != null && jsonEncode(r['film']).length > 4096) {
        bad = 'too_large';
      } else if (kind == 'taste' && jsonEncode(r['data']).length > 24 * 1024) {
        bad = 'too_large';
      } else if (kind == 'stub' && !mine.containsKey('stub:$id') && _stubCount(mine) >= stubLimit) {
        bad = 'limit_reached';
      }
      if (bad != null) {
        rejected.add({'kind': kind, 'id': id, 'code': bad});
        continue;
      }
      final key = '$kind:$id';
      final ms = (parseMs(r['updated_at'] as String)).clamp(0, ceiling);
      final old = mine[key];
      if (old != null && ms <= old.ms) {
        conflicts.add(old.toJson());
        continue;
      }
      final deleted = r['deleted'] as bool;
      mine[key] = _Row(
        kind as String,
        id as String,
        ms,
        deleted,
        deleted ? null : r['film'] as Map<String, dynamic>?,
        deleted ? const {} : r['data'] as Map<String, dynamic>,
        ++_seq,
      );
    }
    return _json(200, {'server_time': _time(), 'conflicts': conflicts, 'rejected': rejected});
  }

  int _stubCount(Map<String, _Row> rows) => rows.values.where((r) => r.kind == 'stub' && !r.deleted).length;

  http.Response _pull(String uid, Map<String, String> q) {
    final after = int.tryParse(q['after'] ?? '0') ?? 0;
    final limit = (int.tryParse(q['limit'] ?? '200') ?? 200).clamp(1, 200);
    final rows = [
      for (final r in (_rows[uid] ?? {}).values)
        if (r.seq > after) r,
    ]..sort((a, b) => a.seq.compareTo(b.seq));
    final page = rows.take(limit).toList();
    return _json(200, {
      'server_time': _time(),
      'records': [for (final r in page) r.toJson()],
      'cursor': page.isEmpty ? after : page.last.seq,
      'more': rows.length > limit,
    });
  }
}
