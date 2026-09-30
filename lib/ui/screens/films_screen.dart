import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../l10n/labels.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';
import 'search_screen.dart';
import 'stubs_screen.dart' show StubSort;

const _langFilter = ['hi', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'pa', 'gu', 'en'];

class FilmsScreen extends ConsumerStatefulWidget {
  const FilmsScreen({super.key});

  @override
  ConsumerState<FilmsScreen> createState() => _FilmsScreenState();
}

class _FilmsScreenState extends ConsumerState<FilmsScreen> {
  String? _lang;
  var _outNow = false;

  /// null keeps the default order: planned date, then newest.
  StubSort? _sort;

  @override
  Widget build(BuildContext context) {
    final seg = ref.watch(filmsSegmentProvider);
    final diary = ref.watch(diaryProvider);
    final today = ref.watch(todayProvider);
    final worldwide = ref.watch(settingsProvider.select((s) => s.worldwide));
    final catalogAsync = ref.watch(catalogProvider);
    final busy = ref.watch(catalogRefreshProvider);
    final p = Palette.of(context);
    final l = context.l;

    bool langOk(Film f) => _lang == null || f.langs.contains(_lang);
    List<(Film, String?)> items;
    String empty;
    switch (seg) {
      case FilmsSegment.fresh:
        items = [
          for (final f in catalogAsync.value?.newReleases(today, worldwide: worldwide, lang: _lang) ?? const <Film>[])
            (f, fmtRelease(context, f)),
        ];
        empty = l.noReleases;
      case FilmsSegment.upcoming:
        items = [
          for (final f in catalogAsync.value?.upcoming(today, worldwide: worldwide, lang: _lang) ?? const <Film>[])
            (f, fmtRelease(context, f)),
        ];
        empty = l.noReleases;
      case FilmsSegment.want:
        final ws =
            diary.wishes.where((w) {
              final f = diary.films[w.filmId];
              if (f == null || !langOk(f)) return false;
              if (!_outNow) return true;
              final d = f.releaseDay;
              return d == null ? (f.year != null && f.year! <= today.year) : !d.isAfter(today);
            }).toList()..sort(
              (a, b) => switch (_sort) {
                StubSort.newest => b.added.compareTo(a.added),
                StubSort.oldest => a.added.compareTo(b.added),
                _ =>
                  a.planned != null && b.planned != null
                      ? a.planned!.compareTo(b.planned!)
                      : a.planned != null
                      ? -1
                      : b.planned != null
                      ? 1
                      : b.added.compareTo(a.added),
              },
            );
        items = [
          for (final w in ws) (diary.films[w.filmId]!, w.planned == null ? null : fmtShort(context, w.planned!)),
        ];
        empty = l.wantEmpty;
      case FilmsSegment.recorded:
        final last = <String, Stub>{};
        final best = <String, double>{};
        for (final s in diary.stubs) {
          final prev = last[s.filmId];
          if (prev == null || byWatchOrder(s, prev) > 0) last[s.filmId] = s;
          if (s.rating != null && s.rating! > (best[s.filmId] ?? -1)) best[s.filmId] = s.rating!;
        }
        int newest(String a, String b) => byWatchOrder(last[b]!, last[a]!);
        final ids = last.keys.where((id) => diary.films[id] != null && langOk(diary.films[id]!)).toList()
          ..sort(
            (a, b) => switch (_sort) {
              StubSort.oldest => byWatchOrder(last[a]!, last[b]!),
              StubSort.ratingHigh =>
                (best[b] ?? -1) != (best[a] ?? -1) ? (best[b] ?? -1).compareTo(best[a] ?? -1) : newest(a, b),
              StubSort.ratingLow =>
                (best[a] ?? 99) != (best[b] ?? 99) ? (best[a] ?? 99).compareTo(best[b] ?? 99) : newest(a, b),
              _ => newest(a, b),
            },
          );
        items = [for (final id in ids) (diary.films[id]!, fmtStubShort(context, last[id]!))];
        empty = l.recordedEmpty;
    }

    return Scaffold(
      floatingActionButton: RecordFab(
        icon: Tk.search,
        tooltip: l.search,
        onPressed: () => push(context, const SearchScreen()),
      ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(
                l.tabFilms,
                actions: [
                  if (seg == FilmsSegment.want || seg == FilmsSegment.recorded)
                    PopupMenuButton<StubSort>(
                      key: const Key('films-sort'),
                      tooltip: l.sort,
                      icon: const TkIcon(Tk.sort),
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => [
                        for (final (v, t) in [
                          (StubSort.newest, l.sortNewest),
                          (StubSort.oldest, l.sortOldest),
                          if (seg == FilmsSegment.recorded) ...[
                            (StubSort.ratingHigh, l.sortRatingHigh),
                            (StubSort.ratingLow, l.sortRatingLow),
                          ],
                        ])
                          CheckedPopupMenuItem(value: v, checked: _sort == v, child: Text(t)),
                      ],
                    ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final (s, label) in [
                      (FilmsSegment.fresh, l.filmsNew),
                      (FilmsSegment.upcoming, l.filmsUpcoming),
                      (FilmsSegment.want, l.filmsWant),
                      (FilmsSegment.recorded, l.filmsRecorded),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OptionBox(
                          label: label,
                          selected: seg == s,
                          onTap: () => ref.read(filmsSegmentProvider.notifier).go(s),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: EdgeFade(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    children: [
                      if (seg == FilmsSegment.want) ...[
                        _LangChip(
                          label: l.filmsReleased,
                          selected: _outNow,
                          onTap: () => setState(() => _outNow = !_outNow),
                        ),
                        Container(
                          width: 1.5,
                          margin: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                          decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(1)),
                        ),
                      ],
                      _LangChip(
                        label: l.allLanguages,
                        selected: _lang == null,
                        onTap: () => setState(() => _lang = null),
                      ),
                      for (final code in _langFilter)
                        _LangChip(
                          label: langName(context, code),
                          selected: _lang == code,
                          onTap: () => setState(() => _lang = code),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (!catalogAsync.hasValue && (seg == FilmsSegment.fresh || seg == FilmsSegment.upcoming))
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (items.isEmpty)
              SliverToBoxAdapter(
                child: EmptyNote(
                  empty,
                  action: seg == FilmsSegment.fresh || seg == FilmsSegment.upcoming ? l.refreshNow : null,
                  onAction: busy ? null : _refresh,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                sliver: SliverLayoutBuilder(
                  builder: (context, c) {
                    const gap = 12.0;
                    final w = (c.crossAxisExtent - gap * 2) / 3;
                    return SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: 16,
                        childAspectRatio: w / (w * 1.5 + textHeight(context, 54, 50)),
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) =>
                          PosterTile(items[i].$1, width: w, strip: items[i].$2, key: ValueKey(items[i].$1.id)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final m = ScaffoldMessenger.of(context);
    final l = context.l;
    try {
      final n = await ref.read(catalogRefreshProvider.notifier).run();
      m.showSnackBar(SnackBar(content: Text(l.refreshDone(n))));
    } catch (_) {
      m.showSnackBar(SnackBar(content: Text(l.refreshFailed)));
    }
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? p.accent : p.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
