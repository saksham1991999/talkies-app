import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/models.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/state/crews_remote.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/state/providers.dart';
import 'package:talkies/state/reminders.dart';
import 'package:talkies/state/together.dart';
import 'package:talkies/ui/format.dart' show appVersion;
import 'package:talkies/ui/screens/crew_screen.dart';
import 'package:talkies/ui/screens/deck_screen.dart';
import 'package:talkies/ui/screens/film_screen.dart';
import 'package:talkies/ui/screens/together_screen.dart';
import 'package:talkies/ui/shell.dart';

import '../together/helpers.dart' show FakeApi, deckJson, emptyTallies, groupJson, memberJson;
import 'together_harness.dart';

/// The gate, in the test's hands: the server is up and the user is signed in while it is true.
class _Gate extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool on) => state = on;
}

final _gate = NotifierProvider<_Gate, bool>(_Gate.new);

const _url = 'https://talkies.test';

/// Who is signed in, in the test's hands.
class _Who extends SessionNotifier {
  @override
  Session? build() => const Session('u1');
  void set(Session? s) => state = s;
}

/// A server with the groups "Friday gang" (mine), "Weekend gang" (to join) and "Cinema club" (to make).
FakeApi _server({bool owner = true}) {
  final api = FakeApi();
  Map<String, dynamic> group(String id, String name) => groupJson(
    id,
    name: name,
    members: [
      memberJson('m1', 'Me', me: true, owner: owner),
      memberJson('m2', 'Asha'),
      memberJson('m3', 'Ravi', guest: true),
    ],
  );
  for (final (id, name) in [('g1', 'Friday gang'), ('g2', 'Weekend gang'), ('g3', 'Cinema club')]) {
    api.routes['GET /v1/groups/$id'] = (_, _) => group(id, name);
    api.routes['GET /v1/groups/$id/nights'] = (_, _) => {'items': <dynamic>[]};
    api.routes['GET /v1/groups/$id/films'] = (_, _) => {'items': <dynamic>[]};
    api.routes['GET /v1/groups/$id/deck'] = (_, _) => id == 'g1' ? _deck(['Q1', 'Q2', 'Q3']) : deckJson(0, []);
    api.routes['GET /v1/groups/$id/tallies'] = (_, _) => emptyTallies();
  }
  api.routes['GET /v1/groups'] = (_, _) => {
    'items': [group('g1', 'Friday gang')],
  };
  api.routes['POST /v1/groups/join'] = (_, _) => {'id': 'g2'};
  api.routes['POST /v1/groups'] = (_, _) => {'id': 'g3'};
  api.routes['POST /v1/groups/g1/invite/rotate'] = (_, _) => {'invite_code': 'WXYZ9876'};
  return api;
}

/// A deck of films with no poster, so the title card draws and nothing touches the network.
Map<String, dynamic> _deck(List<String> ids) => {
  'version': 1,
  'items': [
    for (final id in ids) {'film_id': id, 'film': tFilm(id, title: 'Film $id').toJson(), 'seen_by': 0},
  ],
};

Rig _online(FakeApi api) =>
    rig(apiUrl: _url, api: api, overrides: [onlineProvider.overrideWith((ref) => ref.watch(_gate))]);

void main() {
  setUpAll(loadFonts);

  testWidgets('with the server up and the user signed in, Friends and Join with code appear, and go with the gate', (
    t,
  ) async {
    phoneSize(t);
    final r = _online(_server());
    await t.pumpWidget(r.app(const TogetherScreen()));
    await t.pumpAndSettle();

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Join with code'), findsOneWidget);
    expect(find.text('FRIDAY GANG'), findsOneWidget, reason: 'the shared group is a ticket like the others');
    expect(find.textContaining('Shared'), findsOneWidget);

    await t.tap(find.text('Friends'));
    await t.pumpAndSettle();
    expect(r.container.read(togetherSegmentProvider), TogetherSegment.friends);

    // The server goes away while Friends is open: back to Groups, and nothing online is left.
    r.container.read(_gate.notifier).set(false);
    await t.pumpAndSettle();
    expect(r.container.read(togetherSegmentProvider), TogetherSegment.groups);
    expect(find.text('Friends'), findsNothing);
    expect(find.text('Join with code'), findsNothing);
    expect(find.text('FRIDAY GANG'), findsNothing);
    expect(find.textContaining('No groups yet'), findsOneWidget);
  });

  testWidgets('an invite code opens the join sheet by itself, says what joining shares, and names the group', (
    t,
  ) async {
    phoneSize(t, height: 900);
    final api = _server();
    final r = _online(api);
    await t.pumpWidget(r.app(const TogetherScreen()));
    await t.pumpAndSettle();

    r.container.read(pendingJoinProvider.notifier).set('abcd-2345');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('join-code')), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const Key('join-code'))).controller!.text, 'ABCD2345');
    expect(
      find.text('Joining shares your taste and watchlist with the group deck. Members cannot see who added what.'),
      findsOneWidget,
    );

    await t.tap(find.byKey(const Key('join-go')));
    await t.pumpAndSettle();
    expect(api.calls('POST', '/v1/groups/join').single.body, {'code': 'ABCD2345'});
    expect(find.text('YOU JOINED WEEKEND GANG'), findsOneWidget);
    expect(r.container.read(pendingJoinProvider), isNull, reason: 'a used code does not come back');

    await t.tap(find.text('Open group'));
    await t.pumpAndSettle();
    expect(find.byType(CrewScreen), findsOneWidget);
    expect(find.text('WEEKEND GANG'), findsWidgets);
  });

  testWidgets('a code that is not used does not open the sheet again', (t) async {
    phoneSize(t, height: 900);
    final r = _online(_server());
    await t.pumpWidget(r.app(const TogetherScreen()));
    await t.pumpAndSettle();
    r.container.read(pendingJoinProvider.notifier).set('ABCD2345');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('join-code')), findsOneWidget);
    await t.tapAt(const Offset(20, 20)); // closes the sheet
    await t.pumpAndSettle();
    expect(find.byKey(const Key('join-code')), findsNothing);
    expect(r.container.read(pendingJoinProvider), isNull);
  });

  testWidgets('Join with code takes a typed code, and a code that is not one cannot be sent', (t) async {
    phoneSize(t, height: 900);
    final api = _server();
    final r = _online(api);
    await t.pumpWidget(r.app(const TogetherScreen()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('join-with-code')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('join-code')), 'ABC');
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextButton>(find.descendant(of: find.byKey(const Key('join-go')), matching: find.byType(TextButton)))
          .onPressed,
      isNull,
    );
    await t.enterText(find.byKey(const Key('join-code')), 'abcd 2345');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('join-go')));
    await t.pumpAndSettle();
    expect(api.calls('POST', '/v1/groups/join'), hasLength(1));
  });

  testWidgets('the new group sheet offers an invite link only online, and makes a shared group on the server', (
    t,
  ) async {
    phoneSize(t, height: 900);
    final api = _server();
    final r = _online(api);
    await t.pumpWidget(r.app(const TogetherScreen()));
    await t.pumpAndSettle();
    await t.tap(find.text('New group'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('crew-me')), findsOneWidget, reason: 'a local group asks who holds the phone');
    await t.tap(find.byKey(const Key('crew-shared')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('crew-me')), findsNothing, reason: 'the server knows who you are');
    expect(find.text('Create shared group'), findsOneWidget);
    await t.enterText(find.byKey(const Key('crew-name')), 'Cinema club');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('crew-create')));
    await t.pumpAndSettle();

    expect(api.calls('POST', '/v1/groups').single.body, {'name': 'Cinema club'});
    expect(find.byType(CrewScreen), findsOneWidget);
    expect(r.container.read(sharedCrewsProvider).crews.map((c) => c.id), contains('g3'));
    expect(r.container.read(crewsProvider).crews, isEmpty, reason: 'it is not a local group');
  });

  group('a shared group', () {
    testWidgets('has an invite ticket that shares the link and the code, and a chat', (t) async {
      phoneSize(t, height: 900);
      final r = _online(_server());
      await r.container.read(sharedCrewsProvider.notifier).refresh();
      await t.pumpWidget(r.app(const CrewScreen(crewId: 'g1')));
      await t.pumpAndSettle();

      expect(find.text('FRIDAY GANG'), findsOneWidget);
      expect(find.text('ABCD 2345'), findsOneWidget);
      expect(find.byKey(const Key('crew-chat')), findsOneWidget);
      await t.tap(find.byKey(const Key('crew-share')));
      await t.pumpAndSettle();
      final shared = r.sharer.texts.single;
      expect(shared.text, contains('https://talkies.test/j/ABCD2345'));
      expect(shared.text, contains('ABCD2345'));
      expect(shared.text, contains('Friday gang'));
      expect(shared.subject, 'Join Friday gang on Talkies');

      // The owner makes a new code; the old one stops working.
      await t.tap(find.byKey(const Key('crew-new-code')));
      await t.pumpAndSettle();
      await t.tap(find.text('New code').last);
      await t.pumpAndSettle();
      expect(find.text('WXYZ 9876'), findsOneWidget);
    });

    testWidgets('only the owner can make a new code, delete the group or add guests; others can leave', (t) async {
      phoneSize(t, height: 900);
      final r = _online(_server(owner: false));
      await r.container.read(sharedCrewsProvider.notifier).refresh();
      await t.pumpWidget(r.app(const CrewScreen(crewId: 'g1')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('crew-new-code')), findsNothing);
      await t.tap(find.byKey(const Key('crew-menu')));
      await t.pumpAndSettle();
      expect(find.text('Leave group'), findsOneWidget);
      expect(find.text('Delete group'), findsNothing);
      expect(find.text('Rename group'), findsNothing);
    });

    testWidgets('says it cannot reach Talkies, with Retry, when the server goes away, and comes back with it', (
      t,
    ) async {
      phoneSize(t, height: 900);
      final api = _server();
      final r = _online(api);
      await r.container.read(sharedCrewsProvider.notifier).refresh();
      await t.pumpWidget(r.app(const CrewScreen(crewId: 'g1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('crew-share')), findsOneWidget);

      r.container.read(_gate.notifier).set(false);
      await t.pumpAndSettle();
      expect(find.text("Can't reach Talkies right now. Your diary is safe on this phone."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byKey(const Key('crew-share')), findsNothing);
      expect(find.byKey(const Key('crew-chat')), findsNothing);

      r.container.read(_gate.notifier).set(true);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('crew-share')), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });

  testWidgets('a film only this phone has cannot go to a shared group, and can go to a local one', (t) async {
    phoneSize(t, height: 900);
    final r = _online(_server());
    await r.container.read(sharedCrewsProvider.notifier).refresh();
    final local = await makeCrew(r);
    final own = Film(id: 'my:1', title: 'My film', year: 2020);
    await t.pumpWidget(r.app(FilmScreen(filmId: own.id, fallback: own)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-to-group')));
    await t.pumpAndSettle();

    expect(find.text('Your own films stay on this phone.'), findsOneWidget);
    await t.tap(find.text('Friday gang'));
    await t.pumpAndSettle();
    expect(find.text('Friday Crew'), findsOneWidget, reason: 'the sheet is still open: nothing was added');
    await t.tap(find.text('Friday Crew'));
    await t.pumpAndSettle();
    expect([for (final w in r.container.read(crewsProvider).crew(local)!.films) w.filmId], ['my:1']);
  });

  testWidgets('signing out takes the reminders of shared nights with it and keeps the local ones', (t) async {
    phoneSize(t);
    final r = rig(overrides: [sessionProvider.overrideWith(_Who.new)]);
    r.container.read(settingsProvider.notifier).set((s) => s.copyWith(seenVersion: appVersion));
    final crews = r.container.read(crewsProvider.notifier);
    for (final (night, shared) in [('shared-night', true), ('local-night', false)]) {
      crews.remind(night, shared: shared);
      for (var slot = 0; slot < 2; slot++) {
        await r.reminders.schedule(id: reminderId(night, slot), title: 't', body: 'b', when: DateTime(2030));
      }
    }
    await t.pumpWidget(r.app(const Shell()));
    await t.pumpAndSettle();
    expect(r.reminders.scheduled, hasLength(4));

    (r.container.read(sessionProvider.notifier) as _Who).set(null);
    await t.pumpAndSettle();
    expect(r.reminders.scheduled.keys.toSet(), {reminderId('local-night', 0), reminderId('local-night', 1)});
    expect(r.container.read(crewsProvider).reminders, {'local-night': false});
  });

  group('the deck of a shared group', () {
    testWidgets('swipes as yourself, sends the swipes together, and sends the rest as the deck closes', (t) async {
      phoneSize(t);
      final api = _server();
      api.routes['PUT /v1/groups/g1/swipes'] = (_, body) => {'saved': ((body as Map)['swipes'] as List).length};
      final r = _online(api);
      await r.container.read(sharedCrewsProvider.notifier).refresh();
      await t.pumpWidget(r.app(DeckScreen(crewId: 'g1')));
      await t.pumpAndSettle();
      expect(find.text('1 of 3'), findsOneWidget);

      await t.tap(find.byKey(const Key('vote-want')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('vote-skip')));
      await t.pumpAndSettle();
      expect(find.text('3 of 3'), findsOneWidget);
      expect(api.calls('PUT', '/v1/groups/g1/swipes'), isEmpty, reason: 'they wait a moment to go together');

      // Closing the deck sends what waits, as one request.
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      final sent = api.calls('PUT', '/v1/groups/g1/swipes').single.body as Map;
      expect(sent['swipes'], [
        {'film_id': 'Q1', 'vote': 'want', 'member_id': null},
        {'film_id': 'Q2', 'vote': 'skip', 'member_id': null},
      ]);
    });

    testWidgets('the owner can swipe for a guest, behind the velvet screen; the swipe names the guest', (t) async {
      phoneSize(t);
      final api = _server();
      api.routes['PUT /v1/groups/g1/swipes'] = (_, body) => {'saved': ((body as Map)['swipes'] as List).length};
      final r = _online(api);
      await r.container.read(sharedCrewsProvider.notifier).refresh();
      await t.pumpWidget(r.app(DeckScreen(crewId: 'g1')));
      await t.pumpAndSettle();

      expect(find.text('Ravi'), findsOneWidget, reason: 'a guest');
      expect(find.text('Asha'), findsNothing, reason: 'a member with an account swipes on their own phone');
      await t.tap(find.text('Ravi'));
      await t.pumpAndSettle();
      expect(find.text('RAVI'), findsOneWidget);
      await t.tap(find.byKey(const Key('handoff-confirm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('vote-want')));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      final sent = api.calls('PUT', '/v1/groups/g1/swipes').single.body as Map;
      expect(sent['swipes'], [
        {'film_id': 'Q1', 'vote': 'want', 'member_id': 'm3'},
      ]);
    });

    testWidgets('a member who is not the owner swipes only as themselves: no selector, no passing on', (t) async {
      phoneSize(t);
      final r = _online(_server(owner: false));
      await r.container.read(sharedCrewsProvider.notifier).refresh();
      await t.pumpWidget(r.app(DeckScreen(crewId: 'g1')));
      await t.pumpAndSettle();
      expect(find.text('Ravi'), findsNothing);
      expect(find.byKey(const Key('deck-pass')), findsNothing);
      expect(find.byKey(const Key('vote-want')), findsOneWidget);
    });
  });
}
