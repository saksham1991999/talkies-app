import 'package:flutter/material.dart';

import '../data/models.dart';
import '../l10n/labels.dart';
import 'format.dart';
import 'theme.dart';
import 'together_widgets.dart';

/// What the deck shows: genre, language, decade, streaming service, film or
/// series. A filter only hides cards from the swiper; the deck itself is not
/// changed, and nothing is voted on.
class DeckFilters {
  const DeckFilters({this.genre, this.lang, this.decade, this.ott, this.series});
  final String? genre, lang, ott;

  /// 1990 for the 1990s.
  final int? decade;

  /// True: series only. False: films only.
  final bool? series;

  bool get active => genre != null || lang != null || decade != null || ott != null || series != null;

  bool matches(Film f) =>
      (genre == null || f.genres.contains(genre)) &&
      (lang == null || f.langs.contains(lang)) &&
      (decade == null || (f.year != null && f.year! ~/ 10 * 10 == decade)) &&
      (ott == null || f.ott.contains(ott)) &&
      (series == null || f.series == series);

  DeckFilters copyWith({
    String? Function()? genre,
    String? Function()? lang,
    int? Function()? decade,
    String? Function()? ott,
    bool? Function()? series,
  }) => DeckFilters(
    genre: genre == null ? this.genre : genre(),
    lang: lang == null ? this.lang : lang(),
    decade: decade == null ? this.decade : decade(),
    ott: ott == null ? this.ott : ott(),
    series: series == null ? this.series : series(),
  );
}

/// The values of [of] over [films], most common first, at most [max].
List<T> _common<T extends Object>(Iterable<Film> films, Iterable<T> Function(Film) of, int max) {
  final count = <T, int>{};
  for (final f in films) {
    for (final v in of(f)) {
      count[v] = (count[v] ?? 0) + 1;
    }
  }
  final keys = count.keys.toList()
    ..sort((a, b) {
      final c = count[b]!.compareTo(count[a]!);
      return c != 0 ? c : '$a'.compareTo('$b');
    });
  return keys.take(max).toList();
}

/// Opens the filters sheet over the films of the deck. Every change is reported at once.
Future<void> showDeckFilters(
  BuildContext context, {
  required List<Film> films,
  required DeckFilters filters,
  required bool hideSeen,
  required ValueChanged<DeckFilters> onFilters,
  required ValueChanged<bool> onHideSeen,
}) => showSheet<void>(
  context,
  (_) =>
      _FiltersSheet(films: films, filters: filters, hideSeen: hideSeen, onFilters: onFilters, onHideSeen: onHideSeen),
);

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({
    required this.films,
    required this.filters,
    required this.hideSeen,
    required this.onFilters,
    required this.onHideSeen,
  });
  final List<Film> films;
  final DeckFilters filters;
  final bool hideSeen;
  final ValueChanged<DeckFilters> onFilters;
  final ValueChanged<bool> onHideSeen;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late var _f = widget.filters;
  late var _hide = widget.hideSeen;

  void _set(DeckFilters f) {
    setState(() => _f = f);
    widget.onFilters(f);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final films = widget.films;
    final genres = _common<String>(films, (f) => f.genres, 12);
    // Every language counts: a film that matches only on its second language must be reachable too.
    final langs = _common<String>(films, (f) => f.langs, 10);
    final decades = _common<int>(films, (f) => [if (f.year != null) f.year! ~/ 10 * 10], 20)..sort((a, b) => b - a);
    final services = _common<String>(films, (f) => f.ott, 8);
    final kinds = {for (final f in films) f.series};
    return SheetBody(
      title: l.deckFilters,
      children: [
        SwitchListTile(
          key: const Key('deck-hide-seen'),
          contentPadding: EdgeInsets.zero,
          title: Text(l.deckHideSeen, style: const TextStyle(fontWeight: FontWeight.w700)),
          value: _hide,
          onChanged: (v) {
            setState(() => _hide = v);
            widget.onHideSeen(v);
          },
        ),
        if (kinds.length > 1)
          _Group<bool>(
            title: l.filterKind,
            options: [(false, l.kindFilm), (true, l.kindSeries)],
            value: _f.series,
            onPick: (v) => _set(_f.copyWith(series: () => v)),
          ),
        if (genres.length > 1)
          _Group<String>(
            title: l.byGenre,
            options: [for (final g in genres) (g, genreName(context, g))],
            value: _f.genre,
            onPick: (v) => _set(_f.copyWith(genre: () => v)),
          ),
        if (langs.length > 1)
          _Group<String>(
            title: l.language,
            options: [for (final c in langs) (c, langName(context, c))],
            value: _f.lang,
            onPick: (v) => _set(_f.copyWith(lang: () => v)),
          ),
        if (decades.length > 1)
          _Group<int>(
            title: l.byDecade,
            options: [for (final d in decades) (d, l.decadeLabel('$d'))],
            value: _f.decade,
            onPick: (v) => _set(_f.copyWith(decade: () => v)),
          ),
        if (services.isNotEmpty)
          _Group<String>(
            title: l.availableOn,
            options: [for (final s in services) (s, ottName(s))],
            value: _f.ott,
            onPick: (v) => _set(_f.copyWith(ott: () => v)),
          ),
        if (_f.active)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('deck-reset-filters'),
              onPressed: () => _set(const DeckFilters()),
              child: Text(
                l.resetFilters,
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

/// One filter: "All" and the options, as ticket class boxes. Picking the chosen box again clears it.
class _Group<T extends Object> extends StatelessWidget {
  const _Group({required this.title, required this.options, required this.value, required this.onPick});
  final String title;
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T?> onPick;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TapBox(label: context.l.filterAll, selected: value == null, onTap: () => onPick(null)),
              for (final (v, label) in options)
                TapBox(label: label, selected: value == v, onTap: () => onPick(value == v ? null : v)),
            ],
          ),
        ],
      ),
    );
  }
}
