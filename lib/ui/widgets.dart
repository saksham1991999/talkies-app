import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart' show userAgent;
import '../data/models.dart';
import '../state/providers.dart';
import 'icons.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Posters

const _posterInks = [
  Color(0xFF3A1519), Color(0xFF1C4F4C), Color(0xFF7A2E22), Color(0xFF2F3F6B), //
  Color(0xFF5C4A17), Color(0xFF4A2A44), Color(0xFF2D4A2A),
];

/// Poster files on disk. The default cache keeps only 200 files for 30 days.
// ponytail: 2,000 files (about 140 MB at most); diaries past ~1,500 films evict
// each other, copy their posters into the documents dir if that happens.
final posterCache = CacheManager(
  Config('posters', stalePeriod: const Duration(days: 365), maxNrOfCacheObjects: 2000),
);

/// Downloads posters that are not on disk yet, one at a time, so they show
/// at once when the user opens them. Never throws.
Future<void> prefetchPosters(Iterable<Film> films) async {
  for (final url in {for (final f in films) ?f.posterUrl}) {
    try {
      // Not getSingleFile: it downloads again once a file is 7 days old.
      if (await posterCache.getFileFromCache(url) != null) continue;
      await posterCache.downloadFile(url, authHeaders: const {'User-Agent': userAgent});
    } catch (_) {
      // Offline or a missing file: the widget shows the title card.
    }
  }
}

/// Film poster. Falls back to a printed title card when offline or missing.
class Poster extends ConsumerWidget {
  const Poster(this.film, {super.key, this.width = 60, this.radius = 4});
  final Film film;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = width * 1.5;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget img;
    final rel = film.posterFile;
    final file = rel == null ? null : File(rel.startsWith('/') ? rel : '${ref.watch(docsDirProvider).path}/$rel');
    final url = film.posterUrl;
    if (file != null && file.existsSync()) {
      img = Image.file(file, width: width, height: h, fit: BoxFit.cover, cacheWidth: (width * dpr).round());
    } else if (url != null) {
      img = CachedNetworkImage(
        imageUrl: url,
        cacheManager: posterCache,
        httpHeaders: const {'User-Agent': userAgent},
        width: width,
        height: h,
        fit: BoxFit.cover,
        memCacheWidth: (width * dpr).round(),
        fadeInDuration: const Duration(milliseconds: 160),
        // The placeholder sits on top; the 1 s default hides a ready poster.
        fadeOutDuration: const Duration(milliseconds: 160),
        placeholder: (_, _) => TitleCard(film, width: width),
        errorWidget: (_, _, _) => TitleCard(film, width: width),
      );
    } else {
      img = TitleCard(film, width: width);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: width, height: h, child: img),
    );
  }
}

/// Typographic stand-in poster: the title set in the display face on coloured stock.
class TitleCard extends StatelessWidget {
  const TitleCard(this.film, {super.key, required this.width});
  final Film film;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bg = _posterInks[film.title.hashCode.abs() % _posterInks.length];
    final fg = paperColors.values.elementAt(film.id.hashCode.abs() % 4);
    final small = width < 50;
    return Container(
      width: width,
      height: width * 1.5,
      color: bg,
      padding: EdgeInsets.all(small ? 2 : width * 0.08),
      alignment: small ? Alignment.center : Alignment.bottomLeft,
      child: small
          ? Center(
              child: Text(
                film.title.isEmpty ? '?' : film.title.characters.first.toUpperCase(),
                style: disp(width * 0.5, fg),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  film.title.toUpperCase(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: disp(width * 0.16, fg, spacing: 0.2, height: 1.02),
                ),
                if (film.year != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('${film.year}', style: disp(width * 0.11, fg.withValues(alpha: 0.7))),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ticket paper

/// Rounded ticket with semicircle bites where the perforation meets the edge.
/// [notchY] puts bites on the left and right edges; [notchFromRight] puts them
/// on the top and bottom edges, that far from the right edge.
class TicketBorder extends ShapeBorder {
  const TicketBorder({this.radius = 8, this.notch = 8, this.notchY, this.notchFromRight});
  final double radius, notch;
  final double? notchY, notchFromRight;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    var p = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final bites = Path();
    if (notchY != null) {
      bites.addOval(Rect.fromCircle(center: Offset(rect.left, rect.top + notchY!), radius: notch));
      bites.addOval(Rect.fromCircle(center: Offset(rect.right, rect.top + notchY!), radius: notch));
    }
    if (notchFromRight != null) {
      bites.addOval(Rect.fromCircle(center: Offset(rect.right - notchFromRight!, rect.top), radius: notch));
      bites.addOval(Rect.fromCircle(center: Offset(rect.right - notchFromRight!, rect.bottom), radius: notch));
    }
    if (notchY != null || notchFromRight != null) p = Path.combine(PathOperation.difference, p, bites);
    return p;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

/// Coloured paper in a ticket shape, with grain under the content and a tight
/// shadow cast from above. The perforation is drawn along the notches.
class TicketPaper extends StatelessWidget {
  const TicketPaper({
    super.key,
    required this.color,
    required this.shape,
    required this.child,
    this.lift = true,
    this.perforate = true,
  });
  final Color color;
  final TicketBorder shape;
  final Widget child;
  final bool lift, perforate;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PaperPainter(shape, color, lift),
      foregroundPainter: perforate ? _PerforationPainter(shape, paperInk.withValues(alpha: 0.32)) : null,
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/paper/grain.png'),
              repeat: ImageRepeat.repeat,
              opacity: 0.55,
              scale: 2,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  _PaperPainter(this.shape, this.color, this.lift);
  final TicketBorder shape;
  final Color color;
  final bool lift;

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape.getOuterPath(Offset.zero & size);
    if (lift) {
      canvas.drawPath(
        path.shift(const Offset(0, 1.5)),
        Paint()
          ..color = const Color(0x402A1316)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
      );
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.color != color || old.lift != lift;
}

class _PerforationPainter extends CustomPainter {
  _PerforationPainter(this.shape, this.color);
  final TicketBorder shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final n = shape.notch;
    if (shape.notchY != null) {
      final y = shape.notchY!;
      for (var x = n + 6; x < size.width - n - 4; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 2.5, size.width - n - 4), y), p);
      }
    }
    if (shape.notchFromRight != null) {
      final x = size.width - shape.notchFromRight!;
      for (var y = n + 5; y < size.height - n - 3; y += 7) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 2.5, size.height - n - 3)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Rubber stamp

/// Round rubber stamp: double ring, a word and a date, pressed at an angle.
/// Worn specks come from a seeded pattern, so each stub wears differently.
class Stamp extends StatelessWidget {
  const Stamp({super.key, required this.word, this.line, required this.color, this.size = 84, this.seed = 1});
  final String word;
  final String? line;
  final Color color;
  final double size;
  final int seed;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.2,
    child: CustomPaint(size: Size.square(size), painter: _StampPainter(word, line, color, seed)),
  );
}

class _StampPainter extends CustomPainter {
  _StampPainter(this.word, this.line, this.color, this.seed);
  final String word;
  final String? line;
  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.saveLayer(Offset.zero & size, Paint());
    final ink = Paint()
      ..color = color.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, r - 1.5, ink..strokeWidth = 2.6);
    canvas.drawCircle(c, r - 6, ink..strokeWidth = 1.1);
    void text(String s, double fs, double dy) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: disp(fs, color.withValues(alpha: 0.88), spacing: 1)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width * 0.8);
      tp.paint(canvas, c + Offset(-tp.width / 2, dy - tp.height / 2));
    }

    if (line == null) {
      text(word, r * 0.36, 0);
    } else {
      text(word, r * 0.34, -r * 0.2);
      text(line!, r * 0.3, r * 0.26);
    }
    final rnd = math.Random(seed);
    final wear = Paint()..blendMode = BlendMode.clear;
    for (var i = 0; i < 46; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = math.sqrt(rnd.nextDouble()) * r;
      canvas.drawCircle(c + Offset.fromDirection(a, d), 0.4 + rnd.nextDouble() * 1.1, wear);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StampPainter old) => old.word != word || old.line != line || old.color != color;
}

/// Lands a stamp: it drops from above and settles. Always visible.
class StampPress extends StatelessWidget {
  const StampPress({super.key, required this.child, this.play = true});
  final Widget child;
  final bool play;

  @override
  Widget build(BuildContext context) {
    if (!play || MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.7, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      onEnd: HapticFeedback.mediumImpact,
      builder: (_, s, c) => Transform.scale(scale: s, child: c),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Stars

Path _starPath(Offset c, double r) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final rad = i.isEven ? r : r * 0.46;
    final a = -math.pi / 2 + i * math.pi / 5;
    final pt = c + Offset.fromDirection(a, rad);
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
}

/// Five stars filled to [value] (0 to 5, fractional).
class Stars extends StatelessWidget {
  const Stars(this.value, {super.key, this.size = 14, required this.color, required this.empty});
  final double value;
  final double size;
  final Color color, empty;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * 5 + 4 * size * 0.18, size), painter: _StarsPainter(value, color, empty, size));
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.value, this.color, this.empty, this.star);
  final double value, star;
  final Color color, empty;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = star * 0.18;
    final line = Paint()
      ..color = empty
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, star / 12)
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < 5; i++) {
      final x = i * (star + gap);
      final path = _starPath(Offset(x + star / 2, star * 0.54), star / 2);
      final fillPart = (value - i).clamp(0.0, 1.0);
      if (fillPart > 0) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(x, 0, star * fillPart, star));
        canvas.drawPath(path, Paint()..color = color);
        canvas.restore();
      }
      if (fillPart < 1) canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.value != value || old.color != color || old.empty != empty;
}

/// Drag or tap across the stars. Steps of 0.1.
class StarInput extends StatelessWidget {
  const StarInput({super.key, required this.value, required this.onChanged, this.size = 36});
  final double? value;
  final ValueChanged<double> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final width = size * 5 + 4 * size * 0.18;
    void set(double dx) => onChanged(((dx / width * 5).clamp(0.1, 5.0) * 10).ceil() / 10);
    final v = value ?? 0;
    final up = math.min(5.0, ((v + 0.5) * 10).round() / 10);
    final down = math.max(0.1, ((v - 0.5) * 10).round() / 10);
    return Semantics(
      slider: true,
      value: v.toStringAsFixed(1),
      increasedValue: up.toStringAsFixed(1),
      decreasedValue: down.toStringAsFixed(1),
      onIncrease: () => onChanged(up),
      onDecrease: () => onChanged(down),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => set(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => set(d.localPosition.dx),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Stars(value ?? 0, size: size, color: p.accent, empty: p.inkSoft),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces

/// Section title inside a screen: display face, ink, with an optional action.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(text, style: disp(20, p.ink))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: p.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

/// Selectable option, printed like a ticket class box: square corners, ink rule.
class OptionBox extends StatelessWidget {
  const OptionBox({super.key, required this.label, required this.selected, required this.onTap, this.dense = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 6 : 8),
          decoration: BoxDecoration(
            color: selected ? p.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: selected ? p.ink : p.line, width: 1.2),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: dense ? 12.5 : 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? p.wall : p.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary action: flat accent slab with square-ish corners, no glow.
class InkButton extends StatelessWidget {
  const InkButton({super.key, required this.label, required this.onPressed, this.icon, this.outlined = false});
  final String label;
  final VoidCallback? onPressed;
  final Tk? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = outlined ? p.ink : p.onAccent;
    return SizedBox(
      height: 50,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: outlined ? Colors.transparent : p.accent,
          foregroundColor: fg,
          disabledForegroundColor: fg.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: outlined ? BorderSide(color: p.ink, width: 1.4) : BorderSide.none,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[TkIcon(icon!, size: 20, color: fg), const SizedBox(width: 8)],
            Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, style: disp(17, fg, spacing: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round record button.
class RecordFab extends StatelessWidget {
  const RecordFab({super.key, required this.onPressed, required this.tooltip, this.icon = Tk.plus});
  final VoidCallback onPressed;
  final String tooltip;
  final Tk icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: p.accent,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: p.accent.withValues(alpha: 0.35), offset: const Offset(0, 2), blurRadius: 3),
              ],
            ),
            child: TkIcon(icon, size: 26, color: p.onAccent),
          ),
        ),
      ),
    );
  }
}

/// Placeholder text for empty lists.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.inkSoft, fontSize: 15, height: 1.4),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            InkButton(label: action!, onPressed: onAction, outlined: true),
          ],
        ],
      ),
    );
  }
}

/// Fades the right edge of a horizontal scroller so a clipped item reads as
/// "more this way", not as a cut.
class EdgeFade extends StatelessWidget {
  const EdgeFade({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (r) => const LinearGradient(
      colors: [Colors.black, Colors.black, Colors.transparent],
      stops: [0, 0.88, 1],
    ).createShader(r),
    child: child,
  );
}
