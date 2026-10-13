import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
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
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _controller.text.trim();
    final List<ChatAttachment> attachments = ref.read(
      pendingAttachmentsProvider,
    );
    if (text.isEmpty && attachments.isEmpty) return;
    _controller.clear();
    ref.read(pendingAttachmentsProvider.notifier).state =
        const <ChatAttachment>[];
    FocusScope.of(context).unfocus();
    ref
        .read(chatControllerProvider.notifier)
        .send(text, attachments: attachments);
  }

  Future<void> _pickFile() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final XFile? picked = await openFile();
      if (picked == null) return;
      final Directory docs = await ref.read(documentsDirProvider)();
      final Directory uploads = Directory(
        '${docs.path}${Platform.pathSeparator}uploads',
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
              Expanded(
                child: TextField(
                  key: const Key('composer-field'),
                  controller: _controller,
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
                  color: isRunning ? context.zSurfaceAlt : null,
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
