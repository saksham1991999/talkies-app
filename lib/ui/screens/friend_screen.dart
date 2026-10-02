import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/social.dart';
import '../../state/online.dart';
import '../../state/providers.dart';
import '../../state/social.dart';
import '../avatar.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../online_gate.dart';
import '../online_parts.dart';
import '../profile_body.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Act { unfriend, block, report }

/// A friend's profile: the stats ticket, top films and watchlist, then the films they watched, with a menu to
/// remove, block or report them. [visible] false (from the friends list) means they keep their films private:
/// the screen says so and asks the server for nothing. A friend whose profile the server will not show gets the
/// same quiet line.
class FriendScreen extends ConsumerStatefulWidget {
  const FriendScreen({super.key, required this.card, this.visible = true});
  final UserCard card;
  final bool visible;

  @override
  ConsumerState<FriendScreen> createState() => _FriendScreenState();
}

class _FriendScreenState extends ConsumerState<FriendScreen> {
  String get _id => widget.card.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    if (!mounted || !widget.visible || !ref.read(onlineProvider)) return;
    ref.read(profileProvider(_id).notifier).load();
    ref.read(shelfProvider(_id).notifier).load();
  }

  Future<void> _retry() async {
    await ref.read(backendProvider.notifier).probe(force: true);
    _load();
  }

  Future<void> _act(_Act a) async {
    final l = context.l;
    final name = nameOf(l, widget.card);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void tell(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    switch (a) {
      case _Act.unfriend:
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(l.friendsUnfriendQ(name)),
            content: Text(l.friendsUnfriendBody),
            actions: [
              TextButton(style: linkStyle(context), onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
              TextButton(
                style: linkStyle(context),
                key: const Key('confirm-unfriend'),
                onPressed: () => Navigator.pop(c, true),
                child: Text(l.friendsUnfriend),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        final r = await ref.read(friendsProvider.notifier).remove(_id);
        if (!mounted) return;
        if (r.ok) {
          nav.pop();
          tell(l.friendsUnfriended(name));
        } else {
          tell(problemText(l, r.outcome));
        }
      case _Act.block:
        if (!await confirmBlock(context, name) || !mounted) return;
        final r = await ref.read(blocksProvider.notifier).block(_id);
        if (!mounted) return;
        if (r.ok) {
          nav.pop();
          tell(l.friendsBlocked(name));
        } else {
          tell(problemText(l, r.outcome));
        }
      case _Act.report:
        final reason = await pickReportReason(context, title: l.friendsReportTitle(name));
        if (reason == null || !mounted) return;
        final r = await ref
            .read(reportProvider.notifier)
            .submit(ReportPost(kind: ReportKind.user, targetId: _id, reason: reason));
        if (!mounted) return;
        tell(r.ok ? l.friendsReported : problemText(l, r.outcome));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final online = ref.watch(onlineProvider);
    final showRatings = ref.watch(settingsProvider.select((s) => s.showRatings));
    final profile = ref.watch(profileProvider(_id));
    final shelf = ref.watch(shelfProvider(_id));
    final name = nameOf(l, widget.card);
    final view = profile.value;
    final match = view?.match;
    final ready = profile.status == Fetch.ready && view != null;

    // The body under the header: what there is to show, or one quiet line.
    final List<Widget> body;
    if (!widget.visible) {
      body = [_Quiet(l.friendsPrivateLine(name))];
    } else if (!online || profile.status == Fetch.offline) {
      body = [CantReach(onRetry: _retry)];
    } else if (ready) {
      final hasFilms = (view.stats?.viewings ?? 0) > 0 || view.watchlist.isNotEmpty;
      body = hasFilms ? [ProfileBody(view: view, ratings: showRatings)] : [_Quiet(l.profileEmptyFriend(name))];
    } else if (profile.status == Fetch.failed) {
      body = [
        _Quiet(l.friendsHidden(name)),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextButton(style: linkStyle(context), onPressed: _load, child: Text(l.gateRetry)),
          ),
        ),
      ];
    } else {
      body = [const LoadingBlock()];
    }

    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.maybePop(context)),
        title: Text(name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: disp(24, p.ink)),
        actions: [
          PopupMenuButton<_Act>(
            key: const Key('friend-menu'),
            tooltip: l.friendsMenu,
            icon: const TkIcon(Tk.more),
            onSelected: _act,
            itemBuilder: (_) => [
              PopupMenuItem(value: _Act.unfriend, child: Text(l.friendsUnfriend)),
              PopupMenuItem(value: _Act.block, child: Text(l.friendsBlock)),
              PopupMenuItem(value: _Act.report, child: Text(l.friendsReport)),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Avatar(name: name, ink: widget.card.avatarColor, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: disp(30, p.ink, spacing: 0.6)),
                        if (widget.card.handle != null)
                          Text(
                            '@${widget.card.handle}',
                            style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w600),
                          ),
                        if (match != null && match.both > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    l.friendsBoth(match.both),
                                    style: TextStyle(color: p.ink, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (match.pct != null) ...[
                                  const SizedBox(width: 10),
                                  Semantics(
                                    label: l.friendsMatchLabel(match.pct!),
                                    excludeSemantics: true,
                                    child: Text('${match.pct}%', style: disp(30, figureColor(p), spacing: 0.6)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(delegate: SliverChildListDelegate(body)),
          if (widget.visible && ready && shelf.items.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionTitle(l.friendsShelf)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              sliver: SliverLayoutBuilder(
                builder: (context, c) {
                  const gap = 12.0;
                  final w = (c.crossAxisExtent - gap * 2) / 3;
                  final shown = [
                    for (final i in shelf.items)
                      if (safe(() => i.film) != null) i,
                  ];
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: 16,
                      childAspectRatio: w / (w * 1.5 + textHeight(context, 54, 50)),
                    ),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => PosterTile(
                      shown[i].film,
                      width: w,
                      strip: showRatings && shown[i].rating != null ? fmtRating(shown[i].rating!) : null,
                      key: ValueKey(shown[i].filmId),
                    ),
                  );
                },
              ),
            ),
            if (shelf.next != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: shelf.loadingMore
                      ? const LoadingBlock()
                      : InkButton(
                          key: const Key('shelf-more'),
                          label: l.friendsMore,
                          outlined: true,
                          onPressed: () => ref.read(shelfProvider(_id).notifier).more(),
                        ),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}

/// One quiet line in place of a profile that is private, empty or out of reach.
class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    child: Text(text, style: TextStyle(color: Palette.of(context).inkSoft, fontSize: 15, height: 1.45)),
  );
}
