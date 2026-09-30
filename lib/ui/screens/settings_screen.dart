import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/csv_io.dart';
import '../../data/models.dart';
import '../../l10n/labels.dart';
import '../../state/providers.dart';
import '../common.dart';
import '../format.dart';
import '../icons.dart';
import '../share.dart';
import '../theme.dart';
import '../widgets.dart';
import '../shell.dart' show showWhatsNew;
import 'manage_screens.dart';

/// Launcher icon variants. Native side: activity-alias (Android), alternate icons (iOS).
const appIcons = ['default', 'yellow', 'green', 'blue', 'night'];
const _iconChannel = MethodChannel('talkies/app_icon');

Future<bool> setAppIcon(String name) async {
  try {
    return await _iconChannel.invokeMethod<bool>('set', {'name': name}) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).set;
    final diary = ref.watch(diaryProvider);
    final catalog = ref.watch(catalogProvider).value;
    final busy = ref.watch(catalogRefreshProvider);
    final p = Palette.of(context);
    final l = context.l;

    String iconName(String k) => switch (k) {
      'yellow' => l.icon_yellow,
      'green' => l.icon_green,
      'blue' => l.icon_blue,
      'night' => l.icon_night,
      _ => l.icon_default,
    };
    String accentName(int i) => switch (accents[i].key) {
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

    Widget options<T>(List<(T, String)> items, T value, void Function(T) onTap) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (v, t) in items) OptionBox(label: t, dense: true, selected: v == value, onTap: () => onTap(v)),
      ],
    );

    final updated = s.catalogRefreshed;
    return Scaffold(
      appBar: AppBar(
        leading: TkButton(Tk.back, tooltip: l.back, onPressed: () => Navigator.pop(context)),
        title: Text(l.settingsTitle.toUpperCase(), style: disp(26, p.ink)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          _Group(l.appearance, [
            _Item(
              l.theme,
              child: options(
                [(ThemeMode.system, l.themeSystem), (ThemeMode.light, l.themeLight), (ThemeMode.dark, l.themeDark)],
                s.themeMode,
                (v) => set((x) => x.copyWith(themeMode: v)),
              ),
            ),
            _Item(
              '${l.accentColor} · ${accentName(s.accent)}',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < accents.length; i++)
                    Semantics(
                      button: true,
                      selected: s.accent == i,
                      label: accentName(i),
                      child: GestureDetector(
                        key: Key('accent-$i'),
                        onTap: () => set((x) => x.copyWith(accent: i)),
                        child: _InkDrop(color: accents[i].color, selected: s.accent == i, ring: p.ink),
                      ),
                    ),
                ],
              ),
            ),
            _Item(
              l.appIcon,
              child: Wrap(
                spacing: 14,
                runSpacing: 12,
                children: [
                  for (final k in appIcons)
                    Semantics(
                      button: true,
                      selected: s.icon == k,
                      label: iconName(k),
                      child: GestureDetector(
                        onTap: () async {
                          final m = ScaffoldMessenger.of(context);
                          final ok = await setAppIcon(k);
                          if (ok) set((x) => x.copyWith(icon: k));
                          m.showSnackBar(SnackBar(content: Text(ok ? l.iconChanged : l.iconFailed)));
                        },
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: s.icon == k ? p.ink : Colors.transparent, width: 2),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset('assets/icons/$k.png', width: 56, height: 56),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              iconName(k),
                              style: TextStyle(fontSize: 11, color: p.inkSoft, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]),
          _Group(l.appLanguage, [
            _Item(
              null,
              child: options<String?>(
                [(null, l.languageSystem), for (final (code, name) in uiLanguages) (code, name)],
                s.locale,
                (v) => set((x) => x.copyWith(locale: () => v)),
              ),
            ),
          ]),
          _Group(l.calendarSection, [
            _Item(
              l.weekStart,
              child: options(
                [(DateTime.sunday, l.sunday), (DateTime.monday, l.monday)],
                s.weekStart,
                (v) => set((x) => x.copyWith(weekStart: v)),
              ),
            ),
          ]),
          _Group(l.ratingsSection, [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(l.showRatingsToggle),
              value: s.showRatings,
              onChanged: (v) => set((x) => x.copyWith(showRatings: v)),
            ),
          ]),
          _Group(l.releaseLists, [
            _Item(
              null,
              child: options(
                [(false, l.releasesIndia), (true, l.releasesWorld)],
                s.worldwide,
                (v) => set((x) => x.copyWith(worldwide: v)),
              ),
            ),
          ]),
          _Group(l.manageTags, [
            _Nav(l.manageTags, sub: '${diary.tags.length}', onTap: () => push(context, const TagsScreen())),
            _Nav(l.manageVenues, sub: '${diary.venues.length}', onTap: () => push(context, const VenuesScreen())),
          ]),
          _Group(l.dataSection, [
            _Nav(l.batchAdd, sub: l.batchAddHint, onTap: () => push(context, const BatchScreen())),
            _Nav(l.importCsv, sub: l.importHint, onTap: () => _import(context, ref)),
            Builder(builder: (c) => _Nav(l.exportCsv, onTap: () => _export(c, ref))),
            Builder(
              builder: (c) => _Nav(l.backup, sub: l.backupHint, onTap: () => _backup(c, ref)),
            ),
            _Nav(l.restore, onTap: () => _restore(context, ref)),
          ]),
          _Group(l.refreshCatalog, [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(l.refreshCatalog, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                catalog == null
                    ? l.loadingCatalog
                    : updated == null
                    ? l.builtOn(catalog.built)
                    : l.refreshedOn(catalog.built, fmtDay(context, updated)),
              ),
              trailing: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : TkIcon(Tk.refresh, color: p.ink),
              onTap: busy
                  ? null
                  : () async {
                      final m = ScaffoldMessenger.of(context);
                      try {
                        final n = await ref.read(catalogRefreshProvider.notifier).run();
                        m.showSnackBar(SnackBar(content: Text(l.refreshDone(n))));
                      } catch (_) {
                        m.showSnackBar(SnackBar(content: Text(l.refreshFailed)));
                      }
                    },
            ),
          ]),
          _Group(l.about, [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(l.aboutBody, style: TextStyle(color: p.inkSoft, height: 1.45)),
            ),
            _Nav(l.whatsNew, onTap: () => showWhatsNew(context)),
            _Nav(
              l.privacyPolicy,
              onTap: () => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication),
            ),
            _Nav(
              l.version(appVersion),
              sub: catalog == null ? null : l.searchPrompt(fmtCount(catalog.items.length)),
              onTap: null,
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final d = ref.read(diaryProvider);
    if (d.stubs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.nothingToExport)));
      return;
    }
    final stamp = ymd(DateTime.now());
    await shareBytes(context, utf8.encode(exportCsv(d)), 'talkies-$stamp.csv', 'text/csv');
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final stamp = ymd(DateTime.now());
    final text = const JsonEncoder.withIndent(' ').convert(ref.read(diaryProvider).toJson());
    await shareBytes(context, utf8.encode(text), 'talkies-backup-$stamp.json', 'application/json');
  }

  Future<String?> _pickText(List<String> ext) async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ext);
    if (f == null) return null;
    return utf8.decode(await f.xFile.readAsBytes(), allowMalformed: true);
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final m = ScaffoldMessenger.of(context);
    final l = context.l;
    final text = await _pickText(['csv', 'txt']);
    if (text == null || !context.mounted) return;
    final catalog = await ref.read(catalogProvider.future);
    if (!context.mounted) return;
    final r = parseCsv(text, catalog, ref.read(diaryProvider));
    if (r.rows.isEmpty) {
      m.showSnackBar(SnackBar(content: Text(l.importNothing)));
      return;
    }
    final n = ref.read(diaryProvider.notifier);
    for (final place in r.places) {
      n.addVenue(Venue(place, guessVenueType(place)));
    }
    n.addStubs(r.rows);
    m.showSnackBar(SnackBar(content: Text(l.imported(r.rows.length, r.matched, r.custom))));
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final m = ScaffoldMessenger.of(context);
    final l = context.l;
    final text = await _pickText(['json']);
    if (text == null || !context.mounted) return;
    Diary d;
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['stubs'] is! List) throw const FormatException();
      d = Diary.fromJson(j);
    } catch (_) {
      m.showSnackBar(SnackBar(content: Text(l.restoreFailed)));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.replaceQ),
        content: Text(l.replaceBody(ref.read(diaryProvider).stubs.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(l.replace)),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(diaryProvider.notifier).replaceAll(d);
    m.showSnackBar(SnackBar(content: Text(l.restoreDone)));
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(title, style: disp(21, p.ink)),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.label, {required this.child});
  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        child,
      ],
    ),
  );
}

class _Nav extends StatelessWidget {
  const _Nav(this.title, {this.sub, required this.onTap});
  final String title;
  final String? sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: sub == null ? null : Text(sub!, style: TextStyle(color: p.inkSoft)),
      trailing: onTap == null ? null : TkIcon(Tk.right, size: 18, color: p.inkSoft),
      onTap: onTap,
    );
  }
}

/// Accent swatch: an ink drop, ringed when chosen.
class _InkDrop extends StatelessWidget {
  const _InkDrop({required this.color, required this.selected, required this.ring});
  final Color color, ring;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: selected ? ring : Colors.transparent, width: 2),
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: ring.withValues(alpha: 0.25)),
      ),
      child: selected ? const Center(child: TkIcon(Tk.check, size: 16, color: Colors.white)) : null,
    ),
  );
}
