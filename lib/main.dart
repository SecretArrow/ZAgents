import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'di.dart';
import 'l10n/app_strings.dart';
import 'models/models.dart';
import 'services/context_repository.dart';
import 'services/prompt_repository.dart';
import 'services/settings_repository.dart';
import 'ui/lock_gate.dart';
import 'ui/screens/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 15+ (targetSdk 35/36) enforces edge-to-edge: declare it
  // explicitly so system bars never overlap app content and the insets
  // (status bar top, navigation bar bottom) are always reported to
  // Scaffold/SafeArea.
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Per-theme icon brightness (dark/light) is declared in the AppBarTheme
    // of buildDarkTheme/buildLightTheme and applied by every Scaffold.
  } catch (_) {
    // System UI channels are unavailable in some test environments.
  }
  final PrefsSettingsRepository settingsRepo =
      await PrefsSettingsRepository.create();
  final PrefsContextRepository contextRepo =
      await PrefsContextRepository.create();
  final FilePromptRepository promptRepo = FilePromptRepository(
    resolveBaseDir: getApplicationDocumentsDirectory,
  );
  final SharedPreferences appLockPrefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        contextRepositoryProvider.overrideWithValue(contextRepo),
        promptRepositoryProvider.overrideWithValue(promptRepo),
        appLockPrefsProvider.overrideWithValue(appLockPrefs),
      ],
      child: const ZAgentsApp(),
    ),
  );
}

class ZAgentsApp extends ConsumerWidget {
  const ZAgentsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild the tree only when the language or theme preference changes;
    // other settings (API key, model, …) are read further down the tree.
    final String languageCode = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );
    final ThemeModeSetting themeSetting = ref.watch(
      settingsProvider.select((s) => s.themeMode),
    );
    final ThemeMode themeMode = switch (themeSetting) {
      ThemeModeSetting.light => ThemeMode.light,
      ThemeModeSetting.dark => ThemeMode.dark,
      ThemeModeSetting.system => ThemeMode.system,
    };
    return MaterialApp(
      title: 'ZAgents',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
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
      home: const LockGate(child: HomeShell()),
    );
  }
}
