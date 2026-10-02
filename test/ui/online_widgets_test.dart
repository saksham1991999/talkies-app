import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/together.dart';
import 'package:talkies/ui/online_widgets.dart';
import 'package:talkies/ui/screens/friend_screen.dart';

import '../support/fake_api.dart';
import 'online_harness.dart';

Phone online(FakeApi api, {List<dynamic> shared = const []}) => Phone(
  status: Backend.up,
  session: Session(meId, testMe()),
  api: api,
  overrides: [shareTextProvider.overrideWithValue((text, subject, origin) async => shared.add((text, subject)))],
);

const line = 'Shared from Talkies, a film diary that looks like ticket stubs.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  group('FriendsWhoWatched', () {
    FakeApi who({Object? Function()? reply}) => socialApi()
      ..routes['GET /v1/films/Q1/friends'] = ((_, _) =>
          reply?.call() ??
          {
            'items': [
              {'user': cardJson(ashaId, 'Asha', handle: 'asha_k', ink: 3), 'rating': 4.5},
              {'user': cardJson(taraId, 'Tara', ink: 6), 'rating': null},
            ],
          });

    Widget host(Film film) => Scaffold(
      body: ListView(children: [FriendsWhoWatched(film: film)]),
    );

    testWidgets('the stamps of friends who watched, with the rating they share; a tap opens the friend', (t) async {
      final api = who();
      final phone = online(api);
      await phone.pump(t, host(phone.catalog.byId['Q1']!));
      await t.pumpAndSettle();
      expect(find.text('Friends who watched this'), findsOneWidget);
      expect(find.byKey(const Key('who-$ashaId')), findsOneWidget);
      expect(find.byKey(const Key('who-$taraId')), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget); // Tara shares none: no figure under her stamp
      expect(find.byType(Text).evaluate().where((e) => (e.widget as Text).data == '4.5').length, 1);
      expect(t.getSize(find.byKey(const Key('who-$taraId'))).height, greaterThanOrEqualTo(44));

      api.routes['GET /v1/users/$taraId'] = (_, _) => throw const ApiError(404, 'not_found', 'x');
      await t.tap(find.byKey(const Key('who-$taraId')));
      await t.pumpAndSettle();
      expect(find.byType(FriendScreen), findsOneWidget);
    });

    testWidgets('asked once for a film, and again only after ten minutes', (t) async {
      final api = who();
      final phone = online(api);
      await phone.pump(t, host(phone.catalog.byId['Q1']!));
      await t.pumpAndSettle();
      expect(api.count('GET /v1/films/Q1/friends'), 1);
      await phone.pump(t, const SizedBox()); // the film screen is left and opened again
      await phone.pump(t, host(phone.catalog.byId['Q1']!));
      await t.pumpAndSettle();
      expect(api.count('GET /v1/films/Q1/friends'), 1); // the answer is kept for ten minutes
      expect(find.text('Friends who watched this'), findsOneWidget);
    });

    testWidgets('a custom film draws nothing and asks nothing', (t) async {
      final api = who();
      final phone = online(api);
      await phone.pump(t, host(const Film(id: 'my:1', title: 'Home video')));
      await t.pumpAndSettle();
      expect(find.text('Friends who watched this'), findsNothing);
      expect(api.calls.where((c) => c.contains('/films/')), isEmpty);
    });

    testWidgets('offline, signed out or with no server it draws nothing and asks nothing', (t) async {
      for (final phone in [
        Phone(status: Backend.down, session: Session(meId, testMe()), api: who()),
        Phone(status: Backend.up, api: who()),
        Phone(configured: false),
      ]) {
        await t.pumpWidget(const SizedBox());
        await phone.pump(t, host(phone.catalog.byId['Q1']!));
        await t.pumpAndSettle();
        expect(find.text('Friends who watched this'), findsNothing);
        expect(phone.api?.calls.where((c) => c.contains('/films/')) ?? const [], isEmpty);
        expect(phone.server.total, 0);
      }
    });

    testWidgets('a failing server is silent', (t) async {
      for (final fail in [const ApiOffline('down'), const ApiError(500, 'oops', 'oops')]) {
        final api = who(reply: () => throw fail);
        final phone = online(api);
        await t.pumpWidget(const SizedBox());
        await phone.pump(t, host(phone.catalog.byId['Q1']!));
        await t.pumpAndSettle();
        expect(find.text('Friends who watched this'), findsNothing);
        expect(t.takeException(), isNull);
      }
    });

    testWidgets('nobody watched it: nothing', (t) async {
      final phone = online(who(reply: () => {'items': <Object>[]}));
      await phone.pump(t, host(phone.catalog.byId['Q1']!));
      await t.pumpAndSettle();
      expect(find.text('Friends who watched this'), findsNothing);
    });
  });

  group('shareText', () {
    test('note, title with year, the Wikipedia link and a Talkies line, one to a line', () {
      const film = Film(id: 'Q1', title: 'Sholay', year: 1975, wiki: 'Sholay');
      expect(
        shareText(film, ' Watch it with chai ', line),
        'Watch it with chai\nSholay (1975)\nhttps://en.wikipedia.org/wiki/Sholay\n$line',
      );
    });

    test('no note, no year, and a title with spaces and a custom film', () {
      const kgf = Film(id: 'Q3', title: 'K.G.F: Chapter 2', wiki: 'K.G.F: Chapter 2');
      expect(shareText(kgf, '', line), 'K.G.F: Chapter 2\nhttps://en.wikipedia.org/wiki/K.G.F%3A_Chapter_2\n$line');
      const mine = Film(id: 'my:1', title: 'Home video', year: 2020, wiki: 'Home video');
      expect(shareText(mine, '', line), 'Home video (2020)\n$line');
    });
  });

  group('SendFilmButton', () {
    Future<void> open(WidgetTester t, Phone phone, Film film) async {
      await phone.pump(
        t,
        Scaffold(
          body: Center(child: SendFilmButton(film: film)),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('send-film')));
      await t.pumpAndSettle();
    }

    testWidgets('with no account: a note and Other apps, and the share sheet gets the text', (t) async {
      final shared = <dynamic>[];
      final phone = Phone(
        configured: false,
        overrides: [shareTextProvider.overrideWithValue((text, subject, origin) async => shared.add((text, subject)))],
      );
      await open(t, phone, phone.catalog.byId['Q1']!);
      expect(find.text('SHOLAY'), findsOneWidget);
      expect(find.text('Send to a friend'), findsNothing);
      await t.enterText(find.byKey(const Key('send-note')), 'Watch it with chai');
      await t.tap(find.byKey(const Key('send-other')));
      await t.pumpAndSettle();
      expect(shared, [('Watch it with chai\nSholay (1975)\nhttps://en.wikipedia.org/wiki/Sholay\n$line', 'Sholay')]);
      expect(phone.server.total, 0);
    });

    testWidgets('the note stops at 140 characters', (t) async {
      final phone = Phone(configured: false);
      await open(t, phone, phone.catalog.byId['Q1']!);
      await t.enterText(find.byKey(const Key('send-note')), 'x' * 200);
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const Key('send-note'))).controller!.text.length, 140);
    });

    testWidgets('online: the friends, and one tap sends the film with the note', (t) async {
      final api = socialApi()..routes['POST /v1/films/send'] = ((_, _) => null);
      final phone = online(api);
      await open(t, phone, phone.catalog.byId['Q1']!);
      expect(find.text('Send to a friend'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Kabir'), findsOneWidget);
      await t.enterText(find.byKey(const Key('send-note')), 'Great film');
      await t.tap(find.byKey(const Key('send-to-$ashaId')));
      await t.pumpAndSettle();
      final body = api.bodies[api.calls.lastIndexOf('POST /v1/films/send')] as Map;
      expect(body['user_id'], ashaId);
      expect(body['film_id'], 'Q1');
      expect(body['note'], 'Great film');
      expect(body['film'], isA<Map>());
      expect(find.text('Sent'), findsOneWidget);
      expect(find.byKey(const Key('send-to-$ashaId')), findsNothing);
      expect(find.byKey(const Key('send-to-$kabirId')), findsOneWidget);
    });

    testWidgets('a refusal gets a calm line, and the friend can be tried again', (t) async {
      final api = socialApi();
      final phone = online(api);
      await open(t, phone, phone.catalog.byId['Q1']!);
      for (final (error, text) in [
        (const ApiError(429, 'rate_limited', 'x'), 'You are sending too fast. Wait a little.'),
        (const ApiError(403, 'forbidden', 'x'), 'You cannot send to this person.'),
        (const ApiError(500, 'oops', 'x'), 'Could not send. Try again.'),
        (const ApiOffline('down'), "Can't reach Talkies right now. Your diary is safe on this phone."),
      ]) {
        api.routes['POST /v1/films/send'] = (_, _) => throw error;
        await t.ensureVisible(find.byKey(const Key('send-to-$ashaId')));
        await t.tap(find.byKey(const Key('send-to-$ashaId')));
        await t.pumpAndSettle();
        expect(find.text(text), findsOneWidget, reason: '$error');
        expect(find.byKey(const Key('send-to-$ashaId')), findsOneWidget);
      }
    });

    testWidgets('online with no friends says how to get some', (t) async {
      final api = socialApi()..routes['GET /v1/friends'] = ((_, _) => {'items': <Object>[]});
      final phone = online(api);
      await open(t, phone, phone.catalog.byId['Q1']!);
      expect(find.text('Add friends to send films to them.'), findsOneWidget);
      expect(find.byKey(const Key('send-other')), findsOneWidget);
    });
  });

  group('FriendsStrip', () {
    testWidgets('draws nothing and asks nothing unless the server is up and somebody is signed in', (t) async {
      for (final phone in [
        Phone(status: Backend.down, session: Session(meId, testMe()), api: socialApi()),
        Phone(status: Backend.up, api: socialApi()),
        Phone(configured: false),
      ]) {
        await t.pumpWidget(const SizedBox());
        await phone.pump(t, const Scaffold(body: FriendsStrip()));
        await t.pumpAndSettle();
        expect(find.text('Friends are watching'), findsNothing);
        expect(phone.api?.count('GET /v1/feed') ?? 0, 0);
        expect(phone.server.total, 0);
      }
    });

    testWidgets('what friends watched, with the friend on the poster; sent films and reactions are not in it', (
      t,
    ) async {
      final api = socialApi();
      final phone = online(api);
      await phone.pump(t, const Scaffold(body: FriendsStrip()));
      await t.pumpAndSettle();
      expect(api.count('GET /v1/feed'), 1);
      expect(find.text('Friends are watching'), findsOneWidget);
      expect(find.text('Sholay'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Dilwale Dulhania Le Jayenge'), findsNothing);
      expect(find.text('K.G.F: Chapter 2'), findsNothing);
    });

    testWidgets('a name is cut to its first word on the poster, and a long word to 11 letters and a dot', (t) async {
      final api = socialApi(
        feed: [
          feedItem('w:1', 'watched', cardJson(ashaId, 'Venkatasubramanian Iyer', ink: 1), 'Q1'),
          feedItem('w:2', 'watched', cardJson(taraId, 'Tara Singh', ink: 2), 'Q4'),
        ],
      );
      final phone = online(api);
      await phone.pump(t, const Scaffold(body: FriendsStrip()));
      await t.pumpAndSettle();
      expect(find.text('Venkatasubr…'), findsOneWidget);
      expect(find.text('Tara'), findsOneWidget);
    });

    testWidgets('nothing in the feed, nothing drawn', (t) async {
      final phone = online(socialApi(feed: const []));
      await phone.pump(t, const Scaffold(body: FriendsStrip()));
      await t.pumpAndSettle();
      expect(find.text('Friends are watching'), findsNothing);
    });

    testWidgets('See all goes to the Friends segment of the Together tab', (t) async {
      final phone = online(socialApi());
      await phone.pump(t, const Scaffold(body: FriendsStrip()));
      await t.pumpAndSettle();
      await t.tap(find.text('See all'));
      await t.pump();
      final c = phone.container(t);
      expect(c.read(tabProvider), togetherTab);
      expect(c.read(togetherSegmentProvider), TogetherSegment.friends);
    });

    testWidgets('the strip waits for the server: asks when the status turns up', (t) async {
      final api = socialApi();
      final phone = Phone(
        session: Session(meId, testMe()),
        api: api,
        // The real status machine: unknown until a probe says up.
      );
      await phone.pump(t, const Scaffold(body: FriendsStrip()));
      await t.pumpAndSettle();
      expect(api.count('GET /v1/feed'), 0);
      expect(find.text('Friends are watching'), findsNothing);
      await phone.container(t).read(backendProvider.notifier).probe(force: true);
      await t.pumpAndSettle();
      expect(api.count('GET /v1/feed'), 1);
      expect(find.text('Friends are watching'), findsOneWidget);
    });
  });
}
