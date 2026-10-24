import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' as ar;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zagents/di.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/llm_client.dart';
import 'package:zagents/services/script_fetch_proxy.dart';
import 'package:zagents/services/skill_registry.dart';
import 'package:zagents/services/tool_executor.dart';

import '../support/test_doubles.dart';

void main() {
  late Directory docs;
  late Directory workspace;
  late SkillRegistry registry;
  late ScriptedJsRuntime js;
  late ToolExecutor executor;

  ar.ArchiveFile file(String path, List<int> bytes) =>
      ar.ArchiveFile(path, bytes.length, bytes);

  List<int> zipSkill({
    String name = 'demo-skill',
    String extraFrontMatter = '',
  }) {
    final ar.Archive archive = ar.Archive();
    archive.addFile(
      file(
        '$name/SKILL.md',
        utf8.encode(
          '---\nname: $name\ndescription: demo\nversion: 1.0.0\n'
          '$extraFrontMatter---\n\n# Demo\n',
        ),
      ),
    );
    archive.addFile(
      file(
        '$name/scripts/main.js',
        utf8.encode('console.log("ran", __zSkillArgs.x, process.env.NET);'),
      ),
    );
    return ar.ZipEncoder().encode(archive);
  }

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('skills_tools_test');
    workspace = await Directory.systemTemp.createTemp('skills_ws_test');
    registry = SkillRegistry(resolveBaseDir: () async => docs);
    js = ScriptedJsRuntime();
    executor = ToolExecutor(
      browser: ScriptedBrowserAutomation(
        workspace.path,
        writeScreenshot: false,
      ),
      resolveBaseDir: (_) async => workspace,
      isAutomationEnabled: () => true,
      js: js,
      skills: registry,
    );
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  group('skill_* tools through ToolExecutor', () {
    test('skill_install installs from a workspace archive and reports '
        'honestly', () async {
      // The agent downloads an archive into its workspace first.
      File('${workspace.path}${Platform.pathSeparator}demo.zip')
          .writeAsBytesSync(zipSkill());
      final ToolResult result = await executor.execute(
        'skill_install',
        <String, dynamic>{'source': 'demo.zip'},
        sessionId: 's1',
      );
      expect(result.ok, isTrue);
      expect(result.llmOutput, contains('Installed skill "demo-skill"'));
      expect(result.llmOutput, contains('Permissions declared'));
      expect(result.llmOutput, contains('skill_info("demo-skill")'));
      expect(await registry.list(), hasLength(1));
    });

    test('skill_install reports a missing workspace archive instead of '
        'pretending', () async {
      final ToolResult result = await executor.execute(
        'skill_install',
        <String, dynamic>{'source': 'nope.zip'},
        sessionId: 's1',
      );
      expect(result.ok, isFalse);
      expect(result.llmOutput, contains('not found'));
    });

    test('skill_list / skill_info expose skills with masked config', () async {
      await registry.installFromArchiveBytes(
        zipSkill(
          extraFrontMatter: 'config:\n  - name: API_KEY\n    secret: true\n    required: true\n',
        ),
        source: 'test',
      );
      final ToolResult list = await executor.execute(
        'skill_list',
        <String, dynamic>{},
      );
      expect(list.ok, isTrue);
      expect(list.llmOutput, contains('demo-skill'));
      expect(list.llmOutput, contains('needsConfig'));
      expect(list.llmOutput, contains('missing required config: API_KEY'));

      final ToolResult info = await executor.execute(
        'skill_info',
        <String, dynamic>{'name': 'demo-skill'},
      );
      expect(info.ok, isTrue);
      expect(info.llmOutput, contains('SKILL.md'));
      expect(info.llmOutput, contains('API_KEY(required, unset)'));
    });

    test('skill_config stores values, never echoes them back', () async {
      await registry.installFromArchiveBytes(
        zipSkill(
          extraFrontMatter: 'config:\n  - name: API_KEY\n    secret: true\n    required: true\n',
        ),
        source: 'test',
      );
      final ToolResult result = await executor.execute(
        'skill_config',
        <String, dynamic>{
          'name': 'demo-skill',
          'values': <String, dynamic>{'API_KEY': 'super-secret-42'},
        },
      );
      expect(result.ok, isTrue);
      expect(result.llmOutput, contains('keys: API_KEY'));
      expect(result.llmOutput, isNot(contains('super-secret-42')));
      // And the skill is now ready.
      final ToolResult list = await executor.execute(
        'skill_list',
        <String, dynamic>{},
      );
      expect(list.llmOutput, contains('[ready]'));
    });

    test('skill_run injects config as process.env + __zSkillArgs; output '
        'flows back', () async {
      await registry.installFromArchiveBytes(
        zipSkill(
          extraFrontMatter:
              'config:\n  - name: NET\n    secret: false\n    required: true\n',
        ),
        source: 'test',
      );
      await registry.writeConfig(
        (await registry.list()).first,
        <String, String>{'NET': 'mainnet'},
      );
      final ToolResult result = await executor.execute(
        'skill_run',
        <String, dynamic>{
          'name': 'demo-skill',
          'script': 'scripts/main.js',
          'args': <String, dynamic>{'x': 7},
        },
        sessionId: 's1',
      );
      expect(result.ok, isTrue);
      // The scripted runtime echoes a canned result; the REAL assertions
      // are the code the runtime received: env preamble + script body.
      expect(js.runs, hasLength(1));
      expect(js.runs.first, contains('__zSkillArgs'));
      expect(js.runs.first, contains('"NET":"mainnet"'));
      expect(js.runs.first, contains('console.log("ran"'));
      expect(result.llmOutput, contains('=> "ok"'));
    });

    test(
      'skill_run refuses non-JS scripts and missing scripts honestly',
      () async {
        await registry.installFromArchiveBytes(zipSkill(), source: 'test');
        final ToolResult bash = await executor.execute(
          'skill_run',
          <String, dynamic>{'name': 'demo-skill', 'script': 'run.sh'},
        );
        expect(bash.ok, isFalse);
        expect(bash.llmOutput, contains('unsupported'));

        final ToolResult missing = await executor.execute(
          'skill_run',
          <String, dynamic>{'name': 'demo-skill', 'script': 'scripts/nope.js'},
        );
        expect(missing.ok, isFalse);
        expect(missing.llmOutput, contains('not found'));

        final ToolResult traversal = await executor.execute(
          'skill_run',
          <String, dynamic>{'name': 'demo-skill', 'script': '../other.js'},
        );
        expect(traversal.ok, isFalse);
        expect(traversal.llmOutput, contains('relative'));
      },
    );

    test('skill_run gates on missing required config', () async {
      await registry.installFromArchiveBytes(
        zipSkill(
          extraFrontMatter: 'config:\n  - name: TOKEN\n    secret: true\n    required: true\n',
        ),
        source: 'test',
      );
      final ToolResult result = await executor.execute(
        'skill_run',
        <String, dynamic>{'name': 'demo-skill', 'script': 'scripts/main.js'},
      );
      expect(result.ok, isFalse);
      expect(result.llmOutput, contains('missing required config: TOKEN'));
      expect(js.runs, isEmpty, reason: 'nothing may execute without config');
    });

    test('skill_remove uninstalls', () async {
      await registry.installFromArchiveBytes(zipSkill(), source: 'test');
      final ToolResult result = await executor.execute(
        'skill_remove',
        <String, dynamic>{'name': 'demo-skill'},
      );
      expect(result.ok, isTrue);
      expect(await registry.list(), isEmpty);
    });
  });

  group('ScriptFetchProxy (real network semantics)', () {
    test(
      'GET text: status, body, UA injected from settings identity',
      () async {
        String? seenUa;
        final ScriptFetchProxy proxy = ScriptFetchProxy(
          client: MockClient((http.Request request) async {
            seenUa = request.headers['User-Agent'];
            return http.Response(
              '{"ok":true}',
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
          resolveUserAgent: () => 'ZAgentsTest/1.0',
        );
        final Map<String, dynamic>? res = await proxy.call(
          'https://example.com/api',
          'GET',
          null,
        );
        expect(res!['status'], 200);
        expect(res['body'], '{"ok":true}');
        expect(seenUa, 'ZAgentsTest/1.0');
      },
    );

    test('POST JSON body + header passthrough (UA not overridable)', () async {
      final List<String> seen = <String>[];
      final ScriptFetchProxy proxy = ScriptFetchProxy(
        client: MockClient((http.Request request) async {
          seen
            ..add(request.body)
            ..add(request.headers['X-Custom'] ?? '')
            ..add(request.headers['User-Agent'] ?? '');
          return http.Response(
            'created',
            201,
            headers: <String, String>{'content-type': 'text/plain'},
          );
        }),
        resolveUserAgent: () => 'Fixed/1.0',
      );
      final Map<String, dynamic>? res = await proxy.call(
        'https://example.com/api',
        'POST',
        '{"a":1}',
        headers: <String, String>{'X-Custom': 'v', 'User-Agent': 'evil/9'},
      );
      expect(res!['status'], 201);
      expect(seen[0], '{"a":1}');
      expect(seen[1], 'v');
      expect(seen[2], 'Fixed/1.0', reason: 'UA override is dropped');
    });

    test(
      'binary responses travel as base64 for arrayBuffer() consumers',
      () async {
        final List<int> payload = <int>[0, 1, 2, 255, 128, 7];
        final ScriptFetchProxy proxy = ScriptFetchProxy(
          client: MockClient(
            (http.Request request) async => http.Response.bytes(
              payload,
              200,
              headers: <String, String>{
                'content-type': 'application/octet-stream',
              },
            ),
          ),
        );
        final Map<String, dynamic>? res = await proxy.call(
          'https://example.com/pack',
          'GET',
          null,
        );
        expect(res!['body'], isEmpty);
        expect(base64Decode(res['bodyBase64'] as String), payload);
      },
    );

    test('non-2xx status is REPORTED, not hidden', () async {
      final ScriptFetchProxy proxy = ScriptFetchProxy(
        client: MockClient(
          (http.Request request) async => http.Response('nope', 404),
        ),
      );
      final Map<String, dynamic>? res = await proxy.call(
        'https://example.com/x',
        'GET',
        null,
      );
      expect(res!['status'], 404);
    });

    test('rejected schemes fail cleanly', () async {
      final ScriptFetchProxy proxy = ScriptFetchProxy(
        client: MockClient(
          (http.Request request) async => http.Response('', 200),
        ),
      );
      final Map<String, dynamic>? res = await proxy.call(
        'file:///etc',
        'GET',
        null,
      );
      expect(res!['ok'], isFalse);
      expect(res['error'], contains('http'));
    });
  });

  group('skills in the system prompt (discovery without reinstalling)', () {
    test('the agent wire lists installed skills with status and manual '
        'pointer', () async {
      final ScriptedLlmClient llm = ScriptedLlmClient(<AssistantTurn>[
        AssistantTurn(content: 'ok'),
      ]);
      final ProviderContainer container = ProviderContainer(
        overrides: testOverrides(
          llm: llm,
          dir: docs,
          settings: AppSettings(apiKey: 'k', autoTitle: false),
        ),
      );
      addTearDown(container.dispose);
      // Install through the SAME registry instance the controller reads.
      final SkillRegistry appRegistry = container.read(skillRegistryProvider);
      await appRegistry.installFromArchiveBytes(
        zipSkill(
          extraFrontMatter: 'config:\n  - name: TOKEN\n    secret: true\n    required: true\n',
        ),
        source: 'test',
      );

      await container.read(chatControllerProvider.notifier).send('hi');
      expect(llm.calls, isNotEmpty);
      final String system = llm.calls.first.first['content'] as String;
      expect(system, contains('# Installed skills (available in every chat)'));
      expect(system, contains('demo-skill v1.0.0'));
      expect(system, contains('needs config: TOKEN'));
      expect(system, contains('skill_info("demo-skill")'));
      expect(system, contains('request_confirmation'));

      // And WITHOUT any skill installed the section is absent.
      await appRegistry.remove('demo-skill');
      await container.read(chatControllerProvider.notifier).send('again');
      final String system2 = llm.calls.last.first['content'] as String;
      expect(system2, isNot(contains('# Installed skills')));
    });
  });
}
