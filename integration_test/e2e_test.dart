import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/main.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/js_runtime.dart';
import 'package:zagents/services/agent_controller.dart';
import 'package:zagents/services/llm_client.dart';
import 'package:zagents/services/module_registry.dart';
import 'package:zagents/services/module_runtime.dart';
import 'package:zagents/services/session_sandbox.dart';
import 'package:zagents/ui/screens/settings_screen.dart';

import '../test/support/test_doubles.dart';

/// End-to-end flows executed on a real Android emulator via GitHub Actions.
/// External dependencies (LLM, browser) are replaced with deterministic test doubles
/// so the suite is fast and hermetic.

/// Scrolls a lazy ListView until [key] is built and visible, then taps it
/// (dragUntilVisible builds offscreen items; ensureVisible aligns the
/// exact offset after the language switch reflows the list).
Future<void> tapScrollable(WidgetTester tester, Key key) async {
  if (find.byKey(key).evaluate().isEmpty) {
    await tester.dragUntilVisible(
      find.byKey(key),
      find.byType(ListView),
      const Offset(0, -250),
    );
  }
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('e2e: chat + agent tool call + settings', (
    WidgetTester tester,
  ) async {
    // Real IO must run inside tester.runAsync within widget tests.
    final Directory tempDir = (await tester.runAsync<Directory>(
      () => Directory.systemTemp.createTemp('zagents_e2e'),
    ))!;

    final ScriptedLlmClient llm = ScriptedLlmClient(<AssistantTurn>[
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

    // Leave the editor first — the providers manager is behind it.
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();

    // v1.10.0: long-pressing a (non-active) provider card opens the
    // confirmation dialog; cancelling keeps the connection unchanged.
    await tester.longPress(find.byKey(const Key('provider-InferHub')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('provider-activate-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-activate-provider')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('provider-activate-dialog')), findsNothing);

    // Leave the providers manager.
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    // 5. Language option: English is the default, Bahasa Indonesia switches
    // the whole UI and the choice persists in settings. The settings list
    // is lazy and the module manager tile (v1.21.0) shifts section
    // heights, so each language button may need scrolling (and building)
    // before it can be tapped.
    await tapScrollable(tester, const Key('lang-id'));
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(
      ProviderScope.containerOf(context).read(settingsProvider).languageCode,
      'id',
    );
    await tapScrollable(tester, const Key('lang-en'));
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
    // v1.8.0: "Run until done" switch sits right above the max-steps row.
    expect(find.byKey(const Key('run-until-done-switch')), findsOneWidget);
    // v1.9.0: plan-first (Todos) switch sits right below it, on by default.
    expect(find.byKey(const Key('plan-first-switch')), findsOneWidget);
    expect(container.read(settingsProvider).planFirst, isTrue);
    await tester.dragUntilVisible(
      find.byKey(const Key('node-manager-tile')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-manager-tile')), findsOneWidget);
    expect(find.byKey(const Key('files-tile')), findsOneWidget);
    // The context tile sits above the node section — reveal it too.
    await tester.dragUntilVisible(
      find.byKey(const Key('context-manager-tile')),
      find.byType(ListView),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('context-manager-tile')), findsOneWidget);
    // v1.7.0: the User-Agent mode dropdown sits one section higher still —
    // keep dragging UP.
    await tester.dragUntilVisible(
      find.byKey(const Key('ua-mode-dropdown')),
      find.byType(ListView),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ua-mode-dropdown')), findsOneWidget);
    expect(find.byKey(const Key('ua-rotate-button')), findsOneWidget);

    try {
      await tester.runAsync(() => tempDir.delete(recursive: true));
    } catch (_) {}
  });

  testWidgets('e2e: module installs from ZIP, runs on the real embedded '
      'runtime with the zagents SDK, and stays per-chat isolated', (
    WidgetTester tester,
  ) async {
    final Directory tempDir = (await tester.runAsync<Directory>(
      () => Directory.systemTemp.createTemp('zagents_e2e_module'),
    ))!;

    // -- 1. Build a module ZIP on disk (real IO). -------------------------
    const String manifestJson =
        '{"name":"e2e-module","version":"1.0.0","title":"E2E Module",'
        '"description":"Counts activations per chat",'
        '"permissions":["storage","chat"],"entry":"main.js"}';
    const String entrySource = '''
async function main() {
  const previous = (await zagents.storage.get('count')) || 0;
  await zagents.storage.set('count', previous + 1);
  await zagents.log('Hello from the module! count=' + (previous + 1));
  await zagents.chat.emit('chat emit works');
  return { count: previous + 1 };
}
module.exports = main();
''';
    final File zipFile = File(
      '${tempDir.path}${Platform.pathSeparator}e2e-module.zip',
    );
    await tester.runAsync(() async {
      final Archive archive = Archive()
        ..addFile(
          ArchiveFile(
            'module.json',
            utf8.encode(manifestJson).length,
            utf8.encode(manifestJson),
          ),
        )
        ..addFile(
          ArchiveFile(
            'main.js',
            utf8.encode(entrySource).length,
            utf8.encode(entrySource),
          ),
        );
      zipFile.writeAsBytesSync(ZipEncoder().encode(archive));
    });

    // -- 2. App with the REAL registry + REAL WebView-backed runtime. ----
    final ModuleRegistry registry = ModuleRegistry(
      resolveBaseDir: () async => tempDir,
    );
    final ModuleInstallResult installed = (await tester.runAsync(
      () => registry.installFromZip(zipFile.path),
    ))!;
    expect(installed.ok, isTrue, reason: installed.message);

    final ScriptedLlmClient llm = ScriptedLlmClient(<AssistantTurn>[
      AssistantTurn(content: 'Module output acknowledged.'),
    ]);
    final SessionSandbox sandbox = SessionSandbox(
      resolveDocumentsDir: () async => tempDir,
    );

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        ...testOverrides(
          llm: llm,
          dir: tempDir,
          settings: AppSettings(apiKey: 'e2e-key', autoTitle: false),
          writeScreenshots: false,
        ),
        moduleRegistryProvider.overrideWithValue(registry),
        moduleRuntimeProvider.overrideWith(
          (Ref ref) => ModuleRuntime(
            // The REAL hidden-WebView runtime: exercises the module
            // bootstrap, the zagents SDK global and the Dart bridge.
            js: SerializedJsRuntime(WebViewJsRuntime()),
            resolveSandboxRoot: sandbox.rootFor,
            resolveModulePath: (String name) async =>
                (await registry.get(name))?.path,
            resolveSdkSource: () async =>
                rootBundle.loadString('assets/modules/zagents-sdk.js'),
            resolveNpmModulesRoot: () async =>
                '${tempDir.path}${Platform.pathSeparator}node_modules',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ZAgentsApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // -- 3. Activation + first message, executed in the real async zone.
    // The integration binding runs test bodies in a fake-async zone where
    // real platform async (registry IO, the hidden WebView) never
    // completes — controller work therefore runs inside tester.runAsync
    // (the /plugins menu + permission dialog UI flows are covered by the
    // widget suite). activateModule on a fresh draft stages the module;
    // the FIRST message activates it: transcript order reads user ->
    // module output -> assistant reply.
    await tester.runAsync(() async {
      final ChatController controller = container.read(
        chatControllerProvider.notifier,
      );
      await controller.activateModule('e2e-module');
      expect(
        container.read(chatControllerProvider).pendingModule,
        'e2e-module',
      );
      expect(container.read(chatControllerProvider).activeModules, isEmpty);
      await controller.send('what did the module say?');
    });

    // The entry output, emit and badge are all in the transcript now.
    final String moduleContent = container
        .read(chatControllerProvider)
        .messages
        .map(
          (ChatMessage m) =>
              '[${m.role.name}/${m.moduleName ?? '-'}] ${m.content}',
        )
        .join(' ||| ');
    expect(
      find.textContaining('Hello from the module! count=1'),
      findsOneWidget,
      reason:
          'module entry output never appeared. state.error='
          '${container.read(chatControllerProvider).error} '
          'transcript: $moduleContent',
    );
    expect(find.textContaining('chat emit works'), findsOneWidget);
    expect(find.byKey(const Key('module-badge-e2e-module')), findsOneWidget);
    expect(container.read(chatControllerProvider).activeModules, <String>[
      'e2e-module',
    ]);

    // Per-chat state was materialized inside the session sandbox.
    final Directory instanceDir = (await tester.runAsync(
      () => sandbox
          .rootFor(container.read(chatControllerProvider).sessionId!)
          .then(
            (Directory root) => Directory(
              '${root.path}${Platform.pathSeparator}modules'
              '${Platform.pathSeparator}e2e-module',
            ),
          ),
    ))!;
    expect(instanceDir.existsSync(), isTrue);
    final File storage = File(
      '${instanceDir.path}${Platform.pathSeparator}storage.json',
    );
    expect(storage.existsSync(), isTrue);
    expect(storage.readAsStringSync(), contains('"count":1'));

    try {
      await tester.runAsync(() => tempDir.delete(recursive: true));
    } catch (_) {}
  });
}
