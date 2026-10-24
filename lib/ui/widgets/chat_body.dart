import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../models/models.dart';
import '../../services/agent_controller.dart' show ChatController, ChatState;
import 'empty_state.dart';
import 'message_bubble.dart';
import 'plan_panel.dart';

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

    // Edit/regenerate visibility (v1.15.0): the edit button shows on every
    // non-empty USER bubble while the session is idle; the regenerate
    // button only under the LAST assistant bubble when a preceding user
    // message exists. Both hide while the agent is running.
    final String? sessionId = state.sessionId;
    final bool idle = !state.isRunning && sessionId != null;
    final int lastAssistantIndex = state.messages.lastIndexWhere(
      (ChatMessage m) => m.role == Role.assistant,
    );
    final ChatController controller = ref.read(chatControllerProvider.notifier);

    // v1.38.0: the live Plan panel is PINNED above the list and driven by
    // the global planPanelOpenProvider — it never closes on streaming
    // updates, step transitions, run end or chat switching (see PlanPanel).
    return Column(
      children: <Widget>[
        const PlanPanel(),
        Expanded(
          child: ListView.builder(
            key: const Key('message-list'),
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: items.length,
            itemBuilder: (BuildContext context, int index) {
              final ChatMessage message = items[index];
              // The list is reversed: translate back to the transcript index the
              // controller uses for editUserMessage.
              final int messageIndex = items.length - 1 - index;
              final bool canEdit =
                  idle &&
                  message.role == Role.user &&
                  message.content.trim().isNotEmpty;
              final bool canRegenerate =
                  idle &&
                  messageIndex == lastAssistantIndex &&
                  messageIndex > 0 &&
                  state.messages
                      .take(messageIndex)
                      .any((ChatMessage m) => m.role == Role.user);
              return MessageBubble(
                // v1.34.0: stable identity per message — Flutter can reuse the
                // element and skip rebuilding every historical bubble while a
                // streaming delta only changes the LAST item.
                key: ValueKey<String>(message.id),
                message: message,
                // Live plan for the thinking indicator's show/hide panel.
                todos: state.todos,
                agentWorking: state.isRunning && index == 0,
                onEdit: canEdit
                    ? (String newText) => controller.editUserMessage(
                        sessionId,
                        messageIndex,
                        newText,
                      )
                    : null,
                onRegenerate: canRegenerate
                    ? () => controller.regenerate(sessionId)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
