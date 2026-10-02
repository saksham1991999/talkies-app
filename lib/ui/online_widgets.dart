import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/social.dart';
import '../state/crews.dart';
import '../state/crews_remote.dart';
import '../state/online.dart';
import '../state/providers.dart';
import '../state/social.dart';
import '../state/together.dart';
import 'avatar.dart';
import 'common.dart';
import 'format.dart';
import 'friend_widgets.dart';
import 'icons.dart';
import 'online_gate.dart';
import 'online_parts.dart';
import 'screens/friend_screen.dart';
import 'screens/friends_screen.dart';
import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Friends who watched this

/// "Friends who watched this" for the film screen: the stamps of the friends who watched it, with the rating
/// when they share it. It draws nothing unless the app is online and the film is not a custom one, and it is
/// silent when the server fails.
class FriendsWhoWatched extends ConsumerStatefulWidget {
  const FriendsWhoWatched({super.key, required this.film});
  final Film film;

  @override
  ConsumerState<FriendsWhoWatched> createState() => _FriendsWhoWatchedState();
}

class _FriendsWhoWatchedState extends ConsumerState<FriendsWhoWatched> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_ask);
  }

  @override
  void didUpdateWidget(FriendsWhoWatched old) {
    super.didUpdateWidget(old);
    if (old.film.id != widget.film.id) Future.microtask(_ask);
  }

  // The controller checks the gate and the custom film itself, and caches for ten minutes.
  void _ask() {
    if (mounted) unawaited(ref.read(friendsWhoWatchedProvider.notifier).ensure(widget.film.id));
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(onlineProvider);
    ref.listen(onlineProvider, (was, now) {
      if (now && was != true) _ask();
    });
    if (widget.film.isCustom || !online) return const SizedBox.shrink();
    final friends = ref.watch(friendsWhoWatchedProvider.select((m) => m[widget.film.id]));
    if (friends == null || friends.isEmpty) return const SizedBox.shrink();
    final showRatings = ref.watch(settingsProvider.select((s) => s.showRatings));
    final l = context.l;
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l.friendsWatchedThis),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(
            runSpacing: 4,
            children: [
              for (final w in friends)
                Semantics(
                  button: true,
                  label: [nameOf(l, w.user), if (showRatings && w.rating != null) fmtRating(w.rating!)].join(', '),
                  excludeSemantics: true,
                  child: InkWell(
                    key: Key('who-${w.user.id}'),
                    borderRadius: BorderRadius.circular(3),
                    onTap: () => push(context, FriendScreen(card: w.user)),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Avatar(name: nameOf(l, w.user), ink: w.user.avatarColor, size: 44),
                            if (showRatings && w.rating != null)
                              Text(fmtRating(w.rating!), style: disp(18, figureColor(p), spacing: 0.4)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Send a film

/// Hands text to the system share sheet. Tests replace it.
final shareTextProvider = Provider<Future<void> Function(String text, String subject, Rect? origin)>(
  (ref) =>
      (text, subject, origin) =>
          SharePlus.instance.share(ShareParams(text: text, subject: subject, sharePositionOrigin: origin)),
);

/// What goes to other apps: the note, the title with the year, the Wikipedia link, and a short Talkies line.
String shareText(Film film, String note, String line) {
  final title = film.year == null ? film.title : '${film.title} (${film.year})';
  final wiki = film.wiki != null && !film.isCustom
      ? 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(film.wiki!.replaceAll(' ', '_'))}'
      : null;
  return [if (note.trim().isNotEmpty) note.trim(), title, ?wiki, line].join('\n');
}

/// "Send" for the film screen. Always there: it opens a sheet with a note, the system share sheet, and, while the
/// app is online, the friends to send the film to.
class SendFilmButton extends ConsumerWidget {
  const SendFilmButton({super.key, required this.film});
  final Film film;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    return TextButton.icon(
      key: const Key('send-film'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _SendSheet(film: film),
      ),
      icon: TkIcon(Tk.send, size: 20, color: p.ink),
      label: Text(
        context.l.sendFilm,
        style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
      ),
    );
  }
}

enum _Sending { sending, sent }

class _SendSheet extends ConsumerStatefulWidget {
  const _SendSheet({required this.film});
  final Film film;

  @override
  ConsumerState<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends ConsumerState<_SendSheet> {
  final _note = TextEditingController();
  final _state = <String, _Sending>{};
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(onlineProvider)) ref.read(friendsProvider.notifier).loadFriends();
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _sendTo(UserCard friend) async {
    final l = context.l;
    setState(() {
      _state[friend.id] = _Sending.sending;
      _message = null;
    });
    final r = await outcomeOf(
      () => ref.read(remoteCrewRepoProvider).sendFilm(friend.id, widget.film, note: _note.text),
    );
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _state[friend.id] = _Sending.sent;
      } else {
        _state.remove(friend.id);
        _message = switch (r.refusal) {
          Refusal.offline => l.gateCantReach,
          Refusal.rateLimited => l.sendTooFast,
          Refusal.notAllowed || Refusal.notFound => l.sendNotAllowed,
          _ => l.sendFailed,
        };
      }
    });
  }

  Future<void> _share(BuildContext button) async {
    final box = button.findRenderObject() as RenderBox?;
    await ref.read(shareTextProvider)(
      shareText(widget.film, _note.text, context.l.sendShareLine),
      widget.film.title,
      box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final film = widget.film;
    final online = ref.watch(onlineProvider);
    final friends = online ? ref.watch(friendsProvider).friends : const Remote<List<FriendItem>>();
    final list = friends.value;
    final meta = [if (film.year != null) '${film.year}', ...film.directors.take(1)].join('  ·  ');
    // The people rows pad themselves; everything else gets the same 20.
    Widget pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);
    // namesRoute: a screen reader says what the sheet is when it opens.
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l.sendTitle,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.only(bottom: 20 + MediaQuery.viewInsetsOf(context).bottom),
            children: [
              pad(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Poster(film, width: 48, radius: 3),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            film.title.toUpperCase(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: disp(22, p.ink),
                          ),
                          if (meta.isNotEmpty) Text(meta, style: TextStyle(color: p.inkSoft, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              pad(
                TextField(
                  key: const Key('send-note'),
                  controller: _note,
                  maxLength: 140,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: l.sendNote, hintText: l.sendNoteHint),
                ),
              ),
              if (online) ...[
                pad(
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(l.sendToFriend, style: disp(18, p.ink)),
                  ),
                ),
                if (list == null)
                  switch (friends.status) {
                    Fetch.offline => CantReach(onRetry: () => ref.read(friendsProvider.notifier).loadFriends()),
                    Fetch.failed => pad(Text(l.acctFailed, style: TextStyle(color: p.inkSoft))),
                    _ => const LoadingBlock(),
                  }
                else if (list.isEmpty)
                  pad(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(l.sendNoFriends, style: TextStyle(color: p.inkSoft, height: 1.4)),
                    ),
                  )
                else
                  for (final f in list)
                    PersonRow(
                      key: ValueKey(f.card.id),
                      card: f.card,
                      subtitle: f.card.handle == null ? null : '@${f.card.handle}',
                      trailing: switch (_state[f.card.id]) {
                        _Sending.sent => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TkIcon(Tk.check, size: 18, color: p.ink),
                            const SizedBox(width: 6),
                            Text(
                              l.sendDone,
                              style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        _Sending.sending => const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        null => TextButton(
                          style: linkStyle(context),
                          key: Key('send-to-${f.card.id}'),
                          onPressed: () => _sendTo(f.card),
                          child: Text(l.sendFilm),
                        ),
                      },
                    ),
                if (_message != null)
                  pad(
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _message!,
                          style: TextStyle(color: p.ink, fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              pad(
                Builder(
                  builder: (button) => InkButton(
                    key: const Key('send-other'),
                    label: l.sendOther,
                    icon: Tk.share,
                    outlined: true,
                    onPressed: () => _share(button),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home strip

/// "Friends are watching" for Home: the films friends watched, with the friend's name on each poster. It draws
/// nothing unless the app is online and the feed has something. It asks for the feed only after the first
/// frame, and only once the server is up and somebody is signed in.
class FriendsStrip extends ConsumerStatefulWidget {
  const FriendsStrip({super.key});

  @override
  ConsumerState<FriendsStrip> createState() => _FriendsStripState();
}

class _FriendsStripState extends ConsumerState<FriendsStrip> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    if (!mounted || !ref.read(onlineProvider)) return;
    // Loaded, or loading: leave it. A failed load tries again the next time the app is online.
    if (ref.read(feedProvider).status case Fetch.ready || Fetch.loading) return;
    unawaited(ref.read(feedProvider.notifier).load());
  }

  /// "Asha Rao" is "Asha" on a poster, and never longer than 12 letters.
  String _short(String name) {
    final first = name.trim().split(RegExp(r'\s+')).first;
    return first.characters.length <= 12 ? first : '${first.characters.take(11)}…';
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(onlineProvider);
    ref.listen(onlineProvider, (was, now) {
      if (now && was != true) _load();
    });
    if (!online) return const SizedBox.shrink();
    final items = ref.watch(feedProvider.select((s) => s.items));
    final l = context.l;
    final watched = [
      for (final i in items)
        if (i.kind == FeedKind.watched && safe(() => i.film) != null) i,
    ].take(12).toList();
    if (watched.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          l.friendsStripTitle,
          action: l.seeAll,
          onAction: () {
            ref.read(tabProvider.notifier).go(togetherTab);
            ref.read(togetherSegmentProvider.notifier).go(TogetherSegment.friends);
          },
        ),
        SizedBox(
          height: textHeight(context, 222, 50),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: watched.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) =>
                PosterTile(watched[i].film, width: 108, strip: _short(nameOf(l, watched[i].user))),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The Friends segment

/// Body of the Friends segment of the Together tab: a row to add a friend, the requests, the friends (the first
/// three, then a row for all) with their taste match, and the feed of what they watched. It scrolls itself when it
/// has a bounded height, and takes the height it needs inside a parent that scrolls.
class FriendsSegment extends ConsumerStatefulWidget {
  const FriendsSegment({super.key});

  @override
  ConsumerState<FriendsSegment> createState() => _FriendsSegmentState();
}

class _FriendsSegmentState extends ConsumerState<FriendsSegment> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  /// Asks for the friends, the requests and the feed again.
  Future<void> _load() async {
    if (!mounted || !ref.read(onlineProvider)) return;
    await Future.wait([ref.read(friendsProvider.notifier).refresh(), ref.read(feedProvider.notifier).load()]);
  }

  Future<void> _retry() async {
    await ref.read(backendProvider.notifier).probe(force: true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final online = ref.watch(onlineProvider);
    ref.listen(onlineProvider, (was, now) {
      if (now && was != true) unawaited(_load());
    });
    // The server went away while this is open.
    if (!online) return CantReach(onRetry: _retry);

    final f = ref.watch(friendsProvider);
    final feed = ref.watch(feedProvider);
    final requests = f.requests.value;
    final friends = f.friends.value;
    final hasRequests = requests != null && (requests.incoming.isNotEmpty || requests.outgoing.isNotEmpty);

    Widget failed(Fetch status, VoidCallback retry) => status == Fetch.offline
        ? CantReach(onRetry: retry)
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(l.acctFailed, style: TextStyle(color: p.inkSoft)),
          );

    return _Flow(
      onRefresh: _load,
      children: [
        NavRow(l.friendsAdd, leading: Tk.plus, onTap: () => push(context, const FriendsScreen())),
        if (hasRequests) ...[
          SectionTitle(l.friendsRequests),
          for (final c in requests.incoming) IncomingRequest(c, key: ValueKey('in-${c.id}')),
          for (final c in requests.outgoing) OutgoingRequest(c, key: ValueKey('out-${c.id}')),
        ],
        SectionTitle(l.friendsTitle),
        if (friends == null)
          (f.friends.status == Fetch.offline || f.friends.status == Fetch.failed)
              ? failed(f.friends.status, () => ref.read(friendsProvider.notifier).loadFriends())
              : const LoadingBlock()
        else if (friends.isEmpty)
          EmptyNote(l.friendsEmpty)
        else ...[
          for (final x in friends.take(3)) FriendRow(x, key: ValueKey(x.card.id)),
          if (friends.length > 3)
            NavRow(l.friendsAll, sub: fmtCount(friends.length), onTap: () => push(context, const FriendsScreen())),
        ],
        SectionTitle(l.feedTitle, action: l.feedRefresh, onAction: () => ref.read(feedProvider.notifier).load()),
        if (feed.items.isEmpty)
          switch (feed.status) {
            Fetch.idle || Fetch.loading => const LoadingBlock(),
            Fetch.offline => CantReach(onRetry: () => ref.read(feedProvider.notifier).load()),
            Fetch.failed => failed(Fetch.failed, () => ref.read(feedProvider.notifier).load()),
            Fetch.ready => EmptyNote(l.feedEmpty),
          }
        else ...[
          for (final i in feed.items) FeedTile(i, key: ValueKey(i.id)),
          if (feed.next != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: feed.loadingMore
                  ? const LoadingBlock()
                  : InkButton(
                      key: const Key('feed-more'),
                      label: l.friendsMore,
                      outlined: true,
                      onPressed: () => ref.read(feedProvider.notifier).more(),
                    ),
            ),
        ],
      ],
    );
  }
}

/// A list that scrolls on its own when it has a bounded height (in an Expanded), and takes the height of its
/// rows when a parent scrolls it (in a ListView or a SingleChildScrollView).
class _Flow extends StatelessWidget {
  const _Flow({required this.children, required this.onRefresh});
  final List<Widget> children;

  /// Pull to refresh, for the case where the list scrolls itself.
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.hasBoundedHeight
        ? RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 48),
              children: children,
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
  );
}
