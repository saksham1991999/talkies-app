import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog.dart' show norm;
import '../../data/models.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';

enum StubSort { newest, oldest, ratingHigh, ratingLow }

class StubFilter {
  const StubFilter({this.place, this.tag, this.year, this.series, this.minStars});
  final String? place, tag;
  final int? year;
  final bool? series;
  final int? minStars;

  bool get isEmpty => place == null && tag == null && year == null && series == null && minStars == null;

  bool test(Stub s, Film? f) =>
      (place == null || s.place == place) &&
      (tag == null || s.tags.contains(tag)) &&
      (year == null || (s.hasDate && s.date!.year == year)) &&
      (series == null || (f?.series ?? false) == series) &&
      (minStars == null || (s.rating ?? 0) >= minStars!);
}

/// Sorts and filters stubs; shared by the list and by tests.
List<Stub> queryStubs(
  Diary d, {
  String query = '',
  StubFilter filter = const StubFilter(),
  StubSort sort = StubSort.newest,
}) {
  final q = norm(query);
  final out = d.stubs.where((s) {
    final f = d.films[s.filmId];
    if (!filter.test(s, f)) return false;
    if (q.isEmpty) return true;
    return norm('${f?.title ?? ''} ${f?.original ?? ''} ${s.memo} ${s.tags.join(' ')} ${s.place ?? ''}').contains(q);
  }).toList();
  switch (sort) {
    case StubSort.newest:
      out.sort((a, b) => byWatchOrder(b, a));
    case StubSort.oldest:
      out.sort(byWatchOrder);
    case StubSort.ratingHigh:
      out.sort(
        (a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1) != 0
            ? (b.rating ?? -1).compareTo(a.rating ?? -1)
            : byWatchOrder(b, a),
      );
    case StubSort.ratingLow:
      out.sort(
        (a, b) => (a.rating ?? 99).compareTo(b.rating ?? 99) != 0
            ? (a.rating ?? 99).compareTo(b.rating ?? 99)
            : byWatchOrder(b, a),
      );
  }
  return out;
}

class StubsScreen extends ConsumerStatefulWidget {
  const StubsScreen({super.key});

  @override
  ConsumerState<StubsScreen> createState() => _StubsScreenState();
}

class _StubsScreenState extends ConsumerState<StubsScreen> {
  var _sort = StubSort.newest;
  var _filter = const StubFilter();
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _sortName(StubSort s) => switch (s) {
    StubSort.newest => context.l.sortNewest,
    StubSort.oldest => context.l.sortOldest,
    StubSort.ratingHigh => context.l.sortRatingHigh,
    StubSort.ratingLow => context.l.sortRatingLow,
  };

  @override
  Widget build(BuildContext context) {
    final diary = ref.watch(diaryProvider);
    final grid = ref.watch(settingsProvider.select((s) => s.recordsGrid));
    final p = Palette.of(context);
    final l = context.l;
    final list = queryStubs(diary, query: _q.text, filter: _filter, sort: _sort);
    final byDate = _sort == StubSort.newest || _sort == StubSort.oldest;

    return Scaffold(
      floatingActionButton: RecordFab(onPressed: () => startRecord(context), tooltip: l.recordFilm),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(
                l.tabStubs,
                sub: Text(
                  l.ticketsCount(diary.stubs.length),
                  style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w600),
                ),
                actions: [
                  TkButton(
                    grid ? Tk.list : Tk.grid,
                    tooltip: grid ? l.listView : l.gridView,
                    onPressed: () => ref.read(settingsProvider.notifier).set((s) => s.copyWith(recordsGrid: !grid)),
                  ),
                  PopupMenuButton<StubSort>(
                    tooltip: l.sort,
                    icon: const TkIcon(Tk.sort),
                    initialValue: _sort,
                    onSelected: (s) => setState(() => _sort = s),
                    itemBuilder: (_) => [
                      for (final s in StubSort.values)
                        CheckedPopupMenuItem(value: s, checked: s == _sort, child: Text(_sortName(s))),
                    ],
                  ),
                  Badge(
                    isLabelVisible: !_filter.isEmpty,
                    smallSize: 8,
                    backgroundColor: p.accent,
                    child: TkButton(Tk.filter, tooltip: l.filter, onPressed: _openFilter),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l.searchStubs,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: TkIcon(Tk.search, size: 20, color: p.inkSoft),
                    ),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : TkButton(Tk.close, tooltip: l.clear, size: 18, onPressed: () => setState(_q.clear)),
                  ),
                ),
              ),
            ),
            if (diary.stubs.isEmpty)
              SliverToBoxAdapter(
                child: EmptyNote(l.noStubs, action: l.recordFilm, onAction: () => startRecord(context)),
              )
            else if (list.isEmpty)
              SliverToBoxAdapter(
                child: EmptyNote(
                  l.noMatch,
                  action: l.resetFilters,
                  onAction: () {
                    _q.clear();
                    setState(() => _filter = const StubFilter());
                  },
                ),
              )
            else if (grid)
              _grid(list)
            else
              SliverList.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final s = list[i];
                  final header =
                      byDate &&
                      s.hasDate &&
                      s.precision != DatePrecision.year &&
                      (i == 0 || !_sameMonth(list[i - 1], s));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (header)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          child: Text(
                            fmtMonthYear(context, s.date!).toUpperCase(),
                            style: disp(15, p.inkSoft, spacing: 1.4),
                          ),
                        ),
                      StubRow(s, key: ValueKey(s.id)),
                    ],
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  bool _sameMonth(Stub a, Stub b) =>
      a.hasDate && a.precision != DatePrecision.year && a.date!.year == b.date!.year && a.date!.month == b.date!.month;

  Widget _grid(List<Stub> list) {
    final diary = ref.read(diaryProvider);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(
        builder: (context, c) {
          const gap = 12.0;
          final w = (c.crossAxisExtent - gap * 2) / 3;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: gap,
              mainAxisSpacing: 14,
              childAspectRatio: w / (w * 1.5 + textHeight(context, 54, 50)),
            ),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final s = list[i];
              final f = diary.films[s.filmId];
              if (f == null) return const SizedBox();
              return PosterTile(f, width: w, strip: fmtStubShort(context, s), onTap: () => openStub(context, s));
            },
          );
        },
      ),
    );
  }

  Future<void> _openFilter() async {
    final next = await showModalBottomSheet<StubFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: _filter),
    );
    if (next != null) setState(() => _filter = next);
  }
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});
  final StubFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late var f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(diaryProvider);
    final l = context.l;
    final p = Palette.of(context);
    final places = {for (final s in d.stubs) ?s.place}.toList()..sort();
    final years = {
      for (final s in d.stubs)
        if (s.hasDate) s.date!.year,
    }.toList()..sort((a, b) => b - a);
    Widget group(String title, List<Widget> boxes) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: disp(16, p.ink)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: boxes),
        ],
      ),
    );
    StubFilter copy({Object? place = 0, Object? tag = 0, Object? year = 0, Object? series = 0, Object? minStars = 0}) =>
        StubFilter(
          place: place == 0 ? f.place : place as String?,
          tag: tag == 0 ? f.tag : tag as String?,
          year: year == 0 ? f.year : year as int?,
          series: series == 0 ? f.series : series as bool?,
          minStars: minStars == 0 ? f.minStars : minStars as int?,
        );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            group(l.filterKind, [
              OptionBox(
                label: l.filterAll,
                selected: f.series == null,
                onTap: () => setState(() => f = copy(series: null)),
              ),
              OptionBox(
                label: l.kindFilm,
                selected: f.series == false,
                onTap: () => setState(() => f = copy(series: false)),
              ),
              OptionBox(
                label: l.kindSeries,
                selected: f.series == true,
                onTap: () => setState(() => f = copy(series: true)),
              ),
            ]),
            if (years.isNotEmpty)
              group(l.filterYear, [
                OptionBox(
                  label: l.filterAll,
                  selected: f.year == null,
                  onTap: () => setState(() => f = copy(year: null)),
                ),
                for (final y in years)
                  OptionBox(
                    label: '$y',
                    selected: f.year == y,
                    onTap: () => setState(() => f = copy(year: y)),
                  ),
              ]),
            if (places.isNotEmpty)
              group(l.filterPlace, [
                OptionBox(
                  label: l.filterAll,
                  selected: f.place == null,
                  onTap: () => setState(() => f = copy(place: null)),
                ),
                for (final x in places)
                  OptionBox(
                    label: placeName(context, x),
                    selected: f.place == x,
                    onTap: () => setState(() => f = copy(place: x)),
                  ),
              ]),
            if (d.tags.isNotEmpty)
              group(l.filterTag, [
                OptionBox(
                  label: l.filterAll,
                  selected: f.tag == null,
                  onTap: () => setState(() => f = copy(tag: null)),
                ),
                for (final t in d.tags)
                  OptionBox(
                    label: '#$t',
                    selected: f.tag == t,
                    onTap: () => setState(() => f = copy(tag: t)),
                  ),
              ]),
            group(l.filterRating, [
              OptionBox(
                label: l.filterAll,
                selected: f.minStars == null,
                onTap: () => setState(() => f = copy(minStars: null)),
              ),
              for (final n in [5, 4, 3])
                OptionBox(
                  label: l.starsAtLeast(n),
                  selected: f.minStars == n,
                  onTap: () => setState(() => f = copy(minStars: n)),
                ),
            ]),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, const StubFilter()),
                  child: Text(
                    l.resetFilters,
                    style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkButton(label: l.done, onPressed: () => Navigator.pop(context, f)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
