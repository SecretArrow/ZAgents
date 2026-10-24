import 'package:uuid/uuid.dart';

import '../l10n/app_strings.dart' show defaultLanguageCode;
import 'user_agent.dart' show UaMode, uaModeFromName;

/// Role of a chat message (OpenAI-compatible subset).
enum Role { system, user, assistant, tool }

/// Execution status of a tool call, for UI display.
enum ToolStatus { pending, running, success, error }

const Uuid _uuid = Uuid();

String newId() => _uuid.v4();

/// A single tool invocation requested by the model (or replayed from history).
class ToolCall {
  ToolCall({
    required this.id,
    required this.name,
    Map<String, dynamic>? arguments,
    this.status = ToolStatus.pending,
    this.resultText,
    this.screenshotPath,
  }) : arguments = arguments ?? const <String, dynamic>{};

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  ToolStatus status;
  String? resultText;
  String? screenshotPath;

  /// Short human-readable summary of the arguments for the UI.
  String get argsSummary {
    switch (name) {
      case 'browser_navigate':
        return arguments['url']?.toString() ?? '';
      case 'browser_click':
        return (arguments['text'] ?? arguments['selector'])?.toString() ?? '';
      case 'browser_type':
        return arguments['text']?.toString() ?? '';
      case 'browser_scroll':
        return '${arguments['direction'] ?? 'down'} ${arguments['amount'] ?? ''}'
            .trim();
      case 'browser_extract_text':
        // Language-neutral: UI adds a localized label when this is empty.
        return arguments['selector']?.toString() ?? '';
      case 'run_js':
        return arguments['code']?.toString() ?? '';
      case 'read_file':
      case 'write_file':
        return arguments['path']?.toString() ?? '';
      case 'node_run':
        final String code = arguments['code']?.toString() ?? '';
        return code.length > 40 ? '${code.substring(0, 40)}…' : code;
      case 'node_install':
      case 'node_remove':
        return arguments['package']?.toString() ?? '';
      case 'skill_install':
        return arguments['source']?.toString() ?? '';
      case 'skill_info':
        final String path = arguments['path']?.toString() ?? '';
        final String skill = arguments['name']?.toString() ?? '';
        return path.isEmpty ? skill : '$skill/$path';
      case 'skill_run':
        return '${arguments['name'] ?? ''} · '
            '${arguments['script'] ?? ''}'.trim();
      case 'skill_config':
        // SECRETS: the values object is never shown, persisted or sent
        // back to the provider — only the skill name is.
        return arguments['name']?.toString() ?? '';
      case 'request_confirmation':
        return arguments['title']?.toString() ?? '';
      default:
        final entries = arguments.entries
            .take(3)
            .map((e) => '${e.key}: ${e.value}');
        return entries.join(', ');
    }
  }

  /// Arguments that are safe to persist and to replay to the model.
  ///
  /// `skill_config` carries user secrets (API keys, wallet settings). They
  /// are written to the on-device skill config and MUST NOT be echoed into
  /// the transcript, the session export or the provider request — so only
  /// the skill name and the KEY names survive.
  Map<String, dynamic> get safeArguments {
    if (name != 'skill_config') return arguments;
    final Object? rawValues = arguments['values'];
    final Iterable<Object?> keys = rawValues is Map
        ? rawValues.keys
        : const <Object?>[];
    return <String, dynamic>{
      'name': arguments['name'],
      'values': <String, dynamic>{
        for (final Object? key in keys) key.toString(): '<redacted>',
      },
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'arguments': safeArguments,
    'status': status.name,
    'resultText': resultText,
    'screenshotPath': screenshotPath,
  };

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
    id: json['id'] as String,
    name: json['name'] as String,
    arguments:
        (json['arguments'] as Map<String, dynamic>?) ??
        const <String, dynamic>{},
    status: ToolStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => ToolStatus.pending,
    ),
    resultText: json['resultText'] as String?,
    screenshotPath: json['screenshotPath'] as String?,
  );
}

/// Token usage reported by the provider for one assistant turn
/// (OpenAI-compatible `usage` object). Nullable everywhere: providers that
/// do not report usage simply leave it out, and statistics skip them.
class TokenUsage {
  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
  });

  final int promptTokens;
  final int completionTokens;

  int get totalTokens => promptTokens + completionTokens;

  /// Parses the OpenAI-compatible `usage` object defensively; returns null
  /// when the shape is unusable (older exports, non-numeric values).
  static TokenUsage? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final int? prompt = (raw['prompt_tokens'] ?? raw['promptTokens']) is int
        ? (raw['prompt_tokens'] ?? raw['promptTokens']) as int
        : int.tryParse('${raw['prompt_tokens'] ?? raw['promptTokens']}');
    final int? completion =
        (raw['completion_tokens'] ?? raw['completionTokens']) is int
        ? (raw['completion_tokens'] ?? raw['completionTokens']) as int
        : int.tryParse(
            '${raw['completion_tokens'] ?? raw['completionTokens']}',
          );
    if (prompt == null || completion == null) return null;
    return TokenUsage(promptTokens: prompt, completionTokens: completion);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
  };
}

/// A chat message, used both for UI display and (re)building the LLM wire
/// format.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.toolCalls = const <ToolCall>[],
    this.toolCallId,
    this.toolName,
    required this.createdAt,
    this.isStreaming = false,
    this.attachments = const <ChatAttachment>[],
    this.model,
    this.usage,
    this.moduleName,
  });

  final String id;
  final Role role;
  final String content;

  /// Tool calls attached to an assistant message.
  final List<ToolCall> toolCalls;

  /// For [Role.tool] messages reconstructed from history (not shown in UI).
  final String? toolCallId;
  final String? toolName;
  final DateTime createdAt;
  final bool isStreaming;

  /// Files the user attached to this message (images / text / binary).
  final List<ChatAttachment> attachments;

  /// Model id that produced this assistant turn (v1.17.0 statistics).
  final String? model;

  /// Token usage reported by the provider for this assistant turn.
  final TokenUsage? usage;

  /// When set, this message carries the output of a chat module
  /// (plugins) run — rendered with the module badge in the UI.
  final String? moduleName;

  factory ChatMessage.user(
    String content, {
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) => ChatMessage(
    id: newId(),
    role: Role.user,
    content: content,
    createdAt: DateTime.now(),
    attachments: attachments,
  );

  factory ChatMessage.assistant(
    String content, {
    List<ToolCall> toolCalls = const <ToolCall>[],
    bool isStreaming = false,
    String? model,
    TokenUsage? usage,
    String? moduleName,
    String? id,
  }) => ChatMessage(
    // v1.38.0: callers updating a message in place (streaming deltas,
    // finalize, status notes) pass the PREVIOUS id so the UI's per-message
    // ValueKey stays stable — new ids on every delta used to tear down and
    // re-inflate the whole bubble subtree ~20x/second (frame drops and
    // Plan-panel state loss).
    id: id ?? newId(),
    role: Role.assistant,
    content: content,
    toolCalls: toolCalls,
    createdAt: DateTime.now(),
    isStreaming: isStreaming,
    model: model,
    usage: usage,
    moduleName: moduleName,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'role': role.name,
    'content': content,
    if (toolCalls.isNotEmpty)
      'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
    if (attachments.isNotEmpty)
      'attachments': attachments.map((a) => a.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    if (model != null) 'model': model,
    if (usage != null) 'usage': usage!.toJson(),
    if (moduleName != null) 'moduleName': moduleName,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String? ?? newId(),
    role: Role.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => Role.assistant,
    ),
    content: json['content'] as String? ?? '',
    toolCalls: ((json['toolCalls'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ToolCall.fromJson)
        .toList(),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    attachments: ((json['attachments'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ChatAttachment.fromJson)
        .toList(),
    model: json['model'] as String?,
    usage: TokenUsage.fromJson(json['usage']),
    moduleName: json['moduleName'] as String?,
  );
}

/// Execution status of one todo in the agent's task plan.
enum TodoStatus { pending, inProgress, completed }

/// Accepts the wire spelling (`in_progress`) and the Dart spelling
/// (`inProgress`); anything unknown degrades to [TodoStatus.pending].
TodoStatus todoStatusFromName(String? name) {
  switch (name) {
    case 'in_progress':
    case 'inProgress':
      return TodoStatus.inProgress;
    case 'completed':
    case 'done':
      return TodoStatus.completed;
    default:
      return TodoStatus.pending;
  }
}

/// One step of the agent's task plan, written by the model through the
/// `todo_write` tool. The full list is re-sent on every update, so the
/// latest `todo_write` call always describes the current plan state.
class TodoItem {
  const TodoItem({required this.content, this.status = TodoStatus.pending});

  final String content;
  final TodoStatus status;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'content': content,
    'status': status == TodoStatus.inProgress ? 'in_progress' : status.name,
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
    content: json['content']?.toString() ?? '',
    status: todoStatusFromName(json['status']?.toString()),
  );
}

/// Upper bound for plan size: keeps a runaway model from flooding the
/// chat (and the wire) with an endless todo list.
const int maxTodoItems = 50;

/// How many times per run the agent may be nudged to keep working when it
/// tries to stop with an incomplete plan. A pure runaway guard — real
/// plans finish far below this.
const int maxPlanNudges = 20;

/// Parses the `todos` argument of a `todo_write` tool call defensively:
/// accepts the decoded JSON array, skips malformed entries, trims content
/// and normalizes statuses. Returns only valid items (may be empty).
List<TodoItem> parseTodoList(Object? raw) {
  if (raw is! List<dynamic>) return const <TodoItem>[];
  final List<TodoItem> out = <TodoItem>[];
  for (final Object? entry in raw) {
    if (out.length >= maxTodoItems) break;
    if (entry is! Map<String, dynamic>) {
      if (entry is Map) {
        final TodoItem? item = _todoItemFromLoose(entry);
        if (item != null) out.add(item);
      }
      continue;
    }
    final String content = (entry['content'] ?? entry['text'] ?? '')
        .toString()
        .trim();
    if (content.isEmpty) continue;
    out.add(
      TodoItem(
        content: content.length > 500 ? content.substring(0, 500) : content,
        status: todoStatusFromName(entry['status']?.toString()),
      ),
    );
  }
  return out;
}

TodoItem? _todoItemFromLoose(Map<Object?, Object?> entry) {
  final Object? content = entry['content'] ?? entry['text'];
  final String text = content?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return TodoItem(
    content: text.length > 500 ? text.substring(0, 500) : text,
    status: todoStatusFromName(entry['status']?.toString()),
  );
}

/// True when at least one todo is not completed yet — the signal the
/// agent loop uses to keep working instead of stopping early.
bool hasIncompleteTodos(List<TodoItem> todos) =>
    todos.any((TodoItem t) => t.status != TodoStatus.completed);

/// Lightweight entry shown in the drawer history.
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });
  final String id;
  final String title;
  final DateTime updatedAt;
}

/// One result of the global chat search: the session it belongs to, a
/// short snippet around the first match (title hits carry no [role]),
/// and the message timestamp used for ordering.
class ChatSearchHit {
  const ChatSearchHit({
    required this.sessionId,
    required this.title,
    required this.snippet,
    this.role,
    required this.createdAt,
  });

  final String sessionId;
  final String title;
  final String snippet;

  /// Role of the matching message; null when the match was the title.
  final Role? role;
  final DateTime createdAt;
}

/// A reusable prompt stored in the Prompt Library and insertable into the
/// composer with one tap (see Composer's bookmark button).
class PromptEntry {
  const PromptEntry({
    required this.id,
    required this.title,
    this.content = '',
    required this.createdAt,
  });

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PromptEntry.fromJson(Map<String, dynamic> json) => PromptEntry(
    id: json['id'] as String? ?? newId(),
    title: json['title'] as String? ?? 'Prompt',
    content: _clampContent(json['content'] as String? ?? ''),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  /// Upper bound for a stored prompt: keeps a runaway paste from bloating
  /// the prompts.json file (and the composer) forever.
  static const int maxContentLength = 8000;

  static String _clampContent(String content) =>
      content.length > maxContentLength
      ? content.substring(0, maxContentLength)
      : content;
}

/// App appearance: light, dark (original look) or follow the system.
enum ThemeModeSetting { system, light, dark }

ThemeModeSetting themeModeSettingFromName(String? name) {
  for (final ThemeModeSetting mode in ThemeModeSetting.values) {
    if (mode.name == name) return mode;
  }
  return ThemeModeSetting.dark; // v1.3.0 look preserved by default.
}

/// A named provider configuration. Every preset carries its own API key
/// (and base URL / model) so switching providers is a single tap.
class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.name,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.modelsCache = const <String>[],
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// Model ids from the last successful `GET /models` fetch for this
  /// provider. Lets the model picker open instantly (and offline) with the
  /// models that actually exist on this provider.
  final List<String> modelsCache;

  bool get hasKey => apiKey.trim().isNotEmpty;

  bool get hasModelsCache => modelsCache.isNotEmpty;

  ProviderPreset copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    List<String>? modelsCache,
  }) => ProviderPreset(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    modelsCache: modelsCache ?? this.modelsCache,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'modelsCache': modelsCache,
  };

  factory ProviderPreset.fromJson(Map<String, dynamic> json) => ProviderPreset(
    id: json['id'] as String? ?? newId(),
    name: json['name'] as String? ?? 'Provider',
    baseUrl: json['baseUrl'] as String? ?? '',
    apiKey: json['apiKey'] as String? ?? '',
    model: json['model'] as String? ?? '',
    modelsCache: ((json['modelsCache'] as List<dynamic>?) ?? const <dynamic>[])
        .map((Object? e) => e.toString())
        .toList(),
  );
}

/// Kind of a chat attachment, drives how it is fed to the model.
enum AttachmentKind { image, text, other }

/// A file attached by the user to a chat message.
class ChatAttachment {
  const ChatAttachment({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.kind,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final AttachmentKind kind;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'path': path,
    'sizeBytes': sizeBytes,
    'kind': kind.name,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
    name: json['name'] as String? ?? 'file',
    path: json['path'] as String? ?? '',
    sizeBytes: json['sizeBytes'] as int? ?? 0,
    kind: AttachmentKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => AttachmentKind.other,
    ),
  );
}

/// A reusable prompt context block the user can create, edit, enable and
/// delete in the Context Manager. Enabled entries are injected into the
/// system prompt of every request.
class ContextEntry {
  const ContextEntry({
    required this.id,
    required this.name,
    this.content = '',
    this.enabled = false,
  });

  final String id;
  final String name;
  final String content;

  /// Whether this entry is currently applied to conversations.
  final bool enabled;

  ContextEntry copyWith({String? name, String? content, bool? enabled}) =>
      ContextEntry(
        id: id,
        name: name ?? this.name,
        content: content ?? this.content,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'content': content,
    'enabled': enabled,
  };

  factory ContextEntry.fromJson(Map<String, dynamic> json) => ContextEntry(
    id: json['id'] as String? ?? newId(),
    name: json['name'] as String? ?? 'Context',
    content: json['content'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? false,
  );
}

/// Allowed bounds of the max-steps setting (slider 1-100 + custom input).
const int minMaxSteps = 1;
const int maxMaxSteps = 100;
const int defaultMaxSteps = 6;

/// Absolute ceiling used when "Run until done" is enabled: the agent is
/// NOT bound by the max-steps setting and keeps working until the model
/// stops requesting tools (or the user presses Stop). The ceiling only
/// exists as a runaway guard against a provider looping forever — it is
/// far beyond any real task.
const int unboundedStepLimit = 10000;

int clampMaxSteps(Object? value) {
  final int parsed = value is int ? value : int.tryParse('$value') ?? 0;
  if (parsed < minMaxSteps) return minMaxSteps;
  if (parsed > maxMaxSteps) return maxMaxSteps;
  return parsed;
}

/// Bounds of the auto-retry settings (v1.30.0): how many times the agent
/// may re-attempt a failed turn / resume an interrupted task, and how long
/// (seconds) it waits before each retry — the wait grows with the attempt
/// (delay x attempt) so a struggling network gets progressively more room.
const int minAutoRetryAttempts = 1;
const int maxAutoRetryAttempts = 10;
const int defaultAutoRetryAttempts = 3;
const int minAutoRetryDelay = 0;
const int maxAutoRetryDelay = 60;
const int defaultAutoRetryDelay = 5;

int clampAutoRetryAttempts(Object? value) {
  final int parsed = value is int ? value : int.tryParse('$value') ?? 0;
  if (parsed < minAutoRetryAttempts) return minAutoRetryAttempts;
  if (parsed > maxAutoRetryAttempts) return maxAutoRetryAttempts;
  return parsed;
}

int clampAutoRetryDelay(Object? value) {
  final int parsed = value is int ? value : int.tryParse('$value') ?? 0;
  if (parsed < minAutoRetryDelay) return minAutoRetryDelay;
  if (parsed > maxAutoRetryDelay) return maxAutoRetryDelay;
  return parsed;
}

/// Guesses the [AttachmentKind] of a picked file from its extension.
AttachmentKind attachmentKindFor(String fileName) {
  final String ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  const Set<String> images = <String>{
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'bmp',
    'heic',
  };
  const Set<String> texts = <String>{
    'txt',
    'md',
    'markdown',
    'csv',
    'tsv',
    'json',
    'yaml',
    'yml',
    'xml',
    'html',
    'htm',
    'css',
    'js',
    'mjs',
    'cjs',
    'ts',
    'tsx',
    'jsx',
    'dart',
    'py',
    'rb',
    'go',
    'rs',
    'java',
    'kt',
    'kts',
    'c',
    'h',
    'cpp',
    'hpp',
    'cs',
    'php',
    'sh',
    'bat',
    'ps1',
    'sql',
    'toml',
    'ini',
    'cfg',
    'conf',
    'log',
    'env',
    'gradle',
    'properties',
    'vue',
    'svelte',
    'swift',
  };
  if (images.contains(ext)) return AttachmentKind.image;
  if (texts.contains(ext)) return AttachmentKind.text;
  return AttachmentKind.other;
}

/// User-configurable application settings.
class AppSettings {
  AppSettings({
    this.providerName = 'OpenRouter',
    this.baseUrl = 'https://openrouter.ai/api/v1',
    this.apiKey = '',
    this.model = 'z-ai/glm-4.6',
    this.agentMode = true,
    this.automationEnabled = true,
    this.maxSteps = defaultMaxSteps,
    this.runUntilDone = true,
    this.planFirst = true,
    this.runInBackground = true,
    this.askRandomUa = true,
    this.autoTitle = true,
    this.appLockEnabled = false,
    this.notifyOnDone = true,
    this.autoRetryEnabled = true,
    this.autoRetryAttempts = defaultAutoRetryAttempts,
    this.autoRetryDelay = defaultAutoRetryDelay,
    this.deviceCommandsEnabled = false,
    this.languageCode = defaultLanguageCode,
    this.themeMode = ThemeModeSetting.dark,
    this.uaMode = UaMode.auto,
    this.uaDesktopId = 1,
    this.uaAndroidId = 1,
    List<ProviderPreset>? presets,
  }) : presets = presets ?? _defaultPresets();

  final String providerName;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool agentMode;
  final bool automationEnabled;
  final int maxSteps;

  /// When true (default) the agent loop is NOT capped by [maxSteps]: it
  /// keeps calling tools until the model produces its final answer or the
  /// user presses Stop. When false, [maxSteps] is enforced and hitting it
  /// pauses the work with a visible explanation instead of stopping
  /// silently.
  final bool runUntilDone;

  /// When true (default) agent mode always starts a task by writing a
  /// todo plan (`todo_write`) and keeps working through it: the loop
  /// nudges the model to continue while any todo is still incomplete.
  final bool planFirst;

  /// Keep the agent task running when the user leaves the app (Android
  /// foreground service + wake lock + progress notification).
  final bool runInBackground;

  /// When true (default) tapping "New chat" offers a dialog asking whether
  /// the embedded browser should switch to a different, randomly picked
  /// User-Agent for the next conversation. Disable to skip the prompt.
  final bool askRandomUa;

  /// When true the app shows a lock screen (biometric, PIN fallback)
  /// on app start and every time it is resumed from the background
  /// (v1.18.0). The PIN itself is stored OUTSIDE [AppSettings] — see
  /// AppLockService — so it never travels inside settings backups.
  final bool appLockEnabled;

  /// When true (default) a local notification is posted when an agent run
  /// finishes while the app is in the background (v1.18.0).
  final bool notifyOnDone;

  /// v1.30.0 auto-retry: when true (default), a failed LLM turn (network
  /// error, weak connection, dropped stream, transient provider HTTP
  /// 429/5xx) is re-attempted automatically, and a task that stopped
  /// mid-way is RESUMED from its transcript — an unfinished todo plan is
  /// picked back up instead of staying stalled. The retry count and the
  /// wait between attempts are user-configurable.
  final bool autoRetryEnabled;

  /// Max automatic re-attempts per failure (1-10, default 3).
  final int autoRetryAttempts;

  /// Base wait in seconds before the n-th retry: delay x n, so the wait
  /// grows with each attempt (0-60 s, default 5 s).
  final int autoRetryDelay;

  /// v1.31.0 — master switch for chat-module device commands
  /// (`zagents.device.shell`). OFF by default: only rooted phones can use
  /// it meaningfully, and it gates a capability with system-wide impact
  /// (airplane mode, VPN, ...). Modules that declare the `device`
  /// permission additionally ask for consent at activation.
  final bool deviceCommandsEnabled;

  /// When true (default) conversations created from the automatic prompt
  /// prefix get a short model-generated title after the first answer.
  /// Renamed conversations are never retitled.
  final bool autoTitle;

  /// UI language: 'en' (default) or 'id'. See lib/l10n/app_strings.dart.
  final String languageCode;

  /// Appearance preference.
  final ThemeModeSetting themeMode;

  /// User-Agent selection mode for the embedded browser surfaces.
  final UaMode uaMode;

  /// Sticky User-Agent selection per category (ids into the UA database).
  /// The pick survives restarts and only changes when the user rotates it —
  /// session stability beats novelty.
  final int uaDesktopId;
  final int uaAndroidId;

  /// Provider presets, each with its own API key. The active connection is
  /// still [providerName]/[baseUrl]/[apiKey]/[model]; switching a preset
  /// copies its values into the active fields.
  final List<ProviderPreset> presets;

  /// The preset backing the active connection ([providerName]), if any.
  ProviderPreset? get activePreset {
    for (final ProviderPreset p in presets) {
      if (p.name == providerName) return p;
    }
    return null;
  }

  AppSettings copyWith({
    String? providerName,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? agentMode,
    bool? automationEnabled,
    Object? maxSteps,
    bool? runUntilDone,
    bool? planFirst,
    bool? runInBackground,
    bool? askRandomUa,
    bool? autoTitle,
    bool? appLockEnabled,
    bool? notifyOnDone,
    bool? autoRetryEnabled,
    Object? autoRetryAttempts,
    Object? autoRetryDelay,
    bool? deviceCommandsEnabled,
    String? languageCode,
    ThemeModeSetting? themeMode,
    UaMode? uaMode,
    int? uaDesktopId,
    int? uaAndroidId,
    List<ProviderPreset>? presets,
  }) => AppSettings(
    providerName: providerName ?? this.providerName,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    agentMode: agentMode ?? this.agentMode,
    automationEnabled: automationEnabled ?? this.automationEnabled,
    maxSteps: clampMaxSteps(maxSteps ?? this.maxSteps),
    runUntilDone: runUntilDone ?? this.runUntilDone,
    planFirst: planFirst ?? this.planFirst,
    runInBackground: runInBackground ?? this.runInBackground,
    askRandomUa: askRandomUa ?? this.askRandomUa,
    autoTitle: autoTitle ?? this.autoTitle,
    appLockEnabled: appLockEnabled ?? this.appLockEnabled,
    notifyOnDone: notifyOnDone ?? this.notifyOnDone,
    autoRetryEnabled: autoRetryEnabled ?? this.autoRetryEnabled,
    autoRetryAttempts: clampAutoRetryAttempts(
      autoRetryAttempts ?? this.autoRetryAttempts,
    ),
    autoRetryDelay: clampAutoRetryDelay(autoRetryDelay ?? this.autoRetryDelay),
    deviceCommandsEnabled: deviceCommandsEnabled ?? this.deviceCommandsEnabled,
    languageCode: languageCode ?? this.languageCode,
    themeMode: themeMode ?? this.themeMode,
    uaMode: uaMode ?? this.uaMode,
    uaDesktopId: uaDesktopId ?? this.uaDesktopId,
    uaAndroidId: uaAndroidId ?? this.uaAndroidId,
    presets: presets ?? this.presets,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'providerName': providerName,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'agentMode': agentMode,
    'automationEnabled': automationEnabled,
    'maxSteps': maxSteps,
    'runUntilDone': runUntilDone,
    'planFirst': planFirst,
    'runInBackground': runInBackground,
    'askRandomUa': askRandomUa,
    'autoTitle': autoTitle,
    'appLockEnabled': appLockEnabled,
    'notifyOnDone': notifyOnDone,
    'autoRetryEnabled': autoRetryEnabled,
    'autoRetryAttempts': autoRetryAttempts,
    'autoRetryDelay': autoRetryDelay,
    'deviceCommandsEnabled': deviceCommandsEnabled,
    'languageCode': languageCode,
    'themeMode': themeMode.name,
    'uaMode': uaMode.name,
    'uaDesktopId': uaDesktopId,
    'uaAndroidId': uaAndroidId,
    'presets': presets.map((p) => p.toJson()).toList(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final AppSettings settings = AppSettings(
      providerName: json['providerName'] as String? ?? 'OpenRouter',
      baseUrl: json['baseUrl'] as String? ?? 'https://openrouter.ai/api/v1',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? 'z-ai/glm-4.6',
      agentMode: json['agentMode'] as bool? ?? true,
      automationEnabled: json['automationEnabled'] as bool? ?? true,
      maxSteps: clampMaxSteps(json['maxSteps'] ?? defaultMaxSteps),
      runUntilDone: json['runUntilDone'] as bool? ?? true,
      planFirst: json['planFirst'] as bool? ?? true,
      runInBackground: json['runInBackground'] as bool? ?? true,
      askRandomUa: json['askRandomUa'] as bool? ?? true,
      autoTitle: json['autoTitle'] as bool? ?? true,
      appLockEnabled: json['appLockEnabled'] as bool? ?? false,
      notifyOnDone: json['notifyOnDone'] as bool? ?? true,
      autoRetryEnabled: json['autoRetryEnabled'] as bool? ?? true,
      autoRetryAttempts: clampAutoRetryAttempts(
        json['autoRetryAttempts'] ?? defaultAutoRetryAttempts,
      ),
      autoRetryDelay: clampAutoRetryDelay(
        json['autoRetryDelay'] ?? defaultAutoRetryDelay,
      ),
      deviceCommandsEnabled: json['deviceCommandsEnabled'] as bool? ?? false,
      languageCode: json['languageCode'] as String? ?? defaultLanguageCode,
      themeMode: themeModeSettingFromName(json['themeMode'] as String?),
      uaMode: uaModeFromName(json['uaMode'] as String?),
      uaDesktopId: json['uaDesktopId'] as int? ?? 1,
      uaAndroidId: json['uaAndroidId'] as int? ?? 1,
      presets: (json['presets'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map(ProviderPreset.fromJson)
          .toList(),
    );
    return settings._withPresetMigration();
  }

  /// One-time migration from pre-1.4.0 storage: presets were not persisted
  /// (or the legacy single API key moved to another preset). Seeds the
  /// built-in provider list and assigns the active key/model to the preset
  /// matching [providerName] so nothing the user typed is ever lost.
  AppSettings _withPresetMigration() {
    final Map<String, ProviderPreset> byName = <String, ProviderPreset>{
      for (final ProviderPreset p in presets) p.name: p,
    };
    final List<ProviderPreset> merged = <ProviderPreset>[];
    for (final String name in providerPresets.keys) {
      final ProviderPreset existing =
          byName[name] ??
          ProviderPreset(
            id: newId(),
            name: name,
            baseUrl: providerPresets[name] ?? '',
          );
      final bool isActivePreset = name == providerName;
      merged.add(
        existing.copyWith(
          // Carry the legacy single key/model into the active preset.
          apiKey: existing.hasKey || !isActivePreset ? null : apiKey,
          model: existing.model.isNotEmpty || !isActivePreset ? null : model,
          baseUrl: (existing.baseUrl.isNotEmpty || !isActivePreset)
              ? null
              : baseUrl,
        ),
      );
      byName.remove(name);
    }
    // Custom presets created by the user survive at the end.
    merged.addAll(byName.values);
    return AppSettings(
      providerName: providerName,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      agentMode: agentMode,
      automationEnabled: automationEnabled,
      maxSteps: maxSteps,
      runUntilDone: runUntilDone,
      planFirst: planFirst,
      runInBackground: runInBackground,
      askRandomUa: askRandomUa,
      autoTitle: autoTitle,
      appLockEnabled: appLockEnabled,
      notifyOnDone: notifyOnDone,
      autoRetryEnabled: autoRetryEnabled,
      autoRetryAttempts: autoRetryAttempts,
      autoRetryDelay: autoRetryDelay,
      deviceCommandsEnabled: deviceCommandsEnabled,
      languageCode: languageCode,
      themeMode: themeMode,
      uaMode: uaMode,
      uaDesktopId: uaDesktopId,
      uaAndroidId: uaAndroidId,
      presets: merged,
    );
  }

  /// Seeds the built-in preset list (all with empty keys).
  static List<ProviderPreset> _defaultPresets() => <ProviderPreset>[
    for (final MapEntry<String, String> e in providerPresets.entries)
      ProviderPreset(id: newId(), name: e.key, baseUrl: e.value),
  ];
}

/// Base URL presets for well-known OpenAI-compatible providers.
///
/// InferHub (https://inferhub.dev) exposes an OpenAI-compatible inference
/// API at api.inferhub.dev with keys of the form `sk-airo-…`.
const Map<String, String> providerPresets = <String, String>{
  'OpenRouter': 'https://openrouter.ai/api/v1',
  'InferHub': 'https://api.inferhub.dev/v1',
  'Z.AI': 'https://api.z.ai/api/paas/v4',
  'OpenAI': 'https://api.openai.com/v1',
  'DeepSeek': 'https://api.deepseek.com/v1',
  'Groq': 'https://api.groq.com/openai/v1',
  'Custom': '',
};

/// Default model applied when switching provider presets and the current
/// model is empty or belongs to another provider's default. Providers whose
/// catalogs must be fetched (InferHub) map to null — the user picks from
/// the live model list instead.
const Map<String, String?> providerDefaultModels = <String, String?>{
  'OpenRouter': 'z-ai/glm-4.6',
  'InferHub': null,
  'Z.AI': 'glm-4.6',
  'OpenAI': 'gpt-4.1',
  'DeepSeek': 'deepseek-chat',
  'Groq': 'llama-3.3-70b-versatile',
  'Custom': null,
};

/// Model suggestions (OpenRouter-style slugs) used as offline fallback when
/// the live catalog cannot be fetched. Users may type any model id.
const List<String> suggestedModels = <String>[
  'z-ai/glm-4.6',
  'anthropic/claude-sonnet-4.5',
  'openai/gpt-4.1',
  'google/gemini-2.5-pro',
  'deepseek/deepseek-chat-v3.1',
  'qwen/qwen3-max',
];

/// Page size used by every list in the app (model picker, providers,
/// files, sessions, contexts, libraries, ...). Kept small (5) so lists
/// stay comfortable on phones and the pager is predictable.
const int listPageSize = 5;

/// Builds [ProviderPreset]-compatible host label (scheme + host) for
/// display in provider lists, e.g. `https://api.inferhub.dev/v1` becomes
/// `api.inferhub.dev`. Returns the raw value when parsing fails.
String presetHostLabel(String baseUrl) {
  final Uri? uri = Uri.tryParse(baseUrl.trim());
  if (uri == null || uri.host.isEmpty) return baseUrl.trim();
  return uri.host;
}
