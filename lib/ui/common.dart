import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../l10n/labels.dart';
import '../state/providers.dart';
import 'format.dart';
import 'icons.dart';
import 'screens/film_screen.dart';
import 'screens/record_screen.dart';
import 'screens/search_screen.dart';
import 'screens/stub_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Serial numbers on Indian hall tickets are printed in red.
const serialRed = Color(0xFFB0342B);

Future<T?> push<T>(BuildContext c, Widget page) => Navigator.of(c).push<T>(MaterialPageRoute(builder: (_) => page));

void openFilm(BuildContext c, Film f) => push(c, FilmScreen(filmId: f.id, fallback: f));
void openStub(BuildContext c, Stub s) => push(c, StubScreen(stubId: s.id));

/// + button flow: search, pick a film, fill the stub.
void startRecord(BuildContext c, {DateTime? day}) => push(c, SearchScreen(recordDay: day, forRecord: true));

void recordFilm(BuildContext c, Film f, {DateTime? day}) => push(c, RecordScreen(film: f, day: day));

/// Film snapshot for a stub or wish: diary copy first, catalog as fallback.
Film? filmOf(WidgetRef ref, String id) {
  final d = ref.watch(diaryProvider).films[id];
  if (d != null) return d;
  return ref.watch(catalogProvider).value?.byId[id];
}

/// One viewing, drawn as a horizontal ticket with a tear-off counterfoil.
class StubRow extends ConsumerWidget {
  const StubRow(this.stub, {super.key});
  final Stub stub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(diaryProvider);
    final showRatings = ref.watch(settingsProvider.select((s) => s.showRatings));
    final film = diary.films[stub.filmId];
    final p = Palette.of(context);
    final paper = p.paper(diary.venueType(stub.place));
    final viewing = diary.viewingNumber(stub);
    final title = film?.title ?? '?';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Semantics(
        button: true,
        label: '$title, ${fmtStubDate(context, stub)}',
        child: GestureDetector(
          onTap: () => openStub(context, stub),
          child: TicketPaper(
            color: paper,
            shape: const TicketBorder(radius: 6, notch: 7, notchFromRight: 72),
            child: SizedBox(
              // 100 at normal text size; four text lines grow with larger system text.
              height: textHeight(context, 100, 70),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: film == null ? const SizedBox(width: 50) : Poster(film, width: 50, radius: 3),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: paperInk),
                          ),
                          if (film?.original != null)
                            Text(
                              film!.original!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: paperInkSoft),
                            ),
                          const SizedBox(height: 5),
                          if (showRatings)
                            Row(
                              children: [
                                Stars(stub.rating ?? 0, size: 13, color: serialRed, empty: paperInkSoft),
                                if (stub.rating != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    fmtRating(stub.rating!),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: paperInk),
                                  ),
                                ],
                              ],
                            ),
                          const SizedBox(height: 5),
                          Text(
                            [
                              fmtStubShort(context, stub),
                              if (stub.place != null) placeName(context, stub.place!),
                            ].join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: paperInkSoft, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('No.', style: disp(11, paperInkSoft, spacing: 1)),
                        Text(ticketNo(stub.no), style: disp(21, serialRed, spacing: 1)),
                        const SizedBox(height: 4),
                        if (stub.fdfs)
                          Text(context.l.fdfs, style: disp(12, paperInk, spacing: 1.2))
                        else if (viewing > 1)
                          Text('×$viewing', style: disp(13, paperInk, spacing: 0.6)),
                      ],
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
}

/// Poster in a grid, with a bookmark ribbon for the watchlist and a strip
/// showing the release date or how many times you have watched it.
class PosterTile extends ConsumerWidget {
  const PosterTile(this.film, {super.key, required this.width, this.strip, this.onTap});
  final Film film;
  final double width;
  final String? strip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(diaryProvider);
    final wished = diary.wishFor(film.id) != null;
    final watched = diary.stubs.where((s) => s.filmId == film.id).length;
    final p = Palette.of(context);
    final l = context.l;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Semantics(
                button: true,
                label: film.title,
                child: GestureDetector(
                  onTap: onTap ?? () => openFilm(context, film),
                  child: Poster(film, width: width),
                ),
              ),
              if (strip != null)
                Positioned(
                  left: 0,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 3, 7, 2),
                    color: p.paper(VenueType.ott),
                    child: Text(strip!, style: disp(11.5, paperInk, spacing: 0.6)),
                  ),
                ),
              Positioned(
                right: 4,
                top: 0,
                child: watched > 0
                    ? _Ribbon(color: serialRed, label: '★$watched', tooltip: l.watchCount(watched))
                    : Tooltip(
                        message: wished ? l.inWatchlist : l.wantToWatch,
                        child: InkResponse(
                          radius: 22,
                          onTap: () => ref.read(diaryProvider.notifier).toggleWish(film),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 2, 6),
                            child: _Ribbon(
                              color: wished ? p.paper(VenueType.ott) : p.velvet.withValues(alpha: 0.82),
                              icon: wished ? Tk.check : Tk.plus,
                              iconColor: wished ? paperInk : p.onVelvet,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            film.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink, height: 1.2),
          ),
          if (film.mainLang != null)
            Text(langName(context, film.mainLang!), style: TextStyle(fontSize: 11.5, color: p.inkSoft)),
        ],
      ),
    );
  }
}

/// Bookmark ribbon hanging from the top edge of a poster, V-cut at the tail.
class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.color, this.label, this.icon, this.iconColor, this.tooltip});
  final Color color;
  final String? label;
  final Tk? icon;
  final Color? iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final body = ClipPath(
      clipper: _RibbonClip(),
      child: Container(
        width: 26,
        height: 34,
        color: color,
        alignment: const Alignment(0, -0.35),
        child: label != null
            ? Text(label!, style: disp(10.5, Colors.white, spacing: 0))
            : TkIcon(icon!, size: 15, color: iconColor),
      ),
    );
    return tooltip == null ? body : Tooltip(message: tooltip!, child: body);
  }
}

class _RibbonClip extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width / 2, s.height - 7)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Screen header: big display word with optional actions on the right.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader(this.title, {super.key, this.sub, this.actions = const []});
  final String title;
  final Widget? sub;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: disp(38, p.ink, spacing: 0.6)),
                if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: sub!),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
