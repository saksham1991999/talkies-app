import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crews.dart';
import '../../data/models.dart';
import '../../l10n/labels.dart';
import '../../state/crews.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../night_editor.dart';
import '../theme.dart';
import '../together_widgets.dart';
import '../widgets.dart';

/// Every card of the deck by how many members want it: the top match, a Tonight
/// pick for a group that cannot decide, and the whole list.
class DeckResultsScreen extends ConsumerWidget {
  const DeckResultsScreen({super.key, required this.crewId, this.random});
  final String crewId;

  /// For the Tonight pick. Tests give a seeded one.
  final Random? random;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(crewProvider(crewId));
    final crew = st.crew;
    final p = Palette.of(context);
    final l = context.l;
    final top = st.topMatch;
    final results = st.results;
    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.pop(context)),
        title: Text(l.deckResultsTitle.toUpperCase(), style: disp(26, p.ink)),
      ),
      body: results.isEmpty
          ? EmptyNote(l.deckEmpty)
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (top != null)
                  _TopMatch(
                    card: top,
                    wants: crew.tallies[top.id]?.want ?? 0,
                    onSchedule: () =>
                        push(context, NightEditorScreen(crewId: crewId, films: [for (final c in st.topThree) c.film])),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SlabButton(
                    key: const Key('deck-tonight'),
                    label: l.deckTonight,
                    icon: Tk.clock,
                    tone: SlabTone.velvet,
                    onPressed: () => showSheet<void>(context, (_) => TonightSheet(crewId: crewId, random: random)),
                  ),
                ),
                SectionTitle(l.deckMostWanted),
                for (final c in results)
                  _ResultRow(card: c, wants: crew.tallies[c.id]?.want ?? 0, seenBy: st.seenBy(c)),
              ],
            ),
    );
  }
}

class _TopMatch extends StatelessWidget {
  const _TopMatch({required this.card, required this.wants, required this.onSchedule});
  final DeckCard card;
  final int wants;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TicketPaper(
            color: p.paper(VenueType.ott),
            shape: const TicketBorder(radius: 6, notch: 7, notchFromRight: 88),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 118),
              child: Row(
                children: [
                  Padding(padding: const EdgeInsets.all(12), child: Poster(card.film, width: 62, radius: 3)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.film.title.toUpperCase(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: disp(22, paperInk, spacing: 0.5, height: 1.05),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.deckTopMatch,
                            style: const TextStyle(fontSize: 12.5, color: paperInkSoft, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 88,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$wants', style: disp(38, serialRed, spacing: 0.5)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(l.deckWant.toUpperCase(), style: disp(13, paperInkSoft, spacing: 1)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SlabButton(key: const Key('deck-schedule'), label: l.deckSchedule, icon: Tk.clock, onPressed: onSchedule),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.card, required this.wants, required this.seenBy});
  final DeckCard card;
  final int wants, seenBy;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final film = card.film;
    final meta = [
      if (film.year != null) '${film.year}',
      if (film.mainLang != null) langName(context, film.mainLang!),
      if (seenBy > 0) l.deckSeenBy(seenBy),
    ].join('  ·  ');
    return InkWell(
      onTap: () => openFilm(context, film),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Poster(film, width: 44, radius: 3),
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
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              label: l.deckWantCount(wants),
              excludeSemantics: true,
              child: SizedBox(
                width: 52,
                child: Column(
                  children: [
                    Text('$wants', style: disp(26, wants > 0 ? p.accent : p.inkSoft, spacing: 0.5)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l.deckWant.toUpperCase(), style: disp(11, p.inkSoft, spacing: 1)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tonight's pick: one film at random among those most wanted, shown as a result
/// with "Schedule it". The group that still cannot decide picks again.
class TonightSheet extends ConsumerStatefulWidget {
  const TonightSheet({super.key, required this.crewId, this.random});
  final String crewId;
  final Random? random;

  @override
  ConsumerState<TonightSheet> createState() => _TonightSheetState();
}

class _TonightSheetState extends ConsumerState<TonightSheet> {
  late final _random = widget.random ?? Random();
  late var _picks = ref.read(crewProvider(widget.crewId)).tonight(_random);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final winner = _picks.firstOrNull;
    if (winner == null) {
      return SheetBody(title: l.deckTonightTitle, children: [Note(l.deckTonightNone)]);
    }
    final wants = ref.watch(crewProvider(widget.crewId)).crew.tallies[winner.id]?.want ?? 0;
    return SheetBody(
      title: l.deckTonightTitle,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Poster(winner.film, width: 92, radius: 3),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    winner.film.title.toUpperCase(),
                    key: const Key('tonight-title'),
                    style: disp(28, p.ink, spacing: 0.5, height: 1.05),
                  ),
                  const SizedBox(height: 6),
                  Text(l.deckWantCount(wants), style: disp(18, serialRed, spacing: 0.6)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SlabButton(
          key: const Key('tonight-schedule'),
          label: l.deckSchedule,
          icon: Tk.clock,
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => NightEditorScreen(crewId: widget.crewId, films: [winner.film]),
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('tonight-again'),
            onPressed: () => setState(() => _picks = ref.read(crewProvider(widget.crewId)).tonight(_random)),
            child: Text(
              l.deckPickAgain,
              style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
