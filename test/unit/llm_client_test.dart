import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zagents/services/llm_client.dart';

const LlmConfig _config = LlmConfig(
  baseUrl: 'https://provider.test/v1',
  apiKey: 'test-key',
  model: 'test-model',
);

void main() {
  test('parses SSE stream: content deltas + tool call accumulation', () async {
    final String sse = <String>[
      'data: {"choices":[{"delta":{"role":"assistant","content":"Hello"}}]}',
      '',
      'data: {"choices":[{"delta":{"content":" world"}}]}',
      '',
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"browser_navigate","arguments":""}}]}}]}',
      '',
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"url\\":\\"https://example.com\\"}"}}]}}]}',
      '',
      'data: [DONE]',
      '',
    ].join('\n');

    final http.Client mockClient = MockClient.streaming(
      (http.BaseRequest request, http.ByteStream bodyStream) async =>
          http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(sse)),
            200,
            headers: <String, String>{'content-type': 'text/event-stream'},
          ),
    );
    final LlmClient client = LlmClient(client: mockClient);

    final List<String> deltas = <String>[];
    final AssistantTurn turn = await client.complete(
      config: _config,
      messages: const <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': 'hi'},
      ],
      onDelta: deltas.add,
    );

    expect(deltas.join(), 'Hello world');
    expect(turn.content, 'Hello world');
    expect(turn.toolCalls, hasLength(1));
    expect(turn.toolCalls.first.name, 'browser_navigate');
    expect(turn.toolCalls.first.id, 'call_1');
    expect(turn.toolCalls.first.args['url'], 'https://example.com');
  });

  test('falls back to plain JSON when provider ignores stream=true', () async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'message': <String, dynamic>{
            'role': 'assistant',
            'content': 'Plain answer',
            'tool_calls': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'tc_9',
                'type': 'function',
                'function': <String, dynamic>{
                  'name': 'write_file',
                  'arguments': '{"path":"a.txt","content":"hi"}',
                },
              },
            ],
          },
        },
      ],
    };

    final http.Client mockClient = MockClient(
      (http.BaseRequest request) async => http.Response(
        jsonEncode(payload),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      ),
    );
    final LlmClient client = LlmClient(client: mockClient);

    final AssistantTurn turn = await client.complete(
      config: _config,
      messages: const <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': 'hi'},
      ],
    );

    expect(turn.content, 'Plain answer');
    expect(turn.toolCalls.single.name, 'write_file');
    expect(turn.toolCalls.single.args['path'], 'a.txt');
  });

  test('throws LlmException on HTTP error', () async {
    final http.Client mockClient = MockClient(
      (http.BaseRequest request) async =>
          http.Response('{"error":"invalid api key"}', 401),
    );
    final LlmClient client = LlmClient(client: mockClient);

    await expectLater(
      client.complete(
        config: _config,
        messages: const <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': 'hi'},
        ],
      ),
      throwsA(isA<LlmException>()),
    );
  });

  test('ToolCallRequest.args tolerates malformed JSON', () {
    final ToolCallRequest request = ToolCallRequest(
      id: 'x',
      name: 'browser_click',
      argumentsJson: '{not json',
    );
    expect(request.args, isEmpty);
  });
}
