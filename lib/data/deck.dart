import 'dart:math';

import 'catalog.dart';
import 'crews.dart';
import 'models.dart';
import 'recommend.dart';

// The group deck and its results. Pure functions: the same inputs give the same
// deck whatever the order of the members, so a deck built on any phone matches.

/// Recommendations in a deck, the cards a deck may hold (the server takes 120),
/// and how many recommendations survive the cap when the catalog has them.
const deckRecs = 60, deckCap = 100, deckMinRecs = 20;

const _pool = 4000;

/// Added to a watchlist card for the share of the group that wants it.
const _wishW = 0.35;

/// A film that members want and how many watchlists and lists name it.
typedef Wanted = ({Film film, int n});

/// Votes (member id to film id to vote) summed per film.
Map<String, Tally> tallies(Map<String, Map<String, Vote>> votes) {
  final want = <String, int>{}, skip = <String, int>{}, seen = <String, int>{};
  for (final member in votes.values) {
    for (final MapEntry(key: film, value: vote) in member.entries) {
      final n = switch (vote) {
        Vote.want => want,
        Vote.skip => skip,
        Vote.seen => seen,
      };
      n[film] = (n[film] ?? 0) + 1;
    }
  }
  return {
    for (final id in {...want.keys, ...skip.keys, ...seen.keys})
      id: Tally(want: want[id] ?? 0, skip: skip[id] ?? 0, seen: seen[id] ?? 0),
  };
}

/// Cards for the results list: most want first, then fewest seen, then fewest
/// skip, then deck order.
List<DeckCard> resultsOrder(List<DeckCard> cards, Map<String, Tally> tallies) {
  Tally t(DeckCard c) => tallies[c.id] ?? const Tally();
  final ranked = [for (var i = 0; i < cards.length; i++) (i, cards[i])];
  ranked.sort((a, b) {
    final (x, y) = (t(a.$2), t(b.$2));
    final c = y.want != x.want
        ? y.want.compareTo(x.want)
        : x.seen != y.seen
        ? x.seen.compareTo(y.seen)
        : x.skip.compareTo(y.skip);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final r in ranked) r.$2];
}

/// "Tonight": one film picked at random among those tied at the top want count,
/// then the next best in [ranked] (the output of [resultsOrder]) up to three.
/// Empty when nobody wants anything.
List<DeckCard> tonightPick(List<DeckCard> ranked, Map<String, Tally> tallies, Random rnd) {
  int want(DeckCard c) => tallies[c.id]?.want ?? 0;
  final top = ranked.fold(0, (m, c) => max(m, want(c)));
  if (top == 0) return const [];
  final tied = [
    for (final c in ranked)
      if (want(c) == top) c,
  ];
  final winner = tied[rnd.nextInt(tied.length)];
  return [winner, ...ranked.where((c) => c != winner).take(2)];
}

typedef _Row = ({DeckCard card, double score, bool rec});

/// The deck: every film in [wanted], then up to [deckRecs] diverse
/// recommendations from the [_pool] most popular catalog films that are
/// released, regional (Indian unless [worldwide]), not a series, not wanted and
/// not in [seen]. When fewer than [deckRecs] films have a score, the most
/// popular ones fill the rest.
///
/// [tastes] holds the members that have one; [members] is the head count. A
/// film's score is the blend (half the mean, half the minimum) of the members'
/// scores, each divided by that member's 95th percentile and clamped to 0..1, so
/// one member who dislikes it pulls it down. A wanted film adds [_wishW] times
/// the share of the group that wants it. Cards sort by score, then popularity,
/// then id, and the deck keeps [deckCap] of them, at least [deckMinRecs] of them
/// recommendations when there are that many.
// ponytail: runs on the calling thread (about 4000 films times members); move into Isolate.run if it janks
List<DeckCard> buildDeck({
  required Catalog catalog,
  required List<Taste> tastes,
  required int members,
  required List<Wanted> wanted,
  required Set<String> seen,
  required DateTime today,
  required bool worldwide,
}) {
  final want = <String, Wanted>{};
  for (final w in wanted) {
    final old = want[w.film.id];
    want[w.film.id] = (film: old?.film ?? w.film, n: (old?.n ?? 0) + w.n);
  }

  // Candidates: the most popular films that pass the filters, in a fixed order.
  // The filters come before the cut: in the bundled catalog only 59 of the 4000
  // most popular films of all are Indian, so cutting first would leave no deck.
  final items = catalog.items;
  final t0 = ymd(today);
  // Seen films are deliberately excluded here on both paths (the `seen` set the
  // server gathers in deck-inputs, and the local one), so they never come back.
  // The deck_filters "hide seen" switch only controls unvoted wanted-film cards
  // and the "seen by N" label; it cannot and does not rebuild the deck.
  final cand = <int>[
    for (var i = 0; i < items.length; i++)
      if (_eligible(items[i], today, t0, worldwide) && !want.containsKey(items[i].id) && !seen.contains(items[i].id)) i,
  ];
  cand.sort((a, b) {
    final (x, y) = (items[a], items[b]);
    final c = y.pop.compareTo(x.pop);
    return c != 0 ? c : x.id.compareTo(y.id);
  });
  if (cand.length > _pool) cand.removeRange(_pool, cand.length);

  // One score per film: candidates first, then wanted films.
  final films = [for (final i in cand) items[i], for (final w in want.values) w.film];
  final blend = _blend(catalog, tastes, films);

  // Recommendations: the best by score, diversified; then the most popular if short.
  final recScore = {for (var k = 0; k < cand.length; k++) cand[k]: blend[k]};
  final ranked = [
    for (final i in cand)
      if (recScore[i]! > 0) i,
  ]..sort((a, b) => _byScore(recScore[a]!, items[a], recScore[b]!, items[b]));
  // diverse() leaves equal scores in no promised order: make every score distinct.
  final scored = <(double, int)>[];
  var prev = double.infinity;
  for (final i in ranked) {
    final s = recScore[i]! < prev ? recScore[i]! : prev * (1 - 1e-12);
    scored.add((s, i));
    prev = s;
  }
  final picked = diverse(catalog, scored, deckRecs, <int>{});
  if (picked.length < deckRecs) {
    final have = picked.toSet();
    for (final i in cand) {
      if (picked.length >= deckRecs) break;
      if (have.add(i)) picked.add(i);
    }
  }

  final rows = <_Row>[for (final i in picked) (card: DeckCard(film: items[i]), score: recScore[i]!, rec: true)];
  final heads = max(1, max(members, tastes.length));
  var k = cand.length;
  for (final w in want.values) {
    final share = min(1.0, w.n / heads);
    rows.add((
      card: DeckCard(film: w.film, seenBy: seen.contains(w.film.id) ? 1 : 0, wishers: w.n),
      score: blend[k++] + _wishW * share,
      rec: false,
    ));
  }

  rows.sort((a, b) => _byScore(a.score, a.card.film, b.score, b.card.film));
  return [for (final r in _cap(rows)) r.card];
}

bool _eligible(Film f, DateTime today, String t0, bool worldwide) {
  if (f.series) return false;
  // No year, or this year with no date, is mostly an announced film.
  if (f.year == null || (f.date == null && f.year! >= today.year)) return false;
  return !unreleased(f, t0) && (worldwide || isIndian(f));
}

/// Score down, then popularity down, then id up.
int _byScore(double sa, Film a, double sb, Film b) {
  final c = sb.compareTo(sa);
  if (c != 0) return c;
  final p = b.pop.compareTo(a.pop);
  return p != 0 ? p : a.id.compareTo(b.id);
}

/// The blend of the members' normalized scores for each of [films]. All 0 when
/// no member has a taste.
List<double> _blend(Catalog catalog, List<Taste> tastes, List<Film> films) {
  final norm = <List<double>>[];
  for (final taste in tastes) {
    final raw = [for (final f in films) scoreFor(catalog, f, taste) ?? 0.0];
    final positive = raw.where((x) => x > 0).toList()..sort();
    final p95 = positive.isEmpty ? 0.0 : positive[((positive.length - 1) * 0.95).round()];
    norm.add([for (final x in raw) p95 > 0 ? (x / p95).clamp(0.0, 1.0) : 0.0]);
  }
  if (norm.isEmpty) return List.filled(films.length, 0.0);
  return [
    for (var i = 0; i < films.length; i++) _mix([for (final m in norm) m[i]]),
  ];
}

/// Half the mean, half the minimum. Sorted first, so the sum is the same for any member order.
double _mix(List<double> v) {
  v.sort();
  return 0.5 * (v.fold(0.0, (a, b) => a + b) / v.length) + 0.5 * v.first;
}

/// The best [deckCap] rows, keeping at least [deckMinRecs] recommendations.
List<_Row> _cap(List<_Row> rows) {
  if (rows.length <= deckCap) return rows;
  final out = rows.take(deckCap).toList();
  final keep = min(deckMinRecs, rows.where((r) => r.rec).length);
  final missing = keep - out.where((r) => r.rec).length;
  if (missing <= 0) return out;
  final extra = rows.skip(deckCap).where((r) => r.rec).take(missing).toList();
  var drop = extra.length;
  for (var i = out.length - 1; i >= 0 && drop > 0; i--) {
    if (!out[i].rec) {
      out.removeAt(i);
      drop--;
    }
  }
  return [...out, ...extra]..sort((a, b) => _byScore(a.score, a.card.film, b.score, b.card.film));
}
