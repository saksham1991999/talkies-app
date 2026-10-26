import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/ui/avatar.dart';
import 'package:talkies/ui/theme.dart';

const size = 96.0;

Future<ui.Image> render(WidgetTester tester, Widget child, {Size? view}) async {
  tester.view.physicalSize = view ?? const Size(400, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(dark: false, accentIndex: 0),
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: RepaintBoundary(key: key, child: child),
      ),
    ),
  );
  late ui.Image image;
  await tester.runAsync(() async {
    image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
  });
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Tests draw text in a boxy test font unless the real one is loaded.
  setUpAll(() async {
    for (final (family, path) in [
      ('Tanker', 'assets/fonts/Tanker-Regular.otf'),
      ('Teko', 'assets/fonts/Teko-SemiBold.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  test('initialOf', () {
    expect(initialOf('  priya'), 'P');
    expect(initialOf(''), '?');
    expect(initialOf('अमित'), 'अ');
  });

  testWidgets('the initial sits in the middle of the ring', (tester) async {
    for (final name in ['Asha', 'Mehul', 'Sunita', 'Tara', 'Hari', 'Omar']) {
      final image = await render(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: Avatar(name: name, ink: 0, size: size),
        ),
      );
      final data = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      // Ink pixels inside the inner ring only: the letter.
      var minX = 1 << 20, minY = 1 << 20, maxX = -1, maxY = -1;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final dx = x + 0.5 - size / 2, dy = y + 0.5 - size / 2;
          if (dx * dx + dy * dy > (size * 0.30) * (size * 0.30)) continue;
          final alpha = data.getUint8((y * image.width + x) * 4 + 3);
          if (alpha > 128) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      expect(maxX, greaterThan(0), reason: '$name drew no letter');
      final cx = (minX + maxX + 1) / 2 - size / 2, cy = (minY + maxY + 1) / 2 - size / 2;
      // ignore: avoid_print
      print('$name: letter box ${maxX - minX + 1}x${maxY - minY + 1}, center offset ($cx, $cy)');
      expect(cx.abs(), lessThan(size * 0.04), reason: '$name horizontal');
      expect(cy.abs(), lessThan(size * 0.04), reason: '$name vertical');
    }
  });

  // Contact sheet: AVATAR_SHEET=1 flutter test test/avatar_test.dart
  testWidgets('avatar contact sheet', (tester) async {
    if (Platform.environment['AVATAR_SHEET'] != '1') return;
    final image = await render(
      tester,
      Container(
        color: const Color(0xFFF2CBC1),
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < accents.length; i++)
              Avatar(
                name: ['Asha', 'Bilal', 'Charu', 'Dev', 'Esha', 'Farid', 'Gita', 'Hari', 'Isha', 'Jay', 'Kavya'][i],
                ink: i,
                size: 64,
              ),
            for (final s in [48.0, 40.0, 32.0, 24.0]) Avatar(name: 'Mira', ink: 4, size: s),
            const Avatar(name: 'அமுதா', ink: 2, size: 64),
            const Avatar(name: 'প্রিয়া', ink: 5, size: 64),
          ],
        ),
      ),
      view: const Size(560, 360),
    );
    final bytes = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
    File('build/avatar_sheet.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
