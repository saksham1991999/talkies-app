import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/crews.dart';
import 'package:talkies/ui/swipe_card.dart';

import 'together_harness.dart';

const _w = 280.0;
const _h = 360.0;

/// A card [_w] by [_h] with the three votes it reports.
Future<List<Vote>> _pump(WidgetTester t, {bool reduceMotion = false, Key? key, double scale = 1}) async {
  phoneSize(t);
  final votes = <Vote>[];
  await t.pumpWidget(
    rig().app(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: _w,
            height: _h,
            child: SwipeCard(
              key: key,
              label: 'Film 1, 2015',
              onSwiped: votes.add,
              child: const ColoredBox(key: Key('face'), color: Colors.white),
            ),
          ),
        ),
      ),
      reduceMotion: reduceMotion,
      textScale: scale,
    ),
  );
  return votes;
}

Offset _where(WidgetTester t) => t.state<SwipeCardState>(find.byType(SwipeCard)).offset;

void main() {
  setUpAll(loadFonts);

  group('where a card commits', () {
    test('28 percent of the width sideways, 120 up, or a fling over 700', () {
      const w = 300.0; // 28 percent is 84
      Vote? at(Offset o, [Offset v = Offset.zero]) => swipeCommit(o, v, w);

      expect(at(const Offset(83, 0)), isNull);
      expect(at(const Offset(85, 0)), Vote.want);
      expect(at(const Offset(-85, 0)), Vote.skip);
      expect(at(const Offset(0, -119)), isNull);
      expect(at(const Offset(0, -120)), Vote.seen);
      expect(at(const Offset(0, 200)), isNull, reason: 'down is not a vote');

      // The more distant axis wins when a drag leans both ways.
      expect(at(const Offset(90, -100)), Vote.want);
      expect(at(const Offset(30, -125)), Vote.seen);

      // A fling decides by its main direction, however short the drag.
      expect(at(const Offset(5, 0), const Offset(701, 100)), Vote.want);
      expect(at(const Offset(5, 0), const Offset(-701, 100)), Vote.skip);
      expect(at(const Offset(0, -5), const Offset(100, -701)), Vote.seen);
      expect(at(const Offset(5, 0), const Offset(699, 0)), isNull);
      expect(at(const Offset(0, 5), const Offset(0, 900)), isNull, reason: 'a fling down is not a vote');
      expect(at(const Offset(0, -5), const Offset(800, -700)), Vote.want, reason: 'the faster axis decides');
    });

    test('the lean says how far along a drag is', () {
      expect(swipeLean(Offset.zero, 300), isNull);
      expect(swipeLean(const Offset(42, 0), 300)!.progress, closeTo(0.5, 1e-9));
      expect(swipeLean(const Offset(42, 0), 300)!.vote, Vote.want);
      expect(swipeLean(const Offset(-84, 0), 300)!.vote, Vote.skip);
      expect(swipeLean(const Offset(0, -60), 300)!.vote, Vote.seen);
      expect(swipeLean(const Offset(0, -60), 300)!.progress, closeTo(0.5, 1e-9));
    });
  });

  group('the swipe card', () {
    testWidgets('commits when dragged past its distance, in each direction', (t) async {
      for (final (drag, vote) in [
        (const Offset(120, 0), Vote.want),
        (const Offset(-120, 0), Vote.skip),
        (const Offset(0, -150), Vote.seen),
      ]) {
        // A fresh card for each, as the deck gives one.
        await t.pumpWidget(const SizedBox());
        final votes = await _pump(t);
        await t.drag(find.byType(SwipeCard), drag);
        await t.pumpAndSettle();
        expect(votes, [vote], reason: '$drag');
      }
    });

    testWidgets('springs back under the distance and says nothing', (t) async {
      final votes = await _pump(t);
      await t.drag(find.byType(SwipeCard), const Offset(60, 0));
      expect(_where(t).dx, greaterThan(20), reason: 'it follows the finger');
      await t.pumpAndSettle();
      expect(votes, isEmpty);
      expect(_where(t).distance, lessThan(0.01));

      await t.drag(find.byType(SwipeCard), const Offset(0, -80));
      await t.pumpAndSettle();
      expect(votes, isEmpty);
      expect(_where(t).distance, lessThan(0.01));

      await t.drag(find.byType(SwipeCard), const Offset(0, 160));
      await t.pumpAndSettle();
      expect(votes, isEmpty, reason: 'down is never a vote');
    });

    testWidgets('commits on a fling over 700 dp a second, even after a short drag', (t) async {
      final votes = await _pump(t);
      // 60 dp is under the 78 dp distance: only the speed commits it.
      await t.fling(find.byType(SwipeCard), const Offset(60, 0), 1200);
      await t.pumpAndSettle();
      expect(votes, [Vote.want]);

      votes.clear();
      await t.pumpWidget(const SizedBox());
      final up = await _pump(t);
      await t.fling(find.byType(SwipeCard), const Offset(0, -60), 1200);
      await t.pumpAndSettle();
      expect(up, [Vote.seen]);
    });

    testWidgets('a slow short drag or a fling down springs back', (t) async {
      final votes = await _pump(t);
      await t.fling(find.byType(SwipeCard), const Offset(60, 0), 300);
      await t.pumpAndSettle();
      await t.fling(find.byType(SwipeCard), const Offset(0, 60), 1500);
      await t.pumpAndSettle();
      expect(votes, isEmpty);
      expect(_where(t).distance, lessThan(0.01));
    });

    testWidgets('the buttons, keys and screen reader use the same exit', (t) async {
      final key = GlobalKey<SwipeCardState>();
      final votes = await _pump(t, key: key);
      key.currentState!.swipe(Vote.skip);
      await t.pumpAndSettle();
      expect(votes, [Vote.skip]);
      // Once it has left, it takes no second vote.
      key.currentState!.swipe(Vote.want);
      await t.pumpAndSettle();
      expect(votes, [Vote.skip]);
    });

    testWidgets('tells a screen reader its name and the three votes as actions', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t);
      final node = t.getSemantics(find.bySemanticsLabel('Film 1, 2015'));
      final data = node.getSemanticsData();
      expect(
        [for (final id in data.customSemanticsActionIds!) CustomSemanticsAction.getAction(id)!.label],
        ['Want', 'Skip', 'Seen'],
      );
      expect(data.hint, contains('Swipe right to want'));
      handle.dispose();
    });

    testWidgets('buzzes once at the threshold and once when it commits', (t) async {
      final haptics = recordHaptics(t);
      final votes = await _pump(t);
      final g = await t.startGesture(t.getCenter(find.byType(SwipeCard)));
      await g.moveBy(const Offset(40, 0));
      // Small steps: stop at the first one that reaches 28 percent of 280 dp.
      for (var i = 0; i < 30 && haptics.isEmpty; i++) {
        await g.moveBy(const Offset(10, 0));
      }
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(_where(t).dx, inInclusiveRange(swipeCommitWidth * _w, swipeCommitWidth * _w + 10));
      await g.moveBy(const Offset(40, 0));
      expect(haptics, hasLength(1), reason: 'past the threshold it stays quiet');
      await g.up();
      await t.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.selectionClick', 'HapticFeedbackType.lightImpact']);
      expect(votes, [Vote.want]);
    });

    testWidgets('the stamp of the vote fades in as the drag goes on, and only that stamp', (t) async {
      await _pump(t);
      final g = await t.startGesture(t.getCenter(find.byType(SwipeCard)));
      await g.moveBy(const Offset(40, 0));
      for (final step in [10.0, 10.0]) {
        await g.moveBy(Offset(step, 0));
      }
      await t.pump();
      final dx = _where(t).dx;
      expect(dx, greaterThan(5));
      expect(dx, lessThan(swipeCommitWidth * _w), reason: 'still under the distance');
      // The stamps are the Opacity widgets in the card: one shows, in proportion, and the others are clear.
      final shown = [
        for (final o in t.widgetList<Opacity>(
          find.descendant(of: find.byType(SwipeCard), matching: find.byType(Opacity)),
        ))
          o.opacity,
      ]..sort();
      expect(shown, hasLength(3));
      expect(shown[0], 0);
      expect(shown[1], 0);
      expect(shown[2], closeTo(dx / (swipeCommitWidth * _w), 0.01));
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('under reduced motion it neither tilts nor flies off', (t) async {
      final votes = await _pump(t, reduceMotion: true);
      final g = await t.startGesture(t.getCenter(find.byType(SwipeCard)));
      await g.moveBy(const Offset(60, 0));
      await t.pump();
      final tilt = t.widget<Transform>(
        find.descendant(of: find.byType(SwipeCard), matching: find.byType(Transform)).at(1),
      );
      expect(tilt.transform.getRotation().entry(0, 1), 0, reason: 'no rotation');
      await g.moveBy(const Offset(60, 0));
      await g.up();
      // The vote is reported by the lift itself: there is no animation to wait for.
      expect(votes, [Vote.want]);
      await t.pump();
      expect(find.byKey(const Key('face')), findsNothing, reason: 'the card is gone at once');
    });

    testWidgets('a vote the group refuses brings the card back', (t) async {
      final key = GlobalKey<SwipeCardState>();
      final votes = await _pump(t, key: key);
      key.currentState!.swipe(Vote.want);
      await t.pumpAndSettle();
      expect(votes, [Vote.want]);
      key.currentState!.springBack();
      await t.pumpAndSettle();
      expect(_where(t).distance, lessThan(0.01));
      expect(find.byKey(const Key('face')), findsOneWidget);
    });
  });
}
