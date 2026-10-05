import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:talkies/app.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/screens/home_screen.dart';
import 'package:talkies/ui/screens/record_screen.dart';
import 'package:talkies/ui/screens/settings_screen.dart';
import 'package:talkies/ui/screens/stub_screen.dart';

/// Every main screen in every UI language, light and dark. Any overflow or
/// layout error fails the test. On iOS, screenshots go to build/screens/.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name) async {
    await t.pumpAndSettle();
    if (!Platform.isIOS) return;
    await binding.takeScreenshot(name);
  }

  testWidgets('all languages, all screens', (t) async {
    final dir = Directory.systemTemp.createTempSync('talkies_locales');
    final c = ProviderContainer(
      overrides: [docsDirProvider.overrideWithValue(dir), autoRefreshProvider.overrideWithValue(false)],
    );
    c.read(settingsProvider.notifier).set((s) => s.copyWith(seenVersion: '1.0.0'));
    final cat = await c.read(catalogProvider.future);
    final today = c.read(todayProvider);
    final n = c.read(diaryProvider.notifier);
    n.addVenue(const Venue('PVR Phoenix Palladium', VenueType.cinema));
    for (final (q, draft) in [
      (
        'Sholay',
        StubDraft(
          date: today,
          place: 'PVR Phoenix Palladium',
          rating: 4.8,
          show: 'matinee',
          seatClass: 'Balcony',
          seat: 'H12',
          price: 180,
          fdfs: true,
          format: 'imax',
          tags: const ['classic'],
          memo: 'Yeh haath mujhe de de, Thakur.',
        ),
      ),
      ('RRR', StubDraft(date: today.subtract(const Duration(days: 3)), place: 'Netflix', rating: 4.1, lang: 'hi')),
      ('Kantara', StubDraft(date: DateTime(today.year, today.month, 1), place: 'Cinema hall', rating: 3.6, price: 150)),
      ('Panchayat', StubDraft(date: DateTime(today.year, 2), precision: DatePrecision.month, place: 'Prime Video')),
    ]) {
      n.addStub(cat.search(q).first, draft);
    }
    n.toggleWish(cat.search('Drishyam').first, planned: today.add(const Duration(days: 2)));

    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const TalkiesApp()));
    await t.pumpAndSettle();

    // Every language at normal text size, then two at 1.5x system text.
    for (final (code, scale) in [
      for (final code in ['en', 'hi', 'ta', 'te', 'bn', 'mr', 'kn', 'ml']) (code, 1.0),
      ('en', 1.5),
      ('ta', 1.5),
    ]) {
      binding.platformDispatcher.textScaleFactorTestValue = scale;
      final tag = scale == 1.0 ? code : '${code}_big';
      c
          .read(settingsProvider.notifier)
          .set((s) => s.copyWith(locale: () => code, themeMode: code == 'ta' ? ThemeMode.dark : ThemeMode.light));
      await t.pumpAndSettle();
      for (var tab = 0; tab < 6; tab++) {
        c.read(tabProvider.notifier).go(tab);
        await shot(t, '${tag}_$tab');
      }
      for (final seg in [FilmsSegment.want, FilmsSegment.recorded]) {
        c.read(filmsSegmentProvider.notifier).go(seg);
        c.read(tabProvider.notifier).go(3);
        await shot(t, '${tag}_films_${seg.name}');
      }
      c.read(filmsSegmentProvider.notifier).go(FilmsSegment.fresh);
      c.read(tabProvider.notifier).go(0);
      await t.pumpAndSettle();
      final nav = Navigator.of(t.element(find.byType(HomeScreen)));
      final stub = c.read(diaryProvider).stubs.first;
      nav.push(MaterialPageRoute<void>(builder: (_) => StubScreen(stubId: stub.id)));
      await shot(t, '${tag}_ticket');
      nav.pop();
      nav.push(MaterialPageRoute<void>(builder: (_) => RecordScreen(film: c.read(diaryProvider).films[stub.filmId]!)));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('PVR Phoenix Palladium'));
      await t.pumpAndSettle();
      await t.tap(find.text('PVR Phoenix Palladium'));
      await shot(t, '${tag}_record');
      nav.pop();
      nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      await shot(t, '${tag}_settings');
      nav.pop();
      await t.pumpAndSettle();
    }
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
