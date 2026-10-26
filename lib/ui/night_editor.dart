import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/crews.dart';
import '../data/models.dart';
import '../state/crews.dart';
import '../state/providers.dart';
import 'common.dart';
import 'format.dart';
import 'group_sheets.dart';
import 'icons.dart';
import 'screens/night_screen.dart';
import 'screens/search_screen.dart';
import 'theme.dart';
import 'together_widgets.dart';
import 'widgets.dart';

/// Starts a night from anywhere: the person picks the group first when there are
/// several, and a group is made first when there is none.
Future<void> planNight(BuildContext context, WidgetRef ref, {DateTime? day, List<Film> films = const []}) async {
  final groups = ref.read(groupsProvider);
  final String? id;
  if (groups.isEmpty) {
    id = await showNewGroupSheet(context);
  } else if (groups.length == 1) {
    id = groups.first.id;
  } else {
    id = await showSheet<String>(context, (_) => _GroupChooser(groups));
  }
  if (id == null || !context.mounted) return;
  await push(context, NightEditorScreen(crewId: id, day: day, films: films));
}

class _GroupChooser extends StatelessWidget {
  const _GroupChooser(this.groups);
  final List<Crew> groups;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    return SheetBody(
      title: l.nightChooseGroup,
      children: [
        for (final g in groups)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: g.shared ? Text(l.togetherShared, style: TextStyle(color: p.inkSoft)) : null,
            onTap: () => Navigator.pop(context, g.id),
          ),
      ],
    );
  }
}

/// One time of the night: a day and a clock time, picked one after the other.
class _Slot {
  _Slot({this.date}) : time = const TimeOfDay(hour: 20, minute: 0);
  DateTime? date;
  TimeOfDay time;

  DateTime? get at => date == null ? null : DateTime(date!.year, date!.month, date!.day, time.hour, time.minute);
}

/// Whether [a] and [b] are the same calendar day.
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// The clock time just after [now], on the next whole five minutes.
TimeOfDay _roundedUp(DateTime now) {
  final m = now.hour * 60 + now.minute - now.minute % 5 + 5;
  return TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
}

/// [t], unless [floor] is later: a poll slot may not sit in the past.
TimeOfDay _notBefore(TimeOfDay t, TimeOfDay? floor) {
  final f = floor;
  if (f == null) return t;
  final past = t.hour < f.hour || (t.hour == f.hour && t.minute < f.minute);
  return past ? f : t;
}

/// Plans a night: 1 to 3 films, 1 to 2 times and a place. One film and one time
/// make a night that is set. Anything more is a poll the group votes on.
class NightEditorScreen extends ConsumerStatefulWidget {
  const NightEditorScreen({super.key, required this.crewId, this.films = const [], this.day});
  final String crewId;

  /// Films to start with: the top of the deck, or the Tonight pick.
  final List<Film> films;

  /// The day tapped in the calendar.
  final DateTime? day;

  @override
  ConsumerState<NightEditorScreen> createState() => _NightEditorScreenState();
}

class _NightEditorScreenState extends ConsumerState<NightEditorScreen> {
  late final List<Film> _films = [...widget.films.take(3)];
  late final List<_Slot> _slots = [_Slot(date: widget.day)];
  final _place = TextEditingController();
  var _busy = false;
  String? _note;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  Crew get _crew => ref.read(crewProvider(widget.crewId)).crew;

  void _add(Film f) {
    if (_films.length >= 3 || _films.any((x) => x.id == f.id)) return;
    // A film only this phone has cannot be shown on another phone.
    if (f.isCustom && _crew.shared) {
      setState(() => _note = context.l.crewOwnFilmLocal);
      return;
    }
    setState(() {
      _films.add(f);
      _note = null;
    });
  }

  Future<void> _pickFilm() async {
    final picked = await showSheet<Object>(
      context,
      (_) => _FilmPick(films: [for (final w in _crew.films) w.film], taken: {for (final f in _films) f.id}),
    );
    if (!mounted) return;
    if (picked is Film) {
      _add(picked);
    } else if (picked == true) {
      await push(context, SearchScreen(onPick: _add));
    }
  }

  Future<void> _pickTime(_Slot s) async {
    final today = ref.read(todayProvider);
    final now = ref.read(nowProvider)().toLocal();
    final day = await showDatePicker(
      context: context,
      initialDate: s.date ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 399)),
    );
    if (day == null || !mounted) return;
    // No slot in the past: on today itself the earliest time is now, rounded up to the next five minutes.
    final floor = _sameDay(day, now) ? _roundedUp(now) : null;
    final time = await showTimePicker(context: context, initialTime: _notBefore(s.time, floor));
    if (time == null || !mounted) return;
    setState(() {
      s.date = day;
      s.time = _notBefore(time, floor);
    });
  }

  Future<void> _submit() async {
    final now = ref.read(nowProvider)();
    final times = [for (final s in _slots) ?s.at];
    // The picker clamps, but a slot picked minutes ago can have slipped by: no night in the past.
    if (_films.isEmpty || times.length != _slots.length || times.any((t) => !t.isAfter(now)) || _busy) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    final draft = NightCreate(
      films: List.of(_films),
      slots: [for (final t in times) t.toUtc()],
      // The group's clock when the night is made: the first time's own offset from UTC.
      tzOffsetMin: times.first.timeZoneOffset.inMinutes,
      place: _place.text,
    );
    final r = await ref.read(crewProvider(widget.crewId).notifier).createNight(draft);
    if (!mounted) return;
    final night = r.value;
    if (night == null) {
      setState(() {
        _busy = false;
        _note = refusalText(context, r.refusal!);
      });
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => NightScreen(crewId: widget.crewId, nightId: night.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final crew = ref.watch(crewProvider(widget.crewId)).crew;
    final set = _films.length == 1 && _slots.length == 1;
    final now = ref.watch(nowProvider)();
    final missing = _films.isEmpty
        ? l.nightNeedFilm
        : _slots.any((s) => s.date == null)
        ? l.nightNeedTime
        : _slots.any((s) {
            final at = s.at;
            return at != null && !at.isAfter(now);
          })
        ? l.nightTimePast
        : null;
    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.pop(context)),
        title: Text(l.nightPlanTitle.toUpperCase(), style: disp(26, p.ink)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Text(
              crew.name,
              style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          SectionTitle(l.nightFilms),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.nightFilmsHint, style: TextStyle(color: p.inkSoft, height: 1.4)),
                const SizedBox(height: 8),
                for (final f in _films)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Poster(f, width: 40, radius: 3),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            f.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                          ),
                        ),
                        TkButton(
                          Tk.close,
                          tooltip: l.remove,
                          size: 18,
                          color: p.inkSoft,
                          onPressed: () => setState(() => _films.remove(f)),
                        ),
                      ],
                    ),
                  ),
                if (_films.length < 3)
                  TextButton.icon(
                    key: const Key('night-add-film'),
                    onPressed: _pickFilm,
                    icon: TkIcon(Tk.plus, size: 20, color: p.accent),
                    label: Text(
                      l.nightAddFilm,
                      style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          SectionTitle(l.nightTimes),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.nightTimesHint, style: TextStyle(color: p.inkSoft, height: 1.4)),
                const SizedBox(height: 8),
                for (final (i, s) in _slots.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SlotBox(key: Key('night-slot-$i'), slot: s, onTap: () => _pickTime(s)),
                        ),
                        if (_slots.length > 1)
                          TkButton(
                            Tk.close,
                            tooltip: l.remove,
                            size: 18,
                            color: p.inkSoft,
                            onPressed: () => setState(() => _slots.remove(s)),
                          ),
                      ],
                    ),
                  ),
                if (_slots.length < 2)
                  TextButton.icon(
                    key: const Key('night-add-time'),
                    onPressed: () => setState(() => _slots.add(_Slot())),
                    icon: TkIcon(Tk.plus, size: 20, color: p.accent),
                    label: Text(
                      l.nightAddTime,
                      style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          SectionTitle(l.labelPlace),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              key: const Key('night-place'),
              controller: _place,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: l.nightPlaceHint, counterText: ''),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SlabButton(
                  key: const Key('night-submit'),
                  label: set ? l.nightSetIt : l.nightPostPoll,
                  icon: Tk.clock,
                  busy: _busy,
                  onPressed: missing == null ? _submit : null,
                ),
                Note(missing ?? (set ? l.nightSetNote : l.nightPollNote)),
                if (_note != null) Note(_note!, strong: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A time of the night as a box: the day and the clock time, or an invitation to pick them.
class _SlotBox extends StatelessWidget {
  const _SlotBox({super.key, required this.slot, required this.onTap});
  final _Slot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final at = slot.at;
    // The wall time as picked: a UTC value with the same fields reads the same in any phone's locale.
    final text = at == null
        ? l.nightPickTime
        : fmtNightWhen(context, DateTime.utc(at.year, at.month, at.day, at.hour, at.minute));
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: at == null ? p.line : p.ink, width: 1.2),
          ),
          child: Row(
            children: [
              TkIcon(Tk.calendar, size: 20, color: p.inkSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontWeight: at == null ? FontWeight.w500 : FontWeight.w700,
                    color: at == null ? p.inkSoft : p.ink,
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

/// Films of the group's list to pick from, and a way into the whole catalog.
class _FilmPick extends StatelessWidget {
  const _FilmPick({required this.films, required this.taken});
  final List<Film> films;
  final Set<String> taken;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final rest = [
      for (final f in films)
        if (!taken.contains(f.id)) f,
    ];
    return SheetBody(
      title: l.nightAddFilm,
      children: [
        ListTile(
          key: const Key('night-search-all'),
          contentPadding: EdgeInsets.zero,
          leading: TkIcon(Tk.search, size: 22, color: p.accent),
          title: Text(l.nightSearchAll, style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => Navigator.pop(context, true),
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            l.nightFromList,
            style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
          ),
          const SizedBox(height: 4),
          for (final f in rest)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Poster(f, width: 34, radius: 2),
              title: Text(
                f.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: f.year == null ? null : Text('${f.year}', style: TextStyle(color: p.inkSoft)),
              onTap: () => Navigator.pop(context, f),
            ),
        ],
      ],
    );
  }
}
