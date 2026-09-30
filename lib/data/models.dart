/// Plain data types. Films use the compact keys of assets/catalog/catalog.json
/// so catalog entries, diary snapshots and backups share one codec.
library;

enum DatePrecision { day, month, year, none }

enum VenueType { cinema, ott, home, tv, other }

const wikimediaBase = 'https://upload.wikimedia.org/wikipedia/';

/// Indian languages, in the order the language filter shows them.
const indianLangs = ['hi', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'pa', 'gu', 'or', 'as', 'bho', 'ur'];

class Film {
  const Film({
    required this.id,
    required this.title,
    this.original,
    this.year,
    this.date,
    this.runtime,
    this.directors = const [],
    this.cast = const [],
    this.genres = const [],
    this.langs = const [],
    this.countries = const [],
    this.ott = const [],
    this.poster,
    this.wiki,
    this.pop = 0,
    this.series = false,
    this.seasons,
  });

  /// Wikidata QID, or `my:<n>` for a film the user typed in.
  final String id;
  final String title;

  /// Title in the original script (Devanagari, Tamil, ...), when different.
  final String? original;
  final int? year;

  /// Release date: `YYYY`, `YYYY-MM` or `YYYY-MM-DD` (India release if known).
  final String? date;
  final int? runtime;
  final List<String> directors, cast, genres, langs, countries, ott;

  /// Path under [wikimediaBase], or `file:<path>` for a user photo, relative
  /// to the app documents directory (iOS moves that directory on updates).
  final String? poster;
  final String? wiki;
  final int pop;
  final bool series;
  final int? seasons;

  bool get isCustom => id.startsWith('my:');

  /// Language to show for the film: an Indian one when the film has one.
  String? get mainLang => langs.where(indianLangs.contains).firstOrNull ?? langs.firstOrNull;

  String? get posterUrl {
    final p = poster;
    if (p == null || p.isEmpty || p.startsWith('file:')) return null;
    return wikimediaBase + p;
  }

  String? get posterFile => poster != null && poster!.startsWith('file:') ? poster!.substring(5) : null;

  /// Release day when the catalog knows the exact day.
  DateTime? get releaseDay {
    final d = date;
    if (d == null || d.length != 10) return null;
    return DateTime.tryParse(d);
  }

  /// Sort key for release: exact days first inside a month, unknown last.
  String get releaseSortKey => (date ?? '9999').padRight(10, '~');

  static List<String> _list(Object? v) => v == null ? const [] : (v as List).cast<String>();

  factory Film.fromJson(Map<String, dynamic> j) => Film(
    id: j['id'] as String,
    title: j['t'] as String,
    original: j['o'] as String?,
    year: j['y'] as int?,
    date: j['d'] as String?,
    runtime: j['rt'] as int?,
    directors: _list(j['dir']),
    cast: _list(j['cast']),
    genres: _list(j['g']),
    langs: _list(j['l']),
    countries: _list(j['c']),
    ott: _list(j['ott']),
    poster: j['p'] as String?,
    // The catalog omits the Wikipedia title when it equals the title.
    wiki: (j['w'] as String?) ?? ((j['id'] as String).startsWith('Q') ? j['t'] as String : null),
    pop: (j['pop'] as int?) ?? 0,
    series: j['k'] == 's',
    seasons: j['sn'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    't': title,
    if (original != null) 'o': original,
    if (year != null) 'y': year,
    if (date != null) 'd': date,
    if (runtime != null) 'rt': runtime,
    if (directors.isNotEmpty) 'dir': directors,
    if (cast.isNotEmpty) 'cast': cast,
    if (genres.isNotEmpty) 'g': genres,
    if (langs.isNotEmpty) 'l': langs,
    if (countries.isNotEmpty) 'c': countries,
    if (ott.isNotEmpty) 'ott': ott,
    if (poster != null) 'p': poster,
    if (wiki != null && wiki != title) 'w': wiki,
    if (pop != 0) 'pop': pop,
    if (series) 'k': 's',
    if (seasons != null) 'sn': seasons,
  };

  Film withOtt(List<String> services) => Film(
    id: id,
    title: title,
    original: original,
    year: year,
    date: date,
    runtime: runtime,
    directors: directors,
    cast: cast,
    genres: genres,
    langs: langs,
    countries: countries,
    ott: services,
    poster: poster,
    wiki: wiki,
    pop: pop,
    series: series,
    seasons: seasons,
  );

  Film copyWith({String? title, int? year, String? poster, List<String>? langs, int? runtime, bool? series}) => Film(
    id: id,
    title: title ?? this.title,
    original: original,
    year: year ?? this.year,
    date: date,
    runtime: runtime ?? this.runtime,
    directors: directors,
    cast: cast,
    genres: genres,
    langs: langs ?? this.langs,
    countries: countries,
    ott: ott,
    poster: poster ?? this.poster,
    wiki: wiki,
    pop: pop,
    series: series ?? this.series,
    seasons: seasons,
  );
}

/// One viewing. Every rewatch is a new stub.
class Stub {
  const Stub({
    required this.id,
    required this.no,
    required this.filmId,
    required this.created,
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
  });

  final String id;

  /// Ticket number, printed in red on the stub. Never reused.
  final int no;
  final String filmId;
  final DateTime created;

  /// Local calendar date. For month or year precision the day (and month) is 1.
  final DateTime? date;
  final DatePrecision precision;

  /// 0.1 to 5.0, or null for no rating.
  final double? rating;

  /// Venue name, see [Venue].
  final String? place;
  final String memo;
  final List<String> tags;

  // Cinema-hall details.
  final String? show; // morning, matinee, evening, night, late
  final String? format; // 2d, 3d, imax, 4dx, ...
  final String? seatClass;
  final String? seat;
  final double? price;

  /// First Day First Show.
  final bool fdfs;

  /// Language the user watched it in, when dubbed.
  final String? lang;
  final String? company;

  bool get hasDate => date != null && precision != DatePrecision.none;

  /// Sort key. An undated viewing is one the user cannot remember, so it most
  /// likely came first: it sorts before every dated stub.
  DateTime get sortDate => hasDate ? date! : DateTime(0);

  factory Stub.fromJson(Map<String, dynamic> j) => Stub(
    id: j['id'] as String,
    no: j['no'] as int,
    filmId: j['film'] as String,
    created: DateTime.parse(j['created'] as String),
    date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
    precision: DatePrecision.values.byName((j['prec'] as String?) ?? 'day'),
    rating: (j['rating'] as num?)?.toDouble(),
    place: j['place'] as String?,
    memo: (j['memo'] as String?) ?? '',
    tags: ((j['tags'] as List?) ?? const []).cast<String>(),
    show: j['show'] as String?,
    format: j['format'] as String?,
    seatClass: j['class'] as String?,
    seat: j['seat'] as String?,
    price: (j['price'] as num?)?.toDouble(),
    fdfs: (j['fdfs'] as bool?) ?? false,
    lang: j['lang'] as String?,
    company: j['with'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'no': no,
    'film': filmId,
    'created': created.toIso8601String(),
    if (date != null) 'date': ymd(date!),
    'prec': precision.name,
    if (rating != null) 'rating': rating,
    if (place != null) 'place': place,
    if (memo.isNotEmpty) 'memo': memo,
    if (tags.isNotEmpty) 'tags': tags,
    if (show != null) 'show': show,
    if (format != null) 'format': format,
    if (seatClass != null) 'class': seatClass,
    if (seat != null) 'seat': seat,
    if (price != null) 'price': price,
    if (fdfs) 'fdfs': true,
    if (lang != null) 'lang': lang,
    if (company != null) 'with': company,
  };
}

/// Watchlist entry.
class Wish {
  const Wish({required this.filmId, required this.added, this.planned});
  final String filmId;
  final DateTime added;
  final DateTime? planned;

  factory Wish.fromJson(Map<String, dynamic> j) => Wish(
    filmId: j['film'] as String,
    added: DateTime.parse(j['added'] as String),
    planned: j['planned'] == null ? null : DateTime.parse(j['planned'] as String),
  );

  Map<String, dynamic> toJson() => {
    'film': filmId,
    'added': added.toIso8601String(),
    if (planned != null) 'planned': ymd(planned!),
  };
}

class Venue {
  const Venue(this.name, this.type);
  final String name;
  final VenueType type;

  factory Venue.fromJson(Map<String, dynamic> j) =>
      Venue(j['name'] as String, VenueType.values.byName(j['type'] as String));
  Map<String, dynamic> toJson() => {'name': name, 'type': type.name};
}

const defaultVenues = [
  Venue('Cinema hall', VenueType.cinema),
  Venue('Home', VenueType.home),
  Venue('Netflix', VenueType.ott),
  Venue('Prime Video', VenueType.ott),
  Venue('JioHotstar', VenueType.ott),
  Venue('SonyLIV', VenueType.ott),
  Venue('ZEE5', VenueType.ott),
  Venue('aha', VenueType.ott),
  Venue('Sun NXT', VenueType.ott),
  Venue('TV', VenueType.tv),
];

/// Everything the user owns. Persisted as one JSON file.
class Diary {
  const Diary({
    this.films = const {},
    this.stubs = const [],
    this.wishes = const [],
    this.tags = const [],
    this.venues = defaultVenues,
    this.nextNo = 1,
    this.hidden = const [],
  });

  /// Snapshot of every film referenced by a stub or wish, so records never
  /// depend on the catalog version.
  final Map<String, Film> films;
  final List<Stub> stubs;
  final List<Wish> wishes;
  final List<String> tags;
  final List<Venue> venues;
  final int nextNo;

  /// Film ids marked "Not interested" in recommendations.
  final List<String> hidden;

  Diary copyWith({
    Map<String, Film>? films,
    List<Stub>? stubs,
    List<Wish>? wishes,
    List<String>? tags,
    List<Venue>? venues,
    int? nextNo,
    List<String>? hidden,
  }) => Diary(
    films: films ?? this.films,
    stubs: stubs ?? this.stubs,
    wishes: wishes ?? this.wishes,
    tags: tags ?? this.tags,
    venues: venues ?? this.venues,
    nextNo: nextNo ?? this.nextNo,
    hidden: hidden ?? this.hidden,
  );

  factory Diary.fromJson(Map<String, dynamic> j) => Diary(
    films: {
      for (final f in ((j['films'] as List?) ?? const []).map((e) => Film.fromJson(e as Map<String, dynamic>))) f.id: f,
    },
    stubs: ((j['stubs'] as List?) ?? const []).map((e) => Stub.fromJson(e as Map<String, dynamic>)).toList(),
    wishes: ((j['wishes'] as List?) ?? const []).map((e) => Wish.fromJson(e as Map<String, dynamic>)).toList(),
    tags: ((j['tags'] as List?) ?? const []).cast<String>(),
    venues: j['venues'] == null
        ? defaultVenues
        : (j['venues'] as List).map((e) => Venue.fromJson(e as Map<String, dynamic>)).toList(),
    nextNo: (j['nextNo'] as int?) ?? 1,
    hidden: ((j['hidden'] as List?) ?? const []).cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'films': films.values.map((f) => f.toJson()).toList(),
    'stubs': stubs.map((s) => s.toJson()).toList(),
    'wishes': wishes.map((w) => w.toJson()).toList(),
    'tags': tags,
    'venues': venues.map((v) => v.toJson()).toList(),
    'nextNo': nextNo,
    if (hidden.isNotEmpty) 'hidden': hidden,
  };

  VenueType venueType(String? name) {
    for (final v in venues) {
      if (v.name == name) return v.type;
    }
    return VenueType.other;
  }

  List<Stub> stubsOf(String filmId) => stubs.where((s) => s.filmId == filmId).toList()..sort(byWatchOrder);

  /// 1 for the first viewing of a film, 2 for the second, and so on.
  int viewingNumber(Stub s) => stubsOf(s.filmId).indexWhere((x) => x.id == s.id) + 1;

  Wish? wishFor(String filmId) {
    for (final w in wishes) {
      if (w.filmId == filmId) return w;
    }
    return null;
  }
}

/// Oldest first. Same day: lower ticket number first.
int byWatchOrder(Stub a, Stub b) {
  final c = a.sortDate.compareTo(b.sortDate);
  return c != 0 ? c : a.no.compareTo(b.no);
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
