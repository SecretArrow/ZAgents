import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../di.dart';
import '../../services/module_registry.dart';
import '../../l10n/app_strings.dart';
import '../theme.dart';

/// Modules (plugins) manager: install from ZIP, list installed modules
/// with their permissions, remove, open the official SDK documentation,
/// and start a module in a new chat or the current one.
class ModulesScreen extends ConsumerStatefulWidget {
  const ModulesScreen({super.key});

  @override
  ConsumerState<ModulesScreen> createState() => _ModulesScreenState();

  /// Permission consent dialog — every activation funnels through this so
  /// the user always sees what the module may do before it runs.
  static Future<bool> confirmPermissions(
    BuildContext context,
    WidgetRef ref,
    ChatModule module,
  ) async {
    if (module.manifest.permissions.isEmpty) return true;
    final AppStrings strings = stringsOf(context);
    final bool? allowed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          strings.modulePermissionTitle(
            module.manifest.title.isEmpty ? module.name : module.manifest.title,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              strings.modulePermissionBody,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final ModulePermission p in module.manifest.permissions)
                  Chip(
                    label: Text(p.name, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('module-permission-allow'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.moduleAllow),
          ),
        ],
      ),
    );
    return allowed ?? false;
  }
}

class _ModulesScreenState extends ConsumerState<ModulesScreen> {
  bool _installing = false;

  Future<void> _install() async {
    if (_installing) return;
    setState(() => _installing = true);
    final AppStrings strings = stringsOf(context);
    try {
      const XTypeGroup zipGroup = XTypeGroup(
        label: 'ZIP module',
        extensions: <String>['zip'],
      );
      final XFile? picked = await openFile(
        acceptedTypeGroups: <XTypeGroup>[zipGroup],
      );
      if (picked == null) return;
      final ModuleInstallResult result = await ref
          .read(moduleRegistryProvider)
          .installFromZip(picked.path);
      ref.invalidate(moduleListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.ok
                  ? (result.message.startsWith('Updated')
                        // v1.44.0: version-aware reinstall — surface
                        // "Updated name vX → vY" verbatim.
                        ? result.message
                        : strings.moduleInstallSuccess(result.module!.name))
                  : strings.moduleInstallFailed(result.message),
            ),
          ),
        );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(strings.moduleInstallFailed('$e'))),
          );
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _remove(ChatModule module) async {
    final AppStrings strings = stringsOf(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(strings.moduleRemoveTitle),
        content: Text(strings.moduleRemoveBody(module.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(moduleRegistryProvider).remove(module.name);
    ref.invalidate(moduleListProvider);
  }

  Future<void> _startInNewChat(ChatModule module) async {
    if (!await ModulesScreen.confirmPermissions(context, ref, module)) return;
    if (!mounted) return;
    final NavigatorState navigator = Navigator.of(context);
    await ref.read(chatControllerProvider.notifier).newChat();
    await ref.read(chatControllerProvider.notifier).activateModule(module.name);
    if (navigator.canPop()) navigator.pop();
  }

  /// Exports the module as an installable ZIP (module root = zip root)
  /// into `<docs>/modules-export/` and opens the share sheet so the user
  /// can save or send it. The archive re-installs via the normal path.
  Future<void> _export(ChatModule module) async {
    final AppStrings strings = stringsOf(context);
    try {
      final Directory base = await ref.read(documentsDirProvider)();
      final String target =
          '${base.path}${Platform.pathSeparator}modules-export'
          '${Platform.pathSeparator}'
          '${module.name}-v${module.manifest.version}.zip';
      final ModuleExportResult result = await ref
          .read(moduleRegistryProvider)
          .exportToZip(module.name, target);
      if (!result.ok || result.zipPath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(strings.operationFailed)));
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(result.zipPath!)]),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.operationFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final AsyncValue<List<ChatModule>> modules = ref.watch(moduleListProvider);
    final String? activeModule = ref.watch(
      chatControllerProvider.select(
        (s) => s.activeModules.isNotEmpty ? s.activeModules.first : null,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.modulesTitle),
        actions: <Widget>[
          IconButton(
            key: const Key('modules-sdk-docs'),
            tooltip: strings.moduleSdkDocs,
            icon: const Icon(Icons.menu_book_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SdkDocsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('modules-install'),
        onPressed: _installing ? null : _install,
        icon: _installing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.upload_file_rounded),
        label: Text(strings.modulesInstall),
      ),
      body: modules.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (Object e, StackTrace s) => Center(
          child: Text(
            strings.operationFailed,
            style: TextStyle(color: context.zMuted),
          ),
        ),
        data: (List<ChatModule> items) => items.isEmpty
            ? _EmptyModules(onInstall: _install)
            : ListView.builder(
                key: const Key('modules-list'),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                // +1: the official sample-module catalog footer (v1.44.0).
                itemCount: items.length + 1,
                itemBuilder: (BuildContext context, int index) {
                  if (index == items.length) return const _OfficialCatalog();
                  final ChatModule module = items[index];
                  final bool isActive = activeModule == module.name;
                  return Card(
                    key: Key('module-tile-${module.name}'),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Icon(Icons.extension_rounded, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  module.manifest.title.isEmpty
                                      ? module.name
                                      : module.manifest.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isActive)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Chip(
                                    key: Key('module-active-${module.name}'),
                                    label: Text(
                                      strings.moduleActiveBadge,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              Text(
                                'v${module.manifest.version}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.zMuted,
                                ),
                              ),
                            ],
                          ),
                          if (module.manifest.description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                module.manifest.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.zMuted,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (module.manifest.permissions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: <Widget>[
                                  for (final ModulePermission p
                                      in module.manifest.permissions)
                                    Chip(
                                      label: Text(
                                        p.name,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              TextButton.icon(
                                key: Key('module-new-chat-${module.name}'),
                                onPressed: () => _startInNewChat(module),
                                icon: const Icon(
                                  Icons.add_comment_rounded,
                                  size: 16,
                                ),
                                label: Text(strings.moduleStartNewChat),
                              ),
                              const Spacer(),
                              IconButton(
                                key: Key('module-export-${module.name}'),
                                tooltip: strings.moduleExportTooltip,
                                icon: Icon(
                                  Icons.ios_share_rounded,
                                  color: context.zMuted,
                                ),
                                onPressed: () => _export(module),
                              ),
                              IconButton(
                                key: Key('module-remove-${module.name}'),
                                tooltip: strings.delete,
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: context.zMuted,
                                ),
                                onPressed: () => _remove(module),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyModules extends ConsumerWidget {
  const _EmptyModules({required this.onInstall});

  final Future<void> Function() onInstall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.extension_rounded, size: 48, color: context.zMuted),
            const SizedBox(height: 12),
            Text(strings.modulesEmpty, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              strings.modulesEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.zMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// In-app viewer for the official Module SDK documentation (canonical
/// sources live in `docs/modules/` of the repository; shipped as app
/// assets, English and Bahasa Indonesia).
class SdkDocsScreen extends ConsumerWidget {
  const SdkDocsScreen({super.key});

  /// Canonical documentation sources in the repository (declared as app
  /// assets in pubspec.yaml) — also asserted by module_sdk_assets_test.
  static const String docAssetEn = 'docs/modules/sdk-reference-en.md';
  static const String docAssetId = 'docs/modules/sdk-reference-id.md';

  Future<String> _loadDoc(String languageCode) async {
    final String asset = languageCode.trim().toLowerCase().startsWith('id')
        ? docAssetId
        : docAssetEn;
    try {
      return await rootBundle.loadString(asset);
    } catch (_) {
      // Asset missing in a stripped build: fall back to the other locale.
      return rootBundle.loadString(docAssetEn);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    final String languageCode = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );
    return Scaffold(
      appBar: AppBar(title: Text(strings.moduleSdkDocs)),
      body: FutureBuilder<String>(
        future: _loadDoc(languageCode),
        builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final String doc = snapshot.data ?? '';
          if (doc.isEmpty) {
            return Center(
              child: Text(
                strings.operationFailed,
                style: TextStyle(color: context.zMuted),
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(
              data: doc,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                code: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A bundled catalog entry: one official sample module from the repo's
/// `samples/` folder, with its slash command (or the /plugins activation
/// path) and a one-line description.
class _OfficialSample {
  const _OfficialSample(this.name, this.command, this.description);
  final String name;
  final String command;
  final String description;
}

/// Static catalog of every module shipped in `samples/` (kept in sync with
/// the repo README). The app cannot reach into GitHub at runtime, so the
/// catalog documents WHAT to install from the samples zips — the install
/// itself stays a local, user-driven ZIP pick (no remote code execution).
const List<_OfficialSample> _kOfficialSamples = <_OfficialSample>[
  _OfficialSample(
    'counter',
    '/plugins counter',
    'Per-chat counter — storage isolation demo.',
  ),
  _OfficialSample(
    'network-fetcher',
    '/plugins network-fetcher',
    'Allowlisted HTTP fetch (api.github.com only).',
  ),
  _OfficialSample(
    'file-notes',
    '/plugins file-notes',
    'Sandboxed notes inside the per-chat state dir.',
  ),
  _OfficialSample(
    'chat-streamer',
    '/plugins chat-streamer',
    'Progressive output via zagents.chat.emit.',
  ),
  _OfficialSample(
    'onhomeroom-daily',
    '/plugins onhomeroom-daily',
    'Daily bot for app.onhomeroom.com (agent.compose).',
  ),
  _OfficialSample(
    'airplane-mode',
    '/airplane',
    'Airplane IP-rotation cycle (root / manual).',
  ),
  _OfficialSample(
    'evm-wallet',
    '/wallet',
    'Generate-only EVM wallet with signed transfers.',
  ),
  _OfficialSample(
    'web-browser',
    '/web',
    'Text-mode browser: reader extraction + search.',
  ),
  _OfficialSample(
    'rss-reader',
    '/rss',
    'Per-chat RSS 2.0 / Atom subscriptions.',
  ),
  _OfficialSample('qr-tools', '/qr', 'Scannable QR codes, zero permissions.'),
  _OfficialSample(
    'facebook-page',
    '/fb',
    'Fanspage assistant: auto-reply comments + Messenger (templates + AI polish).',
  ),
  _OfficialSample(
    'twitter-x',
    '/tw',
    'X/Twitter assistant: auto-reply mentions (OAuth 1.0a + AI polish).',
  ),
  _OfficialSample(
    'totp-auth',
    '/otp',
    'RFC 6238 authenticator — secrets never leave the device.',
  ),
  _OfficialSample(
    'csv-data',
    '/csv',
    'RFC 4180 CSV studio: stats, filter, chart.',
  ),
  _OfficialSample(
    'converters',
    '/cur + /unit',
    'Live currency rates + offline unit engine.',
  ),
];

/// v1.44.0 — the "Official sample modules" card at the bottom of the
/// Modules screen: documents every sample shipped with the repo, what it
/// demonstrates and how it is activated, so a fresh install knows what to
/// reach for. Pure documentation — nothing here executes.
class _OfficialCatalog extends ConsumerWidget {
  const _OfficialCatalog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    return Card(
      key: const Key('official-modules-catalog'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.category_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.officialModulesTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              strings.officialModulesSubtitle,
              style: TextStyle(fontSize: 12, color: context.zMuted),
            ),
            const SizedBox(height: 8),
            for (final _OfficialSample sample in _kOfficialSamples)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: Text(
                        sample.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        sample.command,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.zMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 6,
                      child: Text(
                        sample.description,
                        style: TextStyle(fontSize: 11, color: context.zMuted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
