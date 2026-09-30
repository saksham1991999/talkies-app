import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/stats.dart';
import '../../l10n/labels.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../share.dart';
import '../theme.dart';
import '../widgets.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  late Period _period = Period(StatsScope.year, ref.read(todayProvider).year, ref.read(todayProvider).month);

  String _title(BuildContext context) => switch (_period.scope) {
    StatsScope.month => fmtMonthYear(context, DateTime(_period.year, _period.month)),
    StatsScope.year => '${_period.year}',
    StatsScope.all => context.l.scopeAll,
  };

  void _scope(StatsScope s) {
    final t = ref.read(todayProvider);
    setState(
      () => _period = switch (s) {
        StatsScope.month => Period(s, _period.scope == StatsScope.year ? _period.year : t.year, t.month),
        StatsScope.year => Period(s, _period.year),
        StatsScope.all => Period(s, t.year),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final diary = ref.watch(diaryProvider);
    final today = ref.watch(todayProvider);
    final showRatings = ref.watch(settingsProvider.select((s) => s.showRatings));
    final st = computeStats(diary, _period);
    final p = Palette.of(context);
    final l = context.l;
    final atEnd = switch (_period.scope) {
      StatsScope.month => _period.year == today.year && _period.month == today.month,
      StatsScope.year => _period.year >= today.year,
      StatsScope.all => true,
    };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 60),
          children: [
            ScreenHeader(
              l.statsTitle,
              actions: [
                TkButton(
                  Tk.share,
                  tooltip: _period.scope == StatsScope.month ? l.shareMonth : l.share,
                  onPressed: () => showShareSheet(
                    context,
                    _period.scope == StatsScope.month
                        ? MonthShare(year: _period.year, month: _period.month)
                        : StatsShare(period: _period, title: _title(context)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final (s, t) in [
                    (StatsScope.month, l.scopeMonth),
                    (StatsScope.year, l.scopeYear),
                    (StatsScope.all, l.scopeAll),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OptionBox(label: t, dense: true, selected: _period.scope == s, onTap: () => _scope(s)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 4),
                if (_period.scope != StatsScope.all)
                  TkButton(Tk.left, tooltip: l.previous, onPressed: () => setState(() => _period = _period.shift(-1))),
                Expanded(
                  child: Text(
                    _title(context).toUpperCase(),
                    textAlign: _period.scope == StatsScope.all ? TextAlign.left : TextAlign.center,
                    style: disp(34, p.ink, spacing: 1),
                  ),
                ),
                if (_period.scope != StatsScope.all)
                  TkButton(
                    Tk.right,
                    tooltip: l.next,
                    color: atEnd ? p.line : null,
                    onPressed: atEnd ? null : () => setState(() => _period = _period.shift(1)),
                  ),
                const SizedBox(width: 4),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                height: 2,
                decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(1)),
              ),
            ),
            _Headline(st: st),
            if (st.count == 0)
              EmptyNote(l.statsEmpty)
            else ...[
              if (st.timeline.isNotEmpty) ...[
                SectionTitle(switch (_period.scope) {
                  StatsScope.month => l.byDay,
                  StatsScope.year => l.byMonth,
                  StatsScope.all => l.byYear,
                }),
                _Timeline(key: ValueKey(_period), buckets: st.timeline, scope: _period.scope),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text(l.tapForDetail, style: TextStyle(color: p.inkSoft, fontSize: 12)),
                ),
              ],
              if (showRatings)
                _Bars(
                  title: l.byStars,
                  buckets: st.stars.where((b) => b.count > 0).toList(),
                  name: (k) => k == 'none' ? l.unrated : '★ $k',
                  keepOrder: true,
                ),
              _Bars(
                title: l.byVenueType,
                buckets: st.venueTypes,
                name: (k) => venueTypeName(context, VenueType.values.byName(k)),
              ),
              _Bars(title: l.byPlace, buckets: st.places, name: (k) => placeName(context, k)),
              _Bars(title: l.byLanguage, buckets: st.languages, name: (k) => langName(context, k)),
              _Bars(title: l.byGenre, buckets: st.genres, name: (k) => genreName(context, k)),
              _Bars(title: l.byDirector, buckets: st.directors, name: (k) => k),
              _Bars(title: l.byActor, buckets: st.actors, name: (k) => k),
              _Bars(title: l.byDecade, buckets: st.decades, name: (k) => l.decadeLabel(k), keepOrder: true),
              _Bars(title: l.byCountry, buckets: st.countries, name: (k) => countryName(context, k)),
              _Bars(title: l.byTag, buckets: st.tags, name: (k) => '#$k'),
              _Bars(title: l.byFormat, buckets: st.formats, name: formatName),
              _Bars(title: l.byShow, buckets: st.shows, name: (k) => showName(context, k)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.st});
  final Stats st;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    Widget cell(String label, Widget value) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            value,
          ],
        ),
      ),
    );
    final h = st.minutes ~/ 60, m = st.minutes % 60;
    final (hu, mu) = hourMinuteUnits(context);
    Widget sep() => Container(
      width: 1.5,
      height: 44,
      decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(1)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Row(
            children: [
              cell(l.totalStubs, Text('${st.count}', style: disp(40, p.ink, spacing: 0.6))),
              sep(),
              cell(
                l.totalTime,
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$h', style: disp(40, p.ink, spacing: 0.6)),
                      TextSpan(text: ' $hu  ', style: disp(18, p.inkSoft)),
                      TextSpan(text: '$m', style: disp(40, p.ink, spacing: 0.6)),
                      TextSpan(text: ' $mu', style: disp(18, p.inkSoft)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              cell(
                l.spent,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rupees(st.spent), style: disp(28, p.ink, spacing: 0.6)),
                    if (st.paidCount > 0)
                      Text(
                        l.avgTicket(rupees((st.spent / st.paidCount).roundToDouble())),
                        style: TextStyle(color: p.inkSoft, fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              sep(),
              cell(
                '${l.fdfsCount} · ${l.rewatches}',
                Text('${st.fdfs} · ${st.rewatches}', style: disp(28, p.ink, spacing: 0.6)),
              ),
            ],
          ),
          if (st.avgRating != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Text(
                    l.avgRating,
                    style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                  const SizedBox(width: 10),
                  Stars(st.avgRating!, size: 15, color: p.accent, empty: p.inkSoft),
                  const SizedBox(width: 8),
                  Text(fmtRating(st.avgRating!), style: disp(18, p.ink)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertical bars. They rise by clipping a fixed-shape bar, so the rounded
/// caps never change shape mid-animation.
class _Timeline extends StatelessWidget {
  const _Timeline({super.key, required this.buckets, required this.scope});
  final List<Bucket> buckets;
  final StatsScope scope;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final max = buckets.fold<int>(0, (m, b) => b.count > m ? b.count : m);
    final dense = buckets.length > 14;
    String label(int i) => switch (scope) {
      StatsScope.month => (i + 1) % 5 == 0 || i == 0 ? '${i + 1}' : '',
      StatsScope.year => DateFormat.MMM(context.fmtLocale).format(DateTime(2000, i + 1)).substring(0, 1),
      StatsScope.all => buckets.length > 10 && i % 2 == 1 ? '' : "'${buckets[i].key.substring(2)}",
    };
    final reduce = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 170,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduce ? 1 : 0, end: 1),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < buckets.length; i++)
                Expanded(
                  child: Semantics(
                    button: buckets[i].count > 0,
                    label: '${buckets[i].key}: ${buckets[i].count}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: buckets[i].count == 0 ? null : () => _detail(context, buckets[i].key, buckets[i].stubs),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: dense ? 1.5 : 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!dense || buckets[i].count == max)
                              Text(
                                buckets[i].count == 0 ? '' : '${buckets[i].count}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: buckets[i].count == max ? p.accent : p.inkSoft,
                                ),
                              ),
                            const SizedBox(height: 3),
                            SizedBox(
                              height: max == 0 ? 3 : 3 + 112 * buckets[i].count / max,
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  heightFactor: t,
                                  child: Container(
                                    height: max == 0 ? 3 : 3 + 112 * buckets[i].count / max,
                                    decoration: BoxDecoration(
                                      color: buckets[i].count == 0
                                          ? p.line
                                          : (buckets[i].count == max ? p.accent : p.ink),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              label(i),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: TextStyle(fontSize: 10.5, color: p.inkSoft),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal ranked bars with a "show all" toggle. Rows open their films.
class _Bars extends StatefulWidget {
  const _Bars({required this.title, required this.buckets, required this.name, this.keepOrder = false});
  final String title;
  final List<Bucket> buckets;
  final String Function(String) name;
  final bool keepOrder;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  var _all = false;

  @override
  Widget build(BuildContext context) {
    if (widget.buckets.isEmpty) return const SizedBox();
    final p = Palette.of(context);
    final l = context.l;
    final list = widget.buckets;
    final max = list.fold<int>(0, (m, b) => b.count > m ? b.count : m);
    // Only a clear leader gets the ink colour; ties stay neutral.
    final leader = list.where((b) => b.count == max).length == 1 ? list.firstWhere((b) => b.count == max) : null;
    final shown = _all ? list : list.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          widget.title,
          action: list.length > 6 ? (_all ? l.showLess : l.showMore(list.length)) : null,
          onAction: () => setState(() => _all = !_all),
        ),
        for (final b in shown)
          InkWell(
            onTap: () => _detail(context, widget.name(b.key), b.stubs),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 5, 20, 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      widget.name(b.key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        return Stack(
                          children: [
                            Container(
                              height: 12,
                              decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(6)),
                            ),
                            Container(
                              height: 12,
                              width: c.maxWidth * b.count / max,
                              decoration: BoxDecoration(
                                color: b == leader ? p.accent : p.ink,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text('${b.count}', textAlign: TextAlign.right, style: disp(17, p.ink)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

void _detail(BuildContext context, String title, List<Stub> stubs) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('${title.toUpperCase()}  ·  ${stubs.length}', style: disp(22, Palette.of(c).ink)),
          ),
          for (final s in [...stubs]..sort((a, b) => byWatchOrder(b, a))) StubRow(s, key: ValueKey(s.id)),
        ],
      ),
    ),
  ),
);
