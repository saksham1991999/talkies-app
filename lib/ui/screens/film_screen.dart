import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../l10n/labels.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../group_sheets.dart';
import '../icons.dart';
import '../online_widgets.dart';
import '../sharer.dart';
import '../theme.dart';
import '../widgets.dart';

final synopsisProvider = FutureProvider.family<String?, String>((ref, wiki) => fetchSynopsis(wiki));

/// Streaming services named in the film's Wikipedia article, read live.
final streamingProvider = FutureProvider.family<List<String>, String>((ref, wiki) async {
  final c = http.Client();
  try {
    return (await fetchStreaming(c, [wiki]))[wiki] ?? const [];
  } finally {
    c.close();
  }
});

class FilmScreen extends ConsumerWidget {
  const FilmScreen({super.key, required this.filmId, required this.fallback});
  final String filmId;
  final Film fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final film = filmOf(ref, filmId) ?? fallback;
    final diary = ref.watch(diaryProvider);
    final stubs = diary.stubsOf(film.id).reversed.toList();
    final wish = diary.wishFor(film.id);
    // Recent films reach OTT weeks after cinemas: check the article live for
    // them, and for any film with no known service. Offline keeps the list.
    final today = ref.watch(todayProvider);
    final live = film.wiki == null || film.isCustom || (film.ott.isNotEmpty && (film.year ?? 0) < today.year - 1)
        ? null
        : ref.watch(streamingProvider(film.wiki!)).value;
    final services = {...film.ott, ...?live}.toList();
    final p = Palette.of(context);
    final l = context.l;
    final meta = [
      if (film.date != null) fmtRelease(context, film) else if (film.year != null) '${film.year}',
      if (film.runtime != null) fmtRuntime(context, film.runtime!),
      if (film.series) l.kindSeries,
      if (film.seasons != null) l.seasons(film.seasons!),
    ].join('  ·  ');

    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Poster(film, width: 128, radius: 4),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(film.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
                      if (film.original != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(film.original!, style: TextStyle(color: p.inkSoft, fontSize: 15)),
                        ),
                      const SizedBox(height: 8),
                      Text(meta, style: TextStyle(color: p.inkSoft, fontSize: 13.5, height: 1.4)),
                      if (film.genres.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            film.genres.map((g) => genreName(context, g)).join(' · '),
                            style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                      if (stubs.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(l.watchCount(stubs.length), style: disp(17, serialRed, spacing: 0.6)),
                        ),
                      if (film.isCustom)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            l.yourOwnFilm,
                            style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkButton(
                  key: const Key('i-watched'),
                  label: stubs.isEmpty ? l.iWatched : l.watchedAgain,
                  icon: Tk.stubs,
                  onPressed: () => recordFilm(context, film),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      key: const Key('toggle-wish'),
                      onPressed: () {
                        ref.read(diaryProvider.notifier).toggleWish(film);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(content: Text(wish == null ? l.addedToWatchlist : l.removedFromWatchlist)),
                          );
                      },
                      icon: TkIcon(
                        wish == null ? Tk.bookmark : Tk.bookmarked,
                        size: 20,
                        color: wish == null ? p.ink : p.accent,
                      ),
                      label: Text(
                        wish == null ? l.wantToWatch : l.inWatchlist,
                        style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Spacer(),
                    if (wish != null)
                      TextButton(
                        key: const Key('plan-date'),
                        onPressed: () => _plan(context, ref, wish),
                        child: Text(
                          wish.planned == null ? l.setPlannedDate : l.plannedFor(fmtShort(context, wish.planned!)),
                          style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (wish?.planned != null)
                      TkButton(
                        Tk.close,
                        tooltip: l.clearDate,
                        size: 18,
                        color: p.inkSoft,
                        onPressed: () => ref.read(diaryProvider.notifier).setPlanned(film.id, null),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Wrap(
              children: [
                TextButton.icon(
                  key: const Key('add-to-group'),
                  onPressed: () => _addToGroup(context, film),
                  icon: TkIcon(Tk.people, size: 20, color: p.ink),
                  label: Text(
                    l.togetherAddToGroup,
                    style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
                  ),
                ),
                Builder(
                  builder: (anchor) => TextButton.icon(
                    key: const Key('share-film'),
                    onPressed: () => _share(anchor, ref, film),
                    icon: TkIcon(Tk.share, size: 20, color: p.ink),
                    label: Text(
                      l.togetherShareFilm,
                      style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Online only: each draws nothing while the server is not up, or for a film the phone made itself.
          SendFilmButton(film: film),
          FriendsWhoWatched(film: film),
          if (services.isNotEmpty) ...[
            SectionTitle(l.availableOn),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in services)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: p.paper(VenueType.ott), borderRadius: BorderRadius.circular(3)),
                      child: Text(
                        ottName(o),
                        style: const TextStyle(color: paperInk, fontWeight: FontWeight.w800),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(l.streamingHint, style: TextStyle(color: p.inkSoft, fontSize: 12.5)),
            ),
          ],
          if (film.wiki != null && !film.isCustom) _Synopsis(wiki: film.wiki!),
          _Facts(film: film),
          if (stubs.isNotEmpty) ...[SectionTitle(l.yourStubs), for (final s in stubs) StubRow(s, key: ValueKey(s.id))],
          if (!film.isCustom) ...[
            const SizedBox(height: 20),
            if (film.wiki != null)
              _Link(
                label: l.openWikipedia,
                url: 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(film.wiki!.replaceAll(' ', '_'))}',
              ),
            _Link(label: l.fixOnWikidata, url: 'https://www.wikidata.org/wiki/${film.id}'),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
              child: Text(l.fixHint, style: TextStyle(color: p.inkSoft, fontSize: 12.5)),
            ),
          ],
        ],
      ),
    );
  }

  /// The share sheet with the title, the year, the Wikipedia page when the film has one and a line about
  /// Talkies. Nothing is fetched.
  Future<void> _share(BuildContext anchor, WidgetRef ref, Film film) async {
    final line = anchor.l.togetherShareFilmLine;
    final wiki = film.wiki == null || film.isCustom
        ? null
        : 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(film.wiki!.replaceAll(' ', '_'))}';
    final text = [film.year == null ? film.title : '${film.title} (${film.year})', ?wiki, '', line].join('\n');
    final origin = shareOrigin(anchor);
    try {
      await ref.read(sharerProvider).text(text, subject: film.title, origin: origin);
    } catch (_) {
      // A phone with no share sheet has nothing to show; the film stays where it is.
    }
  }

  /// A sheet of the groups: the film goes to the one the person taps. A new group can be made on the spot.
  Future<void> _addToGroup(BuildContext context, Film film) async {
    final group = await showAddToGroupSheet(context, film);
    if (group == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l.togetherAddedTo(group))));
  }

  Future<void> _plan(BuildContext context, WidgetRef ref, Wish wish) async {
    final today = ref.read(todayProvider);
    final d = await showDatePicker(
      context: context,
      initialDate: wish.planned ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 3),
    );
    if (d != null) ref.read(diaryProvider.notifier).setPlanned(wish.filmId, d);
  }
}

class _Synopsis extends ConsumerWidget {
  const _Synopsis({required this.wiki});
  final String wiki;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final l = context.l;
    final s = ref.watch(synopsisProvider(wiki));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l.synopsis),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: switch (s) {
            AsyncData(:final value) => Text(
              (value ?? '').trim().isEmpty ? l.synopsisNone : value!,
              style: TextStyle(height: 1.5, color: (value ?? '').isEmpty ? p.inkSoft : p.ink),
            ),
            AsyncError() => Row(
              children: [
                Expanded(
                  child: Text(l.synopsisOffline, style: TextStyle(color: p.inkSoft)),
                ),
                TkButton(Tk.refresh, tooltip: l.refreshNow, onPressed: () => ref.invalidate(synopsisProvider(wiki))),
              ],
            ),
            _ => const LinearProgressIndicator(minHeight: 2),
          },
        ),
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.film});
  final Film film;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final rows = <(String, String)>[
      if (film.directors.isNotEmpty) (l.director, film.directors.join(', ')),
      if (film.cast.isNotEmpty) (l.cast, film.cast.join(', ')),
      if (film.langs.isNotEmpty) (l.language, film.langs.map((c) => langName(context, c)).join(', ')),
      if (film.countries.isNotEmpty) (l.country, film.countries.map((c) => countryName(context, c)).join(', ')),
    ];
    if (rows.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      k,
                      style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                  Expanded(child: Text(v, style: const TextStyle(fontSize: 14.5, height: 1.35))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.url});
  final String label, url;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
              ),
            ),
            TkIcon(Tk.share, size: 18, color: p.inkSoft),
          ],
        ),
      ),
    );
  }
}
