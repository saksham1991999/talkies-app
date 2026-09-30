import 'dart:math' as math;

import 'package:flutter/material.dart';

/// House icon set. Drawn on a 24 grid with a 1.9 round stroke. Closed shapes
/// carry the ticket notch (home door, stub sides) so the set reads as ours.
enum Tk {
  home,
  stubs,
  calendar,
  films,
  stats,
  settings,
  search,
  plus,
  share,
  back,
  close,
  bookmark,
  bookmarked, //
  filter,
  sort,
  grid,
  list,
  edit,
  trash,
  left,
  right,
  down,
  check,
  photo,
  info,
  refresh,
  again,
}

class TkIcon extends StatelessWidget {
  const TkIcon(this.icon, {super.key, this.size = 24, this.color});
  final Tk icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _TkPainter(icon, color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color!),
  );
}

class _TkPainter extends CustomPainter {
  _TkPainter(this.icon, this.color);
  final Tk icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final s = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    void l(double x1, double y1, double x2, double y2) => canvas.drawLine(Offset(x1, y1), Offset(x2, y2), s);
    Path poly(List<double> p, {bool close = false}) {
      final path = Path()..moveTo(p[0], p[1]);
      for (var i = 2; i < p.length; i += 2) {
        path.lineTo(p[i], p[i + 1]);
      }
      if (close) path.close();
      return path;
    }

    RRect rr(double l, double t, double r, double b, double rad) => RRect.fromLTRBR(l, t, r, b, Radius.circular(rad));

    switch (icon) {
      case Tk.home:
        canvas.drawPath(poly([3.5, 11, 12, 4, 20.5, 11]), s);
        canvas.drawPath(
          Path()
            ..moveTo(6, 9.5)
            ..lineTo(6, 20)
            ..lineTo(9.8, 20)
            ..arcToPoint(const Offset(14.2, 20), radius: const Radius.circular(2.2))
            ..lineTo(18, 20)
            ..lineTo(18, 9.5),
          s,
        );
      case Tk.stubs:
        canvas.drawPath(_ticket(3, 6, 21, 18, 2, 2.1), s);
        for (final y in [8.4, 12.0, 15.6]) {
          l(15, y - 0.5, 15, y + 0.5);
        }
      case Tk.calendar:
        canvas.drawRRect(rr(4, 5.5, 20, 20.5, 2.5), s);
        l(8.5, 3, 8.5, 7.5);
        l(15.5, 3, 15.5, 7.5);
        l(4, 10.5, 20, 10.5);
        canvas.drawCircle(const Offset(15.3, 15.6), 1.7, fill);
      case Tk.films:
        canvas.drawRRect(rr(5, 3, 19, 21, 2), s);
        canvas.drawPath(poly([12.6, 3, 12.6, 9.5, 14.6, 8, 16.6, 9.5, 16.6, 3]), s);
        l(8.5, 14.5, 12, 14.5);
        l(8.5, 17.5, 15.5, 17.5);
      case Tk.stats:
        l(6, 19.5, 6, 13);
        l(12, 19.5, 12, 5.5);
        l(18, 19.5, 18, 10);
      case Tk.settings:
        l(4, 7, 7, 7);
        l(11, 7, 20, 7);
        canvas.drawCircle(const Offset(9, 7), 2, s);
        l(4, 12, 13, 12);
        l(17, 12, 20, 12);
        canvas.drawCircle(const Offset(15, 12), 2, s);
        l(4, 17, 6, 17);
        l(10, 17, 20, 17);
        canvas.drawCircle(const Offset(8, 17), 2, s);
      case Tk.search:
        canvas.drawCircle(const Offset(10.5, 10.5), 6, s);
        l(15.2, 15.2, 20, 20);
      case Tk.plus:
        l(12, 5, 12, 19);
        l(5, 12, 19, 12);
      case Tk.share:
        canvas.drawPath(poly([10, 5, 6.5, 5, 4.5, 7, 4.5, 17.5, 6.5, 19.5, 17, 19.5, 19, 17.5, 19, 14]), s);
        l(11, 13, 19.5, 4.5);
        canvas.drawPath(poly([13.5, 4.5, 19.5, 4.5, 19.5, 10.5]), s);
      case Tk.back:
        l(19, 12, 5.5, 12);
        canvas.drawPath(poly([11, 6.5, 5.5, 12, 11, 17.5]), s);
      case Tk.close:
        l(6.5, 6.5, 17.5, 17.5);
        l(17.5, 6.5, 6.5, 17.5);
      case Tk.bookmark:
      case Tk.bookmarked:
        final b = poly([7, 4, 17, 4, 17, 20, 12, 16, 7, 20], close: true);
        canvas.drawPath(b, s);
        if (icon == Tk.bookmarked) canvas.drawPath(b, fill);
      case Tk.filter:
        canvas.drawPath(poly([4, 5, 20, 5, 14, 12.5, 14, 19, 10, 17, 10, 12.5], close: true), s);
      case Tk.sort:
        l(8, 19, 8, 5);
        canvas.drawPath(poly([4.5, 8.5, 8, 5, 11.5, 8.5]), s);
        l(16, 5, 16, 19);
        canvas.drawPath(poly([12.5, 15.5, 16, 19, 19.5, 15.5]), s);
      case Tk.grid:
        for (final (x, y) in [(4.0, 4.0), (13.5, 4.0), (4.0, 13.5), (13.5, 13.5)]) {
          canvas.drawRRect(rr(x, y, x + 6.5, y + 6.5, 1.5), s);
        }
      case Tk.list:
        for (final y in [7.0, 12.0, 17.0]) {
          l(9.5, y, 20, y);
          canvas.drawCircle(Offset(5, y), 1.2, fill);
        }
      case Tk.edit:
        canvas.drawPath(poly([4, 20, 4.8, 16, 15, 5.8, 18.2, 9, 8, 19.2], close: true), s);
        l(12.8, 8, 16, 11.2);
      case Tk.trash:
        l(4, 7, 20, 7);
        canvas.drawPath(poly([9, 7, 9.6, 4.5, 14.4, 4.5, 15, 7]), s);
        canvas.drawPath(poly([6.2, 7, 7.2, 20, 16.8, 20, 17.8, 7]), s);
        l(10.2, 11, 10.2, 16);
        l(13.8, 11, 13.8, 16);
      case Tk.left:
        canvas.drawPath(poly([15, 5, 8, 12, 15, 19]), s);
      case Tk.right:
        canvas.drawPath(poly([9, 5, 16, 12, 9, 19]), s);
      case Tk.down:
        canvas.drawPath(poly([6, 9, 12, 15, 18, 9]), s);
      case Tk.check:
        canvas.drawPath(poly([5, 12.5, 10, 17.5, 19, 7]), s);
      case Tk.photo:
        canvas.drawRRect(rr(3, 6.5, 21, 19.5, 2.5), s);
        canvas.drawPath(poly([8, 6.5, 9.5, 4.2, 14.5, 4.2, 16, 6.5]), s);
        canvas.drawCircle(const Offset(12, 13), 3.4, s);
      case Tk.info:
        canvas.drawCircle(const Offset(12, 12), 9, s);
        l(12, 11, 12, 16.5);
        canvas.drawCircle(const Offset(12, 7.8), 1.15, fill);
      case Tk.refresh:
      case Tk.again:
        const c = Offset(12, 12.5);
        canvas.drawArc(Rect.fromCircle(center: c, radius: 7), -math.pi * 0.35, math.pi * 1.55, false, s);
        final end = c + Offset.fromDirection(-math.pi * 0.35, 7);
        canvas.drawPath(poly([end.dx - 4.2, end.dy - 0.8, end.dx, end.dy, end.dx + 0.6, end.dy - 4.2]), s);
    }
  }

  @override
  bool shouldRepaint(_TkPainter old) => old.icon != icon || old.color != color;
}

/// Ticket outline with semicircle notches on the left and right edges.
Path _ticket(double l, double t, double r, double b, double rad, double notch) {
  final cy = (t + b) / 2;
  return Path()
    ..moveTo(l + rad, t)
    ..lineTo(r - rad, t)
    ..arcToPoint(Offset(r, t + rad), radius: Radius.circular(rad))
    ..lineTo(r, cy - notch)
    ..arcToPoint(Offset(r, cy + notch), radius: Radius.circular(notch), clockwise: false)
    ..lineTo(r, b - rad)
    ..arcToPoint(Offset(r - rad, b), radius: Radius.circular(rad))
    ..lineTo(l + rad, b)
    ..arcToPoint(Offset(l, b - rad), radius: Radius.circular(rad))
    ..lineTo(l, cy + notch)
    ..arcToPoint(Offset(l, cy - notch), radius: Radius.circular(notch), clockwise: false)
    ..lineTo(l, t + rad)
    ..arcToPoint(Offset(l + rad, t), radius: Radius.circular(rad))
    ..close();
}

/// Tappable house icon with a tooltip, 44pt target.
class TkButton extends StatelessWidget {
  const TkButton(this.icon, {super.key, required this.tooltip, required this.onPressed, this.color, this.size = 24});
  final Tk icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    icon: TkIcon(icon, size: size, color: color),
  );
}
