import 'dart:convert';

import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/recommend.dart';
import 'package:talkies/net/api.dart';

/// A released Indian film with a poster, easy to give traits.
Film film(
  String id, {
  String? title,
  List<String> dir = const [],
  List<String> cast = const [],
  List<String> g = const [],
  String lang = 'hi',
  String date = '2015-01-01',
  int pop = 10,
  bool series = false,
}) => Film(
  id: id,
  title: title ?? id,
  directors: dir,
  cast: cast,
  genres: g,
  langs: [lang],
  countries: const ['IN'],
  date: date,
  year: int.parse(date.substring(0, 4)),
  poster: '$id.jpg',
  pop: pop,
  series: series,
);

Catalog catalogOf(List<Film> films) => Catalog(films, '');

/// A taste that likes these traits (director or cast names, genres) and nothing else.
Taste tasteOf(Map<String, double> traits) =>
    Taste(traits: traits, lang: const {}, era: const {}, kind: const [1.0, 0.0], services: const {});

List<String> ids(Iterable<DeckCard> cards) => [for (final c in cards) c.id];

/// An [Api] that answers from a table of `METHOD /path` routes and keeps a log.
/// Bodies are encoded and decoded as JSON, so a body that is not JSON fails here too.
class FakeApi implements Api {
  final routes = <String, Object? Function(Map<String, String>? query, Object? body)>{};
  final log = <({String method, String path, Map<String, String>? query, Object? body})>[];

  Future<Object?> _do(String method, String path, Map<String, String>? query, Object? body) async {
    final copy = body == null ? null : jsonDecode(jsonEncode(body));
    log.add((method: method, path: path, query: query, body: copy));
    final route = routes['$method $path'];
    if (route == null) throw ApiError(404, 'not_found', 'no route $method $path');
    final reply = route(query, copy);
    return reply == null ? null : jsonDecode(jsonEncode(reply));
  }

  /// Requests so far to [method] [path].
  List<({Map<String, String>? query, Object? body})> calls(String method, String path) => [
    for (final c in log)
      if (c.method == method && c.path == path) (query: c.query, body: c.body),
  ];

  @override
  Future<Object?> get(String path, {Map<String, String>? query}) => _do('GET', path, query, null);
  @override
  Future<Object?> post(String path, {Object? body}) => _do('POST', path, null, body);
  @override
  Future<Object?> put(String path, {Object? body}) => _do('PUT', path, null, body);
  @override
  Future<Object?> patch(String path, {Object? body}) => _do('PATCH', path, null, body);
  @override
  Future<Object?> delete(String path) => _do('DELETE', path, null, null);
}

// Server JSON of backend/API.md.

Map<String, dynamic> memberJson(String id, String name, {bool me = false, bool owner = false, bool guest = false}) => {
  'id': id,
  'name': name,
  'avatar_color': 3,
  'handle': guest ? null : name.toLowerCase(),
  'guest': guest,
  'owner': owner,
  'me': me,
};

Map<String, dynamic> groupJson(
  String id, {
  String name = 'Friday gang',
  int version = 0,
  List<Map<String, dynamic>>? members,
}) => {
  'id': id,
  'name': name,
  'invite_code': 'ABCD2345',
  'deck_version': version,
  'member_count': members?.length ?? 1,
  'members': ?members,
};

Map<String, dynamic> emptyTallies() => {'tallies': <String, dynamic>{}, 'mine': <String, dynamic>{}};

Map<String, dynamic> deckJson(int version, List<String> filmIds, {int seenBy = 0}) => {
  'version': version,
  'items': [
    for (final id in filmIds) {'film_id': id, 'film': film(id).toJson(), 'seen_by': seenBy},
  ],
};

Map<String, dynamic> nightJson({
  String id = 'n1',
  String gid = 'g1',
  String status = 'poll',
  List<String> mine = const [],
  Map<String, int> approvals = const {},
}) {
  final set = status != 'poll';
  return {
    'id': id,
    'group_id': gid,
    'status': status,
    'host_id': 'm1',
    'tz_offset_min': 330,
    'place': set ? 'Home' : null,
    'options': [
      {
        'id': 'o1',
        'kind': 'film',
        'position': 0,
        'film_id': 'Q1',
        'film': film('Q1').toJson(),
        'starts_at': null,
        'approvals': approvals['o1'] ?? 0,
      },
      {
        'id': 'o2',
        'kind': 'film',
        'position': 1,
        'film_id': 'Q2',
        'film': film('Q2').toJson(),
        'starts_at': null,
        'approvals': approvals['o2'] ?? 0,
      },
      {
        'id': 'o3',
        'kind': 'slot',
        'position': 0,
        'film_id': null,
        'film': null,
        'starts_at': '2026-10-03T14:00:00.000Z',
        'approvals': approvals['o3'] ?? 0,
      },
    ],
    'mine': mine,
    'event': set
        ? {
            'film_id': 'Q1',
            'film': film('Q1').toJson(),
            'starts_at': '2026-10-03T14:00:00.000Z',
            'tz_offset_min': 330,
            'place': 'Home',
          }
        : null,
    'rsvps': <dynamic>[],
  };
}
