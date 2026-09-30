import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../l10n/labels.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../share.dart';
import '../theme.dart';
import '../widgets.dart';
import 'record_screen.dart';

class StubScreen extends ConsumerWidget {
  const StubScreen({super.key, required this.stubId, this.justStamped = false});
  final String stubId;
  final bool justStamped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(diaryProvider);
    final p = Palette.of(context);
    final l = context.l;
    final stub = diary.stubs.where((s) => s.id == stubId).firstOrNull;
    final film = stub == null ? null : diary.films[stub.filmId];
    return Scaffold(
      backgroundColor: p.velvet,
      appBar: AppBar(
        backgroundColor: p.velvet,
        foregroundColor: p.onVelvet,
        leading: TkButton(Tk.back, tooltip: l.back, color: p.onVelvet, onPressed: () => Navigator.pop(context)),
        title: stub == null
            ? null
            : Text(
                '${l.ticket.toUpperCase()}  ${l.ticketNo(ticketNo(stub.no)).toUpperCase()}',
                style: disp(22, paperColors[VenueType.ott]!, spacing: 1.4),
              ),
        actions: [
          if (stub != null && film != null)
            TkButton(
              Tk.share,
              tooltip: l.shareTicket,
              color: p.onVelvet,
              onPressed: () => showShareSheet(context, TicketShare(stub: stub, film: film)),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: stub == null || film == null
          ? const SizedBox()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                TicketCard(stub: stub, film: film, pressStamp: justStamped),
                const SizedBox(height: 22),
                InkButton(
                  key: const Key('watched-again'),
                  label: l.watchedAgain,
                  icon: Tk.again,
                  onPressed: () =>
                      Navigator.of(context)
                          .pushReplacement(MaterialPageRoute(builder: (_) => RecordScreen(film: film))),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        key: const Key('tear-up'),
                        onPressed: () => _delete(context, ref, stub, film),
                        icon: TkIcon(Tk.trash, size: 20, color: p.onVelvet),
                        label: Text(
                          l.tearUp,
                          style: TextStyle(color: p.onVelvet, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        key: const Key('edit-stub'),
                        onPressed: () => push(context, RecordScreen(film: film, editing: stub)),
                        icon: TkIcon(Tk.edit, size: 20, color: p.onVelvet),
                        label: Text(
                          l.edit,
                          style: TextStyle(color: p.onVelvet, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Stub stub, Film film) async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.tearUpQ),
        content: Text(l.tearUpBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          TextButton(key: const Key('confirm-tear'), onPressed: () => Navigator.pop(c, true), child: Text(l.tearUp)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final n = ref.read(diaryProvider.notifier);
    n.deleteStub(stub.id);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.stubDeleted),
        action: SnackBarAction(label: l.undo, onPressed: () => n.restoreStub(stub, film)),
      ),
    );
  }
}

/// The ticket. Also rendered off screen for the share image.
class TicketCard extends ConsumerWidget {
  const TicketCard({
    super.key,
    required this.stub,
    required this.film,
    this.pressStamp = false,
    this.interactive = true,
  });
  final Stub stub;
  final Film film;
  final bool pressStamp, interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(diaryProvider);
    final showRatings = ref.watch(settingsProvider.select((s) => s.showRatings));
    final p = Palette.of(context);
    final l = context.l;
    // The perforation sits under the film block; larger system text moves it down.
    final top = textHeight(context, 214, 150);
    final type = diary.venueType(stub.place);
    final viewing = diary.viewingNumber(stub);
    final meta = [
      if (film.year != null) '${film.year}',
      if (film.runtime != null) fmtRuntime(context, film.runtime!),
      if (film.series && film.seasons != null) l.seasons(film.seasons!),
    ].join('  ·  ');
    final fields = <(String, String)>[
      (l.labelDate, stub.date == null ? l.dateUnknown : fmtStubDate(context, stub)),
      (l.labelPlace, stub.place == null ? '-' : placeName(context, stub.place!)),
      if (stub.show != null) (l.labelShow, showName(context, stub.show!)),
      if (stub.seatClass != null) (l.labelClass, stub.seatClass!),
      if (stub.seat != null) (l.labelSeat, stub.seat!),
      if (stub.format != null) (l.labelFormat, formatName(stub.format!)),
      if (stub.price != null) (l.labelPrice, rupees(stub.price!)),
      if (stub.lang != null) (l.labelLang, langName(context, stub.lang!)),
      if (stub.company != null) (l.labelWith, stub.company!),
    ];
    final stamp = Stamp(
      word: l.stampWatched,
      line: stub.precision == DatePrecision.day && stub.date != null ? fmtTicketDate(stub.date!) : null,
      color: p.accent,
      size: 78,
      seed: stub.no,
    );

    return TicketPaper(
      color: p.paper(type),
      shape: TicketBorder(radius: 10, notch: 11, notchY: top),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: paperInk),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: top,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(l.admitOne, style: disp(13, paperInkSoft, spacing: 2.2)),
                            const Spacer(),
                            if (stub.place != null)
                              Flexible(
                                child: Text(
                                  placeName(context, stub.place!).toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: disp(13, paperInk, spacing: 1.4),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: interactive ? () => openFilm(context, film) : null,
                              child: Poster(film, width: 96, radius: 3),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Padding(
                                // Clear of the stamp: stamp is 78 wide, 12 from the edge.
                                padding: const EdgeInsets.only(right: 74),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      film.title,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        height: 1.15,
                                        color: paperInk,
                                      ),
                                    ),
                                    if (film.original != null)
                                      Text(
                                        film.original!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13, color: paperInkSoft),
                                      ),
                                    const SizedBox(height: 6),
                                    Text(
                                      meta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, color: paperInkSoft, height: 1.3),
                                    ),
                                    if (film.directors.isNotEmpty)
                                      Text(
                                        film.directors.first,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12.5, color: paperInkSoft, height: 1.3),
                                      ),
                                    if (film.genres.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          film.genres.take(2).map((g) => genreName(context, g)).join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: serialRed,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    if (interactive && film.wiki != null) ...[
                                      const SizedBox(height: 10),
                                      _SynopsisButton(film: film),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 42,
                    child: StampPress(play: pressStamp, child: stamp),
                  ),
                  if (stub.fdfs)
                    Positioned(
                      right: 20,
                      bottom: 22,
                      child: Transform.rotate(
                        angle: 0.12,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 3),
                          decoration: BoxDecoration(
                            border: Border.all(color: p.accent.withValues(alpha: 0.85), width: 2),
                          ),
                          child: Text(l.fdfs, style: disp(16, p.accent.withValues(alpha: 0.85), spacing: 2)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final w = (c.maxWidth - 16) / 2;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 14,
                        children: [for (final (k, v) in fields) SizedBox(width: w, child: _Field(k, v))],
                      );
                    },
                  ),
                  if (showRatings) ...[
                    const SizedBox(height: 16),
                    _Cap(l.labelRating),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Stars(stub.rating ?? 0, size: 22, color: serialRed, empty: paperInkSoft),
                        const SizedBox(width: 10),
                        Text(
                          stub.rating == null ? l.noRating : fmtRating(stub.rating!),
                          style: stub.rating == null
                              ? const TextStyle(color: paperInkSoft, fontWeight: FontWeight.w600)
                              : disp(22, paperInk),
                        ),
                      ],
                    ),
                  ],
                  if (stub.tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Cap(l.labelTags),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final t in stub.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: paperInk, width: 1.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '#$t',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: paperInk),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _Cap(l.labelMemo),
                  const SizedBox(height: 4),
                  _RuledNote(stub.memo),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        l.watchNth(viewing),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: paperInkSoft),
                      ),
                      const Spacer(),
                      Text('No. ', style: disp(14, paperInkSoft, spacing: 1)),
                      Text(ticketNo(stub.no), style: disp(26, serialRed, spacing: 1.5)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cap extends StatelessWidget {
  const _Cap(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: disp(12, paperInkSoft, spacing: 1.6));
}

class _Field extends StatelessWidget {
  const _Field(this.k, this.v);
  final String k, v;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Cap(k),
      const SizedBox(height: 3),
      Text(
        v,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: paperInk),
      ),
    ],
  );
}

/// Notes written on ruled lines, at least three lines tall.
class _RuledNote extends StatelessWidget {
  const _RuledNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    const lh = 26.0;
    return CustomPaint(
      painter: _Rules(lh),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: lh * 3),
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            text,
            style: const TextStyle(fontSize: 14.5, height: lh / 14.5, color: paperInk),
          ),
        ),
      ),
    );
  }
}

class _Rules extends CustomPainter {
  _Rules(this.lh);
  final double lh;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = paperInk.withValues(alpha: 0.18)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var y = lh + 3; y <= size.height + 0.5; y += lh) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_Rules old) => false;
}

class _SynopsisButton extends StatelessWidget {
  const _SynopsisButton({required this.film});
  final Film film;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => showSynopsis(context, film),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: paperInk, width: 1.3),
        borderRadius: BorderRadius.circular(2),
      ),
      // One line always: long words (Tamil) shrink instead of breaking.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          context.l.synopsis,
          maxLines: 1,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: paperInk),
        ),
      ),
    ),
  );
}

void showSynopsis(BuildContext context, Film film) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) {
    final p = Palette.of(c);
    final l = c.l;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
        child: FutureBuilder<String?>(
          future: film.wiki == null ? Future.value(null) : fetchSynopsis(film.wiki!),
          builder: (c, snap) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(film.title.toUpperCase(), style: disp(22, p.ink)),
              const SizedBox(height: 12),
              if (snap.connectionState != ConnectionState.done)
                const Center(
                  child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
                )
              else
                Text(
                  snap.hasError
                      ? l.synopsisOffline
                      : (snap.data?.trim().isNotEmpty ?? false)
                      ? snap.data!
                      : l.synopsisNone,
                  style: TextStyle(height: 1.5, color: snap.hasError ? p.inkSoft : p.ink),
                ),
            ],
          ),
        ),
      ),
    );
  },
);
