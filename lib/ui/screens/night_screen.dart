import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crews.dart';
import '../../data/models.dart';
import '../../data/night.dart';
import '../../state/crews.dart';
import '../../state/providers.dart';
import '../avatar.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../online_gate.dart';
import '../sharer.dart';
import '../swipe_card.dart' show voteInk;
import '../theme.dart';
import '../together_widgets.dart';
import '../widgets.dart';

/// One movie night, as a ticket. A poll shows what the group votes on. A night
/// that is set shows who is coming, and offers a reminder, a calendar file and,
/// once it has started, the wrap-up that turns it into stubs.
class NightScreen extends ConsumerStatefulWidget {
  const NightScreen({super.key, required this.crewId, required this.nightId});
  final String crewId, nightId;

  @override
  ConsumerState<NightScreen> createState() => _NightScreenState();
}

class _NightScreenState extends ConsumerState<NightScreen> {
  /// Kept in a field: `ref` cannot be read in dispose.
  late final CrewController _ctl;

  /// The member the next vote is for. Null is the person who holds the phone.
  String? _voter;

  /// The member the next reply is for.
  String? _replier;
  String? _note;
  String? _remindNote;
  int? _wrapped;

  @override
  void initState() {
    super.initState();
    _ctl = ref.read(crewProvider(widget.crewId).notifier);
    // A shared night may have changed since the list loaded: ask again on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(crewProvider(widget.crewId)).crew.shared) unawaited(_ctl.refresh());
    });
  }

  /// Shows the reason an action did not happen, or clears the line after one that worked.
  void _took(Outcome<Object?> r) {
    if (!mounted) return;
    setState(() => _note = r.ok ? null : refusalText(context, r.refusal!));
  }

  /// Members the phone may act for. A local group knows everyone. In a shared group: me, and the guests
  /// when the owner votes, or when the host or owner replies.
  List<Member> _actors(Crew crew, Night night, {required bool votes}) {
    if (!crew.shared) return crew.members;
    final may = votes ? crew.isOwner : crew.isHost(night);
    return [if (crew.me != null) crew.me!, if (may) ...crew.members.where((m) => m.guest)];
  }

  String? _pick(String? chosen, List<Member> actors, Crew crew) =>
      chosen != null && actors.any((m) => m.id == chosen) ? chosen : crew.me?.id ?? actors.firstOrNull?.id;

  Future<void> _toggle(Night night, String who, String option) async {
    final votes = {...(night.votes[who] ?? const <String>{})};
    if (!votes.remove(option)) votes.add(option);
    _took(await _ctl.vote(night.id, who, votes));
  }

  Future<void> _remind(Crew crew, Night night, bool on) async {
    final l = context.l;
    final film = night.event?.film.title ?? '';
    final wall = nightWall(night);
    final ok = await _ctl.setReminder(
      night.id,
      on,
      title: l.nightTitle,
      dayBody: l.nightReminderDay(film, crew.name, wall == null ? '' : fmtNightTime(context, wall)),
      hourBody: l.nightReminderHour(film, crew.name),
    );
    if (mounted) setState(() => _remindNote = on && !ok ? l.nightRemindRefused : null);
  }

  /// The calendar file, named after the film.
  Future<void> _ics(BuildContext anchor, Crew crew, Night night) async {
    final event = night.event;
    if (event == null) return;
    final l = context.l;
    final name = '${_fileName(event.film.title)}.ics';
    final bytes = Uint8List.fromList(utf8.encode(icsFor(event, crew.name, uid: 'night-${night.id}@talkies')));
    final origin = shareOrigin(anchor);
    try {
      await ref.read(sharerProvider).file(bytes, name, 'text/calendar', origin: origin);
    } catch (_) {
      if (mounted) setState(() => _note = l.nightIcsFailed);
    }
  }

  static String _fileName(String title) {
    final s = title.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'movie-night' : s;
  }

  Future<void> _wrap(Crew crew, Night night) async {
    // The server writes one stub for each member with an account who said yes. A local group writes mine.
    final made = crew.shared
        ? [
            for (final e in night.rsvps.entries)
              if (e.value == Rsvp.yes && crew.member(e.key)?.guest == false) e.key,
          ].length
        : 1;
    final r = await _ctl.wrapUp(night.id);
    if (!mounted) return;
    setState(() {
      _note = r.ok ? null : refusalText(context, r.refusal!);
      if (r.ok) _wrapped = made;
    });
  }

  Future<void> _delete() async {
    final l = context.l;
    final p = Palette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.nightDeleteQ, style: disp(24, p.ink)),
        content: Text(l.nightDeleteBody, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              l.delete,
              style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await _ctl.deleteNight(widget.nightId);
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).maybePop();
    } else {
      _took(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(crewProvider(widget.crewId));
    final crew = st.crew;
    final night = crew.night(widget.nightId);
    final p = Palette.of(context);
    final l = context.l;
    final back = TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.pop(context));
    if (night == null) {
      return Scaffold(
        appBar: AppBar(leading: back),
        body: st.loading ? const Center(child: CircularProgressIndicator()) : EmptyNote(l.nightGone),
      );
    }
    final now = ref.watch(nowProvider)();
    final host = crew.isHost(night);
    final start = night.event?.startsAt;
    final started = start != null && !start.isAfter(now);
    final unreachable = crew.shared && st.offline;

    return Scaffold(
      appBar: AppBar(leading: back),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          _Header(crew: crew, night: night),
          if (st.loading)
            const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2)),
          if (_note != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Note(_note!, strong: true)),
          if (unreachable)
            CantReach(onRetry: () => _ctl.refresh())
          else if (night.status == NightStatus.poll)
            ..._poll(crew, night, host)
          else ...[
            ..._replies(crew, night),
            if (night.status == NightStatus.set && !started) ..._reminder(crew, night),
            if (night.event != null) ..._calendar(crew, night),
            if (night.status == NightStatus.set && started && host) ..._wrapUp(crew, night),
            if (_wrapped != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Note(
                  // Shared: the server's created/skipped result never reaches the phone, so this is the
                  // honest count of yes replies, not what the server wrote. A local night writes mine.
                  crew.shared ? l.nightWrapExpect(_wrapped!) : l.nightWrapDone(_wrapped!),
                  strong: true,
                ),
              ),
          ],
          if (host && !unreachable)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('night-delete'),
                  onPressed: _delete,
                  child: Text(
                    l.nightDelete,
                    style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -- poll

  List<Widget> _poll(Crew crew, Night night, bool host) {
    final p = Palette.of(context);
    final l = context.l;
    final actors = _actors(crew, night, votes: true);
    final who = _pick(_voter, actors, crew);
    final mine = who == null ? const <String>{} : (night.votes[who] ?? const <String>{});
    final lead = pollTally(night.options);
    final films = night.films, slots = night.slots;

    Widget rows(List<NightOption> options, NightOption? winner) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (final o in options)
            _ApprovalRow(
              key: ValueKey(o.id),
              option: o,
              selected: mine.contains(o.id),
              leading: winner?.id == o.id && o.approvals > 0,
              label: o.kind == OptionKind.film
                  ? (o.film?.title ?? '?')
                  : (o.startsAt == null ? '?' : fmtNightWhen(context, wallClockOf(o.startsAt!, night.tzOffsetMin))),
              onTap: who == null ? null : () => _toggle(night, who, o.id),
            ),
        ],
      ),
    );

    return [
      SectionTitle(l.togetherNightPoll),
      if (actors.length > 1 && who != null)
        _MemberPicker(
          label: l.nightVoteAs,
          members: actors,
          current: who,
          onPick: (m) {
            setState(() => _voter = m.id);
            if (crew.shared && !m.me) unawaited(_ctl.loadNightVotes(night.id, m.id));
          },
        ),
      if (films.length > 1) ...[_Sub(l.nightFilms), rows(films, lead.film)],
      if (slots.length > 1) ...[_Sub(l.nightTimes), rows(slots, lead.slot)],
      if (films.length == 1 || slots.length == 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Text(
            [
              if (films.length == 1 && films.first.film != null) films.first.film!.title,
              if (slots.length == 1 && slots.first.startsAt != null)
                fmtNightWhen(context, wallClockOf(slots.first.startsAt!, night.tzOffsetMin)),
            ].join('  ·  '),
            style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w700),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: host
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SlabButton(
                    key: const Key('night-close'),
                    label: l.nightClosePoll,
                    icon: Tk.check,
                    onPressed: () async => _took(await _ctl.closePoll(night.id)),
                  ),
                  Note(l.nightCloseNote),
                ],
              )
            : Text(l.nightWaitNote, style: TextStyle(color: p.inkSoft, height: 1.4)),
      ),
    ];
  }

  // -- replies

  List<Widget> _replies(Crew crew, Night night) {
    final p = Palette.of(context);
    final l = context.l;
    final canReply = night.status == NightStatus.set;
    final actors = _actors(crew, night, votes: false);
    final who = _pick(_replier, actors, crew);
    final mine = who == null ? null : night.rsvps[who];
    return [
      SectionTitle(l.nightRsvp),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TicketPaper(
          color: p.paper(VenueType.other),
          shape: const TicketBorder(radius: 6),
          perforate: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [for (final m in crew.members) _ReplyRow(member: m, reply: night.rsvps[m.id])],
            ),
          ),
        ),
      ),
      if (canReply) ...[
        if (actors.length > 1 && who != null)
          _MemberPicker(
            label: l.nightReplyFor,
            members: actors,
            current: who,
            onPick: (m) => setState(() => _replier = m.id),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (r, label) in [(Rsvp.yes, l.nightYes), (Rsvp.maybe, l.nightMaybe), (Rsvp.no, l.nightNo)])
                TapBox(
                  key: Key('rsvp-${r.name}'),
                  label: label,
                  dense: false,
                  selected: mine == r,
                  onTap: who == null ? () {} : () async => _took(await _ctl.rsvp(night.id, who, r)),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  // -- reminder, calendar, wrap-up

  List<Widget> _reminder(Crew crew, Night night) {
    final p = Palette.of(context);
    final l = context.l;
    final on = ref.watch(reminderOnProvider(night.id));
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
        child: SwitchListTile(
          key: const Key('night-remind'),
          contentPadding: EdgeInsets.zero,
          secondary: TkIcon(Tk.bell, size: 22, color: p.accent),
          title: Text(l.nightRemind, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(l.nightRemindHint, style: TextStyle(color: p.inkSoft, height: 1.35)),
          value: on,
          onChanged: (v) => _remind(crew, night, v),
        ),
      ),
      if (_remindNote != null)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Note(_remindNote!, strong: true)),
    ];
  }

  List<Widget> _calendar(Crew crew, Night night) {
    final p = Palette.of(context);
    final l = context.l;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Builder(
          builder: (anchor) => ListTile(
            key: const Key('night-ics'),
            leading: TkIcon(Tk.calendar, size: 22, color: p.accent),
            title: Text(l.nightAddCalendar, style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => _ics(anchor, crew, night),
          ),
        ),
      ),
    ];
  }

  List<Widget> _wrapUp(Crew crew, Night night) {
    final l = context.l;
    return [
      SectionTitle(l.nightWrap),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.nightWrapNote, style: TextStyle(color: Palette.of(context).inkSoft, height: 1.4)),
            const SizedBox(height: 12),
            SlabButton(
              key: const Key('night-wrap'),
              label: l.nightWrap,
              icon: Tk.stubs,
              onPressed: () => _wrap(crew, night),
            ),
          ],
        ),
      ),
    ];
  }
}

/// A small heading inside a section.
class _Sub extends StatelessWidget {
  const _Sub(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
    child: Text(
      text,
      style: TextStyle(fontWeight: FontWeight.w700, color: Palette.of(context).ink),
    ),
  );
}

/// "Vote as" or "Reply for": the members the phone may act for.
class _MemberPicker extends StatelessWidget {
  const _MemberPicker({required this.label, required this.members, required this.current, required this.onPick});
  final String label;
  final List<Member> members;
  final String current;
  final ValueChanged<Member> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: Palette.of(context).ink),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in members)
                TapBox(
                  key: ValueKey('actor-${m.id}'),
                  label: memberName(context, m),
                  selected: m.id == current,
                  onTap: () => onPick(m),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A film or a time of a poll as a ticket class box: ink when approved, with its count.
class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({
    super.key,
    required this.option,
    required this.selected,
    required this.leading,
    required this.label,
    required this.onTap,
  });
  final NightOption option;
  final bool selected, leading;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final fg = selected ? p.wall : p.ink;
    final film = option.film;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        button: true,
        checked: selected,
        label: '$label, ${l.nightVotes(option.approvals)}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(3),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? p.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: selected ? p.ink : p.line, width: 1.2),
            ),
            child: Row(
              children: [
                if (film != null) ...[Poster(film, width: 34, radius: 2), const SizedBox(width: 12)],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: fg,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // The leader's count takes the accent; on ink it stays in the wall's tone.
                Text(
                  '${option.approvals}',
                  style: disp(26, selected ? p.wall : (leading ? p.accent : p.inkSoft), spacing: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One member on the guest list: their stamp, their name and their reply as a rubber stamp.
class _ReplyRow extends StatelessWidget {
  const _ReplyRow({required this.member, required this.reply});
  final Member member;
  final Rsvp? reply;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final name = memberName(context, member);
    final (word, ink) = switch (reply) {
      Rsvp.yes => (l.nightYes, voteInk(Vote.want)),
      Rsvp.maybe => (l.nightMaybe, accents[9].color),
      Rsvp.no => (l.nightNo, voteInk(Vote.skip)),
      null => (null, paperInkSoft),
    };
    return Semantics(
      label: '$name, ${word ?? l.nightNoReply}',
      excludeSemantics: true,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Avatar(name: name, ink: member.ink, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: paperInk),
              ),
            ),
            if (word == null)
              Text(
                l.nightNoReply,
                style: const TextStyle(fontSize: 12.5, color: paperInkSoft, fontWeight: FontWeight.w600),
              )
            else
              Stamp(word: word.toUpperCase(), color: ink, size: 54, seed: member.id.hashCode),
          ],
        ),
      ),
    );
  }
}

/// The night as a ticket: film, when and where, with the date, "POLL" or a rubber stamp on the counterfoil.
class _Header extends StatelessWidget {
  const _Header({required this.crew, required this.night});
  final Crew crew;
  final Night night;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final wall = nightWall(night);
    final poll = night.status == NightStatus.poll;
    final done = night.status == NightStatus.done;
    final paper = p.paper(
      poll
          ? VenueType.ott
          : done
          ? VenueType.other
          : VenueType.cinema,
    );
    final film = night.film;
    final title = poll
        ? [for (final o in night.films) o.film?.title ?? '?'].join('  ·  ')
        : (film?.title ?? l.nightTitle);
    final place = (night.event?.place ?? night.place)?.trim() ?? '';
    final when = poll ? l.nightPollOpen : (wall == null ? '' : fmtNightWhen(context, wall));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Semantics(
        container: true,
        label: [title, if (when.isNotEmpty) when, if (place.isNotEmpty) place, crew.name].join(', '),
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, box) {
              // A 320 dp phone leaves 288 dp: a smaller poster and counterfoil keep room for the words.
              final narrow = box.maxWidth < 330;
              final posterW = narrow ? 62.0 : 82.0;
              final stub = narrow ? 92.0 : 104.0;
              return TicketPaper(
                color: paper,
                shape: TicketBorder(radius: 8, notch: 9, notchFromRight: stub),
                child: ConstrainedBox(
                  // At least 164 tall. Long titles and larger system text make the ticket taller, never clipped.
                  constraints: const BoxConstraints(minHeight: 164),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
                        child: film == null ? SizedBox(width: posterW) : Poster(film, width: posterW, radius: 3),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.toUpperCase(),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: disp(24, paperInk, spacing: 0.5, height: 1.05),
                              ),
                              if (when.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  when.toUpperCase(),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: disp(16, serialRed, spacing: 0.8, height: 1.1),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                [if (place.isNotEmpty) place, crew.name].join('  ·  '),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: paperInkSoft,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: stub,
                        child: Center(
                          child: _Counterfoil(night: night, wall: wall),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Counterfoil extends StatelessWidget {
  const _Counterfoil({required this.night, required this.wall});
  final Night night;
  final DateTime? wall;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final w = wall;
    switch (night.status) {
      case NightStatus.poll:
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(l.togetherNightPoll.toUpperCase(), style: disp(30, serialRed, spacing: 1)),
          ),
        );
      case NightStatus.done:
        // The stamp lands when the ticket opens, as the wrap-up stamps it.
        return w == null
            ? const SizedBox.shrink()
            : StampPress(
                child: Stamp(
                  word: l.stampWatched,
                  line: fmtTicketDate(w),
                  color: serialRed,
                  size: 84,
                  seed: night.id.hashCode,
                ),
              );
      case NightStatus.set:
        if (w == null) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(fmtMonthShort(context, w).toUpperCase(), style: disp(15, paperInkSoft, spacing: 1)),
            Text('${w.day}', style: disp(46, serialRed, spacing: 0.5, height: 1.0)),
            Text(fmtNightTime(context, w), style: disp(14, paperInk, spacing: 0.5)),
          ],
        );
    }
  }
}
