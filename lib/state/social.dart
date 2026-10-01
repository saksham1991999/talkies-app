/// Controllers for the social API (phases 1 and 2). They are synchronous
/// notifiers with a small state, they make no call unless the user is online
/// ([onlineProvider]: server up and signed in), and no exception reaches a widget.
/// Screens call `load()` themselves; nothing here runs on its own.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/social.dart';
import '../net/api.dart';
import 'online.dart';
import 'providers.dart';

// ---------------------------------------------------------------------------
// Shared pieces

enum Fetch {
  idle,
  loading,

  /// Has a value.
  ready,

  /// The server cannot be reached: show "Can't reach Talkies" and Retry.
  offline,

  /// Any other failure.
  failed,
}

/// One value from the server with its load state. The last value stays while a reload runs or fails.
class Remote<T> {
  const Remote({this.status = Fetch.idle, this.value});
  final Fetch status;
  final T? value;
  bool get loading => status == Fetch.loading;
}

enum CallOutcome { ok, offline, signedOut, notFound, conflict, rateLimited, invalid, failed }

/// The result of an action. [code] is the `error.code` of the server's reply, for the few codes a screen
/// words itself (`handle_taken`, `already_pending`, `list_full`).
class CallResult<T> {
  const CallResult(this.outcome, {this.value, this.code});
  final CallOutcome outcome;
  final T? value;
  final String? code;
  bool get ok => outcome == CallOutcome.ok;
}

CallOutcome _outcome(Object e) => switch (e) {
  ApiOffline() => CallOutcome.offline,
  ApiUnauthorized() => CallOutcome.signedOut,
  ApiError(status: 404) => CallOutcome.notFound,
  ApiError(status: 409) => CallOutcome.conflict,
  ApiError(status: 429) => CallOutcome.rateLimited,
  ApiError(status: 400 || 422) => CallOutcome.invalid,
  _ => CallOutcome.failed,
};

Fetch _failure(CallOutcome o) => o == CallOutcome.offline ? Fetch.offline : Fetch.failed;

/// Every controller call goes through here. Not online: [CallOutcome.offline], no I/O. Any error, a reply
/// that does not parse included, becomes an outcome.
Future<CallResult<T>> _call<T>(Ref ref, Future<T> Function(Api api) run) async {
  if (!ref.read(onlineProvider)) return CallResult<T>(CallOutcome.offline);
  try {
    return CallResult<T>(CallOutcome.ok, value: await run(ref.read(apiProvider)));
  } catch (e) {
    return CallResult<T>(_outcome(e), code: e is ApiError ? e.code : null);
  }
}

Future<CallResult<void>> _act(Ref ref, Future<void> Function(Api api) run) async {
  final r = await _call<bool>(ref, (api) async {
    await run(api);
    return true;
  });
  return CallResult<void>(r.outcome, code: r.code);
}

Map<String, dynamic> _json(Object? v) => v as Map<String, dynamic>;

/// Riverpod forbids changing a provider inside a widget life-cycle (initState, build, dispose). A screen
/// may call any `load()` from initState: the first state change waits one microtask, until the build is done.
Future<void> _afterBuild() => Future<void>.value();

/// The controllers start fresh when another account signs in, or the user signs out.
String? _account(Ref ref) => ref.watch(sessionProvider.select((s) => s?.userId));

// ---------------------------------------------------------------------------
// Me

class MeController extends Notifier<Remote<Me>> {
  @override
  Remote<Me> build() {
    _account(ref);
    final me = ref.read(sessionProvider)?.me;
    return Remote(status: me == null ? Fetch.idle : Fetch.ready, value: me);
  }

  Future<void> load() async {
    await _afterBuild();
    state = Remote(status: Fetch.loading, value: state.value);
    final r = await _call(ref, (api) async => Me.fromJson(_json(await api.get('/v1/me'))));
    if (!ref.mounted) return;
    state = r.ok
        ? Remote(status: Fetch.ready, value: r.value)
        : Remote(status: _failure(r.outcome), value: state.value);
    if (r.ok) ref.read(sessionProvider.notifier).setMe(r.value!);
  }

  /// Changes handle, display name, stamp color, visibility or share-ratings. A taken handle gives
  /// [CallOutcome.conflict] with code `handle_taken`.
  Future<CallResult<Me>> patch(MePatch p) async {
    final r = await _call(ref, (api) async => Me.fromJson(_json(await api.patch('/v1/me', body: p.toJson()))));
    if (ref.mounted && r.ok) {
      state = Remote(status: Fetch.ready, value: r.value);
      ref.read(sessionProvider.notifier).setMe(r.value!);
    }
    return r;
  }
}

final meProvider = NotifierProvider<MeController, Remote<Me>>(MeController.new, retry: (_, _) => null);

// ---------------------------------------------------------------------------
// Friends

class FriendsState {
  const FriendsState({this.friends = const Remote(), this.requests = const Remote()});
  final Remote<List<FriendItem>> friends;
  final Remote<FriendRequests> requests;
}

class FriendsController extends Notifier<FriendsState> {
  @override
  FriendsState build() {
    _account(ref);
    return const FriendsState();
  }

  Future<void> loadFriends() async {
    await _afterBuild();
    state = FriendsState(
      friends: Remote(status: Fetch.loading, value: state.friends.value),
      requests: state.requests,
    );
    final r = await _call(ref, (api) async => FriendList.fromJson(_json(await api.get('/v1/friends'))).items);
    if (!ref.mounted) return;
    state = FriendsState(
      friends: r.ok
          ? Remote(status: Fetch.ready, value: r.value)
          : Remote(status: _failure(r.outcome), value: state.friends.value),
      requests: state.requests,
    );
  }

  Future<void> loadRequests() async {
    await _afterBuild();
    state = FriendsState(
      friends: state.friends,
      requests: Remote(status: Fetch.loading, value: state.requests.value),
    );
    final r = await _call(ref, (api) async => FriendRequests.fromJson(_json(await api.get('/v1/friends/requests'))));
    if (!ref.mounted) return;
    state = FriendsState(
      friends: state.friends,
      requests: r.ok
          ? Remote(status: Fetch.ready, value: r.value)
          : Remote(status: _failure(r.outcome), value: state.requests.value),
    );
  }

  Future<void> refresh() => Future.wait([loadFriends(), loadRequests()]);

  /// Finds a person by exact handle (30 per hour). [CallOutcome.notFound] when nobody has it.
  Future<CallResult<UserLookup>> lookup(String handle) {
    final h = handle.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    return _call(
      ref,
      (api) async => UserLookup.fromJson(_json(await api.get('/v1/users/lookup', query: {'handle': h}))),
    );
  }

  /// Asks [userId] to be friends. If they asked first, the answer is [RequestStatus.friends].
  /// An existing request gives [CallOutcome.conflict] with code `already_pending`.
  Future<CallResult<FriendRequestResult>> send(String userId) async {
    final r = await _call(
      ref,
      (api) async => FriendRequestResult.fromJson(
        _json(await api.post('/v1/friends/requests', body: FriendRequestPost(userId).toJson())),
      ),
    );
    if (ref.mounted && r.ok) unawaited(r.value!.status == RequestStatus.friends ? refresh() : loadRequests());
    return r;
  }

  Future<CallResult<void>> accept(String userId) async {
    final r = await _act(ref, (api) => api.post('/v1/friends/requests/$userId/accept'));
    if (ref.mounted && r.ok) unawaited(refresh());
    return r;
  }

  /// Declines an incoming request or cancels an outgoing one.
  Future<CallResult<void>> decline(String userId) async {
    final r = await _act(ref, (api) => api.delete('/v1/friends/requests/$userId'));
    if (ref.mounted && r.ok) unawaited(loadRequests());
    return r;
  }

  Future<CallResult<void>> remove(String userId) async {
    final r = await _act(ref, (api) => api.delete('/v1/friends/$userId'));
    if (ref.mounted && r.ok) unawaited(loadFriends());
    return r;
  }
}

final friendsProvider = NotifierProvider<FriendsController, FriendsState>(FriendsController.new, retry: (_, _) => null);

// ---------------------------------------------------------------------------
// Profiles and shelves

/// A profile by user id: a friend's, or the signed-in user's own (`relation: self`).
class ProfileController extends Notifier<Remote<ProfileView>> {
  ProfileController(this.userId);
  final String userId;

  @override
  Remote<ProfileView> build() {
    _account(ref);
    return const Remote();
  }

  /// A hidden profile (not a friend, or not shared) is [Fetch.failed]: the server answers 404.
  Future<void> load() async {
    await _afterBuild();
    state = Remote(status: Fetch.loading, value: state.value);
    final r = await _call(ref, (api) async => ProfileView.fromJson(_json(await api.get('/v1/users/$userId'))));
    if (!ref.mounted) return;
    state = r.ok
        ? Remote(status: Fetch.ready, value: r.value)
        : Remote(status: _failure(r.outcome), value: state.value);
  }
}

final profileProvider = NotifierProvider.family<ProfileController, Remote<ProfileView>, String>(
  ProfileController.new,
  retry: (_, _) => null,
);

class ShelfState {
  const ShelfState({this.items = const [], this.next, this.status = Fetch.idle, this.loadingMore = false});
  final List<ShelfItem> items;

  /// Cursor of the next page, null at the end.
  final String? next;
  final Fetch status;
  final bool loadingMore;
}

/// The films a friend watched, most recent first, a page at a time.
class ShelfController extends Notifier<ShelfState> {
  ShelfController(this.userId);
  final String userId;

  @override
  ShelfState build() {
    _account(ref);
    return const ShelfState();
  }

  Future<void> load() async {
    await _afterBuild();
    state = ShelfState(items: state.items, next: state.next, status: Fetch.loading);
    final r = await _call(ref, (api) async => Shelf.fromJson(_json(await api.get('/v1/users/$userId/films'))));
    if (!ref.mounted) return;
    state = r.ok
        ? ShelfState(items: r.value!.items, next: r.value!.nextCursor, status: Fetch.ready)
        : ShelfState(items: state.items, next: state.next, status: _failure(r.outcome));
  }

  Future<void> more() async {
    final cursor = state.next;
    if (cursor == null || state.loadingMore || state.status != Fetch.ready) return;
    state = ShelfState(items: state.items, next: cursor, status: Fetch.ready, loadingMore: true);
    final r = await _call(
      ref,
      (api) async => Shelf.fromJson(_json(await api.get('/v1/users/$userId/films', query: {'cursor': cursor}))),
    );
    if (!ref.mounted) return;
    state = r.ok
        ? ShelfState(items: [...state.items, ...r.value!.items], next: r.value!.nextCursor, status: Fetch.ready)
        : ShelfState(items: state.items, next: cursor, status: Fetch.ready);
  }
}

final shelfProvider = NotifierProvider.family<ShelfController, ShelfState, String>(
  ShelfController.new,
  retry: (_, _) => null,
);

// ---------------------------------------------------------------------------
// Friends who watched a film

const _watchedTtl = Duration(minutes: 10);
const _watchedCooldown = Duration(minutes: 1);

/// Friends who watched each film, by film id. A film is fetched once per 10 minutes; a failure is silent and
/// not retried for a minute. Custom films are never asked about.
class FriendsWhoWatchedController extends Notifier<Map<String, List<WatchedBy>>> {
  final _asked = <String, DateTime>{};

  @override
  Map<String, List<WatchedBy>> build() {
    _account(ref);
    return const {};
  }

  Future<void> ensure(String filmId) async {
    if (filmId.startsWith('my:') || !ref.read(onlineProvider)) return;
    final now = ref.read(nowProvider)();
    final at = _asked[filmId];
    if (at != null && now.difference(at) < _watchedTtl) return;
    _asked[filmId] = now;
    final r = await _call(
      ref,
      (api) async => FriendsWhoWatched.fromJson(_json(await api.get('/v1/films/$filmId/friends'))).items,
    );
    if (!ref.mounted) return;
    if (r.ok) {
      state = {...state, filmId: r.value!};
    } else {
      _asked[filmId] = now.subtract(_watchedTtl - _watchedCooldown);
    }
  }
}

final friendsWhoWatchedProvider = NotifierProvider<FriendsWhoWatchedController, Map<String, List<WatchedBy>>>(
  FriendsWhoWatchedController.new,
  retry: (_, _) => null,
);

// ---------------------------------------------------------------------------
// Feed

class FeedState {
  const FeedState({this.items = const [], this.next, this.status = Fetch.idle, this.loadingMore = false});
  final List<FeedItem> items;
  final String? next;
  final Fetch status;
  final bool loadingMore;
}

class FeedController extends Notifier<FeedState> {
  // ponytail: hidden items are remembered until the app closes; persist them if people ask
  final _hidden = <String>{};

  @override
  FeedState build() {
    _account(ref);
    return const FeedState();
  }

  List<FeedItem> _visible(List<FeedItem> items) => [
    for (final i in items)
      if (!_hidden.contains(i.id)) i,
  ];

  Future<void> load() async {
    await _afterBuild();
    state = FeedState(items: state.items, next: state.next, status: Fetch.loading);
    final r = await _call(ref, (api) async => Feed.fromJson(_json(await api.get('/v1/feed'))));
    if (!ref.mounted) return;
    state = r.ok
        ? FeedState(items: _visible(r.value!.items), next: r.value!.nextCursor, status: Fetch.ready)
        : FeedState(items: state.items, next: state.next, status: _failure(r.outcome));
  }

  /// The next page by cursor. A failure leaves the list as it is; the next call tries again.
  Future<void> more() async {
    final cursor = state.next;
    if (cursor == null || state.loadingMore || state.status != Fetch.ready) return;
    state = FeedState(items: state.items, next: cursor, status: Fetch.ready, loadingMore: true);
    final r = await _call(
      ref,
      (api) async => Feed.fromJson(_json(await api.get('/v1/feed', query: {'cursor': cursor}))),
    );
    if (!ref.mounted) return;
    state = r.ok
        ? FeedState(
            items: [...state.items, ..._visible(r.value!.items)],
            next: r.value!.nextCursor,
            status: Fetch.ready,
          )
        : FeedState(items: state.items, next: cursor, status: Fetch.ready);
  }

  /// Reacts (0 to 7) to what a friend watched, or clears the reaction with null. Shows it at once and
  /// takes it back if the server refuses. Only `watched` items take a reaction.
  Future<CallResult<void>> react(FeedItem item, int? reaction) async {
    if (item.kind != FeedKind.watched || (reaction != null && (reaction < 0 || reaction >= reactionCount))) {
      return CallResult<void>(CallOutcome.invalid);
    }
    void show(int? r) {
      state = FeedState(
        items: [for (final i in state.items) i.id == item.id ? i.withMyReaction(r) : i],
        next: state.next,
        status: state.status,
        loadingMore: state.loadingMore,
      );
    }

    final before = item.myReaction;
    show(reaction);
    final body = ReactionPut(userId: item.user.id, filmId: item.filmId, reaction: reaction).toJson();
    final r = await _act(ref, (api) => api.put('/v1/reactions', body: body));
    if (ref.mounted && !r.ok) show(before);
    return r;
  }

  /// Puts the film on the user's own watchlist, unless it is there already. True when it was added.
  bool addToWatchlist(FeedItem item) {
    if (ref.read(diaryProvider).wishFor(item.filmId) != null) return false;
    ref.read(diaryProvider.notifier).toggleWish(item.film);
    return true;
  }

  /// Drops an item from the feed. Nothing goes to the server.
  void hide(FeedItem item) {
    _hidden.add(item.id);
    state = FeedState(
      items: _visible(state.items),
      next: state.next,
      status: state.status,
      loadingMore: state.loadingMore,
    );
  }
}

final feedProvider = NotifierProvider<FeedController, FeedState>(FeedController.new, retry: (_, _) => null);

// ---------------------------------------------------------------------------
// Blocks and reports

class BlocksController extends Notifier<Remote<List<UserCard>>> {
  @override
  Remote<List<UserCard>> build() {
    _account(ref);
    return const Remote();
  }

  Future<void> load() async {
    await _afterBuild();
    state = Remote(status: Fetch.loading, value: state.value);
    final r = await _call(ref, (api) async => BlockList.fromJson(_json(await api.get('/v1/blocks'))).items);
    if (!ref.mounted) return;
    state = r.ok
        ? Remote(status: Fetch.ready, value: r.value)
        : Remote(status: _failure(r.outcome), value: state.value);
  }

  /// Blocks [userId]: friendship and requests go, and the person disappears from every list both ways.
  Future<CallResult<void>> block(String userId) async {
    final r = await _act(ref, (api) => api.post('/v1/blocks', body: BlockPost(userId).toJson()));
    if (ref.mounted && r.ok) {
      ref.invalidate(friendsProvider);
      ref.invalidate(feedProvider);
      unawaited(load());
    }
    return r;
  }

  Future<CallResult<void>> unblock(String userId) async {
    final r = await _act(ref, (api) => api.delete('/v1/blocks/$userId'));
    if (ref.mounted && r.ok) unawaited(load());
    return r;
  }
}

final blocksProvider = NotifierProvider<BlocksController, Remote<List<UserCard>>>(
  BlocksController.new,
  retry: (_, _) => null,
);

/// State: [Fetch.loading] while a report is on its way, else idle.
class ReportController extends Notifier<Fetch> {
  @override
  Fetch build() => Fetch.idle;

  Future<CallResult<ReportResult>> submit(ReportPost report) async {
    state = Fetch.loading;
    final r = await _call(
      ref,
      (api) async => ReportResult.fromJson(_json(await api.post('/v1/reports', body: report.toJson()))),
    );
    if (ref.mounted) state = Fetch.idle;
    return r;
  }
}

final reportProvider = NotifierProvider<ReportController, Fetch>(ReportController.new, retry: (_, _) => null);
