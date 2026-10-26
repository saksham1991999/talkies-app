import 'dart:convert';
import 'dart:math';

import '../state/providers.dart' show StubDraft;
import 'crews.dart';

// Pure logic for movie nights: the poll count, reminder times, the calendar
// file and the stub a local night leaves in the diary.

/// How long before the start each reminder fires. The index is the slot.
const reminderLeads = [Duration(days: 1), Duration(hours: 2)];

/// The reminders worth scheduling for a night that starts at [start] (UTC),
/// without the ones already past at [now].
List<({int slot, DateTime at})> reminderTimes(DateTime start, DateTime now) => [
  for (var i = 0; i < reminderLeads.length; i++)
    if (start.subtract(reminderLeads[i]).isAfter(now)) (slot: i, at: start.subtract(reminderLeads[i])),
];

/// Approval counts and the leading film and slot of a poll.
class PollResult {
  const PollResult({required this.approvals, this.film, this.slot});

  /// Option id to the number of members who approved it.
  final Map<String, int> approvals;
  final NightOption? film, slot;
}

/// Counts approvals and picks the winners: the most approved film and slot, a
/// tie going to the lowest position. [votes] (member id to approved option ids)
/// gives the counts when set, else each option's own `approvals` does.
PollResult pollTally(List<NightOption> options, [Map<String, Set<String>>? votes]) {
  final counts = {
    for (final o in options) o.id: votes == null ? o.approvals : votes.values.where((v) => v.contains(o.id)).length,
  };
  NightOption? lead(OptionKind kind) {
    NightOption? best;
    for (final o in options) {
      if (o.kind != kind) continue;
      final (n, bn) = (counts[o.id]!, best == null ? -1 : counts[best.id]!);
      if (best == null || n > bn || (n == bn && o.position < best.position)) best = o;
    }
    return best;
  }

  return PollResult(approvals: counts, film: lead(OptionKind.film), slot: lead(OptionKind.slot));
}

/// An iCalendar (RFC 5545) file for [event]: CRLF lines folded at 75 octets,
/// text escaped, times in UTC, two hours long. Pass the night id as [uid] (for
/// example `night-<id>@talkies`) so importing it again updates the entry. [stamp]
/// is the creation time and defaults to now.
String icsFor(NightEvent event, String groupName, {String? uid, DateTime? stamp}) {
  final start = event.startsAt.toUtc();
  final place = event.place?.trim() ?? '';
  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Talkies//Movie night//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:${uid ?? '${event.film.id}-${start.millisecondsSinceEpoch}@talkies'}',
    'DTSTAMP:${_utc(stamp ?? DateTime.now())}',
    'DTSTART:${_utc(start)}',
    'DTEND:${_utc(start.add(const Duration(hours: 2)))}',
    'SUMMARY:${_escape(event.film.title)}',
    if (place.isNotEmpty) 'LOCATION:${_escape(place)}',
    'DESCRIPTION:${_escape(groupName)}',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

String _utc(DateTime t) {
  final u = t.toUtc();
  String p(int n, [int width = 2]) => n.toString().padLeft(width, '0');
  return '${p(u.year, 4)}${p(u.month)}${p(u.day)}T${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
}

/// TEXT values escape backslash, semicolon, comma and line breaks.
String _escape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll(RegExp(r'\r\n|\r|\n'), r'\n');

/// Folds a line after 75 octets with CRLF and a space, never inside a UTF-8
/// character. The space opens the next line and counts toward its 75.
String _fold(String line) {
  final out = StringBuffer();
  var size = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final n = utf8.encode(ch).length;
    if (size + n > 75) {
      out.write('\r\n ');
      size = 1;
    }
    out.write(ch);
    size += n;
  }
  return out.toString();
}

/// My stub for a local night that was watched: the date of the start on the
/// group's clock, the place, my seat, and the others who came as "who you went
/// with". Those who came are the members who said yes, and me, in member order.
/// Seats run along row [rowLetter] from [firstSeat]. Needs a set night.
StubDraft wrapDraft(Night night, List<Member> members, String rowLetter, int firstSeat) {
  final event = night.event!;
  final going = [
    for (final m in members)
      if (m.me || night.rsvps[m.id] == Rsvp.yes) m,
  ];
  final seat = '$rowLetter${firstSeat + max(0, going.indexWhere((m) => m.me))}';
  final others = [
    for (final m in going)
      if (!m.me) m.name.replaceAll(',', '').trim(),
  ].where((n) => n.isNotEmpty);
  final day = event.wallClock;
  return StubDraft(
    date: DateTime(day.year, day.month, day.day),
    place: event.place,
    seat: seat,
    company: others.isEmpty ? null : others.join(', '),
  );
}
