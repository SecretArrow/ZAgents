import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../../services/agent_controller.dart' show ChatState;
import '../theme.dart';
import '../widgets/agent_toggle.dart';
import '../widgets/chat_body.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/composer.dart';
import '../widgets/model_picker.dart';
import 'settings_screen.dart';

/// Main screen: app bar (brand, model chip, agent toggle, language menu),
/// chat body, composer.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    ref.listen<ChatState>(chatControllerProvider, (
      ChatState? prev,
      ChatState next,
    ) {
      final String? error = next.error;
      if (error != null && error != prev?.error) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
      }
    });

    return Scaffold(
      drawer: const ChatDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: strings.menu,
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            const BrandMark(size: 28),
            const SizedBox(width: 10),
            const ModelChip(),
          ],
        ),
        actions: <Widget>[
          const AgentModeToggle(),
          const _LanguageMenu(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: strings.settings,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: const SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(child: ChatBody()),
            Composer(),
          ],
        ),
      ),
    );
  }
}

/// Quick language switch in the app bar: English (default) / Bahasa Indonesia.
class _LanguageMenu extends ConsumerWidget {
  const _LanguageMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    final String current = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );
    return PopupMenuButton<String>(
      key: const Key('language-menu'),
      icon: const Icon(Icons.language_rounded),
      tooltip: strings.languageSection,
      initialValue: current,
      onSelected: (String code) {
        final AppSettings settings = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .update(settings.copyWith(languageCode: code));
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        for (final String code in supportedLanguageCodes)
          PopupMenuItem<String>(
            key: Key('language-menu-$code'),
            value: code,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    languageNames[code] ?? code,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                if (code == current)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: kAccentColor,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
