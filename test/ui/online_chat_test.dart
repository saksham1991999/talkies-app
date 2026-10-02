import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/net/api.dart';
import 'package:talkies/state/crews_remote.dart';
import 'package:talkies/state/online.dart';
import 'package:talkies/ui/screens/chat_screen.dart';
import 'package:talkies/ui/screens/search_screen.dart';

import '../support/fake_api.dart';
import 'online_harness.dart';

const gid = 'b6f1a2c3-d4e5-4f60-8a1b-2c3d4e5f6a7b';
const raviId = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
final ravi = cardJson(raviId, 'Ravi Kumar', handle: 'ravi_k', ink: 7);
final me = cardJson(meId, 'Meena', handle: 'meena', ink: 1);

Map<String, dynamic> message(
  int id, {
  Map<String, dynamic>? sender,
  String? body,
  String? code,
  Map<String, dynamic>? args,
  String? film,
  String? night,
}) => {
  'id': id,
  'kind': code == null ? 'text' : 'system',
  'sender': sender,
  'body': body,
  'code': code,
  'args': args,
  'film_id': film,
  'film': film == null ? null : filmJson(film),
  'night_id': night,
  'created_at': '2026-10-01T12:00:00.000Z',
};

List<Map<String, dynamic>> conversation() => [
  message(1, code: 'joined', args: {'name': 'Ravi Kumar'}),
  message(2, sender: ravi, body: 'Saturday works for me'),
  message(3, sender: me, body: 'I can do 8 pm'),
  message(4, sender: ravi, body: 'This one on Saturday?', film: 'Q1', night: 'c0ffee00-1111-4222-8333-444455556666'),
  message(5, code: 'night_set', args: {'night_id': 'c0ffee00-1111-4222-8333-444455556666', 'film_id': 'Q4'}),
  message(6, code: 'poll_open', args: {'night_id': 'n2'}),
  message(7, code: 'wrapped', args: {'night_id': 'n1'}),
  message(8, code: 'left', args: {'name': 'Dad'}),
  message(9, code: 'a_code_from_a_newer_server', args: {}),
];

/// A group of two, and its messages. `before` and `after` answer like the server: older ones, none newer.
FakeApi chatApi({
  List<Map<String, dynamic>>? latest,
  List<Map<String, dynamic>> older = const [],
  bool hasMore = false,
}) {
  return FakeApi()
    ..routes['GET /healthz'] = ((_, _) => {
      'ok': true,
      'api': 1,
      'auth': ['email'],
    })
    ..routes['GET /v1/groups'] = ((_, _) => {
      'items': [
        {'id': gid, 'name': 'Friday Crew', 'invite_code': 'K7M2QX9P', 'deck_version': 0, 'member_count': 2},
      ],
    })
    ..routes['GET /v1/groups/$gid'] = ((_, _) => {
      'id': gid,
      'name': 'Friday Crew',
      'invite_code': 'K7M2QX9P',
      'deck_version': 0,
      'member_count': 2,
      'members': [
        {'id': 'm1', 'name': 'Meena', 'avatar_color': 1, 'handle': 'meena', 'guest': false, 'owner': true, 'me': true},
        {
          'id': 'm2',
          'name': 'Ravi Kumar',
          'avatar_color': 7,
          'handle': 'ravi_k',
          'guest': false,
          'owner': false,
          'me': false,
        },
      ],
    })
    ..routes['GET /v1/groups/$gid/nights'] = ((_, _) => {'items': <Object>[]})
    ..routes['GET /v1/groups/$gid/messages'] = ((q, _) {
      if (q?['before'] != null) return {'items': older, 'has_more': false};
      if (q?['after'] != null) return {'items': <Object>[], 'has_more': false};
      return {'items': latest ?? conversation(), 'has_more': hasMore};
    })
    ..routes['POST /v1/groups/$gid/messages'] = ((_, body) {
      final b = body as Map<String, dynamic>;
      return message(
        100,
        sender: me,
        body: b['body'] as String,
        film: b['film_id'] as String?,
        night: b['night_id'] as String?,
      );
    });
}

Phone online(FakeApi api, {Backend status = Backend.up}) =>
    Phone(status: status, session: Session(meId, testMe()), api: api);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  Future<Phone> open(WidgetTester t, FakeApi api, {Backend status = Backend.up}) async {
    final phone = online(api, status: status);
    await phone.pumpPushed(t, const ChatScreen(crewId: gid), size: const Size(360, 1100));
    return phone;
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  IconButton sendButton(WidgetTester t) =>
      t.widget(find.ancestor(of: find.byTooltip('Send message'), matching: find.byType(IconButton)));

  Future<void> close(WidgetTester t) async {
    await t.pageBack();
    await t.pumpAndSettle();
  }

  testWidgets('messages, a film and a night as tickets, and system lines from their codes', (t) async {
    await open(t, chatApi());
    expect(find.text('FRIDAY CREW'), findsOneWidget);
    // Text slips, with the sender's name on the first of a run. Mine has none.
    expect(find.text('Saturday works for me'), findsOneWidget);
    expect(find.text('I can do 8 pm'), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsNWidgets(2)); // before my message and after it
    expect(find.text('Meena'), findsNothing);
    // The film and the night that came with a message are tickets under it.
    expect(find.text('This one on Saturday?'), findsOneWidget);
    expect(find.text('Sholay'), findsOneWidget);
    expect(find.text('1975'), findsOneWidget);
    expect(find.text('Movie night'), findsOneWidget);
    // System lines in the language of the phone, from code and args. An unknown code is skipped.
    expect(find.text('Ravi Kumar joined'), findsOneWidget);
    expect(find.text('A night is set: Kantara'), findsOneWidget);
    expect(find.text('A night poll is open'), findsOneWidget);
    expect(find.text('The night is wrapped up'), findsOneWidget);
    expect(find.text('Dad left'), findsOneWidget);
    expect(find.textContaining('newer_server'), findsNothing);
    // No time on any message.
    expect(find.textContaining('2026'), findsNothing);
    expect(find.textContaining(RegExp(r'\d\d:\d\d')), findsNothing);
    await close(t);
  });

  testWidgets('the chat is active while open and polls; it stops when the screen goes', (t) async {
    final api = chatApi();
    final phone = await open(t, api);
    expect(phone.container(t).read(chatProvider(gid)).active, isTrue);
    expect(api.count('GET /v1/groups/$gid/messages'), 1);
    await t.pump(chatEvery);
    expect(api.count('GET /v1/groups/$gid/messages'), 2);
    expect(api.queries.last, containsPair('after', '9'));

    // In the background it is quiet, and it asks again when the app comes back.
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pump(chatEvery * 2);
    expect(api.count('GET /v1/groups/$gid/messages'), 2);
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pump();
    await t.pump(chatEvery);
    final n = api.count('GET /v1/groups/$gid/messages');
    expect(n, greaterThan(2));

    await close(t);
    await t.pump(chatEvery * 3);
    expect(api.count('GET /v1/groups/$gid/messages'), n); // no timer outlives the screen
  });

  testWidgets('sending: the text goes to the group and shows as mine; the field clears', (t) async {
    final api = chatApi(
      latest: [message(2, sender: ravi, body: 'Hello')],
    );
    await open(t, api);
    expect(sendButton(t).onPressed, isNull); // nothing to send yet
    await t.enterText(find.byKey(const Key('chat-text')), '  See you there  ');
    await t.pump();
    await t.tap(find.byTooltip('Send message'));
    await t.pumpAndSettle();
    expect(bodyOf(api, 'POST /v1/groups/$gid/messages'), {
      'body': 'See you there',
      'film_id': null,
      'film': null,
      'night_id': null,
    });
    expect(find.text('See you there'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const Key('chat-text'))).controller!.text, isEmpty);
    await close(t);
  });

  testWidgets('a film is attached from the search, shown above the field, and goes with the message', (t) async {
    final api = chatApi(
      latest: [message(2, sender: ravi, body: 'Hello')],
    );
    final phone = await open(t, api);
    await t.tap(find.byTooltip('Attach a film'));
    await t.pumpAndSettle();
    final search = t.widget<SearchScreen>(find.byType(SearchScreen));
    expect(search.onPick, isNotNull);
    search.onPick!(phone.catalog.byId['Q1']!);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Sholay'), findsOneWidget); // the ticket above the field
    // A film alone is a message: the send button is on, and the title is the text.
    await t.tap(find.byTooltip('Send message'));
    await t.pumpAndSettle();
    final body = bodyOf(api, 'POST /v1/groups/$gid/messages') as Map;
    expect(body['body'], 'Sholay');
    expect(body['film_id'], 'Q1');
    expect(find.byTooltip('Remove the film'), findsNothing);
    await close(t);
  });

  testWidgets('an attached film can be taken off', (t) async {
    final phone = await open(t, chatApi());
    await t.tap(find.byTooltip('Attach a film'));
    await t.pumpAndSettle();
    t.widget<SearchScreen>(find.byType(SearchScreen)).onPick!(phone.catalog.byId['Q2']!);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byTooltip('Remove the film'), findsOneWidget);
    await t.tap(find.byTooltip('Remove the film'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Remove the film'), findsNothing);
    await close(t);
  });

  testWidgets('a message that fails says so and keeps the text', (t) async {
    final api = chatApi(
      latest: [message(2, sender: ravi, body: 'Hello')],
    );
    api.routes['POST /v1/groups/$gid/messages'] = (_, _) => throw const ApiError(429, 'rate_limited', 'x');
    await open(t, api);
    await t.enterText(find.byKey(const Key('chat-text')), 'Again');
    await t.pump();
    await t.tap(find.byTooltip('Send message'));
    await t.pumpAndSettle();
    expect(find.text('You are sending too fast. Wait a little.'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const Key('chat-text'))).controller!.text, 'Again');
    await close(t);
  });

  testWidgets('press and hold reports a message of someone else, with a reason; mine is not reportable', (t) async {
    final api = chatApi();
    api.routes['POST /v1/reports'] = (_, _) => {'id': 'r1'};
    await open(t, api);
    await t.longPress(find.text('I can do 8 pm'));
    await t.pumpAndSettle();
    expect(find.text('Why do you report this message?'), findsNothing);

    await t.longPress(find.text('Saturday works for me'));
    await t.pumpAndSettle();
    expect(find.text('Why do you report this message?'), findsOneWidget);
    await t.tap(find.text('Spam'));
    await t.pumpAndSettle();
    expect(api.bodies.last, {'kind': 'message', 'target_id': '2', 'reason': 'spam', 'note': null});
    expect(find.text('Report sent. Thank you.'), findsOneWidget);
    await close(t);
  });

  testWidgets('tapping a sender asks, then blocks them and their messages go', (t) async {
    final api = chatApi();
    api.routes['POST /v1/blocks'] = (_, _) => null;
    api.routes['GET /v1/blocks'] = (_, _) => {'items': <Object>[]};
    await open(t, api);
    await t.tap(find.byKey(const Key('sender-$raviId')).first);
    await t.pumpAndSettle();
    expect(find.text('Block Ravi Kumar?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.count('POST /v1/blocks'), 0);

    await t.tap(find.byKey(const Key('sender-$raviId')).first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm-block')));
    await t.pumpAndSettle();
    expect(bodyOf(api, 'POST /v1/blocks'), {'user_id': raviId});
    expect(find.text('Saturday works for me'), findsNothing);
    expect(find.text('I can do 8 pm'), findsOneWidget);
    expect(find.text('Ravi Kumar is blocked.'), findsOneWidget);
    await close(t);
  });

  testWidgets('older messages load by the button, and at the top of the list', (t) async {
    final api = chatApi(
      latest: [message(10, sender: ravi, body: 'Newest one')],
      older: [message(9, sender: ravi, body: 'An older one')],
      hasMore: true,
    );
    await open(t, api);
    expect(find.byKey(const Key('chat-older')), findsOneWidget);
    expect(find.text('An older one'), findsNothing);
    await tapKey(t, 'chat-older');
    expect(api.queries.last, containsPair('before', '10'));
    expect(find.text('An older one'), findsOneWidget);
    expect(find.byKey(const Key('chat-older')), findsNothing);
    await close(t);
  });

  testWidgets('an empty chat says to say hello; the first answer ends the loading', (t) async {
    await open(t, chatApi(latest: const []));
    expect(find.text('No messages yet. Say hello.'), findsOneWidget);
    await close(t);
  });

  testWidgets('server away when opened: Can\'t reach Talkies, no field, no call', (t) async {
    final api = chatApi();
    api.routes['GET /healthz'] = (_, _) => throw const ApiOffline('down');
    await open(t, api, status: Backend.down);
    expect(find.textContaining("Can't reach Talkies"), findsOneWidget);
    expect(find.byKey(const Key('chat-text')), findsNothing);
    expect(api.count('GET /v1/groups/$gid/messages'), 0);
    await close(t);
  });

  testWidgets('the server goes away while the chat is open: the messages stay, with a bar and Retry', (t) async {
    final api = chatApi();
    await open(t, api);
    api.routes['GET /v1/groups/$gid/messages'] = (_, _) => throw const ApiOffline('down');
    await t.pump(chatEvery);
    await t.pump();
    expect(find.text('Saturday works for me'), findsOneWidget);
    expect(find.byKey(const Key('chat-retry')), findsOneWidget);

    api.routes['GET /v1/groups/$gid/messages'] = (_, _) => {'items': <Object>[], 'has_more': false};
    await tapKey(t, 'chat-retry');
    expect(find.byKey(const Key('chat-retry')), findsNothing);
    await close(t);
  });
}

/// The body of the last call to [key] (a later GET has none).
Object? bodyOf(FakeApi api, String key) => api.bodies[api.calls.lastIndexOf(key)];
