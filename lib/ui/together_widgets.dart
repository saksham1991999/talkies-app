import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/crews.dart';
import '../data/models.dart';
import '../state/crews.dart';
import '../state/providers.dart';
import 'avatar.dart';
import 'common.dart';
import 'format.dart';
import 'icons.dart';
import 'screens/crew_screen.dart';
import 'screens/night_screen.dart';
import 'theme.dart';
import 'widgets.dart';

// Pieces the Together screens share: group and night tickets, the member
// counterfoil, a flat button in two inks, and the words for times and refusals.

void openCrew(BuildContext c, String crewId) => push(c, CrewScreen(crewId: crewId));
void openNight(BuildContext c, String crewId, String nightId) => push(c, NightScreen(crewId: crewId, nightId: nightId));

/// Sends the swipes of a shared group that still wait, as its screen closes. A call that comes after the app's
/// providers are gone (the app is closing too) fails quietly: there is nothing left to send them with.
void flushSwipesSoon(CrewController group) => unawaited(group.flushSwipes().then<void>((_) {}, onError: (_) {}));

// ---------------------------------------------------------------------------
// Words

/// The name to show for a member. The phone holder who gave no name is "You".
String memberName(BuildContext c, Member m) {
  final n = m.name.trim();
  if (n.isNotEmpty) return n;
  return m.me ? c.l.togetherYou : '?';
}

/// One calm sentence for each reason an action did not happen.
String refusalText(BuildContext c, Refusal r) {
  final l = c.l;
  return switch (r) {
    Refusal.offline => l.togetherRefusalOffline,
    Refusal.nameTaken => l.togetherRefusalNameTaken,
    Refusal.groupFull => l.togetherRefusalGroupFull,
    Refusal.listFull => l.togetherRefusalListFull,
    Refusal.groupLimit => l.togetherRefusalGroupLimit,
    Refusal.invalidCode => l.togetherRefusalInvalidCode,
    Refusal.rateLimited => l.togetherRefusalRateLimited,
    Refusal.notAllowed => l.togetherRefusalNotAllowed,
    Refusal.notFound => l.togetherRefusalNotFound,
    Refusal.closed => l.togetherRefusalClosed,
    Refusal.invalid => l.togetherRefusalInvalid,
    Refusal.other => l.togetherRefusalOther,
  };
}

// ---------------------------------------------------------------------------
// Times. A night belongs to its group's clock: a UTC instant plus the offset the
// group had when the night was made. Everyone reads the same wall time.

DateTime wallClockOf(DateTime utc, int tzOffsetMin) => utc.toUtc().add(Duration(minutes: tzOffsetMin));

/// When [n] starts on its group's clock: the decided time, else the earliest candidate.
DateTime? nightWall(Night n) {
  final e = n.event;
  if (e != null) return e.wallClock;
  final at = n.when;
  return at == null ? null : wallClockOf(at, n.tzOffsetMin);
}

/// The calendar days [n] occupies: its day once set, else each day of its candidate times.
Set<DateTime> nightDays(Night n) {
  DateTime day(DateTime w) => DateTime(w.year, w.month, w.day);
  final e = n.event;
  if (e != null) return {day(e.wallClock)};
  return {
    for (final s in n.slots)
      if (s.startsAt != null) day(wallClockOf(s.startsAt!, n.tzOffsetMin)),
  };
}

/// Still to come until two hours after the start, the length of a film. The same rule as `nightsProvider`.
bool nightIsAhead(Night n, DateTime now) {
  final t = n.when;
  return t == null || t.add(const Duration(hours: 2)).isAfter(now);
}

/// "Sat, 3 Oct": the weekday and [fmtShort], in the viewer's language.
String fmtNightDay(BuildContext c, DateTime wall) => '${DateFormat.E(c.fmtLocale).format(wall)}, ${fmtShort(c, wall)}';
String fmtNightTime(BuildContext c, DateTime wall) => DateFormat.jm(c.fmtLocale).format(wall);
String fmtNightWhen(BuildContext c, DateTime wall) => '${fmtNightDay(c, wall)}, ${fmtNightTime(c, wall)}';

/// "Oct", in the viewer's language.
String fmtMonthShort(BuildContext c, DateTime wall) => DateFormat('MMM', c.fmtLocale).format(wall);

/// The soonest night of [crew] still to come and not wrapped up, on the group's clock.
DateTime? nextNightOf(Crew crew, DateTime now) {
  final times = [
    for (final n in crew.nights)
      if (n.status != NightStatus.done && n.when != null && nightIsAhead(n, now)) nightWall(n)!,
  ]..sort();
  return times.firstOrNull;
}

// ---------------------------------------------------------------------------
// Sheets

/// Opens a bottom sheet with the house settings: scrolls, drag handle, full height when needed.
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(context: context, isScrollControlled: true, showDragHandle: true, builder: builder);

/// Body of a bottom sheet. It scrolls, clears the keyboard and the home bar, and keeps the 20 dp gutter.
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            // Full width, so a slab or a field fills the sheet and is easy to hit.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(title!.toUpperCase(), style: disp(24, p.ink)),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// A calm line of text under a field or a button: what went wrong, or what to do next.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.strong = false});
  final String text;

  /// Ink instead of the quiet tone: for a refusal the person must read.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.4,
          color: strong ? p.ink : p.inkSoft,
          fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons

/// An [OptionBox] with a hit area 44 dp tall: the choices made while a phone is passed round are small boxes
/// and must still be easy to hit. The box keeps its look; only the area that answers a tap grows.
class TapBox extends StatelessWidget {
  const TapBox({super.key, required this.label, required this.selected, required this.onTap, this.dense = true});
  final String label;
  final bool selected, dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          child: OptionBox(label: label, selected: selected, dense: dense, onTap: onTap),
        ),
      ),
    ),
  );
}

enum SlabTone { accent, velvet, paper }

/// A flat slab like [InkButton], in the accent ink, in velvet, or in ticket paper (for a velvet wall). Two
/// actions next to each other differ by ink, not by a fill against an outline. It never moves.
class SlabButton extends StatelessWidget {
  const SlabButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = SlabTone.accent,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Tk? icon;
  final SlabTone tone;

  /// Shows a small progress mark and ignores taps.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final bg = switch (tone) {
      SlabTone.accent => p.accent,
      SlabTone.velvet => p.velvet,
      SlabTone.paper => p.paper(VenueType.ott),
    };
    final fg = switch (tone) {
      SlabTone.accent => p.onAccent,
      SlabTone.velvet => p.onVelvet,
      SlabTone.paper => paperInk,
    };
    return SizedBox(
      height: 50,
      child: TextButton(
        onPressed: busy ? null : onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          // Disabled reads as plain print on a faint slab: the label still stands clear of what is behind it.
          disabledBackgroundColor: p.ink.withValues(alpha: 0.12),
          disabledForegroundColor: p.inkSoft,
          // Velvet is close to the wall in dark mode: its own light edge keeps the slab readable.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: tone == SlabTone.velvet ? BorderSide(color: p.onVelvet.withValues(alpha: 0.22)) : BorderSide.none,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else if (icon != null)
              TkIcon(icon!, size: 20, color: fg),
            if (busy || icon != null) const SizedBox(width: 8),
            Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, style: disp(17, fg, spacing: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tickets

/// Up to [max] member stamps in two columns and "+N" for the rest: the counterfoil of a group ticket.
class MemberStamps extends StatelessWidget {
  const MemberStamps(this.members, {super.key, this.size = 28, this.max = 4});
  final List<Member> members;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(max).toList();
    final more = members.length - shown.length;
    Widget stamp(Member m) => Avatar(name: memberName(context, m), ink: m.ink, size: size);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                stamp(shown[i]),
                if (i + 1 < shown.length) ...[const SizedBox(width: 4), stamp(shown[i + 1])],
              ],
            ),
          ),
        if (more > 0) Text('+$more', style: disp(14, paperInk, spacing: 0.4)),
      ],
    );
  }
}

/// A group as a ticket: the name in the display face, a quiet line, and the members on the counterfoil.
/// The paper colour comes from the group's id, so each group keeps its own class of ticket.
class CrewTicket extends ConsumerWidget {
  const CrewTicket(this.crew, {super.key, required this.onTap});
  final Crew crew;
  final VoidCallback onTap;

  static const _stub = 88.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final l = context.l;
    final next = nextNightOf(crew, ref.watch(nowProvider)());
    final quiet = [
      // A shared group's list loads when its screen opens: until then an empty list means "unknown".
      if (!crew.shared || crew.films.isNotEmpty) l.togetherFilmsCount(crew.films.length),
      if (next != null) l.togetherNextNightShort(fmtNightDay(context, next)),
      if (crew.shared) l.togetherShared,
    ].join('  ·  ');
    final hash = crew.id.codeUnits.fold(0, (a, c) => (a * 31 + c) & 0xffff);
    final paper = p.paper(VenueType.values[hash % VenueType.values.length]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: [crew.name, l.togetherMembersCount(crew.members.length), if (quiet.isNotEmpty) quiet].join(', '),
        child: GestureDetector(
          onTap: onTap,
          child: TicketPaper(
            color: paper,
            shape: const TicketBorder(radius: 6, notch: 7, notchFromRight: _stub),
            child: ConstrainedBox(
              // At least 104 tall. A long name or larger system text makes the ticket taller, never clipped.
              constraints: const BoxConstraints(minHeight: 104),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            crew.name.toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: disp(26, paperInk, spacing: 0.6, height: 1.05),
                          ),
                          if (quiet.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              quiet,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: paperInkSoft, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _stub,
                    child: Center(child: ExcludeSemantics(child: MemberStamps(crew.members))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A night as a ticket: poster, film, when and where in the group's clock, and the date on the counterfoil.
/// A poll is a yellow ticket, a set night a pink one, a night already watched plain paper.
class NightTicket extends ConsumerWidget {
  const NightTicket(this.entry, {super.key, required this.onTap, this.compact = false});
  final NightEntry entry;
  final VoidCallback onTap;

  /// The smaller tile on Home.
  final bool compact;

  static const _stub = 76.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final (crew, night) = (entry.crew, entry.night);
    final film = night.film;
    final wall = nightWall(night);
    final poll = night.status == NightStatus.poll;
    final done = night.status == NightStatus.done;
    final p = Palette.of(context);
    final paper = p.paper(
      poll
          ? VenueType.ott
          : done
          ? VenueType.other
          : VenueType.cinema,
    );
    final title =
        (film?.title ?? l.nightTitle) + (poll && night.films.length > 1 ? '  +${night.films.length - 1}' : '');
    final when = poll ? l.nightPollOpen : (wall == null ? '' : fmtNightWhen(context, wall));
    final where = [
      crew.name,
      if ((night.event?.place ?? night.place) case final String pl when pl.trim().isNotEmpty) pl,
    ];
    final posterW = compact ? 36.0 : 50.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: [title, if (when.isNotEmpty) when, ...where].join(', '),
        child: GestureDetector(
          onTap: onTap,
          child: TicketPaper(
            color: paper,
            shape: const TicketBorder(radius: 6, notch: 7, notchFromRight: _stub),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 88 : 104),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: film == null ? SizedBox(width: posterW) : Poster(film, width: posterW, radius: 3),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: paperInk,
                              height: 1.2,
                            ),
                          ),
                          if (when.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              when.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: disp(15, serialRed, spacing: 0.8, height: 1.1),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            where.join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: paperInkSoft, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _stub,
                    child: Center(
                      child: ExcludeSemantics(
                        child: _Stub(night: night, wall: wall),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the counterfoil of a night ticket prints: the day, "POLL", or "WATCHED".
class _Stub extends StatelessWidget {
  const _Stub({required this.night, required this.wall});
  final Night night;
  final DateTime? wall;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    if (night.status == NightStatus.poll) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(l.togetherNightPoll.toUpperCase(), style: disp(22, serialRed, spacing: 1)),
      );
    }
    final w = wall;
    if (w == null) return const SizedBox.shrink();
    if (night.status == NightStatus.done) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(l.stampWatched, style: disp(15, paperInkSoft, spacing: 1)),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(fmtMonthShort(context, w).toUpperCase(), style: disp(13, paperInkSoft, spacing: 1)),
        Text('${w.day}', style: disp(34, serialRed, spacing: 0.5)),
      ],
    );
  }
}
