import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../theme.dart';

/// Bottom composer: rounded input + gradient send button / stop button.
class Composer extends ConsumerStatefulWidget {
  const Composer({super.key});

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    FocusScope.of(context).unfocus();
    ref.read(chatControllerProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final bool isRunning = ref.watch(
      chatControllerProvider.select((s) => s.isRunning),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
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
              color: isRunning ? kSurfaceAltColor : null,
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
    );
  }
}
