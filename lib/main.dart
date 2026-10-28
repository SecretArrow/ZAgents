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
  // explicitly, then [insetGuardBuilder] (below, wired as MaterialApp
  // builder) keeps all content strictly between the system bars.
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
  // Per-chat "last seen public IP" memo storage of the chat-switch guard
  // (v1.48.0) — same async-at-boot pattern as the app-lock prefs.
  final SharedPreferences ipMemoPrefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        contextRepositoryProvider.overrideWithValue(contextRepo),
        promptRepositoryProvider.overrideWithValue(promptRepo),
        appLockPrefsProvider.overrideWithValue(appLockPrefs),
        ipMemoPrefsProvider.overrideWithValue(ipMemoPrefs),
      ],
      child: const ZAgentsApp(),
    ),
  );
}

/// v1.49.0 — keeps EVERY screen, dialog, bottom sheet, drawer and
/// snackbar strictly between the Android status bar (notification bar,
/// top) and the navigation bar (system back-home area, bottom).
///
/// Android 15+ (targetSdk 35/36) enforces edge-to-edge: the window always
/// extends under both system bars and there is no manifest opt-out.
/// Padding each screen by hand is fragile — any new route without
/// SafeArea regresses (list bottoms and dialog buttons slid under the
/// bars exactly this way). Instead the WHOLE Navigator is padded once
/// here and the consumed insets are reported as zero to the tree below:
///   * app content can never reach the notification bar or the system
///     navigation area, on any route, including dialogs/sheets/drawers
///     and snackbars;
///   * existing SafeArea widgets see zero extra padding (no double
///     spacing) — they keep working unchanged;
///   * the keyboard stays untouched: MediaQuery.padding collapses when
///     the keyboard overlaps the nav bar (padding = viewPadding −
///     viewInsets), so no phantom gap appears while typing;
///   * the strip behind the transparent system bars is painted with the
///     scaffold background color, so the bars blend with the app in both
///     themes.
Widget insetGuardBuilder(BuildContext context, Widget? child) {
  final MediaQueryData mq = MediaQuery.of(context);
  final double top = mq.padding.top;
  final double bottom = mq.padding.bottom;
  if (top <= 0 && bottom <= 0) {
    return child ?? const SizedBox.shrink();
  }
  return ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: MediaQuery(
        data: mq
            .removePadding(removeTop: true, removeBottom: true)
            .removeViewPadding(removeTop: true, removeBottom: true),
        child: child ?? const SizedBox.shrink(),
      ),
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
      builder: insetGuardBuilder,
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
