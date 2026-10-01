import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/json_file.dart';
import '../data/models.dart';
import '../data/recommend.dart';
import '../data/wire.dart';

/// App documents directory. Overridden in main() and in tests.
final docsDirProvider = Provider<Directory>((ref) => throw UnimplementedError('override docsDirProvider'));

/// Today as a date. Overridden in tests so release lists are stable.
final todayProvider = Provider<DateTime>((ref) => dateOnly(DateTime.now()));

/// The clock. Overridden in tests, so timers and stamps are deterministic.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final catalogProvider = FutureProvider<Catalog>((ref) async {
  final raw = await rootBundle.loadString('assets/catalog/catalog.json', cache: false);
  return loadCatalog(raw, File('${ref.watch(docsDirProvider).path}/catalog_delta.json'));
});

/// Home recommendations. Recomputed when viewings, hidden films, the catalog,
/// the day or the region change. Not on watchlist changes: a film added from a
/// row stays there with its tick, and leaves on the next recompute.
// ponytail: one scan of the catalog on the UI thread; move into Isolate.run behind a FutureProvider if Home janks
final recsProvider = Provider<Recs>((ref) {
  final catalog = ref.watch(catalogProvider).value;
  if (catalog == null) return Recs.none;
  ref.watch(diaryProvider.select((d) => (d.stubs, d.hidden)));
  return recommend(
    catalog,
    ref.read(diaryProvider),
    ref.watch(todayProvider),
    worldwide: ref.watch(settingsProvider.select((s) => s.worldwide)),
  );
});

// ---------------------------------------------------------------------------
// Settings

class Settings {
  const Settings({
    this.themeMode = ThemeMode.system,
    this.accent = 0,
    this.icon = 'default',
    this.weekStart = DateTime.sunday,
    this.locale,
    this.showRatings = true,
    this.shareBg = 0,
    this.worldwide = false,
    this.seenVersion = '',
    this.catalogRefreshed,
    this.recordsGrid = false,
  });

  final ThemeMode themeMode;
  final int accent;
  final String icon;

  /// DateTime.sunday or DateTime.monday.
  final int weekStart;

  /// null follows the device; otherwise 'en', 'hi', ...
  final String? locale;
  final bool showRatings;
  final int shareBg;

  /// Release lists: Indian films only (false) or every film (true).
  final bool worldwide;
  final String seenVersion;
  final DateTime? catalogRefreshed;
  final bool recordsGrid;

  Settings copyWith({
    ThemeMode? themeMode,
    int? accent,
    String? icon,
    int? weekStart,
    String? Function()? locale,
    bool? showRatings,
    int? shareBg,
    bool? worldwide,
    String? seenVersion,
    DateTime? catalogRefreshed,
    bool? recordsGrid,
  }) => Settings(
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    icon: icon ?? this.icon,
    weekStart: weekStart ?? this.weekStart,
    locale: locale == null ? this.locale : locale(),
    showRatings: showRatings ?? this.showRatings,
    shareBg: shareBg ?? this.shareBg,
    worldwide: worldwide ?? this.worldwide,
    seenVersion: seenVersion ?? this.seenVersion,
    catalogRefreshed: catalogRefreshed ?? this.catalogRefreshed,
    recordsGrid: recordsGrid ?? this.recordsGrid,
  );

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
    themeMode: ThemeMode.values.byName((j['themeMode'] as String?) ?? 'system'),
    accent: (j['accent'] as int?) ?? 0,
    icon: (j['icon'] as String?) ?? 'default',
    weekStart: (j['weekStart'] as int?) ?? DateTime.sunday,
    locale: j['locale'] as String?,
    showRatings: (j['showRatings'] as bool?) ?? true,
    shareBg: (j['shareBg'] as int?) ?? 0,
    worldwide: (j['worldwide'] as bool?) ?? false,
    seenVersion: (j['seenVersion'] as String?) ?? '',
    catalogRefreshed: j['catalogRefreshed'] == null ? null : DateTime.parse(j['catalogRefreshed'] as String),
    recordsGrid: (j['recordsGrid'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'accent': accent,
    'icon': icon,
    'weekStart': weekStart,
    'locale': locale,
    'showRatings': showRatings,
    'shareBg': shareBg,
    'worldwide': worldwide,
    'seenVersion': seenVersion,
    if (catalogRefreshed != null) 'catalogRefreshed': catalogRefreshed!.toIso8601String(),
    'recordsGrid': recordsGrid,
  };
}

class SettingsNotifier extends Notifier<Settings> {
  late JsonFile _file;

  @override
  Settings build() {
    _file = JsonFile(File('${ref.watch(docsDirProvider).path}/settings.json'));
    return Settings.fromJson(_file.read() ?? const {});
  }

  void set(Settings Function(Settings s) change) {
    state = change(state);
    _file.write(state.toJson());
  }

  Future<void> flush() => _file.flush();
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

// ---------------------------------------------------------------------------
// Diary

/// Fields the record form edits. Film and ticket number live on the stub.
class StubDraft {
  const StubDraft({
    this.date,
    this.precision = DatePrecision.day,
    this.rating,
    this.place,
    this.memo = '',
    this.tags = const [],
    this.show,
    this.format,
    this.seatClass,
    this.seat,
    this.price,
    this.fdfs = false,
    this.lang,
    this.company,
    this.private = false,
  });

  factory StubDraft.of(Stub s) => StubDraft(
    date: s.date,
    precision: s.precision,
    rating: s.rating,
    place: s.place,
    memo: s.memo,
    tags: s.tags,
    show: s.show,
    format: s.format,
    seatClass: s.seatClass,
    seat: s.seat,
    price: s.price,
    fdfs: s.fdfs,
    lang: s.lang,
    company: s.company,
    private: s.private,
  );

  final DateTime? date;
  final DatePrecision precision;
  final double? rating;
  final String? place;
  final String memo;
  final List<String> tags;
  final String? show, format, seatClass, seat;
  final double? price;
  final bool fdfs;
  final String? lang, company;

  /// See [Stub.private].
  final bool private;

  Stub toStub({required String id, required int no, required String filmId, required DateTime created}) => Stub(
    id: id,
    no: no,
    filmId: filmId,
    created: created,
    date: switch (precision) {
      _ when date == null => null,
      DatePrecision.day => dateOnly(date!),
      DatePrecision.month => DateTime(date!.year, date!.month),
      DatePrecision.year => DateTime(date!.year),
      DatePrecision.none => null,
    },
    precision: date == null ? DatePrecision.none : precision,
    rating: rating,
    place: place,
    memo: memo.trim(),
    tags: tags,
    show: show,
    format: format,
    seatClass: seatClass,
    seat: (seat ?? '').trim().isEmpty ? null : seat!.trim(),
    price: price,
    fdfs: fdfs,
    lang: lang,
    company: (company ?? '').trim().isEmpty ? null : company!.trim(),
    private: private,
  );
}

class DiaryNotifier extends Notifier<Diary> {
  late JsonFile _file;

  @override
  Diary build() {
    _file = JsonFile(File('${ref.watch(docsDirProvider).path}/diary.json'));
    final j = _file.read();
    return j == null ? const Diary() : Diary.fromJson(j);
  }

  void _commit(Diary d) {
    state = d;
    _file.write(d.toJson());
  }

  Future<void> flush() => _file.flush();

  Map<String, Film> _withFilm(Film f) => state.films[f.id] == null ? {...state.films, f.id: f} : state.films;

  /// Records a viewing. Returns the new stub. Removes the film from the watchlist.
  Stub addStub(Film film, StubDraft draft, {DateTime? now}) {
    final created = now ?? DateTime.now();
    final no = state.nextNo;
    final stub = draft.toStub(id: '${created.microsecondsSinceEpoch}-$no', no: no, filmId: film.id, created: created);
    _commit(
      state.copyWith(
        films: _withFilm(film),
        stubs: [...state.stubs, stub],
        wishes: state.wishes.where((w) => w.filmId != film.id).toList(),
        tags: _mergeTags(draft.tags),
        nextNo: no + 1,
      ),
    );
    return stub;
  }

  /// Adds many stubs at once (CSV import, batch entry). Keeps the watchlist.
  int addStubs(List<(Film, StubDraft)> rows, {DateTime? now}) {
    final created = now ?? DateTime.now();
    var no = state.nextNo;
    final films = {...state.films};
    final stubs = [...state.stubs];
    final tags = {...state.tags};
    for (final (film, draft) in rows) {
      films.putIfAbsent(film.id, () => film);
      stubs.add(draft.toStub(id: '${created.microsecondsSinceEpoch}-$no', no: no, filmId: film.id, created: created));
      tags.addAll(draft.tags);
      no++;
    }
    _commit(state.copyWith(films: films, stubs: stubs, tags: tags.toList(), nextNo: no));
    return rows.length;
  }

  void updateStub(Stub old, StubDraft draft) {
    final s = draft.toStub(id: old.id, no: old.no, filmId: old.filmId, created: old.created);
    _commit(state.copyWith(stubs: [for (final x in state.stubs) x.id == old.id ? s : x], tags: _mergeTags(draft.tags)));
  }

  void deleteStub(String id) {
    final stubs = state.stubs.where((s) => s.id != id).toList();
    _commit(state.copyWith(stubs: stubs, films: _prune(stubs, state.wishes)));
  }

  /// Puts back a stub removed by [deleteStub] (undo).
  void restoreStub(Stub s, Film film) {
    _commit(state.copyWith(films: _withFilm(film), stubs: [...state.stubs, s]));
  }

  void toggleWish(Film film, {DateTime? planned, DateTime? now}) {
    if (state.wishFor(film.id) != null) {
      final wishes = state.wishes.where((w) => w.filmId != film.id).toList();
      _commit(state.copyWith(wishes: wishes, films: _prune(state.stubs, wishes)));
    } else {
      _commit(
        state.copyWith(
          films: _withFilm(film),
          wishes: [
            ...state.wishes,
            Wish(filmId: film.id, added: now ?? DateTime.now(), planned: planned),
          ],
        ),
      );
    }
  }

  /// "Not interested": the film leaves recommendations and counts as a mild dislike.
  void setHidden(String filmId, bool on) {
    final rest = state.hidden.where((id) => id != filmId);
    _commit(state.copyWith(hidden: [...rest, if (on) filmId]));
  }

  void setPlanned(String filmId, DateTime? planned) {
    _commit(
      state.copyWith(
        wishes: [
          for (final w in state.wishes)
            w.filmId == filmId ? Wish(filmId: w.filmId, added: w.added, planned: planned) : w,
        ],
      ),
    );
  }

  /// Creates a film the catalog does not have.
  Film addCustomFilm({required String title, int? year, String? lang, bool series = false, String? posterFile}) {
    var n = 1;
    while (state.films.containsKey('my:$n')) {
      n++;
    }
    final f = Film(
      id: 'my:$n',
      title: title.trim(),
      year: year,
      date: year?.toString(),
      langs: lang == null ? const [] : [lang],
      series: series,
      poster: posterFile == null ? null : 'file:$posterFile',
    );
    _commit(state.copyWith(films: {...state.films, f.id: f}));
    return f;
  }

  void updateFilm(Film f) => _commit(state.copyWith(films: {...state.films, f.id: f}));

  /// Fills gaps in film snapshots from a newer catalog: a film recorded before
  /// Wikipedia had its poster gets the poster later. User data is untouched.
  void syncFilms(Catalog cat) {
    var changed = false;
    final films = {...state.films};
    for (final e in state.films.entries) {
      final s = e.value, c = cat.byId[e.key];
      if (c == null || s.isCustom) continue;
      final better =
          (s.poster == null && c.poster != null) ||
          (s.date?.length ?? 0) < (c.date?.length ?? 0) ||
          (s.runtime == null && c.runtime != null) ||
          (s.directors.isEmpty && c.directors.isNotEmpty);
      if (better) {
        films[e.key] = Catalog.fillGaps(s, c);
        changed = true;
      }
    }
    if (changed) _commit(state.copyWith(films: films));
  }

  // Tags --------------------------------------------------------------------

  List<String> _mergeTags(List<String> tags) => [...state.tags, ...tags.where((t) => !state.tags.contains(t))];

  void addTag(String tag) {
    final t = cleanTag(tag);
    if (t.isEmpty || state.tags.contains(t)) return;
    _commit(state.copyWith(tags: [...state.tags, t]));
  }

  void renameTag(String from, String to) {
    final t = cleanTag(to);
    if (t.isEmpty || t == from) return;
    _commit(
      state.copyWith(
        tags: [
          for (final x in state.tags)
            if (x == from) t else if (x != t) x,
        ],
        stubs: [
          for (final s in state.stubs)
            s.tags.contains(from) ? _retag(s, {for (final x in s.tags) x == from ? t : x}.toList()) : s,
        ],
      ),
    );
  }

  void deleteTag(String tag) {
    _commit(
      state.copyWith(
        tags: state.tags.where((t) => t != tag).toList(),
        stubs: [
          for (final s in state.stubs) s.tags.contains(tag) ? _retag(s, s.tags.where((t) => t != tag).toList()) : s,
        ],
      ),
    );
  }

  Stub _retag(Stub s, List<String> tags) => Stub.fromJson(s.toJson()..['tags'] = tags);

  // Venues ------------------------------------------------------------------

  void addVenue(Venue v) {
    final name = v.name.trim();
    if (name.isEmpty || state.venues.any((x) => x.name == name)) return;
    _commit(state.copyWith(venues: [...state.venues, Venue(name, v.type)]));
  }

  void updateVenue(Venue old, Venue next) {
    final name = next.name.trim();
    if (name.isEmpty || (name != old.name && state.venues.any((x) => x.name == name))) return;
    _commit(
      state.copyWith(
        venues: [for (final v in state.venues) v.name == old.name ? Venue(name, next.type) : v],
        stubs: [for (final s in state.stubs) s.place == old.name ? _replace(s, place: name) : s],
      ),
    );
  }

  /// Removes a venue from the picker. Stubs keep the name they were saved with.
  void deleteVenue(String name) => _commit(state.copyWith(venues: state.venues.where((v) => v.name != name).toList()));

  Stub _replace(Stub s, {required String place}) => Stub.fromJson(s.toJson()..['place'] = place);

  /// Marks a stub private or public. The change syncs like any edit.
  void setPrivate(String stubId, bool on) {
    Stub flip(Stub s) {
      final j = s.toJson();
      if (on) {
        j['priv'] = true;
      } else {
        j.remove('priv');
      }
      return Stub.fromJson(j);
    }

    if (!state.stubs.any((s) => s.id == stubId && s.private != on)) return;
    _commit(state.copyWith(stubs: [for (final s in state.stubs) s.id == stubId ? flip(s) : s]));
  }

  // Sync --------------------------------------------------------------------

  /// Applies what the sync engine pulled, in one commit. It never stamps: the
  /// engine's own records say these changes came from the server. A stub that
  /// arrives with `no: 0` (a night wrap-up) gets the next local ticket number,
  /// and `nextNo` moves above every ticket number that arrives.
  void applyRemote(RemoteChanges c) {
    if (c.isEmpty) return;
    final d = state;
    var nextNo = d.nextNo;
    for (final s in c.stubs) {
      if (s.no >= nextNo) nextNo = s.no + 1;
    }
    final incoming = {for (final s in c.stubs) s.id: s};
    final local = {for (final s in d.stubs) s.id: s};

    // Oldest first, so every phone numbers the same arrivals in the same order.
    final order = incoming.values.toList()
      ..sort((a, b) {
        final t = a.created.compareTo(b.created);
        return t != 0 ? t : a.id.compareTo(b.id);
      });
    final arrived = <String, Stub>{};
    for (final s in order) {
      if (s.no != 0) {
        arrived[s.id] = s;
        continue;
      }
      // Keep the number this phone already gave; otherwise take the next one.
      final no = local[s.id]?.no ?? 0;
      arrived[s.id] = Stub.fromJson(s.toJson()..['no'] = no != 0 ? no : nextNo++);
    }
    final stubs = [
      for (final s in d.stubs)
        if (!c.deletedStubs.contains(s.id)) arrived[s.id] ?? s,
      for (final s in arrived.values)
        if (!local.containsKey(s.id)) s,
    ];

    final wishIn = {for (final w in c.wishes) w.filmId: w};
    final wishes = [
      for (final w in d.wishes)
        if (!c.deletedWishes.contains(w.filmId)) wishIn[w.filmId] ?? w,
      for (final w in wishIn.values)
        if (d.wishFor(w.filmId) == null) w,
    ];

    // A catalog film keeps this phone's snapshot (a newer catalog may have filled it). A custom film
    // comes from the phone that edited it, but keeps the photo that only this phone has.
    final films = {...d.films};
    for (final e in c.films.entries) {
      final f = e.value, cur = films[e.key];
      if (!f.isCustom) {
        films.putIfAbsent(e.key, () => f);
      } else {
        films[e.key] = cur?.posterFile != null && f.poster == null ? f.copyWith(poster: cur!.poster) : f;
      }
    }
    final used = {...stubs.map((s) => s.filmId), ...wishes.map((w) => w.filmId)};
    films.removeWhere((id, _) => !used.contains(id));

    final m = c.meta;
    _commit(
      d.copyWith(
        films: films,
        stubs: stubs,
        wishes: wishes,
        tags: m?.tags,
        venues: m?.venues,
        hidden: m == null ? null : [...m.hidden, ...d.hidden.where((id) => id.startsWith('my:'))],
        nextNo: nextNo,
      ),
    );
  }

  // Backup ------------------------------------------------------------------

  void replaceAll(Diary d) => _commit(d);

  /// Drops film snapshots no stub or wish uses any more.
  Map<String, Film> _prune(List<Stub> stubs, List<Wish> wishes) {
    final used = {...stubs.map((s) => s.filmId), ...wishes.map((w) => w.filmId)};
    return {
      for (final e in state.films.entries)
        if (used.contains(e.key)) e.key: e.value,
    };
  }
}

final diaryProvider = NotifierProvider<DiaryNotifier, Diary>(DiaryNotifier.new);

/// Tags are stored without the leading '#'; spaces and commas become '_'.
String cleanTag(String t) =>
    t.trim().replaceAll(RegExp(r'^#+'), '').replaceAll(RegExp(r'[\s,]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

// ---------------------------------------------------------------------------
// Navigation and catalog refresh

class TabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void go(int i) => state = i;
}

final tabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);

enum FilmsSegment { fresh, upcoming, want, recorded }

class FilmsSegmentNotifier extends Notifier<FilmsSegment> {
  @override
  FilmsSegment build() => FilmsSegment.fresh;
  void go(FilmsSegment s) => state = s;
}

final filmsSegmentProvider = NotifierProvider<FilmsSegmentNotifier, FilmsSegment>(FilmsSegmentNotifier.new);

/// False in tests, so nothing touches the network on its own.
final autoRefreshProvider = Provider<bool>((ref) => true);

/// Busy flag for the online catalog refresh.
class CatalogRefresh extends Notifier<bool> {
  @override
  bool build() => false;

  /// Fetches recent and upcoming Indian films. Throws when offline.
  Future<int> run() async {
    if (state) return 0;
    state = true;
    try {
      final dir = ref.read(docsDirProvider);
      final n = await refreshCatalog(File('${dir.path}/catalog_delta.json'), ref.read(todayProvider));
      ref.read(settingsProvider.notifier).set((s) => s.copyWith(catalogRefreshed: DateTime.now()));
      ref.invalidate(catalogProvider);
      return n;
    } on PartialRefresh {
      // Show what was saved, but leave the date alone so the next open retries.
      ref.invalidate(catalogProvider);
      rethrow;
    } finally {
      state = false;
    }
  }

  /// Refreshes quietly when the last refresh is older than three days.
  Future<void> runIfDue() async {
    final last = ref.read(settingsProvider).catalogRefreshed;
    if (!ref.read(autoRefreshProvider) || (last != null && DateTime.now().difference(last).inDays < 3)) return;
    try {
      await run();
    } catch (_) {
      // Offline: the bundled list still works.
    }
  }
}

final catalogRefreshProvider = NotifierProvider<CatalogRefresh, bool>(CatalogRefresh.new);
