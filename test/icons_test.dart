import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/ui/icons.dart';

void main() {
  testWidgets('every house icon paints', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(children: [for (final i in Tk.values) TkIcon(i, size: 32, color: Colors.black)]),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(TkIcon), findsNWidgets(Tk.values.length));
  });

  // Contact sheet for eyeballing the set: ICON_SHEET=1 flutter test test/icons_test.dart
  testWidgets('icon contact sheet', (tester) async {
    if (Platform.environment['ICON_SHEET'] != '1') return;
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFF2CBC1),
            width: 720,
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [for (final i in Tk.values) TkIcon(i, size: 96, color: const Color(0xFF2A1316))],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/icon_sheet.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
