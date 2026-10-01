/// Models of the social API (backend/API.md, phases 1 and 2). Each one mirrors
/// its wire JSON exactly: `toJson` of a parsed model gives back the same JSON,
/// which `test/backend_examples_test.dart` checks against the shared examples.
/// None of the response models holds a diary date.
library;

import '../config.dart';
import 'catalog.dart';
import 'models.dart';
import 'stats.dart';

Map<String, dynamic> _map(Object? v) => v as Map<String, dynamic>;

List<T> _list<T>(Object? v, T Function(Map<String, dynamic> j) parse) => [for (final e in v as List) parse(_map(e))];

// ---------------------------------------------------------------------------
// People

/// A person as others see them. (Named `UserCard` because `Card` is a Flutter widget.)
class UserCard {
  const UserCard({required this.id, this.handle, this.displayName, this.avatarColor = 0});

  final String id;
  final String? handle;
  final String? displayName;

  /// Index of the stamp ink, 0 to 10.
  final int avatarColor;

  /// The name to show: display name, else the handle, else empty.
  String get label => displayName ?? handle ?? '';

  factory UserCard.fromJson(Map<String, dynamic> j) => UserCard(
    id: j['id'] as String,
    handle: j['handle'] as String?,
    displayName: j['display_name'] as String?,
    avatarColor: j['avatar_color'] as int,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'handle': handle,
    'display_name': displayName,
    'avatar_color': avatarColor,
  };
}

enum ProfileVisibility { private, friends }

/// The signed-in user's own profile (`me`).
class Me {
  const Me({
    required this.id,
    this.handle,
    this.displayName,
    this.avatarColor = 0,
    this.visibility = ProfileVisibility.private,
    this.shareRatings = false,
  });

  final String id;
  final String? handle;
  final String? displayName;
  final int avatarColor;
  final ProfileVisibility visibility;
  final bool shareRatings;

  UserCard get card => UserCard(id: id, handle: handle, displayName: displayName, avatarColor: avatarColor);

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as String,
    handle: j['handle'] as String?,
    displayName: j['display_name'] as String?,
    avatarColor: j['avatar_color'] as int,
    visibility: ProfileVisibility.values.byName(j['visibility'] as String),
    shareRatings: j['share_ratings'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'handle': handle,
    'display_name': displayName,
    'avatar_color': avatarColor,
    'visibility': visibility.name,
    'share_ratings': shareRatings,
  };
}

/// `PATCH /v1/me`: only what is set travels. Use the `clear` flags to send null.
class MePatch {
  const MePatch({
    this.handle,
    this.clearHandle = false,
    this.displayName,
    this.clearDisplayName = false,
    this.avatarColor,
    this.visibility,
    this.shareRatings,
  });

  final String? handle;
  final bool clearHandle;
  final String? displayName;
  final bool clearDisplayName;
  final int? avatarColor;
  final ProfileVisibility? visibility;
  final bool? shareRatings;

  factory MePatch.fromJson(Map<String, dynamic> j) => MePatch(
    handle: j['handle'] as String?,
    clearHandle: j.containsKey('handle') && j['handle'] == null,
    displayName: j['display_name'] as String?,
    clearDisplayName: j.containsKey('display_name') && j['display_name'] == null,
    avatarColor: j['avatar_color'] as int?,
    visibility: j['visibility'] == null ? null : ProfileVisibility.values.byName(j['visibility'] as String),
    shareRatings: j['share_ratings'] as bool?,
  );

  Map<String, dynamic> toJson() => {
    if (clearHandle) 'handle': null else if (handle != null) 'handle': handle,
    if (clearDisplayName) 'display_name': null else if (displayName != null) 'display_name': displayName,
    if (avatarColor != null) 'avatar_color': avatarColor,
    if (visibility != null) 'visibility': visibility!.name,
    if (shareRatings != null) 'share_ratings': shareRatings,
  };
}

// ---------------------------------------------------------------------------
// Server and sign-in

/// `GET /healthz`.
class Health {
  const Health({required this.ok, required this.api, required this.auth});

  final bool ok;
  final int api;

  /// Sign-in methods the server offers: `email`, `google`, `apple`.
  final List<String> auth;

  /// A Talkies server this build can talk to.
  bool get usable => ok && api == kApiVersion;

  factory Health.fromJson(Map<String, dynamic> j) =>
      Health(ok: j['ok'] as bool, api: j['api'] as int, auth: ((j['auth'] as List?) ?? const []).cast<String>());

  /// Null unless [j] is a usable health reply. Anything else means the server is down.
  static Health? tryParse(Object? j) {
    try {
      final h = Health.fromJson(_map(j));
      return h.usable ? h : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {'ok': ok, 'api': api, 'auth': auth};
}

/// The error body of every non-2xx reply.
class ErrorBody {
  const ErrorBody({required this.code, required this.message, this.detail});

  final String code;
  final String message;
  final Object? detail;

  factory ErrorBody.fromJson(Map<String, dynamic> j) {
    final e = _map(j['error']);
    return ErrorBody(code: e['code'] as String, message: e['message'] as String, detail: e['detail']);
  }

  Map<String, dynamic> toJson() => {
    'error': {'code': code, 'message': message, 'detail': detail},
  };
}

/// What sign-in and refresh return (`session`).
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
  });

  final String accessToken;
  final String refreshToken;

  /// Epoch seconds.
  final int expiresAt;
  final String userId;

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
    accessToken: j['access_token'] as String,
    refreshToken: j['refresh_token'] as String,
    expiresAt: j['expires_at'] as int,
    userId: _map(j['user'])['id'] as String,
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt,
    'user': {'id': userId},
  };
}

class OtpRequest {
  const OtpRequest(this.email);
  final String email;
  factory OtpRequest.fromJson(Map<String, dynamic> j) => OtpRequest(j['email'] as String);
  Map<String, dynamic> toJson() => {'email': email};
}

class VerifyRequest {
  const VerifyRequest(this.email, this.code);
  final String email, code;
  factory VerifyRequest.fromJson(Map<String, dynamic> j) => VerifyRequest(j['email'] as String, j['code'] as String);
  Map<String, dynamic> toJson() => {'email': email, 'code': code};
}

class RefreshRequest {
  const RefreshRequest(this.refreshToken);
  final String refreshToken;
  factory RefreshRequest.fromJson(Map<String, dynamic> j) => RefreshRequest(j['refresh_token'] as String);
  Map<String, dynamic> toJson() => {'refresh_token': refreshToken};
}

class IdTokenRequest {
  const IdTokenRequest({
    required this.provider,
    required this.idToken,
    this.accessToken,
    this.nonce,
    this.authorizationCode,
  });

  /// `google` or `apple`.
  final String provider;
  final String idToken;
  final String? accessToken;

  /// The raw nonce. For Apple, the SHA-256 of it went to Apple.
  final String? nonce;

  /// Apple's authorization code, when the sign-in returned one.
  final String? authorizationCode;

  factory IdTokenRequest.fromJson(Map<String, dynamic> j) => IdTokenRequest(
    provider: j['provider'] as String,
    idToken: j['id_token'] as String,
    accessToken: j['access_token'] as String?,
    nonce: j['nonce'] as String?,
    authorizationCode: j['authorization_code'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'id_token': idToken,
    'access_token': accessToken,
    'nonce': nonce,
    'authorization_code': authorizationCode,
  };
}

// ---------------------------------------------------------------------------
// Friends

/// How another person relates to the signed-in user.
enum Relation { none, friend, incoming, outgoing, self }

class UserLookup {
  const UserLookup({required this.card, required this.relation});
  final UserCard card;
  final Relation relation;

  factory UserLookup.fromJson(Map<String, dynamic> j) =>
      UserLookup(card: UserCard.fromJson(_map(j['card'])), relation: Relation.values.byName(j['relation'] as String));

  Map<String, dynamic> toJson() => {'card': card.toJson(), 'relation': relation.name};
}

class FriendRequestPost {
  const FriendRequestPost(this.userId);
  final String userId;
  factory FriendRequestPost.fromJson(Map<String, dynamic> j) => FriendRequestPost(j['user_id'] as String);
  Map<String, dynamic> toJson() => {'user_id': userId};
}

enum RequestStatus { pending, friends }

class FriendRequestResult {
  const FriendRequestResult(this.status);
  final RequestStatus status;
  factory FriendRequestResult.fromJson(Map<String, dynamic> j) =>
      FriendRequestResult(RequestStatus.values.byName(j['status'] as String));
  Map<String, dynamic> toJson() => {'status': status.name};
}

class FriendRequests {
  const FriendRequests({this.incoming = const [], this.outgoing = const []});
  final List<UserCard> incoming, outgoing;

  factory FriendRequests.fromJson(Map<String, dynamic> j) => FriendRequests(
    incoming: _list(j['incoming'], UserCard.fromJson),
    outgoing: _list(j['outgoing'], UserCard.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'incoming': [for (final c in incoming) c.toJson()],
    'outgoing': [for (final c in outgoing) c.toJson()],
  };
}

/// Taste match with a friend. `pct` is null when the two shelves share no film.
class TasteMatch {
  const TasteMatch({required this.both, this.pct});
  final int both;
  final int? pct;
  factory TasteMatch.fromJson(Map<String, dynamic> j) => TasteMatch(both: j['both'] as int, pct: j['pct'] as int?);
  Map<String, dynamic> toJson() => {'both': both, 'pct': pct};
}

class FriendItem {
  const FriendItem({required this.card, required this.visible, this.match});
  final UserCard card;

  /// False when the friend does not share their profile with friends.
  final bool visible;
  final TasteMatch? match;

  factory FriendItem.fromJson(Map<String, dynamic> j) => FriendItem(
    card: UserCard.fromJson(_map(j['card'])),
    visible: j['visible'] as bool,
    match: j['match'] == null ? null : TasteMatch.fromJson(_map(j['match'])),
  );

  Map<String, dynamic> toJson() => {'card': card.toJson(), 'visible': visible, 'match': match?.toJson()};
}

class FriendList {
  const FriendList(this.items);
  final List<FriendItem> items;
  factory FriendList.fromJson(Map<String, dynamic> j) => FriendList(_list(j['items'], FriendItem.fromJson));
  Map<String, dynamic> toJson() => {
    'items': [for (final i in items) i.toJson()],
  };
}

// ---------------------------------------------------------------------------
// Profiles and shelves. The film snapshot stays as JSON, so a model re-encodes
// exactly; `film` parses it once, when a screen asks.

class ProfileStats {
  const ProfileStats({
    required this.films,
    required this.viewings,
    this.avgRating,
    this.topGenres = const [],
    this.topLangs = const [],
  });

  final int films, viewings;
  final double? avgRating;
  final List<String> topGenres, topLangs;

  factory ProfileStats.fromJson(Map<String, dynamic> j) => ProfileStats(
    films: j['films'] as int,
    viewings: j['viewings'] as int,
    avgRating: (j['avg_rating'] as num?)?.toDouble(),
    topGenres: (j['top_genres'] as List).cast<String>(),
    topLangs: (j['top_langs'] as List).cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'films': films,
    'viewings': viewings,
    'avg_rating': avgRating,
    'top_genres': topGenres,
    'top_langs': topLangs,
  };
}

class TopFilm {
  TopFilm({required this.filmId, required this.filmJson, this.rating});

  factory TopFilm.of(Film f, double? rating) => TopFilm(filmId: f.id, filmJson: f.toJson(), rating: rating);

  final String filmId;
  final Map<String, dynamic> filmJson;
  final double? rating;
  late final Film film = Film.fromJson(filmJson);

  factory TopFilm.fromJson(Map<String, dynamic> j) =>
      TopFilm(filmId: j['film_id'] as String, filmJson: _map(j['film']), rating: (j['rating'] as num?)?.toDouble());

  Map<String, dynamic> toJson() => {'film_id': filmId, 'film': filmJson, 'rating': rating};
}

/// A watchlist entry of someone else: the film and nothing else.
class WatchItem {
  WatchItem({required this.filmId, required this.filmJson});

  factory WatchItem.of(Film f) => WatchItem(filmId: f.id, filmJson: f.toJson());

  final String filmId;
  final Map<String, dynamic> filmJson;
  late final Film film = Film.fromJson(filmJson);

  factory WatchItem.fromJson(Map<String, dynamic> j) =>
      WatchItem(filmId: j['film_id'] as String, filmJson: _map(j['film']));

  Map<String, dynamic> toJson() => {'film_id': filmId, 'film': filmJson};
}

class ProfileView {
  const ProfileView({
    required this.card,
    required this.relation,
    required this.visible,
    this.match,
    this.stats,
    this.topFilms = const [],
    this.watchlist = const [],
  });

  final UserCard card;

  /// `self` or `friend`.
  final Relation relation;
  final bool visible;
  final TasteMatch? match;
  final ProfileStats? stats;
  final List<TopFilm> topFilms;
  final List<WatchItem> watchlist;

  factory ProfileView.fromJson(Map<String, dynamic> j) => ProfileView(
    card: UserCard.fromJson(_map(j['card'])),
    relation: Relation.values.byName(j['relation'] as String),
    visible: j['visible'] as bool,
    match: j['match'] == null ? null : TasteMatch.fromJson(_map(j['match'])),
    stats: j['stats'] == null ? null : ProfileStats.fromJson(_map(j['stats'])),
    topFilms: _list(j['top_films'], TopFilm.fromJson),
    watchlist: _list(j['watchlist'], WatchItem.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'card': card.toJson(),
    'relation': relation.name,
    'visible': visible,
    'match': match?.toJson(),
    'stats': stats?.toJson(),
    'top_films': [for (final f in topFilms) f.toJson()],
    'watchlist': [for (final w in watchlist) w.toJson()],
  };

  /// The offline "Your profile" preview: what a friend would see, built from the
  /// local diary with the same rules as the server (no private stubs, catalog
  /// films only, at most 10 top films and 50 watchlist films, no dates). Ratings
  /// show when [ratings] is true.
  factory ProfileView.fromDiary(Diary diary, Catalog catalog, {UserCard? card, bool ratings = true}) {
    final d = diary.publicView();
    final stubs = [
      for (final s in d.stubs)
        if (!s.filmId.startsWith('my:')) s,
    ];
    final st = computeStats(d.copyWith(stubs: stubs), const Period(StatsScope.all, 0));
    Film? filmOf(String id) => catalog.byId[id] ?? d.films[id];

    final best = <String, double>{};
    final views = <String, int>{};
    final last = <String, DateTime>{};
    for (final s in stubs) {
      views[s.filmId] = (views[s.filmId] ?? 0) + 1;
      if (s.rating case final r? when r > (best[s.filmId] ?? 0)) best[s.filmId] = r;
      final t = s.date ?? s.created;
      if (!(last[s.filmId]?.isAfter(t) ?? false)) last[s.filmId] = t;
    }
    // Highest rating first when ratings show, else most viewings. The last watch only breaks ties.
    final ids = [
      for (final id in views.keys)
        if (filmOf(id) != null) id,
    ];
    ids.sort((a, b) {
      var c = ratings ? (best[b] ?? -1).compareTo(best[a] ?? -1) : 0;
      if (c == 0) c = views[b]!.compareTo(views[a]!);
      if (c == 0) c = last[b]!.compareTo(last[a]!);
      return c != 0 ? c : a.compareTo(b);
    });

    final wished = [
      for (final w in d.wishes)
        if (!w.filmId.startsWith('my:') && filmOf(w.filmId) != null) w,
    ]..sort((a, b) => b.added.compareTo(a.added));

    return ProfileView(
      card: card ?? const UserCard(id: ''),
      relation: Relation.self,
      visible: true,
      stats: ProfileStats(
        films: views.length,
        viewings: stubs.length,
        avgRating: ratings ? st.avgRating : null,
        topGenres: [for (final b in st.genres.take(3)) b.key],
        topLangs: [for (final b in st.languages.take(3)) b.key],
      ),
      topFilms: [for (final id in ids.take(10)) TopFilm.of(filmOf(id)!, ratings ? best[id] : null)],
      watchlist: [for (final w in wished.take(50)) WatchItem.of(filmOf(w.filmId)!)],
    );
  }
}

class ShelfItem {
  ShelfItem({required this.filmId, required this.filmJson, this.rating, required this.viewings});

  final String filmId;
  final Map<String, dynamic> filmJson;
  final double? rating;
  final int viewings;
  late final Film film = Film.fromJson(filmJson);

  factory ShelfItem.fromJson(Map<String, dynamic> j) => ShelfItem(
    filmId: j['film_id'] as String,
    filmJson: _map(j['film']),
    rating: (j['rating'] as num?)?.toDouble(),
    viewings: j['viewings'] as int,
  );

  Map<String, dynamic> toJson() => {'film_id': filmId, 'film': filmJson, 'rating': rating, 'viewings': viewings};
}

class Shelf {
  const Shelf({required this.items, this.nextCursor});
  final List<ShelfItem> items;
  final String? nextCursor;

  factory Shelf.fromJson(Map<String, dynamic> j) =>
      Shelf(items: _list(j['items'], ShelfItem.fromJson), nextCursor: j['next_cursor'] as String?);

  Map<String, dynamic> toJson() => {
    'items': [for (final i in items) i.toJson()],
    'next_cursor': nextCursor,
  };
}

/// One friend who watched a film.
class WatchedBy {
  const WatchedBy({required this.user, this.rating});
  final UserCard user;
  final double? rating;

  factory WatchedBy.fromJson(Map<String, dynamic> j) =>
      WatchedBy(user: UserCard.fromJson(_map(j['user'])), rating: (j['rating'] as num?)?.toDouble());

  Map<String, dynamic> toJson() => {'user': user.toJson(), 'rating': rating};
}

class FriendsWhoWatched {
  const FriendsWhoWatched(this.items);
  final List<WatchedBy> items;
  factory FriendsWhoWatched.fromJson(Map<String, dynamic> j) =>
      FriendsWhoWatched(_list(j['items'], WatchedBy.fromJson));
  Map<String, dynamic> toJson() => {
    'items': [for (final i in items) i.toJson()],
  };
}

// ---------------------------------------------------------------------------
// Feed, reactions, blocks, reports

enum FeedKind { watched, reaction, sent }

/// Reactions 0 to 7 map to a fixed emoji set in the UI.
const reactionCount = 8;

class FeedItem {
  FeedItem({
    required this.id,
    required this.kind,
    required this.user,
    required this.filmId,
    required this.filmJson,
    this.rating,
    this.reaction,
    this.note,
    this.myReaction,
  });

  /// `<w|r|s>:<feed_seq>`.
  final String id;
  final FeedKind kind;

  /// Who watched, reacted or sent.
  final UserCard user;
  final String filmId;
  final Map<String, dynamic> filmJson;
  final double? rating;

  /// The reaction of [user] on `reaction` items.
  final int? reaction;
  final String? note;

  /// The signed-in user's own reaction, on `watched` items.
  final int? myReaction;
  late final Film film = Film.fromJson(filmJson);

  FeedItem withMyReaction(int? r) => FeedItem(
    id: id,
    kind: kind,
    user: user,
    filmId: filmId,
    filmJson: filmJson,
    rating: rating,
    reaction: reaction,
    note: note,
    myReaction: r,
  );

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
    id: j['id'] as String,
    kind: FeedKind.values.byName(j['kind'] as String),
    user: UserCard.fromJson(_map(j['user'])),
    filmId: j['film_id'] as String,
    filmJson: _map(j['film']),
    rating: (j['rating'] as num?)?.toDouble(),
    reaction: j['reaction'] as int?,
    note: j['note'] as String?,
    myReaction: j['my_reaction'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'user': user.toJson(),
    'film_id': filmId,
    'film': filmJson,
    'rating': rating,
    'reaction': reaction,
    'note': note,
    'my_reaction': myReaction,
  };
}

class Feed {
  const Feed({required this.items, this.nextCursor});
  final List<FeedItem> items;
  final String? nextCursor;

  factory Feed.fromJson(Map<String, dynamic> j) =>
      Feed(items: _list(j['items'], FeedItem.fromJson), nextCursor: j['next_cursor'] as String?);

  Map<String, dynamic> toJson() => {
    'items': [for (final i in items) i.toJson()],
    'next_cursor': nextCursor,
  };
}

class ReactionPut {
  const ReactionPut({required this.userId, required this.filmId, this.reaction});
  final String userId, filmId;

  /// 0 to 7, or null to clear.
  final int? reaction;

  factory ReactionPut.fromJson(Map<String, dynamic> j) =>
      ReactionPut(userId: j['user_id'] as String, filmId: j['film_id'] as String, reaction: j['reaction'] as int?);

  Map<String, dynamic> toJson() => {'user_id': userId, 'film_id': filmId, 'reaction': reaction};
}

class BlockPost {
  const BlockPost(this.userId);
  final String userId;
  factory BlockPost.fromJson(Map<String, dynamic> j) => BlockPost(j['user_id'] as String);
  Map<String, dynamic> toJson() => {'user_id': userId};
}

class BlockList {
  const BlockList(this.items);
  final List<UserCard> items;
  factory BlockList.fromJson(Map<String, dynamic> j) => BlockList(_list(j['items'], UserCard.fromJson));
  Map<String, dynamic> toJson() => {
    'items': [for (final c in items) c.toJson()],
  };
}

enum ReportKind { user, message, group }

enum ReportReason { spam, abuse, harassment, inappropriate, other }

class ReportPost {
  const ReportPost({required this.kind, required this.targetId, required this.reason, this.note});
  final ReportKind kind;

  /// A uuid for `user` and `group`, the message id as text for `message`.
  final String targetId;
  final ReportReason reason;
  final String? note;

  factory ReportPost.fromJson(Map<String, dynamic> j) => ReportPost(
    kind: ReportKind.values.byName(j['kind'] as String),
    targetId: j['target_id'] as String,
    reason: ReportReason.values.byName(j['reason'] as String),
    note: j['note'] as String?,
  );

  Map<String, dynamic> toJson() => {'kind': kind.name, 'target_id': targetId, 'reason': reason.name, 'note': note};
}

class ReportResult {
  const ReportResult(this.id);
  final String id;
  factory ReportResult.fromJson(Map<String, dynamic> j) => ReportResult(j['id'] as String);
  Map<String, dynamic> toJson() => {'id': id};
}
