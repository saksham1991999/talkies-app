import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../data/crews.dart' show DeckCard, Vote;
import '../data/models.dart';
import '../l10n/labels.dart';
import 'common.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

// The swipe card of the group deck: a poster on ticket paper that follows the
// finger. Right wants the film, left skips it, up says it was seen.

/// A card commits when it is dragged this fraction of its width sideways, this
/// many dp up, or flung faster than [swipeFlingSpeed] (dp per second) along its
/// main direction.
const swipeCommitWidth = 0.28;
const swipeCommitUp = 120.0;
const swipeFlingSpeed = 700.0;

/// The vote a drag of [offset] on a card [width] wide leans towards, and how far
/// along it is (1 commits). Null while the card has not moved.
({Vote vote, double progress})? swipeLean(Offset offset, double width) {
  final side = offset.dx.abs() / (width * swipeCommitWidth);
  final up = offset.dy < 0 ? -offset.dy / swipeCommitUp : 0.0;
  if (side == 0 && up == 0) return null;
  if (up > side) return (vote: Vote.seen, progress: up);
  return (vote: offset.dx > 0 ? Vote.want : Vote.skip, progress: side);
}

/// What lifting the finger does: the vote it commits, or null to spring back. A
/// fling over [swipeFlingSpeed] decides by its main direction (a fling down
/// decides nothing). Otherwise the card must have reached its distance.
Vote? swipeCommit(Offset offset, Offset velocity, double width) {
  final (vx, vy) = (velocity.dx, velocity.dy);
  if (vx.abs() > vy.abs()) {
    if (vx.abs() > swipeFlingSpeed) return vx > 0 ? Vote.want : Vote.skip;
  } else if (-vy > swipeFlingSpeed) {
    return Vote.seen;
  }
  final lean = swipeLean(offset, width);
  return lean != null && lean.progress >= 1 ? lean.vote : null;
}

/// The stamp ink of each vote: the app's own inks, paan, sindoor and neel.
Color voteInk(Vote v) => switch (v) {
  Vote.want => accents[8].color,
  Vote.skip => accents[0].color,
  Vote.seen => accents[4].color,
};

String voteWord(BuildContext c, Vote v) => switch (v) {
  Vote.want => c.l.deckWant,
  Vote.skip => c.l.deckSkip,
  Vote.seen => c.l.deckSeen,
};

/// Wraps a card face so it can be dragged. [onSwiped] runs when the card has left.
/// The buttons, the arrow keys and the screen reader actions call [SwipeCardState.swipe].
/// Under reduced motion the card does not tilt and does not fly off.
class SwipeCard extends StatefulWidget {
  const SwipeCard({super.key, required this.child, required this.onSwiped, required this.label});
  final Widget child;
  final ValueChanged<Vote> onSwiped;

  /// What a screen reader says for the card.
  final String label;

  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard> with SingleTickerProviderStateMixin {
  // One unbounded controller moves the card from [_from] to [_to] for both the spring back and the fly-off.
  // The finger itself writes [_drag]; the builder listens to both and reads whichever is moving.
  late final AnimationController _anim = AnimationController.unbounded(vsync: this);
  final _drag = ValueNotifier<Offset>(Offset.zero);
  var _from = Offset.zero;
  var _to = Offset.zero;
  var _armed = false;

  /// The card's width, read from its own box when a gesture needs it. Never set
  /// during build: the box may not have been laid out yet.
  double get _width {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? math.max(1.0, box.size.width) : 300.0;
  }

  /// Where the card sits now: between [_from] and [_to] while the controller runs, otherwise the finger's place.
  Offset get _offset => _anim.isAnimating ? Offset.lerp(_from, _to, _anim.value)! : _drag.value;

  /// The vote that is leaving. The card takes no more drags until [springBack].
  Vote? _leaving;

  /// Hidden at once: reduced motion has no fly-off, so a card that voted just goes.
  var _gone = false;

  @visibleForTesting
  Offset get offset => _offset;

  @override
  void dispose() {
    _anim.dispose();
    _drag.dispose();
    super.dispose();
  }

  /// Freezes a running controller into [_drag], so a new drag or spring starts where the card is.
  void _settle() {
    if (_anim.isAnimating) _drag.value = Offset.lerp(_from, _to, _anim.value)!;
    _anim.stop();
  }

  void _start(DragStartDetails d) {
    if (_leaving != null) return;
    _settle();
    _armed = false;
  }

  void _update(DragUpdateDetails d) {
    if (_leaving != null) return;
    _drag.value += d.delta;
    final lean = swipeLean(_offset, _width);
    final armed = lean != null && lean.progress >= 1;
    if (armed && !_armed) HapticFeedback.selectionClick();
    _armed = armed;
  }

  void _end(DragEndDetails d) {
    if (_leaving != null) return;
    final vote = swipeCommit(_offset, d.velocity.pixelsPerSecond, _width);
    vote == null ? springBack() : _commit(vote);
  }

  /// Sends the card away with [vote], as if it had been dragged there.
  void swipe(Vote vote) => _commit(vote);

  void _commit(Vote vote) {
    if (_leaving != null) return;
    HapticFeedback.lightImpact();
    _leaving = vote;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _gone = true);
      widget.onSwiped(vote);
      return;
    }
    final far = _width * 1.6;
    final high = MediaQuery.sizeOf(context).height;
    _from = _drag.value;
    _to = switch (vote) {
      Vote.want => Offset(far, _from.dy),
      Vote.skip => Offset(-far, _from.dy),
      Vote.seen => Offset(_from.dx, -high),
    };
    _anim.value = 0;
    _anim.animateTo(1, duration: const Duration(milliseconds: 240), curve: Curves.easeIn).whenComplete(() {
      if (mounted) widget.onSwiped(vote);
    });
  }

  /// Brings the card back to the middle: after a short drag, and after a vote the
  /// group refused. Under reduced motion it jumps.
  void springBack() {
    _leaving = null;
    _armed = false;
    _settle();
    if (_gone) setState(() => _gone = false);
    if (_drag.value == Offset.zero) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _drag.value = Offset.zero;
      return;
    }
    _from = _drag.value;
    _to = Offset.zero;
    _anim.value = 0;
    _anim
        .animateWith(
          SpringSimulation(SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 0.72), 0, 1, 0),
        )
        // The spring stops within a pixel of the middle: land exactly. A new drag stops it first and skips this.
        .whenComplete(() {
          if (mounted) _drag.value = Offset.zero;
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final l = context.l;
    // The face is captured here and handed to the builder below: the drag and the
    // fly-off only move it and fade the stamps in, they never rebuild it.
    final face = ExcludeSemantics(child: widget.child);
    return Semantics(
      label: widget.label,
      hint: l.deckSwipeHint,
      customSemanticsActions: {
        CustomSemanticsAction(label: l.deckWant): () => swipe(Vote.want),
        CustomSemanticsAction(label: l.deckSkip): () => swipe(Vote.skip),
        CustomSemanticsAction(label: l.deckSeen): () => swipe(Vote.seen),
      },
      child: GestureDetector(
        onPanStart: _start,
        onPanUpdate: _update,
        onPanEnd: _end,
        onPanCancel: springBack,
        child: AnimatedBuilder(
          animation: Listenable.merge([_anim, _drag]),
          child: face,
          builder: (context, face) {
            final offset = _offset;
            final reduce = MediaQuery.disableAnimationsOf(context);
            final lean = swipeLean(offset, _width);
            double shown(Vote v) => lean != null && lean.vote == v ? lean.progress.clamp(0.0, 1.0) : 0.0;
            final tilt = reduce ? 0.0 : (offset.dx / _width * 0.35).clamp(-0.5, 0.5);
            return Transform.translate(
              offset: offset,
              child: Transform.rotate(
                angle: tilt,
                alignment: Alignment.bottomCenter,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The card's own label above says what it is; its parts would be read twice.
                    face!,
                    // The stamps come in with the drag. They are marks on the card, not controls. They land on
                    // the paper under the poster: ink shows on paper, and not on a dark poster.
                    for (final (v, align) in [
                      (Vote.want, Alignment.bottomLeft),
                      (Vote.skip, Alignment.bottomRight),
                      (Vote.seen, Alignment.bottomCenter),
                    ])
                      Align(
                        alignment: align,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Opacity(
                                opacity: shown(v),
                                child: Stamp(
                                  word: voteWord(context, v).toUpperCase(),
                                  color: voteInk(v),
                                  size: 96,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The face of a deck card: the poster on ticket paper, a perforation, and under it the title, year,
/// language and genres. [seenBy] shows "seen by N" when it is above zero.
class DeckFace extends StatelessWidget {
  const DeckFace({super.key, required this.card, this.showSeen = false, this.seenBy = 0});
  final DeckCard card;

  /// Whether to say how many members have seen the film.
  final bool showSeen;
  final int seenBy;

  static const _pad = 14.0;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final film = card.film;
    final paper = p.paper(VenueType.values[film.id.hashCode.abs() % VenueType.values.length]);
    final meta = [
      if (film.mainLang != null) langName(context, film.mainLang!),
      if (film.series) l.kindSeries,
    ].join('  ·  ');
    final genres = film.genres.take(3).map((g) => genreName(context, g)).join('  ·  ');
    return LayoutBuilder(
      builder: (context, box) {
        // Room under the perforation for two title lines, the year, the genres and "seen by".
        final text = textHeight(context, 108, 150);
        final posterH = math.max(60.0, box.maxHeight - _pad - _gap - _pad - text);
        final posterW = math.min(box.maxWidth - 2 * _pad, posterH / 1.5);
        return TicketPaper(
          color: paper,
          shape: TicketBorder(radius: 8, notch: 9, notchY: _pad + posterH + _gap / 2 + 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_pad, _pad, _pad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Poster(film, width: posterW, radius: 3)),
                const SizedBox(height: _gap + 8),
                Text(
                  film.title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: disp(24, paperInk, spacing: 0.5, height: 1.0),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  TextSpan(
                    children: [
                      if (film.year != null) TextSpan(text: '${film.year}', style: disp(18, serialRed, spacing: 0.8)),
                      if (film.year != null && meta.isNotEmpty) const TextSpan(text: '   '),
                      TextSpan(
                        text: meta,
                        style: const TextStyle(fontSize: 13.5, color: paperInk, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (genres.isNotEmpty)
                  Text(
                    genres,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: paperInkSoft, fontWeight: FontWeight.w500),
                  ),
                if (showSeen && seenBy > 0)
                  Text(
                    l.deckSeenBy(seenBy),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: paperInk, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
