import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zagents/services/file_system_service.dart';
import 'package:zagents/services/js_runtime.dart';
import 'package:zagents/services/npm_service.dart';
import 'package:zagents/services/tool_executor.dart';

import '../fakes/fakes.dart';

void main() {
  late Directory tempDir;
  late FakeBrowserAutomation fakeBrowser;
  late ToolExecutor executor;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_exec_test');
    fakeBrowser = FakeBrowserAutomation(tempDir.path);
    executor = ToolExecutor(
      browser: fakeBrowser,
      resolveBaseDir: () async => tempDir,
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
    expect(fakeBrowser.calls.first, 'navigate:https://example.com');
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
      browser: fakeBrowser,
      resolveBaseDir: () async => tempDir,
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
      resolveBaseDir: () async => tempDir,
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
    final FakeJsRuntime js = FakeJsRuntime(
      const JsRunResult(output: 'hello from node', result: '"42"'),
    );
    final ToolExecutor nodeExecutor = ToolExecutor(
      browser: fakeBrowser,
      resolveBaseDir: () async => tempDir,
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
    final FakeJsRuntime js = FakeJsRuntime(
      const JsRunResult(output: 'starting…', error: 'boom'),
    );
    final ToolExecutor nodeExecutor = ToolExecutor(
      browser: fakeBrowser,
      resolveBaseDir: () async => tempDir,
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
      browser: fakeBrowser,
      resolveBaseDir: () async => tempDir,
      isAutomationEnabled: () => true,
      npm: npm,
    );

    final ToolResult fail = await nodeExecutor.execute(
      'node_install',
      <String, dynamic>{'package': 'missing-pkg'},
    );
    expect(fail.ok, isFalse);

    // Create a fake installed package, then remove it via the tool.
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
        browser: fakeBrowser,
        resolveBaseDir: () async => tempDir,
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
        browser: fakeBrowser,
        resolveBaseDir: () async => tempDir,
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
}
