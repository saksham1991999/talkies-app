import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/l10n/gen/app_localizations.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/reminders.dart';
import 'package:talkies/ui/sharer.dart';
import 'package:talkies/ui/theme.dart';

// Shared set-up for the Together widget tests: a phone with no server, a small
// catalog of films without posters (the title card draws itself, so nothing
// touches the network), a fixed clock, fake reminders and a recording share sheet.

/// The day the tests live on.
final today = DateTime(2026, 10, 1);

/// Nine in the morning UTC: a night on the evening of [today] is still to come.
final now = DateTime.utc(2026, 10, 1, 9);

/// A released Indian film with no poster.
Film tFilm(
  String id, {
  String? title,
  List<String> g = const [],
  String lang = 'hi',
  int year = 2015,
  bool series = false,
  List<String> ott = const [],
  int pop = 10,
}) => Film(
  id: id,
  title: title ?? 'Film $id',
  genres: g,
  langs: [lang],
  countries: const ['IN'],
  date: '$year-01-01',
  year: year,
  series: series,
  ott: ott,
  pop: pop,
);

/// Real fonts, so text measures like it does on a phone. Without them the tests draw boxy letters.
/// Tanker and Teko are in the repo. Roboto is the Material text font and ships with the Flutter SDK.
Future<void> loadFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (family, path) in [
    ('Tanker', 'assets/fonts/Tanker-Regular.otf'),
    ('Teko', 'assets/fonts/Teko-SemiBold.ttf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(path))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final roboto = FontLoader('Roboto');
  var any = false;
  for (final name in ['Regular', 'Medium', 'Bold', 'Light', 'Italic']) {
    final f = File('$root/bin/cache/artifacts/material_fonts/Roboto-$name.ttf');
    if (!f.existsSync()) continue;
    roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    any = true;
  }
  if (any) await roboto.load();
}

/// Records what would go to the share sheet.
class RecordingSharer implements Sharer {
  final texts = <({String text, String? subject})>[];
  final files = <({String name, String mime, String body})>[];

  @override
  Future<void> text(String text, {String? subject, Rect? origin}) async => texts.add((text: text, subject: subject));

  @override
  Future<void> file(Uint8List bytes, String name, String mime, {Rect? origin}) async =>
      files.add((name: name, mime: mime, body: utf8.decode(bytes)));
}

/// One phone: its folder, providers, fake reminders and share sheet, and a count of HTTP requests.
class Rig {
  Rig._(this.dir, this.container, this.reminders, this.sharer, this._requests);

  final Directory dir;
  final ProviderContainer container;
  final FakeReminders reminders;
  final RecordingSharer sharer;
  final List<String> _requests;

  /// URLs asked of the network so far.
  List<String> get requests => _requests;

  /// A MaterialApp around [home] with the app theme and strings. [textScale] and [locale] set the phone's text,
  /// [reduceMotion] the system switch that asks apps to hold still.
  Widget app(
    Widget home, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    bool reduceMotion = false,
    bool dark = false,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildTheme(dark: dark, accentIndex: 0),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: reduceMotion),
        child: child!,
      ),
      home: home,
    ),
  );
}

/// Makes a phone. [films] is the catalog; [at] is what the clock says; [apiUrl] is the server the build knows
/// (none by default) and [api] what answers for it; [overrides] go on top of the usual ones, and may not repeat them.
Rig rig({List<Film>? films, DateTime? at, String apiUrl = '', Api? api, List<Override> overrides = const []}) {
  final dir = Directory.systemTemp.createTempSync('talkies_ui');
  final reminders = FakeReminders();
  final sharer = RecordingSharer();
  final requests = <String>[];
  final catalog = Catalog(films ?? [for (var i = 1; i <= 8; i++) tFilm('Q$i', title: 'Film $i', pop: 100 - i)], 'test');
  final container = ProviderContainer(
    overrides: [
      docsDirProvider.overrideWithValue(dir),
      catalogProvider.overrideWith((ref) async => catalog),
      todayProvider.overrideWithValue(today),
      nowProvider.overrideWithValue(() => at ?? now),
      autoRefreshProvider.overrideWithValue(false),
      remindersProvider.overrideWithValue(reminders),
      sharerProvider.overrideWithValue(sharer),
      apiUrlProvider.overrideWithValue(apiUrl),
      if (api != null) apiProvider.overrideWithValue(api),
      httpClientProvider.overrideWithValue(
        http_testing.MockClient((r) async {
          requests.add(r.url.toString());
          return http.Response('{}', 500);
        }),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return Rig._(dir, container, reminders, sharer, requests);
}

/// A phone-sized window: [width] by [height] logical pixels.
void phoneSize(WidgetTester t, {double width = 400, double height = 800}) {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// The haptic calls so far, like `HapticFeedbackType.lightImpact`.
List<String> recordHaptics(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
    if (c.method == 'HapticFeedback.vibrate') calls.add(c.arguments as String);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

/// A local group called "Friday Crew" held by "Me", with [guests] added. Returns its id.
Future<String> makeCrew(Rig r, {List<String> guests = const []}) async {
  final made = await r.container.read(crewsProvider.notifier).create('Friday Crew', myName: 'Me');
  final id = made.value!.id;
  for (final g in guests) {
    await r.container.read(crewProvider(id).notifier).addMember(g);
  }
  return id;
}
