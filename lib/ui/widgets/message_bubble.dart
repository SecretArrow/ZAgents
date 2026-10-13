import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../theme.dart';
import 'tool_call_card.dart';

/// One chat message: user (gradient bubble, right, with attachment
/// previews) or assistant (surface bubble, left, markdown + tool cards).
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    if (message.role == Role.user) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                        for (final ChatAttachment att in message.attachments)
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
      );
    }

    final bool hasToolCards = message.toolCalls.isNotEmpty;
    final bool showContent = message.content.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
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
              if (message.isStreaming)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
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
