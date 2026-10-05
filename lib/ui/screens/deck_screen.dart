import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog.dart' show norm;
import '../../data/crews.dart';
import '../../state/crews.dart';
import '../common.dart';
import '../deck_filters.dart';
import '../format.dart';
import '../icons.dart';
import '../online_gate.dart';
import '../swipe_card.dart';
import '../theme.dart';
import '../together_widgets.dart';
import '../widgets.dart';
import 'deck_results_screen.dart';

typedef _View = ({List<DeckCard> pool, List<DeckCard> remaining, int done});

enum _Menu { rebuild }

/// The group deck: swipe right to want a film, left to skip it, up if you have
/// seen it. A local group passes the phone from member to member; a shared group
/// swipes as yourself (the owner may swipe for guests).
class DeckScreen extends ConsumerStatefulWidget {
  const DeckScreen({super.key, required this.crewId, this.random});
  final String crewId;

  /// For the Tonight pick. Tests give a seeded one.
  final Random? random;

  @override
  ConsumerState<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends ConsumerState<DeckScreen> {
  /// Kept in a field: `ref` cannot be read in dispose.
  late final CrewController _ctl;
  final _keys = <String, GlobalKey<SwipeCardState>>{};
  final _q = TextEditingController();
  var _searching = false;
  var _hideSeen = true;
  var _filters = const DeckFilters();

  /// The member whose swipes these are. Null is the person who holds the phone.
  String? _swiper;

  /// The member the phone is being handed to. While set, a velvet screen covers the deck.
  String? _handTo;

  /// Swipes of this visit, for Undo.
  final _history = <({String member, String film})>[];

  /// Films Undo brought back for the swiper, the latest first. The earlier vote stays until the film is swiped again.
  // ponytail: a vote cannot be taken back, only replaced; a closed deck keeps the undone vote
  final _reopened = <String>[];
  var _building = true;
  Refusal? _failed;
  String? _note;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _ctl = ref.read(crewProvider(widget.crewId).notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  @override
  void dispose() {
    // Swipes of a shared group wait a moment to be sent together: send them as the deck closes.
    flushSwipesSoon(_ctl);
    _q.dispose();
    super.dispose();
  }

  CrewState get _st => ref.read(crewProvider(widget.crewId));

  Future<void> _ensure({bool rebuild = false}) async {
    if (!mounted) return;
    setState(() {
      _building = true;
      _failed = null;
    });
    // A shared group reads its deck and my votes first: someone else may have built the deck already.
    if (_st.crew.shared) await _ctl.refresh();
    final r = rebuild ? await _ctl.rebuildDeck() : await _ctl.ensureDeck();
    if (!mounted) return;
    setState(() {
      _building = false;
      _failed = r.refusal;
    });
  }

  /// Members the phone may swipe for: everyone in a local group; in a shared group me, and for the owner the guests.
  List<Member> _swipers(Crew crew) => crew.shared
      ? [if (crew.me != null) crew.me!, if (crew.isOwner) ...crew.members.where((m) => m.guest)]
      : crew.members;

  String? _current(Crew crew, List<Member> swipers) {
    if (_swiper != null && swipers.any((m) => m.id == _swiper)) return _swiper;
    return crew.me?.id ?? swipers.firstOrNull?.id;
  }

  _View _view(CrewState st, String swiper) {
    final crew = st.crew;
    final votes = crew.votes[swiper] ?? const <String, Vote>{};
    bool voted(DeckCard c) => votes.containsKey(c.id) && !_reopened.contains(c.id);
    final q = norm(_q.text);
    bool shown(DeckCard c) =>
        _filters.matches(c.film) &&
        (q.isEmpty || norm(c.film.title).contains(q) || norm(c.film.original ?? '').contains(q));
    final cards = crew.deck?.cards ?? const <DeckCard>[];
    // A card the swiper already voted on stays in the count, so "12 of 48" does not shrink as they swipe "seen".
    final pool = [
      for (final c in cards)
        if (shown(c) && (voted(c) || _reopened.contains(c.id) || !_hideSeen || st.seenBy(c) == 0)) c,
    ];
    final back = [for (final id in _reopened) ?pool.where((c) => c.id == id).firstOrNull];
    final rest = [
      for (final c in pool)
        if (!voted(c) && !_reopened.contains(c.id)) c,
    ];
    return (pool: pool, remaining: [...back, ...rest], done: pool.where(voted).length);
  }

  Future<void> _vote(Vote v, DeckCard card, String swiper) async {
    _reopened.remove(card.id);
    _history.add((member: swiper, film: card.id));
    final r = await _ctl.swipe(swiper, card.id, v);
    if (!mounted) return;
    if (r.ok) {
      _keys.remove(card.id);
      if (_note != null) setState(() => _note = null);
      return;
    }
    // The group said no (a guest the phone may not swipe for): the card comes back.
    _history.removeLast();
    setState(() => _note = refusalText(context, r.refusal!));
    _keys[card.id]?.currentState?.springBack();
  }

  void _undo(String swiper) {
    final i = _history.lastIndexWhere((h) => h.member == swiper);
    if (i < 0) return;
    final h = _history.removeAt(i);
    setState(() => _reopened.insert(0, h.film));
  }

  Future<void> _confirmHand(Member m) async {
    // A guest's earlier votes in a shared group live on the server.
    if (_st.crew.shared && !m.me) await _ctl.loadVotes(m.id);
    if (!mounted) return;
    setState(() {
      _swiper = m.id;
      _handTo = null;
      _note = null;
    });
  }

  /// "Done, pass it on": the next member who has cards left. When nobody has, the results.
  void _passOn(CrewState st, List<Member> swipers, String current) {
    final i = swipers.indexWhere((m) => m.id == current);
    for (var k = 1; k < swipers.length; k++) {
      final m = swipers[(i + k) % swipers.length];
      if (st.unswiped(m.id).isNotEmpty) {
        setState(() => _handTo = m.id);
        return;
      }
    }
    _results();
  }

  void _results() => push(context, DeckResultsScreen(crewId: widget.crewId, random: widget.random));

  void _openFilters(List<DeckCard> cards) => showDeckFilters(
    context,
    films: [for (final c in cards) c.film],
    filters: _filters,
    hideSeen: _hideSeen,
    onFilters: (f) {
      // A new pool can pull the dragged card out from under the finger: let it go home first.
      for (final k in _keys.values) {
        k.currentState?.springBack();
      }
      setState(() => _filters = f);
    },
    onHideSeen: (v) {
      for (final k in _keys.values) {
        k.currentState?.springBack();
      }
      setState(() => _hideSeen = v);
    },
  );

  void _clearFilters() => setState(() {
    _filters = const DeckFilters();
    _q.clear();
  });

  KeyEventResult _key(KeyEvent e, DeckCard? top) {
    if (e is! KeyDownEvent || top == null) return KeyEventResult.ignored;
    // Arrow keys belong to the search field while someone types in it. The
    // focused context is the inner Focus widget EditableText builds, never the
    // EditableText itself, so look for its state up the tree instead.
    if (FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }
    final vote = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowRight => Vote.want,
      LogicalKeyboardKey.arrowLeft => Vote.skip,
      LogicalKeyboardKey.arrowUp => Vote.seen,
      _ => null,
    };
    if (vote == null) return KeyEventResult.ignored;
    _keys[top.id]?.currentState?.swipe(vote);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(crewProvider(widget.crewId));
    final crew = st.crew;
    final p = Palette.of(context);
    final l = context.l;
    if (st.gone) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const Scaffold();
    }
    final swipers = _swipers(crew);
    final current = _current(crew, swipers);
    final swiper = current == null ? null : crew.member(current);

    final to = _handTo == null ? null : crew.member(_handTo!);
    if (to != null) {
      return _Handoff(member: to, onCancel: () => setState(() => _handTo = null), onConfirm: () => _confirmHand(to));
    }

    final cards = crew.deck?.cards ?? const <DeckCard>[];
    final view = swiper == null ? null : _view(st, swiper.id);
    final top = view?.remaining.firstOrNull;
    final unreachable = crew.shared && st.offline;

    Widget stage;
    if (_building || (crew.shared && st.loading && cards.isEmpty) || swiper == null || view == null) {
      stage = _Working(text: l.deckBuilding);
    } else if (unreachable) {
      stage = CantReach(onRetry: () => _ensure());
    } else if (_failed != null) {
      stage = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          EmptyNote(refusalText(context, _failed!), action: l.deckRebuild, onAction: () => _ensure(rebuild: true)),
        ],
      );
    } else if (cards.isEmpty) {
      stage = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [EmptyNote(l.deckEmpty, action: l.deckRebuild, onAction: () => _ensure(rebuild: true))],
      );
    } else if (view.pool.isEmpty) {
      stage = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [EmptyNote(l.deckNoMatch, action: l.resetFilters, onAction: _clearFilters)],
      );
    } else if (view.remaining.isEmpty) {
      stage = _EndPanel(
        canUndo: _history.any((h) => h.member == swiper.id),
        onUndo: () => _undo(swiper.id),
        onResults: _results,
        onPass: swipers.length > 1 ? () => _passOn(st, swipers, swiper.id) : null,
      );
    } else {
      final card = view.remaining.first;
      final next = view.remaining.length > 1 ? view.remaining[1] : null;
      final key = _keys.putIfAbsent(card.id, GlobalKey.new);
      stage = _Cards(
        counter: l.deckCounter(view.done + 1, view.pool.length),
        canUndo: _history.any((h) => h.member == swiper.id),
        onUndo: () => _undo(swiper.id),
        showSeen: !_hideSeen,
        top: card,
        next: next,
        seenBy: st.seenBy,
        cardKey: key,
        onSwiped: (v) => _vote(v, card, swiper.id),
        onVote: (v) => key.currentState?.swipe(v),
        onPass: swipers.length > 1 ? () => _passOn(st, swipers, swiper.id) : null,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: Text(
          crew.name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: disp(22, p.ink, spacing: 0.6),
        ),
        actions: [
          TkButton(
            Tk.search,
            tooltip: l.search,
            color: _searching ? p.accent : null,
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _q.clear();
            }),
          ),
          TkButton(
            Tk.filter,
            tooltip: l.deckFilters,
            color: _filters.active || !_hideSeen ? p.accent : null,
            onPressed: cards.isEmpty ? null : () => _openFilters(cards),
          ),
          TkButton(Tk.list, tooltip: l.deckResults, onPressed: _results),
          PopupMenuButton<_Menu>(
            key: const Key('deck-menu'),
            tooltip: l.togetherMore,
            icon: const TkIcon(Tk.more),
            onSelected: (_) => _ensure(rebuild: true),
            itemBuilder: (_) => [PopupMenuItem(value: _Menu.rebuild, child: Text(l.deckRebuild))],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) => _key(e, top),
        child: Column(
          children: [
            if (swipers.length > 1 && swiper != null)
              _SwiperBar(
                members: swipers,
                current: swiper.id,
                onPick: (m) {
                  if (m.id != swiper.id) setState(() => _handTo = m.id);
                },
              ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  key: const Key('deck-search'),
                  controller: _q,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l.deckSearchHint,
                    isDense: true,
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : TkButton(Tk.close, tooltip: l.clear, size: 18, onPressed: () => setState(_q.clear)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (_note != null)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Note(_note!, strong: true)),
            Expanded(child: stage),
          ],
        ),
      ),
    );
  }
}

/// "Building the deck": a quiet progress mark and a line of words.
class _Working extends StatelessWidget {
  const _Working({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(text, style: TextStyle(color: p.inkSoft)),
        ],
      ),
    );
  }
}

/// Who is swiping now. Picking another member hands the phone over.
class _SwiperBar extends StatelessWidget {
  const _SwiperBar({required this.members, required this.current, required this.onPick});
  final List<Member> members;
  final String current;
  final ValueChanged<Member> onPick;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: context.l.deckWho,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: Row(
          children: [
            for (final m in members)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TapBox(
                  key: ValueKey('swiper-${m.id}'),
                  label: memberName(context, m),
                  selected: m.id == current,
                  onTap: () => onPick(m),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The card, the next card behind it, and the three buttons that do what a swipe does.
class _Cards extends StatelessWidget {
  const _Cards({
    required this.counter,
    required this.canUndo,
    required this.onUndo,
    required this.showSeen,
    required this.top,
    required this.next,
    required this.seenBy,
    required this.cardKey,
    required this.onSwiped,
    required this.onVote,
    required this.onPass,
  });
  final String counter;
  final bool canUndo, showSeen;
  final VoidCallback onUndo;
  final DeckCard top;
  final DeckCard? next;
  final int Function(DeckCard) seenBy;
  final GlobalKey<SwipeCardState> cardKey;
  final ValueChanged<Vote> onSwiped, onVote;

  /// Null when only one member swipes.
  final VoidCallback? onPass;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final counterRow = Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 8, 0),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Semantics(liveRegion: true, child: Text(counter, style: disp(20, p.ink, spacing: 1))),
            ),
            TextButton.icon(
              key: const Key('deck-undo'),
              onPressed: canUndo ? onUndo : null,
              icon: TkIcon(Tk.again, size: 18, color: canUndo ? p.ink : p.inkSoft.withValues(alpha: 0.5)),
              label: Text(
                l.undo,
                style: TextStyle(
                  color: canUndo ? p.ink : p.inkSoft.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: _VoteButton(
              key: const Key('vote-skip'),
              vote: Vote.skip,
              icon: Tk.left,
              onTap: () => onVote(Vote.skip),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _VoteButton(
              key: const Key('vote-seen'),
              vote: Vote.seen,
              icon: Tk.up,
              onTap: () => onVote(Vote.seen),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _VoteButton(
              key: const Key('vote-want'),
              vote: Vote.want,
              icon: Tk.right,
              onTap: () => onVote(Vote.want),
            ),
          ),
        ],
      ),
    );
    final pass = onPass == null
        ? null
        : SizedBox(
            height: 48,
            child: TextButton(
              key: const Key('deck-pass'),
              onPressed: onPass,
              child: Text(
                l.deckDonePass,
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          );
    Widget face(DeckCard c) => DeckFace(card: c, showSeen: showSeen, seenBy: seenBy(c));
    final stack = Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The next card waits behind, so a card dragged aside shows it instead of an empty wall.
          if (next != null)
            ExcludeSemantics(
              child: IgnorePointer(child: Transform.scale(scale: 0.96, child: face(next!))),
            ),
          SwipeCard(
            key: cardKey,
            label: [top.film.title, if (top.film.year != null) '${top.film.year}'].join(', '),
            onSwiped: onSwiped,
            child: face(top),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        // The card needs room for its poster and text. On a short window the page scrolls, and the buttons still work.
        final minCard = textHeight(context, 250, 170);
        final fixed = 46 + 80 + (pass == null ? 0 : 48);
        if (box.maxHeight - fixed >= minCard) {
          return Column(
            children: [
              counterRow,
              Expanded(child: stack),
              controls,
              ?pass,
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            children: [
              counterRow,
              SizedBox(height: minCard, child: stack),
              controls,
              ?pass,
            ],
          ),
        );
      },
    );
  }
}

/// Skip, Seen and Want as buttons: the same three votes as the swipe.
class _VoteButton extends StatelessWidget {
  const _VoteButton({super.key, required this.vote, required this.icon, required this.onTap});
  final Vote vote;
  final Tk icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final want = vote == Vote.want;
    final bg = want ? p.accent : p.velvet;
    final fg = want ? p.onAccent : p.onVelvet;
    final word = voteWord(context, vote);
    return Semantics(
      button: true,
      label: word,
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: want ? BorderSide.none : BorderSide(color: p.onVelvet.withValues(alpha: 0.22)),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TkIcon(icon, size: 24, color: fg),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(word.toUpperCase(), style: disp(15, fg, spacing: 0.8)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every card has been swiped: the way on is the results, or the next person.
class _EndPanel extends StatelessWidget {
  const _EndPanel({required this.canUndo, required this.onUndo, required this.onResults, required this.onPass});
  final bool canUndo;
  final VoidCallback onUndo, onResults;
  final VoidCallback? onPass;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.deckAllSwiped.toUpperCase(), textAlign: TextAlign.center, style: disp(32, p.ink, height: 1.05)),
            const SizedBox(height: 22),
            SlabButton(key: const Key('deck-results'), label: l.deckResults, icon: Tk.list, onPressed: onResults),
            if (onPass != null) ...[
              const SizedBox(height: 10),
              SlabButton(
                key: const Key('deck-pass'),
                label: l.deckDonePass,
                icon: Tk.right,
                tone: SlabTone.velvet,
                onPressed: onPass,
              ),
            ],
            if (canUndo)
              TextButton(
                key: const Key('deck-undo'),
                onPressed: onUndo,
                child: Text(
                  l.undo,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The phone changes hands. The velvet screen hides the deck, so the next person
/// cannot see the last one's picks. Nothing is shown until they say who they are.
class _Handoff extends StatelessWidget {
  const _Handoff({required this.member, required this.onCancel, required this.onConfirm});
  final Member member;
  final VoidCallback onCancel, onConfirm;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final name = memberName(context, member);
    // The phone holder gets it back with "I'm back"; the rest are named.
    final back = member.me;
    final soft = p.onVelvet.withValues(alpha: 0.82);
    return Scaffold(
      backgroundColor: p.velvet,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: const Offset(-12, 0),
                  child: TkButton(Tk.back, tooltip: l.back, color: p.onVelvet, onPressed: onCancel),
                ),
              ),
              const Spacer(),
              Semantics(
                header: true,
                label: back ? l.deckHandBack : l.deckHandTitle(name),
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (back ? l.deckHandBack : l.deckHandTo).toUpperCase(),
                      style: disp(22, soft, spacing: 2, height: 1.1),
                    ),
                    if (!back) ...[
                      const SizedBox(height: 8),
                      Text(
                        name.toUpperCase(),
                        key: const Key('handoff-name'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: disp(72, p.onVelvet, spacing: 1, height: 0.98),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(l.deckHandNote, style: TextStyle(color: soft, fontSize: 15, height: 1.4)),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: SlabButton(
                  key: const Key('handoff-confirm'),
                  label: back ? l.deckImBack : l.deckImName(name),
                  tone: SlabTone.paper,
                  onPressed: onConfirm,
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
