import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/gen/app_localizations.dart';
import 'l10n/locale_meta.dart';
import 'l10n/resolution.dart';
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
      // `pt_BR` and `zh_Hans` cannot be read by `Locale(String)`, which would
      // leave the app in English.
      locale: s.locale == null ? null : localeFor(s.locale!),
      // A phone in a language the app does not ship falls back to English, not
      // to whichever locale sorts first in the generated list, which is Arabic.
      localeListResolutionCallback: (locales, _) => resolveAppLocale(locales),
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
