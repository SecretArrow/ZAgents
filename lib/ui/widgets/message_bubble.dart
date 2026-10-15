import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../theme.dart';
import 'todo_plan_card.dart';
import 'tool_call_card.dart';

/// One chat message: user (gradient bubble, right, with attachment
/// previews) or assistant (surface bubble, left, markdown + tool cards).
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.todos = const <TodoItem>[],
    this.agentWorking = false,
    this.onEdit,
    this.onRegenerate,
  });

  final ChatMessage message;

  /// Latest plan of the running session — powers the show/hide panel next
  /// to the thinking indicator.
  final List<TodoItem> todos;

  /// True when the session's agent loop is active AND this bubble is the
  /// newest message: keeps the thinking indicator (and its plan toggle)
  /// visible while tools execute, not just while text streams.
  final bool agentWorking;

  /// Invoked with the new text when the user saves the edit dialog on a
  /// USER bubble. Null hides the edit button entirely (running session,
  /// empty content or no editable session).
  final ValueChanged<String>? onEdit;

  /// Invoked when the user taps the regenerate button under the LAST
  /// ASSISTANT bubble. Null hides the button entirely.
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    if (message.role == Role.user) {
      final bool hasText = message.content.trim().isNotEmpty;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.8,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: kBrandGradient,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (message.attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 6,
                          runSpacing: 6,
                          children: <Widget>[
                            for (final ChatAttachment att
                                in message.attachments)
                              _AttachmentPreview(attachment: att),
                          ],
                        ),
                      ),
                    if (message.content.trim().isNotEmpty)
                      SelectableText(
                        message.content,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (hasText)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (onEdit != null)
                    _EditButton(initialText: message.content, onEdit: onEdit!),
                  _CopyButton(text: message.content),
                ],
              ),
          ],
        ),
      );
    }

    final bool hasToolCards = message.toolCalls.isNotEmpty;
    final bool showContent = message.content.trim().isNotEmpty;
    // No copy control while the answer is still streaming — it appears
    // together with the final text (and never on text-less tool bubbles).
    final bool canCopy = showContent && !message.isStreaming;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.88,
              ),
              padding: EdgeInsets.fromLTRB(
                hasToolCards ? 10 : 14,
                10,
                hasToolCards ? 10 : 14,
                hasToolCards ? 6 : 10,
              ),
              decoration: BoxDecoration(
                color: context.zSurfaceAlt,
                border: Border.all(color: context.zBorder),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final ToolCall call in message.toolCalls)
                    if (call.name == 'todo_write' &&
                        parseTodoList(call.arguments['todos']).isNotEmpty)
                      TodoPlanCard(call: call)
                    else
                      ToolCallCard(call: call),
                  if (showContent)
                    MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        h1: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        h2: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        h3: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: context.zBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.zBorder),
                        ),
                        code: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFFB8C4FF)
                              : const Color(0xFF3D51B4),
                        ),
                        listBullet: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  if (message.isStreaming ||
                      (agentWorking && message.role == Role.assistant))
                    _ThinkingFooter(todos: todos),
                ],
              ),
            ),
          ),
          if (canCopy) _CopyButton(text: message.content),
          if (onRegenerate != null)
            _RegenerateButton(onRegenerate: onRegenerate!),
        ],
      ),
    );
  }
}

/// Small edit control under a USER bubble: opens a multiline dialog
/// pre-filled with the sent text; saving triggers editUserMessage, which
/// truncates everything after the message and regenerates the answer.
class _EditButton extends StatelessWidget {
  const _EditButton({required this.initialText, required this.onEdit});

  /// The message's current text — pre-fills the edit dialog.
  final String initialText;

  final ValueChanged<String> onEdit;

  Future<void> _openDialog(BuildContext context) async {
    final AppStrings strings = stringsOf(context);
    final TextEditingController controller = TextEditingController(
      text: initialText,
    );
    final String? newText = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: context.zSurface,
        title: Text(strings.editDialogTitle),
        content: TextField(
          key: const Key('edit-message-field'),
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          TextButton(
            key: const Key('edit-message-save'),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(strings.save),
          ),
        ],
      ),
    );
    if (newText != null && newText.trim().isNotEmpty) {
      onEdit(newText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    return IconButton(
      key: const Key('edit-message-button'),
      tooltip: strings.editMessageAction,
      onPressed: () => _openDialog(context),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      icon: Icon(Icons.edit_rounded, size: 15, color: context.zMuted),
    );
  }
}

/// Regenerate control under the LAST assistant bubble: one tap drops the
/// answer and replays the conversation from the preceding user message.
class _RegenerateButton extends StatelessWidget {
  const _RegenerateButton({required this.onRegenerate});

  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    return IconButton(
      key: const Key('regenerate-button'),
      tooltip: strings.regenerate,
      onPressed: onRegenerate,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      icon: Icon(Icons.refresh_rounded, size: 16, color: context.zMuted),
    );
  }
}

/// Small copy control rendered under every message bubble (sent and
/// received): one tap puts the raw text on the clipboard and the icon
/// flips to a check mark for a moment as confirmation.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  /// Text placed on the clipboard (verbatim, unformatted).
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _resetTimer;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    return IconButton(
      key: const Key('copy-message-button'),
      tooltip: _copied ? strings.copied : strings.copyMessage,
      onPressed: _copy,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          key: ValueKey<bool>(_copied),
          size: 15,
          color: _copied ? const Color(0xFF4CC38A) : context.zMuted,
        ),
      ),
    );
  }
}

/// Footer row under a working assistant message: spinner + "thinking…"
/// on the left, and — as soon as the agent has written a plan — a
/// right-aligned show/hide toggle that reveals the LIVE todo panel so the
/// user can check at any time how far the agent has progressed.
class _ThinkingFooter extends StatefulWidget {
  const _ThinkingFooter({required this.todos});

  final List<TodoItem> todos;

  @override
  State<_ThinkingFooter> createState() => _ThinkingFooterState();
}

class _ThinkingFooterState extends State<_ThinkingFooter> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final bool hasPlan = widget.todos.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              strings.thinking,
              style: TextStyle(color: context.zMuted, fontSize: 12),
            ),
            const Spacer(),
            if (hasPlan)
              IconButton(
                key: const Key('todo-toggle-button'),
                tooltip: _expanded
                    ? strings.hidePlanTooltip
                    : strings.showPlanTooltip,
                icon: Icon(
                  _expanded
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16,
                  color: context.zMuted,
                ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: const EdgeInsets.all(6),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
          ],
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: _expanded && hasPlan
              ? TodoPlanView(
                  key: const Key('live-todo-panel'),
                  todos: widget.todos,
                  live: true,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Inline preview of a sent attachment inside the user bubble: a small
/// image thumbnail or a file chip.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    if (attachment.kind == AttachmentKind.image) {
      final File file = File(attachment.path);
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: file.existsSync()
            ? Image.file(
                file,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 120,
                  height: 120,
                  color: Colors.white24,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white70,
                  ),
                ),
              )
            : Container(
                width: 120,
                height: 120,
                color: Colors.white24,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white70,
                ),
              ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.insert_drive_file_rounded,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
