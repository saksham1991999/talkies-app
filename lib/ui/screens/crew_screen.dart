import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crews.dart';
import '../../data/models.dart';
import '../../net/api.dart';
import '../../state/crews.dart';
import '../../state/crews_remote.dart';
import '../../state/providers.dart';
import '../avatar.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../night_editor.dart';
import '../online_gate.dart';
import '../sharer.dart';
import '../theme.dart';
import '../together_widgets.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import 'deck_screen.dart';
import 'search_screen.dart';

enum _Act { rename, delete, leave }

/// One group: who is in it, its list, the deck, and its nights. A shared group
/// also has an invite and a chat.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({super.key, required this.crewId});
  final String crewId;

  @override
  ConsumerState<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends ConsumerState<CrewScreen> {
  /// Kept in a field: `ref` cannot be read in dispose.
  late final CrewController _ctl;
  String? _note;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _ctl = ref.read(crewProvider(widget.crewId).notifier);
  }

  @override
  void dispose() {
    // Swipes of a shared group wait a moment to be sent together: send them as the group closes.
    flushSwipesSoon(_ctl);
    super.dispose();
  }

  /// Shows the reason an action did not happen, or clears the line after one that worked.
  void _took(Outcome<Object?> r) {
    if (!mounted) return;
    setState(() => _note = r.ok ? null : refusalText(context, r.refusal!));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final p = Palette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, style: disp(24, p.ink)),
        content: Text(body, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              action,
              style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _rename(Crew crew) async {
    final field = TextEditingController(text: crew.name);
    final p = Palette.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.l.crewRename, style: disp(24, p.ink)),
        content: TextField(
          key: const Key('rename-field'),
          controller: field,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: c.l.crewNameLabel, counterText: ''),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(c.l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(c, field.text),
            child: Text(
              c.l.save,
              style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    field.dispose();
    if (name == null || name.trim().isEmpty || name.trim() == crew.name || !mounted) return;
    _took(await _ctl.rename(name));
  }

  Future<void> _delete(Crew crew) async {
    final l = context.l;
    if (!await _confirm(l.crewDeleteQ(crew.name), crew.shared ? l.crewDeleteShared : l.crewDeleteLocal, l.delete)) {
      return;
    }
    _took(await _ctl.delete());
  }

  Future<void> _leave(Crew crew) async {
    final l = context.l;
    if (!await _confirm(l.crewLeaveQ(crew.name), l.crewLeaveBody, l.crewLeave)) return;
    _took(await _ctl.leave());
  }

  Future<void> _newCode() async {
    final l = context.l;
    if (!await _confirm(l.crewNewCodeQ, l.crewNewCodeBody, l.crewNewCode)) return;
    _took(await _ctl.rotateInvite());
  }

  /// The https link a chat app can open. The page it shows opens Talkies with the code.
  String _link(String code) => '${ref.read(apiUrlProvider).replaceAll(RegExp(r'/+$'), '')}/j/$code';

  Future<void> _share(BuildContext anchor, Crew crew) async {
    final code = crew.inviteCode;
    if (code == null) return;
    final l = context.l;
    final text = l.crewInviteText(crew.name, _link(code), code);
    final subject = l.crewInviteSubject(crew.name);
    final origin = shareOrigin(anchor);
    try {
      await ref.read(sharerProvider).text(text, subject: subject, origin: origin);
    } catch (_) {
      // The phone has no share sheet: the code is still on screen to read out.
    }
  }

  Future<void> _addFilm() => push(
    context,
    SearchScreen(
      onPick: (f) async {
        final r = await _ctl.addFilm(f);
        _took(r);
      },
    ),
  );

  Future<void> _chat() async {
    await push(context, ChatScreen(crewId: widget.crewId));
    if (mounted) ref.read(chatProvider(widget.crewId).notifier).setActive(false);
  }

  Future<void> _filmActions(Film film) => showSheet<void>(
    context,
    (c) => SheetBody(
      title: film.title,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.l.crewOpenFilm, style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () {
            Navigator.pop(c);
            openFilm(context, film);
          },
        ),
        ListTile(
          key: const Key('list-remove'),
          contentPadding: EdgeInsets.zero,
          title: Text(c.l.crewListRemove, style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () async {
            Navigator.pop(c);
            _took(await _ctl.removeFilm(film.id));
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(crewProvider(widget.crewId));
    final crew = st.crew;
    final p = Palette.of(context);
    final l = context.l;
    final listLoading = crew.shared && crew.name.isEmpty && ref.watch(sharedCrewsProvider.select((s) => s.loading));
    if (st.gone && !listLoading) {
      // Deleted, left or removed: nothing is left to show.
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const Scaffold();
    }
    final now = ref.watch(nowProvider)();
    final owner = crew.isOwner;
    final acts = [if (owner) _Act.rename, if (owner) _Act.delete, if (crew.shared && !owner) _Act.leave];
    final quiet = [l.togetherMembersCount(crew.members.length), if (crew.shared) l.togetherShared].join('  ·  ');
    final unreachable = crew.shared && st.offline;

    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.pop(context)),
        actions: [
          if (acts.isNotEmpty)
            PopupMenuButton<_Act>(
              key: const Key('crew-menu'),
              tooltip: l.togetherMore,
              icon: const TkIcon(Tk.more),
              onSelected: (a) => switch (a) {
                _Act.rename => _rename(crew),
                _Act.delete => _delete(crew),
                _Act.leave => _leave(crew),
              },
              itemBuilder: (_) => [
                for (final a in acts)
                  PopupMenuItem(
                    value: a,
                    child: Text(switch (a) {
                      _Act.rename => l.crewRename,
                      _Act.delete => l.crewDelete,
                      _Act.leave => l.crewLeave,
                    }),
                  ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Text(
              crew.name.toUpperCase(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: disp(40, p.ink, spacing: 0.6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(
              quiet,
              style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w600),
            ),
          ),
          if (st.loading)
            const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2)),
          _Members(crew: crew),
          if (_note != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Note(_note!, strong: true)),
          if (unreachable)
            CantReach(onRetry: () => _ctl.refresh())
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SlabButton(
                    key: const Key('crew-swipe'),
                    label: l.crewSwipe,
                    icon: Tk.right,
                    onPressed: () => push(context, DeckScreen(crewId: widget.crewId)),
                  ),
                  const SizedBox(height: 10),
                  SlabButton(
                    key: const Key('crew-plan'),
                    label: l.nightPlanTitle,
                    icon: Tk.clock,
                    tone: SlabTone.velvet,
                    onPressed: () => push(context, NightEditorScreen(crewId: widget.crewId)),
                  ),
                ],
              ),
            ),
            if (crew.shared && crew.inviteCode != null)
              _Invite(
                code: crew.inviteCode!,
                canRotate: owner,
                onShare: (anchor) => _share(anchor, crew),
                onRotate: _newCode,
              ),
            if (crew.shared)
              OnlineOnly(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  child: ListTile(
                    key: const Key('crew-chat'),
                    leading: TkIcon(Tk.chat, size: 22, color: p.accent),
                    title: Text(l.crewChat, style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: TkIcon(Tk.right, size: 18, color: p.inkSoft),
                    onTap: _chat,
                  ),
                ),
              ),
            SectionTitle(l.crewList, action: l.crewListAdd, onAction: _addFilm),
            if (crew.films.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(l.crewListEmpty, style: TextStyle(color: p.inkSoft, height: 1.4)),
              )
            else
              _ListStrip(films: [for (final w in crew.films) w.film], onTap: _filmActions),
            SectionTitle(l.crewNights),
            if (crew.nights.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(l.crewNoNights, style: TextStyle(color: p.inkSoft)),
              )
            else
              for (final n in [...crew.nights]..sort((a, b) => _byTime(a, b, now)))
                NightTicket(
                  (crew: crew, night: n),
                  key: ValueKey(n.id),
                  onTap: () => openNight(context, crew.id, n.id),
                ),
          ],
        ],
      ),
    );
  }

  /// Nights to come first, the soonest on top, then the past ones, the latest on top.
  static int _byTime(Night a, Night b, DateTime now) {
    final (x, y) = (a.when, b.when);
    final (ax, ay) = (nightIsAhead(a, now), nightIsAhead(b, now));
    if (ax != ay) return ax ? -1 : 1;
    if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
    return ax ? x.compareTo(y) : y.compareTo(x);
  }
}

/// The member stamps under the name. Tapping them opens the members sheet.
class _Members extends StatelessWidget {
  const _Members({required this.crew});
  final Crew crew;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    const shown = 7;
    final more = crew.members.length - shown;
    return Semantics(
      button: true,
      label: l.crewMembers,
      excludeSemantics: true,
      child: InkWell(
        key: const Key('crew-members'),
        onTap: () => showSheet<void>(context, (_) => _MembersSheet(crewId: crew.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final m in crew.members.take(shown))
                      Avatar(name: memberName(context, m), ink: m.ink, size: 38),
                    if (more > 0) Text('+$more', style: disp(18, p.ink)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l.crewMembers,
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              TkIcon(Tk.right, size: 18, color: p.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// The invite as a ticket: the code in red print, and the counterfoil shares it.
class _Invite extends StatelessWidget {
  const _Invite({required this.code, required this.canRotate, required this.onShare, required this.onRotate});
  final String code;
  final bool canRotate;
  final void Function(BuildContext anchor) onShare;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final shown = code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TicketPaper(
            color: p.paper(VenueType.ott),
            shape: const TicketBorder(radius: 6, notch: 7, notchFromRight: 84),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 92),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.crewJoinCodeLabel,
                            style: const TextStyle(fontSize: 12.5, color: paperInkSoft, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Semantics(
                              label: code.split('').join(' '),
                              excludeSemantics: true,
                              child: Text(shown, style: disp(36, serialRed, spacing: 3)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Builder(
                      builder: (anchor) => Semantics(
                        button: true,
                        label: l.crewShareInvite,
                        excludeSemantics: true,
                        child: InkWell(
                          key: const Key('crew-share'),
                          onTap: () => onShare(anchor),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const TkIcon(Tk.share, size: 24, color: paperInk),
                                const SizedBox(height: 4),
                                Text(l.share.toUpperCase(), style: disp(13, paperInk, spacing: 1)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (canRotate)
            TextButton.icon(
              key: const Key('crew-new-code'),
              onPressed: onRotate,
              icon: TkIcon(Tk.refresh, size: 18, color: p.inkSoft),
              label: Text(
                l.crewNewCode,
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

/// The group's list as a strip of posters. Tapping one opens its actions.
class _ListStrip extends StatelessWidget {
  const _ListStrip({required this.films, required this.onTap});
  final List<Film> films;
  final void Function(Film) onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      height: textHeight(context, 204, 50),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: films.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final f = films[i];
          return SizedBox(
            width: 96,
            child: Semantics(
              button: true,
              label: f.title,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onTap(f),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Poster(f, width: 96),
                    const SizedBox(height: 6),
                    Text(
                      f.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink, height: 1.2),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Members

class _MembersSheet extends ConsumerStatefulWidget {
  const _MembersSheet({required this.crewId});
  final String crewId;

  @override
  ConsumerState<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends ConsumerState<_MembersSheet> {
  final _name = TextEditingController();
  var _busy = false;
  Refusal? _refused;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add(String name) async {
    final n = name.trim();
    if (n.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _refused = null;
    });
    final r = await ref.read(crewProvider(widget.crewId).notifier).addMember(n);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _refused = r.refusal;
      if (r.ok) _name.clear();
    });
  }

  Future<void> _remove(Member m) async {
    final l = context.l;
    final p = Palette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.l.crewRemoveQ(memberName(c, m)), style: disp(24, p.ink)),
        content: Text(c.l.crewRemoveBody, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              l.remove,
              style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await ref.read(crewProvider(widget.crewId).notifier).removeMember(m.id);
    if (mounted) setState(() => _refused = r.refusal);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final crew = ref.watch(crewProvider(widget.crewId)).crew;
    final canEdit = !crew.shared || crew.isOwner;
    final taken = {for (final m in crew.members) m.name.trim().toLowerCase()};
    final suggestions = [
      for (final n in companyNames(ref.watch(diaryProvider)))
        if (!taken.contains(n.toLowerCase())) n,
    ].take(8).toList();
    return SheetBody(
      title: l.crewMembers,
      children: [
        for (final m in crew.members)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Avatar(name: memberName(context, m), ink: m.ink, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memberName(context, m),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                      ),
                      if ([if (m.me) l.togetherYou, if (m.owner) l.crewOwner, if (m.guest) l.crewGuest] case final tags
                          when tags.isNotEmpty)
                        Text(tags.join('  ·  '), style: TextStyle(color: p.inkSoft, fontSize: 12.5)),
                    ],
                  ),
                ),
                if (canEdit && !m.me)
                  TkButton(Tk.close, tooltip: l.remove, size: 18, color: p.inkSoft, onPressed: () => _remove(m)),
              ],
            ),
          ),
        if (canEdit) ...[
          const SizedBox(height: 14),
          TextField(
            key: const Key('member-name'),
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l.crewAddName,
              counterText: '',
              suffixIcon: TkButton(
                Tk.plus,
                tooltip: l.crewAdd,
                color: p.accent,
                onPressed: _busy ? null : () => _add(_name.text),
              ),
            ),
            onSubmitted: _add,
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [for (final n in suggestions) TapBox(label: n, selected: false, onTap: () => _add(n))],
            ),
          ],
        ],
        if (_refused != null) Note(refusalText(context, _refused!), strong: true),
      ],
    );
  }
}
