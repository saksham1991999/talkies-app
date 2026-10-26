import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/ui/icons.dart';
import 'package:talkies/ui/night_editor.dart';
import 'package:talkies/ui/online_widgets.dart';
import 'package:talkies/ui/screens/calendar_screen.dart';
import 'package:talkies/ui/screens/film_screen.dart';
import 'package:talkies/ui/screens/home_screen.dart';
import 'package:talkies/ui/screens/night_screen.dart';
import 'package:talkies/ui/widgets.dart' show Poster;

import 'together_harness.dart';

/// 8 pm on the third in a group whose clock is 5 h 30 min ahead of UTC.
final _eight = DateTime.utc(2026, 10, 3, 14, 30);

Future<Night> _night(Rig r, String id, {DateTime? at}) async {
  final made = await r.container
      .read(crewProvider(id).notifier)
      .createNight(
        NightCreate(
          films: [tFilm('Q1', title: 'Film 1')],
          slots: [at ?? _eight],
          tzOffsetMin: 330,
          place: 'Home',
        ),
      );
  return made.value!;
}

Finder _clock(Finder within) =>
    find.descendant(of: within, matching: find.byWidgetPredicate((w) => w is TkIcon && w.icon == Tk.clock));

void main() {
  setUpAll(loadFonts);

  group('Home', () {
    testWidgets('shows the next night as a small ticket that opens it, above Recent', (t) async {
      phoneSize(t, height: 1000);
      final r = rig();
      final id = await makeCrew(r);
      final night = await _night(r, id);
      await t.pumpWidget(r.app(const HomeScreen()));
      await t.pumpAndSettle();

      expect(find.text('Next night'), findsOneWidget);
      expect(find.textContaining('SAT, 3 OCT'), findsOneWidget);
      expect(t.getTopLeft(find.text('Next night')).dy, lessThan(t.getTopLeft(find.text('Recent')).dy));
      // The strip of friends' films is in place and draws nothing without a server.
      expect(find.byType(FriendsStrip), findsOneWidget);
      expect(t.getSize(find.byType(FriendsStrip)).height, 0);

      await t.tap(find.textContaining('SAT, 3 OCT'));
      await t.pumpAndSettle();
      expect(find.byType(NightScreen), findsOneWidget);
      expect(r.container.read(crewsProvider).crew(id)!.nights.single.id, night.id);
    });

    testWidgets('shows no row when no night is ahead, and none for a night already over', (t) async {
      phoneSize(t, height: 1000);
      final r = rig(at: DateTime.utc(2026, 10, 3, 20));
      final id = await makeCrew(r);
      await _night(r, id);
      await t.pumpWidget(r.app(const HomeScreen()));
      await t.pumpAndSettle();
      expect(find.text('Next night'), findsNothing);
    });
  });

  group('the film screen', () {
    final film = Film(
      id: 'Q1',
      title: 'Film 1',
      year: 2015,
      date: '2015-01-01',
      wiki: 'Film 1',
      langs: const ['hi'],
      countries: const ['IN'],
    );

    Rig phone() => rig(films: [film]);
    Widget screen(Rig r, {Film? f}) => r.app(FilmScreen(filmId: (f ?? film).id, fallback: f ?? film));

    testWidgets('Share film hands the share sheet the title, year, Wikipedia page and a line about Talkies', (t) async {
      phoneSize(t, height: 1000);
      final r = rig(
        films: [film],
        overrides: [
          synopsisProvider.overrideWith((ref, wiki) async => 'A film.'),
          streamingProvider.overrideWith((ref, wiki) async => <String>[]),
        ],
      );
      await t.pumpWidget(screen(r));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('share-film')));
      await t.pumpAndSettle();

      final shared = r.sharer.texts.single;
      expect(shared.text.split('\n'), [
        'Film 1 (2015)',
        'https://en.wikipedia.org/wiki/Film_1',
        '',
        'Kept in Talkies, a movie ticket diary.',
      ]);
      expect(shared.subject, 'Film 1');
      expect(r.requests, isEmpty, reason: 'sharing asks nothing of the network');
    });

    testWidgets('a film with no Wikipedia page is shared without a link', (t) async {
      phoneSize(t, height: 1000);
      final own = Film(id: 'my:1', title: 'My film', year: 2020);
      final r = phone();
      await t.pumpWidget(screen(r, f: own));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('share-film')));
      await t.pumpAndSettle();
      expect(r.sharer.texts.single.text.split('\n'), ['My film (2020)', '', 'Kept in Talkies, a movie ticket diary.']);
    });

    testWidgets('puts the Send and Friends who watched places under the actions and above Streaming', (t) async {
      phoneSize(t, height: 1000);
      final r = rig(
        films: [
          Film(id: 'Q1', title: 'Film 1', year: 2015, date: '2015-01-01', ott: const ['netflix'], langs: const ['hi']),
        ],
      );
      await t.pumpWidget(
        screen(
          r,
          f: Film(
            id: 'Q1',
            title: 'Film 1',
            year: 2015,
            date: '2015-01-01',
            ott: const ['netflix'],
            langs: const ['hi'],
          ),
        ),
      );
      await t.pumpAndSettle();
      final actions = t.getTopLeft(find.byKey(const Key('toggle-wish'))).dy;
      final send = t.getTopLeft(find.byType(SendFilmButton)).dy;
      final friends = t.getTopLeft(find.byType(FriendsWhoWatched)).dy;
      final streaming = t.getTopLeft(find.text('Streaming on')).dy;
      expect(actions, lessThan(send));
      expect(send, lessThanOrEqualTo(friends));
      expect(friends, lessThan(streaming));
    });

    testWidgets('Add to group lists the groups, adds the film to the one tapped, and says so', (t) async {
      phoneSize(t, height: 1000);
      final r = phone();
      final a = await makeCrew(r);
      final b = (await r.container.read(crewsProvider.notifier).create('Family', myName: 'Me')).value!.id;
      await t.pumpWidget(screen(r));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('add-to-group')));
      await t.pumpAndSettle();
      expect(find.text('Friday Crew'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);

      await t.tap(find.text('Family'));
      await t.pumpAndSettle();
      expect([for (final w in r.container.read(crewsProvider).crew(b)!.films) w.filmId], ['Q1']);
      expect(r.container.read(crewsProvider).crew(a)!.films, isEmpty);
      expect(find.text('Added to Family'), findsOneWidget);
    });

    testWidgets('Add to group can make a new group on the spot and puts the film in it', (t) async {
      phoneSize(t, height: 1000);
      final r = phone();
      await t.pumpWidget(screen(r));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('add-to-group')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('add-to-new-group')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('crew-name')), 'Terrace club');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('crew-create')));
      await t.pumpAndSettle();

      final crew = r.container.read(crewsProvider).crews.single;
      expect(crew.name, 'Terrace club');
      expect([for (final w in crew.films) w.filmId], ['Q1']);
      expect(find.text('Added to Terrace club'), findsOneWidget);
    });
  });

  group('the calendar', () {
    testWidgets('marks the day of a night with a clock, and the Nights option shows only nights', (t) async {
      phoneSize(t, height: 1000);
      final r = rig();
      final id = await makeCrew(r);
      await _night(r, id);
      await t.pumpWidget(r.app(const CalendarScreen()));
      await t.pumpAndSettle();

      final third = find.byKey(const ValueKey('day-2026-10-03-true'));
      final fourth = find.byKey(const ValueKey('day-2026-10-04-true'));
      expect(_clock(third), findsOneWidget);
      expect(_clock(fourth), findsNothing);
      expect(
        find.descendant(of: third, matching: find.byType(Poster)),
        findsNothing,
        reason: 'the Stubs layer is empty',
      );

      await t.tap(find.byKey(const Key('cal-nights')));
      await t.pumpAndSettle();
      expect(
        find.descendant(of: third, matching: find.byType(Poster)),
        findsOneWidget,
        reason: 'the night shows as its film',
      );
      expect(_clock(third), findsOneWidget);

      // The other two options still work as they did.
      await t.tap(find.byKey(const Key('cal-wish')));
      await t.pumpAndSettle();
      expect(find.descendant(of: third, matching: find.byType(Poster)), findsNothing);
      await t.tap(find.byKey(const Key('cal-stubs')));
      await t.pumpAndSettle();
      expect(find.byTooltip('Filter'), findsOneWidget, reason: 'the place filter belongs to the Stubs layer');
    });

    testWidgets('the day sheet lists the night, and Plan a night opens the editor on that day', (t) async {
      phoneSize(t, height: 1000);
      final r = rig();
      final id = await makeCrew(r);
      final night = await _night(r, id);
      await t.pumpWidget(r.app(const CalendarScreen()));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('day-2026-10-03-true')));
      await t.pumpAndSettle();
      expect(find.text('Film 1'), findsOneWidget);
      // The ticket's time line; the clock's own space before PM may be a narrow one, so match the start.
      expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('SAT, 3 OCT, 8:00')), findsOneWidget);
      await t.tap(find.text('Film 1'));
      await t.pumpAndSettle();
      expect(find.byType(NightScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('day-2026-10-05-true')));
      await t.pumpAndSettle();
      expect(find.text('Nothing on this day.'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('cal-plan-night')));
      await t.tap(find.byKey(const Key('cal-plan-night')));
      await t.pumpAndSettle();
      expect(find.byType(NightEditorScreen), findsOneWidget);
      expect(find.textContaining('Mon, 5 Oct'), findsOneWidget, reason: 'the day is already chosen');
      expect(night.id, isNotEmpty);
    });

    testWidgets('with several groups Plan a night asks which one first, and with none it makes one', (t) async {
      phoneSize(t, height: 1000);
      final r = rig();
      final a = await makeCrew(r);
      await r.container.read(crewsProvider.notifier).create('Family', myName: 'Me');
      await t.pumpWidget(r.app(const CalendarScreen()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('day-2026-10-05-true')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('cal-plan-night')));
      await t.tap(find.byKey(const Key('cal-plan-night')));
      await t.pumpAndSettle();
      expect(find.text('WHICH GROUP?'), findsOneWidget);
      await t.tap(find.text('Family'));
      await t.pumpAndSettle();
      expect(find.byType(NightEditorScreen), findsOneWidget);
      expect(a, isNotEmpty);

      // A phone with no group yet: the new group sheet comes first.
      final fresh = rig();
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(fresh.app(const CalendarScreen()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('day-2026-10-05-true')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('cal-plan-night')));
      await t.tap(find.byKey(const Key('cal-plan-night')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('crew-name')), findsOneWidget);
    });
  });
}
