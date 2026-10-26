import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/app.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/icons.dart';
import 'package:talkies/ui/screens/calendar_screen.dart';
import 'package:talkies/ui/screens/home_screen.dart';
import 'package:talkies/ui/screens/language_sheet.dart';
import 'package:talkies/ui/screens/record_screen.dart';
import 'package:talkies/ui/screens/settings_screen.dart';
import 'package:talkies/ui/screens/stub_screen.dart';
import 'package:talkies/ui/shell.dart';
import 'package:talkies/ui/widgets.dart';

import 'layout_harness.dart';
import 'together_harness.dart';

/// The three right-to-left UI languages, at 375x812, light and dark.
///
/// The app grew from 8 to 44 languages. This file proves the layout survives the
/// three that read right to left: the whole shell mirrors, every tab lays out
/// with no overflow, the bottom ticket follows the reading direction, and the
/// house icons that carry a direction are flipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  const rtl = [(Locale('ar'), 'Arabic'), (Locale('he'), 'Hebrew'), (Locale('ur'), 'Urdu')];

  for (final (locale, name) in rtl) {
    group('$name (${locale.languageCode})', () {
      testWidgets('the app itself turns the shell around', (t) async {
        // The real TalkiesApp, so this proves the settings-to-Directionality
        // wiring and not only the test's own MaterialApp.
        final r = await layoutRig();
        r.container.read(settingsProvider.notifier).set((s) => s.copyWith(locale: () => locale.languageCode));
        sizeOf(t, phone);
        await t.pumpWidget(UncontrolledProviderScope(container: r.container, child: const TalkiesApp()));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'the shell threw while starting up');
        expect(
          Directionality.of(t.element(find.byType(HomeScreen))),
          TextDirection.rtl,
          reason: 'Home is laid out left to right in ${locale.languageCode}',
        );
        expect(
          Directionality.of(t.element(find.byType(TicketNav))),
          TextDirection.rtl,
          reason: 'the bottom bar is laid out left to right in ${locale.languageCode}',
        );
      });

      for (final dark in [false, true]) {
        testWidgets('every tab lays out with no overflow${dark ? ' (dark)' : ''}', (t) async {
          final r = await layoutRig();
          await pumpClean(
            t,
            r,
            const Shell(),
            locale: locale,
            dark: dark,
            where: 'the shell in ${locale.languageCode}${dark ? ' dark' : ''}',
          );
          expect(Directionality.of(t.element(find.byType(HomeScreen))), TextDirection.rtl);
          for (final (tab, screen) in const [(0, 'Home'), (1, 'Stubs'), (2, 'Films'), (3, 'Stats'), (4, 'Together')]) {
            r.container.read(tabProvider.notifier).go(tab);
            final watch = ErrorWatch(t);
            await t.pumpAndSettle();
            watch.expectClean('$screen in ${locale.languageCode}${dark ? ' dark' : ''}');
          }
        });
      }

      testWidgets('the pushed screens lay out with no overflow', (t) async {
        final r = await layoutRig();
        for (final (where, screen) in [
          ('Calendar', const CalendarScreen()),
          ('Settings', const SettingsScreen()),
          ('the stub detail', StubScreen(stubId: r.stub.id)),
          ('the record screen', RecordScreen(film: r.film)),
        ]) {
          await pumpClean(t, r, screen, locale: locale, where: '$where in ${locale.languageCode}');
        }
      });

      testWidgets('the language sheet lays out with no overflow', (t) async {
        final r = await layoutRig();
        await pumpClean(
          t,
          r,
          Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => pickLanguage(c, locale.languageCode, (_) {}),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          locale: locale,
          where: 'the host of the language sheet in ${locale.languageCode}',
        );
        await t.tap(find.text('open'));
        final watch = ErrorWatch(t);
        await t.pumpAndSettle();
        watch.expectClean('the language sheet in ${locale.languageCode}');
        expect(find.byType(ListTile), findsWidgets, reason: 'the sheet drew no languages');
      });

      testWidgets('the bottom ticket sits under the active tab', (t) async {
        final r = await layoutRig();
        await pumpClean(t, r, const Shell(), locale: locale, where: 'the shell in ${locale.languageCode}');
        expect(
          find.descendant(of: find.byType(TicketNav), matching: find.byType(InkResponse)),
          findsNWidgets(5),
          reason: 'the bar must show five tabs',
        );
        for (var tab = 0; tab < 5; tab++) {
          r.container.read(tabProvider.notifier).go(tab);
          await t.pumpAndSettle();
          final cell = t.getRect(
            find.descendant(of: find.byType(TicketNav), matching: find.byType(InkResponse)).at(tab),
          );
          final ticket = t.getRect(find.descendant(of: find.byType(TicketNav), matching: find.byType(TicketPaper)));
          expect(
            ticket.center.dx,
            closeTo(cell.center.dx, 1),
            reason:
                'tab $tab is at x ${cell.center.dx.toStringAsFixed(1)} but its ticket is at '
                '${ticket.center.dx.toStringAsFixed(1)} in ${locale.languageCode}: the paper must '
                'follow the tab, and the slide is still measured from the left edge',
          );
          expect(ticket.left, greaterThanOrEqualTo(cell.left));
          expect(ticket.right, lessThanOrEqualTo(cell.right));
        }
      });

      testWidgets('the back icon is painted mirrored', (t) async {
        final r = await layoutRig();
        await pumpClean(t, r, const SettingsScreen(), locale: locale, where: 'Settings in ${locale.languageCode}');
        final back = find.byWidgetPredicate((w) => w is TkIcon && w.icon == Tk.back);
        expect(back, findsWidgets, reason: 'no Tk.back on the settings screen');
        final flips = _flipsX(t, back.first);
        expect(
          flips,
          isTrue,
          reason: 'Tk.back must be painted mirrored in a right-to-left language, or the arrow points the wrong way',
        );
      });
    });
  }

  // The control: the same two checks pass left to right. If this file ever
  // passes because nothing is asserted, this would still fail.
  group('English, the control', () {
    testWidgets('the bottom ticket sits under the active tab', (t) async {
      final r = await layoutRig();
      await pumpClean(t, r, const Shell(), locale: const Locale('en'), where: 'the shell in English');
      expect(Directionality.of(t.element(find.byType(HomeScreen))), TextDirection.ltr);
      for (var tab = 0; tab < 5; tab++) {
        r.container.read(tabProvider.notifier).go(tab);
        await t.pumpAndSettle();
        final cell = t.getRect(find.descendant(of: find.byType(TicketNav), matching: find.byType(InkResponse)).at(tab));
        final ticket = t.getRect(find.descendant(of: find.byType(TicketNav), matching: find.byType(TicketPaper)));
        expect(ticket.center.dx, closeTo(cell.center.dx, 1), reason: 'tab $tab in English');
      }
    });

    testWidgets('the back icon is not mirrored', (t) async {
      final r = await layoutRig();
      await pumpClean(t, r, const SettingsScreen(), locale: const Locale('en'), where: 'Settings in English');
      final back = find.byWidgetPredicate((w) => w is TkIcon && w.icon == Tk.back);
      expect(_flipsX(t, back.first), isFalse, reason: 'Tk.back is mirrored in English');
    });
  });

  // Proof that the detector in this file works. Without it, a green run above
  // could mean "nothing overflowed" or "nothing was ever checked".
  testWidgets('the overflow detector fails a row that does not fit', (t) async {
    final r = await layoutRig();
    sizeOf(t, phone);
    final watch = ErrorWatch(t);
    await t.pumpWidget(
      r.rig.app(
        const Scaffold(
          body: SizedBox(
            width: 20,
            child: Row(children: [SizedBox(width: 500, height: 10), SizedBox(width: 500, height: 10)]),
          ),
        ),
        locale: const Locale('ar'),
      ),
    );
    await t.pumpAndSettle();
    expect(
      () => watch.expectClean('a row that cannot fit'),
      throwsA(isA<TestFailure>()),
      reason: 'the detector must fail an overflowing screen, or every other test in this file proves nothing',
    );
  });
}

/// Whether the [TkIcon] at [icon] paints through a [Transform] that flips the x
/// axis. `TkIcon` builds `Transform.flip` inside itself for RTL, so the flip is a
/// descendant of the icon, not an ancestor.
bool _flipsX(WidgetTester t, Finder icon) {
  final transforms = find.descendant(of: icon, matching: find.byType(Transform));
  for (final element in t.elementList(transforms)) {
    if ((element.widget as Transform).transform.storage[0] < 0) return true;
  }
  return false;
}
