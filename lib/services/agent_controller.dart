import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../tools/tool_defs.dart';
import 'background_service.dart';
import 'llm_client.dart';

/// Wire-only user message appended when the model tries to finish while
/// its todo plan still has incomplete items (run-until-done + plan-first).
/// Never persisted as a visible chat message — the next assistant turn
/// simply continues working, like z.ai agent mode.
String planNudgeText(List<TodoItem> todos) {
  final StringBuffer buffer = StringBuffer(
    'Your task plan is not finished yet, so the task is not done. '
    'Incomplete todos:\n',
  );
  for (final TodoItem todo in todos) {
    if (todo.status == TodoStatus.completed) continue;
    final String status = todo.status == TodoStatus.inProgress
        ? 'in_progress'
        : 'pending';
    buffer.writeln('- [$status] ${todo.content}');
  }
  buffer
    ..writeln()
    ..write(
      'Continue working now: use your tools to complete the next todo, '
      'call todo_write to update the plan, and only write the final '
      'summary when every todo is completed.',
    );
  return buffer.toString();
}

/// Immutable UI state of the currently ACTIVE chat session.
class ChatState {
  const ChatState({
    this.sessionId,
    this.title = '',
    this.messages = const <ChatMessage>[],
    this.isRunning = false,
    this.error,
    this.todos = const <TodoItem>[],
  });

  final String? sessionId;
  final String title;
  final List<ChatMessage> messages;
  final bool isRunning;
  final String? error;

  /// Latest plan written via `todo_write` in the running session — drives
  /// the show/hide plan panel next to the thinking indicator.
  final List<TodoItem> todos;

  static const Object _unset = Object();

  ChatState copyWith({
    String? sessionId,
    String? title,
    List<ChatMessage>? messages,
    bool? isRunning,
    Object? error = _unset,
    List<TodoItem>? todos,
  }) => ChatState(
    sessionId: sessionId ?? this.sessionId,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    isRunning: isRunning ?? this.isRunning,
    error: error == _unset ? this.error : error as String?,
    todos: todos ?? this.todos,
  );
}

/// Internal state of one running (or recently run) session. Sessions run
/// in parallel: each keeps its own message list so switching to another
/// chat never interrupts the loop.
class _SessionRun {
  _SessionRun({required this.sessionId, required this.title});

  final String sessionId;
  String title;
  final List<ChatMessage> messages = <ChatMessage>[];
  bool isRunning = true;
  bool stopRequested = false;

  /// Set when the user deletes the session mid-run: the final persist is
  /// skipped so the conversation cannot resurrect itself.
  bool deleted = false;

  /// base64 payloads cached per attachment path (avoid re-encoding images
  /// on every wire rebuild).
  final Map<String, String> dataUrlCache = <String, String>{};

  /// Text contents of text-like attachments, read once per run.
  final Map<String, String> textCache = <String, String>{};

  /// Latest plan written via `todo_write` in THIS run. Mirrored into the
  /// [ChatState] on every sync so the UI can show live plan progress.
  List<TodoItem> latestTodos = const <TodoItem>[];

  /// Absolute path of the app documents directory, resolved once per run so
  /// binary attachment notes can advertise the documents-relative path the
  /// file tools expect (e.g. `uploads/1_project.zip`).
  String? docsPath;
}

/// Drives multi-session agent loops: user prompt -> LLM (streaming) ->
/// tool calls -> tool results -> ... -> final answer, per session, in
/// parallel. Also handles persistence, history and renaming.
class ChatController extends Notifier<ChatState> {
  final Map<String, _SessionRun> _runs = <String, _SessionRun>{};

  /// The session currently rendered by the UI (null = fresh draft).
  String? _activeSessionId;

  @override
  ChatState build() => const ChatState();

  /// Sessions whose agent loop is still active. Finished runs stay in
  /// [_runs] (their messages are still on screen) but must not keep the
  /// drawer's "running" badge spinning forever.
  Set<String> get runningIds => <String>{
    for (final _SessionRun run in _runs.values)
      if (run.isRunning) run.sessionId,
  };

  void _markRunning() {
    ref.read(runningSessionsProvider.notifier).state = runningIds;
  }

  /// Stops the ACTIVE session's loop (other sessions keep running).
  void stop() {
    final String? id = _activeSessionId;
    if (id != null) _runs[id]?.stopRequested = true;
  }

  Future<void> send(
    String text, {
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || state.isRunning) return;
    _SessionRun? run = _activeSessionId != null
        ? _runs[_activeSessionId!]
        : null;
    if (run != null && run.isRunning) return; // active session busy

    final settings = ref.read(settingsProvider);
    final AppStrings strings = appStringsFor(settings.languageCode);
    if (settings.apiKey.trim().isEmpty) {
      state = state.copyWith(error: strings.missingApiKey);
      return;
    }
    if (settings.model.trim().isEmpty) {
      state = state.copyWith(error: strings.modelNotSet);
      return;
    }

    // Continue the active session, or create a new one. An OPEN but not
    // currently-running session (opened from history, or one whose run has
    // finished) must be CONTINUED — sending a message must never silently
    // fork a brand-new chat. A fresh chat is only created when there is no
    // open conversation at all (i.e. the user tapped "New chat" / fresh app
    // start with no history).
    if (run == null) {
      final String? openId = _activeSessionId;
      if (openId != null) {
        run = await _adoptSession(openId, trimmed);
        // The user may have switched away while the history was loading.
        if (_activeSessionId != openId) return;
        _runs[openId] = run;
        _activeSessionId = openId;
        state = ChatState(
          sessionId: openId,
          title: run.title,
          messages: [...run.messages],
          isRunning: true,
        );
      } else {
        final String sessionId = newId();
        run = _SessionRun(sessionId: sessionId, title: _titleFor(trimmed));
        _runs[sessionId] = run;
        _activeSessionId = sessionId;
        state = ChatState(
          sessionId: sessionId,
          title: run.title,
          messages: run.messages,
          isRunning: true,
        );
      }
    } else {
      state = state.copyWith(isRunning: true, error: null);
    }
    _markRunning();

    // Preload attachment contents (text bodies + image data URLs) and the
    // documents root (for relative path hints on binary attachments).
    run.docsPath ??= (await ref.read(documentsDirProvider)()).path;
    await _prepareAttachments(run, attachments);

    final _RunResult result = await _runLoop(
      run,
      settings,
      trimmed,
      attachments,
    );

    run.isRunning = false;
    _markRunning();
    if (!run.deleted) {
      if (_activeSessionId == run.sessionId) {
        state = state.copyWith(
          messages: [...run.messages],
          isRunning: false,
          error: result.error,
        );
      }
      await _persist(run);
    }
    _runs.remove(run.sessionId);
    _markRunning();
  }

  static String _titleFor(String text) =>
      text.length > 48 ? '${text.substring(0, 48)}…' : text;

  /// Loads an existing (persisted) session into a runnable state so the
  /// next message CONTINUES it instead of forking a new chat. Falls back
  /// to an empty transcript when the stored file is unreadable — the
  /// conversation keeps its id and title either way.
  Future<_SessionRun> _adoptSession(String sessionId, String prompt) async {
    final _SessionRun run = _SessionRun(
      sessionId: sessionId,
      title: state.title.isNotEmpty ? state.title : _titleFor(prompt),
    );
    try {
      final List<ChatMessage>? history = await ref
          .read(chatStoreProvider)
          .load(sessionId);
      if (history != null && history.isNotEmpty) {
        run.messages.addAll(history);
        // Re-read attachment payloads so replayed attachments reach the
        // model again (images need their data URLs, text files their
        // bodies). Missing files are skipped by [_prepareAttachments].
        final List<ChatAttachment> atts = <ChatAttachment>[
          for (final ChatMessage m in history) ...m.attachments,
        ];
        await _prepareAttachments(run, atts);
      }
    } catch (_) {
      // Storage failure: continue with whatever is on screen (possibly
      // empty) rather than blocking the user's message.
    }
    return run;
  }

  /// Reads picked files into the run's caches so wire building never
  /// touches the filesystem again. Failures degrade to a note in text.
  Future<void> _prepareAttachments(
    _SessionRun run,
    List<ChatAttachment> attachments,
  ) async {
    for (final ChatAttachment att in attachments) {
      if (att.path.isEmpty ||
          run.dataUrlCache.containsKey(att.path) ||
          run.textCache.containsKey(att.path)) {
        continue;
      }
      try {
        final File file = File(att.path);
        if (!await file.exists()) continue;
        switch (att.kind) {
          case AttachmentKind.image:
            final List<int> bytes = await file.readAsBytes();
            final String mime = _mimeForName(att.name);
            run.dataUrlCache[att.path] =
                'data:$mime;base64,${base64Encode(bytes)}';
          case AttachmentKind.text:
            final String content = await file.readAsString();
            run.textCache[att.path] = content.length > 20000
                ? '${content.substring(0, 20000)}\n…[truncated]'
                : content;
          case AttachmentKind.other:
            // Binary: only the metadata travels in the prompt.
            break;
        }
      } catch (_) {
        // Unreadable attachment: skip silently, message text still sends.
      }
    }
  }

  static String _mimeForName(String name) {
    final String ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'bmp' => 'image/bmp',
      _ => 'application/octet-stream',
    };
  }

  /// Composes the effective user text: prompt + text-attachment blocks.
  String _composeUserText(
    String prompt,
    List<ChatAttachment> attachments,
    _SessionRun run,
  ) {
    final StringBuffer buffer = StringBuffer(prompt);
    for (final ChatAttachment att in attachments) {
      switch (att.kind) {
        case AttachmentKind.text:
          final String? content = run.textCache[att.path];
          if (content != null) {
            buffer
              ..writeln()
              ..writeln()
              ..writeln('[Attached file: ${att.name}]');
            buffer
              ..writeln('```')
              ..writeln(content)
              ..write('```');
          }
        case AttachmentKind.image:
          // Images travel as separate content parts, not inline text.
          break;
        case AttachmentKind.other:
          // Binary: metadata + the documents-relative path so the agent can
          // act on the file (unzip_file, node_run, zip_file ...).
          final String relative = _relativeToDocs(att.path, run);
          final bool isZip = att.name.toLowerCase().endsWith('.zip');
          buffer
            ..writeln()
            ..writeln(
              '[Attached file: ${att.name} (${att.sizeBytes} bytes, binary — '
              'no preview available)]',
            );
          if (relative.isNotEmpty) {
            buffer.writeln(
              isZip
                  ? 'The archive is saved at "$relative". Use unzip_file '
                        'with this path to extract it, then read_file or '
                        'node_run (require relative paths like '
                        '"./$relative/...") to work with the files inside.'
                  : 'The file is saved at "$relative". It can be processed '
                        'with node_run or re-archived with zip_file.',
            );
          }
      }
    }
    return buffer.toString();
  }

  /// Documents-relative form of [absolutePath] (forward slashes), or ''
  /// when the path is unknown/outside the documents root.
  String _relativeToDocs(String absolutePath, _SessionRun run) {
    final String? docsPath = run.docsPath;
    if (docsPath == null || docsPath.isEmpty) return '';
    String normalized = absolutePath.replaceAll('\\', '/');
    String root = docsPath.replaceAll('\\', '/');
    if (!root.endsWith('/')) root = '$root/';
    if (!normalized.startsWith(root)) return '';
    return normalized.substring(root.length);
  }

  Future<_RunResult> _runLoop(
    _SessionRun run,
    AppSettings settings,
    String prompt,
    List<ChatAttachment> attachments,
  ) async {
    final AppStrings strings = appStringsFor(settings.languageCode);
    run.messages.add(ChatMessage.user(prompt, attachments: attachments));
    _sync(run);

    final wire = <Map<String, dynamic>>[
      _systemWire(settings),
      // Full replay: previous turns (assistant + tool results + user msgs,
      // attachments included) followed by the freshly added user message.
      ..._buildWire(run, run.messages),
    ];

    final config = LlmConfig(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
    );
    final tools = settings.agentMode
        ? buildAgentTools(planFirst: settings.planFirst)
        : null;

    final BackgroundRun background = ref.read(backgroundRunServiceProvider);
    final bool holdStarted = settings.runInBackground;
    if (holdStarted) {
      await background.start(
        title: strings.notifTitle,
        text: strings.notifProcessing,
      );
    }

    try {
      // "Run until done" removes the max-steps cap: the loop only ends
      // when the model stops requesting tools or the user presses Stop.
      // [unboundedStepLimit] remains as a runaway guard.
      final int stepLimit = settings.runUntilDone
          ? unboundedStepLimit
          : settings.maxSteps;

      // Latest plan state written via todo_write in THIS run (tracked on
      // the run itself so the UI can mirror it). A plan from an earlier
      // turn stays in the replayed history; a new user command is expected
      // to re-plan, so the nudge only tracks the current run.
      int planNudges = 0;

      for (var step = 0; step < stepLimit; step++) {
        // Stop pressed before this turn even starts — leave immediately.
        if (run.stopRequested) break;

        // 1. Stream one assistant turn.
        run.messages.add(ChatMessage.assistant('', isStreaming: true));
        _sync(run);

        final buffer = StringBuffer();
        final AssistantTurn turn;
        try {
          turn = await ref
              .read(llmClientProvider)
              .complete(
                config: config,
                messages: wire,
                tools: tools,
                onDelta: (delta) {
                  buffer.write(delta);
                  run.messages[run.messages.length - 1] = ChatMessage.assistant(
                    buffer.toString(),
                    isStreaming: true,
                  );
                  _sync(run);
                },
                // Stop must interrupt DURING the stream, not after it.
                shouldAbort: () => run.stopRequested,
              );
        } on LlmAbortedException {
          // Keep the partial answer on screen; the finalize step below
          // marks it as stopped. No wire entry is added, so the next
          // message continues from a clean history.
          break;
        }
        if (run.stopRequested) break;

        final toolCalls = <ToolCall>[
          for (final tc in turn.toolCalls)
            ToolCall(id: tc.id, name: tc.name, arguments: tc.args),
        ];
        run.messages[run.messages.length - 1] = ChatMessage.assistant(
          turn.content,
          toolCalls: toolCalls,
        );
        _sync(run);

        if (toolCalls.isEmpty) {
          // The model produced a final answer. With "run until done" +
          // plan-first, an incomplete todo plan means the task is NOT
          // done: nudge the model to keep working (z.ai agent mode
          // behavior) instead of accepting a premature summary.
          if (settings.runUntilDone &&
              settings.planFirst &&
              settings.agentMode &&
              !run.stopRequested &&
              hasIncompleteTodos(run.latestTodos) &&
              planNudges < maxPlanNudges) {
            planNudges++;
            wire.add(<String, dynamic>{
              'role': 'user',
              'content': planNudgeText(run.latestTodos),
            });
            continue;
          }
          break; // Final answer reached.
        }

        // 2. Execute each requested tool and feed results back.
        wire.add(<String, dynamic>{
          'role': 'assistant',
          if (turn.content.isNotEmpty) 'content': turn.content,
          'tool_calls': <Map<String, dynamic>>[
            for (final tc in turn.toolCalls)
              <String, dynamic>{
                'id': tc.id,
                'type': 'function',
                'function': <String, dynamic>{
                  'name': tc.name,
                  'arguments': tc.argumentsJson,
                },
              },
          ],
        });

        final executor = ref.read(toolExecutorProvider);
        for (final call in toolCalls) {
          if (run.stopRequested) break;
          call.status = ToolStatus.running;
          _sync(run);
          // Live progress in the foreground-service notification.
          await background.updateStatus(strings.notifStep(step + 1, call.name));

          final result = await executor.execute(
            call.name,
            call.arguments,
            sessionId: run.sessionId,
          );
          call.status = result.ok ? ToolStatus.success : ToolStatus.error;
          call.resultText = result.llmOutput;
          call.screenshotPath = result.screenshotPath;
          if (call.name == 'todo_write') {
            run.latestTodos = parseTodoList(call.arguments['todos']);
          }
          _sync(run);

          wire.add(<String, dynamic>{
            'role': 'tool',
            'tool_call_id': call.id,
            'content': result.llmOutput,
          });
        }
        if (run.stopRequested) break;
      }

      if (run.stopRequested && run.messages.isNotEmpty) {
        final ChatMessage last = run.messages.last;
        if (last.role == Role.assistant && last.isStreaming) {
          final String marker = appStringsFor(settings.languageCode)
              .stoppedMarkdown;
          run.messages[run.messages.length - 1] = ChatMessage.assistant(
            last.content.trim().isEmpty ? marker : '${last.content}\n\n$marker',
          );
          _sync(run);
        }
      } else if (!run.stopRequested &&
          run.messages.isNotEmpty &&
          run.messages.last.role == Role.assistant &&
          run.messages.last.toolCalls.isNotEmpty) {
        // The step cap was exhausted while the model still wanted to call
        // tools — explain the pause instead of stopping silently.
        run.messages.add(
          ChatMessage.assistant(
            strings.maxStepsReachedMarkdown(
              settings.runUntilDone ? unboundedStepLimit : settings.maxSteps,
            ),
          ),
        );
        _sync(run);
      }
      return const _RunResult();
    } catch (e) {
      return _RunResult(error: e.toString());
    } finally {
      // Always release the background hold — success, error, or stop.
      // Refcounted: parallel sessions keep the service alive until all end.
      if (holdStarted) await background.stop();
    }
  }

  /// System message: agent prompt (agent mode) + plan-first addendum +
  /// enabled Context Manager entries merged into ONE system message (some
  /// providers reject several).
  Map<String, dynamic> _systemWire(AppSettings settings) {
    final StringBuffer content = StringBuffer();
    if (settings.agentMode) {
      content.write(agentSystemPrompt);
      if (settings.planFirst) content.write(planFirstSystemPrompt);
    }
    try {
      final List<ContextEntry> entries = ref
          .read(contextRepositoryProvider)
          .load()
          .where((ContextEntry e) => e.enabled && e.content.trim().isNotEmpty)
          .toList();
      for (final ContextEntry entry in entries) {
        if (content.isNotEmpty) content.writeln();
        content
          ..writeln()
          ..writeln('# Context: ${entry.name}')
          ..write(entry.content.trim());
      }
    } catch (_) {
      // Context store failure must never block a chat request.
    }
    return <String, dynamic>{'role': 'system', 'content': content.toString()};
  }

  /// User message in wire format; with image attachments the content
  /// becomes an OpenAI multimodal parts array.
  Map<String, dynamic> _userWireMessage(_SessionRun run, ChatMessage message) {
    final String text = _composeUserText(
      message.content,
      message.attachments,
      run,
    );
    final List<String> dataUrls = <String>[
      for (final ChatAttachment att in message.attachments)
        if (att.kind == AttachmentKind.image &&
            run.dataUrlCache[att.path] != null)
          run.dataUrlCache[att.path]!,
    ];
    if (dataUrls.isEmpty) {
      return <String, dynamic>{'role': 'user', 'content': text};
    }
    return <String, dynamic>{
      'role': 'user',
      'content': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': text},
        for (final String url in dataUrls)
          <String, dynamic>{
            'type': 'image_url',
            'image_url': <String, dynamic>{'url': url},
          },
      ],
    };
  }

  /// Rebuilds the LLM wire for a CONTINUING session (history replay).
  List<Map<String, dynamic>> _buildWire(
    _SessionRun run,
    List<ChatMessage> messages,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final message in messages) {
      switch (message.role) {
        case Role.user:
          out.add(_userWireMessage(run, message));
        case Role.assistant:
          if (message.isStreaming) continue;
          if (message.toolCalls.isNotEmpty) {
            out.add(<String, dynamic>{
              'role': 'assistant',
              if (message.content.isNotEmpty) 'content': message.content,
              'tool_calls': <Map<String, dynamic>>[
                for (final call in message.toolCalls)
                  <String, dynamic>{
                    'id': call.id,
                    'type': 'function',
                    'function': <String, dynamic>{
                      'name': call.name,
                      'arguments': jsonEncode(call.arguments),
                    },
                  },
              ],
            });
            for (final call in message.toolCalls) {
              out.add(<String, dynamic>{
                'role': 'tool',
                'tool_call_id': call.id,
                'content': call.resultText ?? '(no result)',
              });
            }
          } else if (message.content.isNotEmpty) {
            out.add(<String, dynamic>{
              'role': 'assistant',
              'content': message.content,
            });
          }
        default:
          break;
      }
    }
    return out;
  }

  /// Writes the run's view into the UI state — but only when the run's
  /// session is the one currently displayed (parallel sessions otherwise
  /// clobber each other's screen).
  void _sync(_SessionRun run) {
    if (_activeSessionId != run.sessionId) return;
    state = state.copyWith(
      messages: [...run.messages],
      title: run.title,
      sessionId: run.sessionId,
      todos: run.latestTodos,
    );
  }

  Future<void> _persist(_SessionRun run) async {
    final persisted = run.messages
        .where((m) => !(m.isStreaming && m.content.isEmpty))
        .toList();
    try {
      await ref
          .read(chatStoreProvider)
          .save(id: run.sessionId, title: run.title, messages: persisted);
      ref.invalidate(chatListProvider);
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  /// Starts a fresh draft. Any in-flight session keeps running in the
  /// background and can be reopened from history.
  Future<void> newChat() async {
    _activeSessionId = null;
    state = const ChatState();
  }

  /// App-start behavior (chat.z.ai style): reopen the most recent
  /// conversation so the first message CONTINUES it. A brand-new chat is
  /// only started after the user explicitly taps "New chat" in the drawer.
  /// Never yanks the screen away when the user is already interacting.
  Future<void> restoreLastChat() async {
    if (_activeSessionId != null ||
        state.messages.isNotEmpty ||
        state.isRunning) {
      return;
    }
    try {
      final List<ChatSummary> items = await ref.read(chatListProvider.future);
      if (items.isEmpty) return;
      if (_activeSessionId != null ||
          state.messages.isNotEmpty ||
          state.isRunning) {
        return;
      }
      await openChat(items.first);
    } catch (_) {
      // History unavailable: stay on the fresh draft.
    }
  }

  Future<void> openChat(ChatSummary summary) async {
    _activeSessionId = summary.id;
    final _SessionRun? run = _runs[summary.id];
    if (run != null) {
      // Live session (still running or just finished): adopt its state.
      state = ChatState(
        sessionId: run.sessionId,
        title: run.title,
        messages: [...run.messages],
        // A stopping run is still running until its loop actually exits —
        // showing send here would silently swallow the next message.
        isRunning: run.isRunning,
      );
      return;
    }
    try {
      final messages = await ref.read(chatStoreProvider).load(summary.id);
      // The user may have switched again while loading — only commit when
      // this session is still the active one.
      if (_activeSessionId != summary.id) return;
      state = ChatState(
        sessionId: summary.id,
        title: summary.title,
        messages: messages ?? const <ChatMessage>[],
      );
    } catch (_) {
      // A corrupted history entry must never crash the app: open an empty
      // session and tell the user what happened.
      if (_activeSessionId != summary.id) return;
      state = ChatState(
        sessionId: summary.id,
        error: appStringsFor(ref.read(settingsProvider).languageCode)
            .chatOpenError,
      );
    }
  }

  Future<void> renameChat(String id, String title) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final _SessionRun? run = _runs[id];
    if (run != null) {
      run.title = _titleFor(trimmed);
      if (_activeSessionId == id) {
        state = state.copyWith(title: run.title);
      }
    }
    try {
      await ref.read(chatStoreProvider).rename(id, _titleFor(trimmed));
      ref.invalidate(chatListProvider);
    } catch (_) {
      state = state.copyWith(
        error: appStringsFor(ref.read(settingsProvider).languageCode)
            .chatRenameError,
      );
    }
  }

  Future<void> deleteChat(String id) async {
    // If this session is running, stop it and drop its results.
    _runs[id]?.stopRequested = true;
    _runs[id]?.deleted = true;
    try {
      await ref.read(chatStoreProvider).delete(id);
    } catch (_) {
      state = state.copyWith(
        error: appStringsFor(ref.read(settingsProvider).languageCode)
            .chatDeleteError,
      );
      return;
    }
    if (_activeSessionId == id) {
      _activeSessionId = null;
      state = const ChatState();
    }
    ref.invalidate(chatListProvider);
    _markRunning();
  }
}

class _RunResult {
  const _RunResult({this.error});
  final String? error;
}

/// Settings controller: holds AppSettings and persists on every update.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> update(AppSettings next) async {
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }
}
