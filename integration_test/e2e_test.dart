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
            name: 'node_run',
            argumentsJson: jsonEncode(<String, dynamic>{
              'code': '[1,2,3].reduce((a,b)=>a+b)',
            }),
          ),
        ],
      ),
      AssistantTurn(
        content: '',
        toolCalls: <ToolCallRequest>[
          ToolCallRequest(
            id: 'e2e-3',
            name: 'browser_screenshot',
            argumentsJson: '{}',
          ),
        ],
      ),
      AssistantTurn(
        content: 'E2E selesai: halaman dibuka, node dijalankan & screenshot diambil.',
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

    // 2. All tool cards + final answer rendered.
    expect(find.text('browser_navigate'), findsOneWidget);
    expect(find.text('node_run'), findsOneWidget);
    expect(find.text('browser_screenshot'), findsOneWidget);
    expect(find.textContaining('E2E selesai'), findsOneWidget);

    // 3. LLM received a well-formed wire: system + user + tool results.
    final List<Map<String, dynamic>> firstCall = llm.calls.first;
    expect(firstCall.first['role'], 'system');
    expect(firstCall[1]['role'], 'user');
    expect(llm.calls[2].any((m) => m['role'] == 'tool'), isTrue);

    // 4. Settings screen is reachable; provider CRUD works through the
    // full-screen manager (per-provider API key + explicit save button).
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    final BuildContext context = tester.element(find.byType(SettingsScreen));
    final ProviderContainer container = ProviderScope.containerOf(context);

    await tester.tap(find.byKey(const Key('providers-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('provider-OpenRouter')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('editor-api-key-field')),
      'e2e-key-2',
    );
    await tester.tap(find.byKey(const Key('editor-save-api-key-button')));
    await tester.pumpAndSettle();
    // OpenRouter is the active provider: the live connection picks the
    // key up immediately and the preset stores it.
    expect(container.read(settingsProvider).apiKey, 'e2e-key-2');
    expect(
      container
          .read(settingsProvider)
          .presets
          .firstWhere((ProviderPreset p) => p.name == 'OpenRouter')
          .apiKey,
      'e2e-key-2',
    );

    // Leave the editor and the providers manager.
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    // 5. Language option: English is the default, Bahasa Indonesia switches
    // the whole UI and the choice persists in settings.
    await tester.dragUntilVisible(
      find.byKey(const Key('lang-id')),
      find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lang-id')));
    await tester.pumpAndSettle();
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(
      ProviderScope.containerOf(context).read(settingsProvider).languageCode,
      'id',
    );
    await tester.tap(find.byKey(const Key('lang-en')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(
      ProviderScope.containerOf(context).read(settingsProvider).languageCode,
      'en',
    );

    // 6. New v1.4.0 controls exist: theme picker + max-steps custom input
    // + Node.js manager tile + files tile.
    // The language section is at the bottom; drag back UP to reveal the
    // appearance section first (ListView builds lazily).
    await tester.dragUntilVisible(
      find.byKey(const Key('theme-mode-segmented')),
      find.byType(ListView),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-mode-segmented')), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('max-steps-field')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('max-steps-field')), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('node-manager-tile')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-manager-tile')), findsOneWidget);
    expect(find.byKey(const Key('files-tile')), findsOneWidget);
    // v1.7.0: the User-Agent mode dropdown lives below the agent section.
    await tester.dragUntilVisible(
      find.byKey(const Key('ua-mode-dropdown')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ua-mode-dropdown')), findsOneWidget);
    expect(find.byKey(const Key('ua-rotate-button')), findsOneWidget);
    // The context tile sits above the node section — reveal it too.
    await tester.dragUntilVisible(
      find.byKey(const Key('context-manager-tile')),
      find.byType(ListView),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('context-manager-tile')), findsOneWidget);

    try {
      await tester.runAsync(() => tempDir.delete(recursive: true));
    } catch (_) {}
  });
}
