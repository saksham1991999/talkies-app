import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/state/together.dart';
import 'package:talkies/ui/night_editor.dart';
import 'package:talkies/ui/screens/calendar_screen.dart';
import 'package:talkies/ui/screens/crew_screen.dart';
import 'package:talkies/ui/screens/deck_results_screen.dart';
import 'package:talkies/ui/screens/deck_screen.dart';
import 'package:talkies/ui/screens/home_screen.dart';
import 'package:talkies/ui/screens/night_screen.dart';
import 'package:talkies/ui/screens/together_screen.dart';
import 'package:talkies/ui/swipe_card.dart';

import 'together_harness.dart';

// Contact sheets of the Together screens, for looking at them. Off unless a folder is named:
//   SHOTS_DIR=/some/folder flutter test test/ui/together_shots_test.dart
// Each sheet is one PNG with the screens side by side, 360 by 720 dp each.

final _films = [
  tFilm('Q1', title: 'Sholay', g: const ['action', 'drama'], year: 1975, pop: 99),
  tFilm('Q2', title: 'Panchayat', g: const ['comedy', 'drama'], year: 2020, series: false, pop: 98),
  tFilm('Q3', title: 'Kantara', g: const ['thriller'], lang: 'kn', year: 2022, pop: 97),
  tFilm('Q4', title: 'Andaz Apna Apna', g: const ['comedy'], year: 1994, pop: 96),
  tFilm('Q5', title: 'Drishyam', g: const ['thriller', 'crime'], lang: 'ml', year: 2013, pop: 95),
  tFilm('Q6', title: 'Lagaan', g: const ['drama', 'musical'], year: 2001, pop: 94),
];

/// 8 pm on the third in a group whose clock is 5 h 30 min ahead of UTC.
final _eight = DateTime.utc(2026, 10, 3, 14, 30);

Future<({String crew, String second, String set, String poll, String done})> _data(Rig r) async {
  final crew = await makeCrew(r, guests: ['Asha', 'Ravi', 'Meera', 'Dev', 'Kabir']);
  final second = (await r.container.read(crewsProvider.notifier).create('Family', myName: 'Me')).value!.id;
  final ctl = r.container.read(crewProvider(crew).notifier);
  final other = r.container.read(crewProvider(second).notifier);
  for (final f in _films.take(3)) {
    await ctl.addFilm(f);
  }
  final set = (await ctl.createNight(
    NightCreate(films: [_films[0]], slots: [_eight], tzOffsetMin: 330, place: 'Terrace'),
  )).value!;
  final poll = (await ctl.createNight(
    NightCreate(films: _films.take(3).toList(), slots: [_eight, _eight.add(const Duration(days: 1))], tzOffsetMin: 330),
  )).value!;
  final done = (await other.createNight(
    NightCreate(films: [_films[3]], slots: [DateTime.utc(2026, 9, 30, 14, 30)], tzOffsetMin: 330, place: 'PVR Phoenix'),
  )).value!;
  final c = r.container.read(crewsProvider).crew(crew)!;
  await ctl.rsvp(set.id, c.members[0].id, Rsvp.yes);
  await ctl.rsvp(set.id, c.members[1].id, Rsvp.maybe);
  await ctl.rsvp(set.id, c.members[2].id, Rsvp.no);
  await ctl.vote(poll.id, c.members[0].id, {poll.films[0].id, poll.slots[0].id});
  await ctl.vote(poll.id, c.members[1].id, {poll.films[0].id, poll.films[1].id});
  await other.rsvp(done.id, r.container.read(crewsProvider).crew(second)!.me!.id, Rsvp.yes);
  await other.wrapUp(done.id);
  return (crew: crew, second: second, set: set.id, poll: poll.id, done: done.id);
}

void main() {
  setUpAll(loadFonts);

  Future<ui.Image> shot(
    WidgetTester t,
    Rig r,
    Widget home, {
    bool dark = false,
    Future<void> Function()? then,
    Future<void> Function()? after,
  }) async {
    final key = GlobalKey();
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: r.app(home, dark: dark),
      ),
    );
    await t.pumpAndSettle();
    if (then != null) {
      await then();
      await t.pumpAndSettle();
    }
    late ui.Image image;
    await t.runAsync(() async {
      image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1.5);
    });
    if (after != null) await after();
    return image;
  }

  Future<void> sheet(WidgetTester t, String name, List<ui.Image> images) async {
    await t.runAsync(() async {
      final w = images.fold<double>(0, (a, i) => a + i.width + 16);
      final h = images.map((i) => i.height).reduce(math.max).toDouble();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF777777));
      var x = 0.0;
      for (final i in images) {
        canvas.drawImage(i, Offset(x, 0), Paint());
        x += i.width + 16;
      }
      final out = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
      File('${Platform.environment['SHOTS_DIR']}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    final tag = dark ? 'dark' : 'light';
    testWidgets('contact sheets, $tag', (t) async {
      if (Platform.environment['SHOTS_DIR'] == null) return;
      phoneSize(t, width: 360, height: 720);
      final r = rig(films: _films);
      final d = await _data(r);

      await sheet(t, 'a-$tag', [
        await shot(t, r, const TogetherScreen(), dark: dark),
        await shot(
          t,
          r,
          const TogetherScreen(),
          dark: dark,
          then: () async {
            await t.tap(find.text('Nights'));
          },
        ),
        await shot(t, r, CrewScreen(crewId: d.crew), dark: dark),
      ]);

      // The deck, mid-swipe, and the velvet screen.
      await sheet(t, 'b-$tag', [
        await shot(t, r, DeckScreen(crewId: d.crew), dark: dark),
        await shot(
          t,
          r,
          DeckScreen(crewId: d.crew),
          dark: dark,
          then: () async {
            final g = await t.startGesture(t.getCenter(find.byType(SwipeCard)));
            await g.moveBy(const Offset(50, 0));
            await g.moveBy(const Offset(50, -10));
            await t.pump();
            addTearDown(g.cancel);
          },
        ),
        await shot(
          t,
          r,
          DeckScreen(crewId: d.crew),
          dark: dark,
          then: () async {
            await t.tap(find.text('Asha'));
          },
        ),
      ]);

      await sheet(t, 'c-$tag', [
        await shot(t, r, DeckResultsScreen(crewId: d.crew), dark: dark),
        await shot(
          t,
          r,
          NightScreen(crewId: d.crew, nightId: d.poll),
          dark: dark,
        ),
        await shot(
          t,
          r,
          NightScreen(crewId: d.crew, nightId: d.set),
          dark: dark,
        ),
      ]);

      await sheet(t, 'd-$tag', [
        await shot(
          t,
          r,
          NightScreen(crewId: d.second, nightId: d.done),
          dark: dark,
        ),
        await shot(
          t,
          r,
          NightEditorScreen(crewId: d.crew, films: _films.take(2).toList(), day: DateTime(2026, 10, 3)),
          dark: dark,
        ),
        await shot(
          t,
          r,
          const CalendarScreen(),
          dark: dark,
          then: () async {
            await t.tap(find.byKey(const Key('cal-nights')));
          },
        ),
      ]);

      // Votes, so the results have a top match.
      final ctl = r.container.read(crewProvider(d.crew).notifier);
      await ctl.ensureDeck();
      final members = r.container.read(crewsProvider).crew(d.crew)!.members;
      for (final (m, film, vote) in [
        (0, 'Q1', Vote.want),
        (1, 'Q1', Vote.want),
        (2, 'Q1', Vote.want),
        (0, 'Q2', Vote.want),
        (1, 'Q2', Vote.skip),
        (0, 'Q3', Vote.seen),
      ]) {
        await ctl.swipe(members[m].id, film, vote);
      }
      await sheet(t, 'f-$tag', [
        await shot(t, r, DeckResultsScreen(crewId: d.crew), dark: dark),
        await shot(
          t,
          r,
          DeckScreen(crewId: d.crew),
          dark: dark,
          then: () async {
            await t.tap(find.byTooltip('Filters'));
          },
        ),
        await shot(
          t,
          r,
          DeckResultsScreen(crewId: d.crew, random: math.Random(2)),
          dark: dark,
          then: () async {
            await t.tap(find.byKey(const Key('deck-tonight')));
          },
        ),
      ]);

      r.container.read(togetherSegmentProvider.notifier).go(TogetherSegment.groups);
      await sheet(t, 'e-$tag', [
        await shot(t, r, const HomeScreen(), dark: dark),
        await shot(
          t,
          r,
          const TogetherScreen(),
          dark: dark,
          then: () async {
            await t.tap(find.text('New group'));
          },
        ),
        await shot(
          t,
          r,
          const CalendarScreen(),
          dark: dark,
          then: () async {
            await t.tap(find.byKey(const ValueKey('day-2026-10-03-true')));
          },
        ),
      ]);
    });
  }
}
