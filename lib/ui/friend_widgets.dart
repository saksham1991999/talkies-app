import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/social.dart';
import '../state/providers.dart';
import '../state/social.dart';
import 'avatar.dart';
import 'common.dart';
import 'format.dart';
import 'icons.dart';
import 'online_parts.dart';
import 'screens/friend_screen.dart';
import 'theme.dart';
import 'widgets.dart';

// The pieces of the Friends segment: a friend, a request, a feed item and its reactions.

/// A friend: stamp, name, "You both watched 12" and the taste match as a figure. Opens the friend's profile.
class FriendRow extends StatelessWidget {
  const FriendRow(this.item, {super.key});
  final FriendItem item;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final m = item.match;
    final pct = m?.pct;
    return PersonRow(
      card: item.card,
      subtitle: !item.visible
          ? l.friendsKeepsPrivate
          : m != null && m.both > 0
          ? l.friendsBoth(m.both)
          : l.friendsNoCommon,
      trailing: pct == null || !item.visible
          ? null
          : Semantics(
              label: l.friendsMatchLabel(pct),
              excludeSemantics: true,
              child: Text('$pct%', style: disp(30, figureColor(Palette.of(context)), spacing: 0.6)),
            ),
      onTap: () => push(context, FriendScreen(card: item.card, visible: item.visible)),
    );
  }
}

/// A request that came in: Accept or Decline.
class IncomingRequest extends ConsumerStatefulWidget {
  const IncomingRequest(this.card, {super.key});
  final UserCard card;

  @override
  ConsumerState<IncomingRequest> createState() => _IncomingRequestState();
}

class _IncomingRequestState extends ConsumerState<IncomingRequest> {
  var _busy = false;

  Future<void> _answer(Future<CallResult<void>> Function(FriendsController c) call) async {
    final l = context.l;
    setState(() => _busy = true);
    final r = await call(ref.read(friendsProvider.notifier));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) say(context, problemText(l, r.outcome));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final id = widget.card.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PersonRow(card: widget.card, subtitle: l.friendsWantsToBe),
        // Under the name, so the buttons never squeeze it.
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 20, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkButton(
                key: Key('accept-$id'),
                label: l.friendsAccept,
                onPressed: _busy ? null : () => _answer((c) => c.accept(id)),
              ),
              TextButton(
                style: linkStyle(context),
                key: Key('decline-$id'),
                onPressed: _busy ? null : () => _answer((c) => c.decline(id)),
                child: Text(l.friendsDecline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A request you sent: it waits, and you can take it back.
class OutgoingRequest extends ConsumerStatefulWidget {
  const OutgoingRequest(this.card, {super.key});
  final UserCard card;

  @override
  ConsumerState<OutgoingRequest> createState() => _OutgoingRequestState();
}

class _OutgoingRequestState extends ConsumerState<OutgoingRequest> {
  var _busy = false;

  Future<void> _cancel() async {
    final l = context.l;
    setState(() => _busy = true);
    final r = await ref.read(friendsProvider.notifier).decline(widget.card.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) say(context, problemText(l, r.outcome));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PersonRow(card: widget.card, subtitle: l.friendsWaiting),
        Padding(
          padding: const EdgeInsets.fromLTRB(60, 0, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: linkStyle(context),
              key: Key('cancel-${widget.card.id}'),
              onPressed: _busy ? null : _cancel,
              child: Text(l.friendsCancelRequest),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The feed

/// One thing a friend did: they watched a film, reacted to yours, or sent you one. Poster, title, the note of a
/// sent film, a one-tap "Want to watch", and for a watched film the eight reactions. There is no date; the
/// order is the recency.
class FeedTile extends ConsumerWidget {
  const FeedTile(this.item, {super.key});
  final FeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final film = safe(() => item.film);
    if (film == null) return const SizedBox.shrink();
    final l = context.l;
    final p = Palette.of(context);
    final name = nameOf(l, item.user);
    final showRatings = ref.watch(settingsProvider.select((s) => s.showRatings));
    final wished = ref.watch(diaryProvider.select((d) => d.wishFor(item.filmId) != null));
    final verb = switch (item.kind) {
      FeedKind.watched => l.feedWatched(name),
      FeedKind.reaction => l.feedReacted(name),
      FeedKind.sent => l.feedSent(name),
    };
    final reaction = item.reaction;
    final emoji = item.kind == FeedKind.reaction && reaction != null && reaction >= 0 && reaction < reactionCount
        ? reactionEmoji[reaction]
        : null;
    final meta = [if (film.year != null) '${film.year}', ...film.directors.take(1)].join('  ·  ');
    final rating = item.rating;

    Future<void> react(int? r) async {
      final res = await ref.read(feedProvider.notifier).react(item, r);
      if (!res.ok && context.mounted) {
        say(context, res.outcome == CallOutcome.offline ? l.gateCantReach : l.feedReactFailed);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => push(context, FriendScreen(card: item.user)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Avatar(name: name, ink: item.user.avatarColor, size: 36),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      verb,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.ink),
                    ),
                  ),
                  if (emoji != null) ...[
                    const SizedBox(width: 8),
                    Semantics(
                      label: reactionName(l, reaction!),
                      excludeSemantics: true,
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => openFilm(context, film),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Poster(film, width: 64, radius: 3),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        film.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2, color: p.ink),
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: p.inkSoft, height: 1.3),
                        ),
                      if (showRatings && rating != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Stars(rating, size: 13, color: figureColor(p), empty: p.inkSoft),
                              const SizedBox(width: 6),
                              Text(fmtRating(rating), style: disp(18, figureColor(p), spacing: 0.4)),
                            ],
                          ),
                        ),
                      if (item.note != null && item.note!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: p.paper(VenueType.ott),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              item.note!.trim(),
                              style: const TextStyle(fontSize: 13.5, height: 1.35, color: paperInk),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            key: Key('want-${item.id}'),
            onPressed: wished
                ? null
                : () {
                    if (ref.read(feedProvider.notifier).addToWatchlist(item)) say(context, l.addedToWatchlist);
                  },
            icon: TkIcon(wished ? Tk.bookmarked : Tk.bookmark, size: 20, color: wished ? p.accent : p.ink),
            label: Text(
              wished ? l.inWatchlist : l.wantToWatch,
              style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
            ),
          ),
          if (item.kind == FeedKind.watched) ReactionGrid(mine: item.myReaction, onPick: react),
        ],
      ),
    );
  }
}

/// The eight reactions in a grid of four columns (one row of eight on a wide screen). Mine is a slab of ink;
/// tapping it again takes it back. Each is a 44 high target.
class ReactionGrid extends StatelessWidget {
  const ReactionGrid({super.key, required this.mine, required this.onPick});
  final int? mine;
  final void Function(int? reaction) onPick;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= reactionCount * 52 ? reactionCount : 4;
        return Column(
          children: [
            for (var row = 0; row < reactionCount; row += cols)
              Row(
                children: [
                  for (var i = row; i < row + cols; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: mine == i,
                        label: reactionName(l, i),
                        child: InkWell(
                          key: Key('react-$i'),
                          borderRadius: BorderRadius.circular(3),
                          onTap: () => onPick(mine == i ? null : i),
                          child: SizedBox(
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 44,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: mine == i ? p.ink : Colors.transparent,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: ExcludeSemantics(
                                  child: Text(reactionEmoji[i], style: const TextStyle(fontSize: 22)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
