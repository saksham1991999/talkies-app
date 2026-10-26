import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/social.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/social.dart' show CallOutcome;
import 'avatar.dart';
import 'common.dart' show serialRed;
import 'format.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

// Small pieces the online screens share: people rows, the report and block
// flows, the reaction emoji. Nothing here talks to the server.

/// Name of stamp ink [i] (one of [accents]) in the UI language.
String accentName(BuildContext c, int i) {
  final l = c.l;
  return switch (accents[i.clamp(0, accents.length - 1)].key) {
    'marigold' => l.accent_marigold,
    'peacock' => l.accent_peacock,
    'mehendi' => l.accent_mehendi,
    'neel' => l.accent_neel,
    'jamun' => l.accent_jamun,
    'gulabi' => l.accent_gulabi,
    'kesar' => l.accent_kesar,
    'paan' => l.accent_paan,
    'chai' => l.accent_chai,
    'kajal' => l.accent_kajal,
    _ => l.accent_sindoor,
  };
}

/// Colour of a serial-number figure printed on the wall. The red of the tickets has no contrast on the dark
/// wall, so in dark mode the figure takes the ink.
Color figureColor(Palette p) => p.dark ? p.ink : serialRed;

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// Colour of a text button on the wall or on a sheet: the accent while it reads (4.5 to 1), else the ink. Some
/// accents are too light on the light wall (marigold, kesar), and in dark mode even the default is a little
/// dim (3.8 to 1), so a button that carries a word must not rely on the accent alone.
Color linkColor(Palette p) =>
    math.min(_contrast(p.accent, p.wall), _contrast(p.accent, p.surface)) >= 4.5 ? p.accent : p.ink;

/// Style of a text button that carries a word: [linkColor], bold. The whole text style is given: a button style
/// replaces the theme's label style, it does not merge with it.
ButtonStyle linkStyle(BuildContext context) => TextButton.styleFrom(
  foregroundColor: linkColor(Palette.of(context)),
  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
);

/// The name to show for a person: display name, else handle, else "Someone".
String nameOf(AppLocalizations l, UserCard c) => c.label.isEmpty ? l.friendsUnnamed : c.label;

/// A calm sentence for a failed call. Screens that word a case themselves check it first.
String problemText(AppLocalizations l, CallOutcome o) => switch (o) {
  CallOutcome.offline || CallOutcome.signedOut => l.gateCantReach,
  CallOutcome.rateLimited => l.acctRateLimited,
  _ => l.acctFailed,
};

/// The value of [read], or null when it throws. A film snapshot from the server is parsed on first use, and
/// one that does not parse must hide its row, not break the screen.
T? safe<T>(T Function() read) {
  try {
    return read();
  } catch (_) {
    return null;
  }
}

void say(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

/// Centered spinner for a list that has nothing to show yet.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(child: CircularProgressIndicator()),
  );
}

/// A row that opens something: bold title, quiet second line, an arrow, and optionally a bare icon in front.
class NavRow extends StatelessWidget {
  const NavRow(this.title, {super.key, this.sub, this.leading, required this.onTap});
  final String title;
  final String? sub;
  final Tk? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: leading == null ? null : TkIcon(leading!, color: p.ink),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: sub == null ? null : Text(sub!, style: TextStyle(color: p.inkSoft)),
      trailing: onTap == null ? null : TkIcon(Tk.right, size: 18, color: p.inkSoft),
      onTap: onTap,
    );
  }
}

/// A person: stamp, name, a quiet second line, and what goes at the end (a figure, a button). Tapping it is
/// optional. At least 56 high, so the whole row is a target.
class PersonRow extends StatelessWidget {
  const PersonRow({super.key, required this.card, this.subtitle, this.trailing, this.onTap, this.size = 40});
  final UserCard card;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final name = nameOf(context.l, card);
    final row = Row(
      children: [
        ExcludeSemantics(
          child: Avatar(name: name, ink: card.avatarColor, size: size),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.ink),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.inkSoft, height: 1.3),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: row),
    );
    return onTap == null
        ? MergeSemantics(child: body)
        : MergeSemantics(
            child: Semantics(
              button: true,
              child: InkWell(onTap: onTap, child: body),
            ),
          );
  }
}

/// A small ticket: a poster (or none), a title, a quiet second line, and a counterfoil with an arrow, or with
/// [end]. A film or a night in a chat is one. It opens what it names when [onTap] is set.
class TicketRow extends StatelessWidget {
  const TicketRow({super.key, this.film, required this.title, this.sub, this.onTap, this.end});
  final Film? film;
  final String title;
  final String? sub;
  final VoidCallback? onTap;
  final Widget? end;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ticket = TicketPaper(
      color: p.paper(VenueType.ott),
      shape: const TicketBorder(radius: 5, notch: 5, notchFromRight: 46),
      lift: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: film == null ? const SizedBox(width: 4) : Poster(film!, width: 32, radius: 2),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: paperInk, height: 1.2),
                    ),
                    if (sub != null)
                      Text(
                        sub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: paperInkSoft),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 46,
              child: Center(child: end ?? const TkIcon(Tk.right, size: 18, color: paperInkSoft)),
            ),
          ],
        ),
      ),
    );
    // No ripple: it would be painted under the paper. Tickets in this app (the stub rows) are tapped the same way.
    return onTap == null
        ? ticket
        : Semantics(
            button: true,
            label: title,
            excludeSemantics: true,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: ticket),
          );
  }
}

// ---------------------------------------------------------------------------
// Report and block

String reportReasonName(AppLocalizations l, ReportReason r) => switch (r) {
  ReportReason.spam => l.friendsReasonSpam,
  ReportReason.abuse => l.friendsReasonAbuse,
  ReportReason.harassment => l.friendsReasonHarassment,
  ReportReason.inappropriate => l.friendsReasonInappropriate,
  ReportReason.other => l.friendsReasonOther,
};

/// A sheet with the five reasons. Null when the user closes it.
Future<ReportReason?> pickReportReason(BuildContext context, {required String title}) =>
    showModalBottomSheet<ReportReason>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) {
        final p = Palette.of(c);
        final l = c.l;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title, style: disp(22, p.ink)),
              ),
              for (final r in ReportReason.values)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(reportReasonName(l, r), style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(c, r),
                ),
            ],
          ),
        );
      },
    );

/// "Block Asha?" True when the user agrees.
Future<bool> confirmBlock(BuildContext context, String name) async {
  final l = context.l;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(l.friendsBlockQ(name)),
      content: Text(l.friendsBlockBody),
      actions: [
        TextButton(style: linkStyle(context), onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
        TextButton(
          style: linkStyle(context),
          key: const Key('confirm-block'),
          onPressed: () => Navigator.pop(c, true),
          child: Text(l.friendsBlock),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// ---------------------------------------------------------------------------
// Reactions

/// Reaction 0 to 7 on the wire: fire, heart eyes, laugh, sad, clap, mind blown, popcorn, eyes.
const reactionEmoji = ['🔥', '😍', '😂', '😢', '👏', '🤯', '🍿', '👀'];

String reactionName(AppLocalizations l, int i) => switch (i) {
  0 => l.feedReactFire,
  1 => l.feedReactLove,
  2 => l.feedReactLaugh,
  3 => l.feedReactSad,
  4 => l.feedReactClap,
  5 => l.feedReactMind,
  6 => l.feedReactPopcorn,
  _ => l.feedReactEyes,
};
