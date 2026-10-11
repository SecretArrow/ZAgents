import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../tools/tool_defs.dart';
import 'llm_client.dart';

/// Immutable UI state of the current chat session.
class ChatState {
  const ChatState({
    this.sessionId,
    this.title = '',
    this.messages = const <ChatMessage>[],
    this.isRunning = false,
    this.error,
  });

  final String? sessionId;
  final String title;
  final List<ChatMessage> messages;
  final bool isRunning;
  final String? error;

  static const Object _unset = Object();

  ChatState copyWith({
    String? sessionId,
    String? title,
    List<ChatMessage>? messages,
    bool? isRunning,
    Object? error = _unset,
  }) => ChatState(
    sessionId: sessionId ?? this.sessionId,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    isRunning: isRunning ?? this.isRunning,
    error: error == _unset ? this.error : error as String?,
  );
}

/// Drives the agent loop: user prompt -> LLM (streaming) -> tool calls ->
/// tool results -> ... -> final answer. Also handles persistence and history.
class ChatController extends Notifier<ChatState> {
  bool _stopRequested = false;

  @override
  ChatState build() => const ChatState();

  void stop() => _stopRequested = true;

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isRunning) return;
    _stopRequested = false;

    final settings = ref.read(settingsProvider);
    if (settings.apiKey.trim().isEmpty) {
      state = state.copyWith(
        error: appStringsFor(settings.languageCode).missingApiKey,
      );
      return;
    }
    if (settings.model.trim().isEmpty) {
      state = state.copyWith(
        error: appStringsFor(settings.languageCode).modelNotSet,
      );
      return;
    }

    final messages = [...state.messages];
    var sessionId = state.sessionId;
    var title = state.title;
    if (sessionId == null) {
      sessionId = newId();
      title = trimmed.length > 48 ? '${trimmed.substring(0, 48)}…' : trimmed;
    }
    messages.add(ChatMessage.user(trimmed));
    state = state.copyWith(
      sessionId: sessionId,
      title: title,
      messages: messages,
      isRunning: true,
      error: null,
    );

    final wire = <Map<String, dynamic>>[
      if (settings.agentMode)
        <String, dynamic>{'role': 'system', 'content': agentSystemPrompt},
      ..._buildWire(messages),
    ];
    final config = LlmConfig(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
    );
    final tools = settings.agentMode ? buildAgentTools() : null;

    try {
      for (var step = 0; step < settings.maxSteps; step++) {
        // 1. Stream one assistant turn.
        messages.add(ChatMessage.assistant('', isStreaming: true));
        _sync(messages);

        final buffer = StringBuffer();
        final turn = await ref
            .read(llmClientProvider)
            .complete(
              config: config,
              messages: wire,
              tools: tools,
              onDelta: (delta) {
                buffer.write(delta);
                messages[messages.length - 1] = ChatMessage.assistant(
                  buffer.toString(),
                  isStreaming: true,
                );
                _sync(messages);
              },
            );
        if (_stopRequested) break;

        final toolCalls = <ToolCall>[
          for (final tc in turn.toolCalls)
            ToolCall(id: tc.id, name: tc.name, arguments: tc.args),
        ];
        messages[messages.length - 1] = ChatMessage.assistant(
          turn.content,
          toolCalls: toolCalls,
        );
        _sync(messages);

        if (toolCalls.isEmpty) break; // Final answer reached.

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
          if (_stopRequested) break;
          call.status = ToolStatus.running;
          _sync(messages);

          final result = await executor.execute(call.name, call.arguments);
          call.status = result.ok ? ToolStatus.success : ToolStatus.error;
          call.resultText = result.llmOutput;
          call.screenshotPath = result.screenshotPath;
          _sync(messages);

          wire.add(<String, dynamic>{
            'role': 'tool',
            'tool_call_id': call.id,
            'content': result.llmOutput,
          });
        }
        if (_stopRequested) break;
      }

      if (_stopRequested && messages.isNotEmpty) {
        final last = messages.last;
        if (last.role == Role.assistant && last.isStreaming) {
          final stopped = appStringsFor(ref.read(settingsProvider).languageCode)
              .stoppedMarkdown;
          messages[messages.length - 1] = ChatMessage.assistant(
            '${last.content}\n\n$stopped',
          );
        }
      }
    } catch (e) {
      state = state.copyWith(isRunning: false, error: e.toString());
      await _persist(messages);
      return;
    }
    state = state.copyWith(isRunning: false);
    await _persist(messages);
  }

  /// Rebuild the OpenAI wire format from UI messages (incl. past tool calls).
  List<Map<String, dynamic>> _buildWire(List<ChatMessage> messages) {
    final out = <Map<String, dynamic>>[];
    for (final message in messages) {
      switch (message.role) {
        case Role.user:
          out.add(<String, dynamic>{
            'role': 'user',
            'content': message.content,
          });
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

  void _sync(List<ChatMessage> messages) {
    state = state.copyWith(messages: [...messages]);
  }

  Future<void> _persist(List<ChatMessage> messages) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final persisted = messages
        .where((m) => !(m.isStreaming && m.content.isEmpty))
        .toList();
    try {
      await ref
          .read(chatStoreProvider)
          .save(id: sessionId, title: state.title, messages: persisted);
      ref.invalidate(chatListProvider);
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  Future<void> newChat() async {
    if (state.isRunning) return;
    state = const ChatState();
  }

  Future<void> openChat(ChatSummary summary) async {
    if (state.isRunning) return;
    try {
      final messages = await ref.read(chatStoreProvider).load(summary.id);
      state = ChatState(
        sessionId: summary.id,
        title: summary.title,
        messages: messages ?? const <ChatMessage>[],
      );
    } catch (_) {
      // A corrupted history entry must never crash the app: open an empty
      // session and tell the user what happened.
      state = ChatState(
        error: appStringsFor(ref.read(settingsProvider).languageCode)
            .chatOpenError,
      );
    }
  }

  Future<void> deleteChat(String id) async {
    try {
      await ref.read(chatStoreProvider).delete(id);
    } catch (_) {
      state = state.copyWith(
        error: appStringsFor(ref.read(settingsProvider).languageCode)
            .chatDeleteError,
      );
      return;
    }
    if (state.sessionId == id) state = const ChatState();
    ref.invalidate(chatListProvider);
  }
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
