/// How the diary travels to and from the server (backend/API.md, "Sync"): record
/// models, wire ids for custom films, record hashes, and `sync.json`.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'json_file.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Hashes, ids, times

/// First 10 bytes of SHA-1 over the JSON text, as 20 hex characters.
String hashJson(Object? json) =>
    sha1.convert(utf8.encode(jsonEncode(json))).bytes.take(10).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Random id of this install. It keeps custom film ids of two phones apart.
String newDeviceId([Random? random]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = random ?? Random.secure();
  return String.fromCharCodes([for (var i = 0; i < 8; i++) chars.codeUnitAt(r.nextInt(chars.length))]);
}

/// UTC ISO-8601 with milliseconds and `Z`, the only time format the server accepts.
String isoMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

/// Milliseconds of a server time. Rejects a time without `Z`: it would be read as local time.
int parseMs(String iso) {
  if (!iso.endsWith('Z')) throw FormatException('time without Z', iso);
  return DateTime.parse(iso).millisecondsSinceEpoch;
}

// ---------------------------------------------------------------------------
// Wire ids and records of the diary

/// `my:3` becomes `my:<device>.3` on the wire, so two phones' own films never meet.
/// An id that already names another device stays as it is.
String wireFilmId(String id, String device) =>
    id.startsWith('my:') && !id.contains('.') ? 'my:$device.${id.substring(3)}' : id;

/// The reverse. A film of another phone keeps its wire id here, so it needs no map.
String localFilmId(String wire, String device) {
  final p = 'my:$device.';
  return wire.startsWith(p) ? 'my:${wire.substring(p.length)}' : wire;
}

/// The film snapshot of a record. A `file:` poster exists only on this phone and is dropped.
Map<String, dynamic> filmToWire(Film f, String device) {
  final j = f.toJson();
  j['id'] = wireFilmId(f.id, device);
  if (f.posterFile != null) j.remove('p');
  return j;
}

Film filmFromWire(Map<String, dynamic> j, String device) =>
    Film.fromJson({...j, 'id': localFilmId(j['id'] as String, device)});

/// The `data` of a stub record: [Stub.toJson] with the wire film id.
Map<String, dynamic> stubToWire(Stub s, String device) => s.toJson()..['film'] = wireFilmId(s.filmId, device);

Stub stubFromWire(Map<String, dynamic> j, String device) =>
    Stub.fromJson({...j, 'film': localFilmId(j['film'] as String, device)});

Map<String, dynamic> wishToWire(Wish w, String device) => w.toJson()..['film'] = wireFilmId(w.filmId, device);

Wish wishFromWire(Map<String, dynamic> j, String device) =>
    Wish.fromJson({...j, 'film': localFilmId(j['film'] as String, device)});

/// Hash of a stub as the engine compares it. The film snapshot counts only for
/// a custom film, whose edits travel inside the record. A catalog refresh must
/// never look like an edit and overwrite another phone's change.
String stubHash(Stub s, String device, Film? film) {
  final data = stubToWire(s, device);
  return hashJson(film != null && film.isCustom ? {'d': data, 'f': filmToWire(film, device)} : data);
}

String wishHash(Wish w, String device, Film? film) {
  final data = wishToWire(w, device);
  return hashJson(film != null && film.isCustom ? {'d': data, 'f': filmToWire(film, device)} : data);
}

/// The `meta` record: what the diary keeps besides stubs and the watchlist.
/// Custom films are left out of `hidden`: recommendations never offer them.
class MetaDoc {
  const MetaDoc({required this.tags, required this.venues, required this.hidden});

  final List<String> tags;
  final List<Venue> venues;
  final List<String> hidden;

  static MetaDoc of(Diary d) => MetaDoc(
    tags: d.tags,
    venues: d.venues,
    hidden: [
      for (final id in d.hidden)
        if (!id.startsWith('my:')) id,
    ],
  );

  /// The meta of an untouched diary. A phone that still has it has nothing to say yet.
  static final defaults = MetaDoc.of(const Diary());

  factory MetaDoc.fromJson(Map<String, dynamic> j) => MetaDoc(
    tags: ((j['tags'] as List?) ?? const []).cast<String>(),
    venues: ((j['venues'] as List?) ?? const []).map((e) => Venue.fromJson(e as Map<String, dynamic>)).toList(),
    hidden: ((j['hidden'] as List?) ?? const []).cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'tags': tags,
    'venues': [for (final v in venues) v.toJson()],
    'hidden': hidden,
  };

  String get hash => hashJson(toJson());

  /// Both sides, this one first. Used once, on the first sync of a filled phone.
  MetaDoc union(MetaDoc o) => MetaDoc(
    tags: [...tags, ...o.tags.where((t) => !tags.contains(t))],
    venues: [...venues, ...o.venues.where((v) => !venues.any((x) => x.name == v.name))],
    hidden: [...hidden, ...o.hidden.where((h) => !hidden.contains(h))],
  );
}

/// What the sync engine pulled, ready for `DiaryNotifier.applyRemote`. Film ids
/// are local ids; [films] holds snapshots by local id.
class RemoteChanges {
  const RemoteChanges({
    this.stubs = const [],
    this.deletedStubs = const {},
    this.wishes = const [],
    this.deletedWishes = const {},
    this.films = const {},
    this.meta,
  });

  final List<Stub> stubs;
  final Set<String> deletedStubs;
  final List<Wish> wishes;

  /// Film ids of removed watchlist entries.
  final Set<String> deletedWishes;
  final Map<String, Film> films;
  final MetaDoc? meta;

  bool get isEmpty =>
      stubs.isEmpty && deletedStubs.isEmpty && wishes.isEmpty && deletedWishes.isEmpty && films.isEmpty && meta == null;
}

// ---------------------------------------------------------------------------
// API models (backend/API.md: sync_record, sync_record_seq, sync_push, ...)

/// One synced thing. Times stay as text, so a record re-encodes exactly as it arrived.
class SyncRecord {
  const SyncRecord({
    required this.kind,
    required this.id,
    required this.updatedAt,
    this.deleted = false,
    this.film,
    this.data = const {},
    this.seq,
  });

  /// `stub`, `wish`, `meta` or `taste`.
  final String kind;
  final String id;
  final String updatedAt;
  final bool deleted;

  /// Film snapshot, null for a tombstone, `meta` and `taste`.
  final Map<String, dynamic>? film;
  final Map<String, dynamic> data;

  /// Set on records that come from the server.
  final int? seq;

  int get ms => parseMs(updatedAt);

  factory SyncRecord.fromJson(Map<String, dynamic> j) => SyncRecord(
    kind: j['kind'] as String,
    id: j['id'] as String,
    updatedAt: j['updated_at'] as String,
    deleted: j['deleted'] as bool,
    film: j['film'] as Map<String, dynamic>?,
    data: j['data'] as Map<String, dynamic>,
    seq: j['seq'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'updated_at': updatedAt,
    'deleted': deleted,
    'film': film,
    'data': data,
    if (seq != null) 'seq': seq,
  };
}

class SyncPush {
  const SyncPush(this.records);
  final List<SyncRecord> records;

  factory SyncPush.fromJson(Map<String, dynamic> j) =>
      SyncPush([for (final r in j['records'] as List) SyncRecord.fromJson(r as Map<String, dynamic>)]);

  Map<String, dynamic> toJson() => {
    'records': [for (final r in records) r.toJson()],
  };
}

class SyncRejected {
  const SyncRejected({required this.kind, required this.id, required this.code});
  final String kind, id, code;

  factory SyncRejected.fromJson(Map<String, dynamic> j) =>
      SyncRejected(kind: j['kind'] as String, id: j['id'] as String, code: j['code'] as String);

  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'code': code};
}

class SyncPushResult {
  const SyncPushResult({required this.serverTime, required this.conflicts, required this.rejected});
  final String serverTime;

  /// Server rows that kept their place: this push lost.
  final List<SyncRecord> conflicts;
  final List<SyncRejected> rejected;

  int get serverMs => parseMs(serverTime);

  factory SyncPushResult.fromJson(Map<String, dynamic> j) => SyncPushResult(
    serverTime: j['server_time'] as String,
    conflicts: [for (final r in j['conflicts'] as List) SyncRecord.fromJson(r as Map<String, dynamic>)],
    rejected: [for (final r in j['rejected'] as List) SyncRejected.fromJson(r as Map<String, dynamic>)],
  );

  Map<String, dynamic> toJson() => {
    'server_time': serverTime,
    'conflicts': [for (final r in conflicts) r.toJson()],
    'rejected': [for (final r in rejected) r.toJson()],
  };
}

class SyncPull {
  const SyncPull({required this.serverTime, required this.records, required this.cursor, required this.more});
  final String serverTime;
  final List<SyncRecord> records;
  final int cursor;
  final bool more;

  int get serverMs => parseMs(serverTime);

  factory SyncPull.fromJson(Map<String, dynamic> j) => SyncPull(
    serverTime: j['server_time'] as String,
    records: [for (final r in j['records'] as List) SyncRecord.fromJson(r as Map<String, dynamic>)],
    cursor: j['cursor'] as int,
    more: j['more'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'server_time': serverTime,
    'records': [for (final r in records) r.toJson()],
    'cursor': cursor,
    'more': more,
  };
}

// ---------------------------------------------------------------------------
// sync.json

/// What the engine knows about one record. Immutable: a change makes a new entry,
/// so "unchanged since the push" is an identity check.
class SyncEntry {
  const SyncEntry(this.h, this.u, {this.s = 0, this.x = 0});

  /// Hash of the record when it was last seen or edited here.
  final String h;

  /// Edit time in ms on the server clock (local time plus skew).
  final int u;

  /// 0 waits for a push, 1 is acknowledged, 2 was rejected by the server (not retried until it changes).
  final int s;

  /// 1 is a tombstone.
  final int x;

  SyncEntry acked(int u) => SyncEntry(h, u, s: 1, x: x);

  factory SyncEntry.fromJson(Map<String, dynamic> j) =>
      SyncEntry(j['h'] as String, j['u'] as int, s: (j['s'] as int?) ?? 0, x: (j['x'] as int?) ?? 0);

  Map<String, dynamic> toJson() => {'h': h, 'u': u, 's': s, 'x': x};
}

/// `sync.json`: {deviceId, cursor, meta{key:{h,u,s,x}}, lastUser}, plus a few small fields of the engine.
/// Keys: `s:<stub id>`, `w:<wire film id>`, `m` (the meta document).
class SyncStore {
  SyncStore(this._file) {
    final j = _file.read() ?? const <String, dynamic>{};
    deviceId = (j['deviceId'] as String?) ?? newDeviceId();
    cursor = (j['cursor'] as int?) ?? 0;
    lastUser = j['lastUser'] as String?;
    tasteHash = (j['tasteHash'] as String?) ?? '';
    skew = (j['skew'] as int?) ?? 0;
    skewKnown = (j['skewKnown'] as bool?) ?? false;
    metaUnited = (j['metaUnited'] as bool?) ?? false;
    for (final e in ((j['meta'] as Map?) ?? const {}).entries) {
      meta[e.key as String] = SyncEntry.fromJson(e.value as Map<String, dynamic>);
    }
    // The id must outlive a crash: custom films are pushed under it.
    if (j['deviceId'] == null) save();
  }

  final JsonFile _file;

  late String deviceId;

  /// Largest server `seq` this phone has applied.
  int cursor = 0;
  final Map<String, SyncEntry> meta = {};

  /// The account this phone last synced with.
  String? lastUser;

  /// Hash of the taste document on the server, empty when none is there.
  String tasteHash = '';

  /// Server clock minus local clock, ms, from the last `server_time`.
  int skew = 0;
  bool skewKnown = false;

  /// True once the first meta merge (a union on a filled phone) is done.
  bool metaUnited = false;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    if (cursor != 0) 'cursor': cursor,
    if (meta.isNotEmpty) 'meta': {for (final e in meta.entries) e.key: e.value.toJson()},
    if (lastUser != null) 'lastUser': lastUser,
    if (tasteHash.isNotEmpty) 'tasteHash': tasteHash,
    if (skew != 0) 'skew': skew,
    if (skewKnown) 'skewKnown': true,
    if (metaUnited) 'metaUnited': true,
  };

  // ponytail: rewrites the whole file on each change; shard by key if a 20k-stub diary makes it slow
  void save() => _file.write(toJson());

  Future<void> flush() => _file.flush();

  /// Back to the device id alone: the next sign-in starts as a first sync.
  void reset() {
    cursor = 0;
    meta.clear();
    lastUser = null;
    tasteHash = '';
    skew = 0;
    skewKnown = false;
    metaUnited = false;
    save();
  }
}
