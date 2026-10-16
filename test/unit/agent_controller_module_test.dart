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
    Map<String, dynamic>? setup,
  }) async {
    final String manifest = jsonEncode(<String, dynamic>{
      'name': name,
      'version': version,
      'description': description,
      'entry': 'main.js',
      'permissions': permissions.map((p) => p.name).toList(),
      'setup': ?setup,
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
    // Ordinary failures get NO setup guidance and NO form.
    expect(state.setupRequest, isNull);
  });

  test('a STALE module zip failing with setup-required gets actionable '
      'guidance — no dead end, no impossible form', () async {
    final ProviderContainer c = await container();
    // Zips installed before the setup-form feature carry NO setup block
    // and keep failing after app updates (installed modules persist).
    await installModule('legacy');
    js.nextResult = const JsRunResult(
      output: 'OnHomeroom Daily needs your account for THIS chat.',
      error: 'setup required',
    );

    final ChatController controller = c.read(chatControllerProvider.notifier);
    await controller.send('start');
    await controller.activateModule('legacy');

    final ChatState state = c.read(chatControllerProvider);
    final ChatMessage moduleMessage = state.messages.last;
    // Both the failure line and the legacy guidance (updated zip / setup
    // command) land in the transcript.
    expect(
      moduleMessage.content,
      contains(appStringsFor('en').moduleRunFailed('setup required')),
    );
    expect(
      moduleMessage.content,
      contains(appStringsFor('en').moduleSetupLegacyHint('legacy')),
    );
    // No form can be rendered for a manifest without setup fields.
    expect(state.setupRequest, isNull);
  });

  group('module doctor (agent repair staging)', () {
    // A ScriptedLlmClient consumes turns in order across sends: send #1
    // consumes the plain turn (establishes the session), send #2 runs
    // the module_stage_repair tool call + the final answer.
    Future<ProviderContainer> repairContainer() => container(
      turns: <AssistantTurn>[
        AssistantTurn(content: 'ok'),
        AssistantTurn(
          content: '',
          toolCalls: <ToolCallRequest>[
            ToolCallRequest(
              id: 't-repair',
              name: 'module_stage_repair',
              argumentsJson: jsonEncode(<String, dynamic>{
                'path': 'repaired.zip',
              }),
            ),
          ],
        ),
        AssistantTurn(content: 'Repair staged for your confirmation.'),
      ],
    );

    Future<File> writeRepairZip(ProviderContainer c) async {
      final String sessionId = c.read(chatControllerProvider).sessionId!;
      final Directory sandbox = Directory(
        '${tempDir.path}${Platform.pathSeparator}sessions'
        '${Platform.pathSeparator}$sessionId',
      )..createSync(recursive: true);
      final String manifest = jsonEncode(<String, dynamic>{
        'name': 'fixme',
        'version': '1.0.1',
        'title': 'Fixme',
        'permissions': <String>['storage'],
      });
      final List<int> manifestBytes = utf8.encode(manifest);
      final List<int> entryBytes = utf8.encode('module.exports = "fixed";');
      final Archive archive = Archive()
        ..addFile(
          ArchiveFile('module.json', manifestBytes.length, manifestBytes),
        )
        ..addFile(ArchiveFile('main.js', entryBytes.length, entryBytes));
      return File('${sandbox.path}${Platform.pathSeparator}repaired.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
    }

    test('a staged repair surfaces the confirmation card, install goes '
        'through the full pipeline', () async {
      final ProviderContainer c = await repairContainer();
      final ChatController controller = c.read(chatControllerProvider.notifier);

      await controller.send('start');
      final File zip = await writeRepairZip(c);
      await controller.send('perbaiki modulnya');

      final ChatState state = c.read(chatControllerProvider);
      expect(state.pendingModuleInstall, isNotNull);
      expect(state.pendingModuleInstall!.moduleName, 'fixme');
      expect(state.pendingModuleInstall!.version, '1.0.1');
      expect(state.pendingModuleInstall!.permissions, <String>['storage']);
      expect(state.pendingModuleInstall!.zipPath, zip.path);
      // Staging alone does NOT install.
      expect(await c.read(moduleRegistryProvider).get('fixme'), isNull);

      // User taps Install: full installFromZip pipeline runs.
      final bool ok = await controller.installStagedModule();
      expect(ok, isTrue);
      expect((await c.read(moduleRegistryProvider).get('fixme')), isNotNull);
      final ChatState after = c.read(chatControllerProvider);
      expect(after.pendingModuleInstall, isNull);
      expect(
        after.messages.last.content,
        contains(appStringsFor('en').moduleRepairInstalled('fixme')),
      );
    });

    test('discard clears the card without installing', () async {
      final ProviderContainer c = await repairContainer();
      final ChatController controller = c.read(chatControllerProvider.notifier);

      await controller.send('start');
      await writeRepairZip(c);
      await controller.send('perbaiki modulnya');
      expect(c.read(chatControllerProvider).pendingModuleInstall, isNotNull);

      controller.discardStagedModule();
      expect(c.read(chatControllerProvider).pendingModuleInstall, isNull);
      expect(await c.read(moduleRegistryProvider).get('fixme'), isNull);
    });

    test('an invalid repair zip never stages a card', () async {
      final ProviderContainer c = await container(
        turns: <AssistantTurn>[
          AssistantTurn(content: 'ok'),
          AssistantTurn(
            content: '',
            toolCalls: <ToolCallRequest>[
              ToolCallRequest(
                id: 't-bad',
                name: 'module_stage_repair',
                argumentsJson: jsonEncode(<String, dynamic>{
                  'path': 'broken.zip',
                }),
              ),
            ],
          ),
          AssistantTurn(content: 'Sorry, the zip was invalid.'),
        ],
      );
      final ChatController controller = c.read(chatControllerProvider.notifier);

      await controller.send('start');
      final String sessionId = c.read(chatControllerProvider).sessionId!;
      final Directory sandbox = Directory(
        '${tempDir.path}${Platform.pathSeparator}sessions'
        '${Platform.pathSeparator}$sessionId',
      )..createSync(recursive: true);
      File('${sandbox.path}${Platform.pathSeparator}broken.zip')
          .writeAsBytesSync(<int>[1, 2, 3]);

      await controller.send('perbaiki');

      expect(c.read(chatControllerProvider).pendingModuleInstall, isNull);
      final ChatState state = c.read(chatControllerProvider);
      final ChatMessage toolMessage = state.messages
          .where((m) => m.toolCalls.isNotEmpty)
          .last;
      expect(toolMessage.toolCalls.single.status, ToolStatus.error);
    });
  });

  group('per-chat setup gate (form before first run)', () {
    Future<ChatModule> installSetupModule(String name) => installModule(
      name,
      description: 'Needs an account',
      setup: <String, dynamic>{
        'title': 'Acct',
        'fields': <dynamic>[
          <String, dynamic>{'key': 'email', 'type': 'text', 'required': true},
          <String, dynamic>{
            'key': 'password',
            'type': 'password',
            'required': true,
          },
        ],
      },
    );

    test(
      'unsatisfied setup: module does NOT run, form request surfaces',
      () async {
        final ProviderContainer c = await container();
        await installSetupModule('gated');
        js.nextResult = const JsRunResult(output: 'SHOULD NOT RUN');

        final ChatController controller = c.read(
          chatControllerProvider.notifier,
        );
        await controller.send('start');
        await controller.activateModule('gated');

        final ChatState state = c.read(chatControllerProvider);
        // No JS execution ever happened.
        expect(js.moduleInvocations, isEmpty);
        // The module is active but blocked behind its form.
        expect(state.activeModules, <String>['gated']);
        expect(state.setupRequest, isNotNull);
        expect(state.setupRequest!.moduleName, 'gated');
        expect(state.setupRequest!.setup.fields, hasLength(2));
        // Localized needs-setup message posted into the transcript.
        final ChatMessage moduleMessage = state.messages.last;
        expect(moduleMessage.moduleName, 'gated');
        expect(
          moduleMessage.content,
          contains(appStringsFor('en').moduleSetupNeededTitle('Acct')),
        );
      },
    );

    test(
      'staged module on a fresh chat hits the gate on the first message',
      () async {
        final ProviderContainer c = await container();
        await installSetupModule('staged-gate');
        js.nextResult = const JsRunResult(output: 'nope');

        final ChatController controller = c.read(
          chatControllerProvider.notifier,
        );
        await controller.activateModule('staged-gate');
        await controller.send('hello there');

        final ChatState state = c.read(chatControllerProvider);
        expect(js.moduleInvocations, isEmpty);
        expect(state.setupRequest, isNotNull);
        // The user message still got its agent reply.
        expect(state.messages.first.role, Role.user);
        expect(state.messages.last.role, Role.assistant);
      },
    );

    test(
      'submitModuleSetup persists the values and RE-RUNS the module',
      () async {
        final ProviderContainer c = await container();
        final ChatModule mod = await installSetupModule('formflow');
        js.nextResult = const JsRunResult(output: 'cycle ran');

        final ChatController controller = c.read(
          chatControllerProvider.notifier,
        );
        await controller.send('start');
        await controller.activateModule('formflow');
        expect(c.read(chatControllerProvider).setupRequest, isNotNull);

        // Incomplete values are rejected.
        expect(
          await controller.submitModuleSetup('formflow', <String, dynamic>{
            'email': 'me@example.com',
          }),
          isFalse,
        );
        expect(js.moduleInvocations, isEmpty);

        expect(
          await controller.submitModuleSetup('formflow', <String, dynamic>{
            'email': 'me@example.com',
            'password': 'hunter2',
          }),
          isTrue,
        );

        final ChatState state = c.read(chatControllerProvider);
        expect(state.setupRequest, isNull);
        // The module ran exactly once — after the form was submitted.
        expect(js.moduleInvocations, hasLength(1));
        // The submitted values reached the per-chat instance storage.
        final Map<String, dynamic> stored = await moduleRuntime.readStoredSetup(
          state.sessionId!,
          mod.name,
        );
        expect(stored, <String, dynamic>{
          'email': 'me@example.com',
          'password': 'hunter2',
        });
        // The re-run posted the module output.
        expect(
          state.messages.where((ChatMessage m) => m.moduleName == 'formflow'),
          isNotEmpty,
        );
      },
    );

    test('submit works AFTER the agent loop dropped its run object '
        '(staged path, e2e regression)', () async {
      final ProviderContainer c = await container();
      final ChatModule mod = await installSetupModule('lateflow');
      js.nextResult = const JsRunResult(output: 'late cycle ran');

      final ChatController controller = c.read(chatControllerProvider.notifier);
      // Staged module + first message: gate blocks, loop finishes and
      // _executeRun removes the run object from _runs.
      await controller.activateModule('lateflow');
      await controller.send('start the module');
      expect(c.read(chatControllerProvider).setupRequest, isNotNull);

      // Submitting now must still work: the run is re-materialized from
      // the persisted module scope and the request re-derived.
      expect(
        await controller.submitModuleSetup('lateflow', <String, dynamic>{
          'email': 'late@example.com',
          'password': 'hunter2',
        }),
        isTrue,
      );

      final ChatState state = c.read(chatControllerProvider);
      expect(state.setupRequest, isNull);
      expect(js.moduleInvocations, hasLength(1));
      final Map<String, dynamic> stored = await moduleRuntime.readStoredSetup(
        state.sessionId!,
        mod.name,
      );
      expect(stored['email'], 'late@example.com');
      expect(state.messages.last.content, contains('late cycle ran'));
    });

    test('satisfied setup (command-path mirror) runs immediately', () async {
      final ProviderContainer c = await container();
      await installSetupModule('cmdready');
      js.nextResult = const JsRunResult(output: 'ready cycle');

      final ChatController controller = c.read(chatControllerProvider.notifier);
      await controller.send('start');
      final String sessionId = c.read(chatControllerProvider).sessionId!;
      // The module mirrored its configured state into the cooperative key
      // (what the onhomeroom text-command path does).
      await moduleRuntime.writeStoredSetup(
        sessionId,
        'cmdready',
        <String, dynamic>{'email': 'cmd@example.com', 'password': 'p'},
      );
      await controller.activateModule('cmdready');

      final ChatState state = c.read(chatControllerProvider);
      expect(js.moduleInvocations, hasLength(1));
      expect(state.setupRequest, isNull);
      expect(state.messages.last.content, contains('ready cycle'));
    });

    test('reopening the chat resurfaces the form request for an '
        'unconfigured module', () async {
      final ProviderContainer c = await container();
      await installSetupModule('reopen');

      final ChatController controller = c.read(chatControllerProvider.notifier);
      await controller.send('start');
      await controller.activateModule('reopen');
      expect(c.read(chatControllerProvider).setupRequest, isNotNull);

      // Leave to a draft and reopen the same chat from history.
      final String sessionId = c.read(chatControllerProvider).sessionId!;
      await controller.newChat();
      await controller.openChat(
        ChatSummary(id: sessionId, title: 't', updatedAt: DateTime.now()),
      );
      expect(c.read(chatControllerProvider).setupRequest, isNotNull);
      expect(c.read(chatControllerProvider).setupRequest!.moduleName, 'reopen');
    });

    test('deactivating the gated module clears its form request', () async {
      final ProviderContainer c = await container();
      await installSetupModule('gatedbye');

      final ChatController controller = c.read(chatControllerProvider.notifier);
      await controller.send('start');
      await controller.activateModule('gatedbye');
      expect(c.read(chatControllerProvider).setupRequest, isNotNull);
      await controller.deactivateModule('gatedbye');
      expect(c.read(chatControllerProvider).setupRequest, isNull);
      expect(c.read(chatControllerProvider).activeModules, isEmpty);
    });

    test('system prompt notes the per-chat setup fields', () async {
      final ProviderContainer c = await container();
      await installSetupModule('noted');
      js.nextResult = const JsRunResult(output: 'ran');

      final ChatController controller = c.read(chatControllerProvider.notifier);
      await controller.send('start');
      final String sessionId = c.read(chatControllerProvider).sessionId!;
      await moduleRuntime.writeStoredSetup(
        sessionId,
        'noted',
        <String, dynamic>{'email': 'a@b.c', 'password': 'p'},
      );
      await controller.activateModule('noted');

      final ScriptedLlmClient llm =
          c.read(llmClientProvider) as ScriptedLlmClient;
      llm.turns.clear();
      llm.turns.add(AssistantTurn(content: 'ok'));
      await controller.send('again');
      final List<Map<String, dynamic>> wire = llm.calls.last;
      final String system = (wire.first['content'] as String?) ?? '';
      expect(system, contains('# Active module: noted v1.0.0'));
      expect(system, contains('Setup (per chat, collected by the app'));
      // Labels fall back to the field keys when the manifest omits them.
      expect(system, contains('email, password'));
    });
  });
}
