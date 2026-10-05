import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/crews.dart';
import '../data/deck.dart';
import '../data/json_file.dart';
import '../data/models.dart';
import '../data/night.dart';
import '../data/recommend.dart';
import 'crews_remote.dart';
import 'online.dart';
import 'providers.dart';
import 'reminders.dart';

// Groups, decks and nights. A local group (members are names) lives in
// crews.json. A shared group lives on the server (crews_remote.dart). One
// controller serves both and picks the repository by `crew.shared`.

// ---------------------------------------------------------------------------
// Failures and results

/// A shared call could not reach the server, or the session ended. A repository
/// throws this instead of an [ApiException], and the controller turns it into state.
class CrewOffline implements Exception {
  const CrewOffline();
  @override
  String toString() => 'CrewOffline';
}

/// The server (or a local rule) said no. [code] is the `error.code` of the
/// reply, [status] its HTTP status (0 for a local rule).
class CrewRefused implements Exception {
  const CrewRefused(this.code, [this.status = 0]);
  final String code;
  final int status;
  @override
  String toString() => 'CrewRefused($status $code)';
}

/// Why an action did not happen. The UI writes one sentence for each.
enum Refusal {
  /// The server cannot be reached.
  offline,
  nameTaken,
  groupFull,
  listFull,
  groupLimit,
  invalidCode,
  rateLimited,
  notAllowed,
  notFound,

  /// The poll or night is not in the state the action needs (someone else changed it).
  closed,
  invalid,
  other,
}

Refusal _refusalOf(CrewRefused r) => switch (r.code) {
  'name_taken' => Refusal.nameTaken,
  'group_full' => Refusal.groupFull,
  'list_full' => Refusal.listFull,
  'group_limit' => Refusal.groupLimit,
  'invalid_code' => Refusal.invalidCode,
  'not_polling' || 'not_set' || 'deck_conflict' => Refusal.closed,
  'rate_limited' => Refusal.rateLimited,
  _ => switch (r.status) {
    403 => Refusal.notAllowed,
    404 => Refusal.notFound,
    429 => Refusal.rateLimited,
    400 || 422 => Refusal.invalid,
    _ => Refusal.other,
  },
};

/// The result of an action: a [value], or the [refusal] that stopped it.
class Outcome<T> {
  const Outcome.ok([this.value]) : refusal = null;
  const Outcome.no(Refusal this.refusal) : value = null;
  final T? value;
  final Refusal? refusal;
  bool get ok => refusal == null;
}

/// Runs [f] and turns what a repository throws into a [Refusal]. Any other error is a bug and still throws.
Future<Outcome<T>> outcomeOf<T>(Future<T> Function() f) async {
  try {
    return Outcome.ok(await f());
  } on CrewOffline {
    return const Outcome.no(Refusal.offline);
  } on CrewRefused catch (e) {
    return Outcome.no(_refusalOf(e));
  }
}

// ---------------------------------------------------------------------------
// Repository

/// What building a deck needs besides the group: the catalog and, for a local
/// group, the taste, watchlist and seen films of the person who holds the phone.
class DeckEnv {
  const DeckEnv({
    required this.catalog,
    required this.today,
    this.worldwide = false,
    this.myTaste,
    this.myWishes = const [],
    this.mySeen = const {},
  });
  final Catalog catalog;
  final DateTime today;
  final bool worldwide;
  final Taste? myTaste;
  final List<Film> myWishes;
  final Set<String> mySeen;
}

/// One interface for groups, the shared list, the deck, swipes, nights, votes,
/// replies and the wrap-up. Every method takes the group as it is and returns
/// the group as it should become: nothing here writes the stores, so the
/// controller can apply a result when it is still current. A repository throws
/// [CrewOffline] and [CrewRefused], never an [ApiException].
abstract class CrewRepo {
  Future<Crew> create(String name, {String? myName});

  /// Fetches everything a screen shows. A local group already has it.
  Future<Crew> load(Crew crew);
  Future<Crew> rename(Crew crew, String name);

  /// Owner only. Removes the group for everyone.
  Future<void> delete(Crew crew);

  /// Leaves the group. For a local group, the same as [delete].
  Future<void> leave(Crew crew);

  /// A name in a local group; a guest (owner only) in a shared one.
  Future<Crew> addMember(Crew crew, String name);
  Future<Crew> removeMember(Crew crew, String memberId);

  /// Shared groups only.
  Future<Crew> rotateInvite(Crew crew);
  Future<Crew> addFilm(Crew crew, Film film);
  Future<Crew> removeFilm(Crew crew, String filmId);
  Future<Crew> rebuildDeck(Crew crew, DeckEnv env);

  /// A later swipe on the same film by the same member replaces the earlier one.
  /// Returns the group with fresh tallies.
  Future<Crew> swipes(Crew crew, List<Swipe> batch);

  /// Reads one member's votes on the deck. A local group already has them.
  Future<Crew> loadVotes(Crew crew, String memberId);

  /// Reads one member's votes in one night. A local night already has them.
  Future<Crew> loadNightVotes(Crew crew, String nightId, String memberId);
  Future<Crew> createNight(Crew crew, NightCreate draft);
  Future<Crew> vote(Crew crew, String nightId, String memberId, Set<String> optionIds);
  Future<Crew> closePoll(Crew crew, String nightId, {String? filmOptionId, String? slotOptionId, String? place});
  Future<Crew> rsvp(Crew crew, String nightId, String memberId, Rsvp response);
  Future<Crew> deleteNight(Crew crew, String nightId);
  Future<Crew> wrapUp(Crew crew, String nightId, {String? seatRow, int? firstSeat});
}

/// [CrewRepo] over crews.json. Members are names: the person who holds the
/// phone ([Member.me]) and guests. Swipes, votes and replies are entered per
/// member on this phone. The wrap-up writes my stub into the diary.
class LocalCrewRepo implements CrewRepo {
  LocalCrewRepo({required this.addStub, required this.now, Random? random}) : _random = random ?? Random();

  /// Records my viewing. In the app: `DiaryNotifier.addStub`.
  final Stub Function(Film film, StubDraft draft, DateTime now) addStub;
  final DateTime Function() now;
  final Random _random;

  @override
  Future<Crew> create(String name, {String? myName}) async {
    final n = name.trim();
    if (n.isEmpty || n.length > 40) throw const CrewRefused('invalid_request', 422);
    return Crew(
      id: newId(),
      name: n,
      members: [Member(id: newId(), name: (myName ?? '').trim(), owner: true, me: true)],
    );
  }

  @override
  Future<Crew> load(Crew crew) async => crew;

  @override
  Future<Crew> rename(Crew crew, String name) async {
    final n = name.trim();
    if (n.isEmpty || n.length > 40) throw const CrewRefused('invalid_request', 422);
    return crew.copyWith(name: n);
  }

  @override
  Future<void> delete(Crew crew) async {}

  @override
  Future<void> leave(Crew crew) async {}

  @override
  Future<Crew> addMember(Crew crew, String name) async {
    final n = name.trim();
    if (n.isEmpty || n.length > 40) throw const CrewRefused('invalid_request', 422);
    if (crew.members.length >= 30) throw const CrewRefused('group_full', 409);
    if (crew.members.any((m) => m.name.toLowerCase() == n.toLowerCase())) throw const CrewRefused('name_taken', 409);
    final m = Member(id: newId(), name: n, ink: nextInk(crew.members), guest: true);
    return crew.copyWith(members: [...crew.members, m]);
  }

  /// Removing a member also removes their swipes, votes and replies.
  @override
  Future<Crew> removeMember(Crew crew, String memberId) async {
    final m = crew.member(memberId);
    if (m == null) throw const CrewRefused('not_found', 404);
    if (m.me) throw const CrewRefused('forbidden', 403);
    final votes = {...crew.votes}..remove(memberId);
    return crew.copyWith(
      members: [
        for (final x in crew.members)
          if (x.id != memberId) x,
      ],
      votes: votes,
      tallies: tallies(votes),
      nights: [
        for (final n in crew.nights)
          _recount(
            n.copyWith(
              votes: {...n.votes}..remove(memberId),
              rsvps: {...n.rsvps}..remove(memberId),
              hostId: n.hostId == memberId ? crew.me?.id : n.hostId,
            ),
          ),
      ],
    );
  }

  @override
  Future<Crew> rotateInvite(Crew crew) async => throw const CrewRefused('forbidden', 403);

  @override
  Future<Crew> addFilm(Crew crew, Film film) async {
    if (crew.films.any((w) => w.filmId == film.id)) return crew;
    if (crew.films.length >= 200) throw const CrewRefused('list_full', 409);
    return crew.copyWith(films: [...crew.films, WatchItem(film)]);
  }

  @override
  Future<Crew> removeFilm(Crew crew, String filmId) async => crew.copyWith(
    films: [
      for (final w in crew.films)
        if (w.filmId != filmId) w,
    ],
  );

  /// Local members have no accounts: only my taste and my watchlist count, plus
  /// the shared list. Films any member swiped "seen" on, and films in my diary,
  /// are not recommended.
  @override
  Future<Crew> rebuildDeck(Crew crew, DeckEnv env) async {
    final wishes = {for (final f in env.myWishes) f.id: f};
    final listed = {for (final w in crew.films) w.filmId: w.film};
    final cards = buildDeck(
      catalog: env.catalog,
      tastes: [?env.myTaste],
      members: crew.members.length,
      wanted: [
        for (final id in {...wishes.keys, ...listed.keys})
          (film: wishes[id] ?? listed[id]!, n: (wishes.containsKey(id) ? 1 : 0) + (listed.containsKey(id) ? 1 : 0)),
      ],
      seen: {
        ...env.mySeen,
        for (final m in crew.votes.values)
          for (final e in m.entries)
            if (e.value == Vote.seen) e.key,
      },
      mySeen: env.mySeen,
      today: env.today,
      worldwide: env.worldwide,
    );
    final version = (crew.deck?.version ?? crew.deckVersion) + 1;
    return crew.copyWith(
      deck: Deck(version: version, cards: cards),
      deckVersion: version,
    );
  }

  @override
  Future<Crew> swipes(Crew crew, List<Swipe> batch) async {
    final votes = {
      for (final e in crew.votes.entries) e.key: {...e.value},
    };
    for (final s in batch) {
      final id = s.memberId ?? crew.me?.id;
      if (id == null || crew.member(id) == null) continue;
      (votes[id] ??= {})[s.filmId] = s.vote;
    }
    return crew.copyWith(votes: votes, tallies: tallies(votes));
  }

  @override
  Future<Crew> loadVotes(Crew crew, String memberId) async => crew;

  @override
  Future<Crew> loadNightVotes(Crew crew, String nightId, String memberId) async => crew;

  @override
  Future<Crew> createNight(Crew crew, NightCreate draft) async {
    if (!draft.isValid(now())) throw const CrewRefused('invalid_request', 422);
    final films = [
      for (final (i, f) in draft.films.indexed) NightOption(id: newId(), kind: OptionKind.film, position: i, film: f),
    ];
    final slots = [
      for (final (i, s) in draft.slots.indexed)
        NightOption(id: newId(), kind: OptionKind.slot, position: i, startsAt: s.toUtc()),
    ];
    final place = blankToNull(draft.place);
    // One film and one time: nothing to vote on, so the night is set.
    final set = films.length == 1 && slots.length == 1;
    final night = Night(
      id: newId(),
      crewId: crew.id,
      status: set ? NightStatus.set : NightStatus.poll,
      hostId: crew.me?.id,
      tzOffsetMin: draft.tzOffsetMin,
      place: place,
      options: [...films, ...slots],
      event: set
          ? NightEvent(
              film: films.first.film!,
              startsAt: slots.first.startsAt!,
              tzOffsetMin: draft.tzOffsetMin,
              place: place,
            )
          : null,
    );
    return crew.copyWith(nights: [night, ...crew.nights]);
  }

  Night _night(Crew crew, String id) => crew.night(id) ?? (throw const CrewRefused('not_found', 404));

  Crew _put(Crew crew, Night night) =>
      crew.copyWith(nights: [for (final n in crew.nights) n.id == night.id ? night : n]);

  /// Approvals of every option, counted from the votes.
  Night _recount(Night n) {
    final counts = pollTally(n.options, n.votes).approvals;
    return n.copyWith(options: [for (final o in n.options) o.withApprovals(counts[o.id] ?? 0)]);
  }

  @override
  Future<Crew> vote(Crew crew, String nightId, String memberId, Set<String> optionIds) async {
    final night = _night(crew, nightId);
    if (night.status != NightStatus.poll) throw const CrewRefused('not_polling', 409);
    if (crew.member(memberId) == null) throw const CrewRefused('forbidden', 403);
    final known = {for (final o in night.options) o.id};
    if (!optionIds.every(known.contains)) throw const CrewRefused('invalid_request', 422);
    return _put(
      crew,
      _recount(
        night.copyWith(
          votes: {
            ...night.votes,
            memberId: {...optionIds},
          },
        ),
      ),
    );
  }

  /// Without ids, the most approved film and time win, a tie going to the lowest position.
  @override
  Future<Crew> closePoll(Crew crew, String nightId, {String? filmOptionId, String? slotOptionId, String? place}) async {
    final night = _night(crew, nightId);
    if (night.status != NightStatus.poll) throw const CrewRefused('not_polling', 409);
    final lead = pollTally(night.options, night.votes);
    NightOption? pick(String? id, OptionKind kind, NightOption? winner) =>
        id == null ? winner : night.options.where((o) => o.id == id && o.kind == kind).firstOrNull;
    final film = pick(filmOptionId, OptionKind.film, lead.film)?.film;
    final at = pick(slotOptionId, OptionKind.slot, lead.slot)?.startsAt;
    if (film == null || at == null) throw const CrewRefused('invalid_request', 422);
    final event = NightEvent(
      film: film,
      startsAt: at,
      tzOffsetMin: night.tzOffsetMin,
      place: blankToNull(place) ?? night.place,
    );
    return _put(crew, night.copyWith(status: NightStatus.set, event: event));
  }

  @override
  Future<Crew> rsvp(Crew crew, String nightId, String memberId, Rsvp response) async {
    final night = _night(crew, nightId);
    if (night.status != NightStatus.set) throw const CrewRefused('not_set', 409);
    if (crew.member(memberId) == null) throw const CrewRefused('forbidden', 403);
    return _put(crew, night.copyWith(rsvps: {...night.rsvps, memberId: response}));
  }

  @override
  Future<Crew> deleteNight(Crew crew, String nightId) async => crew.copyWith(
    nights: [
      for (final n in crew.nights)
        if (n.id != nightId) n,
    ],
  );

  /// Writes my stub: no ticket number is chosen here, the diary gives the next one.
  @override
  Future<Crew> wrapUp(Crew crew, String nightId, {String? seatRow, int? firstSeat}) async {
    final night = _night(crew, nightId);
    final event = night.event;
    if (night.status != NightStatus.set || event == null) throw const CrewRefused('not_set', 409);
    final row = seatRow ?? String.fromCharCode(0x41 + _random.nextInt(12));
    if (!RegExp(r'^[A-Z]$').hasMatch(row)) throw const CrewRefused('invalid_request', 422);
    final draft = wrapDraft(night, crew.members, row, firstSeat ?? 1 + _random.nextInt(20));
    addStub(event.film, draft, now());
    return _put(crew, night.copyWith(status: NightStatus.done));
  }
}

final localCrewRepoProvider = Provider<LocalCrewRepo>(
  (ref) => LocalCrewRepo(
    addStub: (film, draft, now) => ref.read(diaryProvider.notifier).addStub(film, draft, now: now),
    now: ref.read(nowProvider),
  ),
);

// ---------------------------------------------------------------------------
// crews.json

class CrewsState {
  const CrewsState({this.crews = const [], this.reminders = const {}});

  /// Local groups.
  final List<Crew> crews;

  /// Nights that have reminders on, by night id. The value is true for a night of a shared group.
  final Map<String, bool> reminders;

  Crew? crew(String id) => crews.where((c) => c.id == id).firstOrNull;

  CrewsState copyWith({List<Crew>? crews, Map<String, bool>? reminders}) =>
      CrewsState(crews: crews ?? this.crews, reminders: reminders ?? this.reminders);
}

/// The local groups and the list of reminders, in crews.json. Read once, synchronously.
class CrewsNotifier extends Notifier<CrewsState> {
  late JsonFile _file;

  @override
  CrewsState build() {
    _file = JsonFile(File('${ref.watch(docsDirProvider).path}/crews.json'));
    final j = _file.read();
    if (j == null) return const CrewsState();
    try {
      return CrewsState(
        crews: [
          for (final c in (j['crews'] as List? ?? const []))
            _withTallies(Crew.fromJson(c as Map<String, dynamic>, shared: false)),
        ],
        reminders: {for (final e in ((j['reminders'] as Map?) ?? const {}).entries) e.key as String: e.value == true},
      );
    } catch (_) {
      // Valid JSON that is not ours: keep the file for recovery instead of overwriting it.
      try {
        _file.file.renameSync('${_file.file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      } on FileSystemException {
        // Nothing more to do: the next write replaces it.
      }
      return const CrewsState();
    }
  }

  static Crew _withTallies(Crew c) => c.copyWith(tallies: tallies(c.votes));

  void _commit(CrewsState s) {
    state = s;
    _file.write({
      'version': 1,
      'crews': [for (final c in s.crews) c.toJson()],
      'reminders': s.reminders,
    });
  }

  Future<void> flush() => _file.flush();

  /// Makes a local group. [myName] is the name of the person who holds the phone
  /// (may be empty: the UI shows "You").
  Future<Outcome<Crew>> create(String name, {String myName = ''}) async {
    final r = await outcomeOf(() => ref.read(localCrewRepoProvider).create(name, myName: myName));
    if (ref.mounted && r.value != null) put(r.value!);
    return r;
  }

  /// Adds or replaces a local group.
  void put(Crew crew) {
    final crews = [...state.crews];
    final i = crews.indexWhere((c) => c.id == crew.id);
    if (i < 0) {
      crews.add(crew);
    } else {
      crews[i] = crew;
    }
    _commit(state.copyWith(crews: crews));
  }

  void remove(String id) => _commit(
    state.copyWith(
      crews: [
        for (final c in state.crews)
          if (c.id != id) c,
      ],
    ),
  );

  /// Remembers that [nightId] has reminders on.
  void remind(String nightId, {required bool shared}) =>
      _commit(state.copyWith(reminders: {...state.reminders, nightId: shared}));

  /// Cancels the reminders of these nights and forgets them.
  Future<void> unremind(Iterable<String> nightIds) async {
    final ids = nightIds.toSet();
    if (ids.isEmpty) return;
    final reminders = ref.read(remindersProvider);
    for (final id in ids) {
      for (var slot = 0; slot < reminderLeads.length; slot++) {
        try {
          await reminders.cancel(reminderId(id, slot));
        } catch (_) {
          // A reminder that cannot be cancelled only rings for a night that is gone.
        }
      }
    }
    if (!ref.mounted) return;
    _commit(state.copyWith(reminders: {...state.reminders}..removeWhere((id, _) => ids.contains(id))));
  }

  /// Sign out and account deletion: shared groups go away, so do their reminders.
  Future<void> dropShared() => unremind([
    for (final e in state.reminders.entries)
      if (e.value) e.key,
  ]);

  /// After a full refresh of the shared groups: reminders of shared nights that no longer exist are cancelled.
  Future<void> reconcile(Set<String> liveSharedNights) => unremind([
    for (final e in state.reminders.entries)
      if (e.value && !liveSharedNights.contains(e.key)) e.key,
  ]);
}

final crewsProvider = NotifierProvider<CrewsNotifier, CrewsState>(CrewsNotifier.new, retry: (_, _) => null);

/// Whether the night has reminders on.
final reminderOnProvider = Provider.family<bool, String>(
  (ref, nightId) => ref.watch(crewsProvider.select((s) => s.reminders.containsKey(nightId))),
);

// ---------------------------------------------------------------------------
// Lists of groups and nights

/// Local groups, then shared ones while the server is up and the user is signed in.
/// Reads only crews.json until then.
final groupsProvider = Provider<List<Crew>>((ref) {
  final local = ref.watch(crewsProvider).crews;
  if (!ref.watch(onlineProvider)) return local;
  return [...local, ...ref.watch(sharedCrewsProvider).crews];
});

typedef NightEntry = ({Crew crew, Night night});

/// A night is still to come until two hours after it starts (the length of a film).
bool _ahead(DateTime? start, DateTime now) => start == null || start.add(const Duration(hours: 2)).isAfter(now);

/// Every night of every group in [groupsProvider]: nights still to come first,
/// the soonest on top, then the past ones, the latest on top.
final nightsProvider = Provider<List<NightEntry>>((ref) {
  final now = ref.watch(nowProvider)();
  final all = [
    for (final c in ref.watch(groupsProvider))
      for (final n in c.nights) (crew: c, night: n),
  ];
  all.sort((a, b) {
    final (x, y) = (a.night.when, b.night.when);
    final (ax, ay) = (_ahead(x, now), _ahead(y, now));
    if (ax != ay) return ax ? -1 : 1;
    if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
    return ax ? x.compareTo(y) : y.compareTo(x);
  });
  return all;
});

/// The night the Home row shows: the soonest one still to come that is not wrapped up, or null.
final nextNightProvider = Provider<NightEntry?>((ref) {
  final now = ref.watch(nowProvider)();
  for (final e in ref.watch(nightsProvider)) {
    final n = e.night;
    if (n.status != NightStatus.done && n.when != null && _ahead(n.when, now)) return e;
  }
  return null;
});

// ---------------------------------------------------------------------------
// The controller

class CrewState {
  const CrewState({required this.crew, this.loading = false, this.offline = false, this.gone = false, this.note});
  final Crew crew;

  /// A shared group is being fetched.
  final bool loading;

  /// The last shared call could not reach the server: show "Can't reach Talkies" and Retry ([CrewController.refresh]).
  final bool offline;

  /// The group no longer exists (deleted, left or removed): close the screen.
  final bool gone;

  /// Why the last swipe flush was refused: a Note for the screen. Stays until a
  /// flush succeeds.
  final Refusal? note;

  CrewState copyWith({Crew? crew, bool? loading, bool? offline, bool? gone, Refusal? note, bool clearNote = false}) =>
      CrewState(
        crew: crew ?? this.crew,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
        gone: gone ?? this.gone,
        note: clearNote ? null : (note ?? this.note),
      );

  /// The deck by want, for the results list.
  List<DeckCard> get results => resultsOrder(crew.deck?.cards ?? const [], crew.tallies);

  /// The most wanted card, or null while nobody wants anything. "Schedule it" starts from it.
  DeckCard? get topMatch {
    final r = results;
    return r.isNotEmpty && (crew.tallies[r.first.id]?.want ?? 0) > 0 ? r.first : null;
  }

  /// The three best cards: the films a poll starts with.
  List<DeckCard> get topThree => results.take(3).toList();

  /// The cards [memberId] has not swiped yet, in deck order.
  List<DeckCard> unswiped(String memberId) {
    final voted = crew.votes[memberId] ?? const {};
    return [
      for (final c in crew.deck?.cards ?? const <DeckCard>[])
        if (!voted.containsKey(c.id)) c,
    ];
  }

  /// Tonight's pick: one film at random among the most wanted, with the next best, up to three.
  List<DeckCard> tonight(Random random) => tonightPick(results, crew.tallies, random);

  /// How many members have seen the film. The server counts a shared group. A
  /// local group adds up the "seen" swipes and my diary.
  int seenBy(DeckCard c) {
    if (crew.shared) return c.seenBy;
    final mine = crew.votes[crew.me?.id]?[c.id] == Vote.seen;
    return (crew.tallies[c.id]?.seen ?? 0) + (c.seenBy > 0 && !mine ? 1 : 0);
  }
}

/// The tallies [t] gains when a vote [v] replaces [before] (+1) or is taken back (-1).
Tally _vote(Tally? t, Vote? v, int d) => Tally(
  want: (t?.want ?? 0) + (v == Vote.want ? d : 0),
  skip: (t?.skip ?? 0) + (v == Vote.skip ? d : 0),
  seen: (t?.seen ?? 0) + (v == Vote.seen ? d : 0),
);

/// A shared group's swipes wait this long to be sent together.
const _swipeDelay = Duration(milliseconds: 1500);

/// Actions on one group, local or shared. The state mirrors the group in its
/// store: crews.json for a local group, memory for a shared one.
class CrewController extends Notifier<CrewState> {
  CrewController(this.id);
  final String id;

  final _pending = <Swipe>[];
  Timer? _swipeTimer;
  bool _sending = false;

  /// Actions run one after the other, each on the result of the one before.
  Future<void> _tail = Future.value();

  @override
  CrewState build() {
    ref.onDispose(() => _swipeTimer?.cancel());
    final local = ref.read(crewsProvider).crew(id);
    if (local != null) {
      ref.listen(crewsProvider, (_, s) {
        final c = s.crew(id);
        state = c == null ? state.copyWith(gone: true) : state.copyWith(crew: c);
      });
      return CrewState(crew: local);
    }
    final shared = ref.read(sharedCrewsProvider).crew(id);
    ref.listen(sharedCrewsProvider, (_, s) {
      final c = s.crew(id);
      if (c != null) {
        // The list had not loaded when this controller was made: the group is here now.
        final late = state.gone;
        state = state.copyWith(crew: c, gone: false);
        if (late) unawaited(refresh());
      } else if (ref.read(onlineProvider) && !s.loading && !s.offline) {
        state = state.copyWith(gone: true);
      }
    });
    ref.listen(onlineProvider, (_, on) {
      if (on) {
        unawaited(flushSwipes());
        unawaited(refresh());
      } else {
        state = state.copyWith(offline: true);
      }
    });
    if (shared != null) Future.microtask(refresh);
    return CrewState(
      crew: shared ?? Crew(id: id, name: '', shared: true),
      loading: shared != null,
      gone: shared == null,
    );
  }

  CrewRepo _repo(Crew c) => c.shared ? ref.read(remoteCrewRepoProvider) : ref.read(localCrewRepoProvider);

  /// Writes [c] to its store and shows it.
  void _store(Crew c) {
    if (c.shared) {
      ref.read(sharedCrewsProvider.notifier).put(c);
    } else {
      ref.read(crewsProvider.notifier).put(c);
    }
    state = state.copyWith(crew: c);
  }

  /// Takes the result of a call that reached the server.
  void _commit(Crew c) {
    _store(_withPending(c));
    state = state.copyWith(offline: false);
  }

  /// [c] with the swipes the server has not acknowledged put back into its votes
  /// and tallies, so that a result computed before they were made cannot undo
  /// them (this is also what makes a swipe safe next to a queued action).
  Crew _withPending(Crew c) {
    if (_pending.isEmpty) return c;
    final me = c.me?.id;
    final votes = {
      for (final e in c.votes.entries) e.key: {...e.value},
    };
    var counts = c.tallies;
    for (final s in _pending) {
      final member = s.memberId ?? me;
      if (member == null) continue;
      final before = votes[member]?[s.filmId];
      (votes[member] ??= {})[s.filmId] = s.vote;
      if (before != s.vote) {
        counts = {...counts, s.filmId: _vote(_vote(counts[s.filmId], before, -1), s.vote, 1)};
      }
    }
    return c.copyWith(votes: votes, tallies: counts);
  }

  /// Fetches a shared group again: members, nights, list, deck and my votes.
  /// Call it when the screen opens and from Retry. A local group has nothing to fetch.
  Future<void> refresh() async {
    if (!ref.mounted || !state.crew.shared || state.gone) return;
    if (!ref.read(onlineProvider)) {
      state = state.copyWith(offline: true, loading: false);
      return;
    }
    state = state.copyWith(loading: true);
    final r = await outcomeOf(() => _repo(state.crew).load(state.crew));
    if (!ref.mounted) return;
    if (r.value case final c?) {
      _store(_withPending(c));
      state = state.copyWith(loading: false, offline: false);
    } else {
      state = state.copyWith(
        loading: false,
        offline: r.refusal != Refusal.notFound,
        gone: r.refusal == Refusal.notFound,
      );
    }
  }

  /// Runs [fn] after the earlier actions, on the group as they left it. A
  /// result that is still current becomes the state. When the server says the
  /// view was stale, the group is fetched again.
  Future<Outcome<T>> _act<T>(Future<(Crew, T)> Function(CrewRepo repo, Crew crew) fn) {
    final done = _tail.then<Outcome<T>>((_) async {
      if (!ref.mounted) return Outcome<T>.no(Refusal.other);
      final crew = state.crew;
      final r = await outcomeOf(() => fn(_repo(crew), crew));
      if (!ref.mounted) return r.ok ? Outcome<T>.ok(r.value!.$2) : Outcome<T>.no(r.refusal!);
      if (r.value case (final next, final value)) {
        _commit(next);
        return Outcome<T>.ok(value);
      }
      final why = r.refusal!;
      if (why == Refusal.offline) {
        state = state.copyWith(offline: true);
      } else if (crew.shared && (why == Refusal.closed || why == Refusal.notFound)) {
        unawaited(refresh());
      }
      return Outcome<T>.no(why);
    });
    _tail = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<Outcome<Crew>> _crew(Future<Crew> Function(CrewRepo repo, Crew crew) fn) => _act((repo, crew) async {
    final next = await fn(repo, crew);
    return (next, next);
  });

  // -- group

  Future<Outcome<Crew>> rename(String name) => _crew((r, c) => r.rename(c, name));

  /// A name in a local group. In a shared group, a guest: only the owner may add one.
  Future<Outcome<Crew>> addMember(String name) =>
      state.crew.shared && !state.crew.isOwner ? _no() : _crew((r, c) => r.addMember(c, name));

  Future<Outcome<Crew>> removeMember(String memberId) =>
      state.crew.shared && !state.crew.isOwner ? _no() : _crew((r, c) => r.removeMember(c, memberId));

  /// Gives a shared group a new invite code and invalidates the old one. Owner only.
  Future<Outcome<Crew>> rotateInvite() =>
      !state.crew.shared || !state.crew.isOwner ? _no() : _crew((r, c) => r.rotateInvite(c));

  Future<Outcome<Crew>> _no() async => const Outcome.no(Refusal.notAllowed);

  /// Removes the group for everyone. Owner only.
  Future<Outcome<void>> delete() => _drop((r, c) => r.delete(c), ownerOnly: true);

  /// Leaves the group: it goes from this phone, and from the others if it was a local group.
  Future<Outcome<void>> leave() => _drop((r, c) => r.leave(c));

  Future<Outcome<void>> _drop(Future<void> Function(CrewRepo repo, Crew crew) fn, {bool ownerOnly = false}) {
    if (ownerOnly && state.crew.shared && !state.crew.isOwner) {
      return Future.value(const Outcome.no(Refusal.notAllowed));
    }
    return _act((repo, crew) async {
      await fn(repo, crew);
      return (crew, null);
    }).then((r) async {
      if (!r.ok || !ref.mounted) return r;
      final crew = state.crew;
      await ref.read(crewsProvider.notifier).unremind([for (final n in crew.nights) n.id]);
      if (!ref.mounted) return r;
      if (crew.shared) {
        ref.read(sharedCrewsProvider.notifier).remove(id);
      } else {
        ref.read(crewsProvider.notifier).remove(id);
      }
      state = state.copyWith(gone: true);
      return r;
    });
  }

  // -- shared list

  Future<Outcome<Crew>> addFilm(Film film) => _crew((r, c) => r.addFilm(c, film));
  Future<Outcome<Crew>> removeFilm(String filmId) => _crew((r, c) => r.removeFilm(c, filmId));

  // -- deck and swipes

  Future<DeckEnv> _env(bool local) async {
    // Everything that needs ref is read before the await.
    final today = ref.read(todayProvider);
    final worldwide = ref.read(settingsProvider).worldwide;
    final diary = ref.read(diaryProvider);
    final catalog = await ref.read(catalogProvider.future);
    if (!local) return DeckEnv(catalog: catalog, today: today, worldwide: worldwide);
    return DeckEnv(
      catalog: catalog,
      today: today,
      worldwide: worldwide,
      // A private stub stays out of the taste, like every other shared view of
      // the diary; it still counts as a film I have seen below.
      myTaste: buildTaste(catalog, diary.publicView(), today),
      myWishes: [for (final w in diary.wishes) ?(diary.films[w.filmId] ?? catalog.byId[w.filmId])],
      mySeen: {for (final s in diary.stubs) s.filmId},
    );
  }

  /// Builds the deck anew from the members' tastes and lists. For a shared group
  /// a deck that someone else built first wins, and at most one deck is written
  /// every 10 seconds.
  Future<Outcome<Crew>> rebuildDeck() async {
    final Outcome<DeckEnv> env;
    try {
      env = Outcome.ok(await _env(!state.crew.shared));
    } catch (_) {
      // The catalog did not load.
      return const Outcome.no(Refusal.other);
    }
    return _crew((r, c) => r.rebuildDeck(c, env.value!));
  }

  /// Builds the deck when the group has none yet.
  Future<Outcome<Crew>> ensureDeck() async {
    final deck = state.crew.deck;
    if (deck != null && deck.cards.isNotEmpty) return Outcome.ok(state.crew);
    return rebuildDeck();
  }

  /// Records [vote] on [filmId] for [memberId]. A local group saves at once. A
  /// shared group shows it at once and sends swipes together, up to 50 a request;
  /// call [flushSwipes] when the deck closes. A later swipe replaces the earlier
  /// one, so "undo" is to swipe again. Only the owner may swipe for another member.
  Future<Outcome<Crew>> swipe(String memberId, String filmId, Vote vote) async {
    final crew = state.crew;
    if (crew.member(memberId) == null) return const Outcome.no(Refusal.notFound);
    if (!crew.shared) return _crew((r, c) => r.swipes(c, [Swipe(memberId: memberId, filmId: filmId, vote: vote)]));
    final me = crew.me?.id;
    if (memberId != me && !crew.isOwner) return const Outcome.no(Refusal.notAllowed);
    _pending.add(Swipe(memberId: memberId == me ? null : memberId, filmId: filmId, vote: vote));
    // Optimistic, with tallies recomputed on top of what the group had: a queued
    // action that commits an older result cannot wipe them ([_withPending]).
    _store(_withPending(crew));
    _swipeTimer?.cancel();
    if (_pending.length >= 50) {
      unawaited(flushSwipes());
    } else {
      _swipeTimer = Timer(_swipeDelay, () => unawaited(flushSwipes()));
    }
    return Outcome.ok(state.crew);
  }

  /// Sends the swipes that wait, then takes the server's tallies. Swipes the
  /// server could not take yet (offline, rate limited) stay for the next try;
  /// ones it refused for good (the group or deck no longer takes them) are
  /// dropped so they are not retried for ever. Either refusal is kept in the
  /// state as a note the screen can show.
  Future<Outcome<Crew>> flushSwipes() async {
    _swipeTimer?.cancel();
    if (_sending || _pending.isEmpty || !state.crew.shared || !ref.mounted) return Outcome.ok(state.crew);
    _sending = true;
    // The batch stays in _pending while it is in flight, so a reload meanwhile cannot lose it.
    final batch = [..._pending];
    final r = await outcomeOf(() => _repo(state.crew).swipes(state.crew, batch));
    _sending = false;
    // Offline and rate_limited mean "not yet": the swipes keep waiting. Every
    // other refusal is final for those films: the batch is dropped.
    final transient = r.refusal == Refusal.offline || r.refusal == Refusal.rateLimited;
    if (!transient) _pending.removeRange(0, batch.length);
    if (!ref.mounted) return r.ok ? Outcome.ok(state.crew) : Outcome.no(r.refusal!);
    if (r.value case final sent?) {
      // Only the tallies: the votes of swipes made meanwhile are in the state already.
      _commit(state.crew.copyWith(tallies: sent.tallies));
      state = state.copyWith(clearNote: true, offline: false);
      if (_pending.isNotEmpty) unawaited(flushSwipes());
    } else {
      state = state.copyWith(
        note: r.refusal,
        offline: r.refusal == Refusal.offline ? true : null,
      );
    }
    return r.ok ? Outcome.ok(state.crew) : Outcome.no(r.refusal!);
  }

  /// Reads the votes of one member of a shared group (a guest, for the owner).
  Future<Outcome<Crew>> loadVotes(String memberId) => _crew((r, c) => r.loadVotes(c, memberId));

  // -- nights

  /// The new night is the value.
  Future<Outcome<Night>> createNight(NightCreate draft) async {
    if (!draft.isValid(ref.read(nowProvider)())) return const Outcome.no(Refusal.invalid);
    return _act((repo, crew) async {
      final next = await repo.createNight(crew, draft);
      final old = {for (final n in crew.nights) n.id};
      return (next, next.nights.firstWhere((n) => !old.contains(n.id)));
    });
  }

  /// Sets what [memberId] approves in a poll. Members vote for themselves; the owner votes for guests.
  Future<Outcome<Crew>> vote(String nightId, String memberId, Set<String> optionIds) =>
      _crew((r, c) => r.vote(c, nightId, memberId, optionIds));

  /// Reads the votes of one member in a night (a guest, for the owner of a shared group).
  Future<Outcome<Crew>> loadNightVotes(String nightId, String memberId) =>
      _crew((r, c) => r.loadNightVotes(c, nightId, memberId));

  /// Ends a poll. Without ids the most approved film and time win. Host or owner.
  Future<Outcome<Crew>> closePoll(String nightId, {String? filmOptionId, String? slotOptionId, String? place}) =>
      _crew((r, c) => r.closePoll(c, nightId, filmOptionId: filmOptionId, slotOptionId: slotOptionId, place: place));

  /// Records a reply. Members reply for themselves; the host or owner replies for others.
  Future<Outcome<Crew>> rsvp(String nightId, String memberId, Rsvp response) =>
      _crew((r, c) => r.rsvp(c, nightId, memberId, response));

  Future<Outcome<Crew>> deleteNight(String nightId) async {
    final r = await _crew((repo, c) => repo.deleteNight(c, nightId));
    if (r.ok && ref.mounted) await ref.read(crewsProvider.notifier).unremind([nightId]);
    return r;
  }

  /// After the night: one stub for me in the diary, with the others as "who you
  /// went with" (local group). A shared group asks the server to write a stub for
  /// every member with an account, then syncs so mine arrives. Host or owner.
  Future<Outcome<Crew>> wrapUp(String nightId, {String? seatRow, int? firstSeat}) async {
    final shared = state.crew.shared;
    final r = await _crew((repo, c) => repo.wrapUp(c, nightId, seatRow: seatRow, firstSeat: firstSeat));
    if (!r.ok || !ref.mounted) return r;
    await ref.read(crewsProvider.notifier).unremind([nightId]);
    if (shared && ref.mounted) {
      try {
        await ref.read(wrapupSyncProvider)();
      } catch (_) {
        // The stub arrives with the next sync.
      }
    }
    return r;
  }

  /// Turns reminders for a set night on or off: one a day before, one two hours
  /// before, past ones skipped. The caller writes the texts (localized). Asks for
  /// permission at the first use. False when the night has no date, when every
  /// reminder time is already past, or the user said no.
  Future<bool> setReminder(
    String nightId,
    bool on, {
    required String title,
    required String dayBody,
    required String hourBody,
  }) async {
    final store = ref.read(crewsProvider.notifier);
    if (!on) {
      await store.unremind([nightId]);
      return true;
    }
    final start = state.crew.night(nightId)?.event?.startsAt;
    if (start == null) return false;
    final reminders = ref.read(remindersProvider);
    final times = reminderTimes(start, ref.read(nowProvider)());
    // Nothing to schedule (the night starts within two hours): say so instead
    // of recording a reminder that will never ring.
    if (times.isEmpty) return false;
    try {
      if (!await reminders.ensurePermission()) return false;
      for (final t in times) {
        await reminders.schedule(
          id: reminderId(nightId, t.slot),
          title: title,
          body: t.slot == 0 ? dayBody : hourBody,
          when: t.at,
        );
      }
    } catch (_) {
      return false;
    }
    if (!ref.mounted) return false;
    store.remind(nightId, shared: state.crew.shared);
    return true;
  }
}

final crewProvider = NotifierProvider.family<CrewController, CrewState, String>(
  CrewController.new,
  retry: (_, _) => null,
);
