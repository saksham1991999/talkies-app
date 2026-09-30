import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:talkies/app.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/common.dart';
import 'package:talkies/ui/widgets.dart';

/// End to end: record, rewatch, calendar, films, watchlist, stats, settings
/// (ink, dark mode, Hindi), own film, quick add, tear up and undo, share
/// preview, and persistence. Screenshots land in build/screens/ via flutter drive.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name) async {
    await t.pumpAndSettle();
    // Android: convertFlutterSurfaceToImage hangs on the emulator; skip captures there.
    if (!Platform.isIOS) return;
    try {
      await binding.takeScreenshot(name);
    } catch (_) {
      // flutter test (no driver) cannot capture; the flow still runs.
    }
  }

  Future<void> pumpUntil(WidgetTester t, Finder f, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Timed out waiting for $f');
  }

  Future<void> tapText(WidgetTester t, String text, {Finder? scrollable}) async {
    final f = find.text(text).hitTestable();
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        find.text(text),
        250,
        scrollable: scrollable ?? find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await t.pumpAndSettle();
    }
    await t.tap(find.text(text).hitTestable().first);
    await t.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester t, String key, {Finder? scrollable}) async {
    final f = find.byKey(Key(key));
    if (f.hitTestable().evaluate().isEmpty) {
      await t.scrollUntilVisible(f, 250, scrollable: scrollable ?? find.byType(Scrollable).first, maxScrolls: 40);
      await t.pumpAndSettle();
    }
    await t.tap(f.hitTestable().first);
    await t.pumpAndSettle();
  }

  Future<void> tapTip(WidgetTester t, String tip) async {
    await t.tap(find.byTooltip(tip).hitTestable().first);
    await t.pumpAndSettle();
  }

  Future<void> back(WidgetTester t) => tapTip(t, 'Back');

  testWidgets('full journey', (t) async {
    final dir = Directory.systemTemp.createTempSync('talkies_e2e');
    final container = ProviderContainer(
      overrides: [docsDirProvider.overrideWithValue(dir), autoRefreshProvider.overrideWithValue(false)],
    );
    final today = container.read(todayProvider);
    await t.pumpWidget(UncontrolledProviderScope(container: container, child: const TalkiesApp()));

    // First launch shows what's new.
    await pumpUntil(t, find.text('Got it'));
    await shot(t, '00_whats_new');
    await tapText(t, 'Got it');
    await pumpUntil(t, find.text('New releases'));
    await shot(t, '01_home_empty');

    // Record Sholay at a cinema hall with every hall detail.
    await tapTip(t, 'Record a film');
    await pumpUntil(t, find.byKey(const Key('search-field')));
    await t.enterText(find.byKey(const Key('search-field')), 'sholay');
    await pumpUntil(t, find.text('Sholay'));
    await shot(t, '02_search');
    await t.tap(find.text('Sholay').first);
    await t.pumpAndSettle();
    expect(find.text('NEW STUB'), findsOneWidget);
    await tapText(t, 'Cinema hall');
    await tapText(t, 'Matinee');
    await tapText(t, 'IMAX');
    await tapText(t, 'Balcony');
    await t.scrollUntilVisible(find.byKey(const Key('price')), 200, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byKey(const Key('price')), '120');
    await tapKey(t, 'fdfs');
    final stars = find.byType(StarInput);
    await t.scrollUntilVisible(stars, 250, scrollable: find.byType(Scrollable).first);
    final box = t.getRect(stars);
    await t.tapAt(Offset(box.left + box.width * 0.9, box.center.dy));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('new-tag')), 200, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byKey(const Key('new-tag')), 'classic');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('memo')), 250, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byKey(const Key('memo')), 'Gabbar still gives me chills. Watched with Dadi.');
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(t, '03_record_filled');
    await tapKey(t, 'stamp-it');
    expect(find.text('0001'), findsWidgets);
    expect(find.text('FDFS'), findsWidgets);
    expect(find.text('₹120'), findsOneWidget);
    await shot(t, '04_ticket');

    // Rewatch on Netflix.
    await tapKey(t, 'watched-again');
    await tapText(t, 'Netflix');
    await tapKey(t, 'stamp-it');
    expect(find.text('0002'), findsWidgets);
    expect(find.text('Second watch'), findsOneWidget);
    await back(t);
    await pumpUntil(t, find.text('Recent'));
    expect(find.byType(StubRow), findsNWidgets(2));
    await shot(t, '05_home');

    // Stubs tab, list and grid.
    await tapText(t, 'STUBS');
    await shot(t, '06_stubs');
    await tapTip(t, 'Grid view');
    await shot(t, '07_stubs_grid');
    await tapTip(t, 'List view');

    // Calendar: today holds both stubs.
    await tapText(t, 'CALENDAR');
    expect(find.textContaining('2 watched', findRichText: true), findsOneWidget);
    await shot(t, '08_calendar');
    await t.tap(find.byKey(ValueKey('day-${ymd(today)}-true')));
    await t.pumpAndSettle();
    expect(find.byType(StubRow), findsNWidgets(2));
    await shot(t, '09_day_sheet');
    await t.tapAt(const Offset(20, 80));
    await t.pumpAndSettle();

    // Films: releases, search, watchlist.
    await tapText(t, 'FILMS');
    await pumpUntil(t, find.byType(PosterTile));
    await shot(t, '10_films_new');
    await tapText(t, 'Upcoming', scrollable: find.byType(Scrollable).at(1));
    await shot(t, '11_films_upcoming');
    await tapTip(t, 'Search');
    await t.enterText(find.byKey(const Key('search-field')), 'rrr');
    await pumpUntil(t, find.text('RRR'));
    await t.tap(find.byTooltip('Want to watch').first);
    await t.pumpAndSettle();
    await back(t);
    await tapText(t, 'Want', scrollable: find.byType(Scrollable).at(1));
    expect(find.byType(PosterTile), findsOneWidget);
    await shot(t, '12_films_want');

    // Film page for RRR: plan a date is offered once it is in the watchlist.
    await t.tap(find.byType(PosterTile).first);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('plan-date')), findsOneWidget);
    await shot(t, '13_film_page');
    await back(t);

    // Stats.
    await tapText(t, 'STATS');
    expect(find.text('₹120'), findsOneWidget);
    await shot(t, '14_stats');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await shot(t, '15_stats_more');

    // Settings: ink, dark mode, Hindi.
    await tapText(t, 'HOME');
    await tapTip(t, 'Settings');
    await t.tap(find.byKey(const Key('accent-2')));
    await tapText(t, 'Dark');
    await shot(t, '16_settings_dark');
    // Alternate launcher icon through the native channel, then back. iOS
    // replies only after the user taps OK on its system alert, which a test
    // cannot tap, so this runs on Android.
    if (Platform.isAndroid) {
      await tapText(t, 'Yellow ticket');
      await pumpUntil(t, find.text('App icon changed'));
      expect(container.read(settingsProvider).icon, 'yellow');
      ScaffoldMessenger.of(t.element(find.text('App icon changed'))).removeCurrentSnackBar();
      await tapText(t, 'Pink ticket');
      await pumpUntil(t, find.text('App icon changed'));
      expect(container.read(settingsProvider).icon, 'default');
    }
    await back(t);
    await shot(t, '17_home_dark');
    await t.tap(find.byType(StubRow).first);
    await t.pumpAndSettle();
    await shot(t, '18_ticket_dark');
    await back(t);
    await tapTip(t, 'Settings');
    await tapText(t, 'हिन्दी');
    expect(find.text('सेटिंग्स'), findsOneWidget);
    await tapTip(t, 'वापस');
    expect(find.text('हाल ही में'), findsOneWidget);
    await shot(t, '19_home_hindi');
    await tapText(t, 'आँकड़े'.toUpperCase());
    await shot(t, '20_stats_hindi');
    await tapText(t, 'होम'.toUpperCase());
    await tapTip(t, 'सेटिंग्स');
    await tapText(t, 'English');
    await tapText(t, 'Light');
    await back(t);

    // A film the catalog does not have.
    await tapTip(t, 'Record a film');
    await t.enterText(find.byKey(const Key('search-field')), 'Nani ki Kahani home video');
    await pumpUntil(t, find.byKey(const Key('add-own-film')));
    await tapKey(t, 'add-own-film');
    expect(find.text('Nani ki Kahani home video'), findsWidgets);
    await tapKey(t, 'custom-save');
    await tapText(t, "Don't remember");
    await tapKey(t, 'stamp-it');
    expect(find.text('0003'), findsWidgets);
    expect(find.text('Date not remembered'), findsWidgets);
    await back(t);

    // Quick add three titles.
    await tapTip(t, 'Settings');
    await tapText(t, 'Quick add');
    await t.enterText(find.byKey(const Key('batch-text')), 'Sholay 1975\nRRR (2022)\nZzqx Unknown Reel');
    await t.pumpAndSettle();
    await tapKey(t, 'batch-match');
    await pumpUntil(t, find.text('Add 3 stubs'));
    await shot(t, '21_quick_add');
    await tapKey(t, 'batch-add');
    await back(t);
    expect(container.read(diaryProvider).stubs, hasLength(6));

    // Tear up a stub, then undo.
    await tapText(t, 'STUBS');
    await t.tap(find.byType(StubRow).first);
    await t.pumpAndSettle();
    await tapKey(t, 'tear-up');
    await tapKey(t, 'confirm-tear');
    expect(container.read(diaryProvider).stubs, hasLength(5));
    await tapText(t, 'Undo');
    expect(container.read(diaryProvider).stubs, hasLength(6));

    // Share preview for a ticket.
    await t.tap(find.byType(StubRow).first);
    await t.pumpAndSettle();
    await tapTip(t, 'Share ticket');
    expect(find.byKey(const Key('share-image')), findsOneWidget);
    await shot(t, '22_share_sheet');
    await t.tapAt(const Offset(20, 80));
    await t.pumpAndSettle();
    await back(t);

    // Everything reached disk.
    await container.read(diaryProvider.notifier).flush();
    final saved = jsonDecode(File('${dir.path}/diary.json').readAsStringSync()) as Map<String, dynamic>;
    expect((saved['stubs'] as List).length, 6);
    expect((saved['wishes'] as List).length, 1);
    expect(saved['nextNo'], 7);
  });
}
