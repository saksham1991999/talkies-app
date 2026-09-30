import 'package:flutter/material.dart';

import '../data/models.dart';

/// The world: an Indian single-screen talkies. Distemper-green walls, velvet
/// maroon curtains, tickets printed on coloured paper by seat class, and a
/// rubber stamp in the accent ink.
class Accent {
  const Accent(this.key, this.color);
  final String key;
  final Color color;
}

const accents = [
  Accent('sindoor', Color(0xFFB0342B)),
  Accent('marigold', Color(0xFFC77F12)),
  Accent('peacock', Color(0xFF1C6566)),
  Accent('mehendi', Color(0xFF5C7429)),
  Accent('neel', Color(0xFF2F4A86)),
  Accent('jamun', Color(0xFF5E2D50)),
  Accent('gulabi', Color(0xFFBD3F68)),
  Accent('kesar', Color(0xFFD0662A)),
  Accent('paan', Color(0xFF3A7A4B)),
  Accent('chai', Color(0xFF7A4C2B)),
  Accent('kajal', Color(0xFF2B2424)),
];

/// Ticket paper, keyed by venue type, like class-coloured hall tickets.
const paperColors = {
  VenueType.cinema: Color(0xFFF2CBC1),
  VenueType.ott: Color(0xFFF0DC9C),
  VenueType.home: Color(0xFFCDE0C3),
  VenueType.tv: Color(0xFFC7D9E8),
  VenueType.other: Color(0xFFF0EBDD),
};

/// Ink printed on ticket paper. Same in light and dark mode: paper is paper.
const paperInk = Color(0xFF2A1316);
const paperInkSoft = Color(0xFF6B5450);

/// Background colours offered for share images.
const shareBackgrounds = [
  Color(0xFF3A1519), Color(0xFF1F3B36), Color(0xFF1E2B45), Color(0xFF2A2320), //
  Color(0xFFE3E6D8), Color(0xFFF2CBC1), Color(0xFFF0DC9C), Color(0xFFCDE0C3),
  Color(0xFFC7D9E8), Color(0xFFB0342B), Color(0xFFC77F12), Color(0xFF5E2D50),
];

class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.wall,
    required this.surface,
    required this.ink,
    required this.inkSoft,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.velvet,
    required this.onVelvet,
    required this.dark,
  });

  final Color wall, surface, ink, inkSoft, line, accent, onAccent, velvet, onVelvet;
  final bool dark;

  /// Ticket paper for a venue type; slightly dimmed in dark mode.
  Color paper(VenueType t) => dark ? Color.lerp(paperColors[t]!, wall, 0.12)! : paperColors[t]!;

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 || other == null ? this : other;
}

const display = 'Tanker';
const displayFallback = ['Teko'];

TextStyle disp(double size, Color color, {double spacing = 0.4, double height = 1.0}) => TextStyle(
  fontFamily: display,
  fontFamilyFallback: displayFallback,
  fontSize: size,
  color: color,
  letterSpacing: spacing,
  height: height,
);

ThemeData buildTheme({required bool dark, required int accentIndex}) {
  final accent = accents[accentIndex.clamp(0, accents.length - 1)].color;
  final p = dark
      ? Palette(
          wall: const Color(0xFF170D0E),
          surface: const Color(0xFF241416),
          ink: const Color(0xFFF1E5DD),
          inkSoft: const Color(0xFFB9A49B),
          line: const Color(0x33F1E5DD),
          accent: Color.lerp(accent, Colors.white, accentIndex == 10 ? 0.75 : 0.12)!,
          onAccent: accentIndex == 10 ? paperInk : Colors.white,
          velvet: const Color(0xFF2E1316),
          onVelvet: const Color(0xFFE9D8CF),
          dark: true,
        )
      : Palette(
          wall: const Color(0xFFE3E6D8),
          surface: const Color(0xFFEEF0E5),
          ink: const Color(0xFF2A1316),
          inkSoft: const Color(0xFF6B5A55),
          line: const Color(0x2B2A1316),
          accent: accent,
          onAccent: Colors.white,
          velvet: const Color(0xFF3A1519),
          onVelvet: const Color(0xFFEFDFD6),
          dark: false,
        );
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: dark ? Brightness.dark : Brightness.light)
      .copyWith(
        primary: p.accent,
        onPrimary: p.onAccent,
        surface: p.wall,
        onSurface: p.ink,
        surfaceContainerHighest: p.surface,
        outline: p.line,
      );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: scheme.brightness);
  return base.copyWith(
    scaffoldBackgroundColor: p.wall,
    extensions: [p],
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.wall,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.velvet,
      contentTextStyle: TextStyle(color: p.onVelvet),
      actionTextColor: paperColors[VenueType.ott],
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.ink, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(color: p.inkSoft),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : p.inkSoft),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.surface),
      trackOutlineColor: WidgetStateProperty.all(p.line),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: p.velvet,
      headerForegroundColor: p.onVelvet,
    ),
  );
}
