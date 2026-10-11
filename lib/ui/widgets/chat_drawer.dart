import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
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
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: kSurfaceColor,
        title: const Text('Hapus percakapan?'),
        content: const Text('Percakapan ini akan dihapus permanen.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
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
              child: const Row(
                children: <Widget>[
                  BrandMark(size: 36),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'ZAgents',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'AI Agent · Flutter',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
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
                label: const Text('Percakapan baru'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                'RIWAYAT',
                style: TextStyle(
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
                error: (Object error, StackTrace stack) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Gagal memuat riwayat.',
                    style: TextStyle(color: kMutedTextColor, fontSize: 13),
                  ),
                ),
                data: (List<ChatSummary> items) {
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Belum ada percakapan.',
                        style: TextStyle(color: kMutedTextColor, fontSize: 13),
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
              title: const Text('Pengaturan'),
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
