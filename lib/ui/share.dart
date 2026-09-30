import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/stats.dart';
import '../l10n/labels.dart';
import '../state/providers.dart';
import 'common.dart';
import 'format.dart';
import 'icons.dart';
import 'screens/stub_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shares bytes as a file through the system sheet.
Future<void> shareBytes(BuildContext context, Uint8List bytes, String name, String mime) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, name: name, mimeType: mime)],
      fileNameOverrides: [name],
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// What a share image shows. Subclasses build the image at a fixed size.
abstract class ShareContent {
  const ShareContent();
  Size get size;
  String get fileName;
  bool get hasOptions => false;
  Widget build(BuildContext context, ShareOptions o);
}

class ShareOptions {
  const ShareOptions({required this.bg, this.titles = true, this.dates = true, this.ratings = true});
  final Color bg;
  final bool titles, dates, ratings;

  bool get darkBg => ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;
  Color get ink => darkBg ? const Color(0xFFF1E5DD) : paperInk;
  Color get soft => darkBg ? const Color(0xFFBFA9A0) : paperInkSoft;
}

Future<void> showShareSheet(BuildContext context, ShareContent content) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ShareSheet(content: content),
);

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.content});
  final ShareContent content;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _key = GlobalKey();
  var _titles = true, _dates = true, _ratings = true;
  var _busy = false;

  Future<void> _share(BuildContext btn) async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!btn.mounted) return;
      await shareBytes(btn, data!.buffer.asUint8List(), widget.content.fileName, 'image/png');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgIndex = ref.watch(settingsProvider.select((s) => s.shareBg));
    final p = Palette.of(context);
    final l = context.l;
    final c = widget.content;
    final o = ShareOptions(
      bg: shareBackgrounds[bgIndex.clamp(0, shareBackgrounds.length - 1)],
      titles: _titles,
      dates: _dates,
      ratings: _ratings && ref.watch(settingsProvider.select((s) => s.showRatings)),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(l.shareTitle.toUpperCase(), style: disp(22, p.ink)),
            const SizedBox(height: 12),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.42,
              child: FittedBox(
                child: RepaintBoundary(
                  key: _key,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
                    child: SizedBox.fromSize(size: c.size, child: c.build(context, o)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.background, style: disp(16, p.ink)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < shareBackgrounds.length; i++)
                  Semantics(
                    button: true,
                    selected: i == bgIndex,
                    label: '${l.background} ${i + 1}',
                    child: GestureDetector(
                      onTap: () => ref.read(settingsProvider.notifier).set((s) => s.copyWith(shareBg: i)),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: shareBackgrounds[i],
                          shape: BoxShape.circle,
                          border: Border.all(color: i == bgIndex ? p.ink : p.line, width: i == bgIndex ? 3 : 1),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (c.hasOptions) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OptionBox(
                    label: l.showTitles,
                    dense: true,
                    selected: _titles,
                    onTap: () => setState(() => _titles = !_titles),
                  ),
                  OptionBox(
                    label: l.showDates,
                    dense: true,
                    selected: _dates,
                    onTap: () => setState(() => _dates = !_dates),
                  ),
                  OptionBox(
                    label: l.showRatings,
                    dense: true,
                    selected: _ratings,
                    onTap: () => setState(() => _ratings = !_ratings),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Builder(
              builder: (btn) => InkButton(
                key: const Key('share-image'),
                label: l.share,
                icon: Tk.share,
                onPressed: _busy ? null : () => _share(btn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wordmark set at the foot of every share image.
class _Foot extends StatelessWidget {
  const _Foot(this.o);
  final ShareOptions o;

  @override
  Widget build(BuildContext context) =>
      Text('TALKIES', textAlign: TextAlign.center, style: disp(18, o.soft, spacing: 6));
}

class TicketShare extends ShareContent {
  const TicketShare({required this.stub, required this.film});
  final Stub stub;
  final Film film;

  @override
  Size get size => const Size(380, 700);
  @override
  String get fileName => 'talkies-ticket-${ticketNo(stub.no)}.png';

  @override
  Widget build(BuildContext context, ShareOptions o) => Container(
    color: o.bg,
    padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
    child: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: TicketCard(stub: stub, film: film, interactive: false),
          ),
        ),
        const SizedBox(height: 12),
        _Foot(o),
      ],
    ),
  );
}

/// A month on one card: poster grid with optional titles, dates and ratings.
class MonthShare extends ShareContent {
  const MonthShare({required this.year, required this.month});
  final int year, month;

  @override
  Size get size => const Size(380, 640);
  @override
  bool get hasOptions => true;
  @override
  String get fileName => 'talkies-$year-${month.toString().padLeft(2, '0')}.png';

  @override
  Widget build(BuildContext context, ShareOptions o) => Consumer(
    builder: (context, ref, _) {
      final d = ref.watch(diaryProvider);
      final stubs =
          d.stubs
              .where(
                (s) => s.hasDate && s.precision != DatePrecision.year && s.date!.year == year && s.date!.month == month,
              )
              .toList()
            ..sort(byWatchOrder);
      final l = context.l;
      final shown = stubs.take(15).toList();
      return Container(
        color: o.bg,
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.monthAtMovies(fmtMonthYear(context, DateTime(year, month))).toUpperCase(),
              style: disp(24, o.ink, spacing: 0.8),
            ),
            const SizedBox(height: 2),
            Text(
              l.ticketsCount(stubs.length),
              style: TextStyle(color: o.soft, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(l.nothingToShare, style: TextStyle(color: o.soft)),
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        const gap = 10.0;
                        final w = (c.maxWidth - gap * 4) / 5;
                        return Wrap(
                          spacing: gap,
                          runSpacing: 10,
                          children: [
                            for (final s in shown)
                              SizedBox(
                                width: w,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (d.films[s.filmId] case final f?) Poster(f, width: w, radius: 2),
                                    if (o.titles)
                                      Text(
                                        d.films[s.filmId]?.title ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: o.ink),
                                      ),
                                    if (o.dates && s.precision == DatePrecision.day)
                                      Text(fmtShort(context, s.date!), style: TextStyle(fontSize: 9, color: o.soft)),
                                    if (o.ratings && s.rating != null)
                                      Stars(s.rating!, size: 8, color: serialRed, empty: o.soft),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            _Foot(o),
          ],
        ),
      );
    },
  );
}

/// Headline numbers and top lists for a stats period.
class StatsShare extends ShareContent {
  const StatsShare({required this.period, required this.title});
  final Period period;
  final String title;

  @override
  Size get size => const Size(380, 640);
  @override
  String get fileName => 'talkies-stats-${period.year}.png';

  @override
  Widget build(BuildContext context, ShareOptions o) => Consumer(
    builder: (context, ref, _) {
      final st = computeStats(ref.watch(diaryProvider), period);
      final l = context.l;
      Widget big(String v, String k) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v, style: disp(40, o.ink, spacing: 0.6)),
            Text(
              k,
              style: TextStyle(color: o.soft, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
      );
      Widget top(String heading, List<Bucket> b, String Function(String) name) => b.isEmpty
          ? const SizedBox()
          : Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading.toUpperCase(), style: disp(14, o.soft, spacing: 1.4)),
                  const SizedBox(height: 4),
                  for (final x in b.take(3))
                    Text(
                      '${name(x.key)}  ${x.count}',
                      style: TextStyle(color: o.ink, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                ],
              ),
            );
      return Container(
        color: o.bg,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: disp(34, o.ink, spacing: 1)),
            const SizedBox(height: 18),
            Row(children: [big('${st.count}', l.totalStubs), big(fmtRuntime(context, st.minutes), l.totalTime)]),
            if (st.paidCount > 0) ...[
              const SizedBox(height: 12),
              Row(children: [big(rupees(st.spent), l.spent), big('${st.fdfs}', l.fdfsCount)]),
            ],
            top(l.byLanguage, st.languages, (k) => langName(context, k)),
            top(l.byGenre, st.genres, (k) => genreName(context, k)),
            top(l.byDirector, st.directors, (k) => k),
            const Spacer(),
            _Foot(o),
          ],
        ),
      );
    },
  );
}
