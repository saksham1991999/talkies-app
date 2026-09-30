import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(diaryProvider);
    final today = ref.watch(todayProvider);
    final worldwide = ref.watch(settingsProvider.select((s) => s.worldwide));
    final catalog = ref.watch(catalogProvider).value;
    final p = Palette.of(context);
    final l = context.l;

    final thisYear = diary.stubs.where((s) => s.hasDate && s.date!.year == today.year).toList();
    final thisMonth = thisYear.where((s) => s.precision != DatePrecision.year && s.date!.month == today.month).length;
    final recent = [...diary.stubs]..sort((a, b) => byWatchOrder(b, a));
    final fresh = catalog?.newReleases(today, worldwide: worldwide).take(12).toList() ?? const <Film>[];
    final soon = catalog?.upcoming(today, worldwide: worldwide).take(12).toList() ?? const <Film>[];
    final recs = ref.watch(recsProvider);
    void hide(Film f) => _hide(context, ref, f);

    return Scaffold(
      floatingActionButton: RecordFab(onPressed: () => startRecord(context), tooltip: l.recordFilm),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 20),
                    Expanded(child: Text('TALKIES  ${today.year}', style: disp(15, p.accent, spacing: 2.4))),
                    TkButton(Tk.settings, tooltip: l.settings, onPressed: () => push(context, const SettingsScreen())),
                    const SizedBox(width: 8),
                  ],
                ),
                _Counts(year: thisYear.length, month: thisMonth, monthName: fmtMonth(context, today)),
                _VenueSplit(stubs: thisYear, diary: diary),
              ],
            ),
            SectionTitle(
              l.recent,
              action: recent.isEmpty ? null : l.allStubs,
              onAction: () => ref.read(tabProvider.notifier).go(1),
            ),
            if (recent.isEmpty)
              EmptyNote(l.emptyHome, action: l.recordFilm, onAction: () => startRecord(context))
            else
              for (final s in recent.take(4)) StubRow(s, key: ValueKey(s.id)),
            if (recs.forYou.isNotEmpty) ...[
              SectionTitle(l.forYou),
              _PosterStrip(films: recs.forYou, strip: _year, onHide: hide),
            ],
            if (fresh.isNotEmpty) ...[
              SectionTitle(l.newReleases, action: l.seeAll, onAction: () => _films(ref, FilmsSegment.fresh)),
              _PosterStrip(films: fresh, strip: (f) => fmtRelease(context, f)),
            ],
            for (final (anchor, films) in recs.because) ...[
              SectionTitle(l.becauseYouLiked(anchor.title)),
              _PosterStrip(films: films, strip: _year, onHide: hide),
            ],
            if (soon.isNotEmpty) ...[
              SectionTitle(l.comingSoon, action: l.seeAll, onAction: () => _films(ref, FilmsSegment.upcoming)),
              _PosterStrip(films: soon, strip: (f) => fmtRelease(context, f)),
            ],
          ],
        ),
      ),
    );
  }

  static String? _year(Film f) => f.year?.toString();

  /// "Not interested", with Undo.
  void _hide(BuildContext context, WidgetRef ref, Film f) {
    final diary = ref.read(diaryProvider.notifier);
    HapticFeedback.selectionClick();
    diary.setHidden(f.id, true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l.hiddenFromRecs),
          action: SnackBarAction(label: context.l.undo, onPressed: () => diary.setHidden(f.id, false)),
        ),
      );
  }

  void _films(WidgetRef ref, FilmsSegment s) {
    ref.read(filmsSegmentProvider.notifier).go(s);
    ref.read(tabProvider.notifier).go(3);
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.year, required this.month, required this.monthName});
  final int year, month;
  final String monthName;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    Widget count(int n, double size, Color c, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Long unit words (Tamil, Malayalam) shrink the line instead of overflowing.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _CountUp(value: n, style: disp(size, c, spacing: 1)),
              const SizedBox(width: 6),
              Text(l.unitFilms(n).toUpperCase(), style: disp(size * 0.24, p.accent, spacing: 1)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: p.inkSoft, fontWeight: FontWeight.w600),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(flex: 5, child: count(year, 104, p.ink, l.thisYear)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              child: Container(
                width: 2,
                decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(1)),
              ),
            ),
            Flexible(flex: 4, child: count(month, 58, p.accent, monthName)),
            const SizedBox(width: 10),
            // Brand mark: part of the row, so no text can run under it.
            Align(
              alignment: Alignment.topCenter,
              child: ExcludeSemantics(
                child: Stamp(
                  word: 'TALKIES',
                  line: 'ADMIT ONE',
                  color: p.accent.withValues(alpha: 0.26),
                  size: 92,
                  seed: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Counts up from zero once. The final number is always what is shown at rest.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});
  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// One bar split by where the films were watched this year.
class _VenueSplit extends StatelessWidget {
  const _VenueSplit({required this.stubs, required this.diary});
  final List<Stub> stubs;
  final Diary diary;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final counts = <VenueType, int>{};
    for (final s in stubs) {
      final t = diary.venueType(s.place);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final order = VenueType.values.where((t) => (counts[t] ?? 0) > 0).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: context.l.splitLegend,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: order.isEmpty
                    ? ColoredBox(color: p.line, child: const SizedBox.expand())
                    : Row(
                        children: [
                          for (final t in order)
                            Expanded(
                              flex: counts[t]!,
                              child: ColoredBox(color: p.paper(t), child: const SizedBox.expand()),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          if (order.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final t in order)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: p.paper(t), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${venueTypeName(context, t)} ${counts[t]}',
                        style: TextStyle(fontSize: 12, color: p.inkSoft, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PosterStrip extends StatelessWidget {
  const _PosterStrip({required this.films, required this.strip, this.onHide});
  final List<Film> films;
  final String? Function(Film) strip;

  /// Long-press action: "Not interested".
  final void Function(Film)? onHide;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: textHeight(context, 222, 50),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: films.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, i) => PosterTile(
        films[i],
        width: 108,
        strip: strip(films[i]),
        onLongPress: onHide == null ? null : () => onHide!(films[i]),
        longPressHint: onHide == null ? null : context.l.notInterested,
      ),
    ),
  );
}
