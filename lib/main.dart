import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'di.dart';
import 'l10n/app_strings.dart';
import 'services/settings_repository.dart';
import 'ui/screens/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final PrefsSettingsRepository settingsRepo =
      await PrefsSettingsRepository.create();
  runApp(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
      ],
      child: const ZAgentsApp(),
    ),
  );
}

class ZAgentsApp extends ConsumerWidget {
  const ZAgentsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild the tree only when the language preference changes; other
    // settings (API key, model, …) are read further down the tree.
    final String languageCode = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );
    return MaterialApp(
      title: 'ZAgents',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      // Explicit locale (never the device locale): English is the default
      // until the user picks Bahasa Indonesia in Settings.
      locale: Locale(languageCode),
      supportedLocales: const <Locale>[Locale('en'), Locale('id')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        zLocalizationsDelegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
    );
  }
}
