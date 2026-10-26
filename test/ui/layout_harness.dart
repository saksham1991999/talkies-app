import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/state/links.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/format.dart';

import 'together_harness.dart';

/// Shared set-up for the layout proofs: the real providers (from
/// together_harness), a diary with content on every screen, and a pump that
/// fails with the whole error report when a screen overflows.

/// No invite links: the app asks the platform for one at start-up, and this
/// test is about layout, not about plugins.
class NoLinks implements LinkSource {
  @override
  Future<Uri?> initial() async => null;

  @override
  Stream<Uri> get stream => const Stream<Uri>.empty();
}

/// A phone at 375x812 (an iPhone 12 mini / SE-class width), the narrowest size
/// the app claims to support.
const phone = Size(375, 812);

/// The rig, plus the catalog its films come from.
class LayoutRig {
  LayoutRig(this.rig, this.catalog);

  final Rig rig;
  final Catalog catalog;

  ProviderContainer get container => rig.container;

  /// A stub the tests can open.
  Stub get stub => container.read(diaryProvider).stubs.first;

  /// The film of [stub].
  Film get film => container.read(diaryProvider).films[stub.filmId]!;
}

/// A phone whose diary holds four stubs and one planned watch, so Home, Stubs,
/// Stats, the calendar, a stub detail and the record screen all have real rows.
Future<LayoutRig> layoutRig() async {
  final r = rig(overrides: [linkSourceProvider.overrideWithValue(NoLinks())]);
  final set = r.container.read(settingsProvider.notifier).set;
  // The release notes open once per version: this phone has seen them.
  set((s) => s.copyWith(seenVersion: appVersion));
  final cat = await r.container.read(catalogProvider.future);
  final n = r.container.read(diaryProvider.notifier);
  n.addVenue(const Venue('PVR Phoenix Palladium', VenueType.cinema));
  for (final (id, draft) in [
    (
      'Q1',
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
    ('Q2', StubDraft(date: today.subtract(const Duration(days: 3)), place: 'Netflix', rating: 4.1, lang: 'hi')),
    ('Q3', StubDraft(date: DateTime(today.year, today.month, 1), place: 'Cinema hall', rating: 3.6, price: 150)),
    ('Q4', StubDraft(date: DateTime(today.year, 2), precision: DatePrecision.month, place: 'Prime Video')),
  ]) {
    n.addStub(cat.byId[id]!, draft);
  }
  n.toggleWish(cat.byId['Q5']!, planned: today.add(const Duration(days: 2)));
  return LayoutRig(r, cat);
}

/// Every error a screen raised, collector first, so a message can carry all of
/// them instead of whatever `takeException` happens to hold.
class ErrorWatch {
  ErrorWatch(WidgetTester t) : _t = t {
    _before = FlutterError.onError;
    FlutterError.onError = (d) {
      reports.add(d.toString());
      _before?.call(d);
    };
  }

  final WidgetTester _t;
  final List<String> reports = [];
  FlutterExceptionHandler? _before;

  void stop() => FlutterError.onError = _before;

  /// Fails with the whole report, including the widget tree of the overflow, if
  /// the frame raised anything at all.
  void expectClean(String where) {
    stop();
    final thrown = _t.takeException();
    final all = [...reports, if (thrown != null) '$thrown'];
    if (all.isEmpty) return;
    final seen = <String>{};
    final unique = [
      for (final r in all)
        if (seen.add(r)) r,
    ];
    fail(
      '$where: ${unique.length} layout error(s)\n\n'
      '${unique.map((e) => _trim(e)).join('\n────\n')}',
    );
  }
}

/// The head of an error report: the message, the offending render object and its
/// creator chain. The whole dump is thousands of lines and hides the cause.
String _trim(String report) {
  final lines = report.split('\n');
  return lines.take(60).join('\n') + (lines.length > 60 ? '\n… ${lines.length - 60} more line(s)' : '');
}

/// Pumps [screen] as the whole app at phone size, in [locale] and [textScale],
/// and fails the test if the frame raised an error.
Future<void> pumpClean(
  WidgetTester t,
  LayoutRig r,
  Widget screen, {
  required Locale locale,
  Size size = phone,
  double textScale = 1,
  bool dark = false,
  String? where,
}) async {
  sizeOf(t, size);
  final watch = ErrorWatch(t);
  await t.pumpWidget(r.rig.app(screen, locale: locale, textScale: textScale, dark: dark));
  await t.pumpAndSettle();
  watch.expectClean(
    where ??
        '${screen.runtimeType} in ${locale.toLanguageTag()} at ${size.width.toInt()}x'
            '${size.height.toInt()}, text $textScale${dark ? ', dark' : ''}',
  );
}

/// The phone's window size. Separate from [phone] so a test can pass a size.
void sizeOf(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// The MediaQuery text scale the tree is actually laid out with, so a test that
/// means to use 1.3x can prove it did.
double textScaleOf(WidgetTester t) {
  final ctx = t.element(find.byType(Scaffold).first);
  return MediaQuery.textScalerOf(ctx).scale(100) / 100;
}
