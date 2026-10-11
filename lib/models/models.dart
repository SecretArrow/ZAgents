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

  factory ChatMessage.user(String content) => ChatMessage(
    id: newId(),
    role: Role.user,
    content: content,
    createdAt: DateTime.now(),
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

/// User-configurable application settings.
class AppSettings {
  AppSettings({
    this.providerName = 'OpenRouter',
    this.baseUrl = 'https://openrouter.ai/api/v1',
    this.apiKey = '',
    this.model = 'z-ai/glm-4.6',
    this.agentMode = true,
    this.automationEnabled = true,
    this.maxSteps = 6,
    this.languageCode = defaultLanguageCode,
  });

  final String providerName;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool agentMode;
  final bool automationEnabled;
  final int maxSteps;

  /// UI language: 'en' (default) or 'id'. See lib/l10n/app_strings.dart.
  final String languageCode;

  AppSettings copyWith({
    String? providerName,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? agentMode,
    bool? automationEnabled,
    int? maxSteps,
    String? languageCode,
  }) => AppSettings(
    providerName: providerName ?? this.providerName,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    agentMode: agentMode ?? this.agentMode,
    automationEnabled: automationEnabled ?? this.automationEnabled,
    maxSteps: maxSteps ?? this.maxSteps,
    languageCode: languageCode ?? this.languageCode,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'providerName': providerName,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'agentMode': agentMode,
    'automationEnabled': automationEnabled,
    'maxSteps': maxSteps,
    'languageCode': languageCode,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    providerName: json['providerName'] as String? ?? 'OpenRouter',
    baseUrl: json['baseUrl'] as String? ?? 'https://openrouter.ai/api/v1',
    apiKey: json['apiKey'] as String? ?? '',
    model: json['model'] as String? ?? 'z-ai/glm-4.6',
    agentMode: json['agentMode'] as bool? ?? true,
    automationEnabled: json['automationEnabled'] as bool? ?? true,
    maxSteps: json['maxSteps'] as int? ?? 6,
    languageCode: json['languageCode'] as String? ?? defaultLanguageCode,
  );
}

/// Base URL presets for well-known OpenAI-compatible providers.
const Map<String, String> providerPresets = <String, String>{
  'OpenRouter': 'https://openrouter.ai/api/v1',
  'Z.AI': 'https://api.z.ai/api/paas/v4',
  'OpenAI': 'https://api.openai.com/v1',
  'DeepSeek': 'https://api.deepseek.com/v1',
  'Groq': 'https://api.groq.com/openai/v1',
  'Custom': '',
};

/// Model suggestions (OpenRouter-style slugs). Users may type any model id.
const List<String> suggestedModels = <String>[
  'z-ai/glm-4.6',
  'anthropic/claude-sonnet-4.5',
  'openai/gpt-4.1',
  'google/gemini-2.5-pro',
  'deepseek/deepseek-chat-v3.1',
  'qwen/qwen3-max',
];
