import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Connection settings for an OpenAI-compatible endpoint.
class LlmConfig {
  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
}

/// A tool call requested by the model (arguments still raw JSON string).
class ToolCallRequest {
  ToolCallRequest({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;

  /// Parsed arguments; falls back to an empty map on malformed JSON.
  Map<String, dynamic> get args {
    try {
      final decoded = jsonDecode(argumentsJson.isEmpty ? '{}' : argumentsJson);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // fall through
    }
    return <String, dynamic>{};
  }
}

/// One completed assistant turn: streamed text + any tool calls.
class AssistantTurn {
  AssistantTurn({
    required this.content,
    this.toolCalls = const <ToolCallRequest>[],
  });

  final String content;
  final List<ToolCallRequest> toolCalls;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

class LlmException implements Exception {
  LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Streaming client for OpenAI-compatible chat completion APIs
/// (OpenRouter, Z.AI, OpenAI, DeepSeek, Groq, ...).
class LlmClient {
  LlmClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Sends a chat completion request and streams the assistant turn.
  ///
  /// [onDelta] receives incremental content tokens while streaming.
  /// Tool call deltas are accumulated internally and returned with the turn.
  Future<AssistantTurn> complete({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    void Function(String delta)? onDelta,
  }) async {
    final url = Uri.parse(
      '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions',
    );
    final requestBody = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'stream': true,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
    };

    final request = http.Request('POST', url)
      ..headers['Authorization'] = 'Bearer ${config.apiKey}'
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      // OpenRouter attribution (ignored by other providers).
      ..headers['HTTP-Referer'] = 'https://github.com/SecretArrow/ZAgents'
      ..headers['X-Title'] = 'ZAgents'
      ..body = jsonEncode(requestBody);

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      throw LlmException('Could not connect to provider: $e');
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw LlmException(
        'HTTP ${response.statusCode}: ${_truncate(body, 300)}',
      );
    }

    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (!contentType.contains('text/event-stream')) {
      // Some providers ignore `stream: true`; parse a plain JSON response.
      final raw = await response.stream.bytesToString();
      return _parseNonStreaming(raw);
    }
    try {
      return await _parseSse(response.stream, onDelta);
    } on LlmException {
      rethrow;
    } catch (e) {
      // Network drop mid-stream: keep whatever was streamed so far when it
      // is usable text, otherwise surface a connection error.
      throw LlmException('Connection lost while streaming: $e');
    }
  }

  AssistantTurn _parseNonStreaming(String raw) {
    try {
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      final choices = obj['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = choices.first['message'];
        if (message is Map<String, dynamic>) {
          return AssistantTurn(
            content: message['content']?.toString() ?? '',
            toolCalls: _parseFullToolCalls(message['tool_calls']),
          );
        }
      }
      throw LlmException('Unknown response format: ${_truncate(raw, 200)}');
    } on LlmException {
      rethrow;
    } catch (e) {
      throw LlmException('Failed to read response: $e');
    }
  }

  Future<AssistantTurn> _parseSse(
    http.ByteStream stream,
    void Function(String delta)? onDelta,
  ) async {
    final contentBuffer = StringBuffer();
    final toolAccumulators = <int, _ToolAccumulator>{};
    var lineBuffer = '';
    var done = false;

    try {
      await for (final chunk in stream.transform(utf8.decoder)) {
        lineBuffer += chunk;
        while (true) {
          final newlineIndex = lineBuffer.indexOf('\n');
          if (newlineIndex < 0) break;
          final line = lineBuffer.substring(0, newlineIndex).trim();
          lineBuffer = lineBuffer.substring(newlineIndex + 1);

          if (line.isEmpty || line.startsWith(':')) continue;
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data == '[DONE]') {
            done = true;
            break;
          }

          Map<String, dynamic> event;
          try {
            final decoded = jsonDecode(data);
            if (decoded is! Map<String, dynamic>) continue;
            event = decoded;
          } catch (_) {
            continue;
          }

          final choices = event['choices'];
          if (choices is! List || choices.isEmpty) continue;
          final delta = choices.first['delta'];
          if (delta is! Map<String, dynamic>) continue;

          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            contentBuffer.write(content);
            onDelta?.call(content);
          }

          final toolCalls = delta['tool_calls'];
          if (toolCalls is List) {
            for (final raw in toolCalls) {
              if (raw is! Map<String, dynamic>) continue;
              final index = (raw['index'] as int?) ?? toolAccumulators.length;
              final acc = toolAccumulators.putIfAbsent(
                index,
                _ToolAccumulator.new,
              );
              if (raw['id'] is String && (acc.id == null || acc.id!.isEmpty)) {
                acc.id = raw['id'] as String;
              }
              final function = raw['function'];
              if (function is Map<String, dynamic>) {
                final name = function['name'];
                if (name is String &&
                    name.isNotEmpty &&
                    (acc.name == null || acc.name!.isEmpty)) {
                  acc.name = name;
                }
                final arguments = function['arguments'];
                if (arguments is String) acc.arguments.write(arguments);
              }
            }
          }
        }
        if (done) break;
      }
    } on LlmException {
      rethrow;
    } catch (e) {
      // A dropped socket mid-stream must not crash the app: keep partial
      // plain-text content, but never return half-received tool calls
      // (their JSON arguments would be truncated and unusable).
      if (toolAccumulators.isEmpty && contentBuffer.isNotEmpty) {
        return AssistantTurn(content: contentBuffer.toString());
      }
      throw LlmException('Connection lost while streaming: $e');
    }

    final ordered = toolAccumulators.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return AssistantTurn(
      content: contentBuffer.toString(),
      toolCalls: <ToolCallRequest>[
        for (final entry in ordered)
          if (entry.value.name != null) entry.value.toRequest(),
      ],
    );
  }

  List<ToolCallRequest> _parseFullToolCalls(Object? rawToolCalls) {
    if (rawToolCalls is! List) return const <ToolCallRequest>[];
    final out = <ToolCallRequest>[];
    for (final raw in rawToolCalls) {
      if (raw is! Map<String, dynamic>) continue;
      final function = raw['function'];
      if (function is! Map<String, dynamic>) continue;
      final Object? name = function['name'];
      // A provider glitch (missing name) must not crash the app: the entry
      // is skipped instead of throwing on null.
      if (name == null || name.toString().isEmpty) continue;
      out.add(
        ToolCallRequest(
          id: raw['id']?.toString() ?? newCallId(),
          name: name.toString(),
          argumentsJson: (function['arguments'] ?? '').toString(),
        ),
      );
    }
    return out;
  }

  String _truncate(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}...';
}

int _callCounter = 0;
String newCallId() =>
    'call_${DateTime.now().millisecondsSinceEpoch}_${_callCounter++}';

class _ToolAccumulator {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();

  ToolCallRequest toRequest() => ToolCallRequest(
    id: (id == null || id!.isEmpty) ? newCallId() : id!,
    name: name!,
    argumentsJson: arguments.toString(),
  );
}
