import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog.dart';
import '../../data/models.dart';
import '../../l10n/labels.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';
import 'custom_film_screen.dart';
import 'record_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.forRecord = false, this.recordDay, this.onPick, this.includeCustom = true});

  /// Tapping a result opens the stub form instead of the film page.
  final bool forRecord;
  final DateTime? recordDay;

  /// Pick mode, for choosing a film for something else (a group list, a night): tapping a result
  /// hands the film over and closes the screen. The bookmark button and "add it yourself" are not shown.
  final ValueChanged<Film>? onPick;

  /// False hides the phone's own films from the results. Pickers whose target
  /// lives on the server (a chat message, a film sent to a friend) cannot take
  /// them: a `my:` id names a film only this phone knows.
  final bool includeCustom;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _q = TextEditingController();
  bool? _series;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _pick(Film f) {
    if (widget.onPick != null) {
      widget.onPick!(f);
      Navigator.of(context).pop();
    } else if (widget.forRecord) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RecordScreen(film: f, day: widget.recordDay),
        ),
      );
    } else {
      openFilm(context, f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final diary = ref.watch(diaryProvider);
    final p = Palette.of(context);
    final l = context.l;
    final q = _q.text.trim();

    List<Film> results = const [];
    if (catalog.value != null && q.isNotEmpty) {
      final nq = norm(q);
      final own = widget.includeCustom
          ? diary.films.values
                .where((f) => f.isCustom && (_series == null || f.series == _series) && norm(f.title).contains(nq))
                .toList()
          : const <Film>[];
      results = [...own, ...catalog.value!.search(q, series: _series)];
    }

    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: TextField(
          key: const Key('search-field'),
          controller: _q,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l.searchHint,
            isDense: true,
            suffixIcon: q.isEmpty
                ? null
                : TkButton(Tk.close, tooltip: l.clear, size: 18, onPressed: () => setState(_q.clear)),
          ),
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              children: [
                for (final (v, label) in [(null, l.searchAll), (false, l.kindFilm), (true, l.kindSeries)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OptionBox(
                      label: label,
                      dense: true,
                      selected: _series == v,
                      onTap: () => setState(() => _series = v),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            // A refresh reloads the catalog; keep showing the previous one meanwhile.
            child: switch (catalog.value) {
              final Catalog value => ListView.builder(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 40),
                itemCount: results.length + 1,
                itemBuilder: (context, i) {
                  if (i < results.length) {
                    return _ResultRow(
                      results[i],
                      onTap: () => _pick(results[i]),
                      forRecord: widget.forRecord || widget.onPick != null,
                    );
                  }
                  return _Footer(
                    prompt: q.isEmpty
                        ? l.searchPrompt(fmtCount(value.items.length))
                        : (results.isEmpty ? l.noResults(q) : null),
                    canAdd: widget.onPick == null,
                    onAdd: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) =>
                            CustomFilmScreen(initialTitle: q, forRecord: widget.forRecord, recordDay: widget.recordDay),
                      ),
                    ),
                    p: p,
                  );
                },
              ),
              _ when catalog.hasError => EmptyNote(l.catalogError),
              _ => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(l.loadingCatalog, style: TextStyle(color: p.inkSoft)),
                  ],
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.prompt, required this.onAdd, required this.p, this.canAdd = true});
  final String? prompt;
  final VoidCallback onAdd;
  final Palette p;
  final bool canAdd;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        children: [
          if (prompt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                prompt!,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.inkSoft, height: 1.4),
              ),
            ),
          if (canAdd) ...[
            Text(l.notFound, style: TextStyle(color: p.inkSoft)),
            TextButton(
              key: const Key('add-own-film'),
              onPressed: onAdd,
              child: Text(
                l.addManually,
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends ConsumerWidget {
  const _ResultRow(this.film, {required this.onTap, required this.forRecord});
  final Film film;
  final VoidCallback onTap;
  final bool forRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final l = context.l;
    final diary = ref.watch(diaryProvider);
    final watched = diary.stubs.where((s) => s.filmId == film.id).length;
    final wished = diary.wishFor(film.id) != null;
    final meta = [
      if (film.year != null) '${film.year}',
      if (film.series) l.kindSeries,
      if (film.mainLang != null) langName(context, film.mainLang!),
      if (film.directors.isNotEmpty) film.directors.first,
    ].join('  ·  ');
    return InkWell(
      onTap: onTap,
      onLongPress: forRecord ? () => openFilm(context, film) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Poster(film, width: 46, radius: 3),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    film.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  if (film.original != null)
                    Text(
                      film.original!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                  ),
                  if (film.cast.isNotEmpty)
                    Text(
                      film.cast.take(3).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.inkSoft),
                    ),
                ],
              ),
            ),
            if (watched > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: l.watchCount(watched),
                  child: Text('×$watched', style: disp(16, serialRed)),
                ),
              )
            else if (!forRecord)
              TkButton(
                wished ? Tk.bookmarked : Tk.bookmark,
                tooltip: wished ? l.inWatchlist : l.wantToWatch,
                color: wished ? p.accent : p.inkSoft,
                onPressed: () => ref.read(diaryProvider.notifier).toggleWish(film),
              ),
          ],
        ),
      ),
    );
  }
}
