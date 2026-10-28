import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'llm_client.dart';

/// AgentRouter (https://agentrouter.org) transport.
///
/// The gateway serves BOTH wire protocols on the version-segmented base
/// (`…/v1/chat/completions` OpenAI-compatible, `…/v1/messages` Anthropic
/// Messages). Which one speaks FIRST is decided per model family — the
/// room-browser-proven recipe: Claude models speak Anthropic Messages
/// natively, GPT and every other family speaks OpenAI-compatible
/// ([prefersAnthropic]). A 404/405 on the first-choice path still falls
/// back ONCE to the other protocol for single-protocol deployments, and
/// the confirmed protocol is cached per (normalized base URL, family) so
/// later calls skip the guess entirely.
///
/// [AgentRouterLlmClient] also carries the claude-cli User-Agent the
/// gateway REQUIRES on every request (missing it yields 401
/// unauthorized_client_error / WAF challenges), sends dual auth headers
/// (x-api-key + Bearer) on the Anthropic path, and translates two gateway
/// failure modes into actionable messages: Aliyun WAF bot-challenge pages
/// ("switch to mobile data") and the "Invalid API Key" deployment
/// mismatch (apex vs co. consoles have separate key databases).
///
/// Everything outside agentrouter.org (and its subdomains) goes through
/// `super.complete()` unchanged — zero behavior change for OpenRouter,
/// Z.AI, OpenAI, DeepSeek, Groq and custom providers.

/// Exact User-Agent every AgentRouter request must carry — the Anthropic
/// transport AND the OpenAI-compatible fallback alike.
const String kAgentRouterUserAgent = 'claude-cli/1.0.60 (external, cli)';

/// Anthropic API version header sent on every AgentRouter request.
const String kAnthropicVersion = '2023-06-01';

/// `max_tokens` is REQUIRED by the Anthropic Messages protocol; used when
/// [LlmConfig.maxTokens] is not set.
const int kAgentRouterMaxTokens = 8192;

const String _agentRouterDomain = 'agentrouter.org';

/// Returns the host of [baseUrl], or null when it cannot be parsed (or is
/// empty). Pure function — unit-tested directly.
String? hostOf(String baseUrl) {
  final Uri? uri = Uri.tryParse(baseUrl.trim());
  if (uri == null) return null;
  final String host = uri.host.trim();
  return host.isEmpty ? null : host;
}

/// Strict anti-typosquatting hostname check: ONLY `agentrouter.org` and
/// any-depth `*.agentrouter.org` subdomains qualify. Rejects look-alikes
/// (`evil-agentrouter.org`, `agentrouter.org.evil.com`,
/// `agentrouter.community`, `agentrouter.orgx`), hosts with underscores,
/// IP literals, empty hosts, case noise and trailing dots. Pure function.
bool isAgentRouterHost(String host) {
  final String h = host.trim().toLowerCase();
  if (h.isEmpty || h.contains('_')) return false;
  // An empty label rejects '' and hosts with a trailing/leading/doubled
  // dot ('agentrouter.org.', '.agentrouter.org', 'a..b').
  for (final String label in h.split('.')) {
    if (label.isEmpty) return false;
  }
  return h == _agentRouterDomain || h.endsWith('.$_agentRouterDomain');
}

/// Normalized base URL used as the protocol-probe cache key (and for
/// building `{base}/messages` / `{base}/chat/completions` URLs).
String normalizeBaseUrl(String baseUrl) =>
    baseUrl.replaceAll(RegExp(r'/+$'), '');

/// AgentRouter's official paths live under the version segment
/// (`…/v1/chat/completions`, `…/v1/messages`). Base URLs without any
/// version segment get `/v1` appended; URLs that already carry one pass
/// through untouched. Pure function — unit-tested directly.
String normalizeAgentRouterBase(String baseUrl) {
  final String trimmed = normalizeBaseUrl(baseUrl.trim());
  final Uri? uri = Uri.tryParse(trimmed);
  final bool hasVersionSegment = <String>[
    for (final String s in uri?.pathSegments ?? const <String>[])
      if (s.trim().isNotEmpty) s,
  ].any((String s) => RegExp(r'^v\d+$').hasMatch(s.toLowerCase()));
  return hasVersionSegment ? trimmed : '$trimmed/v1';
}

/// Room-browser-proven per-model routing: the gateway serves both wire
/// protocols, and the model family has a natural first choice — Claude
/// models speak Anthropic Messages natively, GPT and every other family
/// speaks OpenAI-compatible. A wrong first guess costs one dead request
/// (or a WAF page on guarded deployments), so the family decides. Pure
/// function — unit-tested directly.
bool prefersAnthropic(String model) =>
    model.trim().toLowerCase().startsWith('claude');

/// Detects Aliyun WAF bot-challenge pages (slider captcha / JS challenge)
/// served instead of API responses to datacenter IPs. Runs on response
/// bodies and on error messages that embed a body snippet — the markers
/// (`acw_tc`, `acw_sc__v2`, captcha scripts) live in the first bytes of
/// the page. Pure function — unit-tested directly.
bool looksLikeWafChallenge(String body) {
  final String s = body.toLowerCase();
  return s.contains('acw_tc') ||
      s.contains('acw_sc') ||
      s.contains('aliyunwaf') ||
      s.contains('aliyun waf') ||
      s.contains('anti-bot') ||
      s.contains('captcha') ||
      (s.contains('aliyun') && (s.contains('waf') || s.contains('slider')));
}

/// Actionable guidance for [looksLikeWafChallenge]: the fix is a network
/// switch (phone networks pass, datacenter IPs are challenged), never a
/// key or URL change.
String agentRouterWafMessage() =>
    'AgentRouter is bot-challenging this connection (Aliyun WAF). The '
    'gateway blocks datacenter IPs but normally allows phone networks — '
    'switch to mobile data (or another WiFi) and retry. No API key or '
    'URL change is needed.';

/// The gateway's own rejection string ("Invalid API Key!"). agentrouter.org
/// and co.agentrouter.org run SEPARATE key databases, so a valid-looking
/// key from the wrong console is rejected exactly like a dead one.
bool looksLikeInvalidApiKey(String body) =>
    body.toLowerCase().contains('invalid api key');

/// Actionable guidance for [looksLikeInvalidApiKey].
String agentRouterInvalidKeyMessage() =>
    'AgentRouter rejected this API key ("Invalid API Key"). agentrouter.org '
    'and co.agentrouter.org are separate deployments with separate key '
    'databases — generate the key on the same host you are calling and '
    'check that it is still active.';

/// Confirmed wire protocol per (normalized base URL, model family).
enum _WireProtocol { anthropic, openAi }

/// Streaming client for AgentRouter: Anthropic Messages protocol with an
/// automatic OpenAI-compatible fallback. See the library doc comment.
class AgentRouterLlmClient extends LlmClient {
  // `client` must be forwarded to the super constructor AND mirrored into
  // `_injected` below — one parameter, two destinations, so it cannot be a
  // plain super parameter.
  // ignore: use_super_parameters
  AgentRouterLlmClient({http.Client? client})
    : _injected = client,
      super(client: client, extraHeaders: _userAgentForUrl);

  /// Mirrors the base class's private injected-transport field so the
  /// Anthropic path reuses the same test double the OpenAI path gets.
  final http.Client? _injected;

  /// Confirmed wire protocol per `base|family` key: an entry means the
  /// gateway answered a REAL turn through that protocol — later calls for
  /// the same family skip the first-choice guessing entirely.
  static final Map<String, _WireProtocol> _confirmedProtocol =
      <String, _WireProtocol>{};

  static String _protocolCacheKey(String base, bool anthropicFirst) =>
      '$base|${anthropicFirst ? 'anthropic-first' : 'openai-first'}';

  /// Test hook: clears the confirmed-protocol cache.
  static void clearProtocolCache() => _confirmedProtocol.clear();

  @override
  Future<AssistantTurn> complete({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    void Function(String delta)? onDelta,
    bool Function()? shouldAbort,
    Object? cancelKey,
  }) async {
    // Validated on EVERY call — special treatment only when the host of
    // the resolved base URL strictly passes [isAgentRouterHost].
    final String? host = hostOf(config.baseUrl);
    if (host == null || !isAgentRouterHost(host)) {
      return super.complete(
        config: config,
        messages: messages,
        tools: tools,
        onDelta: onDelta,
        shouldAbort: shouldAbort,
        cancelKey: cancelKey,
      );
    }
    final String base = normalizeAgentRouterBase(config.baseUrl);
    // Both official paths are served under the version segment; hand the
    // normalized base to the OpenAI path too (super builds
    // `{base}/chat/completions`).
    final LlmConfig normalized = LlmConfig(
      baseUrl: base,
      apiKey: config.apiKey,
      model: config.model,
      maxTokens: config.maxTokens,
    );
    final bool anthropicFirst = prefersAnthropic(config.model);
    final String cacheKey = _protocolCacheKey(base, anthropicFirst);
    final _WireProtocol? confirmed = _confirmedProtocol[cacheKey];
    if (confirmed == _WireProtocol.openAi) {
      return _completeOpenAi(
        config: normalized,
        messages: messages,
        tools: tools,
        onDelta: onDelta,
        shouldAbort: shouldAbort,
        cancelKey: cancelKey,
        allowFallback: false,
        cacheKey: cacheKey,
      );
    }
    if (confirmed == _WireProtocol.anthropic) {
      return _completeAnthropic(
        config: normalized,
        base: base,
        messages: messages,
        tools: tools,
        onDelta: onDelta,
        shouldAbort: shouldAbort,
        cancelKey: cancelKey,
        allowFallback: false,
        cacheKey: cacheKey,
      );
    }
    return anthropicFirst
        ? _completeAnthropic(
            config: normalized,
            base: base,
            messages: messages,
            tools: tools,
            onDelta: onDelta,
            shouldAbort: shouldAbort,
            cancelKey: cancelKey,
            allowFallback: true,
            cacheKey: cacheKey,
          )
        : _completeOpenAi(
            config: normalized,
            messages: messages,
            tools: tools,
            onDelta: onDelta,
            shouldAbort: shouldAbort,
            cancelKey: cancelKey,
            allowFallback: true,
            cacheKey: cacheKey,
          );
  }

  /// Brands every agentrouter-host request of the OpenAI-compatible
  /// fallback path with the required User-Agent (the Anthropic path sets
  /// it on its own request builder). Plain LlmClient instances and other
  /// hosts get no extra headers, keeping the base behavior untouched.
  static Map<String, String> _userAgentForUrl(Uri url) {
    if (isAgentRouterHost(url.host)) {
      return const <String, String>{'User-Agent': kAgentRouterUserAgent};
    }
    return const <String, String>{};
  }

  /// The OpenAI-compatible path IS the base transport — same request
  /// building, SSE parsing, retry semantics — with the AgentRouter
  /// User-Agent merged in via the constructor-injected header hook. A
  /// successful turn confirms the protocol for this (base, family) pair;
  /// 404/405 falls back once to the Anthropic path when allowed; WAF
  /// pages and key/deployment mismatches become actionable errors.
  Future<AssistantTurn> _completeOpenAi({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    void Function(String delta)? onDelta,
    bool Function()? shouldAbort,
    Object? cancelKey,
    required bool allowFallback,
    required String cacheKey,
  }) async {
    try {
      final AssistantTurn turn = await super.complete(
        config: config,
        messages: messages,
        tools: tools,
        onDelta: onDelta,
        shouldAbort: shouldAbort,
        cancelKey: cancelKey,
      );
      _confirmedProtocol[cacheKey] = _WireProtocol.openAi;
      return turn;
    } on LlmException catch (e) {
      // Non-200 errors embed the body snippet; parse failures embed it
      // too (the base transport includes the raw body since v1.49.3) —
      // which is exactly what makes WAF/invalid-key detection possible
      // on this path.
      if (looksLikeWafChallenge(e.message)) {
        throw LlmException(agentRouterWafMessage(), statusCode: e.statusCode);
      }
      if (looksLikeInvalidApiKey(e.message)) {
        throw LlmException(
          agentRouterInvalidKeyMessage(),
          statusCode: e.statusCode,
        );
      }
      if (allowFallback && (e.statusCode == 404 || e.statusCode == 405)) {
        return _completeAnthropic(
          config: config,
          base: normalizeBaseUrl(config.baseUrl),
          messages: messages,
          tools: tools,
          onDelta: onDelta,
          shouldAbort: shouldAbort,
          cancelKey: cancelKey,
          allowFallback: false,
          cacheKey: cacheKey,
        );
      }
      rethrow;
    }
  }

  Future<AssistantTurn> _completeAnthropic({
    required LlmConfig config,
    required String base,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    void Function(String delta)? onDelta,
    bool Function()? shouldAbort,
    Object? cancelKey,
    required bool allowFallback,
    required String cacheKey,
  }) async {
    if (shouldAbort?.call() ?? false) {
      throw const LlmAbortedException('');
    }
    final Uri url = Uri.parse('$base/messages');
    final Map<String, dynamic> body = buildAnthropicRequestBody(
      config: config,
      messages: messages,
      tools: tools,
    );

    final http.Client callClient = _injected ?? http.Client();
    final bool ownsClient = _injected == null;
    // Same per-run registry as the base transport: force-stop hard-closes
    // this request exactly like an OpenAI-compatible one.
    if (cancelKey != null) LlmClient.registerLiveStream(cancelKey, callClient);
    try {
      final http.StreamedResponse response;
      try {
        response = await callClient.send(
          await _buildAnthropicRequest(config, url, body),
        );
      } catch (e) {
        // Transport errors must NOT silently fall back: re-sending the
        // same turn over a second protocol after a real network failure
        // risks duplicate outputs. Surface it like the base client does.
        throw LlmException('Could not connect to provider: $e');
      }

      if (response.statusCode == 404 || response.statusCode == 405) {
        // No /messages endpoint on this base: OpenAI-compatible gateway.
        if (allowFallback) {
          // await — the finally below must run AFTER the fallback turn is
          // fully consumed, not when its Future is merely returned.
          return await _completeOpenAi(
            config: config,
            messages: messages,
            tools: tools,
            onDelta: onDelta,
            shouldAbort: shouldAbort,
            cancelKey: cancelKey,
            allowFallback: false,
            cacheKey: cacheKey,
          );
        }
        // The confirmed route suddenly 404s — surface a hard error. The
        // two-way fallback is strictly one-shot: never flip back and
        // forth (guard anti-loop).
        throw LlmException(
          'HTTP ${response.statusCode}: /messages unavailable on $base',
          statusCode: response.statusCode,
        );
      }

      if (response.statusCode != 200) {
        final String raw = await response.stream.bytesToString();
        // Auth/API errors keep the provider's own message — these NEVER
        // trigger a protocol fallback (only 404/405 above may).
        throw agentRouterHttpError(raw, response.statusCode);
      }

      final String contentType = (response.headers['content-type'] ?? '')
          .toLowerCase();
      if (!contentType.contains('text/event-stream')) {
        final String raw = await response.stream.bytesToString();
        if (looksLikeWafChallenge(raw)) {
          throw LlmException(agentRouterWafMessage());
        }
        if (looksLikeInvalidApiKey(raw)) {
          throw LlmException(agentRouterInvalidKeyMessage());
        }
        final Object? decoded = _tryDecode(raw);
        if (decoded is Map<String, dynamic> && decoded['choices'] is List) {
          // OpenAI-shaped answer on the Anthropic endpoint: consume THIS
          // response (no re-send — no duplicate output) and remember the
          // protocol for the following calls.
          _confirmedProtocol[cacheKey] = _WireProtocol.openAi;
          return _parseOpenAiMessage(raw);
        }
        _confirmedProtocol[cacheKey] = _WireProtocol.anthropic;
        return _parseAnthropicMessage(raw);
      }

      _confirmedProtocol[cacheKey] = _WireProtocol.anthropic;
      return await _parseAnthropicSse(response, onDelta, shouldAbort);
    } finally {
      if (cancelKey != null) {
        LlmClient.unregisterLiveStream(cancelKey, callClient);
      }
      if (ownsClient) {
        try {
          callClient.close();
        } catch (_) {
          // Never let transport cleanup mask the actual result.
        }
      }
    }
  }

  Future<http.Request> _buildAnthropicRequest(
    LlmConfig config,
    Uri url,
    Map<String, dynamic> body,
  ) async => http.Request('POST', url)
    ..headers['x-api-key'] = config.apiKey
    ..headers['Authorization'] = 'Bearer ${config.apiKey}'
    ..headers['anthropic-version'] = kAnthropicVersion
    ..headers['Content-Type'] = 'application/json'
    ..headers['Accept'] = 'text/event-stream'
    ..headers['User-Agent'] = kAgentRouterUserAgent
    // Encoded OFF the UI isolate — same rationale as the base transport.
    ..body = await Isolate.run(() => jsonEncode(body));

  /// Anthropic SSE consumption. Mirrors the robustness of the base
  /// `_parseSse`: line-buffered, CRLF-tolerant, malformed JSON events are
  /// ignored, Stop aborts mid-stream keeping the partial text.
  Future<AssistantTurn> _parseAnthropicSse(
    http.StreamedResponse response,
    void Function(String delta)? onDelta,
    bool Function()? shouldAbort,
  ) async {
    final StringBuffer contentBuffer = StringBuffer();
    final Map<int, _AnthropicToolBlock> toolBlocks =
        <int, _AnthropicToolBlock>{};
    int? inputTokens;
    int? outputTokens;
    var lineBuffer = '';
    var done = false;
    var aborted = false;

    try {
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        // Stop must interrupt DURING generation: bail out of the stream at
        // the first chance, cancelling the HTTP subscription with it.
        if (shouldAbort?.call() ?? false) {
          aborted = true;
          break;
        }
        lineBuffer += chunk;
        while (true) {
          final int newlineIndex = lineBuffer.indexOf('\n');
          if (newlineIndex < 0) break;
          // trim() also strips the '\r' of CRLF line endings.
          final String line = lineBuffer.substring(0, newlineIndex).trim();
          lineBuffer = lineBuffer.substring(newlineIndex + 1);

          if (line.isEmpty || line.startsWith(':')) continue;
          // `event:`/`id:` lines carry no payload — the JSON itself has
          // the event `type`.
          if (!line.startsWith('data:')) continue;
          final String data = line.substring(5).trim();
          if (data.isEmpty) continue;
          if (data == '[DONE]') {
            done = true;
            break;
          }

          final Object? decoded = _tryDecode(data);
          if (decoded is! Map<String, dynamic>) continue; // malformed JSON
          final String type = decoded['type']?.toString() ?? '';

          if (type == 'error') {
            if (looksLikeWafChallenge(data)) {
              throw LlmException(agentRouterWafMessage());
            }
            if (looksLikeInvalidApiKey(data)) {
              throw LlmException(agentRouterInvalidKeyMessage());
            }
            throw LlmException(anthropicErrorMessage(data));
          }

          if (type == 'message_start') {
            final Map<String, dynamic>? message = _asMap(decoded['message']);
            final Map<String, dynamic>? usage = _asMap(message?['usage']);
            if (usage != null) {
              inputTokens = _asInt(usage['input_tokens']) ?? inputTokens;
              outputTokens = _asInt(usage['output_tokens']) ?? outputTokens;
            }
          } else if (type == 'content_block_start') {
            final int index = _asInt(decoded['index']) ?? toolBlocks.length;
            final Map<String, dynamic>? block = _asMap(
              decoded['content_block'],
            );
            // Tool call id/name arrive ONLY here; arguments come later via
            // input_json_delta accumulation.
            if (block != null && block['type']?.toString() == 'tool_use') {
              toolBlocks[index] = _AnthropicToolBlock(
                id: block['id']?.toString(),
                name: block['name']?.toString(),
              );
            }
          } else if (type == 'content_block_delta') {
            final Map<String, dynamic>? delta = _asMap(decoded['delta']);
            if (delta == null) continue;
            final String deltaType = delta['type']?.toString() ?? '';
            if (deltaType == 'text_delta') {
              final String text = delta['text']?.toString() ?? '';
              if (text.isNotEmpty) {
                contentBuffer.write(text);
                onDelta?.call(text);
              }
            } else if (deltaType == 'input_json_delta') {
              final int index = _asInt(decoded['index']) ?? 0;
              toolBlocks
                  .putIfAbsent(index, _AnthropicToolBlock.new)
                  .arguments
                  .write(delta['partial_json']?.toString() ?? '');
            }
          } else if (type == 'message_delta') {
            final Map<String, dynamic>? usage = _asMap(decoded['usage']);
            if (usage != null) {
              inputTokens = _asInt(usage['input_tokens']) ?? inputTokens;
              outputTokens = _asInt(usage['output_tokens']) ?? outputTokens;
            }
            // delta.stop_reason is informational: the turn shape (content
            // + tool calls) already tells the agent loop what happened.
          } else if (type == 'message_stop') {
            done = true;
          }
          // 'content_block_stop' and 'ping' need no handling.
        }
        if (done) break;
      }
    } on LlmException {
      rethrow;
    } catch (e) {
      // A dropped socket mid-stream must not crash the app: keep partial
      // plain-text content, but never return half-received tool calls
      // (their JSON arguments would be truncated and unusable).
      if (toolBlocks.isEmpty && contentBuffer.isNotEmpty) {
        return AssistantTurn(content: contentBuffer.toString());
      }
      throw LlmException('Connection lost while streaming: $e');
    }
    if (aborted) {
      throw LlmAbortedException(contentBuffer.toString());
    }

    final List<int> indexes = toolBlocks.keys.toList()..sort();
    return AssistantTurn(
      content: contentBuffer.toString(),
      usage: (inputTokens != null || outputTokens != null)
          ? TokenUsage(
              promptTokens: inputTokens ?? 0,
              completionTokens: outputTokens ?? 0,
            )
          : null,
      toolCalls: <ToolCallRequest>[
        for (final int index in indexes)
          if (toolBlocks[index]!.hasName) toolBlocks[index]!.toRequest(),
      ],
    );
  }

  /// Full (non-SSE) Anthropic message:
  /// `{content:[{type:'text'|'tool_use',...}],usage,stop_reason}`.
  AssistantTurn _parseAnthropicMessage(String raw) {
    final Object? decoded = _tryDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw LlmException('Unknown response format: ${truncateForError(raw)}');
    }
    final StringBuffer text = StringBuffer();
    final List<ToolCallRequest> toolCalls = <ToolCallRequest>[];
    final Object? content = decoded['content'];
    if (content is List) {
      for (final Object? block in content) {
        if (block is! Map<String, dynamic>) continue;
        final String type = block['type']?.toString() ?? '';
        if (type == 'text') {
          text.write(block['text']?.toString() ?? '');
        } else if (type == 'tool_use') {
          final String name = block['name']?.toString() ?? '';
          // A glitched entry (missing name) must not crash the app.
          if (name.isEmpty) continue;
          final String id = block['id']?.toString() ?? '';
          toolCalls.add(
            ToolCallRequest(
              id: id.isEmpty ? newCallId() : id,
              name: name,
              argumentsJson: jsonEncode(
                _asMap(block['input']) ?? <String, dynamic>{},
              ),
            ),
          );
        }
      }
    }
    final Map<String, dynamic>? usage = _asMap(decoded['usage']);
    final int? input = _asInt(usage?['input_tokens']);
    final int? output = _asInt(usage?['output_tokens']);
    return AssistantTurn(
      content: text.toString(),
      toolCalls: toolCalls,
      usage: (input != null || output != null)
          ? TokenUsage(promptTokens: input ?? 0, completionTokens: output ?? 0)
          : null,
    );
  }

  /// OpenAI-shaped JSON that arrived on the Anthropic endpoint — parsed
  /// exactly like the base transport's non-streaming parser would.
  AssistantTurn _parseOpenAiMessage(String raw) {
    final Object? decoded = _tryDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw LlmException('Unknown response format: ${truncateForError(raw)}');
    }
    final Object? choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final Object? first = choices.first;
      if (first is Map<String, dynamic>) {
        final Object? message = first['message'];
        if (message is Map<String, dynamic>) {
          return AssistantTurn(
            content: message['content']?.toString() ?? '',
            toolCalls: _parseFullOpenAiToolCalls(message['tool_calls']),
            usage: TokenUsage.fromJson(decoded['usage']),
          );
        }
      }
    }
    throw LlmException('Unknown response format: ${truncateForError(raw)}');
  }

  List<ToolCallRequest> _parseFullOpenAiToolCalls(Object? rawToolCalls) {
    if (rawToolCalls is! List) return const <ToolCallRequest>[];
    final List<ToolCallRequest> out = <ToolCallRequest>[];
    for (final Object? raw in rawToolCalls) {
      if (raw is! Map<String, dynamic>) continue;
      final Object? function = raw['function'];
      if (function is! Map<String, dynamic>) continue;
      final Object? name = function['name'];
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
}

/// Extracts the provider's own error message from an Anthropic-shaped
/// error payload (`{"type":"error","error":{"type":...,"message":...}}`);
/// falls back to the truncated raw body.
String anthropicErrorMessage(String raw) {
  final Object? decoded = _tryDecode(raw);
  if (decoded is Map<String, dynamic>) {
    final Object? error = decoded['error'];
    if (error is Map<String, dynamic>) {
      final String message = error['message']?.toString() ?? '';
      if (message.isNotEmpty) return message;
    }
  }
  return truncateForError(raw);
}

/// Non-200 on an AgentRouter path: WAF challenges and key/deployment
/// mismatches become actionable errors; everything else keeps the
/// provider's own error text (Anthropic-shaped payloads are unwrapped).
LlmException agentRouterHttpError(String raw, int statusCode) {
  if (looksLikeWafChallenge(raw)) {
    return LlmException(agentRouterWafMessage(), statusCode: statusCode);
  }
  if (looksLikeInvalidApiKey(raw)) {
    return LlmException(agentRouterInvalidKeyMessage(), statusCode: statusCode);
  }
  return LlmException(
    'HTTP $statusCode: ${anthropicErrorMessage(raw)}',
    statusCode: statusCode,
  );
}

/// Builds the Anthropic Messages request body from the app's OpenAI-style
/// wire messages. Pure function — unit-tested directly.
///
/// Mapping:
/// * all `system` messages join with '\n\n' into the top-level `system`
///   string (omitted when there are none);
/// * `user` string content becomes a single text block; array content maps
///   text parts to text blocks and `image_url` data URIs to base64 image
///   blocks (non-data URLs degrade to a text placeholder — never a crash);
/// * `assistant` text becomes a text block and each `tool_calls` entry a
///   `tool_use` block with `input` = the decoded arguments JSON;
/// * each `tool` message becomes its own `user` message carrying one
///   `tool_result` block.
Map<String, dynamic> buildAnthropicRequestBody({
  required LlmConfig config,
  required List<Map<String, dynamic>> messages,
  List<Map<String, dynamic>>? tools,
}) {
  final List<String> systemParts = <String>[];
  final List<Map<String, dynamic>> anthropicMessages = <Map<String, dynamic>>[];

  for (final Map<String, dynamic> message in messages) {
    final String role = message['role']?.toString() ?? '';
    if (role == 'system') {
      systemParts.add(_contentToText(message['content']));
    } else if (role == 'tool') {
      anthropicMessages.add(<String, dynamic>{
        'role': 'user',
        'content': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'tool_result',
            'tool_use_id': message['tool_call_id']?.toString() ?? '',
            'content': _contentToText(message['content']),
          },
        ],
      });
    } else if (role == 'assistant') {
      final List<Map<String, dynamic>> blocks = <Map<String, dynamic>>[];
      final String text = _contentToText(message['content']);
      if (text.isNotEmpty) {
        blocks.add(<String, dynamic>{'type': 'text', 'text': text});
      }
      final Object? toolCalls = message['tool_calls'];
      if (toolCalls is List) {
        for (final Object? raw in toolCalls) {
          if (raw is! Map<String, dynamic>) continue;
          final Object? function = raw['function'];
          if (function is! Map<String, dynamic>) continue;
          final String name = function['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          final String id = raw['id']?.toString() ?? '';
          blocks.add(<String, dynamic>{
            'type': 'tool_use',
            'id': id.isEmpty ? newCallId() : id,
            'name': name,
            'input': _decodeArguments(function['arguments']),
          });
        }
      }
      if (blocks.isNotEmpty) {
        anthropicMessages.add(<String, dynamic>{
          'role': 'assistant',
          'content': blocks,
        });
      }
    } else {
      anthropicMessages.add(<String, dynamic>{
        'role': 'user',
        'content': _userContentBlocks(message['content']),
      });
    }
  }

  return <String, dynamic>{
    'model': config.model,
    // Anthropic REQUIRES max_tokens — config override or the default cap.
    'max_tokens': config.maxTokens ?? kAgentRouterMaxTokens,
    'stream': true,
    if (systemParts.isNotEmpty) 'system': systemParts.join('\n\n'),
    'messages': anthropicMessages,
    if (tools != null && tools.isNotEmpty)
      'tools': <Map<String, dynamic>>[
        for (final Map<String, dynamic> tool in tools)
          _anthropicToolSchema(tool),
      ],
  };
}

String _contentToText(Object? content) {
  if (content is String) return content;
  if (content is List) {
    // Concatenate the text parts of array-shaped content.
    final StringBuffer buffer = StringBuffer();
    for (final Object? part in content) {
      if (part is Map<String, dynamic>) {
        final Object? text = part['text'];
        if (text != null) buffer.write(text.toString());
      } else if (part is String) {
        buffer.write(part);
      }
    }
    return buffer.toString();
  }
  return content?.toString() ?? '';
}

List<Map<String, dynamic>> _userContentBlocks(Object? content) {
  if (content is List) {
    final List<Map<String, dynamic>> blocks = <Map<String, dynamic>>[];
    for (final Object? part in content) {
      final Map<String, dynamic>? block = _userContentBlock(part);
      if (block != null) blocks.add(block);
    }
    if (blocks.isNotEmpty) return blocks;
  }
  // String (or unusable) content: a single text block.
  return <Map<String, dynamic>>[
    <String, dynamic>{'type': 'text', 'text': _contentToText(content)},
  ];
}

Map<String, dynamic>? _userContentBlock(Object? part) {
  if (part is String) {
    return <String, dynamic>{'type': 'text', 'text': part};
  }
  if (part is! Map<String, dynamic>) return null;
  final String type = part['type']?.toString() ?? '';
  if (type == 'image_url') {
    final Object? imageUrl = part['image_url'];
    final String? url = imageUrl is Map<String, dynamic>
        ? imageUrl['url']?.toString()
        : (imageUrl is String ? imageUrl : null);
    final RegExpMatch? dataUri = url == null
        ? null
        : _dataUriPattern.firstMatch(url);
    if (dataUri != null) {
      return <String, dynamic>{
        'type': 'image',
        'source': <String, dynamic>{
          'type': 'base64',
          'media_type': dataUri.group(1)!,
          'data': dataUri.group(2)!,
        },
      };
    }
    // Anthropic accepts no remote image URL here: keep the URL text as a
    // placeholder instead of crashing.
    return <String, dynamic>{'type': 'text', 'text': url ?? ''};
  }
  final Object? text = part['text'];
  if (text != null) {
    return <String, dynamic>{'type': 'text', 'text': text.toString()};
  }
  return null;
}

final RegExp _dataUriPattern = RegExp(
  r'^data:([^;,]+);base64,(.+)$',
  dotAll: true,
);

/// OpenAI tool definition
/// (`{type:'function',function:{name,description,parameters}}`) → Anthropic
/// tool schema (`{name,description,input_schema}`).
Map<String, dynamic> _anthropicToolSchema(Map<String, dynamic> tool) {
  final Object? function = tool['function'];
  final Map<String, dynamic> fn = function is Map<String, dynamic>
      ? function
      : <String, dynamic>{};
  final Object? parameters = fn['parameters'];
  return <String, dynamic>{
    'name': fn['name']?.toString() ?? '',
    'description': fn['description']?.toString() ?? '',
    // Anthropic requires a JSON schema; an absent one degrades to the
    // empty object schema instead of breaking the request.
    'input_schema': parameters is Map<String, dynamic>
        ? parameters
        : <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
  };
}

Map<String, dynamic> _decodeArguments(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    final Object? decoded = _tryDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  }
  // Malformed arguments must not break the whole request.
  return <String, dynamic>{};
}

Object? _tryDecode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _asMap(Object? raw) =>
    raw is Map<String, dynamic> ? raw : null;

int? _asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

String truncateForError(String text, [int max = 300]) =>
    text.length <= max ? text : '${text.substring(0, max)}...';

/// Accumulator for one Anthropic `tool_use` content block: id/name arrive
/// in `content_block_start`, the arguments JSON accumulates from
/// `input_json_delta` chunks.
class _AnthropicToolBlock {
  _AnthropicToolBlock({this.id, this.name});

  final String? id;
  final String? name;
  final StringBuffer arguments = StringBuffer();

  bool get hasName => name != null && name!.isNotEmpty;

  ToolCallRequest toRequest() => ToolCallRequest(
    id: (id == null || id!.isEmpty) ? newCallId() : id!,
    name: name!,
    argumentsJson: arguments.toString(),
  );
}
