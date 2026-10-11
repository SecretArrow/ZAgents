import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/agent_controller.dart';
import 'package:zagents/services/llm_client.dart';

import '../fakes/fakes.dart';

Future<ProviderContainer> _container(
  List<AssistantTurn> turns,
  Directory dir, {
  AppSettings? settings,
}) async {
  final ProviderContainer container = ProviderContainer(
    overrides: testOverrides(
      llm: FakeLlmClient(turns),
      dir: dir,
      settings: settings ?? AppSettings(apiKey: 'test-key'),
    ),
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_agent_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('agent loop: executes tool then produces final answer', () async {
    final ProviderContainer container = await _container(<AssistantTurn>[
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 't1',
            name: 'browser_navigate',
            argumentsJson: jsonEncode(<String, dynamic>{
              'url': 'https://example.com',
            }),
          ),
        ],
      ),
      AssistantTurn(content: 'Halaman dibuka: Example Domain'),
    ], tempDir);

    await container
        .read(chatControllerProvider.notifier)
        .send('Buka example.com');
    final ChatState state = container.read(chatControllerProvider);

    expect(state.isRunning, isFalse);
    expect(state.error, isNull);
    expect(state.messages.first.role, Role.user);
    expect(state.messages.first.content, 'Buka example.com');

    final List<ChatMessage> assistant = state.messages
        .where((m) => m.role == Role.assistant)
        .toList();
    expect(assistant, hasLength(2));
    expect(assistant.first.toolCalls.single.status, ToolStatus.success);
    expect(
      assistant.first.toolCalls.single.resultText,
      contains('Example Domain'),
    );
    expect(assistant.last.content, 'Halaman dibuka: Example Domain');
  });

  test('agent loop: write_file then read_file roundtrip', () async {
    final ProviderContainer container = await _container(<AssistantTurn>[
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 'w1',
            name: 'write_file',
            argumentsJson: jsonEncode(<String, dynamic>{
              'path': 'notes/todo.txt',
              'content': 'belajar flutter',
            }),
          ),
        ],
      ),
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 'r1',
            name: 'read_file',
            argumentsJson: jsonEncode(<String, dynamic>{
              'path': 'notes/todo.txt',
            }),
          ),
        ],
      ),
      AssistantTurn(content: 'File tersimpan dan terbaca.'),
    ], tempDir);

    await container
        .read(chatControllerProvider.notifier)
        .send('Simpan catatan');
    final ChatState state = container.read(chatControllerProvider);
    final List<ChatMessage> assistant = state.messages
        .where((m) => m.role == Role.assistant)
        .toList();

    expect(assistant[0].toolCalls.single.status, ToolStatus.success);
    expect(assistant[1].toolCalls.single.status, ToolStatus.success);
    expect(
      assistant[1].toolCalls.single.resultText,
      contains('belajar flutter'),
    );

    final File file = File('${tempDir.path}/notes/todo.txt');
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), 'belajar flutter');
  });

  test('send without API key surfaces a friendly error', () async {
    final ProviderContainer container = await _container(
      <AssistantTurn>[AssistantTurn(content: 'tidak boleh dipanggil')],
      tempDir,
      settings: AppSettings(apiKey: ''),
    );

    await container.read(chatControllerProvider.notifier).send('Halo');
    final ChatState state = container.read(chatControllerProvider);

    expect(state.isRunning, isFalse);
    expect(state.error, contains('API key'));
    expect(state.messages, isEmpty); // rejected before appending anything
  });

  test('maxSteps bounds the number of LLM turns', () async {
    final FakeLlmClient fake = FakeLlmClient(<AssistantTurn>[
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 'loop',
            name: 'browser_extract_text',
            argumentsJson: '{}',
          ),
        ],
      ),
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: testOverrides(
        llm: fake,
        dir: tempDir,
        settings: AppSettings(apiKey: 'k', maxSteps: 2),
      ),
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).send('loop terus');
    expect(fake.calls, hasLength(2)); // exactly maxSteps turns
    final ChatState state = container.read(chatControllerProvider);
    expect(state.isRunning, isFalse);
    expect(state.error, isNull);
  });
}
