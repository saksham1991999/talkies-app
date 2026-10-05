import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/crews.dart';
import '../state/crews_remote.dart' show pendingJoinProvider;
import '../state/links.dart';
import '../state/online.dart';
import '../state/providers.dart';
import '../state/together.dart';
import 'common.dart';
import 'format.dart';
import 'icons.dart';
import 'screens/calendar_screen.dart';
import 'screens/films_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/stubs_screen.dart';
import 'screens/together_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  late final AppLifecycleListener _life;

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The app can sit in the background past midnight: re-read "today" on resume.
    _life = AppLifecycleListener(onResume: () => ref.invalidate(todayProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(settingsProvider).seenVersion != appVersion) _whatsNew();
      ref.read(catalogRefreshProvider.notifier).runIfDue();
      // Nothing online runs before the first frame. Both calls do nothing without a server in the build
      // and in tests that turn background work off.
      startOnline(ref);
      startLinks(ref);
    });
  }

  Future<void> _whatsNew() async {
    await showWhatsNew(context);
    if (!mounted) return;
    ref.read(settingsProvider.notifier).set((s) => s.copyWith(seenVersion: appVersion));
  }

  /// An invite code arrived (link or typing). Online: the Together tab opens its join sheet. Signed out
  /// with a server in the build: Settings opens, the one place that may ask the server and offer sign-in;
  /// the code waits. Without a server the link does nothing.
  void _routeJoin(String? code) {
    if (code == null || !mounted) return;
    if (ref.read(onlineProvider)) {
      ref.read(togetherSegmentProvider.notifier).go(TogetherSegment.groups);
      ref.read(tabProvider.notifier).go(togetherTab);
    } else if (!ref.read(signedInProvider) &&
        ref.read(backendProvider) != Backend.none &&
        ref.read(settingsOpenProvider) == 0) {
      push(context, const SettingsScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Newer catalog data (posters, exact dates) flows into the user's snapshots.
    ref.listen(catalogProvider, (_, next) {
      if (next.value case final cat?) {
        ref.read(diaryProvider.notifier).syncFilms(cat);
        // Posters for the release lists, then the user's stubs and watchlist.
        final today = ref.read(todayProvider);
        final ww = ref.read(settingsProvider).worldwide;
        prefetchPosters([
          ...cat.newReleases(today, worldwide: ww).take(30),
          ...cat.upcoming(today, worldwide: ww).take(30),
          ...ref.read(diaryProvider).films.values,
        ]);
      }
    });
    // Signing out or deleting the account drops the shared groups, and their reminders with them.
    ref.listen(signedInProvider, (was, now) {
      if (was == true && !now) unawaited(ref.read(crewsProvider.notifier).dropShared());
    });
    ref.listen(pendingJoinProvider, (_, code) => _routeJoin(code));
    ref.listen(onlineProvider, (_, on) {
      if (on) _routeJoin(ref.read(pendingJoinProvider));
    });
    final tab = ref.watch(tabProvider);
    final l = context.l;
    return Scaffold(
      body: IndexedStack(
        index: tab,
        // Together is appended: the tab numbers go(1) and go(3) stay valid.
        children: const [HomeScreen(), StubsScreen(), CalendarScreen(), FilmsScreen(), StatsScreen(), TogetherScreen()],
      ),
      bottomNavigationBar: TicketNav(
        index: tab,
        onTap: ref.read(tabProvider.notifier).go,
        items: [
          (Tk.home, l.tabHome),
          (Tk.stubs, l.tabStubs),
          (Tk.calendar, l.tabCalendar),
          (Tk.films, l.tabFilms),
          (Tk.stats, l.tabStats),
          (Tk.people, l.tabTogether),
        ],
      ),
    );
  }
}

/// Bottom navigation drawn as a roll of tickets. The current tab is the
/// ticket torn from the roll: paper-coloured, notched, sliding into place.
class TicketNav extends StatelessWidget {
  const TicketNav({super.key, required this.index, required this.onTap, required this.items});
  final int index;
  final ValueChanged<int> onTap;
  final List<(Tk, String)> items;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final paper = p.paper(VenueType.cinema);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: p.velvet,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth / items.length;
              return Stack(
                children: [
                  for (var i = 1; i < items.length; i++)
                    Positioned(
                      left: i * w - 1,
                      top: 16,
                      bottom: 16,
                      child: CustomPaint(size: const Size(2, 32), painter: _Dots(p.onVelvet.withValues(alpha: 0.3))),
                    ),
                  AnimatedPositioned(
                    duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    left: index * w + 5,
                    top: 7,
                    width: w - 10,
                    height: 50,
                    child: TicketPaper(
                      color: paper,
                      lift: false,
                      perforate: false,
                      shape: const TicketBorder(radius: 5, notch: 5, notchY: 25),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: i == index,
                            label: items[i].$2,
                            excludeSemantics: true,
                            child: InkResponse(
                              onTap: () => onTap(i),
                              radius: 40,
                              child: _NavItem(
                                icon: items[i].$1,
                                label: items[i].$2,
                                active: i == index,
                                p: p,
                                // Six tabs on a 320 dp phone leave 53 dp each: a little less side padding keeps
                                // the label near full size instead of shrinking it to fit.
                                dense: items.length > 5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.active, required this.p, this.dense = false});
  final Tk icon;
  final String label;
  final bool active;
  final Palette p;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = active ? paperInk : p.onVelvet.withValues(alpha: 0.78);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TkIcon(icon, size: 22, color: color),
        const SizedBox(height: 3),
        // Long labels (Tamil, Malayalam) shrink to fit instead of being cut.
        Padding(
          // The active label is dark ink: it must stay on the paper, which is 5 dp in from each cell edge.
          padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label.toUpperCase(), maxLines: 1, style: disp(11.5, color, spacing: dense ? 0.5 : 0.9)),
          ),
        ),
      ],
    );
  }
}

class _Dots extends CustomPainter {
  _Dots(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var y = 1.0; y < size.height; y += 5) {
      canvas.drawLine(Offset(1, y), Offset(1, y + 0.1), p);
    }
  }

  @override
  bool shouldRepaint(_Dots old) => old.color != color;
}

/// Release notes. Shown once per version and from Settings.
Future<void> showWhatsNew(BuildContext context) {
  final l = context.l;
  return showDialog<void>(
    context: context,
    builder: (c) {
      final p = Palette.of(c);
      return AlertDialog(
        title: Text(l.whatsNewTitle(appVersion), style: disp(26, p.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in [l.whatsNew1, l.whatsNew2, l.whatsNew3])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: TkIcon(Tk.stubs, size: 18, color: p.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t, style: const TextStyle(height: 1.4))),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(
              l.gotIt,
              style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
    },
  );
}
