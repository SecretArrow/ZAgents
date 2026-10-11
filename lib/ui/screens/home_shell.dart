import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../services/agent_controller.dart' show ChatState;
import '../theme.dart';
import '../widgets/agent_toggle.dart';
import '../widgets/chat_body.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/composer.dart';
import '../widgets/model_picker.dart';
import 'settings_screen.dart';

/// Main screen: app bar (brand, model chip, agent toggle), chat body, composer.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  Widget build(BuildContext context) {
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
          tooltip: 'Menu',
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
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pengaturan',
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
