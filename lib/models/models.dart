import 'package:uuid/uuid.dart';

import '../l10n/app_strings.dart' show defaultLanguageCode;

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
      default:
        final entries = arguments.entries
            .take(3)
            .map((e) => '${e.key}: ${e.value}');
        return entries.join(', ');
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'arguments': arguments,
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

/// A chat message, used both for UI display and (re)building the LLM wire format.
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
  }) => ChatMessage(
    id: newId(),
    role: Role.assistant,
    content: content,
    toolCalls: toolCalls,
    createdAt: DateTime.now(),
    isStreaming: isStreaming,
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
  );
}

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
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;

  bool get hasKey => apiKey.trim().isNotEmpty;

  ProviderPreset copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) => ProviderPreset(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };

  factory ProviderPreset.fromJson(Map<String, dynamic> json) => ProviderPreset(
    id: json['id'] as String? ?? newId(),
    name: json['name'] as String? ?? 'Provider',
    baseUrl: json['baseUrl'] as String? ?? '',
    apiKey: json['apiKey'] as String? ?? '',
    model: json['model'] as String? ?? '',
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

int clampMaxSteps(Object? value) {
  final int parsed = value is int ? value : int.tryParse('$value') ?? 0;
  if (parsed < minMaxSteps) return minMaxSteps;
  if (parsed > maxMaxSteps) return maxMaxSteps;
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
    this.runInBackground = true,
    this.languageCode = defaultLanguageCode,
    this.themeMode = ThemeModeSetting.dark,
    List<ProviderPreset>? presets,
  }) : presets = presets ?? _defaultPresets();

  final String providerName;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool agentMode;
  final bool automationEnabled;
  final int maxSteps;

  /// Keep the agent task running when the user leaves the app (Android
  /// foreground service + wake lock + progress notification).
  final bool runInBackground;

  /// UI language: 'en' (default) or 'id'. See lib/l10n/app_strings.dart.
  final String languageCode;

  /// Appearance preference.
  final ThemeModeSetting themeMode;

  /// Provider presets, each with its own API key. The active connection is
  /// still [providerName]/[baseUrl]/[apiKey]/[model]; switching a preset
  /// copies its values into the active fields.
  final List<ProviderPreset> presets;

  AppSettings copyWith({
    String? providerName,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? agentMode,
    bool? automationEnabled,
    Object? maxSteps,
    bool? runInBackground,
    String? languageCode,
    ThemeModeSetting? themeMode,
    List<ProviderPreset>? presets,
  }) => AppSettings(
    providerName: providerName ?? this.providerName,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    agentMode: agentMode ?? this.agentMode,
    automationEnabled: automationEnabled ?? this.automationEnabled,
    maxSteps: clampMaxSteps(maxSteps ?? this.maxSteps),
    runInBackground: runInBackground ?? this.runInBackground,
    languageCode: languageCode ?? this.languageCode,
    themeMode: themeMode ?? this.themeMode,
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
    'runInBackground': runInBackground,
    'languageCode': languageCode,
    'themeMode': themeMode.name,
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
      runInBackground: json['runInBackground'] as bool? ?? true,
      languageCode: json['languageCode'] as String? ?? defaultLanguageCode,
      themeMode: themeModeSettingFromName(json['themeMode'] as String?),
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
      runInBackground: runInBackground,
      languageCode: languageCode,
      themeMode: themeMode,
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

/// Page size of the model picker list.
const int modelPickerPageSize = 20;
