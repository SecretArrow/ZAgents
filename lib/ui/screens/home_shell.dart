import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../../services/agent_controller.dart'
    show ChatState, ModuleSetupRequest;
import '../theme.dart';
import '../widgets/agent_toggle.dart';
import '../widgets/chat_body.dart';
import '../widgets/chat_drawer.dart';
import '../widgets/composer.dart';
import '../widgets/model_picker.dart';
import '../widgets/module_repair_card.dart';
import '../widgets/module_setup_sheet.dart';
import 'settings_screen.dart';

/// Main screen: app bar (brand, model chip, agent toggle, language menu),
/// chat body, composer.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// The setup request whose sheet was already auto-opened — a request
  /// stays pending (banner) until submitted, so the sheet must pop up
  /// exactly ONCE per request, not on every rebuild after a dismissal.
  ModuleSetupRequest? _autoOpenedSetup;

  @override
  void initState() {
    super.initState();
    // Continue-where-you-left-off: reopen the most recent conversation (if
    // any) so the first message continues it. Starting a NEW chat stays an
    // explicit drawer action ("New chat").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(chatControllerProvider.notifier).restoreLastChat();
      }
    });
  }

  Future<void> _openSetupSheet(ModuleSetupRequest request) async {
    _autoOpenedSetup = request;
    final Map<String, dynamic>? values = await showModuleSetupSheet(
      context,
      request,
    );
    // Dismissal keeps the banner; submission re-runs the module inside
    // submitModuleSetup — nothing left to do here.
    if (values == null) _autoOpenedSetup = null;
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    // Narrow screens: drop decorative elements (brand mark, quick language
    // menu — still available in Settings) so the app bar can never overflow
    // into the action icons or behind the status bar area.
    final double width = MediaQuery.sizeOf(context).width;
    final bool showBrand = width >= 340;
    final bool showLanguageMenu = width >= 360;
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
      // A module waiting for its per-chat setup form: open the sheet once
      // per request object (the gate fires mid-run, so the identity guard
      // alone decides); afterwards the persistent banner drives re-entry.
      final ModuleSetupRequest? setup = next.setupRequest;
      if (setup != null && !identical(setup, _autoOpenedSetup)) {
        _openSetupSheet(setup);
      }
    });

    return PopScope<bool>(
      // The shell is the root route: Android back must confirm before the
      // app leaves (v1.28.0) so a running agent task is never lost to a
      // stray back press. Open drawers and pushed screens pop normally —
      // they handle back BEFORE this scope is reached.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? result) async {
        if (didPop) return;
        final AppStrings strings = stringsOf(context);
        final bool? exit = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            key: const Key('exit-confirm-dialog'),
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text(strings.exitAppTitle),
            content: Text(strings.exitAppBody),
            actions: <Widget>[
              TextButton(
                key: const Key('exit-confirm-no'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                key: const Key('exit-confirm-yes'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(strings.exitAppConfirm),
              ),
            ],
          ),
        );
        if (exit == true) {
          // Best-effort: platform channels are unavailable in some test
          // environments; the intent (leave the app) is what matters.
          try {
            await SystemNavigator.pop();
          } catch (_) {}
        }
      },
      child: Scaffold(
        drawer: const ChatDrawer(),
        appBar: AppBar(
          leading: Builder(
            // A Builder context BELOW the Scaffold is required for
            // Scaffold.of(); the widget's own context would throw.
            builder: (BuildContext menuContext) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: strings.menu,
              onPressed: () => Scaffold.of(menuContext).openDrawer(),
            ),
          ),
          titleSpacing: 0,
          title: Row(
            children: <Widget>[
              if (showBrand) ...<Widget>[
                const BrandMark(size: 28),
                const SizedBox(width: 10),
              ],
              // Flexible so a long model name shrinks (ellipsis) instead of
              // overflowing the app bar into the action icons.
              const Flexible(child: ModelChip()),
            ],
          ),
          actions: <Widget>[
            const AgentModeToggle(),
            if (showLanguageMenu) const _LanguageMenu(),
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
        body: SafeArea(
          child: Column(
            children: <Widget>[
              const Expanded(child: ChatBody()),
              const ModuleRepairCard(),
              const _ModuleSetupBanner(),
              const Composer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent banner for a module waiting on its per-chat setup form.
/// Tapping "Set up" opens the form again; submitting hides the banner and
/// re-runs the module (controller handles both).
class _ModuleSetupBanner extends ConsumerWidget {
  const _ModuleSetupBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ModuleSetupRequest? request = ref.watch(
      chatControllerProvider.select((ChatState s) => s.setupRequest),
    );
    if (request == null) return const SizedBox.shrink();
    // v1.29.0: when a SENT message is queued behind this form, say so —
    // the agent deliberately does not work on it until the input lands.
    final bool waiting = ref.watch(
      chatControllerProvider.select((ChatState s) => s.waitingForSetup),
    );
    final AppStrings strings = stringsOf(context);
    return Material(
      key: const Key('module-setup-banner'),
      color: context.zSurfaceAlt,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: <Widget>[
            const Icon(Icons.extension_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    strings.moduleSetupNeededTitle(request.title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (waiting)
                    Text(
                      strings.moduleSetupWaitingHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              key: const Key('module-setup-banner-button'),
              onPressed: () {
                final _HomeShellState? host = context
                    .findAncestorStateOfType<_HomeShellState>();
                host?._openSetupSheet(request);
              },
              child: Text(strings.moduleSetupBannerCta),
            ),
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
