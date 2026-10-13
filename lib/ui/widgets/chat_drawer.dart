import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../screens/files_screen.dart';
import '../screens/settings_screen.dart';
import '../theme.dart';
import 'paged_list.dart';

/// Navigation drawer: brand header, new chat, files, history list
/// (long-press to rename, running badge for parallel sessions),
/// session import/export and settings.
class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({super.key});

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final AppStrings strings = stringsOf(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: context.zSurface,
        title: Text(strings.deleteChatTitle),
        content: Text(strings.deleteChatBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(chatControllerProvider.notifier).deleteChat(id);
    }
  }

  Future<void> _renameChat(
    BuildContext context,
    WidgetRef ref,
    ChatSummary item,
  ) async {
    final AppStrings strings = stringsOf(context);
    final TextEditingController controller = TextEditingController(
      text: item.title,
    );
    final String? newName = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: context.zSurface,
        title: Text(strings.renameChatTitle),
        content: TextField(
          autofocus: true,
          controller: controller,
          decoration: InputDecoration(labelText: strings.nameHint),
          onSubmitted: (String value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(strings.save),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;
    await ref
        .read(chatControllerProvider.notifier)
        .renameChat(item.id, newName);
  }

  Future<void> _exportSessions(BuildContext context, WidgetRef ref) async {
    final AppStrings strings = stringsOf(context);
    try {
      final dynamic file = await ref.read(sessionExporterProvider).exportAll();
      if (!context.mounted) return;
      _snack(context, strings.exportDone(file.path));
    } catch (_) {
      if (!context.mounted) return;
      _snack(context, strings.operationFailed);
    }
  }

  Future<void> _importSessions(BuildContext context, WidgetRef ref) async {
    final AppStrings strings = stringsOf(context);
    try {
      final XFile? picked = await openFile();
      if (picked == null) return;
      final int count = await ref
          .read(sessionExporterProvider)
          .importFrom(picked.path);
      ref.invalidate(chatListProvider);
      if (!context.mounted) return;
      _snack(context, strings.importDone(count));
    } catch (_) {
      if (!context.mounted) return;
      _snack(context, strings.importFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    final AsyncValue<List<ChatSummary>> history = ref.watch(chatListProvider);
    final Set<String> running = ref.watch(runningSessionsProvider);
    return Drawer(
      backgroundColor: context.zSurface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: kBrandGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: <Widget>[
                  const BrandMark(size: 36),
                  const SizedBox(width: 12),
                  // Expanded so narrow drawers can never overflow the row.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          'ZAgents',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          strings.agentTagline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FilledButton.icon(
                key: const Key('new-chat'),
                onPressed: () {
                  ref.read(chatControllerProvider.notifier).newChat();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.add_rounded),
                label: Text(strings.newChat),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                key: const Key('drawer-files'),
                dense: true,
                leading: const Icon(Icons.folder_open_rounded, size: 20),
                title: Text(strings.filesTitle),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FilesScreen(),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Text(
                strings.historyTitle.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: kMutedTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: history.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (Object error, StackTrace stack) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    strings.historyLoadFailed,
                    style: TextStyle(color: context.zMuted, fontSize: 13),
                  ),
                ),
                data: (List<ChatSummary> items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        strings.noChats,
                        style: TextStyle(color: context.zMuted, fontSize: 13),
                      ),
                    );
                  }
                  return PagedList<ChatSummary>(
                    prefix: 'history',
                    searchFieldKey: const Key('history-search-field'),
                    searchHint: strings.searchSessionsHint,
                    items: items,
                    resetKey: items.length,
                    filter: (ChatSummary c, String q) =>
                        c.title.toLowerCase().contains(q),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemBuilder: (BuildContext context, ChatSummary item) {
                      final bool isRunning = running.contains(item.id);
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: kMutedTextColor,
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                '${item.updatedAt.day}/${item.updatedAt.month}/${item.updatedAt.year}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.zMuted,
                                ),
                              ),
                            ),
                            if (isRunning) ...<Widget>[
                              const SizedBox(width: 8),
                              const SizedBox(
                                key: Key('running-badge'),
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: kMutedTextColor,
                          ),
                          onPressed: () =>
                              _confirmDelete(context, ref, item.id),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          ref
                              .read(chatControllerProvider.notifier)
                              .openChat(item);
                        },
                        onLongPress: () => _renameChat(context, ref, item),
                      );
                    },
                    emptyBuilder: (BuildContext emptyContext) => Center(
                      child: Text(
                        strings.noResults,
                        style: TextStyle(
                          color: emptyContext.zMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.file_upload_outlined, size: 20),
              title: Text(
                strings.importSessions,
                style: const TextStyle(fontSize: 13),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _importSessions(context, ref);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.file_download_outlined, size: 20),
              title: Text(
                strings.exportSessions,
                style: const TextStyle(fontSize: 13),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _exportSessions(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(strings.settings),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
