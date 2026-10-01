import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../state/crews.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../night_editor.dart';
import '../share.dart';
import '../theme.dart';
import '../together_widgets.dart';
import '../widgets.dart';

const _base = 1200;

/// What the grid shows: the stubs, the planned watchlist films, or the movie nights.
enum _Layer { stubs, wish, nights }

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  final _pages = PageController(initialPage: _base);
  var _page = _base;
  var _layer = _Layer.stubs;
  VenueType? _type;

  DateTime _month(int page) {
    final t = ref.watch(todayProvider);
    return DateTime(t.year, t.month + page - _base);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int by) =>
      _pages.animateToPage(_page + by, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final diary = ref.watch(diaryProvider);
    final p = Palette.of(context);
    final l = context.l;
    final m = _month(_page);
    final watched = diary.stubs
        .where((s) => s.precision == DatePrecision.day && s.date!.year == m.year && s.date!.month == m.month)
        .where((s) => _type == null || diary.venueType(s.place) == _type)
        .length;
    final planned = diary.wishes
        .where((w) => w.planned != null && w.planned!.year == m.year && w.planned!.month == m.month)
        .length;

    return Scaffold(
      floatingActionButton: RecordFab(onPressed: () => startRecord(context), tooltip: l.recordFilm),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              l.tabCalendar,
              sub: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: l.calWatched(watched),
                      style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: '   '),
                    TextSpan(
                      text: l.calPlanned(planned),
                      style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              actions: [
                TkButton(
                  Tk.share,
                  tooltip: l.shareMonth,
                  onPressed: () => showShareSheet(context, MonthShare(year: m.year, month: m.month)),
                ),
                if (_layer == _Layer.stubs)
                  Badge(
                    isLabelVisible: _type != null,
                    smallSize: 8,
                    backgroundColor: p.accent,
                    child: PopupMenuButton<VenueType?>(
                      tooltip: l.filter,
                      icon: const TkIcon(Tk.filter),
                      onSelected: (t) => setState(() => _type = t),
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem(value: null, checked: _type == null, child: Text(l.filterAll)),
                        for (final t in VenueType.values)
                          CheckedPopupMenuItem(value: t, checked: _type == t, child: Text(venueTypeName(context, t))),
                      ],
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (v, label) in [
                          (_Layer.stubs, l.showStubs),
                          (_Layer.wish, l.showWatchlist),
                          (_Layer.nights, l.togetherNights),
                        ])
                          OptionBox(
                            key: Key('cal-${v.name}'),
                            label: label,
                            selected: _layer == v,
                            dense: true,
                            onTap: () => setState(() => _layer = v),
                          ),
                      ],
                    ),
                  ),
                  if (_page != _base)
                    TextButton(
                      onPressed: () => _pages.animateToPage(
                        _base,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      ),
                      child: Text(
                        l.today,
                        style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                TkButton(Tk.left, tooltip: l.previous, onPressed: () => _go(-1)),
                Expanded(
                  child: Text(
                    fmtMonthYear(context, m).toUpperCase(),
                    textAlign: TextAlign.center,
                    style: disp(22, p.ink, spacing: 1.2),
                  ),
                ),
                TkButton(Tk.right, tooltip: l.next, onPressed: () => _go(1)),
              ],
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _MonthGrid(month: _month(i), layer: _layer, type: _type),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({required this.month, required this.layer, required this.type});
  final DateTime month;
  final _Layer layer;
  final VenueType? type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(diaryProvider);
    final weekStart = ref.watch(settingsProvider.select((s) => s.weekStart));
    final today = ref.watch(todayProvider);
    final p = Palette.of(context);

    // Movie nights of every group, by day of this month: the clock mark on a cell, and the nights layer.
    final nightsByDay = <int, List<Film>>{};
    final nightCount = <int, int>{};
    for (final e in ref.watch(nightsProvider)) {
      for (final d in nightDays(e.night)) {
        if (d.year != month.year || d.month != month.month) continue;
        nightCount[d.day] = (nightCount[d.day] ?? 0) + 1;
        if (e.night.film case final f?) (nightsByDay[d.day] ??= []).add(f);
      }
    }

    final byDay = <int, List<Film>>{};
    if (layer == _Layer.nights) {
      byDay.addAll(nightsByDay);
    } else if (layer == _Layer.wish) {
      for (final w in diary.wishes) {
        final d = w.planned;
        if (d == null || d.year != month.year || d.month != month.month) continue;
        final f = diary.films[w.filmId];
        if (f != null) (byDay[d.day] ??= []).add(f);
      }
    } else {
      final stubs =
          diary.stubs
              .where(
                (s) => s.precision == DatePrecision.day && s.date!.year == month.year && s.date!.month == month.month,
              )
              .where((s) => type == null || diary.venueType(s.place) == type)
              .toList()
            ..sort(byWatchOrder);
      for (final s in stubs) {
        final f = diary.films[s.filmId];
        if (f != null) (byDay[s.date!.day] ??= []).add(f);
      }
    }

    final first = DateTime(month.year, month.month);
    final lead = (first.weekday - weekStart) % 7;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final names = [
      for (var i = 0; i < 7; i++) DateFormat.E(context.fmtLocale).format(DateTime(2024, 1, 7 + (weekStart % 7) + i)),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        const pad = 12.0;
        final cw = (box.maxWidth - pad * 2) / 7;
        final ch = cw * 1.42;
        return ListView(
          padding: const EdgeInsets.fromLTRB(pad, 0, pad, 100),
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  SizedBox(
                    width: cw,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        names[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: (weekStart + i) % 7 == DateTime.sunday % 7 ? p.accent : p.inkSoft,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Wrap(
              children: [
                for (var i = 0; i < 42; i++)
                  _DayCell(
                    key: ValueKey(
                      'day-${ymd(DateTime(month.year, month.month, i - lead + 1))}-${i >= lead && i - lead < days}',
                    ),
                    width: cw,
                    height: ch,
                    day: i - lead + 1,
                    inMonth: i >= lead && i - lead < days,
                    date: DateTime(month.year, month.month, i - lead + 1),
                    films: byDay[i - lead + 1] ?? const [],
                    isToday: DateUtils.isSameDay(DateTime(month.year, month.month, i - lead + 1), today),
                    ring: switch (layer) {
                      _Layer.stubs => null,
                      _Layer.wish => paperColors[VenueType.ott],
                      _Layer.nights => paperColors[VenueType.cinema],
                    },
                    nights: i >= lead && i - lead < days ? (nightCount[i - lead + 1] ?? 0) : 0,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.width,
    required this.height,
    required this.day,
    required this.inMonth,
    required this.date,
    required this.films,
    required this.isToday,
    required this.ring,
    required this.nights,
  });
  final double width, height;
  final int day;
  final bool inMonth, isToday;
  final DateTime date;
  final List<Film> films;

  /// Colour of the frame round a day that has films on a planning layer, or null.
  final Color? ring;

  /// How many movie nights fall on this day.
  final int nights;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final shown = DateTime(date.year, date.month, date.day).day;
    final numStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      color: isToday
          ? p.onAccent
          : (films.isEmpty ? (inMonth ? p.ink : p.inkSoft.withValues(alpha: 0.5)) : Colors.white),
    );
    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Semantics(
          button: inMonth,
          label:
              '${fmtDay(context, date)}${films.isEmpty ? '' : ', ${films.map((f) => f.title).join(', ')}'}'
              '${nights == 0 ? '' : ', ${context.l.nightTitle}'}',
          child: InkWell(
            onTap: inMonth ? () => _openDay(context) : null,
            borderRadius: BorderRadius.circular(3),
            child: Container(
              decoration: BoxDecoration(
                color: inMonth ? p.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: ring != null && films.isNotEmpty ? Border.all(color: ring!, width: 2) : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (films.isNotEmpty) Poster(films.first, width: width, radius: 0),
                  if (films.isNotEmpty)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment(0, -0.2),
                          colors: [Color(0x99000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 3,
                    top: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                      alignment: Alignment.center,
                      decoration: isToday
                          ? BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(9))
                          : null,
                      child: Text('$shown', style: numStyle),
                    ),
                  ),
                  // A movie night that day: the clock mark, on the poster's dark top edge or on the plain cell.
                  if (nights > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: ExcludeSemantics(
                        child: TkIcon(Tk.clock, size: 13, color: films.isEmpty ? p.accent : Colors.white),
                      ),
                    ),
                  if (films.length > 1)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        color: p.paper(VenueType.ott),
                        child: Text('+${films.length - 1}', style: disp(11, paperInk, spacing: 0)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openDay(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DaySheet(date: date, outer: context),
  );
}

class _DaySheet extends ConsumerWidget {
  const _DaySheet({required this.date, required this.outer});
  final DateTime date;

  /// The calendar's own context: the sheet's goes when it closes, and what opens next needs one that stays.
  final BuildContext outer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(diaryProvider);
    final p = Palette.of(context);
    final l = context.l;
    final stubs =
        diary.stubs.where((s) => s.precision == DatePrecision.day && DateUtils.isSameDay(s.date, date)).toList()
          ..sort(byWatchOrder);
    final wishes = diary.wishes.where((w) => DateUtils.isSameDay(w.planned, date)).toList();
    final day = DateTime(date.year, date.month, date.day);
    final nights = [
      for (final e in ref.watch(nightsProvider))
        if (nightDays(e.night).contains(day)) e,
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(fmtDay(context, date).toUpperCase(), style: disp(22, p.ink, spacing: 1)),
            ),
            if (stubs.isEmpty && wishes.isEmpty && nights.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(l.dayEmpty, style: TextStyle(color: p.inkSoft)),
              ),
            for (final s in stubs) StubRow(s, key: ValueKey(s.id)),
            if (wishes.isNotEmpty) SectionTitle(l.showWatchlist),
            for (final w in wishes)
              if (diary.films[w.filmId] case final f?)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Poster(f, width: 34, radius: 2),
                  title: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(l.plannedFor(fmtShort(context, date))),
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      recordFilm(context, f, day: date);
                    },
                    child: Text(
                      l.iWatched,
                      style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
                    ),
                  ),
                  onTap: () => openFilm(context, f),
                ),
            if (nights.isNotEmpty) ...[
              SectionTitle(l.togetherNights),
              for (final e in nights)
                NightTicket(
                  e,
                  key: ValueKey('${e.crew.id}/${e.night.id}'),
                  onTap: () {
                    Navigator.pop(context);
                    openNight(outer, e.crew.id, e.night.id);
                  },
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: InkButton(
                label: l.recordForDay,
                icon: Tk.plus,
                onPressed: () {
                  Navigator.pop(context);
                  startRecord(context, day: date);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: SlabButton(
                key: const Key('cal-plan-night'),
                label: l.nightPlanTitle,
                icon: Tk.clock,
                tone: SlabTone.velvet,
                onPressed: () {
                  Navigator.pop(context);
                  planNight(outer, ref, day: date);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
