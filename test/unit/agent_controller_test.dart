import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/agent_controller.dart';
import 'package:zagents/services/background_service.dart';
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

  test('maxSteps bounds the number of LLM turns (runUntilDone off)', () async {
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
        settings: AppSettings(apiKey: 'k', maxSteps: 2, runUntilDone: false),
      ),
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).send('loop terus');
    expect(fake.calls, hasLength(2)); // exactly maxSteps turns
    final ChatState state = container.read(chatControllerProvider);
    expect(state.isRunning, isFalse);
    expect(state.error, isNull);
  });

  test(
    'sending to an opened history chat continues it instead of forking',
    () async {
      final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
        AssistantTurn(content: 'first reply'),
      ]);
      final ProviderContainer container = ProviderContainer(
        overrides: testOverrides(
          llm: llm,
          dir: tempDir,
          settings: AppSettings(apiKey: 'k'),
        ),
      );
      addTearDown(container.dispose);

      // Turn 1 creates and persists session X.
      await container
          .read(chatControllerProvider.notifier)
          .send('first question');
      final String id = container.read(chatControllerProvider).sessionId!;
      expect(id, isNotNull);

      // Reopen it from history (the finished run is no longer tracked).
      await container
          .read(chatControllerProvider.notifier)
          .openChat(
            ChatSummary(
              id: id,
              title: 'first question',
              updatedAt: DateTime.now(),
            ),
          );
      expect(container.read(chatControllerProvider).sessionId, id);

      // Turn 2 must CONTINUE session X — same id, full history on the wire.
      await container
          .read(chatControllerProvider.notifier)
          .send('second question');
      final ChatState state = container.read(chatControllerProvider);
      expect(
        state.sessionId,
        id,
        reason: 'sending into an open chat must not fork a new session',
      );
      expect(
        state.messages.where((m) => m.role == Role.user).map((m) => m.content),
        containsAll(<String>['first question', 'second question']),
      );

      // The LLM wire for the second call replayed the earlier turn.
      final List<Map<String, dynamic>> wire = llm.calls.last;
      final List<String> userTexts = <String>[
        for (final Map<String, dynamic> m in wire)
          if (m['role'] == 'user') m['content'] as String,
      ];
      expect(userTexts, contains('first question'));
      expect(userTexts, contains('second question'));

      // Nothing new was stored: still exactly one conversation file.
      final List<ChatSummary> summaries = await container
          .read(chatStoreProvider)
          .listSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, id);
    },
  );

  test('restoreLastChat reopens the most recent conversation', () async {
    final ProviderContainer container = await _container(
      <AssistantTurn>[AssistantTurn(content: 'hi there')],
      tempDir,
      settings: AppSettings(apiKey: 'k'),
    );
    addTearDown(container.dispose);
    final notifier = container.read(chatControllerProvider.notifier);

    await notifier.send('hello world');
    final String id = container.read(chatControllerProvider).sessionId!;
    await notifier.newChat();
    expect(container.read(chatControllerProvider).sessionId, isNull);

    await notifier.restoreLastChat();
    expect(container.read(chatControllerProvider).sessionId, id);
    expect(container.read(chatControllerProvider).messages, isNotEmpty);
  });

  test(
    'restoreLastChat keeps the fresh draft when there is no history',
    () async {
      final ProviderContainer container = await _container(
        <AssistantTurn>[AssistantTurn(content: 'ok')],
        tempDir,
        settings: AppSettings(apiKey: 'k'),
      );
      addTearDown(container.dispose);

      await container.read(chatControllerProvider.notifier).restoreLastChat();
      final ChatState state = container.read(chatControllerProvider);
      expect(state.sessionId, isNull);
      expect(state.messages, isEmpty);
    },
  );

  test('runUntilDone ignores maxSteps and works to the final answer', () async {
    final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 't1',
            name: 'browser_extract_text',
            argumentsJson: '{}',
          ),
        ],
      ),
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 't2',
            name: 'browser_extract_text',
            argumentsJson: '{}',
          ),
        ],
      ),
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 't3',
            name: 'browser_extract_text',
            argumentsJson: '{}',
          ),
        ],
      ),
      AssistantTurn(content: 'task finished'),
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: testOverrides(
        llm: llm,
        dir: tempDir,
        // maxSteps=2 would normally cut the loop after two turns.
        settings: AppSettings(apiKey: 'k', maxSteps: 2, runUntilDone: true),
      ),
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).send('long task');
    expect(llm.calls, hasLength(4)); // 3 tool rounds + final answer
    final ChatState state = container.read(chatControllerProvider);
    expect(state.error, isNull);
    expect(state.messages.last.content, 'task finished');
    expect(state.messages.last.toolCalls, isEmpty);
  });

  test('maxSteps cap with runUntilDone=false appends a visible note', () async {
    final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
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
        llm: llm,
        dir: tempDir,
        settings: AppSettings(apiKey: 'k', maxSteps: 2, runUntilDone: false),
      ),
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).send('loop terus');
    expect(llm.calls, hasLength(2));
    final ChatState state = container.read(chatControllerProvider);
    expect(state.isRunning, isFalse);
    expect(state.error, isNull);
    // The pause is explained instead of stopping silently.
    expect(
      state.messages.last.content,
      contains(
        appStringsFor('en').maxStepsReachedMarkdown(2).replaceAll('*', ''),
      ),
      reason: 'cap exhaustion must be visible to the user',
    );
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

  test(
    'enabled context entries are injected into the system message',
    () async {
      final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
        AssistantTurn(content: 'ok'),
      ]);
      final ProviderContainer container = ProviderContainer(
        overrides: testOverrides(
          llm: llm,
          dir: tempDir,
          settings: AppSettings(apiKey: 'k'),
          contexts: <ContextEntry>[
            const ContextEntry(
              id: 'c1',
              name: 'House rules',
              content: 'Always be brief.',
              enabled: true,
            ),
            const ContextEntry(
              id: 'c2',
              name: 'Disabled',
              content: 'Never applied.',
              enabled: false,
            ),
          ],
        ),
      );
      addTearDown(container.dispose);

      await container.read(chatControllerProvider.notifier).send('hi');
      final List<Map<String, dynamic>> wire = llm.calls.first;
      expect(wire.first['role'], 'system');
      expect(wire.first['content'], contains('Always be brief.'));
      expect(wire.first['content'], contains('# Context: House rules'));
      expect(wire.first['content'], isNot(contains('Never applied.')));
    },
  );

  test('text attachments travel inline in the user wire message', () async {
    final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
      AssistantTurn(content: 'parsed'),
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: testOverrides(
        llm: llm,
        dir: tempDir,
        settings: AppSettings(apiKey: 'k'),
      ),
    );
    addTearDown(container.dispose);

    final File dataFile = File('${tempDir.path}/numbers.csv');
    await dataFile.writeAsString('a,b\n1,2');

    await container
        .read(chatControllerProvider.notifier)
        .send(
          'analyze this',
          attachments: <ChatAttachment>[
            ChatAttachment(
              name: 'numbers.csv',
              path: dataFile.path,
              sizeBytes: 8,
              kind: AttachmentKind.text,
            ),
          ],
        );
    final Map<String, dynamic> userWire = llm.calls.first.firstWhere(
      (m) => m['role'] == 'user',
    );
    expect(userWire['content'], contains('analyze this'));
    expect(userWire['content'], contains('[Attached file: numbers.csv]'));
    expect(userWire['content'], contains('a,b\n1,2'));
  });

  test('image attachments become OpenAI vision content parts', () async {
    final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
      AssistantTurn(content: 'nice picture'),
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: testOverrides(
        llm: llm,
        dir: tempDir,
        settings: AppSettings(apiKey: 'k'),
      ),
    );
    addTearDown(container.dispose);

    final File image = File('${tempDir.path}/tiny.png');
    await image.writeAsBytes(base64Decode(tinyPngBase64));

    await container
        .read(chatControllerProvider.notifier)
        .send(
          'what is this?',
          attachments: <ChatAttachment>[
            ChatAttachment(
              name: 'tiny.png',
              path: image.path,
              sizeBytes: 100,
              kind: AttachmentKind.image,
            ),
          ],
        );
    final Map<String, dynamic> userWire = llm.calls.first.firstWhere(
      (m) => m['role'] == 'user',
    );
    final List<dynamic> parts = userWire['content'] as List<dynamic>;
    expect(parts.first['type'], 'text');
    expect(parts.first['text'], contains('what is this?'));
    expect(parts.last['type'], 'image_url');
    expect(
      (parts.last['image_url'] as Map<String, dynamic>)['url'],
      startsWith('data:image/png;base64,'),
    );
  });

  test(
    'sessions run in parallel and switching never interrupts them',
    () async {
      // Gate each LLM turn behind a completer so we control run timing.
      final List<Completer<AssistantTurn>> gates =
          List<Completer<AssistantTurn>>.generate(
            4,
            (_) => Completer<AssistantTurn>(),
          );
      int turn = 0;
      final _GatedLlmClient llm = _GatedLlmClient(gates, () => turn++);
      final ProviderContainer container = ProviderContainer(
        overrides: testOverrides(
          llm: llm,
          dir: tempDir,
          settings: AppSettings(apiKey: 'k'),
        ),
      );
      addTearDown(container.dispose);

      // Session A starts and blocks mid-run.
      final Future<void> runA = container
          .read(chatControllerProvider.notifier)
          .send('task A');
      await Future<void>.delayed(Duration.zero);
      final String? idA = container.read(chatControllerProvider).sessionId;
      expect(idA, isNotNull);
      expect(container.read(chatControllerProvider).isRunning, isTrue);
      expect(container.read(runningSessionsProvider), contains(idA));

      // Starting a NEW session while A runs must be possible.
      await container.read(chatControllerProvider.notifier).newChat();
      final Future<void> runB = container
          .read(chatControllerProvider.notifier)
          .send('task B');
      await Future<void>.delayed(Duration.zero);
      final String? idB = container.read(chatControllerProvider).sessionId;
      expect(idB, isNot(idA));
      expect(
        container.read(runningSessionsProvider),
        containsAll(<String?>[idA, idB]),
      );

      // Finish A, then B.
      gates[0].complete(AssistantTurn(content: 'A done'));
      await runA;
      expect(
        container.read(chatControllerProvider).sessionId,
        idB,
        reason: 'finishing a background run must not switch the screen',
      );
      gates[1].complete(AssistantTurn(content: 'B done'));
      await runB;
      expect(container.read(runningSessionsProvider), isEmpty);

      // Both conversations were persisted independently.
      final List<ChatSummary> summaries = await container
          .read(chatStoreProvider)
          .listSummaries();
      expect(
        summaries.map((s) => s.title),
        containsAll(<String>['task A', 'task B']),
      );
    },
  );

  test('renameChat updates the stored title', () async {
    final ProviderContainer container = await _container(<AssistantTurn>[
      AssistantTurn(content: 'ok'),
    ], tempDir);
    await container.read(chatControllerProvider.notifier).send('hello');
    final String id = container.read(chatControllerProvider).sessionId!;
    await container
        .read(chatControllerProvider.notifier)
        .renameChat(id, 'Renamed');
    final List<ChatSummary> summaries = await container
        .read(chatStoreProvider)
        .listSummaries();
    expect(summaries.single.title, 'Renamed');
  });

  test(
    'deleting a running session stops it and skips the final persist',
    () async {
      final List<Completer<AssistantTurn>> gates =
          List<Completer<AssistantTurn>>.generate(
            2,
            (_) => Completer<AssistantTurn>(),
          );
      int turn = 0;
      final _GatedLlmClient llm = _GatedLlmClient(gates, () => turn++);
      final ProviderContainer container = ProviderContainer(
        overrides: testOverrides(
          llm: llm,
          dir: tempDir,
          settings: AppSettings(apiKey: 'k'),
        ),
      );
      addTearDown(container.dispose);

      final Future<void> run = container
          .read(chatControllerProvider.notifier)
          .send('doomed');
      await Future<void>.delayed(Duration.zero);
      final String id = container.read(chatControllerProvider).sessionId!;

      await container.read(chatControllerProvider.notifier).deleteChat(id);
      gates[0].complete(AssistantTurn(content: 'too late'));
      await run;

      expect(
        await container.read(chatStoreProvider).load(id),
        isNull,
        reason: 'a deleted session must not be resurrected by its own run',
      );
      expect(container.read(runningSessionsProvider), isEmpty);
    },
  );
}

/// LLM fake whose turns are gated behind completers for parallel-run tests.
class _GatedLlmClient implements LlmClient {
  _GatedLlmClient(this.gates, this.nextTurn);

  final List<Completer<AssistantTurn>> gates;
  final int Function() nextTurn;

  @override
  Future<AssistantTurn> complete({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    void Function(String delta)? onDelta,
  }) => gates[nextTurn() % gates.length].future;
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
