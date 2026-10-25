import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../services/attachment_service.dart';
import '../../services/module_registry.dart';
import '../../services/speech_service.dart';
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

  /// v1.44.0 — live dictation state: a listening session renders an inline
  /// partial-text row and turns the mic control into a stop control.
  bool _listening = false;
  String _speechPartial = '';

  /// v1.42.0 — consecutive Stop taps while the SAME run is still active.
  /// 1 tap = graceful stop; tap 2 asks again + hints; tap 3 opens the
  /// force-stop offer dialog. Reset whenever the running flag flips (run
  /// ended, or a new run started), so counts never leak across runs.
  int _stopTaps = 0;

  /// v1.38.1 — the chat this text field is currently bound to (null =
  /// fresh draft). Typed text is stored per chat in the controller, so
  /// switching chats swaps the draft and one chat's text never appears
  /// in another.
  String? _boundSession;

  @override
  void initState() {
    super.initState();
    _boundSession = ref.read(chatControllerProvider).sessionId;
    _controller.text = ref
        .read(chatControllerProvider.notifier)
        .draftTextFor(_boundSession);
    _controller.addListener(() {
      ref
          .read(chatControllerProvider.notifier)
          .setDraftText(_boundSession, _controller.text);
    });
  }

  /// Re-binds the field to another chat: the old text is already saved by
  /// the listener; load the target chat's own draft (never another's).
  void _rebind(String? session) {
    if (_boundSession == session) return;
    _boundSession = session;
    final String draft = ref
        .read(chatControllerProvider.notifier)
        .draftTextFor(session);
    if (_controller.text == draft) return;
    _controller.text = draft;
    _controller.selection = TextSelection.collapsed(offset: draft.length);
  }

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
    // The picker is a system dialog: the user can switch chats while it is
    // open. Files belong to the chat they were picked FROM, so the session is
    // captured before the await and the result is discarded if the user moved
    // on — otherwise chat A's file silently appeared in chat B's composer.
    final String? sessionId = ref.read(activeSessionIdProvider);
    try {
      final XFile? picked = await openFile();
      if (picked == null) return;
      if (ref.read(activeSessionIdProvider) != sessionId) return;
      // v1.44.0: images take the optimization pipeline — validated by
      // content magic, downscaled to a 1600 px long edge, re-encoded —
      // and are stored under `attachments/` in the SAME per-chat sandbox.
      // Non-image files keep the byte-for-byte uploads copy below.
      if (AttachmentService.looksLikeImage(picked.name)) {
        final AttachmentResult result = await ref
            .read(attachmentServiceProvider)
            .optimizeAndStore(sessionId: sessionId, picked: picked);
        if (ref.read(activeSessionIdProvider) != sessionId) return;
        if (!result.ok) {
          if (mounted) _showAttachmentError(result);
          return;
        }
        final List<String> refParts = result.relativePath!.split(
          Platform.pathSeparator,
        );
        final ChatAttachment attachment = ChatAttachment(
          name: refParts.last,
          path: result.absolutePath!,
          sizeBytes: result.bytes!.length,
          kind: AttachmentKind.image,
        );
        ref.read(pendingAttachmentsProvider.notifier).state = <ChatAttachment>[
          ...ref.read(pendingAttachmentsProvider),
          attachment,
        ];
        return;
      }
      // Uploads live in the ACTIVE session's own workspace — files never
      // mix between chats (private-window isolation).
      final Directory root = await ref
          .read(sessionSandboxProvider)
          .rootFor(sessionId);
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
      if (ref.read(activeSessionIdProvider) != sessionId) {
        // The user switched while the copy ran: don't leave an orphan file
        // (and don't stage it into the wrong chat).
        try {
          if (dest.existsSync()) dest.deleteSync();
        } catch (_) {}
        return;
      }
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
    // v1.42.0: the tap counter is only meaningful within one run — any
    // running-state change (run ended or a new run began) starts fresh.
    ref.listen<bool>(chatControllerProvider.select((s) => s.isRunning), (
      bool? previous,
      bool next,
    ) {
      if (previous != next && _stopTaps != 0) _stopTaps = 0;
    });
    // v1.38.1: swap the draft text when the displayed chat changes.
    ref.listen<String?>(
      chatControllerProvider.select((s) => s.sessionId),
      (String? previous, String? current) => _rebind(current),
    );
    // v1.44.0: dictation belongs to the chat it was started in — a chat
    // switch ends the speech session instead of letting the final words
    // land in another chat's draft.
    ref.listen<String?>(chatControllerProvider.select((s) => s.sessionId), (
      String? previous,
      String? current,
    ) {
      if (previous != current && _listening) {
        ref.read(speechServiceProvider).stop();
      }
    });
    // A chat whose history is still being read has no runnable transcript
    // yet — sending now would fork a duplicate session (see ChatController
    // .send), so the send control is disabled until the load lands.
    final bool isLoading = ref.watch(
      chatControllerProvider.select((s) => s.isLoading),
    );
    final List<ChatAttachment> pending = ref.watch(pendingAttachmentsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // v1.44.0: live dictation preview — the partial transcript while
          // the mic is open, so the user sees the phone is listening.
          if (_listening)
            Padding(
              key: const Key('speech-listening-row'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 16,
                    color: context.zMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _speechPartial.isEmpty
                          ? stringsOf(context).speechListening
                          : _speechPartial,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.zMuted),
                    ),
                  ),
                ],
              ),
            ),
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
              IconButton(
                key: const Key('mic-button'),
                tooltip: _listening ? strings.speechStop : strings.speechListen,
                onPressed: _toggleMic,
                icon: Icon(
                  _listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                  color: _listening ? const Color(0xFFE5484D) : context.zMuted,
                ),
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
                  gradient: isRunning || isLoading ? null : kBrandGradient,
                  // v1.30.0: the Stop button is clearly red — it must read
                  // as an interrupt control, not a disabled send button.
                  color: isRunning
                      ? const Color(0xFFE5484D)
                      : (isLoading ? context.zSurfaceAlt : null),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  key: Key(isRunning ? 'stop-button' : 'send-button'),
                  onPressed: isLoading
                      ? null
                      : (isRunning ? _handleStopPressed : _submit),
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isRunning
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
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

  /// v1.44.0 — mic control: first tap probes availability (lazy init +
  /// runtime RECORD_AUDIO prompt), starts dictation in the app language,
  /// and the next tap stops it. Final recognition results are appended to
  /// the composer text (per-chat draft, so they survive a chat switch);
  /// partials only feed the inline preview row.
  Future<void> _toggleMic() async {
    final AppStrings strings = stringsOf(context);
    if (_listening) {
      await ref.read(speechServiceProvider).stop();
      return;
    }
    final SpeechService speech = ref.read(speechServiceProvider);
    final SpeechAvailability availability = await speech.ensureReady();
    if (!mounted) return;
    if (availability == SpeechAvailability.unavailable) {
      _snack(strings.speechUnavailable);
      return;
    }
    if (availability == SpeechAvailability.notAuthorized) {
      _snack(strings.speechPermissionDenied);
      return;
    }
    setState(() {
      _listening = true;
      _speechPartial = '';
    });
    await speech.start(
      localeCode: ref.read(settingsProvider).languageCode,
      onResult: (String text, bool finalResult) {
        if (!mounted) return;
        if (!finalResult) {
          setState(() => _speechPartial = text);
          return;
        }
        final String trimmed = text.trim();
        if (trimmed.isNotEmpty) {
          final String current = _controller.text;
          final String merged = current.isEmpty
              ? trimmed
              : '$current ${trimmed.trimLeft()}';
          _controller.value = TextEditingValue(
            text: merged,
            selection: TextSelection.collapsed(offset: merged.length),
          );
        }
        setState(() => _speechPartial = '');
      },
      onEnd: () {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _speechPartial = '';
        });
      },
    );
  }

  /// Localized snackbar for the image-attachment failure kinds.
  void _showAttachmentError(AttachmentResult result) {
    final AppStrings strings = stringsOf(context);
    switch (result.errorType) {
      case AttachmentErrorType.tooLarge:
        _snack(strings.imageTooLarge);
      case AttachmentErrorType.notAnImage:
        _snack(strings.imageNotAnImage);
      case AttachmentErrorType.cancelled:
        break;
      case AttachmentErrorType.saveFailed:
      case null:
        _snack(strings.operationFailed);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// v1.42.0 — 1 tap stops the process (graceful); the 2nd tap asks again
  /// and hints; after the 3rd tap the force-stop offer is shown. Every tap
  /// (re)arms the cooperative stop, so the loop keeps exiting as early as
  /// it can while the user escalates.
  void _handleStopPressed() {
    _stopTaps++;
    ref.read(chatControllerProvider.notifier).stop();
    if (_stopTaps >= 3) {
      _stopTaps = 0;
      _showForceStopDialog();
    } else if (_stopTaps == 2) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('stop-hint-snack'),
            content: Text(stringsOf(context).stopHintForce),
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  /// Third-tap offer: force-stops ONLY after an explicit confirmation —
  /// a mis-tap must never kill a healthy run.
  Future<void> _showForceStopDialog() async {
    final AppStrings strings = stringsOf(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('force-stop-dialog'),
        title: Text(strings.forceStopTitle),
        content: Text(strings.forceStopBody),
        actions: <Widget>[
          TextButton(
            key: const Key('force-stop-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.forceStopCancel),
          ),
          FilledButton(
            key: const Key('force-stop-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.forceStopConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(chatControllerProvider.notifier).forceStop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('force-stop-done-snack'),
          content: Text(stringsOf(context).forceStopDone),
          duration: const Duration(seconds: 3),
        ),
      );
  }
}
