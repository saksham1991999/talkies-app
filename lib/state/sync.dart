import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/json_file.dart';
import '../data/models.dart';
import '../data/recommend.dart';
import '../data/wire.dart';
import '../net/api.dart';
import 'online.dart';
import 'providers.dart';

/// `sync.json`, read once on first use.
final syncStoreProvider = Provider<SyncStore>(
  (ref) => SyncStore(JsonFile(File('${ref.watch(docsDirProvider).path}/sync.json'))),
);

enum SyncState {
  idle,
  syncing,

  /// The last run failed. A retry is scheduled, or waits for the server to come back.
  failed,

  /// A different account signed in on a phone whose diary belongs to another one. Nothing syncs until
  /// the UI calls [SyncEngine.chooseAccount].
  needsAccountChoice,
}

enum AccountChoice {
  /// Upload this phone's diary into the new account and union it with what the account already holds.
  merge,

  /// Replace this phone's diary with the new account's. The old account keeps its copy on the server.
  separate,
}

const _debounce = Duration(seconds: 2);
const _tasteDelay = Duration(seconds: 30);
const _backoff = [
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
];
const _batch = 200;

/// Keeps the diary and the server equal for a signed-in user, as backend/API.md describes.
///
/// A record is a stub (key `s:<id>`), a watchlist entry (`w:<wire film id>`) or the meta document (`m`).
/// [scan] compares every record's hash with `sync.json` and stamps what changed, at edit time and also
/// while offline, so a phone that was away cannot overwrite a newer edit when it returns. A [run] pulls,
/// merges and pushes. Runs only while [onlineProvider] is true, one at a time.
class SyncEngine extends Notifier<SyncState> {
  late SyncStore _store;
  Future<void>? _running;
  bool _again = false;
  bool _kicked = false;
  int _failures = 0;

  /// Records this build cannot read, counted as they are skipped. The cursor does not pass them,
  /// so they stay pending; an update that teaches the format applies them at the next pull.
  int _poison = 0;
  Timer? _debounceTimer, _backoffTimer, _tasteTimer;

  // Hashes by object: an unchanged stub is hashed once, however often the diary changes.
  final _stubHashes = Expando<String>();
  final _wishHashes = Expando<String>();

  @override
  SyncState build() {
    _store = ref.watch(syncStoreProvider);
    ref.onDispose(() {
      _debounceTimer?.cancel();
      _backoffTimer?.cancel();
      _tasteTimer?.cancel();
    });
    ref.listen(diaryProvider, (_, _) => _onDiary());
    ref.listen(sessionProvider.select((s) => s?.userId), (_, user) => _onUser(user));
    // The source providers notify at once; a derived one like onlineProvider waits for the next read.
    ref.listen(backendProvider, (was, now) {
      if (now == Backend.up && was != Backend.up) kick();
    });
    // The first pass needs `state`, which a notifier cannot touch inside build.
    scheduleMicrotask(() {
      if (ref.mounted) _onUser(_user);
    });
    return SyncState.idle;
  }

  String? get _user => ref.read(sessionProvider)?.userId;
  bool get _auto => ref.read(autoRefreshProvider);

  /// Server clock in ms: the local clock plus the skew the last reply showed.
  int _stamp() => ref.read(nowProvider)().millisecondsSinceEpoch + _store.skew;

  /// How many records the engine skipped because this build cannot read them (since sign-in, or
  /// since the last user change). Above zero, they sit before the cursor until an update reads them.
  int get poison => _poison;

  // Triggers ----------------------------------------------------------------

  void _onUser(String? user) {
    _debounceTimer?.cancel();
    _backoffTimer?.cancel();
    _tasteTimer?.cancel();
    _failures = 0;
    _poison = 0;
    if (user == null) {
      state = SyncState.idle;
      return;
    }
    try {
      if (!_checkAccount(user)) return;
      state = SyncState.idle;
      scan();
    } catch (_) {
      // The next run scans again. Nothing here may break the sign-in.
    }
    kick();
    _scheduleTaste();
  }

  void _onDiary() {
    if (_user == null || state == SyncState.needsAccountChoice) return;
    try {
      scan();
    } catch (_) {
      // The next run scans again. An edit must never fail because of the sync.
    }
    if (!_auto) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, kick);
    _scheduleTaste();
  }

  /// Starts a run now (no-op in tests with `autoRefreshProvider` false, and while not online). Kicks of the
  /// same moment (sign-in, status up) make one run.
  void kick() {
    if (!_auto || _kicked) return;
    _kicked = true;
    scheduleMicrotask(() {
      _kicked = false;
      if (ref.mounted) unawaited(run());
    });
  }

  void _retry() {
    if (!_auto) return;
    final delay = _backoff[min(_failures, _backoff.length - 1)];
    _failures++;
    _backoffTimer?.cancel();
    _backoffTimer = Timer(delay, kick);
  }

  /// An account other than the last one signed in on a phone that has a diary: ask first.
  bool _checkAccount(String user) {
    final last = _store.lastUser;
    if (last == user) return true;
    final d = ref.read(diaryProvider);
    if (last != null && (d.stubs.isNotEmpty || d.wishes.isNotEmpty)) {
      state = SyncState.needsAccountChoice;
      return false;
    }
    if (last != null) _store.reset(); // another account, and nothing here to lose: start clean
    _store.lastUser = user;
    _store.save();
    return true;
  }

  /// The answer to [SyncState.needsAccountChoice].
  Future<void> chooseAccount(AccountChoice choice) async {
    final user = _user;
    if (user == null || state != SyncState.needsAccountChoice) return;
    if (choice == AccountChoice.separate) ref.read(diaryProvider.notifier).replaceAll(const Diary());
    _store.reset();
    _store.lastUser = user;
    _store.save();
    state = SyncState.idle;
    scan();
    await run();
  }

  // Stamping ----------------------------------------------------------------

  String _stubHash(Diary d, Stub s) {
    final film = d.films[s.filmId];
    if (film != null && film.isCustom) return stubHash(s, _store.deviceId, film);
    return _stubHashes[s] ??= stubHash(s, _store.deviceId, null);
  }

  String _wishHash(Diary d, Wish w) {
    final film = d.films[w.filmId];
    if (film != null && film.isCustom) return wishHash(w, _store.deviceId, film);
    return _wishHashes[w] ??= wishHash(w, _store.deviceId, null);
  }

  /// Compares the diary with `sync.json`: a changed record is stamped now and waits for a push, a record
  /// that is gone becomes a tombstone. Cheap and local, so it runs on every diary change. Returns whether
  /// anything changed.
  // ponytail: the first scan of a big diary hashes every record on the UI thread; move it into an isolate if 20k stubs stutter
  bool scan() {
    if (_user == null || state == SyncState.needsAccountChoice) return false;
    final d = ref.read(diaryProvider);
    final now = _stamp();
    final meta = _store.meta;
    final live = <String>{};
    var changed = false;
    // Never at or before the record's last stamp: an echo of our own earlier push must not beat a later edit,
    // even if the clock stood still or stepped back.
    int after(String key) => max(now, (meta[key]?.u ?? 0) + 1);
    void touch(String key, String hash) {
      live.add(key);
      final e = meta[key];
      if (e != null && e.x == 0 && e.h == hash) return;
      meta[key] = SyncEntry(hash, after(key));
      changed = true;
    }

    for (final s in d.stubs) {
      touch('s:${s.id}', _stubHash(d, s));
    }
    for (final w in d.wishes) {
      touch('w:${wireFilmId(w.filmId, _store.deviceId)}', _wishHash(d, w));
    }
    // A phone that still has the untouched meta has nothing to say, and must not overwrite the server's.
    final doc = MetaDoc.of(d), h = doc.hash, e = meta['m'];
    if (e == null ? h != MetaDoc.defaults.hash : (e.x == 1 || e.h != h)) {
      meta['m'] = SyncEntry(h, after('m'));
      changed = true;
    }
    for (final e in meta.entries.toList()) {
      if (e.key == 'm' || live.contains(e.key) || e.value.x == 1) continue;
      meta[e.key] = SyncEntry('', after(e.key), x: 1);
      changed = true;
    }
    if (changed) _store.save();
    return changed;
  }

  // Runs ---------------------------------------------------------------------

  /// One sync: pull everything after the cursor, merge, apply to the diary once, push what is pending,
  /// apply the rows the server kept. A failure leaves the work for the next run. Does nothing unless the
  /// server is up and a user is signed in.
  Future<void> run() {
    if (!ref.read(onlineProvider) || state == SyncState.needsAccountChoice) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true; // edits made during this run go in a second pass
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      if (!await _once()) return;
    } while (_again && ref.mounted && ref.read(onlineProvider));
  }

  Future<bool> _once() async {
    final user = _user;
    if (user == null) return false;
    state = SyncState.syncing;
    try {
      if (!_checkAccount(user)) return false;
      // The store may be reset under this run (sign-out, account switch, or
      // the answer to needsAccountChoice). The rows below belong to this
      // account only: stop before writing anything when that happens, and
      // loop once more so the new account still gets its first run.
      final gen = _store.generation;
      bool stale() {
        if (_store.generation == gen) return false;
        _again = true;
        return true;
      }
      // The server makes the profile row on the first GET /v1/me, and records need it.
      if (!await ref.read(sessionProvider.notifier).ensureMe()) throw const ApiOffline('profile unavailable');
      scan();
      final (:records, :cursor) = await _pull();
      if (!ref.mounted) return false;
      // True so the loop takes one fresh pass (a signed-out phone exits it
      // at once); the new account still gets its first run.
      if (stale()) return true;
      final (:changes, :unreadable) = _merge(records);
      _apply(changes);
      // The cursor does not pass a record this build cannot read: the next run refetches it, and an
      // update that teaches the format applies it then.
      if (unreadable.isEmpty) _store.cursor = cursor;
      _poison += unreadable.length;
      _store.save();
      await _push(gen);
      if (!ref.mounted) return false;
      if (stale()) return true;
      // An acknowledged tombstone needs no memory: the server keeps the row that beats older edits.
      _store.meta.removeWhere((_, e) => e.x == 1 && e.s == 1);
      _store.save();
      _failures = 0;
      state = SyncState.idle;
      return true;
    } on ApiUnauthorized {
      if (ref.mounted) state = SyncState.idle; // signed out: nothing to retry
      return false;
    } catch (_) {
      if (ref.mounted) {
        state = SyncState.failed;
        _retry();
      }
      return false;
    }
  }

  void _apply(RemoteChanges c) {
    if (!c.isEmpty) ref.read(diaryProvider.notifier).applyRemote(c);
  }

  /// Every page after the cursor. A record that came twice (it changed between pages) counts once, latest.
  Future<({List<SyncRecord> records, int cursor})> _pull() async {
    final api = ref.read(apiProvider);
    var after = _store.cursor;
    final byKey = <String, SyncRecord>{};
    while (true) {
      final reply = await api.get('/v1/sync/pull', query: {'after': '$after', 'limit': '$_batch'});
      final p = SyncPull.fromJson(reply as Map<String, dynamic>);
      if (!ref.mounted) return (records: const <SyncRecord>[], cursor: after);
      _learnSkew(p.serverMs);
      for (final r in p.records) {
        byKey['${r.kind}:${r.id}'] = r;
      }
      final moved = p.cursor > after;
      after = p.cursor;
      if (!p.more || !moved) break; // a server that says "more" without moving would loop forever
    }
    return (records: byKey.values.toList(), cursor: after);
  }

  void _learnSkew(int serverMs) {
    final k = serverMs - ref.read(nowProvider)().millisecondsSinceEpoch;
    if (!_store.skewKnown) {
      // Stamps made before the first reply used no skew. Move them onto the server clock.
      for (final e in _store.meta.entries.toList()) {
        if (e.value.s == 0) _store.meta[e.key] = SyncEntry(e.value.h, e.value.u + k, x: e.value.x);
      }
      _store.skewKnown = true;
    }
    _store.skew = k;
  }

  static String? _key(String kind, String id) => switch (kind) {
    'stub' => 's:$id',
    'wish' => 'w:$id',
    'meta' => 'm',
    _ => null, // taste is ours alone; unknown kinds come from a newer server
  };

  /// Decides for each remote record whether it replaces the local one, updates `sync.json` for the ones
  /// that do, and returns the changes for the diary plus the records it could not read (see [poison]).
  /// The local record is kept when it is unacknowledged and
  /// strictly newer; a tie takes the server row, as the server does. With [sent] the records are the rows the
  /// server kept over a push: they win, unless the record changed here since it was sent.
  ({RemoteChanges changes, List<SyncRecord> unreadable}) _merge(
    List<SyncRecord> remote, {
    Map<String, SyncEntry>? sent,
  }) {
    final d = ref.read(diaryProvider);
    final catalog = ref.read(catalogProvider).value;
    final dev = _store.deviceId, meta = _store.meta;
    final localStubs = {for (final s in d.stubs) s.id};
    final stubs = <Stub>[], wishes = <Wish>[];
    final delStubs = <String>{}, delWishes = <String>{};
    final films = <String, Film>{};
    MetaDoc? newMeta;
    final unreadable = <SyncRecord>[];

    Film? filmOf(Map<String, dynamic>? snapshot, String localId) =>
        snapshot == null ? (d.films[localId] ?? catalog?.byId[localId]) : filmFromWire(snapshot, dev);

    for (final r in remote) {
      final key = _key(r.kind, r.id);
      if (key == null) continue;
      try {
        final e = meta[key], ms = r.ms;
        final held = sent == null ? e != null && e.s != 1 && e.u > ms : e == null || !identical(e, sent[key]);
        switch (r.kind) {
          case 'meta':
            if (r.deleted) continue;
            final theirs = MetaDoc.fromJson(r.data), mine = MetaDoc.of(d);
            if (sent == null && !_store.metaUnited && mine.hash != MetaDoc.defaults.hash) {
              // The first sync of a filled phone: both sides' tags, venues and hidden films, once.
              final both = mine.union(theirs);
              if (both.hash != mine.hash) newMeta = both;
              // Pending, and newer than the row it was made from, so the server takes it.
              meta[key] = both.hash == theirs.hash
                  ? SyncEntry(both.hash, ms, s: 1)
                  : SyncEntry(both.hash, max(_stamp(), ms + 1));
            } else if (!held) {
              if (theirs.hash != mine.hash) newMeta = theirs;
              meta[key] = SyncEntry(theirs.hash, ms, s: 1);
            }
            _store.metaUnited = true;
          case 'stub':
            if (held) continue;
            if (r.deleted) {
              if (e != null || localStubs.contains(r.id)) {
                delStubs.add(r.id);
                meta[key] = SyncEntry('', ms, s: 1, x: 1);
              }
              continue;
            }
            final stub = stubFromWire(r.data, dev);
            final film = filmOf(r.film, stub.filmId);
            if (film == null) continue; // nothing to show the stub with
            final h = stubHash(stub, dev, film);
            if (e != null && e.x == 0 && e.h == h) {
              meta[key] = e.acked(ms); // the same content: nothing to apply
            } else {
              stubs.add(stub);
              films[stub.filmId] = film;
              meta[key] = SyncEntry(h, ms, s: 1);
            }
          case 'wish':
            if (held) continue;
            final filmId = localFilmId(r.id, dev);
            if (r.deleted) {
              if (e != null || d.wishFor(filmId) != null) {
                delWishes.add(filmId);
                meta[key] = SyncEntry('', ms, s: 1, x: 1);
              }
              continue;
            }
            final wish = wishFromWire(r.data, dev);
            final film = filmOf(r.film, wish.filmId);
            if (film == null) continue;
            final h = wishHash(wish, dev, film);
            if (e != null && e.x == 0 && e.h == h) {
              meta[key] = e.acked(ms);
            } else {
              wishes.add(wish);
              films[wish.filmId] = film;
              meta[key] = SyncEntry(h, ms, s: 1);
            }
        }
      } catch (_) {
        // A record this build cannot read stays pending before the cursor; see [poison].
        unreadable.add(r);
      }
    }
    return (
      changes: RemoteChanges(
        stubs: stubs,
        deletedStubs: delStubs,
        wishes: wishes,
        deletedWishes: delWishes,
        films: films,
        meta: newMeta,
      ),
      unreadable: unreadable,
    );
  }

  SyncRecord? _record(String key, SyncEntry e, Diary d, Map<String, Stub> stubs, Map<String, Wish> wishes) {
    final dev = _store.deviceId, at = isoMs(e.u);
    if (key == 'm') return SyncRecord(kind: 'meta', id: 'meta', updatedAt: at, data: MetaDoc.of(d).toJson());
    final id = key.substring(2);
    if (key.startsWith('s:')) {
      if (e.x == 1) return SyncRecord(kind: 'stub', id: id, updatedAt: at, deleted: true);
      final s = stubs[id], film = s == null ? null : d.films[s.filmId];
      if (s == null || film == null) return null;
      return SyncRecord(kind: 'stub', id: id, updatedAt: at, film: filmToWire(film, dev), data: stubToWire(s, dev));
    }
    if (e.x == 1) return SyncRecord(kind: 'wish', id: id, updatedAt: at, deleted: true);
    final w = wishes[localFilmId(id, dev)], film = w == null ? null : d.films[w.filmId];
    if (w == null || film == null) return null;
    return SyncRecord(kind: 'wish', id: id, updatedAt: at, film: filmToWire(film, dev), data: wishToWire(w, dev));
  }

  /// Sends every pending record in batches of 200. The server answers with the rows that kept their place
  /// (applied here) and the records it refused (not retried until they change).
  Future<void> _push(int gen) async {
    final api = ref.read(apiProvider);
    final tried = <String>{};
    while (true) {
      final keys = [
        for (final e in _store.meta.entries)
          if (e.value.s == 0 && !tried.contains(e.key)) e.key,
      ].take(_batch).toList();
      if (keys.isEmpty) return;
      tried.addAll(keys);

      final d = ref.read(diaryProvider);
      final stubs = {for (final s in d.stubs) s.id: s};
      final wishes = {for (final w in d.wishes) w.filmId: w};
      final sent = <String, SyncEntry>{};
      final records = <SyncRecord>[];
      for (final key in keys) {
        final e = _store.meta[key]!;
        final rec = _record(key, e, d, stubs, wishes);
        if (rec == null) continue; // the next scan sorts it out
        sent[key] = e;
        records.add(rec);
      }
      if (records.isEmpty) continue;

      final reply = await api.post('/v1/sync/push', body: SyncPush(records).toJson());
      final res = SyncPushResult.fromJson(reply as Map<String, dynamic>);
      if (!ref.mounted || _store.generation != gen) return;
      _learnSkew(res.serverMs);

      final lost = {for (final c in res.conflicts) ?_key(c.kind, c.id): c};
      final refused = {for (final r in res.rejected) ?_key(r.kind, r.id)};
      for (final MapEntry(key: key, value: e) in sent.entries) {
        // Edited since it was sent: it stays pending and goes again with its new stamp. The same
        // guard spares it when the push loses: the server's row is applied only if this exact
        // entry is still the one here, so an edit made while the push travelled survives.
        if (!identical(_store.meta[key], e) || lost.containsKey(key)) continue;
        _store.meta[key] = refused.contains(key) ? SyncEntry(e.h, e.u, s: 2, x: e.x) : e.acked(e.u);
        if (key == 'm' && !refused.contains(key)) _store.metaUnited = true;
      }
      final (:changes, :unreadable) = _merge(lost.values.toList(), sent: sent);
      _poison += unreadable.length;
      _apply(changes);
      _store.save();
    }
  }

  // Taste ---------------------------------------------------------------------

  void _scheduleTaste() {
    if (!_auto) return;
    _tasteTimer?.cancel();
    _tasteTimer = Timer(_tasteDelay, () => unawaited(pushTaste()));
  }

  /// Uploads the taste document (from the public view of the diary, so private stubs never count) when
  /// its hash changed since the last upload. Needs the catalog and a server that is up.
  Future<void> pushTaste() async {
    if (!ref.read(onlineProvider) || state == SyncState.needsAccountChoice) return;
    final catalog = ref.read(catalogProvider).value;
    if (catalog == null) return;
    final taste = buildTaste(catalog, ref.read(diaryProvider).publicView(), ref.read(todayProvider))?.toJson();
    final h = taste == null ? '' : hashJson(taste);
    if (h == _store.tasteHash) return;
    try {
      final record = SyncRecord(
        kind: 'taste',
        id: 'taste',
        updatedAt: isoMs(_stamp()),
        deleted: taste == null,
        data: taste ?? const {},
      );
      final reply = await ref.read(apiProvider).post('/v1/sync/push', body: SyncPush([record]).toJson());
      final res = SyncPushResult.fromJson(reply as Map<String, dynamic>);
      if (!ref.mounted) return;
      _learnSkew(res.serverMs);
      // A refusal or a newer server row leaves the hash alone: the next change tries again.
      if (res.rejected.isEmpty && res.conflicts.isEmpty) {
        _store.tasteHash = h;
        _store.save();
      }
    } catch (_) {
      // Retried at the next change.
    }
  }
}

final syncEngineProvider = NotifierProvider<SyncEngine, SyncState>(SyncEngine.new, retry: (_, _) => null);

/// One sync run, for callers that need the server's changes now. A night wrap-up writes stubs into
/// every member's diary on the server, and the host's phone calls this to pull its own.
final syncRunProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(syncEngineProvider.notifier).run(),
);
