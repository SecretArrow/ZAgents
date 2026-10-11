import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'di.dart';
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
    return MaterialApp(
      title: 'ZAgents',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      home: const HomeShell(),
    );
  }
}
