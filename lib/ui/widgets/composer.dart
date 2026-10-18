import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../services/module_registry.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../screens/modules_screen.dart';
import '../screens/prompt_library_screen.dart';
import '../theme.dart';

/// Bottom composer: attachment chips, rounded input, gradient send /
/// stop button. The paperclip copies the picked file into the app's
/// uploads folder and stages it for the next message.
class Composer extends ConsumerStatefulWidget {
  const Composer({super.key});

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _controller.text.trim();
    final List<ChatAttachment> attachments = ref.read(
      pendingAttachmentsProvider,
    );
    if (text.isEmpty && attachments.isEmpty) return;
    // Slash commands are consumed LOCALLY — they never reach the LLM.
    if (text == '/plugins') {
      _controller.clear();
      FocusScope.of(context).unfocus();
      _openModuleSheet();
      return;
    }
    if (text.startsWith('/plugins ')) {
      final String moduleName = text.substring('/plugins '.length).trim();
      _controller.clear();
      FocusScope.of(context).unfocus();
      _activateNamedModule(moduleName);
      return;
    }
    _controller.clear();
    ref.read(pendingAttachmentsProvider.notifier).state =
        const <ChatAttachment>[];
    FocusScope.of(context).unfocus();
    ref
        .read(chatControllerProvider.notifier)
        .send(text, attachments: attachments);
  }

  /// `/plugins name`: resolves the module, asks for permission consent
  /// (when the manifest declares capabilities) and activates it for the
  /// current chat. Unknown names surface a localized snackbar.
  Future<void> _activateNamedModule(String name) async {
    if (name.isEmpty) {
      _openModuleSheet();
      return;
    }
    final AppStrings strings = stringsOf(context);
    final ChatModule? module = await ref.read(moduleRegistryProvider).get(name);
    if (!mounted) return;
    if (module == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.moduleNotFound(name))));
      return;
    }
    if (!await ModulesScreen.confirmPermissions(context, ref, module)) {
      return;
    }
    if (!mounted) return;
    await ref.read(chatControllerProvider.notifier).activateModule(module.name);
  }

  /// Interactive module menu for `/plugins`: every installed module with
  /// its active state; tapping activates (with consent) in the current
  /// chat, the trailing trash button removes (uninstalls) the module
  /// after confirmation, and a footer shortcut opens the Modules manager.
  Future<void> _openModuleSheet() async {
    final AppStrings strings = stringsOf(context);
    ref.invalidate(moduleListProvider);
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => Consumer(
        builder: (BuildContext context, WidgetRef sheetRef, _) {
          final AsyncValue<List<ChatModule>> modules = sheetRef.watch(
            moduleListProvider,
          );
          final List<String> active = sheetRef.watch(
            chatControllerProvider.select((s) => s.activeModules),
          );
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          strings.pluginMenuTitle,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('plugin-sheet-manage'),
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(this.context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ModulesScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.extension_rounded, size: 16),
                        label: Text(strings.modulesManage),
                      ),
                    ],
                  ),
                ),
                modules.when(
                  loading: () => const SizedBox(
                    height: 120,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (Object e, StackTrace s) => SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        strings.operationFailed,
                        style: TextStyle(color: context.zMuted),
                      ),
                    ),
                  ),
                  data: (List<ChatModule> items) => items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: Column(
                            children: <Widget>[
                              Text(
                                strings.pluginMenuEmpty,
                                style: TextStyle(color: context.zMuted),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                key: const Key('plugin-sheet-open-modules'),
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  Navigator.of(this.context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const ModulesScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: Text(strings.modulesInstall),
                              ),
                            ],
                          ),
                        )
                      : Flexible(
                          child: ListView.builder(
                            key: const Key('plugin-sheet-list'),
                            shrinkWrap: true,
                            itemCount: items.length,
                            itemBuilder: (BuildContext context, int index) {
                              final ChatModule module = items[index];
                              final bool isActive = active.contains(
                                module.name,
                              );
                              return ListTile(
                                key: Key('plugin-sheet-item-${module.name}'),
                                dense: true,
                                leading: Icon(
                                  isActive
                                      ? Icons.check_circle_rounded
                                      : Icons.extension_rounded,
                                  size: 20,
                                  color: isActive ? null : context.zMuted,
                                ),
                                title: Text(
                                  module.manifest.title.isEmpty
                                      ? module.name
                                      : module.manifest.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: module.manifest.description.isEmpty
                                    ? null
                                    : Text(
                                        module.manifest.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      'v${module.manifest.version}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.zMuted,
                                      ),
                                    ),
                                    IconButton(
                                      key: Key(
                                        'plugin-sheet-remove-${module.name}',
                                      ),
                                      tooltip: strings.delete,
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: context.zMuted,
                                      ),
                                      onPressed: () =>
                                          _removeModule(sheetRef, module),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  final NavigatorState sheetNav = Navigator.of(
                                    sheetContext,
                                  );
                                  if (isActive) {
                                    await sheetRef
                                        .read(chatControllerProvider.notifier)
                                        .deactivateModule(module.name);
                                    sheetNav.pop();
                                    return;
                                  }
                                  if (!await ModulesScreen.confirmPermissions(
                                    this.context,
                                    sheetRef,
                                    module,
                                  )) {
                                    return;
                                  }
                                  await sheetRef
                                      .read(chatControllerProvider.notifier)
                                      .activateModule(module.name);
                                  sheetNav.pop();
                                },
                              );
                            },
                          ),
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Uninstalls a module straight from the `/plugins` sheet: confirm →
  /// deactivate in the current chat (when active) → delete from the
  /// registry → refresh the list. The sheet stays open so the user can
  /// continue managing modules.
  Future<void> _removeModule(WidgetRef sheetRef, ChatModule module) async {
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
    final bool removed = await sheetRef
        .read(moduleRegistryProvider)
        .remove(module.name);
    if (!removed) return;
    if (sheetRef
        .read(chatControllerProvider)
        .activeModules
        .contains(module.name)) {
      await sheetRef
          .read(chatControllerProvider.notifier)
          .deactivateModule(module.name);
    }
    sheetRef.invalidate(moduleListProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(strings.moduleRemoved(module.name))),
      );
  }

  Future<void> _pickFile() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final XFile? picked = await openFile();
      if (picked == null) return;
      // Uploads live in the ACTIVE session's own workspace — files never
      // mix between chats (private-window isolation).
      final Directory root = await ref
          .read(sessionSandboxProvider)
          .rootFor(ref.read(activeSessionIdProvider));
      final Directory uploads = Directory(
        '${root.path}${Platform.pathSeparator}uploads',
      );
      if (!uploads.existsSync()) uploads.createSync(recursive: true);
      final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String safeName = picked.name.replaceAll('/', '_');
      final File dest = File(
        '${uploads.path}${Platform.pathSeparator}${stamp}_$safeName',
      );
      await File(picked.path).copy(dest.path);
      final ChatAttachment attachment = ChatAttachment(
        name: safeName,
        path: dest.path,
        sizeBytes: await dest.length(),
        kind: attachmentKindFor(safeName),
      );
      ref.read(pendingAttachmentsProvider.notifier).state = <ChatAttachment>[
        ...ref.read(pendingAttachmentsProvider),
        attachment,
      ];
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(stringsOf(context).operationFailed)),
          );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Appends the chosen prompt's content to the composer text (at the
  /// cursor end) and keeps the keyboard focus.
  void _insertPrompt(PromptEntry entry) {
    final String base = _controller.text;
    final String merged = base.isEmpty
        ? entry.content
        : base.endsWith('\n')
        ? '$base${entry.content}'
        : '$base\n${entry.content}';
    _controller.text = merged;
    _controller.selection = TextSelection.collapsed(offset: merged.length);
    _focusNode.requestFocus();
  }

  /// Bottom sheet listing the Prompt Library entries; tapping one inserts
  /// it into the composer. Includes a shortcut into the library screen.
  Future<void> _openPromptSheet() async {
    final AppStrings strings = stringsOf(context);
    ref.invalidate(promptListProvider);
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => Consumer(
        builder: (BuildContext context, WidgetRef sheetRef, _) {
          final AsyncValue<List<PromptEntry>> prompts = sheetRef.watch(
            promptListProvider,
          );
          return SafeArea(
            child: prompts.when(
              loading: () => const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (Object e, StackTrace s) => SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    strings.operationFailed,
                    style: TextStyle(color: context.zMuted),
                  ),
                ),
              ),
              data: (List<PromptEntry> items) => Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            strings.promptLibrary,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          key: const Key('prompt-sheet-manage'),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            Navigator.of(this.context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PromptLibraryScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.bookmarks_rounded, size: 16),
                          label: Text(strings.edit),
                        ),
                      ],
                    ),
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      child: Column(
                        children: <Widget>[
                          Text(
                            strings.promptLibraryEmpty,
                            style: TextStyle(color: context.zMuted),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            key: const Key('prompt-sheet-open-library'),
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              Navigator.of(this.context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const PromptLibraryScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: Text(strings.newPrompt),
                          ),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        key: const Key('prompt-sheet-list'),
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (BuildContext context, int index) {
                          final PromptEntry entry = items[index];
                          return ListTile(
                            key: Key('prompt-sheet-item-${entry.id}'),
                            dense: true,
                            leading: const Icon(Icons.notes_rounded, size: 18),
                            title: Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: entry.content.isEmpty
                                ? null
                                : Text(
                                    entry.content,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              _insertPrompt(entry);
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final bool isRunning = ref.watch(
      chatControllerProvider.select((s) => s.isRunning),
    );
    final List<ChatAttachment> pending = ref.watch(pendingAttachmentsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (pending.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                key: const Key('pending-attachments'),
                scrollDirection: Axis.horizontal,
                shrinkWrap: true,
                children: <Widget>[
                  for (final ChatAttachment att in pending)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        avatar: Icon(
                          att.kind == AttachmentKind.image
                              ? Icons.image_rounded
                              : Icons.insert_drive_file_rounded,
                          size: 16,
                          color: context.zMuted,
                        ),
                        label: Text(
                          att.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: context.zSurfaceAlt,
                        side: BorderSide(color: context.zBorder),
                        onDeleted: () {
                          ref
                              .read(pendingAttachmentsProvider.notifier)
                              .state = ref
                              .read(pendingAttachmentsProvider)
                              .where((ChatAttachment a) => a.path != att.path)
                              .toList();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              IconButton(
                key: const Key('attach-button'),
                tooltip: strings.attachFile,
                onPressed: _picking ? null : _pickFile,
                icon: _picking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.attach_file_rounded, color: context.zMuted),
              ),
              IconButton(
                key: const Key('prompt-insert-button'),
                tooltip: strings.insertPrompt,
                onPressed: _openPromptSheet,
                icon: Icon(Icons.notes_rounded, color: context.zMuted),
              ),
              Expanded(
                child: TextField(
                  key: const Key('composer-field'),
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: strings.askAnything),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  gradient: isRunning ? null : kBrandGradient,
                  // v1.30.0: the Stop button is clearly red — it must read
                  // as an interrupt control, not a disabled send button.
                  color: isRunning ? const Color(0xFFE5484D) : null,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  key: Key(isRunning ? 'stop-button' : 'send-button'),
                  onPressed: isRunning
                      ? () => ref.read(chatControllerProvider.notifier).stop()
                      : _submit,
                  icon: Icon(
                    isRunning ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                    color: Colors.white,
                  ),
                  tooltip: isRunning ? strings.stop : strings.send,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
