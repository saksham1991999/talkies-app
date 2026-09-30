import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';
import 'record_screen.dart' show VenueDialog;

AppBar _bar(BuildContext context, String title) => AppBar(
  leading: TkButton(Tk.back, tooltip: context.l.back, onPressed: () => Navigator.pop(context)),
  title: Text(title.toUpperCase(), style: disp(24, Palette.of(context).ink)),
);

Future<bool> _confirm(BuildContext context, String text, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.l.cancel)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

Future<String?> _ask(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(prefixText: '# '),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(context.l.cancel)),
        TextButton(onPressed: () => Navigator.pop(d, c.text), child: Text(context.l.save)),
      ],
    ),
  ).whenComplete(c.dispose);
}

class TagsScreen extends ConsumerStatefulWidget {
  const TagsScreen({super.key});

  @override
  ConsumerState<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends ConsumerState<TagsScreen> {
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  void _add() {
    ref.read(diaryProvider.notifier).addTag(_new.text);
    _new.clear();
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(diaryProvider);
    final n = ref.read(diaryProvider.notifier);
    final p = Palette.of(context);
    final l = context.l;
    return Scaffold(
      appBar: _bar(context, l.manageTags),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              controller: _new,
              onSubmitted: (_) => _add(),
              decoration: InputDecoration(
                hintText: l.tagHint,
                prefixText: '# ',
                suffixIcon: TkButton(Tk.plus, tooltip: l.addTag, onPressed: _add),
              ),
            ),
          ),
          if (d.tags.isEmpty) EmptyNote(l.tagsEmpty),
          for (final t in d.tags)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 20, right: 8),
              title: Text('#$t', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                l.stubsUsing(d.stubs.where((s) => s.tags.contains(t)).length),
                style: TextStyle(color: p.inkSoft),
              ),
              onTap: () async {
                final v = await _ask(context, l.renameTag, t);
                if (v != null) n.renameTag(t, v);
              },
              trailing: TkButton(
                Tk.trash,
                tooltip: l.delete,
                color: p.inkSoft,
                onPressed: () async {
                  final count = d.stubs.where((s) => s.tags.contains(t)).length;
                  if (await _confirm(context, l.deleteTagQ(t, count), l.delete)) n.deleteTag(t);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class VenuesScreen extends ConsumerWidget {
  const VenuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(diaryProvider);
    final n = ref.read(diaryProvider.notifier);
    final p = Palette.of(context);
    final l = context.l;
    return Scaffold(
      appBar: _bar(context, l.manageVenues),
      floatingActionButton: RecordFab(
        tooltip: l.addPlace,
        onPressed: () async {
          final v = await showDialog<Venue>(context: context, builder: (_) => const VenueDialog());
          if (v != null) n.addVenue(v);
        },
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          for (final v in d.venues)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 20, right: 8),
              leading: Container(
                width: 14,
                height: 22,
                decoration: BoxDecoration(color: p.paper(v.type), borderRadius: BorderRadius.circular(2)),
              ),
              title: Text(placeName(context, v.name), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${venueTypeName(context, v.type)} · ${l.stubsUsing(d.stubs.where((s) => s.place == v.name).length)}',
                style: TextStyle(color: p.inkSoft),
              ),
              onTap: () async {
                final next = await showDialog<Venue>(
                  context: context,
                  builder: (_) => VenueDialog(initial: v),
                );
                if (next != null) n.updateVenue(v, next);
              },
              trailing: TkButton(
                Tk.trash,
                tooltip: l.remove,
                color: p.inkSoft,
                onPressed: () async {
                  if (await _confirm(context, l.deleteVenueQ(v.name), l.remove)) n.deleteVenue(v.name);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// One title per line, matched offline. Unmatched lines become the user's own films.
class BatchScreen extends ConsumerStatefulWidget {
  const BatchScreen({super.key});

  @override
  ConsumerState<BatchScreen> createState() => _BatchScreenState();
}

/// Splits "Sholay 1975", "RRR (2022)" or "Panchayat" into a title and a year.
(String, int?) splitTitleYear(String line) {
  final m = RegExp(r'^(.*?)[\s,(\[]+((?:18|19|20)\d{2})[)\]]?\s*$').firstMatch(line.trim());
  if (m != null && m[1]!.trim().isNotEmpty) return (m[1]!.trim(), int.parse(m[2]!));
  return (line.trim(), null);
}

class _BatchScreenState extends ConsumerState<BatchScreen> {
  final _text = TextEditingController();
  List<(String, int?, Film?)>? _rows;
  String? _place;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _match() async {
    FocusScope.of(context).unfocus();
    final cat = await ref.read(catalogProvider.future);
    if (!mounted) return;
    final rows = <(String, int?, Film?)>[];
    for (final line in _text.text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final (t, y) = splitTitleYear(line);
      final hit = cat.match(t, y) ?? (y == null ? cat.search(t, limit: 1, titleOnly: true).firstOrNull : null);
      rows.add((t, y, hit));
    }
    setState(() => _rows = rows);
  }

  void _addAll() {
    final n = ref.read(diaryProvider.notifier);
    final l = context.l;
    final out = <(Film, StubDraft)>[];
    for (final (t, y, f) in _rows!) {
      final film = f ?? n.addCustomFilm(title: t, year: y);
      out.add((film, StubDraft(precision: DatePrecision.none, place: _place)));
    }
    n.addStubs(out);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.batchDone(out.length))));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(diaryProvider);
    final p = Palette.of(context);
    final l = context.l;
    final rows = _rows;
    return Scaffold(
      appBar: _bar(context, l.batchTitle),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text(l.batchHint, style: TextStyle(color: p.inkSoft)),
          const SizedBox(height: 10),
          TextField(
            key: const Key('batch-text'),
            controller: _text,
            minLines: 5,
            maxLines: 12,
            onChanged: (_) => setState(() => _rows = null),
            decoration: InputDecoration(hintText: l.batchExample),
          ),
          const SizedBox(height: 12),
          if (rows == null)
            InkButton(
              key: const Key('batch-match'),
              label: l.batchMatch,
              onPressed: _text.text.trim().isEmpty ? null : _match,
            )
          else ...[
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    if (rows[i].$3 != null) Poster(rows[i].$3!, width: 38, radius: 2) else const SizedBox(width: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rows[i].$3?.title ?? rows[i].$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            rows[i].$3 == null
                                ? l.batchOwn
                                : [
                                    if (rows[i].$3!.year != null) '${rows[i].$3!.year}',
                                    ...rows[i].$3!.directors.take(1),
                                  ].join(' · '),
                            style: TextStyle(color: p.inkSoft, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    TkButton(
                      Tk.close,
                      tooltip: l.remove,
                      size: 18,
                      color: p.inkSoft,
                      onPressed: () => setState(() => rows.removeAt(i)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Text(l.batchDefaults, style: disp(16, p.ink)),
            const SizedBox(height: 8),
            Text(l.dateUnknown, style: TextStyle(color: p.inkSoft)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in d.venues)
                  OptionBox(
                    label: placeName(context, v.name),
                    dense: true,
                    selected: _place == v.name,
                    onTap: () => setState(() => _place = _place == v.name ? null : v.name),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            InkButton(
              key: const Key('batch-add'),
              label: l.batchAddAll(rows.length),
              onPressed: rows.isEmpty ? null : _addAll,
            ),
          ],
        ],
      ),
    );
  }
}
