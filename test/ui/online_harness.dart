import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/social.dart';
import 'package:talkies/l10n/gen/app_localizations.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/ui/theme.dart';

import '../support/device.dart' show MemoryStorage, testCatalog;
import '../support/fake_api.dart';
import '../support/fake_backend.dart';

/// Tanker, Teko and Roboto with their real glyph metrics. Tests draw boxy Ahem letters unless fonts are
/// loaded, and Ahem is far wider than any real font, which would fake overflow. Roboto comes from the Flutter
/// SDK; without it the text stays Ahem and the overflow checks only get stricter.
Future<void> loadFonts() async {
  for (final (family, path) in [
    ('Tanker', 'assets/fonts/Tanker-Regular.otf'),
    ('Teko', 'assets/fonts/Teko-SemiBold.ttf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(path))).load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  var any = false;
  for (final f in ['Regular', 'Medium', 'Bold', 'Italic', 'Light']) {
    final file = File('$dir/Roboto-$f.ttf');
    if (!file.existsSync()) continue;
    roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    any = true;
  }
  if (any) await roboto.load();
}

class _Status extends BackendNotifier {
  _Status(this.status);
  final Backend status;
  @override
  Backend build() => status;
}

class _Who extends SessionNotifier {
  _Who(this.session);
  final Session? session;
  @override
  Session? build() => session;
}

class _Methods extends ServerAuth {
  _Methods(this.methods);
  final List<String> methods;
  @override
  List<String> build() => methods;
}

const meId = '11111111-1111-4111-8111-000000000001';

/// A signed-in user for tests that do not sign in through the screen.
Me testMe({
  String? name = 'Meena',
  String? handle = 'meena',
  int ink = 1,
  bool friends = false,
  bool ratings = false,
}) => Me(
  id: meId,
  handle: handle,
  displayName: name,
  avatarColor: ink,
  visibility: friends ? ProfileVisibility.friends : ProfileVisibility.private,
  shareRatings: ratings,
);

/// A phone for widget tests: a documents folder, the small catalog, and either the in-memory server
/// ([server]) or a table of routes ([api]) behind the online layer. Nothing runs in the background.
class Phone {
  Phone({
    this.configured = true,
    FakeBackend? server,
    this.api,
    this.status,
    this.session,
    this.auth,
    this.locale = const Locale('en'),
    this.dark = false,
    this.overrides = const [],
  }) : server = server ?? FakeBackend(),
       dir = Directory.systemTemp.createTempSync('talkies_ui'),
       storage = MemoryStorage() {
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  }

  /// False builds the app with no server address: no online code may run.
  final bool configured;
  final FakeBackend server;

  /// When set, every call goes to this table instead of [server].
  final FakeApi? api;

  /// Forces the backend status and the signed-in user, like the gate tests do.
  final Backend? status;
  final Session? session;

  /// What the server lists for sign-in, when forced.
  final List<String>? auth;
  final Locale locale;
  final bool dark;
  final List<Override> overrides;
  final Directory dir;
  final MemoryStorage storage;
  final Catalog catalog = testCatalog();

  /// Built once: pumping a second screen into the same scope must not change the overrides.
  late final List<Override> _overrides = [
    docsDirProvider.overrideWithValue(dir),
    apiUrlProvider.overrideWithValue(configured ? 'https://talkies.test' : ''),
    httpClientProvider.overrideWithValue(server.client),
    tokenStoreProvider.overrideWithValue(TokenStore(storage)),
    autoRefreshProvider.overrideWithValue(false),
    nowProvider.overrideWithValue(() => DateTime.utc(2026, 10, 1, 12)),
    todayProvider.overrideWithValue(DateTime(2026, 10, 1)),
    catalogProvider.overrideWith((ref) => catalog),
    if (api != null) apiProvider.overrideWithValue(api!),
    if (status != null) backendProvider.overrideWith(() => _Status(status!)),
    if (session != null) sessionProvider.overrideWith(() => _Who(session)),
    if (auth != null) serverAuthProvider.overrideWith(() => _Methods(auth!)),
    ...overrides,
  ];

  final _shot = GlobalKey();

  Widget app(Widget home, {double textScale = 1.0}) => ProviderScope(
    overrides: _overrides,
    child: RepaintBoundary(
      key: _shot,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark: dark, accentIndex: 0),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );

  /// A phone-sized window (default 360 x 740 dp) and the screen on it.
  Future<void> pump(WidgetTester t, Widget home, {Size size = const Size(360, 740), double textScale = 1.0}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(home, textScale: textScale));
    await t.pump();
  }

  /// [screen] pushed on top of a plain page, so it can pop. Taps "open" to get there.
  Future<void> pumpPushed(
    WidgetTester t,
    Widget screen, {
    Size size = const Size(360, 740),
    double textScale = 1.0,
  }) async {
    await pump(
      t,
      Scaffold(
        body: Center(
          child: Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      size: size,
      textScale: textScale,
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  /// Writes the screen as a PNG into the folder named by the SHOTS environment variable, to look at it. It does
  /// nothing when the variable is not set, so a normal run writes no file.
  Future<void> shot(WidgetTester t, String name) async {
    final dir = Platform.environment['SHOTS'];
    if (dir == null) return;
    await t.runAsync(() async {
      final boundary = _shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  ProviderContainer container(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
}

/// The text of the one error a pumped screen raised, or null. Overflow shows up here.
Object? takeError(WidgetTester t) => t.takeException();

// ---------------------------------------------------------------------------
// Wire data for the social screens

const ashaId = '22222222-2222-4222-8222-00000000000a';
const rohanId = '22222222-2222-4222-8222-00000000000b';
const taraId = '22222222-2222-4222-8222-00000000000c';
const kabirId = '22222222-2222-4222-8222-00000000000d';

Map<String, dynamic> cardJson(String id, String name, {String? handle, int ink = 0}) => {
  'id': id,
  'handle': handle,
  'display_name': name,
  'avatar_color': ink,
};

/// The film snapshot of a catalog film, as the server sends it.
Map<String, dynamic> filmJson(String id) => testCatalog().byId[id]!.toJson();

Map<String, dynamic> feedItem(
  String id,
  String kind,
  Map<String, dynamic> user,
  String film, {
  double? rating,
  int? reaction,
  String? note,
  int? mine,
}) => {
  'id': id,
  'kind': kind,
  'user': user,
  'film_id': film,
  'film': filmJson(film),
  'rating': rating,
  'reaction': reaction,
  'note': note,
  'my_reaction': mine,
};

/// A server with friends: Asha (match 74, you both watched 12), a friend who keeps films private, one request
/// each way, and a feed of a watched film, a sent film and a reaction.
FakeApi socialApi({String? feedNext, List<Map<String, dynamic>>? feed}) {
  final asha = cardJson(ashaId, 'Asha', handle: 'asha_k', ink: 3);
  final kabir = cardJson(kabirId, 'Kabir', handle: 'kabir', ink: 5);
  return FakeApi()
    ..routes['GET /healthz'] = ((_, _) => {
      'ok': true,
      'api': 1,
      'auth': ['email'],
    })
    ..routes['GET /v1/friends'] = ((_, _) => {
      'items': [
        {
          'card': asha,
          'visible': true,
          'match': {'both': 12, 'pct': 74},
        },
        {'card': kabir, 'visible': false, 'match': null},
      ],
    })
    ..routes['GET /v1/friends/requests'] = ((_, _) => {
      'incoming': [cardJson(rohanId, 'Rohan', handle: 'rohan', ink: 2)],
      'outgoing': [cardJson(taraId, 'Tara', handle: 'tara', ink: 6)],
    })
    ..routes['GET /v1/feed'] = ((q, _) => {
      'items':
          feed ??
          [
            feedItem('w:30', 'watched', asha, 'Q1', rating: 4.5),
            feedItem('s:29', 'sent', asha, 'Q2', note: 'Watch this with chai'),
            feedItem('r:28', 'reaction', kabir, 'Q3', reaction: 0),
          ],
      'next_cursor': q?['cursor'] == null ? feedNext : null,
    });
}
