import 'package:flutter/material.dart';

import 'theme.dart';

/// A person as a round rubber stamp: a double ring and an initial, in one of
/// the 11 stamp inks. No photo, no gradient: the same stamp the diary uses.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.ink, this.size = 40});

  /// The initial comes from here.
  final String name;

  /// Index into [accents]. Out-of-range values are clamped.
  final int ink;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final i = ink.clamp(0, accents.length - 1);
    // Same lift the theme gives the accent in dark mode.
    final color = p.dark ? Color.lerp(accents[i].color, Colors.white, i == 10 ? 0.75 : 0.12)! : accents[i].color;
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Transform.rotate(
        angle: -0.12,
        child: CustomPaint(size: Size.square(size), painter: AvatarPainter(initialOf(name), color)),
      ),
    );
  }
}

/// First letter of [name], upper case, or `?` when there is none.
String initialOf(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : String.fromCharCode(t.runes.first).toUpperCase();
}

class AvatarPainter extends CustomPainter {
  AvatarPainter(this.initial, this.color);
  final String initial;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, r - size.width * 0.04, ink..strokeWidth = (size.width * 0.055).clamp(1.4, 4));
    canvas.drawCircle(c, r - size.width * 0.15, ink..strokeWidth = (size.width * 0.02).clamp(0.8, 2));
    final tp = TextPainter(
      text: TextSpan(text: initial, style: disp(size.width * 0.46, color, spacing: 0)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width * 0.7);
    // Center the capitals, not the line box: use the baseline and half the cap height.
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final cap = size.width * 0.46 * 0.78; // Tanker capitals are 0.78 em tall (measured).
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy + cap / 2 - base));
  }

  @override
  bool shouldRepaint(AvatarPainter old) => old.initial != initial || old.color != color;
}
