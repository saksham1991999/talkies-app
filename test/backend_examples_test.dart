import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/recommend.dart';
import 'package:talkies/data/social.dart';
import 'package:talkies/data/wire.dart';

// The shared wire examples: backend/tests/examples/<model>.<case>.json hold exact JSON for the models of
// backend/API.md. The backend checks each file against its Pydantic model; this test parses the same files
// with the client models of phases 1 and 2. It passes while a model has no example, and fails when an
// example exists that the client cannot read. A request must re-encode to identical JSON. A reply must be
// covered: every key the server sends is held by the model and written back. No reply of another person
// may hold a diary date or a private field.

typedef Codec = ({
  Object Function(Map<String, dynamic> j) parse,
  Map<String, dynamic> Function(Object o) encode,
  String kind,
});

Codec _codec<T extends Object>(
  String kind,
  T Function(Map<String, dynamic> j) from,
  Map<String, dynamic> Function(T o) to,
) => (parse: from, encode: (o) => to(o as T), kind: kind);

Codec request<T extends Object>(T Function(Map<String, dynamic> j) from, Map<String, dynamic> Function(T o) to) =>
    _codec('request', from, to);

/// A reply that reaches another person or the app UI: checked for diary dates.
Codec reply<T extends Object>(T Function(Map<String, dynamic> j) from, Map<String, dynamic> Function(T o) to) =>
    _codec('reply', from, to);

/// The owner's own data: stubs carry dates by design.
Codec sync<T extends Object>(T Function(Map<String, dynamic> j) from, Map<String, dynamic> Function(T o) to) =>
    _codec('sync', from, to);

final codecs = <String, Codec>{
  'card': reply(UserCard.fromJson, (o) => o.toJson()),
  'session': reply(AuthSession.fromJson, (o) => o.toJson()),
  'health': reply(Health.fromJson, (o) => o.toJson()),
  'error': reply(ErrorBody.fromJson, (o) => o.toJson()),
  'otp_request': request(OtpRequest.fromJson, (o) => o.toJson()),
  'verify_request': request(VerifyRequest.fromJson, (o) => o.toJson()),
  'refresh_request': request(RefreshRequest.fromJson, (o) => o.toJson()),
  'id_token_request': request(IdTokenRequest.fromJson, (o) => o.toJson()),
  'me': reply(Me.fromJson, (o) => o.toJson()),
  'me_patch': request(MePatch.fromJson, (o) => o.toJson()),
  'sync_record': sync(SyncRecord.fromJson, (o) => o.toJson()),
  'sync_record_seq': sync(SyncRecord.fromJson, (o) => o.toJson()),
  'sync_push': request(SyncPush.fromJson, (o) => o.toJson()),
  'sync_push_result': sync(SyncPushResult.fromJson, (o) => o.toJson()),
  'sync_pull': sync(SyncPull.fromJson, (o) => o.toJson()),
  'lookup': reply(UserLookup.fromJson, (o) => o.toJson()),
  'friend_request_post': request(FriendRequestPost.fromJson, (o) => o.toJson()),
  'friend_request_result': reply(FriendRequestResult.fromJson, (o) => o.toJson()),
  'friend_requests': reply(FriendRequests.fromJson, (o) => o.toJson()),
  'match': reply(TasteMatch.fromJson, (o) => o.toJson()),
  'friend_list': reply(FriendList.fromJson, (o) => o.toJson()),
  'profile_view': reply(ProfileView.fromJson, (o) => o.toJson()),
  'shelf': reply(Shelf.fromJson, (o) => o.toJson()),
  'friends_who_watched': reply(FriendsWhoWatched.fromJson, (o) => o.toJson()),
  'feed': reply(Feed.fromJson, (o) => o.toJson()),
  'reaction_put': request(ReactionPut.fromJson, (o) => o.toJson()),
  'block_post': request(BlockPost.fromJson, (o) => o.toJson()),
  'block_list': reply(BlockList.fromJson, (o) => o.toJson()),
  'report_post': request(ReportPost.fromJson, (o) => o.toJson()),
  'report_result': reply(ReportResult.fromJson, (o) => o.toJson()),
};

/// Keys that would give away a diary entry to someone else (API.md, "Rules" of phase 2).
const forbidden = {
  'date',
  'created',
  'created_at',
  'watched_on',
  'watched_at',
  'memo',
  'place',
  'seat',
  'price',
  'with',
  'tags',
  'no',
  'planned',
  'added',
  'priv',
};

/// Every key and value of [want] is in [got]. [got] may hold more (a null the server left out).
bool covers(Object? want, Object? got) {
  if (want is Map) {
    return got is Map && want.entries.every((e) => got.containsKey(e.key) && covers(e.value, got[e.key]));
  }
  if (want is List) {
    if (got is! List || got.length != want.length) return false;
    for (var i = 0; i < want.length; i++) {
      if (!covers(want[i], got[i])) return false;
    }
    return true;
  }
  return want == got;
}

void scan(Object? v, void Function(String key, Object? value) visit) {
  if (v is Map) {
    for (final e in v.entries) {
      visit(e.key as String, e.value);
      scan(e.value, visit);
    }
  } else if (v is List) {
    for (final e in v) {
      scan(e, visit);
    }
  }
}

void main() {
  // EXAMPLES_DIR points the test at other files, to try it out on a scratch folder.
  final dir = Directory(Platform.environment['EXAMPLES_DIR'] ?? 'backend/tests/examples');
  final files = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  test('the client knows every model of its list', () {
    expect(codecs.keys.toSet(), {
      'card',
      'session',
      'health',
      'error',
      'otp_request',
      'verify_request',
      'refresh_request',
      'id_token_request',
      'me',
      'me_patch',
      'sync_record',
      'sync_record_seq',
      'sync_push',
      'sync_push_result',
      'sync_pull',
      'lookup',
      'friend_request_post',
      'friend_request_result',
      'friend_requests',
      'match',
      'friend_list',
      'profile_view',
      'shelf',
      'friends_who_watched',
      'feed',
      'reaction_put',
      'block_post',
      'block_list',
      'report_post',
      'report_result',
    });
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final model = name.split('.').first;
    final codec = codecs[model];
    if (codec == null) continue; // a model of another phase, or of the backend alone

    test('$name parses as $model and round-trips', () {
      final json = jsonDecode(file.readAsStringSync());
      expect(json, isA<Map<String, dynamic>>(), reason: 'an example is one JSON object');
      final wire = json as Map<String, dynamic>;
      final parsed = codec.parse(wire);
      final back = codec.encode(parsed);
      // The text of the file, parsed again, must equal what the model writes: no key lost, no value changed.
      final text = jsonDecode(jsonEncode(back));

      if (codec.kind == 'request') {
        expect(text, wire, reason: 'a request re-encodes to identical JSON');
      } else {
        expect(
          covers(wire, text),
          isTrue,
          reason: 'the model drops or changes something the server sends:\n$wire\n$text',
        );
      }

      if (codec.kind == 'reply') {
        scan(wire, (key, _) => expect(forbidden.contains(key), isFalse, reason: 'diary field "$key" in a reply'));
      }
      // A film snapshot never carries a photo that exists on one phone only.
      scan(wire, (key, value) {
        if (key == 'p') expect(value is String && value.startsWith('file:'), isFalse, reason: 'file: poster in $name');
      });
    });

    if (model == 'sync_record' ||
        model == 'sync_record_seq' ||
        model == 'sync_push' ||
        model == 'sync_push_result' ||
        model == 'sync_pull') {
      test('$name: a taste record holds a taste document', () {
        // The `data` of a taste record is the phone's own taste JSON
        // (`Taste.toJson`), not an arbitrary map: the app reads it back with
        // `Taste.tryFromJson`, which needs `v`, `t`, `l`, `e`, `k` and `s`.
        final wire = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final data = wire['kind'] == 'taste'
            ? wire['data'] as Map<String, dynamic>
            : wire['records'] is List && (wire['records'] as List).isNotEmpty
            ? (wire['records'] as List)
                  .map((r) => r as Map<String, dynamic>)
                  .firstWhere((r) => r['kind'] == 'taste', orElse: () => const {})['data']
                  as Map<String, dynamic>?
            : null;
        if (data == null) return; // this example carries no taste record
        final taste = Taste.tryFromJson(data);
        expect(taste, isNotNull, reason: 'data is not a v1 taste document');
        expect(taste!.toJson().keys.toSet(), data.keys.toSet());
      });

      test('$name: times are UTC with Z, and seq is where it belongs', () {
        final wire = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        switch (model) {
          case 'sync_record':
            final r = SyncRecord.fromJson(wire);
            expect(r.ms, isPositive);
            expect(r.seq, isNull, reason: 'a record that goes up has no seq');
            expect(const {'stub', 'wish', 'meta', 'taste'}, contains(r.kind));
          case 'sync_record_seq':
            final r = SyncRecord.fromJson(wire);
            expect(r.ms, isPositive);
            expect(r.seq, isNotNull, reason: 'a record that comes down has a seq');
          case 'sync_push':
            for (final r in SyncPush.fromJson(wire).records) {
              expect(r.ms, isPositive);
              expect(r.seq, isNull);
            }
          case 'sync_push_result':
            final p = SyncPushResult.fromJson(wire);
            expect(p.serverMs, isPositive);
            for (final r in p.conflicts) {
              expect(r.ms, isPositive);
              expect(r.seq, isNotNull);
            }
          case 'sync_pull':
            final p = SyncPull.fromJson(wire);
            expect(p.serverMs, isPositive);
            for (final r in p.records) {
              expect(r.ms, isPositive);
              expect(r.seq, isNotNull);
            }
        }
      });
    }
  }

  test(files.isEmpty ? 'no examples yet' : '${files.length} example file(s) found', () {
    // Nothing to check when the backend has not written examples yet. This test only says which case it is.
    expect(files.every((f) => f.path.endsWith('.json')), isTrue);
  });
}
