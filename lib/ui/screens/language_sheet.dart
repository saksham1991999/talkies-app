import 'package:flutter/material.dart';

import '../../l10n/locale_meta.dart';
import '../format.dart';
import '../icons.dart';
import '../theme.dart';

/// Bottom sheet that picks one of the translated UI languages.
///
/// Only languages whose ARB text is really translated are offered: a seeded
/// file that still holds English would otherwise read as a broken translation.
Future<void> pickLanguage(BuildContext context, String? current, ValueChanged<String?> onPick) async {
  final picked = await showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LanguageSheet(current: current),
  );
  if (picked == _LanguageSheet.system) {
    onPick(null);
  } else if (picked != null) {
    onPick(picked);
  }
}

/// Language name for the current setting, in its own script.
String languageName(BuildContext c, String? code) {
  if (code == null) return c.l.languageSystem;
  for (final lang in appLanguages) {
    if (lang.code == code) return lang.native;
  }
  return code;
}

class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.current});
  static const system = '\u0000system';
  final String? current;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final l = context.l;
    final languages = appLanguages.where((x) => x.ready || x.code == 'en').toList();
    final q = _query.trim().toLowerCase();
    bool match(AppLanguage x) =>
        q.isEmpty ||
        x.native.toLowerCase().contains(q) ||
        x.english.toLowerCase().contains(q) ||
        x.code.toLowerCase().contains(q);
    final indian = languages.where((x) => x.indian && match(x)).toList();
    final world = languages.where((x) => !x.indian && match(x)).toList();

    Widget row(String code, String title, String? sub, {bool system = false}) {
      final on = system ? widget.current == null : widget.current == code;
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(
          title,
          style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: p.ink),
        ),
        subtitle: sub == null ? null : Text(sub, style: TextStyle(color: p.inkSoft, fontSize: 12)),
        trailing: on ? TkIcon(Tk.check, size: 18, color: p.ink) : null,
        onTap: () => Navigator.pop(context, system ? _LanguageSheet.system : code),
      );
    }

    return Material(
      color: p.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 12, 8),
                child: Row(
                  children: [
                    Expanded(child: Text(l.appLanguage, style: disp(22, p.ink))),
                    TkButton(Tk.close, tooltip: l.cancel, onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: p.ink),
                  decoration: InputDecoration(
                    hintText: l.search,
                    hintStyle: TextStyle(color: p.inkSoft),
                    isDense: true,
                    prefixIcon: TkIcon(Tk.search, size: 18, color: p.inkSoft),
                    filled: true,
                    fillColor: p.wall,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (q.isEmpty) row(_LanguageSheet.system, l.languageSystem, null, system: true),
                    if (indian.isNotEmpty) _head(context, l.languagesIndian),
                    for (final x in indian) row(x.code, x.native, x.english == x.native ? null : x.english),
                    if (world.isNotEmpty) _head(context, l.languagesWorld),
                    for (final x in world) row(x.code, x.native, x.english == x.native ? null : x.english),
                    if (indian.isEmpty && world.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(l.noResults(_query), style: TextStyle(color: p.inkSoft)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _head(BuildContext c, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(text.toUpperCase(), style: TextStyle(color: Palette.of(c).inkSoft, fontSize: 10, letterSpacing: 1.4)),
  );
}
