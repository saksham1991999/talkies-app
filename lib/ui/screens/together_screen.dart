import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/crews.dart';
import '../../state/crews_remote.dart';
import '../../state/online.dart';
import '../../state/providers.dart';
import '../../state/together.dart';
import '../common.dart';
import '../format.dart';
import '../group_sheets.dart';
import '../icons.dart';
import '../night_editor.dart';
import '../online_gate.dart';
import '../online_widgets.dart';
import '../theme.dart';
import '../together_widgets.dart';
import '../widgets.dart';
import 'profile_screen.dart';

/// The sixth tab: groups, nights and, while the server is up and the user is
/// signed in, friends. The root reads only crews.json at build time, because the
/// Shell builds every tab on the first frame.
class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key});

  @override
  ConsumerState<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends ConsumerState<TogetherScreen> {
  var _joinOpen = false;

  @override
  void initState() {
    super.initState();
    // A code that arrived before this screen was built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeJoin());
  }

  /// A waiting invite code opens the join sheet by itself, but only while the
  /// server is up and the user is signed in.
  Future<void> _maybeJoin() async {
    if (!mounted || _joinOpen) return;
    final code = ref.read(pendingJoinProvider);
    if (code == null || !ref.read(onlineProvider)) return;
    _joinOpen = true;
    final id = await showJoinSheet(ref, context, code: code);
    _joinOpen = false;
    if (id != null && mounted) openCrew(context, id);
  }

  Future<void> _joinWithCode() async {
    final id = await showJoinSheet(ref, context);
    if (id != null && mounted) openCrew(context, id);
  }

  Future<void> _newGroup() async {
    final id = await showNewGroupSheet(context);
    if (id != null && mounted) openCrew(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final online = ref.watch(onlineProvider);
    final picked = ref.watch(togetherSegmentProvider);
    // The Friends segment exists only while the gate is open.
    final seg = !online && picked == TogetherSegment.friends ? TogetherSegment.groups : picked;
    ref.listen(onlineProvider, (_, on) {
      if (!on && ref.read(togetherSegmentProvider) == TogetherSegment.friends) {
        ref.read(togetherSegmentProvider.notifier).go(TogetherSegment.groups);
      }
      _maybeJoin();
    });
    ref.listen(pendingJoinProvider, (_, _) => _maybeJoin());

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 20),
                Expanded(child: Text(l.tabTogether.toUpperCase(), style: disp(15, p.accent, spacing: 2.4))),
                TkButton(Tk.person, tooltip: l.togetherProfile, onPressed: () => push(context, const ProfileScreen())),
                const SizedBox(width: 8),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final (s, label) in [
                      (TogetherSegment.groups, l.togetherGroups),
                      (TogetherSegment.nights, l.togetherNights),
                      if (online) (TogetherSegment.friends, l.togetherFriends),
                    ])
                      TapBox(
                        label: label,
                        dense: false,
                        selected: seg == s,
                        onTap: () => ref.read(togetherSegmentProvider.notifier).go(s),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: switch (seg) {
                TogetherSegment.groups => _GroupsBody(onNew: _newGroup, onJoin: _joinWithCode),
                TogetherSegment.nights => const _NightsBody(),
                // A body that scrolls itself: it gets the height under the segments.
                TogetherSegment.friends => const FriendsSegment(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupsBody extends ConsumerWidget {
  const _GroupsBody({required this.onNew, required this.onJoin});
  final VoidCallback onNew, onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final p = Palette.of(context);
    final groups = ref.watch(groupsProvider);
    final online = ref.watch(onlineProvider);
    final offline = online && ref.watch(sharedCrewsProvider.select((s) => s.offline));
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SlabButton(label: l.togetherNewGroup, icon: Tk.plus, onPressed: onNew),
        ),
        if (groups.isEmpty)
          EmptyNote(l.togetherNoGroups)
        else
          for (final g in groups) CrewTicket(g, key: ValueKey(g.id), onTap: () => openCrew(context, g.id)),
        OnlineOnly(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: ListTile(
              key: const Key('join-with-code'),
              leading: TkIcon(Tk.link, size: 22, color: p.accent),
              title: Text(l.togetherJoinWithCode, style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: onJoin,
            ),
          ),
        ),
        if (offline) CantReach(onRetry: () => ref.read(sharedCrewsProvider.notifier).refresh()),
      ],
    );
    // Pull to refresh asks the server, so it exists only while the gate is open.
    return online
        ? RefreshIndicator(onRefresh: () => ref.read(sharedCrewsProvider.notifier).refresh(), child: list)
        : list;
  }
}

class _NightsBody extends ConsumerWidget {
  const _NightsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final entries = ref.watch(nightsProvider);
    final now = ref.watch(nowProvider)();
    final ahead = [
      for (final e in entries)
        if (nightIsAhead(e.night, now)) e,
    ];
    final past = [
      for (final e in entries)
        if (!nightIsAhead(e.night, now)) e,
    ];
    Widget ticket(NightEntry e) => NightTicket(
      e,
      key: ValueKey('${e.crew.id}/${e.night.id}'),
      onTap: () => openNight(context, e.crew.id, e.night.id),
    );
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SlabButton(
            label: l.nightPlanTitle,
            icon: Tk.clock,
            tone: SlabTone.velvet,
            onPressed: () => planNight(context, ref),
          ),
        ),
        if (entries.isEmpty) EmptyNote(l.togetherNoNights),
        if (ahead.isNotEmpty) ...[SectionTitle(l.togetherComingUp), for (final e in ahead) ticket(e)],
        if (past.isNotEmpty) ...[SectionTitle(l.togetherEarlier), for (final e in past) ticket(e)],
      ],
    );
  }
}
