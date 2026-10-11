import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/l10n/app_strings.dart';
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

  test('openChat on a corrupted session file never crashes', () async {
    final ProviderContainer container = await _container(<AssistantTurn>[
      AssistantTurn(content: 'ok'),
    ], tempDir);
    final Directory chatsDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}chats',
    );
    chatsDir.createSync(recursive: true);
    await File('${chatsDir.path}${Platform.pathSeparator}corrupt.json')
        .writeAsString('{not valid json!!');

    // Must not throw, even though the file cannot be parsed.
    await container
        .read(chatControllerProvider.notifier)
        .openChat(
          ChatSummary(
            id: 'corrupt',
            title: 'Broken',
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
    final ChatState state = container.read(chatControllerProvider);
    expect(state.sessionId, 'corrupt');
    expect(state.messages, isEmpty);
  });

  test('openChat storage failure is converted to an error, no crash', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        ...testOverrides(
          llm: FakeLlmClient(<AssistantTurn>[AssistantTurn(content: 'ok')]),
          dir: tempDir,
          settings: AppSettings(apiKey: 'test-key'),
        ),
        chatStoreProvider.overrideWithValue(ThrowingChatStore()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(chatControllerProvider.notifier)
        .openChat(
          ChatSummary(
            id: 'any',
            title: 'Any',
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
    final ChatState state = container.read(chatControllerProvider);
    expect(state.error, 'Could not open this conversation.');
  });

  test(
    'deleteChat storage failure is converted to an error, no crash',
    () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          ...testOverrides(
            llm: FakeLlmClient(<AssistantTurn>[AssistantTurn(content: 'ok')]),
            dir: tempDir,
            settings: AppSettings(apiKey: 'test-key'),
          ),
          chatStoreProvider.overrideWithValue(ThrowingChatStore()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(chatControllerProvider.notifier).deleteChat('x');
      final ChatState state = container.read(chatControllerProvider);
      expect(state.error, 'Could not delete this conversation.');
    },
  );

  test('background hold starts and stops around the agent loop', () async {
    final RecordingBackgroundRun background = RecordingBackgroundRun();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        ...testOverrides(
          llm: FakeLlmClient(<AssistantTurn>[
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
            AssistantTurn(content: 'done'),
          ]),
          dir: tempDir,
          settings: AppSettings(apiKey: 'k'),
        ),
        backgroundRunServiceProvider.overrideWithValue(background),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).send('go');

    // Started with the localized notification strings…
    expect(
      background.calls.first,
      'start:${appStringsFor('en').notifTitle}'
      '|${appStringsFor('en').notifProcessing}',
    );
    // …received a live per-step update while the tool ran…
    expect(
      background.calls,
      contains(
        'update:${appStringsFor('en').notifStep(1, 'browser_navigate')}',
      ),
    );
    // …and was always released, even on success.
    expect(background.calls.last, 'stop');
    expect(background.isActive, isFalse);
  });

  test('background hold is released even when the LLM throws', () async {
    final RecordingBackgroundRun background = RecordingBackgroundRun();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        ...testOverrides(
          llm: _ThrowingLlmClient(),
          dir: tempDir,
          settings: AppSettings(apiKey: 'k'),
        ),
        backgroundRunServiceProvider.overrideWithValue(background),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).send('boom');

    final ChatState state = container.read(chatControllerProvider);
    expect(state.isRunning, isFalse);
    expect(state.error, isNotNull);
    expect(background.calls.first, startsWith('start:'));
    expect(background.calls.last, 'stop');
  });

  test('runInBackground=false never touches the background service', () async {
    final RecordingBackgroundRun background = RecordingBackgroundRun();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        ...testOverrides(
          llm: FakeLlmClient(<AssistantTurn>[AssistantTurn(content: 'ok')]),
          dir: tempDir,
          settings: AppSettings(apiKey: 'k', runInBackground: false),
        ),
        backgroundRunServiceProvider.overrideWithValue(background),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).send('plain');
    expect(background.calls, isEmpty);
  });
}

/// LLM fake whose complete() always throws — proves the controller
/// releases the background hold on the error path.
class _ThrowingLlmClient implements LlmClient {
  @override
  Future<AssistantTurn> complete({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    void Function(String delta)? onDelta,
  }) async => throw const SocketException('provider unreachable');
}
