import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../screens/settings_screen.dart';
import '../theme.dart';

/// Navigation drawer: brand header, new chat, history list, settings.
class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final AppStrings strings = stringsOf(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: kSurfaceColor,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    final AsyncValue<List<ChatSummary>> history = ref.watch(chatListProvider);
    return Drawer(
      backgroundColor: kSurfaceColor,
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'ZAgents',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        strings.agentTagline,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
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
                    style: const TextStyle(
                      color: kMutedTextColor,
                      fontSize: 13,
                    ),
                  ),
                ),
                data: (List<ChatSummary> items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        strings.noChats,
                        style: const TextStyle(
                          color: kMutedTextColor,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ChatSummary item = items[index];
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
                        subtitle: Text(
                          '${item.updatedAt.day}/${item.updatedAt.month}/${item.updatedAt.year}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: kMutedTextColor,
                          ),
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
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
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
