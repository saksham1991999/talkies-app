import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:talkies/app.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/screens/film_screen.dart';
import 'package:talkies/ui/screens/home_screen.dart';
import 'package:talkies/ui/screens/search_screen.dart';
import 'package:talkies/ui/screens/stub_screen.dart';
import 'package:talkies/ui/widgets.dart';

/// App Store and Play screenshots: a full 2026 diary, then the key screens.
/// iOS only (flutter drive writes build/screens/). Needs network for posters.
/// Run: flutter drive --driver=test_driver/integration_test.dart
///   --target=integration_test/store_screens_test.dart -d SIMULATOR_ID
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name) async {
    // Let cached posters decode and fade in.
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  testWidgets('store screenshots', (t) async {
    final dir = Directory.systemTemp.createTempSync('talkies_store');
    final c = ProviderContainer(
      overrides: [docsDirProvider.overrideWithValue(dir), autoRefreshProvider.overrideWithValue(false)],
    );
    c.read(settingsProvider.notifier).set((s) => s.copyWith(seenVersion: '1.0.0'));
    final cat = await c.read(catalogProvider.future);
    final n = c.read(diaryProvider.notifier);
    const hall = 'Moti Mahal Talkies';
    n.addVenue(const Venue(hall, VenueType.cinema));

    DateTime d(int m, int day) => DateTime(2026, m, day);
    StubDraft cinema(
      DateTime day,
      double rating, {
      String show = 'evening',
      String? cls,
      String? seat,
      double? price,
      bool fdfs = false,
      String? format,
      List<String> tags = const [],
      String memo = '',
      String place = 'Cinema hall',
    }) => StubDraft(
      date: day,
      place: place,
      rating: rating,
      show: show,
      seatClass: cls,
      seat: seat,
      price: price,
      fdfs: fdfs,
      format: format,
      tags: tags,
      memo: memo,
    );
    StubDraft ott(DateTime day, String place, double? rating, {String? lang, List<String> tags = const []}) =>
        StubDraft(date: day, place: place, rating: rating, lang: lang, tags: tags);

    final rows = <(String, StubDraft)>[
      ('Q136673072', cinema(d(1, 2), 4.2, cls: 'Gold', price: 280)), // Ikkis
      ('Q124301053', cinema(d(1, 10), 3.4, show: 'morning', fdfs: true, price: 200, tags: ['fdfs'])), // The RajaSaab
      ('Q131445677', cinema(d(1, 11), 4.0, show: 'matinee', price: 180, place: hall)), // Parasakthi
      (
        'Q126734387',
        cinema(d(1, 24), 3.9, fdfs: true, format: 'imax', cls: 'Recliner', price: 450, tags: ['fdfs']),
      ), // Border 2
      ('Q124636001', ott(d(2, 8), 'JioHotstar', 4.6, tags: ['friends'])), // Manjummel Boys
      (
        'Q949228',
        cinema(
          d(2, 14),
          5.0,
          show: 'matinee',
          cls: 'Balcony',
          seat: 'B7',
          price: 120,
          place: hall,
          tags: ['classic', 're-release'],
          memo: 'Re-release in 70mm. The whole hall clapped at the coin toss.',
        ),
      ), // Sholay
      ('Q124467044', ott(d(2, 22), 'aha', 4.3, tags: ['comfort'])), // Premalu
      ('Q124714626', ott(d(3, 1), 'Netflix', 4.7, tags: ['family'])), // Laapataa Ladies
      ('Q126595889', ott(d(3, 8), 'Netflix', 4.5)), // Maharaja
      (
        'Q137998501',
        cinema(
          d(3, 20),
          4.8,
          show: 'night',
          fdfs: true,
          format: 'imax',
          cls: 'Recliner',
          seat: 'F14',
          price: 520,
          tags: ['fdfs', 'friends'],
          memo: 'Night show with the whole gang. Whistles at the interval.',
        ),
      ), // Dhurandhar: The Revenge
      ('Q107105860', cinema(d(3, 22), 4.4, format: 'imax', price: 480)), // Project Hail Mary
      ('Q137998501', cinema(d(4, 4), 4.6, show: 'matinee', format: 'dolby', price: 350)), // second watch
      ('Q122921105', ott(d(4, 5), 'JioHotstar', 4.9, tags: ['family'])), // 12th Fail
      ('Q136187174', cinema(d(4, 18), 3.5, show: 'matinee', price: 220, tags: ['family'])), // Bhooth Bangla
      ('Q116677364', cinema(d(4, 25), 3.8, format: 'dolby', price: 400)), // Michael
      ('Q114322727', ott(d(5, 2), 'Prime Video', 4.4, lang: 'hi')), // Kantara in Hindi
      ('Q131341662', cinema(d(5, 16), 3.6, place: hall, price: 160)), // Karuppu
      ('Q60424165', ott(d(5, 24), 'Netflix', 4.5, lang: 'hi', tags: ['rewatch'])), // RRR in Hindi
      ('Q125453590', ott(d(6, 7), 'Netflix', 4.1)), // Lucky Baskhar
      ('Q121842080', ott(d(6, 14), 'SonyLIV', 4.2)), // Bramayugam
      ('Q44612834', ott(d(6, 28), 'Netflix', 4.6, tags: ['rewatch'])), // Andhadhun
      ('Q96398312', ott(d(7, 5), 'Prime Video', 4.8, tags: ['comfort'])), // Panchayat
      (
        'Q131547207',
        cinema(d(7, 17), 4.7, show: 'night', format: 'imax', cls: 'Premium', seat: 'J9', price: 650),
      ), // The Odyssey
      ('Q113244935', cinema(d(7, 31), 3.9, fdfs: true, format: '4dx', price: 550, tags: ['fdfs'])), // Spider-Man
      ('Q60737728', ott(d(8, 9), 'Prime Video', 4.5)), // Kumbalangi Nights
      ('Q27963002', ott(d(8, 16), 'Netflix', 4.3)), // Super Deluxe
      ('Q229633', ott(d(8, 30), 'TV', 4.0, tags: ['family', 'rewatch'])), // 3 Idiots
      ('Q134972728', ott(d(9, 6), 'JioHotstar', 4.2)), // Lokah Chapter 1
      ('Q135230927', ott(d(9, 10), 'Netflix', 4.4)), // Dhurandhar
      ('Q131763755', ott(d(9, 13), 'Netflix', 3.7)), // Mardaani 3
      ('Q133816460', ott(d(9, 17), 'JioHotstar', 4.6, tags: ['family'])), // Tourist Family
      ('Q124254266', ott(d(9, 20), 'Prime Video', 3.9, tags: ['friends'])), // Stree 2
      ('Q134486853', ott(d(9, 24), 'Netflix', 4.5)), // Homebound
      ('Q21001674', ott(d(9, 27), 'Home', 4.4, lang: 'hi', tags: ['rewatch'])), // Baahubali 2
      ('Q138035399', cinema(d(9, 28), 3.8, place: hall, show: 'matinee', cls: 'Dress Circle', price: 200)), // Mirzapur
    ];
    for (final (id, draft) in rows) {
      final f = cat.byId[id];
      expect(f, isNotNull, reason: id);
      n.addStub(f!, draft);
    }
    for (final (id, day) in [('Q133255153', d(10, 15)), ('Q135196186', d(11, 8)), ('Q131178539', d(12, 24))]) {
      n.toggleWish(cat.byId[id]!, planned: day);
    }

    // Posters for the diary and the first rows of new releases, before any capture.
    final today = c.read(todayProvider);
    final films = [
      ...c.read(diaryProvider).films.values,
      ...cat.newReleases(today).take(24),
      ...cat.upcoming(today).take(12),
    ];
    await t.runAsync(() => prefetchPosters(films));

    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const TalkiesApp()));
    await t.pumpAndSettle();
    final nav = Navigator.of(t.element(find.byType(HomeScreen)));
    Future<void> open(Widget w) async {
      nav.push(MaterialPageRoute<void>(builder: (_) => w));
      await t.pumpAndSettle();
    }

    Future<void> close() async {
      nav.pop();
      await t.pumpAndSettle();
    }

    final stubs = c.read(diaryProvider).stubs;
    final hero = stubs.firstWhere((s) => s.filmId == 'Q137998501');
    final sholay = stubs.firstWhere((s) => s.filmId == 'Q949228');

    await shot(t, '01_home');
    await open(StubScreen(stubId: hero.id));
    await shot(t, '02_ticket');
    await close();
    await open(StubScreen(stubId: sholay.id));
    await shot(t, '03_ticket_classic');
    await t.tap(find.byTooltip('Share ticket').first);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('share-image')), findsOneWidget);
    await shot(t, '04_share');
    await t.tapAt(const Offset(20, 80));
    await t.pumpAndSettle();
    await close();

    for (final (tab, name) in [(1, '05_stubs'), (2, '06_calendar'), (4, '07_stats')]) {
      c.read(tabProvider.notifier).go(tab);
      await shot(t, name);
    }
    await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await shot(t, '08_stats_more');
    c.read(tabProvider.notifier).go(1);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Grid view').first);
    await shot(t, '09_stubs_grid');
    await t.tap(find.byTooltip('List view').first);
    await t.pumpAndSettle();

    c.read(tabProvider.notifier).go(3);
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 2));
    await shot(t, '10_films_new');

    final rrr = cat.byId['Q60424165']!;
    await open(FilmScreen(filmId: rrr.id, fallback: rrr));
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 100)); // synopsis from Wikipedia
    }
    await shot(t, '11_film_page');
    await close();

    await open(const SearchScreen());
    await t.enterText(find.byKey(const Key('search-field')), 'शोले');
    await t.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(t, '12_search_native');
    await close();

    // Hindi, dark mode.
    c.read(tabProvider.notifier).go(0);
    c.read(settingsProvider.notifier).set((s) => s.copyWith(locale: () => 'hi', themeMode: ThemeMode.dark));
    await t.pumpAndSettle();
    await shot(t, '13_home_hi_dark');
    await open(StubScreen(stubId: hero.id));
    await shot(t, '14_ticket_hi_dark');
    await close();
  });
}
