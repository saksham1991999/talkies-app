import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/state/crews.dart';
import 'package:talkies/ui/screens/together_screen.dart';

import 'together_harness.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('with no server the Together tab shows Groups and Nights only, and never asks the network', (t) async {
    phoneSize(t);
    final r = rig();
    await t.pumpWidget(r.app(const TogetherScreen()));
    await t.pumpAndSettle();

    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Nights'), findsOneWidget);
    expect(find.text('Friends'), findsNothing);
    expect(find.text('Join with code'), findsNothing);
    expect(find.byKey(const Key('join-with-code')), findsNothing);
    expect(find.text('New group'), findsOneWidget);

    await t.tap(find.text('Nights'));
    await t.pumpAndSettle();
    expect(find.textContaining('No nights planned yet'), findsOneWidget);
    expect(r.requests, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('a local group can be made and a guest added', (t) async {
    phoneSize(t);
    final r = rig();
    await t.pumpWidget(r.app(const TogetherScreen()));
    await t.pumpAndSettle();
    expect(find.textContaining('No groups yet'), findsOneWidget);

    await t.tap(find.text('New group'));
    await t.pumpAndSettle();
    // No server: the sheet offers no shared group.
    expect(find.byKey(const Key('crew-shared')), findsNothing);
    await t.enterText(find.byKey(const Key('crew-name')), 'Friday Crew');
    await t.enterText(find.byKey(const Key('crew-me')), 'Saksham');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('crew-create')));
    await t.pumpAndSettle();

    // The new group opens.
    expect(find.text('FRIDAY CREW'), findsOneWidget);
    var crew = r.container.read(crewsProvider).crews.single;
    expect(crew.name, 'Friday Crew');
    expect([for (final m in crew.members) (m.name, m.me, m.owner)], [('Saksham', true, true)]);
    expect(crew.shared, isFalse);

    await t.tap(find.byKey(const Key('crew-members')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('member-name')), 'Asha');
    await t.tap(find.byTooltip('Add'));
    await t.pumpAndSettle();

    crew = r.container.read(crewsProvider).crews.single;
    expect([for (final m in crew.members) (m.name, m.guest)], [('Saksham', false), ('Asha', true)]);
    expect(find.text('Asha'), findsOneWidget);

    // The same name twice is refused in plain words.
    await t.enterText(find.byKey(const Key('member-name')), 'asha');
    await t.tap(find.byTooltip('Add'));
    await t.pumpAndSettle();
    expect(find.text('Someone in the group already has that name.'), findsOneWidget);
    expect(r.container.read(crewsProvider).crews.single.members, hasLength(2));
    expect(r.requests, isEmpty);
    expect(t.takeException(), isNull);
  });
}
