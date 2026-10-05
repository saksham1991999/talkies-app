import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/crews.dart';
import '../data/deck.dart';
import '../data/models.dart';
import '../net/api.dart';
import 'crews.dart';
import 'online.dart';
import 'providers.dart';
import 'sync.dart';

// Shared groups: the server side of CrewRepo, the groups of the signed-in user
// (memory only), the invite link, the deck rebuild, and chat. Nothing here runs
// unless the backend is up and the user is signed in.

/// Every phase 3 to 5 call of backend/API.md, mapped to [CrewRepo]. It turns what
/// [Api] throws into [CrewOffline] and [CrewRefused].
class RemoteCrewRepo implements CrewRepo {
  RemoteCrewRepo(this.api, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Api api;
  final DateTime Function() _now;

  /// When this phone last wrote each group's deck. The server allows one write per 10 seconds.
  final _lastDeckWrite = <String, DateTime>{};

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on ApiOffline {
      throw const CrewOffline();
    } on ApiUnauthorized {
      throw const CrewOffline();
    } on ApiError catch (e) {
      throw CrewRefused(e.code, e.status);
    } on TypeError {
      // A reply that is not shaped like backend/API.md.
      throw const CrewRefused('bad_reply');
    } on FormatException {
      throw const CrewRefused('bad_reply');
    } on ArgumentError {
      // An enum value this app does not know.
      throw const CrewRefused('bad_reply');
    }
  }

  static String _g(String id) => '/v1/groups/$id';
  static Map<String, dynamic> _map(Object? json) => json as Map<String, dynamic>;

  /// Name, invite code, members and nights of one group.
  Future<Crew> _header(String id) async {
    // Future.wait throws the error itself; a record's `.wait` would wrap it.
    final r = await Future.wait([api.get(_g(id)), api.get('${_g(id)}/nights')]);
    final crew = Crew.fromJson(_map(r[0]));
    return crew.copyWith(nights: Night.listFromJson(r[1], mineFor: crew.me?.id));
  }

  /// The groups of the signed-in user, each with members and nights.
  // ponytail: one detail call and one nights call per group; a summary endpoint would cut 1 + 2N calls to 1
  Future<List<Crew>> groups() => _call(() async {
    final list = Crew.listFromJson(await api.get('/v1/groups'));
    return Future.wait([for (final g in list) _header(g.id)]);
  });

  /// Joins by invite code. Idempotent for a member.
  Future<Crew> join(String code) => _call(() async {
    final g = _map(await api.post('/v1/groups/join', body: joinPostBody(code)));
    return _header(g['id'] as String);
  });

  @override
  Future<Crew> create(String name, {String? myName}) => _call(() async {
    final g = _map(await api.post('/v1/groups', body: groupCreateBody(name.trim())));
    return _header(g['id'] as String);
  });

  @override
  Future<Crew> load(Crew crew) => _call(() async {
    final g = _g(crew.id);
    final r = await Future.wait([
      api.get(g),
      api.get('$g/films'),
      api.get('$g/deck'),
      api.get('$g/tallies'),
      api.get('$g/nights'),
    ]);
    final (detail, films, deck, mine, nights) = (r[0], r[1], r[2], r[3], r[4]);
    final head = Crew.fromJson(_map(detail));
    final me = head.me?.id;
    final reply = TalliesReply.fromJson(_map(mine));
    final d = Deck.fromJson(_map(deck));
    // Night votes this phone already knows (a guest's included), by night id.
    final oldVotes = {for (final n in crew.nights) n.id: n.votes};
    return head.copyWith(
      films: WatchItem.listFromJson(films),
      deck: d,
      deckVersion: d.version,
      // Keep the votes of guests read earlier; mine are fresh.
      votes: {...crew.votes, ?me: reply.mine},
      tallies: reply.tallies,
      // The list carries only mine; keep each night's known guest votes, as
      // [_take] does for a single night read.
      nights: [
        for (final n in Night.listFromJson(nights, mineFor: me))
          n.copyWith(votes: {...?oldVotes[n.id], ...n.votes}),
      ],
    );
  });

  @override
  Future<Crew> rename(Crew crew, String name) => _call(() async {
    final g = _map(await api.patch(_g(crew.id), body: groupPatchBody(name.trim())));
    return crew.copyWith(name: g['name'] as String);
  });

  @override
  Future<void> delete(Crew crew) => _call(() => api.delete(_g(crew.id)));

  @override
  Future<void> leave(Crew crew) => _call(() => api.delete('${_g(crew.id)}/members/me'));

  @override
  Future<Crew> addMember(Crew crew, String name) => _call(() async {
    final m = Member.fromJson(_map(await api.post('${_g(crew.id)}/guests', body: guestPostBody(name.trim()))));
    return crew.copyWith(members: [...crew.members, m]);
  });

  /// The server drops the member's swipes and votes, so the group is read again.
  @override
  Future<Crew> removeMember(Crew crew, String memberId) => _call(() async {
    await api.delete('${_g(crew.id)}/members/$memberId');
    return load(
      crew.copyWith(
        members: [
          for (final m in crew.members)
            if (m.id != memberId) m,
        ],
        votes: {...crew.votes}..remove(memberId),
      ),
    );
  });

  @override
  Future<Crew> rotateInvite(Crew crew) => _call(() async {
    return crew.copyWith(inviteCode: parseInviteCode(await api.post('${_g(crew.id)}/invite/rotate')));
  });

  @override
  Future<Crew> addFilm(Crew crew, Film film) => _call(() async {
    // Another member's phone cannot show a film that only exists in my diary.
    if (film.isCustom) throw const CrewRefused('invalid_request', 422);
    await api.put('${_g(crew.id)}/films/${Uri.encodeComponent(film.id)}', body: groupFilmPutBody(film));
    return crew.copyWith(
      films: [
        for (final w in crew.films)
          if (w.filmId != film.id) w,
        WatchItem(film),
      ],
    );
  });

  @override
  Future<Crew> removeFilm(Crew crew, String filmId) => _call(() async {
    await api.delete('${_g(crew.id)}/films/${Uri.encodeComponent(filmId)}');
    return crew.copyWith(
      films: [
        for (final w in crew.films)
          if (w.filmId != filmId) w,
      ],
    );
  });

  /// Reads the inputs, builds the deck and writes it with the version this phone
  /// read. If someone else wrote first (409), theirs wins. Within 10 seconds of
  /// this phone's last write nothing is written: the server's deck is read.
  @override
  Future<Crew> rebuildDeck(Crew crew, DeckEnv env) => _call(() async {
    final g = _g(crew.id);
    final last = _lastDeckWrite[crew.id];
    if (last == null || _now().difference(last) >= const Duration(seconds: 10)) {
      final inputs = DeckInputs.fromJson(_map(await api.get('$g/deck-inputs')));
      final cards = buildDeck(
        catalog: env.catalog,
        tastes: inputs.tastes,
        members: crew.members.length,
        wanted: inputs.wanted,
        seen: inputs.seen,
        today: env.today,
        worldwide: env.worldwide,
      );
      try {
        await api.put('$g/deck', body: deckPutBody(crew.deck?.version ?? crew.deckVersion, cards));
        _lastDeckWrite[crew.id] = _now();
      } on ApiError catch (e) {
        if (e.code != 'deck_conflict') rethrow;
      }
    }
    // Read it back: the server counts `seen_by`, and a conflict leaves the winner's deck.
    final deck = Deck.fromJson(_map(await api.get('$g/deck')));
    return crew.copyWith(deck: deck, deckVersion: deck.version);
  });

  /// Sends the swipes, 50 to a request, then reads the tallies. Inside a batch the
  /// last swipe on a film wins. The caller's own swipes go without a member id.
  @override
  Future<Crew> swipes(Crew crew, List<Swipe> batch) => _call(() async {
    final me = crew.me?.id;
    final last = <String, Swipe>{};
    for (final s in batch) {
      final member = s.memberId == me ? null : s.memberId;
      last.remove('$member|${s.filmId}');
      last['$member|${s.filmId}'] = Swipe(memberId: member, filmId: s.filmId, vote: s.vote);
    }
    final wire = last.values.toList();
    for (var i = 0; i < wire.length; i += 50) {
      await api.put('${_g(crew.id)}/swipes', body: swipesPutBody(wire.sublist(i, min(i + 50, wire.length))));
    }
    final reply = TalliesReply.fromJson(_map(await api.get('${_g(crew.id)}/tallies')));
    return crew.copyWith(tallies: reply.tallies);
  });

  @override
  Future<Crew> loadVotes(Crew crew, String memberId) => _call(() async {
    final query = memberId == crew.me?.id ? null : {'member_id': memberId};
    final reply = TalliesReply.fromJson(_map(await api.get('${_g(crew.id)}/tallies', query: query)));
    return crew.copyWith(votes: {...crew.votes, memberId: reply.mine}, tallies: reply.tallies);
  });

  Night _night(Crew crew, String id) => crew.night(id) ?? (throw const CrewRefused('not_found', 404));

  Crew _put(Crew crew, Night night) =>
      crew.copyWith(nights: [for (final n in crew.nights) n.id == night.id ? night : n]);

  /// A night read from the server, with the votes this phone already knows kept.
  Crew _take(Crew crew, Night old, Night fresh) => _put(crew, fresh.copyWith(votes: {...old.votes, ...fresh.votes}));

  @override
  Future<Crew> loadNightVotes(Crew crew, String nightId, String memberId) => _call(() async {
    final old = _night(crew, nightId);
    final query = memberId == crew.me?.id ? null : {'member_id': memberId};
    final fresh = Night.fromJson(_map(await api.get('/v1/nights/$nightId', query: query)), mineFor: memberId);
    return _take(crew, old, fresh);
  });

  @override
  Future<Crew> createNight(Crew crew, NightCreate draft) => _call(() async {
    final j = _map(await api.post('${_g(crew.id)}/nights', body: draft.toJson()));
    return crew.copyWith(
      nights: [
        Night.fromJson(j, mineFor: crew.me?.id),
        ...crew.nights,
      ],
    );
  });

  @override
  Future<Crew> vote(Crew crew, String nightId, String memberId, Set<String> optionIds) => _call(() async {
    final night = _night(crew, nightId);
    final body = votesPutBody(optionIds, memberId == crew.me?.id ? null : memberId);
    final approvals = parseVotesResult(await api.put('/v1/nights/$nightId/votes', body: body));
    return _put(
      crew,
      night.copyWith(
        options: [for (final o in night.options) o.withApprovals(approvals[o.id] ?? 0)],
        votes: {
          ...night.votes,
          memberId: {...optionIds},
        },
      ),
    );
  });

  @override
  Future<Crew> closePoll(Crew crew, String nightId, {String? filmOptionId, String? slotOptionId, String? place}) =>
      _call(() async {
        final old = _night(crew, nightId);
        final body = closePostBody(filmOptionId: filmOptionId, slotOptionId: slotOptionId, place: blankToNull(place));
        final fresh = Night.fromJson(
          _map(await api.post('/v1/nights/$nightId/close', body: body)),
          mineFor: crew.me?.id,
        );
        return _take(crew, old, fresh);
      });

  @override
  Future<Crew> rsvp(Crew crew, String nightId, String memberId, Rsvp response) => _call(() async {
    final night = _night(crew, nightId);
    await api.put('/v1/nights/$nightId/rsvp', body: rsvpPutBody(response, memberId == crew.me?.id ? null : memberId));
    return _put(crew, night.copyWith(rsvps: {...night.rsvps, memberId: response}));
  });

  @override
  Future<Crew> deleteNight(Crew crew, String nightId) => _call(() async {
    await api.delete('/v1/nights/$nightId');
    return crew.copyWith(
      nights: [
        for (final n in crew.nights)
          if (n.id != nightId) n,
      ],
    );
  });

  /// The server writes a stub for every member with an account who said yes. The
  /// caller then syncs, so that mine arrives (see [wrapupSyncProvider]).
  @override
  Future<Crew> wrapUp(Crew crew, String nightId, {String? seatRow, int? firstSeat}) => _call(() async {
    final night = _night(crew, nightId);
    parseWrapupResult(
      await api.post(
        '/v1/nights/$nightId/wrapup',
        body: wrapupPostBody(seatRow: seatRow, firstSeat: firstSeat),
      ),
    );
    return _put(crew, night.copyWith(status: NightStatus.done));
  });

  // -- chat, and things that start from a film

  /// Ascending. With neither [after] nor [before]: the latest page.
  Future<MessagePage> messages(String crewId, {int? after, int? before, int limit = 50}) => _call(() async {
    final j = await api.get(
      '${_g(crewId)}/messages',
      query: {if (after != null) 'after': '$after', if (before != null) 'before': '$before', 'limit': '$limit'},
    );
    return MessagePage.fromJson(_map(j));
  });

  Future<Message> sendMessage(String crewId, String body, {Film? film, String? nightId}) => _call(() async {
    final j = await api.post(
      '${_g(crewId)}/messages',
      body: messagePostBody(body, film: film, nightId: nightId),
    );
    return Message.fromJson(_map(j));
  });

  /// [kind] is `user`, `message` or `group`; [targetId] a uuid, or a message id as text.
  Future<void> report(String kind, String targetId, String reason, {String? note}) => _call(
    () => api.post(
      '/v1/reports',
      body: {'kind': kind, 'target_id': targetId, 'reason': reason, 'note': blankToNull(note)},
    ),
  );

  /// Puts a film on a friend's feed. The friend must be a friend and not blocked.
  Future<void> sendFilm(String userId, Film film, {String? note}) =>
      _call(() => api.post('/v1/films/send', body: sendFilmBody(userId, film, note: blankToNull(note))));
}

final remoteCrewRepoProvider = Provider<RemoteCrewRepo>(
  (ref) => RemoteCrewRepo(ref.watch(apiProvider), now: ref.read(nowProvider)),
  retry: (_, _) => null,
);

/// After a wrap-up the server holds a new stub for me, and a sync brings it to
/// the diary: the default runs the sync engine (see [syncRunProvider]). Tests
/// replace this with a fake; a failure is not a wrap-up failure (the caller
/// catches).
final wrapupSyncProvider = Provider<Future<void> Function()>(
  (ref) => () => ref.read(syncRunProvider)(),
);

// ---------------------------------------------------------------------------
// Shared groups

class SharedCrews {
  const SharedCrews({this.crews = const [], this.loading = false, this.offline = false});
  final List<Crew> crews;
  final bool loading;

  /// The last refresh could not reach the server. [crews] is what was known before.
  final bool offline;

  Crew? crew(String id) => crews.where((c) => c.id == id).firstOrNull;
}

/// The groups of the signed-in user, in memory only. Empty unless the server is up
/// and the user is signed in. Each group holds its members and nights; a group
/// gains its list, deck and votes when its controller loads them.
class SharedCrewsNotifier extends Notifier<SharedCrews> {
  @override
  SharedCrews build() {
    if (!ref.watch(onlineProvider)) return const SharedCrews();
    Future.microtask(refresh);
    return const SharedCrews(loading: true);
  }

  /// Fetches every group again (pull to refresh, Retry).
  Future<void> refresh() async {
    if (!ref.mounted || !ref.read(onlineProvider)) return;
    state = SharedCrews(crews: state.crews, loading: true);
    final r = await outcomeOf(() => ref.read(remoteCrewRepoProvider).groups());
    if (!ref.mounted) return;
    final fresh = r.value;
    if (fresh == null) {
      state = SharedCrews(crews: state.crews, offline: true);
      return;
    }
    // A controller may have loaded a group's list or deck meanwhile: keep that.
    final old = {for (final c in state.crews) c.id: c};
    state = SharedCrews(
      crews: [
        for (final c in fresh)
          if (old[c.id] case final o?)
            c.copyWith(films: o.films, deck: o.deck, votes: o.votes, tallies: o.tallies)
          else
            c,
      ],
    );
    await ref.read(crewsProvider.notifier).reconcile({
      for (final c in fresh)
        for (final n in c.nights) n.id,
    });
  }

  /// Adds or replaces a group.
  void put(Crew crew) {
    final crews = [...state.crews];
    final i = crews.indexWhere((c) => c.id == crew.id);
    if (i < 0) {
      crews.add(crew);
    } else {
      crews[i] = crew;
    }
    state = SharedCrews(crews: crews);
  }

  void remove(String id) => state = SharedCrews(
    crews: [
      for (final c in state.crews)
        if (c.id != id) c,
    ],
  );

  Future<Outcome<Crew>> create(String name) async {
    final r = await outcomeOf(() => ref.read(remoteCrewRepoProvider).create(name));
    if (ref.mounted && r.value != null) put(r.value!);
    return r;
  }

  /// Joins with an invite code (typed, pasted, or from a link). The group is the value.
  Future<Outcome<Crew>> joinGroup(String code) async {
    final c = normalizeCode(code);
    if (c == null) return const Outcome.no(Refusal.invalidCode);
    final r = await outcomeOf(() => ref.read(remoteCrewRepoProvider).join(c));
    if (ref.mounted && r.value != null) {
      put(r.value!);
      ref.read(pendingJoinProvider.notifier).clear();
    }
    return r;
  }
}

final sharedCrewsProvider = NotifierProvider<SharedCrewsNotifier, SharedCrews>(
  SharedCrewsNotifier.new,
  retry: (_, _) => null,
);

/// An invite code in its one spelling (upper case, no spaces or dashes), or null if it is not one.
String? normalizeCode(String raw) {
  final code = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^[A-HJ-KM-NP-Z2-9]{8}$').hasMatch(code) ? code : null;
}

/// The invite code from a `talkies://join?code=` link, waiting for the user to
/// confirm. The link handler sets it; the Together screen offers to join.
class PendingJoin extends Notifier<String?> {
  @override
  String? build() => null;

  /// Anything that is not a code clears it.
  void set(String? raw) => state = raw == null ? null : normalizeCode(raw);

  void clear() => state = null;
}

final pendingJoinProvider = NotifierProvider<PendingJoin, String?>(PendingJoin.new, retry: (_, _) => null);

// ---------------------------------------------------------------------------
// Chat

/// How often an open chat asks for new messages: fast while the chat has seen a
/// message in the last two minutes, slower once it has been quiet.
const chatEvery = Duration(seconds: 4);
const chatIdleEvery = Duration(seconds: 15);

class ChatState {
  const ChatState({this.messages = const [], this.active = false, this.hasOlder = false, this.offline = false});

  /// Oldest first.
  final List<Message> messages;

  /// The chat screen is open and visible. Polling runs only then.
  final bool active;

  /// Earlier messages exist ([ChatController.loadOlder]).
  final bool hasOlder;
  final bool offline;

  ChatState copyWith({List<Message>? messages, bool? active, bool? hasOlder, bool? offline}) => ChatState(
    messages: messages ?? this.messages,
    active: active ?? this.active,
    hasOlder: hasOlder ?? this.hasOlder,
    offline: offline ?? this.offline,
  );
}

/// The chat of one shared group. Polls with `after=<last id>` while
/// [ChatState.active] is true — every [chatEvery] while the chat is live, every
/// [chatIdleEvery] after two quiet minutes — and sends nothing while the server
/// is down. Dropped when no screen listens, so the timer cannot outlive the chat.
class ChatController extends Notifier<ChatState> {
  ChatController(this.crewId);
  final String crewId;
  Timer? _timer;
  bool _busy = false;

  /// When the chat last saw a message arrive or leave. Null counts as live: a
  /// chat just opened asks fast until it has been quiet a while.
  DateTime? _lastLive;

  @override
  ChatState build() {
    ref.onDispose(() => _timer?.cancel());
    // Back online while the chat is open: ask now instead of at the next tick.
    ref.listen(onlineProvider, (_, on) {
      if (on && state.active) unawaited(poll());
    });
    return const ChatState();
  }

  Duration get _every =>
      _lastLive != null && ref.read(nowProvider)().difference(_lastLive!) >= const Duration(minutes: 2)
      ? chatIdleEvery
      : chatEvery;

  /// One self-renewing tick: the wait is chosen again each time, so a quiet chat
  /// slows down with no more machinery than this one timer.
  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_every, () {
      unawaited(poll());
      _schedule();
    });
  }

  /// Marks the chat live, so the next ask comes at the fast rate again.
  void _live() {
    _lastLive = ref.read(nowProvider)();
    if (state.active) _schedule();
  }

  /// Call with true when the chat screen shows and with false when it hides or the app pauses.
  void setActive(bool on) {
    if (!on && !state.active) return;
    state = state.copyWith(active: on);
    if (!on) {
      _timer?.cancel();
      _timer = null;
    } else {
      // Fresh on open, and fast again when the app comes back to an open chat.
      _live();
      unawaited(poll());
    }
  }

  void _add(List<Message> items, {bool? hasOlder}) {
    final byId = {for (final m in state.messages) m.id: m, for (final m in items) m.id: m};
    state = state.copyWith(
      messages: byId.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      hasOlder: hasOlder,
      offline: false,
    );
    if (items.isNotEmpty) _live();
  }

  /// Fetches what is new: the latest page the first time, then everything after the last id.
  Future<void> poll() async {
    if (_busy || !state.active || !ref.read(onlineProvider)) return;
    _busy = true;
    try {
      var more = true;
      while (more && ref.mounted && state.active) {
        final after = state.messages.isEmpty ? null : state.messages.last.id;
        final r = await outcomeOf(() => ref.read(remoteCrewRepoProvider).messages(crewId, after: after));
        if (!ref.mounted) return;
        final page = r.value;
        if (page == null) {
          state = state.copyWith(offline: true);
          return;
        }
        // The first page says whether older messages exist; a page after the last id says whether more follow.
        _add(page.items, hasOlder: after == null ? page.hasMore : null);
        more = after != null && page.hasMore && page.items.isNotEmpty;
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> loadOlder() async {
    if (state.messages.isEmpty || !state.hasOlder) return;
    final r = await outcomeOf(() => ref.read(remoteCrewRepoProvider).messages(crewId, before: state.messages.first.id));
    if (!ref.mounted) return;
    final page = r.value;
    if (page == null) {
      state = state.copyWith(offline: true);
    } else {
      _add(page.items, hasOlder: page.hasMore);
    }
  }

  /// Sends a text of 1 to 1000 characters, with a film or a night attached if given.
  Future<Outcome<Message>> send(String text, {Film? film, String? nightId}) async {
    final body = text.trim();
    if (body.isEmpty || body.length > 1000) return const Outcome.no(Refusal.invalid);
    final r = await outcomeOf(
      () => ref.read(remoteCrewRepoProvider).sendMessage(crewId, body, film: film, nightId: nightId),
    );
    if (!ref.mounted) return r;
    if (r.value case final m?) {
      _add([m]);
    } else if (r.refusal == Refusal.offline) {
      state = state.copyWith(offline: true);
    }
    return r;
  }

  /// Reports a message. [reason] is `spam`, `abuse`, `harassment`, `inappropriate` or `other`.
  Future<Outcome<void>> report(Message message, String reason, {String? note}) =>
      outcomeOf(() => ref.read(remoteCrewRepoProvider).report('message', '${message.id}', reason, note: note));
}

final chatProvider = NotifierProvider.autoDispose.family<ChatController, ChatState, String>(
  ChatController.new,
  retry: (_, _) => null,
);
