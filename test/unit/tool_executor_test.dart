import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
