import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../tools/tool_defs.dart';
import 'background_service.dart';
import 'image_downscale.dart';
import 'llm_client.dart';
import 'module_registry.dart';
import 'module_runtime.dart';

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
    this.pendingModule,
    this.activeModules = const <String>[],
  });

  final String? sessionId;
  final String title;
  final List<ChatMessage> messages;
  final bool isRunning;
  final String? error;

  /// Latest plan written via `todo_write` in the running session — drives
  /// the show/hide plan panel next to the thinking indicator.
  final List<TodoItem> todos;

  /// Module (plugins) selected on a FRESH DRAFT that activates with the
  /// first message. Null when no module is staged.
  final String? pendingModule;

  /// Modules currently active for the displayed session (per-chat
  /// private-window scope).
  final List<String> activeModules;

  static const Object _unset = Object();

  ChatState copyWith({
    String? sessionId,
    String? title,
    List<ChatMessage>? messages,
    bool? isRunning,
    Object? error = _unset,
    List<TodoItem>? todos,
    Object? pendingModule = _unset,
    List<String>? activeModules,
  }) => ChatState(
    sessionId: sessionId ?? this.sessionId,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    isRunning: isRunning ?? this.isRunning,
    error: error == _unset ? this.error : error as String?,
    todos: todos ?? this.todos,
    pendingModule: pendingModule == _unset
        ? this.pendingModule
        : pendingModule as String?,
    activeModules: activeModules ?? this.activeModules,
  );
}

/// Internal state of one running (or recently run) session. Sessions run
/// in parallel: each keeps its own message list so switching to another
/// chat never interrupts the loop.
class _SessionRun {
  _SessionRun({
    required this.sessionId,
    required this.title,
    bool running = true,
  }) : isRunning = running;

  final String sessionId;
  String title;
  final List<ChatMessage> messages = <ChatMessage>[];
  bool isRunning = true;
  bool stopRequested = false;

  /// True while the session title still came from the automatic
  /// `_titleFor(prompt)` path (fresh session or history fallback): the
  /// first successful answer then triggers the model-generated title.
  /// A user rename flips this off permanently.
  bool autoTitlePending = false;

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

  /// Chat modules (plugins) active for THIS session — a per-chat
  /// private-window scope: activating a module in another chat never
  /// affects this list, and each active module gets its own state
  /// directory under this session's sandbox.
  final List<String> activeModules = <String>[];

  /// Module staged on the draft; activates with the first message.
  String? pendingModule;

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

  /// Stops the ACTIVE session's loop (other sessions keep running) and
  /// safely terminates any chat-module execution belonging to it.
  void stop() {
    final String? id = _activeSessionId;
    if (id != null) {
      _runs[id]?.stopRequested = true;
      try {
        ref.read(moduleRuntimeProvider).terminateSession(id);
      } catch (_) {
        // Runtime unavailable: the stop itself still proceeds.
      }
    }
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

    // Module staged on the draft (module chip on the empty state) —
    // captured BEFORE the session-state reset below can drop it.
    final String? stagedModule = state.pendingModule;

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
        run.autoTitlePending = true;
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

    // A module staged on the draft activates with the FIRST message of the
    // session — inside _executeRun, right after the user message lands, so
    // the transcript reads: user → module output → agent reply.
    run.pendingModule ??= stagedModule;
    state = state.copyWith(pendingModule: null);

    await _executeRun(run, settings, prompt: trimmed, attachments: attachments);
  }

  /// Clears the module staged on a fresh draft (chip unselected).
  void stageNoModule() {
    if (state.pendingModule == null) return;
    state = state.copyWith(pendingModule: null);
  }

  /// Activates a chat module for the CURRENT context:
  /// * fresh draft → the module is staged (pendingModule) and activates
  ///   with the first message;
  /// * open session → the module activates immediately: it joins the
  ///   session's private-window scope and its entry point runs with the
  ///   output posted as a module message.
  ///
  /// The UI shows the permission dialog BEFORE calling this; the granted
  /// set is therefore the module's declared manifest permissions.
  Future<void> activateModule(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final String? sessionId = _activeSessionId;
    if (sessionId == null) {
      // Draft: stage for the first message.
      if (state.pendingModule == trimmed) return;
      state = state.copyWith(pendingModule: trimmed);
      return;
    }
    _SessionRun? run = _runs[sessionId];
    if (run == null) {
      run = await _materializeSession(sessionId);
      if (run == null) return;
      _runs[sessionId] = run;
    }
    if (run.isRunning || (_activeSessionId == sessionId && state.isRunning)) {
      state = state.copyWith(
        error: appStringsFor(ref.read(settingsProvider).languageCode)
            .moduleSessionBusy,
      );
      return;
    }
    if (run.activeModules.contains(trimmed)) return;
    await _activateModule(run, trimmed);
  }

  /// Deactivates a chat module for the ACTIVE session: removes it from the
  /// per-chat scope, safely terminates a live execution and records the
  /// change as a module message. Returns false when nothing was active.
  Future<bool> deactivateModule(String name) async {
    final String trimmed = name.trim();
    final String? sessionId = _activeSessionId;
    if (sessionId == null || trimmed.isEmpty) return false;
    _SessionRun? run = _runs[sessionId];
    if (run == null) {
      run = await _materializeSession(sessionId);
      if (run == null) return false;
      _runs[sessionId] = run;
    }
    if (!run.activeModules.contains(trimmed)) return false;
    run.activeModules.remove(trimmed);
    // Safe termination: cancel any live execution; persisted per-chat
    // state (storage.json, state/) is intentionally kept for the day the
    // module is re-activated in this chat.
    try {
      ref.read(moduleRuntimeProvider).terminate(sessionId, trimmed);
    } catch (_) {
      // Runtime unavailable: the deactivation itself still proceeds.
    }
    final AppStrings strings = appStringsFor(
      ref.read(settingsProvider).languageCode,
    );
    run.messages.add(
      ChatMessage.assistant(
        strings.moduleDeactivated(trimmed),
        moduleName: trimmed,
      ),
    );
    _sync(run);
    if (_activeSessionId == sessionId) {
      state = state.copyWith(activeModules: [...run.activeModules]);
    }
    await _persist(run);
    return true;
  }

  /// Activates [name] on a materialized run: executes the entry point in
  /// the session's isolated sandbox and posts the output as a module
  /// message. Failures degrade into the message body — they never break
  /// the chat.
  Future<void> _activateModule(_SessionRun run, String name) async {
    final AppStrings strings = appStringsFor(
      ref.read(settingsProvider).languageCode,
    );
    final ChatModule? module = await ref.read(moduleRegistryProvider).get(name);
    if (module == null) {
      if (_activeSessionId == run.sessionId) {
        state = state.copyWith(error: strings.moduleNotFound(name));
      }
      return;
    }
    run.activeModules.add(name);
    run.pendingModule = null;
    final ChatMessage moduleMessage = ChatMessage.assistant(
      '',
      moduleName: name,
    );
    run.messages.add(moduleMessage);
    _sync(run);
    if (_activeSessionId == run.sessionId) {
      state = state.copyWith(activeModules: [...run.activeModules]);
    }

    final StringBuffer body = StringBuffer();
    void refresh() {
      final int index = run.messages.indexOf(moduleMessage);
      if (index == -1) return;
      run.messages[index] = ChatMessage.assistant(
        body.toString(),
        moduleName: name,
      );
      _sync(run);
    }

    try {
      final ModuleRunResult result = await ref
          .read(moduleRuntimeProvider)
          .run(
            sessionId: run.sessionId,
            module: module,
            granted: module.manifest.permissions,
            onChatEmit: (String text) {
              body.writeln(text);
              refresh();
            },
          );
      if (result.output.trim().isNotEmpty) {
        if (body.isNotEmpty) body.writeln();
        body.write(result.output);
      }
      if (!result.ok) {
        if (body.isNotEmpty) {
          body
            ..writeln()
            ..writeln();
        }
        body.write(
          result.terminated
              ? strings.moduleTerminated
              : strings.moduleRunFailed(result.error ?? ''),
        );
      }
    } catch (e) {
      if (body.isNotEmpty) {
        body
          ..writeln()
          ..writeln();
      }
      body.write(strings.moduleRunFailed('$e'));
    }
    refresh();
    await _persist(run);
  }

  /// Rewrites a previously sent user message and REGENERATES everything
  /// after it: the message content is replaced (attachments kept) and
  /// every later message is dropped, then the agent loop replays the
  /// truncated history. Works on live sessions and on sessions freshly
  /// opened from history. Returns false when the request is invalid
  /// (unknown session, still running, no user message at that index).
  Future<bool> editUserMessage(
    String sessionId,
    int messageIndex,
    String newText,
  ) async {
    final String trimmed = newText.trim();
    if (trimmed.isEmpty) return false;
    _SessionRun? run = _runs[sessionId];
    if (run == null) {
      if (_activeSessionId != sessionId) return false;
      run = await _materializeSession(sessionId);
      if (run == null) return false;
      _runs[sessionId] = run;
    }
    if (run.isRunning || (_activeSessionId == sessionId && state.isRunning)) {
      return false;
    }
    if (messageIndex < 0 || messageIndex >= run.messages.length) {
      return false;
    }
    final ChatMessage target = run.messages[messageIndex];
    if (target.role != Role.user) return false;
    if (!_passesConnectionChecks()) return false;

    // Replace the content, keep the attachments, drop everything after.
    run.messages[messageIndex] = ChatMessage(
      id: target.id,
      role: Role.user,
      content: trimmed,
      createdAt: target.createdAt,
      attachments: target.attachments,
    );
    if (messageIndex < run.messages.length - 1) {
      run.messages.removeRange(messageIndex + 1, run.messages.length);
    }
    run.latestTodos = const <TodoItem>[];
    _showRunningTranscript(run);
    await _executeRun(run, ref.read(settingsProvider));
    return true;
  }

  /// Regenerates the answer to the LAST user message: trailing assistant
  /// messages are dropped (the user message is kept) and the agent loop
  /// replays the history from there. Returns false when the request is
  /// invalid (unknown session, still running, no user message).
  Future<bool> regenerate(String sessionId) async {
    _SessionRun? run = _runs[sessionId];
    if (run == null) {
      if (_activeSessionId != sessionId) return false;
      run = await _materializeSession(sessionId);
      if (run == null) return false;
      _runs[sessionId] = run;
    }
    if (run.isRunning || (_activeSessionId == sessionId && state.isRunning)) {
      return false;
    }
    int lastUser = -1;
    for (var i = run.messages.length - 1; i >= 0; i--) {
      if (run.messages[i].role == Role.user) {
        lastUser = i;
        break;
      }
    }
    if (lastUser < 0) return false;
    if (!_passesConnectionChecks()) return false;

    if (lastUser < run.messages.length - 1) {
      run.messages.removeRange(lastUser + 1, run.messages.length);
    }
    run.latestTodos = const <TodoItem>[];
    _showRunningTranscript(run);
    await _executeRun(run, ref.read(settingsProvider));
    return true;
  }

  /// API key/model validation shared by send/edit/regenerate. Surfaces a
  /// localized error on the chat state when something is missing.
  bool _passesConnectionChecks() {
    final settings = ref.read(settingsProvider);
    final AppStrings strings = appStringsFor(settings.languageCode);
    if (settings.apiKey.trim().isEmpty) {
      state = state.copyWith(error: strings.missingApiKey);
      return false;
    }
    if (settings.model.trim().isEmpty) {
      state = state.copyWith(error: strings.modelNotSet);
      return false;
    }
    return true;
  }

  /// Puts an (edited) transcript on screen and flips the session into the
  /// running state — the same visual contract a normal send has.
  void _showRunningTranscript(_SessionRun run) {
    if (_activeSessionId != run.sessionId) return;
    state = state.copyWith(
      sessionId: run.sessionId,
      title: run.title,
      messages: [...run.messages],
      isRunning: true,
      error: null,
    );
  }

  /// Shared run scaffolding for send / edit / regenerate: background hold,
  /// the agent loop itself, final state + persistence, auto-title.
  /// [prompt] null = replay-only (edit/regenerate); a non-null prompt is
  /// appended as a new user message first.
  Future<void> _executeRun(
    _SessionRun run,
    AppSettings settings, {
    String? prompt,
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) async {
    run.isRunning = true;
    _markRunning();

    // Preload attachment contents (text bodies + image data URLs) and the
    // documents root (for relative path hints on binary attachments).
    run.docsPath ??= (await ref.read(documentsDirProvider)()).path;
    await _prepareAttachments(run, attachments);

    final _RunResult result = await _runLoop(
      run,
      settings,
      prompt,
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
      if (result.error == null && !run.stopRequested) {
        await _maybeAutoTitle(run, settings);
      }
      await _maybeNotifyDone(run, settings, result.error);
    }
    _runs.remove(run.sessionId);
    _markRunning();
  }

  /// Posts a local "task finished" notification when a run completes while
  /// the app is in the background (v1.18.0). Skipped when the user turned
  /// notifications off, when the app is on screen, or when the user/Stop
  /// ended the run — those already have their own feedback.
  Future<void> _maybeNotifyDone(
    _SessionRun run,
    AppSettings settings,
    String? error,
  ) async {
    try {
      if (!settings.notifyOnDone || run.stopRequested) return;
      if (ref.read(appInForegroundProvider)) return;
      final AppStrings strings = appStringsFor(settings.languageCode);
      await ref
          .read(backgroundRunServiceProvider)
          .notifyDone(
            title: strings.notifDoneTitle,
            text: strings.notifDoneBody(run.title, error),
            sessionId: run.deleted ? null : run.sessionId,
          );
    } catch (_) {
      // A failed notification must never disturb the finished run.
    }
  }

  static String _titleFor(String text) =>
      text.length > 48 ? '${text.substring(0, 48)}…' : text;

  /// Loads an existing (persisted) session into a runnable state so the
  /// next message CONTINUES it instead of forking a new chat. Falls back
  /// to an empty transcript when the stored file is unreadable — the
  /// conversation keeps its id and title either way.
  Future<_SessionRun> _adoptSession(String sessionId, String prompt) async {
    final _SessionRun run =
        await _materializeSession(sessionId) ??
        _SessionRun(sessionId: sessionId, title: '');
    // When the screen had no title the run was titled from the prompt —
    // exactly the automatic-title path, so the model may rename it later.
    if (state.title.isEmpty) {
      run.title = _titleFor(prompt);
      run.autoTitlePending = true;
    }
    return run;
  }

  /// Builds a [_SessionRun] from the STORED history of [sessionId] so
  /// edit/regenerate work on freshly opened sessions too (and _adoptSession
  /// can share the logic). Returns null when the run could not be built —
  /// storage failures degrade to an empty transcript, never an exception.
  Future<_SessionRun?> _materializeSession(String sessionId) async {
    // Materialized history is NOT running — edit/regenerate check this
    // flag before reshaping the transcript.
    final _SessionRun run = _SessionRun(
      sessionId: sessionId,
      title: state.title.isNotEmpty ? state.title : '',
      running: false,
    );
    try {
      // Modules are a per-chat scope: restore THIS chat's active list.
      run.activeModules.addAll(
        await ref.read(chatStoreProvider).loadModules(sessionId),
      );
    } catch (_) {
      // Module bookkeeping failure must never block a chat.
    }
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
      // empty) rather than blocking the user's request.
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
            // Vision hardening (v1.16.0): cap the long edge and re-encode
            // so a full-resolution photo never becomes megabytes of base64
            // in the wire. Mime follows the OUTPUT format (a downscaled
            // JPEG may no longer match the original file extension).
            final DownscaledImage prepared = await downscaleForUpload(bytes);
            run.dataUrlCache[att.path] =
                'data:${prepared.mime};base64,${base64Encode(prepared.bytes)}';
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
    String? prompt,
    List<ChatAttachment> attachments,
  ) async {
    final AppStrings strings = appStringsFor(settings.languageCode);
    // A null prompt means REPLAY: edit/regenerate already reshaped the
    // transcript, so no new user message is appended — the wire rebuilds
    // from run.messages below and truncation "just works".
    if (prompt != null) {
      run.messages.add(ChatMessage.user(prompt, attachments: attachments));
      _sync(run);
    }

    // Staged module (new chat with a module) activates AFTER the user
    // message so its entry output lands between the prompt and the reply.
    final String? stagedModule = run.pendingModule;
    if (stagedModule != null) {
      run.pendingModule = null;
      await _activateModule(run, stagedModule);
    }

    final wire = <Map<String, dynamic>>[
      _systemWire(settings, run),
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
          model: settings.model,
          usage: turn.usage,
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
  /// active-module context + enabled Context Manager entries merged into
  /// ONE system message (some providers reject several).
  Map<String, dynamic> _systemWire(AppSettings settings, _SessionRun run) {
    final StringBuffer content = StringBuffer();
    if (settings.agentMode) {
      content.write(agentSystemPrompt);
      if (settings.planFirst) content.write(planFirstSystemPrompt);
    }
    // Chat modules active in THIS session (per-chat scope): the model
    // should treat their run output as conversation data.
    if (run.activeModules.isNotEmpty) {
      final ModuleRegistry registry = ref.read(moduleRegistryProvider);
      for (final String name in run.activeModules) {
        try {
          final ChatModule? module = registry.getSync(name);
          if (module == null) continue;
          content
            ..writeln()
            ..writeln()
            ..writeln(
              '# Active module: ${module.name} v${module.manifest.version}',
            )
            ..write(
              module.manifest.description.trim().isEmpty
                  ? 'This module runs in THIS chat\'s isolated sandbox. '
                        'Its entry point already executed; treat its module '
                        'message output as data the user may ask about.'
                  : module.manifest.description.trim(),
            );
        } catch (_) {
          // Registry hiccup: skip the context block.
        }
      }
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
          .save(
            id: run.sessionId,
            title: run.title,
            messages: persisted,
            modules: run.activeModules,
          );
      ref.invalidate(chatListProvider);
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  /// Model-generated conversation title (v1.15.0). Runs ONCE per session,
  /// after the first successful answer, when the title still came from the
  /// automatic prompt-prefix path and the user has not renamed the chat.
  /// Every failure keeps the old title and never surfaces an error.
  Future<void> _maybeAutoTitle(_SessionRun run, AppSettings settings) async {
    try {
      if (!settings.autoTitle || !run.autoTitlePending) return;
      ChatMessage? firstUser;
      ChatMessage? firstAssistant;
      for (final ChatMessage m in run.messages) {
        if (m.role == Role.user &&
            firstUser == null &&
            m.content.trim().isNotEmpty) {
          firstUser = m;
        }
        if (m.role == Role.assistant &&
            firstAssistant == null &&
            m.content.trim().isNotEmpty &&
            !m.isStreaming) {
          firstAssistant = m;
        }
        if (firstUser != null && firstAssistant != null) break;
      }
      if (firstUser == null || firstAssistant == null) return;

      final AssistantTurn turn = await ref
          .read(llmClientProvider)
          .complete(
            config: LlmConfig(
              baseUrl: settings.baseUrl,
              apiKey: settings.apiKey,
              model: settings.model,
            ),
            tools: null,
            messages: <Map<String, dynamic>>[
              <String, dynamic>{
                'role': 'system',
                'content':
                    'You write short conversation titles. Reply with '
                    'ONLY the title: max 6 words, no quotes, no punctuation '
                    'at the end, same language as the conversation.',
              },
              <String, dynamic>{
                'role': 'user',
                'content':
                    '${_capForTitle(firstUser.content, 500)}\n\n'
                    'Assistant reply:\n'
                    '${_capForTitle(firstAssistant.content, 500)}',
              },
            ],
          );

      final String title = _sanitizeTitle(turn.content);
      if (title.isEmpty || title == run.title) return;
      run.title = title;
      run.autoTitlePending = false;
      if (_activeSessionId == run.sessionId) {
        state = state.copyWith(title: title);
      }
      try {
        await ref.read(chatStoreProvider).rename(run.sessionId, title);
        ref.invalidate(chatListProvider);
      } catch (_) {
        // The UI already shows the new title; storage stays best-effort.
      }
    } catch (_) {
      // Title generation is a pure nicety: any failure (API, parsing,
      // storage) keeps the existing title silently.
    }
  }

  /// Cleans a model-proposed title: trims, strips wrapping quotes, joins
  /// newlines and caps the length. Returns '' when nothing usable remains.
  static String _sanitizeTitle(String raw) {
    String title = raw.trim();
    if (title.length >= 2) {
      const List<String> quotes = <String>['"', "'", '“', '”', '«', '»'];
      for (final String q in quotes) {
        if (title.startsWith(q) && title.endsWith(q)) {
          title = title.substring(1, title.length - 1).trim();
          break;
        }
      }
    }
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.length > 80) title = title.substring(0, 80);
    return title.trim();
  }

  static String _capForTitle(String text, int max) {
    final String trimmed = text.trim();
    return trimmed.length > max ? trimmed.substring(0, max) : trimmed;
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
        activeModules: [...run.activeModules],
      );
      return;
    }
    try {
      final messages = await ref.read(chatStoreProvider).load(summary.id);
      // The user may have switched again while loading — only commit when
      // this session is still the active one.
      if (_activeSessionId != summary.id) return;
      List<String> modules = const <String>[];
      try {
        modules = await ref.read(chatStoreProvider).loadModules(summary.id);
      } catch (_) {
        // Module bookkeeping failure must never block opening a chat.
      }
      if (_activeSessionId != summary.id) return;
      state = ChatState(
        sessionId: summary.id,
        title: summary.title,
        messages: messages ?? const <ChatMessage>[],
        activeModules: modules,
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
      // A manual rename is authoritative: no automatic retitle afterwards.
      run.autoTitlePending = false;
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
    // If this session is running, stop it and drop its results; a live
    // module execution for the session is terminated safely too.
    _runs[id]?.stopRequested = true;
    _runs[id]?.deleted = true;
    try {
      ref.read(moduleRuntimeProvider).terminateSession(id);
    } catch (_) {
      // Runtime unavailable: deletion proceeds regardless.
    }
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
