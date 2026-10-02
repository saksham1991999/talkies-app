import 'dart:math';

import 'models.dart';
import 'recommend.dart' show Taste;

// Groups ("crews"), the swipe deck, movie nights and chat. A local group lives
// in crews.json (members are names). A shared group lives on the server and
// only in memory here. Both use these types. `fromJson` reads the server shapes
// of backend/API.md and the local file; `toJson` writes the local file, and the
// `...Body` functions write request bodies.

final _secure = Random.secure();

/// A random version 4 uuid in lowercase, like the ids the server makes.
String newId() {
  final b = List<int>.generate(16, (_) => _secure.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')];
  String part(int from, int to) => h.sublist(from, to).join();
  return '${part(0, 4)}-${part(4, 6)}-${part(6, 8)}-${part(8, 10)}-${part(10, 16)}';
}

/// UTC ISO-8601 with milliseconds and `Z`: the one time format of the API.
String wireTime(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true).toIso8601String();

DateTime parseTime(Object? s) => DateTime.parse(s as String).toUtc();

/// A film snapshot. The wire id may sit beside the snapshot instead of in it.
Film _film(Object? json, [Object? id]) {
  final m = Map<String, dynamic>.from(json as Map);
  if (id != null) m['id'] ??= id;
  return Film.fromJson(m);
}

List<T> _list<T>(Object? json, T Function(Map<String, dynamic> j) parse) => [
  for (final e in (json as List? ?? const [])) parse(e as Map<String, dynamic>),
];

int _int(Object? v, [int or = 0]) => v is num ? v.toInt() : or;

/// Trimmed text, or null when nothing is left.
String? blankToNull(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();

// ---------------------------------------------------------------------------
// People

class Member {
  const Member({
    required this.id,
    required this.name,
    this.ink = 0,
    this.handle,
    this.guest = false,
    this.owner = false,
    this.me = false,
  });

  /// Member id (not a user id). Local ids are made by [newId].
  final String id;

  /// May be empty for [me] in a local group: the UI writes "You".
  final String name;

  /// Stamp ink, 0 to 10 (`avatar_color` on the wire).
  final int ink;
  final String? handle;

  /// A name without an account.
  final bool guest, owner, me;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    ink: _int(j['avatar_color']).clamp(0, 10),
    handle: j['handle'] as String?,
    guest: (j['guest'] as bool?) ?? false,
    owner: (j['owner'] as bool?) ?? false,
    me: (j['me'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar_color': ink,
    'handle': handle,
    'guest': guest,
    'owner': owner,
    'me': me,
  };

  Member copyWith({String? name, int? ink, bool? owner}) => Member(
    id: id,
    name: name ?? this.name,
    ink: ink ?? this.ink,
    handle: handle,
    guest: guest,
    owner: owner ?? this.owner,
    me: me,
  );
}

/// The `card` a chat message names as its sender.
class Sender {
  const Sender({required this.id, this.handle, this.name, this.ink = 0});
  final String id;
  final String? handle, name;
  final int ink;

  factory Sender.fromJson(Map<String, dynamic> j) => Sender(
    id: j['id'] as String,
    handle: j['handle'] as String?,
    name: j['display_name'] as String?,
    ink: _int(j['avatar_color']).clamp(0, 10),
  );
}

/// Smallest ink in 0 to 10 that no member uses, else the next in turn.
int nextInk(List<Member> members) {
  final used = {for (final m in members) m.ink};
  for (var i = 0; i <= 10; i++) {
    if (!used.contains(i)) return i;
  }
  return members.length % 11;
}

/// Names from the "who you went with" of past stubs, most frequent first, for
/// member suggestions. A value splits on commas, `&` and " and ".
// ponytail: the first spelling seen wins when names differ only by case
List<String> companyNames(Diary d) {
  final count = <String, int>{};
  final spelling = <String, String>{};
  final split = RegExp(r',|&|\s+and\s+', caseSensitive: false);
  for (final s in d.stubs) {
    for (final part in (s.company ?? '').split(split)) {
      final name = part.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      spelling.putIfAbsent(key, () => name);
      count[key] = (count[key] ?? 0) + 1;
    }
  }
  final keys = count.keys.toList()
    ..sort((a, b) {
      final c = count[b]!.compareTo(count[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final k in keys) spelling[k]!];
}

// ---------------------------------------------------------------------------
// Shared list, deck, swipes

/// A film on a group's shared list.
class WatchItem {
  const WatchItem(this.film);
  final Film film;

  String get filmId => film.id;

  factory WatchItem.fromJson(Map<String, dynamic> j) => WatchItem(_film(j['film'], j['film_id']));
  static List<WatchItem> listFromJson(Object? json) => _list((json as Map)['items'], WatchItem.fromJson);

  Map<String, dynamic> toJson() => {'film_id': film.id, 'film': film.toJson()};
}

enum Vote { want, skip, seen }

/// Swipes on one film, summed over members.
class Tally {
  const Tally({this.want = 0, this.skip = 0, this.seen = 0});
  final int want, skip, seen;

  factory Tally.fromJson(Map<String, dynamic> j) =>
      Tally(want: _int(j['want']), skip: _int(j['skip']), seen: _int(j['seen']));
}

class DeckCard {
  const DeckCard({required this.film, this.seenBy = 0, this.wishers = 0});
  final Film film;

  /// Members who have seen the film. The server counts them by its Seen rule.
  /// For a deck built here: 1 when this phone's diary has the film.
  final int seenBy;

  /// How many watchlists and lists want the film. Known only for a deck built on
  /// this phone (a deck read from the server has 0).
  final int wishers;

  String get id => film.id;

  factory DeckCard.fromJson(Map<String, dynamic> j) =>
      DeckCard(film: _film(j['film'], j['film_id']), seenBy: _int(j['seen_by']), wishers: _int(j['wishers']));

  Map<String, dynamic> toJson() => {
    'film_id': film.id,
    'film': film.toJson(),
    'seen_by': seenBy,
    if (wishers > 0) 'wishers': wishers,
  };
}

class Deck {
  const Deck({required this.version, this.cards = const []});
  final int version;
  final List<DeckCard> cards;

  factory Deck.fromJson(Map<String, dynamic> j) =>
      Deck(version: _int(j['version']), cards: _list(j['items'], DeckCard.fromJson));

  Map<String, dynamic> toJson() => {
    'version': version,
    'items': [for (final c in cards) c.toJson()],
  };
}

/// Everything GET /deck-inputs says. Nothing in it names a member.
class DeckInputs {
  const DeckInputs({this.tastes = const [], this.seen = const {}, this.wanted = const []});

  /// One per member with an account and a taste. Bad uploads are dropped.
  final List<Taste> tastes;
  final Set<String> seen;

  /// Film and how many watchlists and lists want it.
  final List<({Film film, int n})> wanted;

  factory DeckInputs.fromJson(Map<String, dynamic> j) => DeckInputs(
    tastes: [for (final t in (j['tastes'] as List? ?? const [])) ?Taste.tryFromJson(t)],
    seen: {for (final x in (j['seen'] as List? ?? const [])) x as String},
    wanted: [
      for (final w in (j['wanted'] as List? ?? const []))
        (film: _film((w as Map)['film'], w['film_id']), n: _int(w['n'], 1)),
    ],
  );
}

/// One swipe. A null [memberId] is the caller.
class Swipe {
  const Swipe({this.memberId, required this.filmId, required this.vote});
  final String? memberId;
  final String filmId;
  final Vote vote;

  Map<String, dynamic> toJson() => {'film_id': filmId, 'vote': vote.name, 'member_id': memberId};
}

/// GET /tallies: counts for every film, and the votes of one member.
class TalliesReply {
  const TalliesReply({this.tallies = const {}, this.mine = const {}});
  final Map<String, Tally> tallies;
  final Map<String, Vote> mine;

  factory TalliesReply.fromJson(Map<String, dynamic> j) => TalliesReply(
    tallies: {
      for (final e in ((j['tallies'] as Map?) ?? const {}).entries)
        e.key as String: Tally.fromJson(e.value as Map<String, dynamic>),
    },
    mine: _votes(j['mine']),
  );
}

/// Film id to vote. An unknown vote from a newer server is dropped.
Map<String, Vote> _votes(Object? json) {
  final out = <String, Vote>{};
  for (final e in ((json as Map?) ?? const {}).entries) {
    final v = e.value is String ? Vote.values.asNameMap()[e.value] : null;
    if (v != null) out[e.key as String] = v;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Nights

enum NightStatus { poll, set, done }

enum Rsvp { yes, no, maybe }

enum OptionKind { film, slot }

/// A film or a time the group votes on.
class NightOption {
  const NightOption({
    required this.id,
    required this.kind,
    required this.position,
    this.film,
    this.startsAt,
    this.approvals = 0,
  });
  final String id;
  final OptionKind kind;

  /// Order of creation inside its kind. Ties in a poll go to the lowest.
  final int position;
  final Film? film;

  /// UTC. Set for a slot.
  final DateTime? startsAt;

  /// Members who approved it. Counted here for a local night, by the server for a shared one.
  final int approvals;

  factory NightOption.fromJson(Map<String, dynamic> j) => NightOption(
    id: j['id'] as String,
    kind: OptionKind.values.byName(j['kind'] as String),
    position: _int(j['position']),
    film: j['film'] == null ? null : _film(j['film'], j['film_id']),
    startsAt: j['starts_at'] == null ? null : parseTime(j['starts_at']),
    approvals: _int(j['approvals']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'position': position,
    'film_id': film?.id,
    'film': film?.toJson(),
    'starts_at': startsAt == null ? null : wireTime(startsAt!),
    'approvals': approvals,
  };

  NightOption withApprovals(int n) =>
      NightOption(id: id, kind: kind, position: position, film: film, startsAt: startsAt, approvals: n);
}

/// What a night was decided to be.
class NightEvent {
  const NightEvent({required this.film, required this.startsAt, this.tzOffsetMin = 0, this.place});
  final Film film;

  /// UTC instant.
  final DateTime startsAt;

  /// Minutes the group's clock is ahead of UTC when the night was made.
  final int tzOffsetMin;
  final String? place;

  /// A UTC value whose fields read the group's wall clock.
  DateTime get wallClock => startsAt.add(Duration(minutes: tzOffsetMin));

  factory NightEvent.fromJson(Map<String, dynamic> j) => NightEvent(
    film: _film(j['film'], j['film_id']),
    startsAt: parseTime(j['starts_at']),
    tzOffsetMin: _int(j['tz_offset_min']),
    place: j['place'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'film_id': film.id,
    'film': film.toJson(),
    'starts_at': wireTime(startsAt),
    'tz_offset_min': tzOffsetMin,
    'place': place,
  };
}

class Night {
  const Night({
    required this.id,
    required this.crewId,
    this.status = NightStatus.poll,
    this.hostId,
    this.tzOffsetMin = 0,
    this.place,
    this.options = const [],
    this.votes = const {},
    this.event,
    this.rsvps = const {},
  });
  final String id, crewId;
  final NightStatus status;

  /// Member id of the host. Null when the host left.
  final String? hostId;
  final int tzOffsetMin;
  final String? place;
  final List<NightOption> options;

  /// Option ids each member approved. A local night knows every member. A shared
  /// night knows the caller, and a guest after the owner asked for it.
  final Map<String, Set<String>> votes;
  final NightEvent? event;

  /// Only members who replied.
  final Map<String, Rsvp> rsvps;

  List<NightOption> get films => [
    for (final o in options)
      if (o.kind == OptionKind.film) o,
  ];
  List<NightOption> get slots => [
    for (final o in options)
      if (o.kind == OptionKind.slot) o,
  ];

  /// The film to show: the decided one, else the first candidate.
  Film? get film => event?.film ?? films.firstOrNull?.film;

  /// The decided start, else the earliest candidate slot. UTC.
  DateTime? get when {
    if (event != null) return event!.startsAt;
    final times = [for (final s in slots) ?s.startsAt]..sort();
    return times.firstOrNull;
  }

  /// [mineFor] is the member `mine` belongs to in a server reply.
  factory Night.fromJson(Map<String, dynamic> j, {String? mineFor}) {
    final votes = <String, Set<String>>{};
    if (j['votes'] case final Map v) {
      for (final e in v.entries) {
        votes[e.key as String] = {for (final x in e.value as List) x as String};
      }
    } else if (mineFor != null && j['mine'] != null) {
      votes[mineFor] = {for (final x in j['mine'] as List) x as String};
    }
    return Night(
      id: j['id'] as String,
      crewId: j['group_id'] as String,
      status: NightStatus.values.byName(j['status'] as String),
      hostId: j['host_id'] as String?,
      tzOffsetMin: _int(j['tz_offset_min']),
      place: j['place'] as String?,
      options: _list(j['options'], NightOption.fromJson),
      votes: votes,
      event: j['event'] == null ? null : NightEvent.fromJson(j['event'] as Map<String, dynamic>),
      rsvps: {
        for (final r in (j['rsvps'] as List? ?? const []))
          (r as Map)['member_id'] as String: Rsvp.values.byName(r['response'] as String),
      },
    );
  }

  static List<Night> listFromJson(Object? json, {String? mineFor}) => [
    for (final e in ((json as Map)['items'] as List? ?? const []))
      Night.fromJson(e as Map<String, dynamic>, mineFor: mineFor),
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': crewId,
    'status': status.name,
    'host_id': hostId,
    'tz_offset_min': tzOffsetMin,
    'place': place,
    'options': [for (final o in options) o.toJson()],
    'votes': {for (final e in votes.entries) e.key: (e.value.toList()..sort())},
    'event': event?.toJson(),
    'rsvps': [
      for (final e in rsvps.entries) {'member_id': e.key, 'response': e.value.name},
    ],
  };

  Night copyWith({
    NightStatus? status,
    List<NightOption>? options,
    Map<String, Set<String>>? votes,
    NightEvent? event,
    Map<String, Rsvp>? rsvps,
    String? hostId,
  }) => Night(
    id: id,
    crewId: crewId,
    status: status ?? this.status,
    hostId: hostId ?? this.hostId,
    tzOffsetMin: tzOffsetMin,
    place: place,
    options: options ?? this.options,
    votes: votes ?? this.votes,
    event: event ?? this.event,
    rsvps: rsvps ?? this.rsvps,
  );
}

/// What the host asks for: 1 to 3 films and 1 to 2 times. One film and one time
/// make a night that is already set; anything else is a poll.
class NightCreate {
  const NightCreate({required this.films, required this.slots, this.tzOffsetMin = 0, this.place});
  final List<Film> films;
  final List<DateTime> slots;
  final int tzOffsetMin;
  final String? place;

  /// The limits the server enforces, so the phone can say no first.
  bool isValid(DateTime now) =>
      films.isNotEmpty &&
      films.length <= 3 &&
      {for (final f in films) f.id}.length == films.length &&
      slots.isNotEmpty &&
      slots.length <= 2 &&
      {for (final s in slots) s.millisecondsSinceEpoch}.length == slots.length &&
      slots.every(
        (s) => s.isAfter(now.subtract(const Duration(days: 1))) && s.isBefore(now.add(const Duration(days: 400))),
      );

  Map<String, dynamic> toJson() => {
    'films': [for (final f in films) WatchItem(f).toJson()],
    'slots': [for (final s in slots) wireTime(s)],
    'tz_offset_min': tzOffsetMin,
    'place': blankToNull(place),
  };
}

// ---------------------------------------------------------------------------
// Chat

enum MessageKind { text, system }

class Message {
  const Message({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.sender,
    this.body,
    this.code,
    this.args,
    this.filmId,
    this.film,
    this.nightId,
  });
  final int id;
  final MessageKind kind;
  final DateTime createdAt;
  final Sender? sender;

  /// Text of a `text` message.
  final String? body;

  /// A `system` message: what happened (`joined`, `left`, `poll_open`, `night_set`, `wrapped`) and its arguments.
  /// The app writes the sentence in its own language.
  final String? code;
  final Map<String, dynamic>? args;
  final String? filmId;
  final Film? film;
  final String? nightId;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: _int(j['id']),
    // An unknown kind from a newer server shows as a system line the UI can skip.
    kind: MessageKind.values.asNameMap()[j['kind']] ?? MessageKind.system,
    createdAt: parseTime(j['created_at']),
    sender: j['sender'] == null ? null : Sender.fromJson(j['sender'] as Map<String, dynamic>),
    body: j['body'] as String?,
    code: j['code'] as String?,
    args: j['args'] == null ? null : Map<String, dynamic>.from(j['args'] as Map),
    filmId: j['film_id'] as String?,
    film: j['film'] == null ? null : _film(j['film'], j['film_id']),
    nightId: j['night_id'] as String?,
  );
}

class MessagePage {
  const MessagePage(this.items, this.hasMore);
  final List<Message> items;
  final bool hasMore;

  factory MessagePage.fromJson(Map<String, dynamic> j) =>
      MessagePage(_list(j['items'], Message.fromJson), (j['has_more'] as bool?) ?? false);
}

// ---------------------------------------------------------------------------
// The group

/// A group with everything this phone knows about it. A shared group starts as a
/// header (name, members, nights) and gains films, deck and votes when its
/// screen loads them.
class Crew {
  const Crew({
    required this.id,
    required this.name,
    this.shared = false,
    this.members = const [],
    this.inviteCode,
    this.deckVersion = 0,
    this.films = const [],
    this.deck,
    this.votes = const {},
    this.tallies = const {},
    this.nights = const [],
  });
  final String id, name;

  /// Lives on the server. A group with no account behind it is local.
  final bool shared;
  final List<Member> members;
  final String? inviteCode;
  final int deckVersion;

  /// The shared list.
  final List<WatchItem> films;
  final Deck? deck;

  /// Member id to film id to vote. A local group knows every member. A shared one
  /// knows the caller, and a guest after the owner asked for it.
  final Map<String, Map<String, Vote>> votes;

  /// Counts over all members. Derived from [votes] for a local group, from the server for a shared one.
  final Map<String, Tally> tallies;
  final List<Night> nights;

  Member? get me => members.where((m) => m.me).firstOrNull;
  bool get isOwner => me?.owner ?? false;

  /// Whether I may close, delete or wrap up [n]: I am its host or the group owner.
  bool isHost(Night n) => isOwner || (me != null && n.hostId == me!.id);
  Member? member(String id) => members.where((m) => m.id == id).firstOrNull;
  Night? night(String id) => nights.where((n) => n.id == id).firstOrNull;

  Crew copyWith({
    String? name,
    List<Member>? members,
    String? inviteCode,
    int? deckVersion,
    List<WatchItem>? films,
    Deck? deck,
    Map<String, Map<String, Vote>>? votes,
    Map<String, Tally>? tallies,
    List<Night>? nights,
  }) => Crew(
    id: id,
    name: name ?? this.name,
    shared: shared,
    members: members ?? this.members,
    inviteCode: inviteCode ?? this.inviteCode,
    deckVersion: deckVersion ?? this.deckVersion,
    films: films ?? this.films,
    deck: deck ?? this.deck,
    votes: votes ?? this.votes,
    tallies: tallies ?? this.tallies,
    nights: nights ?? this.nights,
  );

  /// The server's `group` or `group_detail`, or an entry of crews.json.
  factory Crew.fromJson(Map<String, dynamic> j, {bool shared = true}) => Crew(
    id: j['id'] as String,
    name: j['name'] as String,
    shared: shared,
    members: _list(j['members'], Member.fromJson),
    inviteCode: j['invite_code'] as String?,
    deckVersion: _int(j['deck_version']),
    films: _list(j['films'], WatchItem.fromJson),
    deck: j['deck'] == null ? null : Deck.fromJson(j['deck'] as Map<String, dynamic>),
    votes: {for (final m in ((j['swipes'] as Map?) ?? const {}).entries) m.key as String: _votes(m.value)},
    nights: _list(j['nights'], Night.fromJson),
  );

  static List<Crew> listFromJson(Object? json) => _list((json as Map)['items'], Crew.fromJson);

  /// The entry of crews.json. [tallies] is derived and not written.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (inviteCode != null) 'invite_code': inviteCode,
    'deck_version': deckVersion,
    'members': [for (final m in members) m.toJson()],
    'films': [for (final f in films) f.toJson()],
    if (deck != null) 'deck': deck!.toJson(),
    'swipes': {
      for (final m in votes.entries) m.key: {for (final v in m.value.entries) v.key: v.value.name},
    },
    'nights': [for (final n in nights) n.toJson()],
  };
}

// ---------------------------------------------------------------------------
// Replies with one value, and request bodies. The repositories and the contract
// test (test/backend_examples_crews_test.dart) share these.

String parseInviteCode(Object? json) => (json as Map)['invite_code'] as String;
int parseDeckPutResult(Object? json) => _int((json as Map)['version']);
int parseSwipesResult(Object? json) => _int((json as Map)['saved']);
Map<String, int> parseVotesResult(Object? json) => {
  for (final e in ((json as Map)['approvals'] as Map).entries) e.key as String: _int(e.value),
};
({int created, int skipped}) parseWrapupResult(Object? json) =>
    (created: _int((json as Map)['created']), skipped: _int(json['skipped']));

Map<String, dynamic> groupCreateBody(String name) => {'name': name};
Map<String, dynamic> groupPatchBody(String name) => {'name': name};
Map<String, dynamic> joinPostBody(String code) => {'code': code};
Map<String, dynamic> guestPostBody(String name) => {'name': name};
Map<String, dynamic> groupFilmPutBody(Film film) => {'film': film.toJson()};

Map<String, dynamic> deckPutBody(int baseVersion, List<DeckCard> cards) => {
  'base_version': baseVersion,
  'items': [for (final c in cards) WatchItem(c.film).toJson()],
};

Map<String, dynamic> swipesPutBody(List<Swipe> swipes) => {
  'swipes': [for (final s in swipes) s.toJson()],
};

Map<String, dynamic> votesPutBody(Iterable<String> optionIds, String? memberId) => {
  'option_ids': optionIds.toList(),
  'member_id': memberId,
};

Map<String, dynamic> closePostBody({String? filmOptionId, String? slotOptionId, String? place}) => {
  'film_option_id': filmOptionId,
  'slot_option_id': slotOptionId,
  'place': place,
};

Map<String, dynamic> rsvpPutBody(Rsvp response, String? memberId) => {'response': response.name, 'member_id': memberId};

Map<String, dynamic> messagePostBody(String body, {Film? film, String? nightId}) => {
  'body': body,
  'film_id': film?.id,
  'film': film?.toJson(),
  'night_id': nightId,
};

Map<String, dynamic> wrapupPostBody({String? seatRow, int? firstSeat, List<String>? memberIds}) => {
  'seat_row': seatRow,
  'first_seat': firstSeat,
  'member_ids': memberIds,
};

Map<String, dynamic> sendFilmBody(String userId, Film film, {String? note}) => {
  'user_id': userId,
  'film_id': film.id,
  'film': film.toJson(),
  'note': note,
};
