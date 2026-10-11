import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/main.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/llm_client.dart';
import 'package:zagents/ui/screens/settings_screen.dart';

import '../test/fakes/fakes.dart';

/// End-to-end flows executed on a real Android emulator via GitHub Actions.
/// External dependencies (LLM, browser) are replaced with deterministic fakes
/// so the suite is fast and hermetic.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('e2e: chat + agent tool call + settings', (
    WidgetTester tester,
  ) async {
    // Real IO must run inside tester.runAsync within widget tests.
    final Directory tempDir = (await tester.runAsync<Directory>(
      () => Directory.systemTemp.createTemp('zagents_e2e'),
    ))!;

    final FakeLlmClient llm = FakeLlmClient(<AssistantTurn>[
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 'e2e-1',
            name: 'browser_navigate',
            argumentsJson: jsonEncode(<String, dynamic>{
              'url': 'https://example.com',
            }),
          ),
        ],
      ),
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 'e2e-2',
            name: 'browser_screenshot',
            argumentsJson: '{}',
          ),
        ],
      ),
      AssistantTurn(
        content: 'E2E selesai: halaman dibuka & screenshot diambil.',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(
          llm: llm,
          dir: tempDir,
          settings: AppSettings(apiKey: 'e2e-key'),
        ),
        child: const ZAgentsApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 1. Send a prompt from the composer.
    await tester.enterText(
      find.byKey(const Key('composer-field')),
      'Buka example.com',
    );
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 2. Both tool cards + final answer rendered.
    expect(find.text('browser_navigate'), findsOneWidget);
    expect(find.text('browser_screenshot'), findsOneWidget);
    expect(find.textContaining('E2E selesai'), findsOneWidget);

    // 3. LLM received a well-formed wire: system + user + tool results.
    final List<Map<String, dynamic>> firstCall = llm.calls.first;
    expect(firstCall.first['role'], 'system');
    expect(firstCall[1]['role'], 'user');
    expect(llm.calls[2].any((m) => m['role'] == 'tool'), isTrue);

    // 4. Settings screen is reachable and editable.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.enterText(find.byKey(const Key('api-key-field')), 'e2e-key-2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final BuildContext context = tester.element(find.byType(SettingsScreen));
    expect(
      ProviderScope.containerOf(context).read(settingsProvider).apiKey,
      'e2e-key-2',
    );

    try {
      await tester.runAsync(() => tempDir.delete(recursive: true));
    } catch (_) {}
  });
}
