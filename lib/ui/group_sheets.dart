import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/crews.dart';
import '../data/models.dart';
import '../state/crews.dart';
import '../state/crews_remote.dart';
import '../state/providers.dart';
import 'format.dart';
import 'icons.dart';
import 'online_gate.dart';
import 'theme.dart';
import 'together_widgets.dart';

// Sheets that start or join a group, and put a film into one. Each returns what
// the caller needs to go on (a group id or a name); none navigates by itself.

// ---------------------------------------------------------------------------
// New group

/// Asks for a name, who is holding the phone and who to add, and makes the
/// group. Returns the new group's id, or null when the sheet is dismissed.
Future<String?> showNewGroupSheet(BuildContext context) => showSheet<String>(context, (_) => const _NewGroupSheet());

class _NewGroupSheet extends ConsumerStatefulWidget {
  const _NewGroupSheet();

  @override
  ConsumerState<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends ConsumerState<_NewGroupSheet> {
  final _name = TextEditingController();
  final _me = TextEditingController();
  final _picked = <String>{};
  var _shared = false;
  var _busy = false;
  Refusal? _refused;

  @override
  void initState() {
    super.initState();
    // The name given in an earlier group is the usual answer.
    for (final c in ref.read(crewsProvider).crews) {
      final n = c.me?.name.trim() ?? '';
      if (n.isNotEmpty) {
        _me.text = n;
        break;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _me.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _refused = null;
    });
    final r = _shared
        ? await ref.read(sharedCrewsProvider.notifier).create(name)
        : await ref.read(crewsProvider.notifier).create(name, myName: _me.text.trim());
    if (!mounted) return;
    final crew = r.value;
    if (crew == null) {
      setState(() {
        _busy = false;
        _refused = r.refusal;
      });
      return;
    }
    if (!_shared) {
      final group = ref.read(crewProvider(crew.id).notifier);
      for (final n in _picked) {
        // A full group or a repeated name is no reason to stop: the members sheet shows who is in.
        await group.addMember(n);
        if (!mounted) return;
      }
    }
    Navigator.pop(context, crew.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final mine = _me.text.trim().toLowerCase();
    final suggestions = [
      for (final n in companyNames(ref.watch(diaryProvider)))
        if (n.toLowerCase() != mine) n,
    ].take(8).toList();
    return SheetBody(
      title: l.crewNewTitle,
      children: [
        TextField(
          key: const Key('crew-name'),
          controller: _name,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: l.crewNameLabel, counterText: ''),
          onChanged: (_) => setState(() {}),
        ),
        if (!_shared) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('crew-me'),
            controller: _me,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.crewMyNameLabel, hintText: l.togetherYou, counterText: ''),
            onChanged: (_) => setState(() {}),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              l.crewSuggestTitle,
              style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final n in suggestions)
                  TapBox(
                    label: n,
                    selected: _picked.contains(n),
                    onTap: () => setState(() => _picked.contains(n) ? _picked.remove(n) : _picked.add(n)),
                  ),
              ],
            ),
          ],
        ],
        OnlineOnly(
          child: SwitchListTile(
            key: const Key('crew-shared'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.crewSharedSwitch, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(l.crewSharedHint, style: TextStyle(color: p.inkSoft, height: 1.35)),
            value: _shared,
            onChanged: _busy ? null : (v) => setState(() => _shared = v),
          ),
        ),
        if (_refused != null) Note(refusalText(context, _refused!), strong: true),
        const SizedBox(height: 18),
        SlabButton(
          key: const Key('crew-create'),
          label: _shared ? l.crewCreateShared : l.crewCreate,
          busy: _busy,
          onPressed: _name.text.trim().isEmpty ? null : _create,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Join with a code

/// Joins a shared group. [code] comes from a link; without one the person types it.
/// The sheet says what joining shares, joins on the button, and then shows the
/// group's name. Returns the group's id when the person opens the group.
Future<String?> showJoinSheet(WidgetRef ref, BuildContext context, {String? code}) async {
  final id = await showSheet<String>(context, (_) => _JoinSheet(code: code));
  // A code that was not used must not open the sheet again.
  ref.read(pendingJoinProvider.notifier).clear();
  return id;
}

class _JoinSheet extends ConsumerStatefulWidget {
  const _JoinSheet({this.code});
  final String? code;

  @override
  ConsumerState<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends ConsumerState<_JoinSheet> {
  late final _code = TextEditingController(text: widget.code ?? '');
  var _busy = false;
  Refusal? _refused;
  Crew? _joined;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_busy || normalizeCode(_code.text) == null) return;
    setState(() {
      _busy = true;
      _refused = null;
    });
    final r = await ref.read(sharedCrewsProvider.notifier).joinGroup(_code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _joined = r.value;
      _refused = r.refusal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final joined = _joined;
    if (joined != null) {
      return SheetBody(
        children: [
          Text(l.joinJoined(joined.name).toUpperCase(), style: disp(30, p.ink, height: 1.05)),
          const SizedBox(height: 18),
          SlabButton(label: l.joinOpen, icon: Tk.right, onPressed: () => Navigator.pop(context, joined.id)),
        ],
      );
    }
    return SheetBody(
      title: l.crewJoinTitle,
      children: [
        TextField(
          key: const Key('join-code'),
          controller: _code,
          autofocus: widget.code == null,
          maxLength: 12,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          style: disp(26, p.ink, spacing: 4),
          inputFormatters: [TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase()))],
          decoration: InputDecoration(labelText: l.crewJoinCodeLabel, counterText: ''),
          onChanged: (_) => setState(() => _refused = null),
          onSubmitted: (_) => _join(),
        ),
        Note(l.crewJoinNote),
        if (_refused != null) Note(refusalText(context, _refused!), strong: true),
        const SizedBox(height: 18),
        SlabButton(
          key: const Key('join-go'),
          label: l.joinAction,
          busy: _busy,
          onPressed: normalizeCode(_code.text) == null ? null : _join,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add a film to a group

/// Lists the groups so a film can go to one of them, with "New group" at the end.
/// Returns the name of the group the film went to, or null.
Future<String?> showAddToGroupSheet(BuildContext context, Film film) =>
    showSheet<String>(context, (_) => _AddToGroupSheet(film));

class _AddToGroupSheet extends ConsumerStatefulWidget {
  const _AddToGroupSheet(this.film);
  final Film film;

  @override
  ConsumerState<_AddToGroupSheet> createState() => _AddToGroupSheetState();
}

class _AddToGroupSheetState extends ConsumerState<_AddToGroupSheet> {
  String? _busyId;
  Refusal? _refused;

  Future<void> _add(Crew crew) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = crew.id;
      _refused = null;
    });
    final r = await ref.read(crewProvider(crew.id).notifier).addFilm(widget.film);
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, crew.name);
    } else {
      setState(() {
        _busyId = null;
        _refused = r.refusal;
      });
    }
  }

  Future<void> _new() async {
    final id = await showNewGroupSheet(context);
    if (id == null || !mounted) return;
    final crew = ref.read(groupsProvider).where((c) => c.id == id).firstOrNull;
    if (crew != null) await _add(crew);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final groups = ref.watch(groupsProvider);
    return SheetBody(
      title: l.togetherAddToGroup,
      children: [
        for (final g in groups)
          // A film only this phone has cannot be shown on another phone.
          _GroupRow(
            crew: g,
            enabled: !(widget.film.isCustom && g.shared) && _busyId == null,
            note: widget.film.isCustom && g.shared ? l.crewOwnFilmLocal : null,
            has: g.films.any((w) => w.filmId == widget.film.id),
            onTap: () => _add(g),
          ),
        if (_refused != null) Note(refusalText(context, _refused!), strong: true),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('add-to-new-group'),
            onPressed: _busyId == null ? _new : null,
            icon: TkIcon(Tk.plus, size: 20, color: p.accent),
            label: Text(
              l.togetherNewGroup,
              style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.crew, required this.enabled, required this.has, required this.onTap, this.note});
  final Crew crew;
  final bool enabled, has;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      onTap: onTap,
      title: Text(crew.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        note ?? [if (crew.shared) l.togetherShared, l.togetherFilmsCount(crew.films.length)].join('  ·  '),
        style: TextStyle(color: p.inkSoft),
      ),
      trailing: has ? TkIcon(Tk.check, size: 20, color: p.accent) : null,
    );
  }
}
