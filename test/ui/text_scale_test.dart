import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/l10n/locale_meta.dart';
import 'package:talkies/ui/common.dart';
import 'package:talkies/ui/screens/record_screen.dart';
import 'package:talkies/ui/screens/settings_screen.dart';
import 'package:talkies/ui/screens/stub_screen.dart';
import 'package:talkies/ui/shell.dart';

import 'layout_harness.dart';
import 'together_harness.dart';

/// The languages whose text is longest, at 375x812 with the system text at 1.0x
/// and 1.3x. 44-language layouts break here: a German or Polish row is 20% wider
/// than the English one before the phone grows the glyphs at all.
///
/// The six long ones were picked by measuring the ARB files, not by guessing.
/// Ranked by total extra characters over English across every key: Tamil +35%,
/// Greek +30%, Romanian +23%, German +22%, Malayalam +21%, Polish +21%. The
/// other two are here because they break differently: Arabic reads right to
/// left (and its longest string is 92 characters longer than the English), and
/// Traditional Chinese has the opposite problem, very short strings that wrap at
/// different places.
///
/// Glyph widths: the repo ships Tanker and Teko, and [loadFonts] adds Roboto from
/// the Flutter SDK for body text. Scripts with no font in the repo (Tamil, Greek,
/// Arabic, Chinese) draw as one-em boxes, wider than the real glyphs. That is the
/// conservative direction: a row that fits here fits on a phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  const worst = [
    ('ta', 'Tamil, +35% text'),
    ('el', 'Greek, +30% text'),
    ('ro', 'Romanian, +23% text'),
    ('de', 'German, +22% text'),
    ('ml', 'Malayalam, +21% text'),
    ('pl', 'Polish, +21% text'),
    ('ar', 'Arabic, right to left'),
    ('zh_Hant', 'Traditional Chinese, short strings'),
  ];

  for (final (code, why) in worst) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('$code at $scale x text', (t) async {
        final r = await layoutRig();
        final locale = localeFor(code);
        final at = '$code ($why) at ${scale}x';

        // The shell builds all five tabs at once, so this one pump covers Home,
        // Stubs, Films, Stats and Together.
        await pumpClean(t, r, const Shell(), locale: locale, textScale: scale, where: 'the shell in $at');
        if (scale != 1.0) {
          // Proves the phone really lays out at that size: a test that silently
          // stayed at 1.0x would prove nothing.
          expect(textScaleOf(t), closeTo(scale, 0.001), reason: 'the text scaler did not apply');
        }
        // Proves the rows really reached the screen, so a silent empty diary
        // cannot turn this into a test of nothing.
        expect(find.byType(StubRow), findsWidgets, reason: 'no stub row on Home in $at');

        await pumpClean(t, r, const SettingsScreen(), locale: locale, textScale: scale, where: 'Settings in $at');
        await pumpClean(
          t,
          r,
          StubScreen(stubId: r.stub.id),
          locale: locale,
          textScale: scale,
          where: 'a ticket in $at',
        );
        expect(find.byType(TicketCard), findsOneWidget, reason: 'the ticket did not draw in $at');
        await pumpClean(
          t,
          r,
          RecordScreen(film: r.film),
          locale: locale,
          textScale: scale,
          where: 'the record screen in $at',
        );
      });
    }
  }
}
