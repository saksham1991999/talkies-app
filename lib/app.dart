import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/gen/app_localizations.dart';
import 'state/providers.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

class TalkiesApp extends ConsumerWidget {
  const TalkiesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Talkies',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(dark: false, accentIndex: s.accent),
      darkTheme: buildTheme(dark: true, accentIndex: s.accent),
      themeMode: s.themeMode,
      locale: s.locale == null ? null : Locale(s.locale!),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Shell(),
    );
  }
}
