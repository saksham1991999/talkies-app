import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/social.dart';
import '../../state/online.dart';
import '../../state/social.dart';
import '../common.dart';
import '../format.dart';
import '../friend_widgets.dart';
import '../icons.dart';
import '../online_gate.dart';
import '../online_parts.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_screen.dart';

final _handleRe = RegExp(r'^[a-z0-9_]{3,20}$');

/// Add a friend by their exact handle, and the whole list of friends. A handle is the only way to find a person:
/// there is no search, so nobody can browse for strangers.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _handle = TextEditingController();
  var _busy = false;

  /// The person found by the last lookup, with how they relate to me now.
  UserLookup? _found;
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
    _handle.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    await ref.read(backendProvider.notifier).probe(force: true);
    if (mounted && ref.read(onlineProvider)) ref.read(friendsProvider.notifier).loadFriends();
  }

  Future<void> _find() async {
    final l = context.l;
    final h = _handle.text.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    if (!_handleRe.hasMatch(h)) {
      setState(() {
        _found = null;
        _message = l.friendsNotFound;
      });
      return;
    }
    setState(() {
      _busy = true;
      _found = null;
      _message = null;
    });
    final r = await ref.read(friendsProvider.notifier).lookup(h);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _found = r.value;
      _message = r.ok
          ? null
          : switch (r.outcome) {
              CallOutcome.notFound || CallOutcome.invalid => l.friendsNotFound,
              _ => problemText(l, r.outcome),
            };
    });
  }

  Future<void> _send(UserLookup found) async {
    final l = context.l;
    setState(() {
      _busy = true;
      _message = null;
    });
    final r = await ref.read(friendsProvider.notifier).send(found.card.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        final friends = r.value!.status == RequestStatus.friends;
        _found = UserLookup(card: found.card, relation: friends ? Relation.friend : Relation.outgoing);
        _message = friends ? l.friendsNowFriends : l.friendsRequestSent;
      } else if (r.outcome == CallOutcome.conflict && r.code == 'already_pending') {
        _found = UserLookup(card: found.card, relation: Relation.outgoing);
        _message = l.friendsPendingAlready;
      } else {
        _message = problemText(l, r.outcome);
      }
    });
  }

  Future<void> _accept(UserLookup found) async {
    final l = context.l;
    setState(() => _busy = true);
    final r = await ref.read(friendsProvider.notifier).accept(found.card.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _found = UserLookup(card: found.card, relation: Relation.friend);
        _message = l.friendsNowFriends;
      } else {
        _message = problemText(l, r.outcome);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final p = Palette.of(context);
    final online = ref.watch(onlineProvider);
    final friends = ref.watch(friendsProvider).friends;
    final me = ref.watch(meProvider).value ?? ref.watch(sessionProvider.select((s) => s?.me));
    final list = friends.value;
    final found = _found;

    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.maybePop(context)),
        title: Text(l.friendsTitle.toUpperCase(), style: disp(26, p.ink)),
      ),
      body: !online
          ? ListView(children: [CantReach(onRetry: _retry)])
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 48),
              children: [
                SectionTitle(l.friendsAdd),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.friendsAddHint, style: TextStyle(color: p.inkSoft, height: 1.45)),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('friend-handle'),
                        controller: _handle,
                        maxLength: 21,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.search,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[@A-Za-z0-9_]')),
                          TextInputFormatter.withFunction((_, n) => n.copyWith(text: n.text.toLowerCase())),
                        ],
                        onSubmitted: (_) => _busy ? null : _find(),
                        onChanged: (_) => setState(() {
                          _found = null;
                          _message = null;
                        }),
                        decoration: InputDecoration(
                          labelText: l.friendsHandleLabel,
                          hintText: l.friendsHandleHint,
                          prefixText: '@',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkButton(
                        key: const Key('find-friend'),
                        label: l.friendsFind,
                        icon: Tk.search,
                        onPressed: _busy || _handle.text.trim().isEmpty ? null : _find,
                      ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _message!,
                              style: TextStyle(color: p.ink, fontWeight: FontWeight.w600, height: 1.4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (found != null) ...[
                  const SizedBox(height: 8),
                  PersonRow(
                    card: found.card,
                    subtitle: found.card.handle == null ? null : '@${found.card.handle}',
                    size: 48,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: switch (found.relation) {
                      Relation.none => Align(
                        alignment: Alignment.centerLeft,
                        child: InkButton(
                          key: const Key('send-request'),
                          label: l.friendsSendRequest,
                          onPressed: _busy ? null : () => _send(found),
                        ),
                      ),
                      Relation.incoming => Align(
                        alignment: Alignment.centerLeft,
                        child: InkButton(
                          key: const Key('accept-found'),
                          label: l.friendsAccept,
                          onPressed: _busy ? null : () => _accept(found),
                        ),
                      ),
                      Relation.outgoing => Text(l.friendsWaiting, style: TextStyle(color: p.inkSoft)),
                      Relation.friend => Text(l.friendsAlready, style: TextStyle(color: p.inkSoft)),
                      Relation.self => Text(l.friendsYourself, style: TextStyle(color: p.inkSoft)),
                    },
                  ),
                ],
                if (me != null && me.handle == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: NavRow(l.friendsNoHandle, onTap: () => push(context, const AccountScreen())),
                  ),
                SectionTitle(l.friendsTitle),
                if (list == null)
                  switch (friends.status) {
                    Fetch.offline => CantReach(onRetry: _retry),
                    Fetch.failed => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(l.acctFailed, style: TextStyle(color: p.inkSoft)),
                    ),
                    _ => const LoadingBlock(),
                  }
                else if (list.isEmpty)
                  EmptyNote(l.friendsEmpty)
                else
                  for (final f in list) FriendRow(f, key: ValueKey(f.card.id)),
              ],
            ),
    );
  }
}
