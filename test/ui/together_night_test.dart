import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/night_editor.dart';
import 'package:talkies/ui/screens/night_screen.dart';
import 'package:talkies/ui/widgets.dart' show Stamp;

import 'together_harness.dart';

final _f1 = tFilm('Q1', title: 'Film 1');
final _f2 = tFilm('Q2', title: 'Film 2');

/// 8 pm in a group whose clock is 5 h 30 min ahead of UTC (India): 14:30 UTC on the third.
final _eight = DateTime.utc(2026, 10, 3, 14, 30);

/// A rubber stamp with this word. Stamps are painted, not text, so a text finder cannot see them.
Finder _stamp(String word) => find.byWidgetPredicate((w) => w is Stamp && w.word == word);

Crew _crew(Rig r, String id) => r.container.read(crewsProvider).crew(id)!;

/// A night that is already set, made the way the editor makes one.
Future<Night> _setNight(Rig r, String id, {String? place = 'Home', DateTime? at}) async {
  final made = await r.container
      .read(crewProvider(id).notifier)
      .createNight(NightCreate(films: [_f1], slots: [at ?? _eight], tzOffsetMin: 330, place: place));
  return made.value!;
}

void main() {
  setUpAll(loadFonts);

  group('the night editor', () {
    testWidgets('posts a poll: two films and a time, voted on by the group', (t) async {
      phoneSize(t, height: 900);
      final r = rig();
      final id = await makeCrew(r, guests: ['Asha']);
      await t.pumpWidget(r.app(NightEditorScreen(crewId: id, films: [_f1, _f2], day: DateTime(2026, 10, 3))));
      await t.pumpAndSettle();
      expect(find.text('Post poll'), findsOneWidget);
      await t.enterText(find.byKey(const Key('night-place')), 'Terrace');
      await t.tap(find.byKey(const Key('night-submit')));
      await t.pumpAndSettle();

      final night = _crew(r, id).nights.single;
      expect(night.status, NightStatus.poll);
      expect([for (final o in night.films) o.film!.id], ['Q1', 'Q2']);
      expect(night.slots, hasLength(1));
      expect(night.place, 'Terrace');
      expect(night.hostId, _crew(r, id).me!.id);

      // The editor made way for the night screen.
      expect(find.byType(NightEditorScreen), findsNothing);
      expect(find.byType(NightScreen), findsOneWidget);
      expect(find.text('POLL OPEN'), findsOneWidget);
      expect(find.text('Film 1'), findsOneWidget);
      expect(find.text('Film 2'), findsOneWidget);
      expect(find.text('No votes'), findsNothing);

      // Me: approve film 1. Then Asha: approve both.
      await t.tap(find.text('Film 1'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('actor-${_crew(r, id).members.last.id}')));
      await t.pumpAndSettle();
      await t.tap(find.text('Film 1'));
      await t.pumpAndSettle();
      await t.tap(find.text('Film 2'));
      await t.pumpAndSettle();
      final voted = _crew(r, id).nights.single;
      expect([for (final o in voted.films) o.approvals], [2, 1]);
      expect(voted.votes[_crew(r, id).members.last.id], {for (final o in voted.films) o.id});

      // The host closes it: the film with the most approvals wins, and the night is set.
      await t.ensureVisible(find.byKey(const Key('night-close')));
      await t.tap(find.byKey(const Key('night-close')));
      await t.pumpAndSettle();
      final set = _crew(r, id).nights.single;
      expect(set.status, NightStatus.set);
      expect(set.event!.film.id, 'Q1');
      expect(find.text('Who is coming'), findsOneWidget);
      expect(r.requests, isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets('one film and one time make a night that is set', (t) async {
      phoneSize(t, height: 900);
      final r = rig();
      final id = await makeCrew(r);
      await t.pumpWidget(r.app(NightEditorScreen(crewId: id, films: [_f1], day: DateTime(2026, 10, 3))));
      await t.pumpAndSettle();
      expect(find.text('Set it'), findsOneWidget);
      expect(find.text('Post poll'), findsNothing);
      await t.tap(find.byKey(const Key('night-submit')));
      await t.pumpAndSettle();

      final night = _crew(r, id).nights.single;
      expect(night.status, NightStatus.set);
      expect(night.event!.film.id, 'Q1');
      expect(find.text('Who is coming'), findsOneWidget);
    });

    testWidgets('asks for a film and a time before it lets go', (t) async {
      phoneSize(t, height: 900);
      final r = rig();
      final id = await makeCrew(r);
      await t.pumpWidget(r.app(NightEditorScreen(crewId: id)));
      await t.pumpAndSettle();
      expect(find.text('Pick at least one film.'), findsOneWidget);
      expect(
        t
            .widget<TextButton>(
              find.descendant(of: find.byKey(const Key('night-submit')), matching: find.byType(TextButton)),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the date and time pickers set a time, and a second time makes a poll', (t) async {
      phoneSize(t, height: 900);
      final r = rig();
      final id = await makeCrew(r);
      await t.pumpWidget(r.app(NightEditorScreen(crewId: id, films: [_f1])));
      await t.pumpAndSettle();
      expect(find.text('Pick a date and time.'), findsOneWidget);

      await t.tap(find.byKey(const Key('night-slot-0')));
      await t.pumpAndSettle();
      await t.tap(find.text('5'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.text('OK')); // the time picker, at its 8:00 PM
      await t.pumpAndSettle();
      expect(find.textContaining('Mon, 5 Oct'), findsOneWidget);
      expect(find.textContaining('8:00'), findsOneWidget);
      expect(find.text('Set it'), findsOneWidget);

      await t.tap(find.byKey(const Key('night-add-time')));
      await t.pumpAndSettle();
      expect(find.text('Post poll'), findsOneWidget, reason: 'two times need a vote');
      await t.tap(find.byKey(const Key('night-slot-1')));
      await t.pumpAndSettle();
      await t.tap(find.text('6'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('night-submit')));
      await t.pumpAndSettle();

      final night = _crew(r, id).nights.single;
      expect(night.status, NightStatus.poll);
      expect(night.slots, hasLength(2));
      expect(night.slots.first.startsAt!.isBefore(night.slots.last.startsAt!), isTrue);
      // Two times show as two rows to vote on.
      expect(find.textContaining('Mon, 5 Oct'), findsOneWidget);
      expect(find.textContaining('Tue, 6 Oct'), findsOneWidget);
    });

    testWidgets('a time earlier today is clamped to after now', (t) async {
      phoneSize(t, height: 900);
      final r = rig();
      final id = await makeCrew(r);
      await t.pumpWidget(r.app(NightEditorScreen(crewId: id, films: [_f1])));
      await t.pumpAndSettle();
      // Today, with the picker's first morning time: whatever the phone's clock,
      // the posted slot must land after now.
      await t.tap(find.byKey(const Key('night-slot-0')));
      await t.pumpAndSettle();
      await t.tap(find.text('1'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.tap(find.text('AM'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.textContaining('has already passed'), findsNothing);
      await t.tap(find.byKey(const Key('night-submit')));
      await t.pumpAndSettle();
      final night = _crew(r, id).nights.single;
      expect(night.status, NightStatus.set);
      expect(night.slots.single.startsAt!.isAfter(r.container.read(nowProvider)()), isTrue);
    });

    testWidgets('Add a film offers the whole catalog', (t) async {
      phoneSize(t, height: 900);
      final r = rig();
      final id = await makeCrew(r);
      await t.pumpWidget(r.app(NightEditorScreen(crewId: id)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('night-add-film')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('night-search-all')), findsOneWidget);
    });
  });

  group('the night screen', () {
    testWidgets('a set night is a ticket: film, date and time on the group clock, place, replies', (t) async {
      phoneSize(t, height: 900);
      final r = rig();
      final id = await makeCrew(r, guests: ['Asha']);
      final night = await _setNight(r, id);
      await t.pumpWidget(r.app(NightScreen(crewId: id, nightId: night.id)));
      await t.pumpAndSettle();

      expect(find.text('FILM 1'), findsWidgets);
      expect(find.textContaining('SAT, 3 OCT'), findsOneWidget);
      expect(find.textContaining('8:00'), findsWidgets);
      expect(find.text('3'), findsOneWidget, reason: 'the day on the counterfoil');
      expect(find.textContaining('Home'), findsOneWidget);
      expect(find.text('No reply yet'), findsNWidgets(2));

      // I say yes; the host sets Asha's reply for her.
      await t.tap(find.byKey(const Key('rsvp-yes')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('actor-${_crew(r, id).members.last.id}')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rsvp-maybe')));
      await t.pumpAndSettle();
      final crew = _crew(r, id);
      expect(crew.nights.single.rsvps, {crew.members.first.id: Rsvp.yes, crew.members.last.id: Rsvp.maybe});
      expect(find.text('No reply yet'), findsNothing);
      expect(_stamp('YES'), findsOneWidget);
      expect(_stamp('MAYBE'), findsOneWidget);
    });

    testWidgets('the reminder switch schedules two reminders, asks permission once, and says so when refused', (
      t,
    ) async {
      phoneSize(t, height: 900);
      final r = rig(at: DateTime.utc(2026, 10, 1, 9));
      final id = await makeCrew(r);
      final night = await _setNight(r, id);
      await t.pumpWidget(r.app(NightScreen(crewId: id, nightId: night.id)));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('night-remind')));
      await t.pumpAndSettle();
      expect(r.reminders.permissionAsks, 1);
      expect(r.reminders.scheduled, hasLength(2));
      expect({for (final s in r.reminders.scheduled.values) s.title}, {'Movie night'});
      expect(
        [for (final s in r.reminders.scheduled.values) s.body]
            .any((b) => b.contains('Film 1') && b.contains('Friday Crew')),
        isTrue,
      );
      expect(r.container.read(reminderOnProvider(night.id)), isTrue);

      await t.tap(find.byKey(const Key('night-remind')));
      await t.pumpAndSettle();
      expect(r.reminders.scheduled, isEmpty);
      expect(r.container.read(reminderOnProvider(night.id)), isFalse);

      r.reminders.granted = false;
      await t.tap(find.byKey(const Key('night-remind')));
      await t.pumpAndSettle();
      expect(r.reminders.scheduled, isEmpty);
      expect(r.container.read(reminderOnProvider(night.id)), isFalse);
      expect(find.textContaining('Talkies cannot send reminders'), findsOneWidget);
    });

    testWidgets('exports a calendar file named after the film', (t) async {
      phoneSize(t, height: 900);
      final r = rig();
      final id = await makeCrew(r);
      final night = await _setNight(r, id);
      await t.pumpWidget(r.app(NightScreen(crewId: id, nightId: night.id)));
      await t.pumpAndSettle();

      await t.ensureVisible(find.byKey(const Key('night-ics')));
      await t.tap(find.byKey(const Key('night-ics')));
      await t.pumpAndSettle();
      final file = r.sharer.files.single;
      expect(file.name, 'Film-1.ics');
      expect(file.mime, 'text/calendar');
      expect(file.body, contains('SUMMARY:Film 1'));
      expect(file.body, contains('DTSTART:20261003T143000Z'));
      expect(file.body, contains('LOCATION:Home'));
      expect(file.body, contains('DESCRIPTION:Friday Crew'));
      expect(file.body, contains('UID:night-${night.id}@talkies'));
    });

    testWidgets('after the start the host can wrap up: a stub for the diary, with the others as company', (t) async {
      phoneSize(t, height: 900);
      final r = rig(at: DateTime.utc(2026, 10, 3, 18));
      final id = await makeCrew(r, guests: ['Asha', 'Ravi']);
      final night = await _setNight(r, id);
      final crew = _crew(r, id);
      final ctl = r.container.read(crewProvider(id).notifier);
      await ctl.rsvp(night.id, crew.members[1].id, Rsvp.yes);
      await ctl.rsvp(night.id, crew.members[2].id, Rsvp.no);
      await t.pumpWidget(r.app(NightScreen(crewId: id, nightId: night.id)));
      await t.pumpAndSettle();

      // Nothing to remind about once it has started; the wrap-up is offered.
      expect(find.byKey(const Key('night-remind')), findsNothing);
      await t.ensureVisible(find.byKey(const Key('night-wrap')));
      await t.tap(find.byKey(const Key('night-wrap')));
      await t.pumpAndSettle();

      final stubs = r.container.read(diaryProvider).stubs;
      expect(stubs, hasLength(1));
      expect(stubs.single.filmId, 'Q1');
      expect(stubs.single.company, 'Asha');
      expect(stubs.single.place, 'Home');
      expect(_crew(r, id).nights.single.status, NightStatus.done);
      expect(find.text('1 stub made'), findsOneWidget);
      expect(_stamp('WATCHED'), findsOneWidget, reason: 'the rubber stamp on the counterfoil');
      expect(find.byKey(const Key('night-wrap')), findsNothing);
    });

    testWidgets('the host can delete the night, and its reminders go with it', (t) async {
      phoneSize(t, height: 900);
      final r = rig(at: DateTime.utc(2026, 10, 1, 9));
      final id = await makeCrew(r);
      final night = await _setNight(r, id);
      await t.pumpWidget(
        r.app(
          Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NightScreen(crewId: id, nightId: night.id),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('night-remind')));
      await t.pumpAndSettle();
      expect(r.reminders.scheduled, hasLength(2));

      await t.ensureVisible(find.byKey(const Key('night-delete')));
      await t.tap(find.byKey(const Key('night-delete')));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(_crew(r, id).nights, isEmpty);
      expect(r.reminders.scheduled, isEmpty);
      expect(find.byType(NightScreen), findsNothing);
    });
  });
}
