import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/data/night.dart';

import 'helpers.dart';

NightOption filmOpt(String id, int pos, {int approvals = 0}) =>
    NightOption(id: id, kind: OptionKind.film, position: pos, film: film(id), approvals: approvals);

NightOption slotOpt(String id, int pos, DateTime at, {int approvals = 0}) =>
    NightOption(id: id, kind: OptionKind.slot, position: pos, startsAt: at, approvals: approvals);

void main() {
  group('pollTally', () {
    final options = [
      filmOpt('f0', 0),
      filmOpt('f1', 1),
      slotOpt('s0', 0, DateTime.utc(2026, 10, 3, 14)),
      slotOpt('s1', 1, DateTime.utc(2026, 10, 4, 14)),
    ];

    test('counts approvals and picks the most approved film and slot', () {
      final r = pollTally(options, {
        'm1': {'f1', 's1'},
        'm2': {'f1', 's0'},
        'm3': {'f0', 's1'},
      });
      expect(r.approvals, {'f0': 1, 'f1': 2, 's0': 1, 's1': 2});
      expect(r.film!.id, 'f1');
      expect(r.slot!.id, 's1');
    });

    test('a tie goes to the lowest position, for films and slots alike', () {
      final r = pollTally(options, {
        'm1': {'f0', 's1'},
        'm2': {'f1', 's0'},
      });
      expect(r.film!.id, 'f0');
      expect(r.slot!.id, 's0');
      // Same with the options listed in another order.
      expect(
        pollTally(options.reversed.toList(), {
          'm1': {'f0', 's1'},
          'm2': {'f1', 's0'},
        }).film!.id,
        'f0',
      );
    });

    test('no votes: the first film and slot win', () {
      final r = pollTally(options, {});
      expect((r.film!.id, r.slot!.id), ('f0', 's0'));
      expect(r.approvals.values, everyElement(0));
    });

    test('without a vote map the options own counts are used (a shared night)', () {
      final r = pollTally([
        filmOpt('f0', 0, approvals: 1),
        filmOpt('f1', 1, approvals: 3),
        slotOpt('s0', 0, DateTime.utc(2026, 10, 3)),
      ]);
      expect(r.film!.id, 'f1');
      expect(r.approvals['f1'], 3);
    });

    test('a poll with only films has no leading slot', () {
      expect(pollTally([filmOpt('f0', 0)]).slot, isNull);
    });
  });

  group('reminderTimes', () {
    final start = DateTime.utc(2026, 10, 10, 18);

    test('a day and two hours before', () {
      final r = reminderTimes(start, start.subtract(const Duration(days: 3)));
      expect([for (final t in r) t.slot], [0, 1]);
      expect(r[0].at, DateTime.utc(2026, 10, 9, 18));
      expect(r[1].at, DateTime.utc(2026, 10, 10, 16));
      expect(r[0].at.isUtc, isTrue);
    });

    test('past times are dropped, and a time equal to now is past', () {
      expect([for (final t in reminderTimes(start, start.subtract(const Duration(hours: 10)))) t.slot], [1]);
      expect(reminderTimes(start, DateTime.utc(2026, 10, 10, 16)), isEmpty);
      expect(reminderTimes(start, start.subtract(const Duration(hours: 1))), isEmpty);
      expect(reminderTimes(start, start.add(const Duration(days: 1))), isEmpty);
    });
  });

  group('icsFor', () {
    NightEvent event({String title = 'Dune', String? place, DateTime? at}) => NightEvent(
      film: film('Q1', title: title),
      startsAt: at ?? DateTime.utc(2026, 10, 10, 18, 30, 15),
      tzOffsetMin: 330,
      place: place,
    );
    final stamp = DateTime.utc(2026, 10, 1, 9, 5, 7);

    /// Content lines with the folds taken out.
    List<String> unfold(String ics) => ics.replaceAll('\r\n ', '').split('\r\n');

    test('has CRLF everywhere, the calendar frame, UTC times and a UID', () {
      final ics = icsFor(
        event(place: 'Home'),
        'Friday gang',
        uid: 'night-abc@talkies',
        stamp: stamp,
      );
      expect(ics.endsWith('END:VCALENDAR\r\n'), isTrue);
      expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')), reason: 'no bare LF');
      expect(ics.replaceAll('\r\n', ''), isNot(contains('\r')), reason: 'no bare CR');
      final lines = unfold(ics)..removeLast();
      expect(lines.first, 'BEGIN:VCALENDAR');
      expect(lines, containsAllInOrder(['VERSION:2.0', 'BEGIN:VEVENT', 'END:VEVENT', 'END:VCALENDAR']));
      expect(lines, contains('UID:night-abc@talkies'));
      expect(lines, contains('DTSTAMP:20261001T090507Z'));
      expect(lines, contains('DTSTART:20261010T183015Z'));
      expect(lines, contains('DTEND:20261010T203015Z'), reason: 'two hours long');
      expect(lines, contains('SUMMARY:Dune'));
      expect(lines, contains('LOCATION:Home'));
      expect(lines, contains('DESCRIPTION:Friday gang'));
    });

    test('a local start time is written in UTC', () {
      final local = DateTime(2026, 10, 10, 18, 30);
      final line = unfold(icsFor(event(at: local), 'g', stamp: stamp)).firstWhere((l) => l.startsWith('DTSTART'));
      expect(line, endsWith('Z'));
      expect(line, 'DTSTART:${local.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]|\.\d+'), '')}');
    });

    test('escapes backslash, semicolon, comma and line breaks, and leaves no empty place', () {
      final ics = icsFor(
        event(title: r'A;B,C\D', place: ' '),
        'Line one\nLine two\r\nthree',
        stamp: stamp,
      );
      final lines = unfold(ics);
      expect(lines, contains(r'SUMMARY:A\;B\,C\\D'));
      expect(lines, contains(r'DESCRIPTION:Line one\nLine two\nthree'));
      expect(lines.any((l) => l.startsWith('LOCATION')), isFalse);
    });

    test('folds at 75 octets, never inside a character, and unfolds to the same text', () {
      final long = 'सिनेपोलिस, अंधेरी वेस्ट: ${'ताज महल पैलेस ' * 12}'; // Devanagari: 3 octets a letter
      final emoji = '🎬' * 40; // 4 octets, outside the BMP
      for (final place in [long, emoji, 'x' * 300, 'y' * 62]) {
        final ics = icsFor(event(place: place), 'g', stamp: stamp);
        for (final physical in ics.split('\r\n')) {
          expect(utf8.encode(physical).length, lessThanOrEqualTo(75), reason: physical);
          expect(physical.codeUnits, everyElement(isNot(0xFFFD)));
        }
        final location = unfold(ics).firstWhere((l) => l.startsWith('LOCATION:'));
        expect(location, 'LOCATION:${place.trim().replaceAll(',', r'\,').replaceAll(';', r'\;')}');
      }
      // A fold line starts with one space and holds the rest.
      final folded = icsFor(event(place: 'z' * 200), 'g', stamp: stamp).split('\r\n');
      final i = folded.indexWhere((l) => l.startsWith('LOCATION'));
      expect(utf8.encode(folded[i]).length, 75);
      expect(folded[i + 1], startsWith(' '));
      expect(utf8.encode(folded[i + 1]).length, 75);
    });

    test('the UID is stable for one event', () {
      final a = icsFor(event(), 'g', stamp: stamp);
      expect(
        icsFor(event(), 'other group', stamp: DateTime.utc(2030)),
        contains(unfold(a).firstWhere((l) => l.startsWith('UID:'))),
      );
    });
  });

  group('wrapDraft', () {
    final members = [
      const Member(id: 'ben', name: 'Ben', guest: true),
      const Member(id: 'me', name: '', owner: true, me: true),
      const Member(id: 'chitra', name: 'Chitra', guest: true),
      const Member(id: 'dev', name: 'Dev, Jr', guest: true),
      const Member(id: 'eli', name: 'Eli', guest: true),
    ];
    Night night({Map<String, Rsvp> rsvps = const {}, DateTime? at, int tz = 330, String? place = 'Asha home'}) => Night(
      id: 'n1',
      crewId: 'c1',
      status: NightStatus.set,
      rsvps: rsvps,
      event: NightEvent(
        film: film('Q9', title: 'Pushpa'),
        startsAt: at ?? DateTime.utc(2026, 10, 10, 13),
        tzOffsetMin: tz,
        place: place,
      ),
    );

    test('my seat follows the members who said yes; the others become company', () {
      final d = wrapDraft(
        night(rsvps: {'ben': Rsvp.yes, 'chitra': Rsvp.no, 'dev': Rsvp.yes, 'eli': Rsvp.maybe}),
        members,
        'C',
        4,
      );
      // Going, in member order: Ben, me, Dev. I am second.
      expect(d.seat, 'C5');
      expect(d.company, 'Ben, Dev Jr', reason: 'commas leave names: the company list is comma separated');
      expect(d.place, 'Asha home');
      expect(d.precision, DatePrecision.day);
      expect(d.date, DateTime(2026, 10, 10));
      expect(d.rating, isNull);
    });

    test('alone: first seat, no company', () {
      final d = wrapDraft(night(), members, 'A', 1);
      expect(d.seat, 'A1');
      expect(d.company, isNull);
    });

    test('the date is the group day, which can differ from the UTC day', () {
      // 21:00 UTC is 02:30 the next day at +05:30.
      expect(wrapDraft(night(at: DateTime.utc(2026, 10, 10, 21)), members, 'A', 1).date, DateTime(2026, 10, 11));
      // 01:00 UTC is 20:00 the day before at -05:00.
      expect(
        wrapDraft(night(at: DateTime.utc(2026, 10, 11, 1), tz: -300), members, 'A', 1).date,
        DateTime(2026, 10, 10),
      );
    });

    test('the draft makes a valid stub with a day date', () {
      final d = wrapDraft(night(rsvps: {'ben': Rsvp.yes}), members, 'B', 7);
      final stub = d.toStub(id: 's', no: 1, filmId: 'Q9', created: DateTime(2026, 10, 11));
      expect((stub.seat, stub.company, stub.hasDate), ('B8', 'Ben', true));
    });
  });

  group('companyNames', () {
    Stub stub(int i, String? company) => Stub(
      id: 's$i',
      no: i,
      filmId: 'Q$i',
      created: DateTime(2026),
      date: DateTime(2026, 1, 1 + i),
      company: company,
    );

    test('splits on comma, & and "and", trims, counts, most frequent first', () {
      final d = Diary(
        stubs: [
          stub(1, 'Asha, Ben'),
          stub(2, 'Asha & Chitra'),
          stub(3, 'Ben and Asha'),
          stub(4, 'asha'),
          stub(5, ' Dev '),
          stub(6, null),
          stub(7, ''),
          stub(8, 'Anand and Priya Sandhya'),
        ],
      );
      expect(companyNames(d), ['Asha', 'Ben', 'Anand', 'Chitra', 'Dev', 'Priya Sandhya']);
    });

    test('an empty diary has no names', () {
      expect(companyNames(const Diary()), isEmpty);
    });
  });
}
