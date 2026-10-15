import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zagents/services/file_system_service.dart';
import 'package:zagents/services/js_runtime.dart';
import 'package:zagents/services/npm_service.dart';
import 'package:zagents/services/tool_executor.dart';
import 'package:zagents/services/web_fetcher.dart';

import '../support/test_doubles.dart';

void main() {
  late Directory tempDir;
  late ScriptedBrowserAutomation scriptedBrowser;
  late ToolExecutor executor;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_exec_test');
    scriptedBrowser = ScriptedBrowserAutomation(tempDir.path);
    executor = ToolExecutor(
      browser: scriptedBrowser,
      resolveBaseDir: (_) async => tempDir,
      isAutomationEnabled: () => true,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('browser_navigate returns page info JSON', () async {
    final ToolResult result = await executor.execute(
      'browser_navigate',
      <String, dynamic>{'url': 'https://example.com'},
    );
    expect(result.ok, isTrue);
    expect(result.llmOutput, contains('Example Domain'));
    expect(scriptedBrowser.calls.first, 'navigate:https://example.com');
  });

  test('browser_screenshot saves PNG and returns path', () async {
    final ToolResult result = await executor.execute(
      'browser_screenshot',
      <String, dynamic>{},
    );
    expect(result.ok, isTrue);
    expect(result.screenshotPath, isNotNull);
    expect(File(result.screenshotPath!).existsSync(), isTrue);
  });

  test('write_file + read_file roundtrip', () async {
    final ToolResult write = await executor.execute(
      'write_file',
      <String, dynamic>{'path': 'docs/report.md', 'content': '# Laporan'},
    );
    expect(write.ok, isTrue);
    expect(File('${tempDir.path}/docs/report.md').existsSync(), isTrue);

    final ToolResult read = await executor.execute(
      'read_file',
      <String, dynamic>{'path': 'docs/report.md'},
    );
    expect(read.ok, isTrue);
    expect(read.llmOutput, '# Laporan');
  });

  test('path traversal is rejected', () async {
    final ToolResult result = await executor.execute(
      'read_file',
      <String, dynamic>{'path': '../../etc/passwd'},
    );
    expect(result.ok, isFalse);
  });

  test('browser tools blocked when automation disabled', () async {
    final ToolExecutor guarded = ToolExecutor(
      browser: scriptedBrowser,
      resolveBaseDir: (_) async => tempDir,
      isAutomationEnabled: () => false,
    );
    final ToolResult result = await guarded.execute(
      'browser_navigate',
      <String, dynamic>{'url': 'x'},
    );
    expect(result.ok, isFalse);
    expect(result.llmOutput, contains('disabled'));
  });

  test('unknown tool returns error result instead of throwing', () async {
    final ToolResult result = await executor.execute(
      'nope',
      <String, dynamic>{},
    );
    expect(result.ok, isFalse);
    expect(result.llmOutput, contains('Unknown tool'));
  });

  test('browser interface rejects empty URL', () async {
    final ToolResult result = await executor.execute(
      'browser_navigate',
      <String, dynamic>{'url': ''},
    );
    expect(result.ok, isFalse);
  });

  test('browser platform failure degrades to error result, no crash', () async {
    final ToolExecutor crashing = ToolExecutor(
      browser: ThrowingBrowserAutomation(),
      resolveBaseDir: (_) async => tempDir,
      isAutomationEnabled: () => true,
    );
    for (final String tool in <String>[
      'browser_navigate',
      'browser_click',
      'browser_type',
      'browser_scroll',
      'browser_screenshot',
      'browser_extract_text',
      'run_js',
    ]) {
      final ToolResult result = await crashing.execute(tool, <String, dynamic>{
        'url': 'https://example.com',
        'code': '1',
      });
      expect(result.ok, isFalse, reason: '$tool must not throw');
      expect(result.llmOutput, isNotEmpty);
    }
  });

  test('read_file on binary content returns error result, no crash', () async {
    final File binary = File(
      '${tempDir.path}${Platform.pathSeparator}blob.bin',
    );
    await binary.writeAsBytes(<int>[0x00, 0xFF, 0xFE, 0x80, 0x81]);
    final ToolResult result = await executor.execute(
      'read_file',
      <String, dynamic>{'path': 'blob.bin'},
    );
    // Either read fine or degraded to an error — never a crash.
    expect(result.ok, anyOf(isTrue, isFalse));
    expect(result.llmOutput, isNotEmpty);
  });

  test('write_file failure degrades to error result, no crash', () async {
    // A FILE occupies the intermediate path segment, so creating the
    // parent directory of the target fails with a filesystem error.
    final File blocker = File('${tempDir.path}${Platform.pathSeparator}sub');
    await blocker.writeAsString('x');
    final ToolResult result = await executor.execute(
      'write_file',
      <String, dynamic>{'path': 'sub/dir/file.txt', 'content': 'hi'},
    );
    expect(result.ok, isFalse);
    expect(result.llmOutput, contains('Could not write file'));
  });

  test('node_run executes through the injected JS runtime', () async {
    final ScriptedJsRuntime js = ScriptedJsRuntime(
      const JsRunResult(output: 'hello from node', result: '"42"'),
    );
    final ToolExecutor nodeExecutor = ToolExecutor(
      browser: scriptedBrowser,
      resolveBaseDir: (_) async => tempDir,
      isAutomationEnabled: () => true,
      js: js,
    );
    final ToolResult result = await nodeExecutor.execute(
      'node_run',
      <String, dynamic>{'code': 'return 42;'},
    );
    expect(result.ok, isTrue);
    expect(result.llmOutput, contains('hello from node'));
    expect(result.llmOutput, contains('=> "42"'));
    expect(js.runs.single, 'return 42;');
  });

  test('node_run surfaces script errors without crashing', () async {
    final ScriptedJsRuntime js = ScriptedJsRuntime(
      const JsRunResult(output: 'starting…', error: 'boom'),
    );
    final ToolExecutor nodeExecutor = ToolExecutor(
      browser: scriptedBrowser,
      resolveBaseDir: (_) async => tempDir,
      isAutomationEnabled: () => true,
      js: js,
    );
    final ToolResult result = await nodeExecutor.execute(
      'node_run',
      <String, dynamic>{'code': 'throw new Error("boom")'},
    );
    expect(result.ok, isFalse);
    expect(result.llmOutput, contains('starting…'));
    expect(result.llmOutput, contains('boom'));
  });

  test(
    'node tools degrade gracefully when the runtime is unavailable',
    () async {
      for (final String tool in <String>[
        'node_run',
        'node_install',
        'node_remove',
      ]) {
        final ToolResult result = await executor.execute(
          tool,
          <String, dynamic>{'code': '1', 'package': 'x'},
        );
        expect(result.ok, isFalse, reason: '$tool must not throw');
        expect(result.llmOutput, isNotEmpty);
      }
    },
  );

  test('node_install / node_remove go through the npm service', () async {
    final NpmService npm = NpmService(
      resolveBaseDir: () async => tempDir,
      client: MockClient(
        (http.Request request) async => http.Response('not found', 404),
      ),
    );
    final ToolExecutor nodeExecutor = ToolExecutor(
      browser: scriptedBrowser,
      resolveBaseDir: (_) async => tempDir,
      isAutomationEnabled: () => true,
      npm: npm,
    );

    final ToolResult fail = await nodeExecutor.execute(
      'node_install',
      <String, dynamic>{'package': 'missing-pkg'},
    );
    expect(fail.ok, isFalse);

    // Create an installed package fixture, then remove it via the tool.
    final Directory pkg = Directory('${tempDir.path}/node_modules/left-pad');
    await pkg.create(recursive: true);
    await File('${pkg.path}/package.json')
        .writeAsString('{"name":"left-pad","version":"1.0.0"}');
    final ToolResult removed = await nodeExecutor.execute(
      'node_remove',
      <String, dynamic>{'package': 'left-pad'},
    );
    expect(removed.ok, isTrue);
    expect(pkg.existsSync(), isFalse);
  });

  group('todo_write (plan tool)', () {
    test('valid plan returns progress json for the model', () async {
      final ToolResult result = await executor.execute(
        'todo_write',
        <String, dynamic>{
          'todos': <dynamic>[
            <String, dynamic>{'content': 'research', 'status': 'completed'},
            <String, dynamic>{'content': 'draft', 'status': 'in_progress'},
            <String, dynamic>{'content': 'review', 'status': 'pending'},
          ],
        },
      );
      expect(result.ok, isTrue);
      expect(result.llmOutput, contains('"total":3'));
      expect(result.llmOutput, contains('"completed":1'));
      expect(result.llmOutput, contains('"in_progress":1'));
      expect(result.llmOutput, contains('"pending":1'));
      expect(result.displayText, 'plan 1/3');
    });

    test(
      'missing or empty todos is an error the model can retry from',
      () async {
        final ToolResult missing = await executor.execute(
          'todo_write',
          <String, dynamic>{},
        );
        expect(missing.ok, isFalse);
        expect(missing.llmOutput, contains('todos'));

        final ToolResult empty = await executor.execute(
          'todo_write',
          <String, dynamic>{
            'todos': <dynamic>[
              <String, dynamic>{'status': 'pending'},
            ],
          },
        );
        expect(empty.ok, isFalse);
      },
    );

    test('todo_write is never gated by the automation switch', () async {
      final ToolExecutor gated = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (_) async => tempDir,
        isAutomationEnabled: () => false,
      );
      final ToolResult result = await gated.execute(
        'todo_write',
        <String, dynamic>{
          'todos': <dynamic>[
            <String, dynamic>{'content': 'step', 'status': 'pending'},
          ],
        },
      );
      expect(result.ok, isTrue);
    });
  });

  group('archive tools (zip_file / unzip_file)', () {
    late ToolExecutor fsExecutor;

    setUp(() {
      fsExecutor = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (_) async => tempDir,
        isAutomationEnabled: () => true,
        fs: FileSystemService(resolveBaseDir: () async => tempDir),
      );
    });

    test(
      'unzip_file extracts an archive and lists the JS files inside',
      () async {
        // Build a source folder that mimics an uploaded JS project, then
        // compress it with the very same service the tool delegates to.
        final Directory src = Directory('${tempDir.path}/proj');
        src.createSync(recursive: true);
        File('${src.path}/index.js').writeAsStringSync("console.log('hi');");
        final Directory lib = Directory('${src.path}/lib');
        lib.createSync(recursive: true);
        File('${lib.path}/util.js').writeAsStringSync('module.exports = 42;');
        final String zipRel = await FileSystemService(
          resolveBaseDir: () async => tempDir,
        ).zip('proj');

        final ToolResult result = await fsExecutor.execute(
          'unzip_file',
          <String, dynamic>{'path': zipRel},
        );
        expect(result.ok, isTrue);
        // 'proj' still exists next to the archive -> extraction lands in
        // proj_extracted and both extracted files are listed for the model.
        expect(result.llmOutput, contains('proj_extracted'));
        expect(result.llmOutput, contains('proj_extracted/index.js'));
        expect(result.llmOutput, contains('proj_extracted/lib/util.js'));
        expect(
          File('${tempDir.path}/proj_extracted/index.js').readAsStringSync(),
          "console.log('hi');",
        );
      },
    );

    test(
      'unzip_file without a password reports password-protected archives',
      () async {
        final Directory uploads = Directory('${tempDir.path}/uploads');
        uploads.createSync(recursive: true);
        File('${uploads.path}/locked.zip').writeAsBytesSync(
          File('test/fixtures/zipcrypto.zip').readAsBytesSync(),
        );

        final ToolResult result = await fsExecutor.execute(
          'unzip_file',
          <String, dynamic>{'path': 'uploads/locked.zip'},
        );
        expect(result.ok, isFalse);
        expect(result.llmOutput, contains('password-protected'));
        expect(result.llmOutput, contains('password'));
      },
    );

    test(
      'unzip_file decrypts encrypted archives when given the password',
      () async {
        final Directory uploads = Directory('${tempDir.path}/uploads');
        uploads.createSync(recursive: true);
        File('${uploads.path}/locked.zip').writeAsBytesSync(
          File('test/fixtures/zipcrypto.zip').readAsBytesSync(),
        );

        final ToolResult result = await fsExecutor.execute(
          'unzip_file',
          <String, dynamic>{
            'path': 'uploads/locked.zip',
            'password': 'fixt-pass-42',
          },
        );
        expect(result.ok, isTrue);
        expect(result.llmOutput, contains('uploads/locked/hello.txt'));
        expect(
          File('${tempDir.path}/uploads/locked/hello.txt').readAsStringSync(),
          'Hello from an encrypted zip! ZAgents can decrypt this.\n',
        );
      },
    );

    test(
      'unzip_file with a wrong password tells the model to re-ask',
      () async {
        final Directory uploads = Directory('${tempDir.path}/uploads');
        uploads.createSync(recursive: true);
        File('${uploads.path}/locked.zip').writeAsBytesSync(
          File('test/fixtures/zipcrypto.zip').readAsBytesSync(),
        );

        final ToolResult result = await fsExecutor.execute(
          'unzip_file',
          <String, dynamic>{'path': 'uploads/locked.zip', 'password': 'guess'},
        );
        expect(result.ok, isFalse);
        expect(result.llmOutput, contains('wrong'));
        expect(result.llmOutput, contains('"password"'));
      },
    );

    test('zip_file compresses a folder into a .zip next to it', () async {
      final Directory notes = Directory('${tempDir.path}/notes');
      notes.createSync(recursive: true);
      File('${notes.path}/a.txt').writeAsStringSync('hello');
      final ToolResult result = await fsExecutor.execute(
        'zip_file',
        <String, dynamic>{'path': 'notes'},
      );
      expect(result.ok, isTrue);
      expect(result.llmOutput, contains('notes.zip'));
      expect(File('${tempDir.path}/notes.zip').existsSync(), isTrue);
    });

    test('archive tools degrade gracefully without the fs service', () async {
      final ToolResult result = await executor.execute(
        'unzip_file',
        <String, dynamic>{'path': 'whatever.zip'},
      );
      expect(result.ok, isFalse);
      expect(result.llmOutput, contains('not available'));
    });

    test('path traversal and empty path are rejected', () async {
      final ToolResult bad = await fsExecutor.execute(
        'unzip_file',
        <String, dynamic>{'path': '../../x.zip'},
      );
      expect(bad.ok, isFalse);
      final ToolResult empty = await fsExecutor.execute(
        'zip_file',
        <String, dynamic>{'path': '  '},
      );
      expect(empty.ok, isFalse);
    });
  });

  group('per-session workspace isolation', () {
    late Map<String, Directory> roots;

    setUp(() async {
      roots = <String, Directory>{
        'a': Directory('${tempDir.path}/sessions/a'),
        'b': Directory('${tempDir.path}/sessions/b'),
      };
      for (final Directory dir in roots.values) {
        await dir.create(recursive: true);
      }
    });

    FileSystemService fsForSid(String? sid) => FileSystemService(
      resolveBaseDir: () async => sid == null ? tempDir : roots[sid] ?? tempDir,
    );

    test('write_file in one session is invisible to another session', () async {
      final ToolExecutor executor = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (String? sid) async =>
            sid == null ? tempDir : roots[sid] ?? tempDir,
        isAutomationEnabled: () => true,
        fsFor: fsForSid,
      );

      final ToolResult write = await executor.execute(
        'write_file',
        <String, dynamic>{'path': 'notes.txt', 'content': 'secret-a'},
        sessionId: 'a',
      );
      expect(write.ok, isTrue);

      final ToolResult readA = await executor.execute(
        'read_file',
        <String, dynamic>{'path': 'notes.txt'},
        sessionId: 'a',
      );
      expect(readA.ok, isTrue);
      expect(readA.llmOutput, 'secret-a');

      final ToolResult readB = await executor.execute(
        'read_file',
        <String, dynamic>{'path': 'notes.txt'},
        sessionId: 'b',
      );
      expect(readB.ok, isFalse);
      expect(readB.llmOutput, contains('File not found'));
    });

    test('zip_file archives stay inside their own session workspace', () async {
      final ToolExecutor executor = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (String? sid) async =>
            sid == null ? tempDir : roots[sid] ?? tempDir,
        isAutomationEnabled: () => true,
        fsFor: fsForSid,
      );
      Directory('${roots['a']!.path}/proj').createSync();
      File('${roots['a']!.path}/proj/data.txt').writeAsStringSync('data');

      final ToolResult zip = await executor.execute(
        'zip_file',
        <String, dynamic>{'path': 'proj'},
        sessionId: 'a',
      );
      expect(zip.ok, isTrue);

      final ToolResult readB = await executor.execute(
        'read_file',
        <String, dynamic>{'path': 'proj.zip'},
        sessionId: 'b',
      );
      expect(readB.ok, isFalse);
      expect(readB.llmOutput, contains('File not found'));
    });

    test('browser screenshots land in the session workspace', () async {
      final ToolExecutor executor = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (String? sid) async =>
            sid == null ? tempDir : roots[sid] ?? tempDir,
        isAutomationEnabled: () => true,
      );
      final ToolResult shot = await executor.execute(
        'browser_screenshot',
        <String, dynamic>{},
        sessionId: 'a',
      );
      expect(shot.ok, isTrue);
      expect(
        Directory('${roots['a']!.path}/browser_shots').existsSync(),
        isTrue,
      );
      expect(
        Directory('${roots['b']!.path}/browser_shots').existsSync(),
        isFalse,
      );
    });

    test('node_run works inside the session but npm stays global', () async {
      final RecordingJsRuntime js = RecordingJsRuntime();
      final ToolExecutor executor = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (String? sid) async =>
            sid == null ? tempDir : roots[sid] ?? tempDir,
        isAutomationEnabled: () => true,
        js: js,
      );
      final ToolResult run = await executor.execute(
        'node_run',
        <String, dynamic>{'code': 'return 1;'},
        sessionId: 'a',
      );
      expect(run.ok, isTrue);
      expect(js.workingDirs.single, roots['a']!.path);
      expect(js.moduleRoots.single, <String>[
        '${tempDir.path}${Platform.pathSeparator}node_modules',
      ]);
    });
  });

  group('web_fetch + git tools (v1.16.0)', () {
    test('web_fetch returns the fetcher output', () async {
      final ToolExecutor withFetcher = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (_) async => tempDir,
        isAutomationEnabled: () => true,
        fetcher: WebFetcher(
          client: MockClient(
            (http.Request request) async => http.Response(
              'hello web world',
              200,
              headers: <String, String>{'content-type': 'text/plain'},
            ),
          ),
        ),
      );
      final ToolResult result = await withFetcher.execute(
        'web_fetch',
        <String, dynamic>{'url': 'https://example.test/page'},
      );
      expect(result.ok, isTrue);
      expect(result.llmOutput, 'hello web world');
      expect(result.displayText, contains('example.test'));
    });

    test('web_fetch without a fetcher degrades gracefully', () async {
      final ToolResult result = await executor.execute(
        'web_fetch',
        <String, dynamic>{'url': 'https://example.test/page'},
      );
      expect(result.ok, isFalse);
      expect(result.llmOutput, contains('not available'));
    });

    test(
      'git_clone builds an isomorphic-git script inside the sandbox',
      () async {
        final RespondingJsRuntime js = RespondingJsRuntime(
          (String code) => const JsRunResult(
            output: 'Cloned 3 top-level entries',
            result: '"clone ok"',
          ),
        );
        final ToolExecutor gitExecutor = ToolExecutor(
          browser: scriptedBrowser,
          resolveBaseDir: (_) async => tempDir,
          isAutomationEnabled: () => true,
          js: js,
          npm: _ScriptedNpm(hasIsoGit: true),
        );
        final ToolResult result = await gitExecutor.execute(
          'git_clone',
          <String, dynamic>{'url': 'https://github.com/user/repo.git'},
          sessionId: 'a',
        );
        expect(result.ok, isTrue);
        expect(js.scripts.single, contains('git.clone'));
        expect(js.scripts.single, contains('isomorphic-git'));
        // Destination defaults to the repo name, inside the session sandbox.
        expect(
          js.scripts.single,
          contains('${tempDir.path}${Platform.pathSeparator}repo'),
        );
        expect(js.workingDirs.single, tempDir.path);
        expect(js.moduleRoots.single, <String>[
          '${tempDir.path}${Platform.pathSeparator}node_modules',
        ]);
      },
    );

    test('git tools auto-install isomorphic-git when missing', () async {
      final _ScriptedNpm npm = _ScriptedNpm(hasIsoGit: false);
      final ToolExecutor gitExecutor = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (_) async => tempDir,
        isAutomationEnabled: () => true,
        js: RespondingJsRuntime(
          (String code) => const JsRunResult(output: 'branch: main'),
        ),
        npm: npm,
      );
      final ToolResult result = await gitExecutor.execute(
        'git_status',
        <String, dynamic>{},
        sessionId: 'a',
      );
      expect(result.ok, isTrue);
      expect(npm.installed, <String>['isomorphic-git']);
      expect(result.llmOutput, contains('branch: main'));
    });

    test(
      'git tools fail with a clear error when npm cannot provide the package',
      () async {
        final ToolExecutor gitExecutor = ToolExecutor(
          browser: scriptedBrowser,
          resolveBaseDir: (_) async => tempDir,
          isAutomationEnabled: () => true,
          js: RespondingJsRuntime(
            (String code) => const JsRunResult(output: ''),
          ),
          npm: _ScriptedNpm(hasIsoGit: false, installOk: false),
        );
        final ToolResult result = await gitExecutor.execute(
          'git_log',
          <String, dynamic>{},
          sessionId: 'a',
        );
        expect(result.ok, isFalse);
        expect(result.llmOutput, contains('isomorphic-git'));
      },
    );

    test('git_commit requires message + author identity', () async {
      final ToolExecutor gitExecutor = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (_) async => tempDir,
        isAutomationEnabled: () => true,
        js: RespondingJsRuntime(
          (String code) => const JsRunResult(output: 'x'),
        ),
        npm: _ScriptedNpm(hasIsoGit: true),
      );
      final ToolResult noAuthor = await gitExecutor.execute(
        'git_commit',
        <String, dynamic>{'message': 'hi'},
        sessionId: 'a',
      );
      expect(noAuthor.ok, isFalse);
      expect(noAuthor.llmOutput, contains('authorName'));
    });

    test('git_clone rejects destination traversal', () async {
      final ToolExecutor gitExecutor = ToolExecutor(
        browser: scriptedBrowser,
        resolveBaseDir: (_) async => tempDir,
        isAutomationEnabled: () => true,
        js: RespondingJsRuntime(
          (String code) => const JsRunResult(output: 'x'),
        ),
        npm: _ScriptedNpm(hasIsoGit: true),
      );
      final ToolResult result = await gitExecutor.execute(
        'git_clone',
        <String, dynamic>{
          'url': 'https://github.com/user/repo.git',
          'destination': '../escape',
        },
        sessionId: 'a',
      );
      expect(result.ok, isFalse);
      expect(result.llmOutput, contains('Invalid destination'));
    });
  });
}

/// NpmService test double: reports whether isomorphic-git is already installed and
/// records installs instead of touching the registry.
class _ScriptedNpm extends NpmService {
  _ScriptedNpm({required this.hasIsoGit, this.installOk = true})
    : super(resolveBaseDir: () async => Directory.systemTemp);

  final bool hasIsoGit;
  final bool installOk;
  final List<String> installed = <String>[];

  @override
  Future<List<InstalledModule>> listInstalled() async => hasIsoGit
      ? <InstalledModule>[
          InstalledModule(
            name: 'isomorphic-git',
            version: '1.25.0',
            path: '/stub/isomorphic-git',
          ),
        ]
      : const <InstalledModule>[];

  @override
  Future<NpmInstallResult> install(String name, {String? version}) async {
    installed.add(name);
    return NpmInstallResult(
      ok: installOk,
      message: installOk ? 'installed $name' : 'registry offline',
    );
  }
}

/// JsRuntime test double that records generated scripts (assertions run on the
/// isomorphic-git calls) and returns canned results.
class RespondingJsRuntime implements JsRuntime {
  RespondingJsRuntime(this.respond);

  final JsRunResult Function(String code) respond;
  final List<String> scripts = <String>[];
  final List<String?> workingDirs = <String?>[];
  final List<List<String>> moduleRoots = <List<String>>[];

  @override
  Future<JsRunResult> run(
    String code, {
    List<String> moduleRoots = const <String>[],
    String? workingDir,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    scripts.add(code);
    workingDirs.add(workingDir);
    this.moduleRoots.add(moduleRoots);
    return respond(code);
  }

  @override
  Future<JsRunResult> runModule(ModuleInvocation invocation) async =>
      respond(invocation.entrySource);

  @override
  void dispose() {}
}

/// JsRuntime test double that records workingDir/moduleRoots for isolation tests.
class RecordingJsRuntime implements JsRuntime {
  final List<String?> workingDirs = <String?>[];
  final List<List<String>> moduleRoots = <List<String>>[];

  @override
  Future<JsRunResult> run(
    String code, {
    List<String> moduleRoots = const <String>[],
    String? workingDir,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    workingDirs.add(workingDir);
    this.moduleRoots.add(moduleRoots);
    return const JsRunResult(output: 'ok', result: '"ok"');
  }

  @override
  Future<JsRunResult> runModule(ModuleInvocation invocation) async =>
      const JsRunResult(output: 'ok', result: '"ok"');

  @override
  void dispose() {}
}
