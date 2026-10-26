import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crews.dart';
import '../../data/models.dart';
import '../../state/crews.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../online_widgets.dart';
import '../theme.dart';
import '../together_widgets.dart';
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
    final nextNight = ref.watch(nextNightProvider);
    void hide(Film f) => _hide(context, ref, f);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Row(
              children: [
                const SizedBox(width: 20),
                Expanded(child: Text('TALKIES  ${today.year}', style: disp(15, p.inkSoft, spacing: 2.4))),
                _RecordButton(),
                TkButton(Tk.settings, tooltip: l.settings, onPressed: () => push(context, const SettingsScreen())),
                const SizedBox(width: 8),
              ],
            ),
            if (nextNight != null && p.dark)
              _TonightHero(entry: nextNight)
            else if (nextNight != null) ...[
              SectionTitle(l.togetherNextNight),
              NightTicket(
                nextNight,
                compact: true,
                onTap: () => openNight(context, nextNight.crew.id, nextNight.night.id),
              ),
            ],
            _Counts(year: thisYear.length, month: thisMonth, monthName: fmtMonth(context, today)),
            _FdfsStrip(count: diary.stubs.where((s) => s.fdfs).length),
            SectionTitle(
              l.recent,
              action: recent.isEmpty ? null : l.allStubs,
              onAction: () => ref.read(tabProvider.notifier).go(1),
            ),
            if (recent.isEmpty)
              EmptyNote(l.emptyHome, action: l.recordFilm, onAction: () => startRecord(context))
            else
              for (final s in recent.take(4)) StubRow(s, key: ValueKey(s.id)),
            // Draws nothing unless the server is up and the user is signed in.
            const FriendsStrip(),
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
    ref.read(tabProvider.notifier).go(2);
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
          alignment: AlignmentDirectional.bottomStart,
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

/// Record in context: the primary action lives in the header, filled ink.
class _RecordButton extends StatelessWidget {
  const _RecordButton();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => startRecord(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(color: p.btnPrimary, borderRadius: BorderRadius.circular(22)),
          child: Text(
            context.l.recordFilm,
            maxLines: 1,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.onBtnPrimary),
          ),
        ),
      ),
    );
  }
}

/// Tonight owns the first screen when the house lights are down: the hall,
/// the crew, the vote. One tap opens the night.
class _TonightHero extends StatelessWidget {
  const _TonightHero({required this.entry});
  final NightEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final (crew, night) = (entry.crew, entry.night);
    final film = night.film;
    final place = night.event?.place ?? night.place;
    final wall = nightWall(night);
    final when = night.status == NightStatus.poll ? l.nightPollOpen : (wall == null ? '' : fmtNightWhen(context, wall));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Semantics(
        button: true,
        label: [crew.name, if (when.isNotEmpty) when].join(', '),
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => openNight(context, crew.id, night.id),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Image.asset('assets/images/hall.jpg', height: 300, width: double.infinity, fit: BoxFit.cover),
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        p.wall.withValues(alpha: 0.45),
                        p.wall.withValues(alpha: 0.05),
                        p.wall.withValues(alpha: 0.92),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          crew.name,
                          if (place != null && place.trim().isNotEmpty) place.trim(),
                        ].join(' · ').toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: p.tonight,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        film?.title ?? l.nightTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: disp(34, p.ink, height: 1.05),
                      ),
                      if (when.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(when, style: TextStyle(fontSize: 14, color: p.ink)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// First day first shows, kept on screen one as a stamp and a count.
class _FdfsStrip extends StatelessWidget {
  const _FdfsStrip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (count == 0) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        children: [
          Stamp(word: context.l.fdfs, color: p.accent, size: 64, seed: 7),
          const SizedBox(width: 12),
          Text(
            '$count ${context.l.fdfsCount}',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
          ),
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
