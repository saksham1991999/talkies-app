import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/ui/screens/deck_screen.dart';
import 'package:talkies/ui/swipe_card.dart';

import 'together_harness.dart';

/// Opens the deck of [id] and waits for the first card.
Future<void> _open(WidgetTester t, Rig r, String id, {Random? random}) async {
  await t.pumpWidget(r.app(DeckScreen(crewId: id, random: random)));
  await t.pumpAndSettle();
}

/// The title printed on a card under its poster. (The poster's own title card prints it too.)
Finder _title(String title) => find.byWidgetPredicate((w) => w is Text && w.data == title && w.style?.fontSize == 24);

Map<String, Vote> _votes(Rig r, String id, String name) {
  final crew = r.container.read(crewsProvider).crew(id)!;
  return crew.votes[crew.members.firstWhere((m) => m.name == name).id] ?? const {};
}

void main() {
  setUpAll(loadFonts);

  testWidgets('shows the deck as a poster on ticket paper with a count and three buttons', (t) async {
    phoneSize(t);
    final r = rig();
    final id = await makeCrew(r);
    await _open(t, r, id);

    expect(find.text('1 of 8'), findsOneWidget);
    expect(_title('FILM 1'), findsOneWidget);
    expect(find.byType(DeckFace), findsNWidgets(2), reason: 'the card and the one waiting behind it');
    for (final k in ['vote-skip', 'vote-seen', 'vote-want']) {
      expect(find.byKey(Key(k)), findsOneWidget);
      expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44));
    }
    // One member swipes: nobody to pass the phone to.
    expect(find.byKey(const Key('deck-pass')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('the buttons vote, save at once, and move on to the next card', (t) async {
    phoneSize(t);
    final r = rig();
    final id = await makeCrew(r);
    await _open(t, r, id);

    await t.tap(find.byKey(const Key('vote-want')));
    await t.pumpAndSettle();
    expect(find.text('2 of 8'), findsOneWidget);
    expect(_title('FILM 2'), findsOneWidget);
    await t.tap(find.byKey(const Key('vote-skip')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('vote-seen')));
    await t.pumpAndSettle();

    expect(_votes(r, id, 'Me'), {'Q1': Vote.want, 'Q2': Vote.skip, 'Q3': Vote.seen});
    expect(find.text('4 of 8'), findsOneWidget);
  });

  testWidgets('arrow keys swipe and Undo brings the card back', (t) async {
    phoneSize(t);
    final r = rig();
    final id = await makeCrew(r);
    await _open(t, r, id);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(_votes(r, id, 'Me'), {'Q1': Vote.want});
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(_votes(r, id, 'Me'), {'Q1': Vote.want, 'Q2': Vote.skip, 'Q3': Vote.seen});

    await t.tap(find.byKey(const Key('deck-undo')));
    await t.pumpAndSettle();
    expect(_title('FILM 3'), findsOneWidget, reason: 'the last card is back on top');
    expect(find.text('3 of 8'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(_votes(r, id, 'Me')['Q3'], Vote.want, reason: 'a later swipe replaces the earlier one');
    expect(find.text('4 of 8'), findsOneWidget);
  });

  testWidgets('arrow keys in the search field move the caret instead of voting', (t) async {
    phoneSize(t);
    final r = rig();
    final id = await makeCrew(r);
    await _open(t, r, id);

    await t.tap(find.byTooltip('Search'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('deck-search')), 'film');
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(_votes(r, id, 'Me'), isEmpty, reason: 'no card was voted');
    expect(find.text('1 of 8'), findsOneWidget, reason: 'the top card did not move');
    expect(
      t.widget<TextField>(find.byKey(const Key('deck-search'))).controller?.text,
      'film',
      reason: 'the field kept its text',
    );
  });

  testWidgets('a swipe on the card itself votes too', (t) async {
    phoneSize(t);
    final r = rig();
    final id = await makeCrew(r);
    await _open(t, r, id);

    await t.drag(find.byType(SwipeCard), const Offset(-160, 0));
    await t.pumpAndSettle();
    expect(_votes(r, id, 'Me'), {'Q1': Vote.skip});
  });

  group('passing the phone', () {
    testWidgets('each member swipes in turn behind a velvet screen', (t) async {
      phoneSize(t);
      final r = rig();
      final id = await makeCrew(r, guests: ['Asha']);
      await _open(t, r, id);
      expect(find.byKey(const Key('deck-pass')), findsOneWidget, reason: 'two members: the phone can be passed');

      await t.tap(find.byKey(const Key('vote-want')));
      await t.pumpAndSettle();
      expect(find.text('2 of 8'), findsOneWidget);

      // Pick Asha: the deck goes, and a velvet screen names her.
      await t.tap(find.text('Asha'));
      await t.pumpAndSettle();
      expect(find.byType(DeckFace), findsNothing, reason: 'earlier picks stay hidden');
      expect(find.byType(SwipeCard), findsNothing);
      expect(find.text('ASHA'), findsOneWidget);
      expect(find.text('Hand the phone to'.toUpperCase()), findsOneWidget);
      expect(find.text("I'm Asha"), findsOneWidget);

      // Until she says so, her deck stays shut. Then it starts at the top: her votes are her own.
      await t.tap(find.byKey(const Key('handoff-confirm')));
      await t.pumpAndSettle();
      expect(find.text('1 of 8'), findsOneWidget);
      expect(_title('FILM 1'), findsOneWidget);
      await t.tap(find.byKey(const Key('vote-skip')));
      await t.pumpAndSettle();
      expect(find.text('2 of 8'), findsOneWidget);
      expect(_votes(r, id, 'Asha'), {'Q1': Vote.skip});
      expect(_votes(r, id, 'Me'), {'Q1': Vote.want}, reason: 'each swipe saved for its own member');

      // "Done, pass it on": the next member with cards left. From Asha that is the phone holder.
      await t.tap(find.byKey(const Key('deck-pass')));
      await t.pumpAndSettle();
      expect(find.byType(DeckFace), findsNothing);
      expect(find.text('Hand the phone back'.toUpperCase()), findsOneWidget);
      await t.tap(find.byKey(const Key('handoff-confirm')));
      await t.pumpAndSettle();
      expect(find.text('2 of 8'), findsOneWidget, reason: 'back on my own deck where I left it');
      expect(r.requests, isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets('a film one member has seen is gone from the next member\'s deck while Hide seen is on', (t) async {
      phoneSize(t);
      final r = rig();
      final id = await makeCrew(r, guests: ['Asha']);
      await _open(t, r, id);

      await t.tap(find.byKey(const Key('vote-seen')));
      await t.pumpAndSettle();
      await t.tap(find.text('Asha'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('handoff-confirm')));
      await t.pumpAndSettle();

      expect(_title('FILM 1'), findsNothing);
      expect(_title('FILM 2'), findsOneWidget);
      expect(find.text('1 of 7'), findsOneWidget);
    });

    testWidgets('Done, pass it on skips members with nothing left, and ends in the results', (t) async {
      phoneSize(t);
      final r = rig(
        films: [for (var i = 1; i <= 2; i++) tFilm('Q$i', title: 'Film $i', pop: 100 - i)],
      );
      final id = await makeCrew(r, guests: ['Asha']);
      await _open(t, r, id);
      // I swipe both cards.
      await t.tap(find.byKey(const Key('vote-want')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('vote-want')));
      await t.pumpAndSettle();
      expect(find.text('That is every card.'.toUpperCase()), findsOneWidget);

      // Asha has cards left, so she is next.
      await t.tap(find.byKey(const Key('deck-pass')));
      await t.pumpAndSettle();
      expect(find.text('ASHA'), findsOneWidget);
      await t.tap(find.byKey(const Key('handoff-confirm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('vote-want')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('vote-skip')));
      await t.pumpAndSettle();

      // Everyone has swiped: passing on leads to the results.
      await t.tap(find.byKey(const Key('deck-pass')));
      await t.pumpAndSettle();
      expect(find.text('RESULTS'), findsOneWidget);
      expect(find.byKey(const Key('deck-schedule')), findsOneWidget, reason: 'the top match');
    });
  });

  testWidgets('filters hide cards without voting on them, and the count follows', (t) async {
    phoneSize(t);
    final r = rig(
      films: [
        for (var i = 1; i <= 4; i++) tFilm('Q$i', title: 'Film $i', g: const ['drama'], pop: 100 - i),
        for (var i = 5; i <= 6; i++) tFilm('Q$i', title: 'Film $i', g: const ['comedy'], pop: 100 - i),
      ],
    );
    final id = await makeCrew(r);
    await _open(t, r, id);
    expect(find.text('1 of 6'), findsOneWidget);

    await t.tap(find.byTooltip('Filters'));
    await t.pumpAndSettle();
    await t.tap(find.text('Comedy'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(20, 20)); // close the sheet
    await t.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(_title('FILM 5'), findsOneWidget);
    expect(_votes(r, id, 'Me'), isEmpty);

    // Search inside the deck.
    await t.tap(find.byTooltip('Search'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('deck-search')), 'film 6');
    await t.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
    expect(_title('FILM 6'), findsOneWidget);
    await t.enterText(find.byKey(const Key('deck-search')), 'zzz');
    await t.pumpAndSettle();
    expect(find.text('No cards match these filters.'), findsOneWidget);
  });

  testWidgets('Hide seen is on by default and the switch brings seen films back, with "seen by"', (t) async {
    phoneSize(t);
    final r = rig();
    final id = await makeCrew(r, guests: ['Asha']);
    await _open(t, r, id);
    await t.tap(find.byKey(const Key('vote-seen')));
    await t.pumpAndSettle();
    expect(find.textContaining('Seen by'), findsNothing);

    await t.tap(find.byTooltip('Filters'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('deck-hide-seen')));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(20, 20));
    await t.pumpAndSettle();

    // Asha's deck now holds the film I have seen, and says so.
    await t.tap(find.text('Asha'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('handoff-confirm')));
    await t.pumpAndSettle();
    expect(_title('FILM 1'), findsOneWidget);
    expect(find.text('Seen by 1 member'), findsOneWidget);
  });

  testWidgets('results list the deck by want, with the top match and Schedule it', (t) async {
    phoneSize(t);
    final r = rig();
    final id = await makeCrew(r, guests: ['Asha']);
    await _open(t, r, id);
    // Me: want film 1, skip film 2. Asha: skip film 1, want film 2 and film 3.
    await t.tap(find.byKey(const Key('vote-want')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('vote-skip')));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('handoff-confirm')));
    await t.pumpAndSettle();
    for (final k in ['vote-skip', 'vote-want', 'vote-want']) {
      await t.tap(find.byKey(Key(k)));
      await t.pumpAndSettle();
    }

    await t.tap(find.byTooltip('Show all'));
    await t.pumpAndSettle();
    expect(find.text('RESULTS'), findsOneWidget);
    expect(find.text('Top match'), findsOneWidget);
    // Films 1, 2 and 3 each have one want: the tie goes to the fewest skips, then deck order.
    final crew = r.container.read(crewsProvider).crews.single;
    expect([
      for (final e in crew.tallies.entries) (e.key, e.value.want),
    ], containsAll([('Q1', 1), ('Q2', 1), ('Q3', 1)]));

    await t.tap(find.byKey(const Key('deck-schedule')));
    await t.pumpAndSettle();
    // The editor starts with the top three films.
    expect(find.text('Plan a night'.toUpperCase()), findsOneWidget);
    expect(find.byKey(const Key('night-add-film')), findsNothing, reason: 'three films are the most');
    expect(find.text('Post poll'), findsOneWidget);
  });

  testWidgets('the Tonight picker picks at random among the most wanted and offers Schedule it', (t) async {
    phoneSize(t);
    final r = rig();
    final id = await makeCrew(r);
    await _open(t, r, id);
    // Nobody wants anything yet.
    await t.tap(find.byTooltip('Show all'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('deck-tonight')));
    await t.pumpAndSettle();
    expect(find.text('No one has said Want yet. Swipe first.'), findsOneWidget);
    await t.tapAt(const Offset(20, 20));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();

    // Two films tie at the top; a seeded Random picks one of them.
    for (final k in ['vote-want', 'vote-skip', 'vote-want']) {
      await t.tap(find.byKey(Key(k)));
      await t.pumpAndSettle();
    }
    await t.pumpWidget(const SizedBox());
    await _open(t, r, id, random: Random(3));
    await t.tap(find.byTooltip('Show all'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('deck-tonight')));
    await t.pumpAndSettle();
    final picked = t.widget<Text>(find.byKey(const Key('tonight-title'))).data!;
    expect(['FILM 1', 'FILM 3'], contains(picked));
    expect(find.text('Schedule it'), findsWidgets);

    await t.tap(find.byKey(const Key('tonight-schedule')));
    await t.pumpAndSettle();
    expect(find.text('Plan a night'.toUpperCase()), findsOneWidget);
    expect(
      find.text(picked[0] + picked.substring(1).toLowerCase()),
      findsOneWidget,
      reason: 'the pick is the one film',
    );
    expect(find.text('Set it'), findsOneWidget);
  });
}
