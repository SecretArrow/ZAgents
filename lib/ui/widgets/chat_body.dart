import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../models/models.dart';
import '../../services/agent_controller.dart' show ChatState;
import 'empty_state.dart';
import 'message_bubble.dart';

/// Message list (bottom-anchored via reverse ListView) or empty state.
class ChatBody extends ConsumerWidget {
  const ChatBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ChatState state = ref.watch(chatControllerProvider);
    if (state.messages.isEmpty) {
      return const EmptyState();
    }
    final List<ChatMessage> items = state.messages.reversed.toList();
    return ListView.builder(
      key: const Key('message-list'),
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) => MessageBubble(
        message: items[index],
        // Live plan for the thinking indicator's show/hide panel.
        todos: state.todos,
        agentWorking: state.isRunning && index == 0,
      ),
    );
  }
}
