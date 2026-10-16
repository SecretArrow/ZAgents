import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/agent_controller.dart';
import 'package:zagents/services/js_runtime.dart';
import 'package:zagents/services/module_registry.dart';
import 'package:zagents/services/llm_client.dart';
import 'package:zagents/services/module_runtime.dart';
import 'package:zagents/services/session_sandbox.dart';

import '../support/test_doubles.dart';

void main() {
  late Directory tempDir;
  late ModuleRegistry registry;
  late ScriptedJsRuntime js;
  late ModuleRuntime moduleRuntime;
  late SessionSandbox sandbox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_module_ctrl');
    registry = ModuleRegistry(resolveBaseDir: () async => tempDir);
    js = ScriptedJsRuntime();
    sandbox = SessionSandbox(resolveDocumentsDir: () async => tempDir);
    moduleRuntime = ModuleRuntime(
      js: js,
      resolveSandboxRoot: sandbox.rootFor,
      resolveModulePath: (String name) async =>
          (await registry.get(name))?.path,
      resolveSdkSource: () async => 'module.exports = zagents;',
      resolveNpmModulesRoot: () async =>
          '${tempDir.path}${Platform.pathSeparator}node_modules',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Installs a module fixture into the registry via the public ZIP path.
  Future<ChatModule> installModule(
    String name, {
    String version = '1.0.0',
    String description = 'Counts things',
    List<ModulePermission> permissions = const <ModulePermission>[
      ModulePermission.storage,
    ],
  }) async {
    final String manifest = jsonEncode(<String, dynamic>{
      'name': name,
      'version': version,
      'description': description,
      'entry': 'main.js',
      'permissions': permissions.map((p) => p.name).toList(),
    });
    final List<int> entry = utf8.encode('// $name entry');
    final Archive archive = Archive()
      ..addFile(
        ArchiveFile(
          'module.json',
          utf8.encode(manifest).length,
          utf8.encode(manifest),
        ),
      )
      ..addFile(ArchiveFile('main.js', entry.length, entry));
    final File zip = File(
      '${tempDir.path}${Platform.pathSeparator}$name-install.zip',
    )..writeAsBytesSync(ZipEncoder().encode(archive));
    final ModuleInstallResult result = await registry.installFromZip(zip.path);
    expect(result.ok, isTrue, reason: result.message);
    return result.module!;
  }

  Future<ProviderContainer> container({List<AssistantTurn>? turns}) async {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        ...testOverrides(
          llm: ScriptedLlmClient(
            turns ??
                <AssistantTurn>[AssistantTurn(content: 'Module output noted.')],
          ),
          dir: tempDir,
          settings: AppSettings(apiKey: 'k', autoTitle: false),
        ),
        moduleRegistryProvider.overrideWithValue(registry),
        moduleRuntimeProvider.overrideWithValue(moduleRuntime),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'draft + activateModule stages pendingModule for the first message',
    () async {
      final ProviderContainer c = await container();
      await installModule('counter');
      await c.read(chatControllerProvider.notifier).activateModule('counter');
      expect(c.read(chatControllerProvider).pendingModule, 'counter');
    },
  );

  test('staged module activates with the first message: entry output lands '
      'in a module message before the agent reply', () async {
    final ProviderContainer c = await container();
    final ChatModule mod = await installModule('counter');
    js.nextResult = const JsRunResult(output: 'Count: 1', result: '"done"');

    final ChatController controller = c.read(chatControllerProvider.notifier);
    await controller.activateModule('counter');
    await controller.send('hello');

    final ChatState state = c.read(chatControllerProvider);
    expect(state.isRunning, isFalse);
    // Message order: user -> module -> assistant.
    expect(state.messages.first.role, Role.user);
    final ChatMessage moduleMessage = state.messages[1];
    expect(moduleMessage.moduleName, 'counter');
    expect(moduleMessage.content, contains('Count: 1'));
    expect(state.messages.last.role, Role.assistant);
    expect(state.pendingModule, isNull);

    // The module ran with per-chat state dir + granted permissions.
    final ModuleInvocation invocation = js.moduleInvocations.single;
    expect(invocation.info['sessionId'], state.sessionId);
    expect(invocation.permissions, <String>{'storage'});
    expect(invocation.entrySource, '// counter entry');
    expect(File(mod.entryPath).existsSync(), isTrue);
  });

  test(
    'staged module receives the first message as zagents.info.prompt',
    () async {
      final ProviderContainer c = await container();
      await installModule('setupme');
      js.nextResult = const JsRunResult(output: 'ready', result: '"done"');

      final ChatController controller = c.read(chatControllerProvider.notifier);
      await controller.activateModule('setupme');
      await controller.send('setup me@example.com hunter2');

      expect(js.moduleInvocations, hasLength(1));
      expect(
        js.moduleInvocations.single.info['prompt'],
        'setup me@example.com hunter2',
      );
    },
  );

  test(
    'immediate activation on an open session carries no prompt key',
    () async {
      final ProviderContainer c = await container();
      await installModule('instant');
      js.nextResult = const JsRunResult(output: 'ok');

      final ChatController controller = c.read(chatControllerProvider.notifier);
      await controller.send('hi there');
      await controller.activateModule('instant');

      expect(js.moduleInvocations, hasLength(1));
      expect(js.moduleInvocations.single.info.containsKey('prompt'), isFalse);
    },
  );

  test('activating on an OPEN session runs the entry immediately and '
      'persists the module list', () async {
    final ProviderContainer c = await container();
    await installModule('weather');
    js.nextResult = const JsRunResult(output: 'Weather: sunny');

    final ChatController controller = c.read(chatControllerProvider.notifier);
    await controller.send('hi there'); // creates session 1
    final String sessionId = c.read(chatControllerProvider).sessionId!;
    // The run finished; now activate the module on the SAME session.
    await controller.activateModule('weather');

    final ChatState state = c.read(chatControllerProvider);
    expect(state.activeModules, <String>['weather']);
    final ChatMessage moduleMessage = state.messages.last;
    expect(moduleMessage.moduleName, 'weather');
    expect(moduleMessage.content, contains('Weather: sunny'));

    // Persisted: a fresh store read sees the module list.
    final List<String> stored = await c
        .read(chatStoreProvider)
        .loadModules(sessionId);
    expect(stored, <String>['weather']);
  });

  test('opened sessions restore their own module scope and system prompt '
      'context', () async {
    final ProviderContainer c = await container();
    await installModule('weather');
    js.nextResult = const JsRunResult(output: 'sunny');

    final ChatController controller = c.read(chatControllerProvider.notifier);
    await controller.send('first message');
    await controller.activateModule('weather');

    // Simulate reopening from history (draft → open).
    await controller.newChat();
    final String sessionId = (await c.read(chatListProvider.future)).first.id;
    await controller.openChat(
      ChatSummary(id: sessionId, title: 't', updatedAt: DateTime.now()),
    );
    expect(c.read(chatControllerProvider).activeModules, <String>['weather']);

    // Next run: the system wire carries the module context block.
    final ScriptedLlmClient llm =
        c.read(llmClientProvider) as ScriptedLlmClient;
    llm.turns.clear();
    llm.turns.add(AssistantTurn(content: 'ok'));
    await controller.send('again');
    final List<Map<String, dynamic>> wire = llm.calls.last;
    final String system = (wire.first['content'] as String?) ?? '';
    expect(system, contains('# Active module: weather v1.0.0'));
    expect(system, contains('Counts things'));
  });

  test('deactivation removes the module, persists, and appends a module '
      'message', () async {
    final ProviderContainer c = await container();
    await installModule('weather');
    js.nextResult = const JsRunResult(output: 'sunny');

    final ChatController controller = c.read(chatControllerProvider.notifier);
    await controller.send('first');
    await controller.activateModule('weather');
    expect(await controller.deactivateModule('weather'), isTrue);
    final ChatState state = c.read(chatControllerProvider);
    expect(state.activeModules, isEmpty);
    expect(state.messages.last.moduleName, 'weather');
    expect(state.messages.last.content, contains('deactivated'));

    final String sessionId = state.sessionId!;
    expect(await c.read(chatStoreProvider).loadModules(sessionId), isEmpty);
    expect(await controller.deactivateModule('weather'), isFalse);
  });

  test('module context is per chat: activating in chat 2 does not leak '
      'into chat 1 (user regression scenario)', () async {
    final ProviderContainer c = await container();
    await installModule('weather');
    js.nextResult = const JsRunResult(output: 'sunny');

    final ChatController controller = c.read(chatControllerProvider.notifier);
    // Chat 1: activate module.
    await controller.send('chat1 start');
    await controller.activateModule('weather');
    expect(c.read(chatControllerProvider).activeModules, <String>['weather']);

    // Chat 2 (new chat, no module).
    await controller.newChat();
    await controller.send('chat2 start');
    final ChatState chat2 = c.read(chatControllerProvider);
    expect(chat2.activeModules, isEmpty);

    // Chat 2's module storage/state must be separate — chat 2's run never
    // sees chat 1's module invocation state dirs.
    final Directory chat1Modules = await moduleRuntime.instanceDirFor(
      // chat 1's id came before newChat; recover from the store list.
      (await c.read(chatListProvider.future)).last.id,
      'weather',
    );
    final Directory chat2Modules = await moduleRuntime.instanceDirFor(
      chat2.sessionId!,
      'weather',
    );
    expect(chat1Modules.path != chat2Modules.path, isTrue);
    expect(chat2Modules.path.contains(chat2.sessionId!), isTrue);
  });

  test('unknown module activation surfaces a localized error', () async {
    final ProviderContainer c = await container();
    final ChatController controller = c.read(chatControllerProvider.notifier);
    await controller.send('start');
    await controller.activateModule('ghost');
    expect(
      c.read(chatControllerProvider).error,
      appStringsFor('en').moduleNotFound('ghost'),
    );
  });

  test('module run failure degrades into the module message', () async {
    final ProviderContainer c = await container();
    await installModule('broken');
    js.nextResult = const JsRunResult(output: '', error: 'boom inside');

    final ChatController controller = c.read(chatControllerProvider.notifier);
    await controller.send('start');
    await controller.activateModule('broken');

    final ChatState state = c.read(chatControllerProvider);
    final ChatMessage moduleMessage = state.messages.last;
    expect(moduleMessage.moduleName, 'broken');
    expect(
      moduleMessage.content,
      contains(appStringsFor('en').moduleRunFailed('boom inside')),
    );
  });
}
