import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zagents/main.dart';
import 'package:zagents/di.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/llm_client.dart';

import '../../test/fakes/fakes.dart';

/// Drawer assertions must be scoped: chat texts also render in the body
/// behind the drawer (find.text matches those bubbles too).
Finder inDrawer(Finder finder) =>
    find.descendant(of: find.byType(Drawer), matching: finder);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_widget_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Widget wrap({LlmClient? llm, AppSettings? settings}) => ProviderScope(
    overrides: testOverrides(
      llm: llm,
      dir: tempDir,
      settings: settings ?? AppSettings(apiKey: 'test-key'),
      writeScreenshots: false,
    ),
    child: const ZAgentsApp(),
  );

  testWidgets('send message -> streamed answer appears', (
    WidgetTester tester,
  ) async {
    final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
      AssistantTurn(content: 'Halo, ini jawaban agent.'),
    ]);
    await tester.pumpWidget(wrap(llm: llm));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'Hai agent',
    );
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump(); // user bubble appears
    expect(find.text('Hai agent'), findsOneWidget);

    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(
      find.byKey(const Key('send-button')),
      findsOneWidget,
    ); // running ended
  });

  testWidgets('agent tool call renders ToolCallCard and final answer', (
    WidgetTester tester,
  ) async {
    final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
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
      AssistantTurn(content: 'Selesai membuka halaman.'),
    ]);
    await tester.pumpWidget(wrap(llm: llm));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'Buka example.com',
    );
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    expect(find.text('browser_navigate'), findsOneWidget);
    expect(find.textContaining('Selesai membuka halaman.'), findsOneWidget);
  });

  testWidgets('screenshot tool shows image in tool card', (
    WidgetTester tester,
  ) async {
    final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 't2',
            name: 'browser_screenshot',
            argumentsJson: '{}',
          ),
        ],
      ),
      AssistantTurn(content: 'Ini tangkapannya.'),
    ]);
    await tester.pumpWidget(wrap(llm: llm));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'Screenshot',
    );
    await tester.tap(find.byKey(const Key('send-button')));
    // Bounded pumps instead of pumpAndSettle: Image.file codec decoding
    // never completes inside the fake-async test zone and would block settle.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('browser_screenshot'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('agent toggle switches settings', (WidgetTester tester) async {
    final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
      AssistantTurn(content: 'ok'),
    ]);
    await tester.pumpWidget(wrap(llm: llm));
    await tester.pump();

    expect(find.byKey(const Key('agent-toggle')), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-toggle')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    // Toggle still rendered after state change.
    expect(find.byKey(const Key('agent-toggle')), findsOneWidget);
  });

  testWidgets('drawer history search filters chats', (
    WidgetTester tester,
  ) async {
    // Static history (the real chat store does disk IO that never
    // completes inside the fake-async zone — the same reason
    // files_screen_test overrides this provider).
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...testOverrides(
            dir: tempDir,
            settings: AppSettings(apiKey: 'test-key'),
            writeScreenshots: false,
          ),
          chatListProvider.overrideWith(
            (Ref ref) async => <ChatSummary>[
              ChatSummary(
                id: 'c-1',
                title: 'Resep kue cokelat',
                updatedAt: DateTime(2025, 1, 1),
              ),
              ChatSummary(
                id: 'c-2',
                title: 'Jadwal kereta api',
                updatedAt: DateTime(2025, 1, 2),
              ),
            ],
          ),
        ],
        child: const ZAgentsApp(),
      ),
    );
    await tester.pump();

    // Open the drawer and search the history.
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(
      inDrawer(find.byKey(const Key('history-search-field'))),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('history-search-field')),
      'kereta api',
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(inDrawer(find.text('Jadwal kereta api')), findsOneWidget);
    expect(inDrawer(find.text('Resep kue cokelat')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('history-search-field')),
      'kue cokelat',
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(inDrawer(find.text('Resep kue cokelat')), findsOneWidget);
    expect(inDrawer(find.text('Jadwal kereta api')), findsNothing);
  });
}
