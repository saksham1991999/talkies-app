import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/together.dart';
import 'package:talkies/ui/format.dart' show appVersion;
import 'package:talkies/ui/icons.dart';
import 'package:talkies/ui/screens/crew_screen.dart';
import 'package:talkies/ui/screens/deck_screen.dart';
import 'package:talkies/ui/screens/night_screen.dart';
import 'package:talkies/ui/screens/together_screen.dart';
import 'package:talkies/ui/shell.dart';
import 'package:talkies/ui/swipe_card.dart';
import 'package:talkies/ui/night_editor.dart';

import 'together_harness.dart';

/// A phone 320 dp wide, the narrowest we design for, with the system text 50 percent larger.
const _narrow = Size(320, 640);

/// Three groups with long names, seven members in one, and a poll, a night that is set and one that is done.
Future<List<String>> _fill(Rig r) async {
  final names = ['Friday night film club on the terrace', 'Family', 'வெள்ளி இரவு திரைப்பட நண்பர்கள் குழு'];
  final ids = <String>[];
  for (final n in names) {
    final made = await r.container.read(crewsProvider.notifier).create(n, myName: 'Saksham');
    ids.add(made.value!.id);
  }
  final first = r.container.read(crewProvider(ids.first).notifier);
  for (final g in ['Asha', 'Ravi', 'Meera', 'Dev', 'Kabir', 'Tanvi']) {
    await first.addMember(g);
  }
  final films = [
    tFilm('Q1', title: 'Gangs of Wasseypur Part Two'),
    tFilm('Q2', title: 'Film 2'),
    tFilm('Q3', title: 'Film 3'),
  ];
  final poll = await first.createNight(
    NightCreate(
      films: films,
      slots: [DateTime.utc(2026, 10, 3, 14, 30), DateTime.utc(2026, 10, 4, 14, 30)],
      tzOffsetMin: 330,
      place: 'The big terrace',
    ),
  );
  expect(poll.ok, isTrue);
  final second = r.container.read(crewProvider(ids[1]).notifier);
  final set = await second.createNight(
    NightCreate(films: [films.first], slots: [DateTime.utc(2026, 10, 2, 14, 30)], tzOffsetMin: 330, place: 'Home'),
  );
  final done = await second.createNight(
    NightCreate(
      films: [films[1]],
      slots: [DateTime.utc(2026, 9, 30, 14, 30)],
      tzOffsetMin: 330,
      place: 'PVR Phoenix Marketcity',
    ),
  );
  await second.rsvp(set.value!.id, r.container.read(crewsProvider).crews[1].me!.id, Rsvp.yes);
  await second.rsvp(done.value!.id, r.container.read(crewsProvider).crews[1].me!.id, Rsvp.yes);
  await second.wrapUp(done.value!.id);
  return ids;
}

void main() {
  setUpAll(loadFonts);

  for (final (name, locale) in [('English', const Locale('en')), ('Tamil', const Locale('ta'))]) {
    group('at 320 dp with text 1.5 times larger, in $name', () {
      testWidgets('the Together tab holds: groups, nights, and a night that has stubs', (t) async {
        phoneSize(t, width: _narrow.width, height: _narrow.height);
        final r = rig();
        await _fill(r);
        await t.pumpWidget(r.app(const TogetherScreen(), locale: locale, textScale: 1.5));
        await t.pumpAndSettle();
        expect(find.byType(TogetherScreen), findsOneWidget);
        // Every ticket scrolls into view without overflow.
        await t.drag(find.byType(ListView).first, const Offset(0, -600));
        await t.pumpAndSettle();

        r.container.read(togetherSegmentProvider.notifier).go(TogetherSegment.nights);
        await t.pumpAndSettle();
        await t.drag(find.byType(ListView).first, const Offset(0, -600));
        await t.pumpAndSettle();
      });

      testWidgets('the group, deck, night and editor screens hold', (t) async {
        phoneSize(t, width: _narrow.width, height: _narrow.height);
        final r = rig(
          films: [
            for (var i = 1; i <= 6; i++)
              tFilm('Q$i', title: 'A long film title number $i', g: const ['drama', 'comedy', 'romance'], pop: 100 - i),
          ],
        );
        final ids = await _fill(r);
        final crew = r.container.read(crewsProvider).crew(ids.first)!;
        final screens = <Widget>[
          CrewScreen(crewId: ids.first),
          DeckScreen(crewId: ids.first),
          NightScreen(crewId: ids.first, nightId: crew.nights.first.id),
          NightScreen(crewId: ids[1], nightId: r.container.read(crewsProvider).crew(ids[1])!.nights.first.id),
          NightScreen(crewId: ids[1], nightId: r.container.read(crewsProvider).crew(ids[1])!.nights.last.id),
          NightEditorScreen(
            crewId: ids.first,
            films: crew.nights.first.films.map((o) => o.film!).toList(),
            day: DateTime(2026, 10, 3),
          ),
        ];
        for (final s in screens) {
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(r.app(s, locale: locale, textScale: 1.5));
          await t.pumpAndSettle();
          // The deck shows its card, not a progress mark.
          if (s is DeckScreen) expect(find.byType(SwipeCard), findsOneWidget);
          // Scroll to the end of whatever scrolls, so nothing hides below the fold.
          final lists = find.byType(ListView);
          if (lists.evaluate().isNotEmpty) {
            await t.drag(lists.first, const Offset(0, -2000));
            await t.pumpAndSettle();
          }
        }
      });
    });
  }

  group('six tabs on a 320 dp phone', () {
    for (final scale in [1.0, 1.5]) {
      testWidgets('the nav fits and every label stays readable at text $scale', (t) async {
        phoneSize(t, width: _narrow.width, height: _narrow.height);
        final r = rig();
        await t.pumpWidget(
          r.app(
            Scaffold(
              bottomNavigationBar: Builder(
                builder: (c) => TicketNav(
                  index: 5,
                  onTap: (_) {},
                  items: [
                    (Tk.home, 'Home'),
                    (Tk.stubs, 'Stubs'),
                    (Tk.calendar, 'Calendar'),
                    (Tk.films, 'Films'),
                    (Tk.stats, 'Stats'),
                    (Tk.people, 'Together'),
                  ],
                ),
              ),
            ),
            textScale: scale,
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final cell = _narrow.width / 6;
        final boxes = find.descendant(of: find.byType(TicketNav), matching: find.byType(FittedBox));
        expect(boxes, findsNWidgets(6));
        for (var i = 0; i < 6; i++) {
          final text = find.descendant(of: boxes.at(i), matching: find.byType(Text));
          final natural = t.getSize(text).width;
          final shown = t.getSize(boxes.at(i)).width;
          final shrink = natural <= shown ? 1.0 : shown / natural;
          final printed = 11.5 * scale * shrink;
          // The label sits inside its tab, and what is printed stays at 8.5 pt or more.
          expect(shown, lessThanOrEqualTo(cell), reason: 'label $i is wider than its tab');
          expect(printed, greaterThanOrEqualTo(8.5), reason: 'label $i is printed at ${printed.toStringAsFixed(1)} pt');
        }
      });
    }

    testWidgets('the whole app opens with six tabs and the sixth shows Together', (t) async {
      phoneSize(t);
      final r = rig();
      // The release notes are shown once per version: this phone has seen them.
      r.container.read(settingsProvider.notifier).set((s) => s.copyWith(seenVersion: appVersion));
      await t.pumpWidget(r.app(const Shell()));
      await t.pumpAndSettle();
      final tab = find.descendant(of: find.byType(TicketNav), matching: find.text('TOGETHER'));
      expect(tab, findsOneWidget);
      await t.tap(tab);
      await t.pumpAndSettle();
      expect(find.byType(TogetherScreen), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
    });
  });
}
