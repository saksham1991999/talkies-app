import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/social.dart';
import '../l10n/labels.dart';
import 'common.dart';
import 'format.dart';
import 'share.dart';
import 'theme.dart';
import 'widgets.dart';

/// What a profile shows, for your own preview and for a friend: the stats ticket, the top films and the
/// watchlist. It holds no date: a [ProfileView] has none.
class ProfileBody extends StatelessWidget {
  const ProfileBody({super.key, required this.view, required this.ratings});
  final ProfileView view;

  /// Show star ratings. False hides them, whatever the view holds.
  final bool ratings;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final stats = view.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stats != null) StatsTicket(stats: stats, ratings: ratings),
        if (view.topFilms.isNotEmpty) ...[
          SectionTitle(l.profileTopFilms),
          FilmStrip([
            for (final t in view.topFilms) (t.film, ratings && t.rating != null ? fmtRating(t.rating!) : null),
          ]),
        ],
        if (view.watchlist.isNotEmpty) ...[
          SectionTitle(l.profileWatchlist),
          FilmStrip([for (final w in view.watchlist) (w.film, null)]),
        ],
      ],
    );
  }
}

/// The numbers of a profile on a ticket: films, viewings and the average rating above the perforation,
/// top genres and languages below it. The perforation sits where the figures end: their height is measured with
/// the real text size and the width of a column, so large text and long words (Tamil) never run into it.
class StatsTicket extends StatelessWidget {
  const StatsTicket({super.key, required this.stats, required this.ratings});
  final ProfileStats stats;
  final bool ratings;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final figures = <(String, String)>[
      ('${stats.films}', l.unitFilms(stats.films)),
      ('${stats.viewings}', l.profileViewings(stats.viewings)),
      if (ratings && stats.avgRating != null) (fmtRating(stats.avgRating!), l.avgRating),
    ];
    final genres = [for (final g in stats.topGenres) genreName(context, g)];
    final langs = [for (final c in stats.topLangs) langName(context, c)];
    final scaler = MediaQuery.textScalerOf(context);
    // The figures are big already: they grow with the text setting only up to 1.2.
    final big = scaler.clamp(maxScaleFactor: 1.2);
    final dir = Directionality.of(context);
    final labelStyle = DefaultTextStyle.of(context).style
        .merge(const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600));
    final figureStyle = disp(46, paperInk, spacing: 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, box) {
          final column = (box.maxWidth - 36) / figures.length;
          double height(String text, TextStyle style, TextScaler ts, int lines) => (TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: dir,
            textScaler: ts,
            maxLines: lines,
          )..layout(maxWidth: column)).height;
          var figureHeight = 0.0;
          for (final (value, label) in figures) {
            figureHeight = math.max(
              figureHeight,
              height(value, figureStyle, big, 1) + 4 + height(label, labelStyle, scaler, 2),
            );
          }
          final top = 14 + figureHeight + 14 + 2;
          return TicketPaper(
            color: p.paper(VenueType.cinema),
            shape: TicketBorder(radius: 10, notch: 11, notchY: top),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: paperInk),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: top,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      // The numbers hang from one line, whatever the labels under them take.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (value, label) in figures)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // A long number (Indian grouping) shrinks the line instead of overflowing.
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(value, textScaler: big, style: disp(46, serialRed, spacing: 1)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: paperInkSoft,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (genres.isNotEmpty) _Field(l.profileTopGenres, genres.join('  ·  ')),
                        if (genres.isNotEmpty && langs.isNotEmpty) const SizedBox(height: 12),
                        if (langs.isNotEmpty) _Field(l.profileTopLangs, langs.join('  ·  ')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A printed field of a ticket: its name in small display caps, its value below.
class _Field extends StatelessWidget {
  const _Field(this.name, this.value);
  final String name, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name.toUpperCase(), style: disp(12, paperInkSoft, spacing: 1.6)),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: paperInk, height: 1.3),
      ),
    ],
  );
}

/// A row of posters that scrolls sideways. Each poster can carry a short tag, like the release strip of Home.
class FilmStrip extends StatelessWidget {
  const FilmStrip(this.items, {super.key});
  final List<(Film, String?)> items;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: textHeight(context, 222, 50),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, i) => PosterTile(items[i].$1, width: 108, strip: items[i].$2),
    ),
  );
}

/// The profile as an image to share: the figures and the top films, built from the same [ProfileView] a
/// friend would see, so a private stub is never on it. There is no date in it.
class ProfileShare extends ShareContent {
  const ProfileShare({required this.view, required this.title, this.handle, required this.ratings});
  final ProfileView view;
  final String title;
  final String? handle;
  final bool ratings;

  @override
  Size get size => const Size(380, 640);
  @override
  String get fileName => 'talkies-profile.png';

  @override
  Widget build(BuildContext context, ShareOptions o) {
    final l = context.l;
    final stats = view.stats;
    Widget big(String v, String k) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: Text(v, style: disp(40, o.ink, spacing: 0.6)),
          ),
          Text(
            k,
            style: TextStyle(color: o.soft, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
    final genres = [for (final g in stats?.topGenres ?? const <String>[]) genreName(context, g)];
    final langs = [for (final c in stats?.topLangs ?? const <String>[]) langName(context, c)];
    final show = o.ratings && ratings;
    Widget line(String name, List<String> values) => values.isEmpty
        ? const SizedBox()
        : Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.toUpperCase(), style: disp(14, o.soft, spacing: 1.4)),
                Text(
                  values.join('  ·  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
          Text(title.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: disp(34, o.ink, spacing: 1)),
          if (handle != null)
            Text(
              '@$handle',
              style: TextStyle(color: o.soft, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 18),
          if (stats != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                big('${stats.films}', l.unitFilms(stats.films)),
                big('${stats.viewings}', l.profileViewings(stats.viewings)),
                if (show && stats.avgRating != null) big(fmtRating(stats.avgRating!), l.avgRating),
              ],
            ),
          line(l.profileTopGenres, genres),
          line(l.profileTopLangs, langs),
          const SizedBox(height: 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                const gap = 10.0, cols = 4;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final t in view.topFilms.take(8))
                      SizedBox(
                        width: w,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Poster(t.film, width: w, radius: 2),
                            Text(
                              t.film.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: o.ink),
                            ),
                            if (show && t.rating != null) Stars(t.rating!, size: 9, color: serialRed, empty: o.soft),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Text('TALKIES', textAlign: TextAlign.center, style: disp(18, o.soft, spacing: 6)),
        ],
      ),
    );
  }
}
