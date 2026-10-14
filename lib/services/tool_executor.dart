import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import 'browser_automation.dart';
import 'file_system_service.dart';
import 'js_runtime.dart';
import 'npm_service.dart';

/// Result of executing one tool.
class ToolResult {
  const ToolResult({
    required this.ok,
    required this.llmOutput,
    this.screenshotPath,
    this.displayText,
  });

  final bool ok;

  /// Content sent back to the model as the tool message.
  final String llmOutput;

  /// Optional screenshot path to render in the UI.
  final String? screenshotPath;

  /// Optional short label for the UI.
  final String? displayText;
}

/// Executes agent tools: embedded browser automation, page JS, file IO
/// scoped to the app documents directory, and the embedded Node.js-style
/// JS runtime with npm package management.
class ToolExecutor {
  ToolExecutor({
    required this.browser,
    required this.resolveBaseDir,
    required this.isAutomationEnabled,
    this.js,
    this.npm,
    this.fs,
  });

  final BrowserAutomation browser;
  final Future<Directory> Function() resolveBaseDir;
  final bool Function() isAutomationEnabled;

  /// Embedded JS runtime + npm manager. Nullable so existing tests and
  /// minimal setups keep working; the node tools degrade gracefully.
  final JsRuntime? js;
  final NpmService? npm;

  /// File workspace (zip/unzip + sandboxed paths). Nullable for legacy
  /// tests; the zip tools degrade gracefully when absent.
  final FileSystemService? fs;

  static const Set<String> _browserTools = <String>{
    'browser_navigate',
    'browser_click',
    'browser_type',
    'browser_scroll',
    'browser_screenshot',
    'browser_extract_text',
    'run_js',
  };

  Future<ToolResult> execute(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case 'todo_write':
          return _todoWrite(args);
        case 'browser_navigate':
          return await _navigate(args);
        case 'browser_click':
          return await _click(args);
        case 'browser_type':
          return await _type(args);
        case 'browser_scroll':
          return await _scroll(args);
        case 'browser_screenshot':
          return await _screenshot();
        case 'browser_extract_text':
          return await _extract(args);
        case 'run_js':
          return await _runJs(args);
        case 'read_file':
          return await _readFile(args);
        case 'write_file':
          return await _writeFile(args);
        case 'unzip_file':
          return await _unzipFile(args);
        case 'zip_file':
          return await _zipFile(args);
        case 'node_run':
          return await _nodeRun(args);
        case 'node_install':
          return await _nodeInstall(args);
        case 'node_remove':
          return await _nodeRemove(args);
        default:
          return ToolResult(ok: false, llmOutput: 'Unknown tool: $name');
      }
    } catch (e) {
      // Never let a tool failure crash the agent loop: degrade to a result
      // the model can read and retry around.
      return ToolResult(ok: false, llmOutput: 'Tool $name failed: $e');
    }
  }

  ToolResult? _automationGuard(String name) {
    if (_browserTools.contains(name) && !isAutomationEnabled()) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Browser automation is disabled in Settings.',
      );
    }
    return null;
  }

  Future<ToolResult> _navigate(Map<String, dynamic> args) async {
    final guard = _automationGuard('browser_navigate');
    if (guard != null) return guard;
    final url = args['url']?.toString() ?? '';
    final info = await browser.navigate(url);
    return ToolResult(
      ok: info.error == null,
      llmOutput: jsonEncode(info.toJson()),
      displayText: info.title.isEmpty ? info.url : info.title,
    );
  }

  Future<ToolResult> _click(Map<String, dynamic> args) async {
    final guard = _automationGuard('browser_click');
    if (guard != null) return guard;
    final result = await browser.click(
      selector: args['selector']?.toString(),
      text: args['text']?.toString(),
    );
    final ok = result['ok'] == true;
    return ToolResult(
      ok: ok,
      llmOutput: jsonEncode(result),
      displayText: result['clicked']?.toString(),
    );
  }

  Future<ToolResult> _type(Map<String, dynamic> args) async {
    final guard = _automationGuard('browser_type');
    if (guard != null) return guard;
    final result = await browser.type(
      args['text']?.toString() ?? '',
      selector: args['selector']?.toString(),
      clear: args['clear'] is bool ? args['clear'] as bool : true,
    );
    return ToolResult(ok: result['ok'] == true, llmOutput: jsonEncode(result));
  }

  Future<ToolResult> _scroll(Map<String, dynamic> args) async {
    final guard = _automationGuard('browser_scroll');
    if (guard != null) return guard;
    final result = await browser.scroll(
      direction: args['direction']?.toString() ?? 'down',
      amount: args['amount'] is int ? args['amount'] as int : 800,
    );
    return ToolResult(ok: result['ok'] == true, llmOutput: jsonEncode(result));
  }

  Future<ToolResult> _screenshot() async {
    final guard = _automationGuard('browser_screenshot');
    if (guard != null) return guard;
    final base = await resolveBaseDir();
    final shotsDir = '${base.path}${Platform.pathSeparator}browser_shots';
    final path = await browser.screenshot(saveDir: shotsDir);
    if (path == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Screenshot could not be captured.',
      );
    }
    return ToolResult(
      ok: true,
      llmOutput: 'Screenshot saved at $path',
      screenshotPath: path,
      displayText: 'screenshot',
    );
  }

  Future<ToolResult> _extract(Map<String, dynamic> args) async {
    final guard = _automationGuard('browser_extract_text');
    if (guard != null) return guard;
    final maxLength = args['maxLength'] is int
        ? args['maxLength'] as int
        : 8000;
    final text = await browser.extractText(maxLength: maxLength);
    return ToolResult(
      ok: true,
      llmOutput: text.isEmpty ? '(empty page)' : text,
    );
  }

  Future<ToolResult> _runJs(Map<String, dynamic> args) async {
    final guard = _automationGuard('run_js');
    if (guard != null) return guard;
    final code = args['code']?.toString() ?? '';
    if (code.trim().isEmpty) {
      return const ToolResult(ok: false, llmOutput: 'Parameter code is empty.');
    }
    final result = await browser.runJs(code);
    return ToolResult(ok: true, llmOutput: result);
  }

  Future<Directory> _safeBaseDir() async => resolveBaseDir();

  /// Resolves [requested] under [base], rejecting path traversal.
  File? _resolveFile(Directory base, String requested) {
    if (requested.trim().isEmpty) return null;
    try {
      final resolved = base.uri.resolve(requested).toFilePath();
      final normalizedBase = base.path.endsWith(Platform.pathSeparator)
          ? base.path
          : '${base.path}${Platform.pathSeparator}';
      if (!resolved.startsWith(normalizedBase)) return null;
      return File(resolved);
    } catch (_) {
      return null;
    }
  }

  Future<ToolResult> _readFile(Map<String, dynamic> args) async {
    final base = await _safeBaseDir();
    final file = _resolveFile(base, args['path']?.toString() ?? '');
    if (file == null) {
      return const ToolResult(ok: false, llmOutput: 'Invalid path.');
    }
    if (!await file.exists()) {
      return ToolResult(ok: false, llmOutput: 'File not found: ${file.path}');
    }
    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      // Binary or non-UTF8 file: report instead of crashing.
      return ToolResult(
        ok: false,
        llmOutput: 'File could not be read as text: $e',
      );
    }
    final truncated = content.length > 20000
        ? '${content.substring(0, 20000)}\n... [truncated]'
        : content;
    return ToolResult(
      ok: true,
      llmOutput: truncated,
      displayText: file.path.split(Platform.pathSeparator).last,
    );
  }

  Future<ToolResult> _writeFile(Map<String, dynamic> args) async {
    final base = await _safeBaseDir();
    final file = _resolveFile(base, args['path']?.toString() ?? '');
    if (file == null) {
      return const ToolResult(ok: false, llmOutput: 'Invalid path.');
    }
    final content = args['content']?.toString() ?? '';
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    } catch (e) {
      return ToolResult(ok: false, llmOutput: 'Could not write file: $e');
    }
    return ToolResult(
      ok: true,
      llmOutput: 'Wrote ${content.length} characters to ${file.path}',
      displayText: file.path.split(Platform.pathSeparator).last,
    );
  }

  // -- Archive tools (zip / unzip) ---------------------------------------

  /// Lists up to [_unzipListCap] files under [dir] (relative paths, '/'
  /// separators) so the model learns what an archive contained.
  static const int _unzipListCap = 100;

  Future<List<String>> _listFiles(Directory dir, String relativeRoot) async {
    final List<String> out = <String>[];
    if (!dir.existsSync()) return out;
    await for (final FileSystemEntity entity in dir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (FileSystemEntity.typeSync(entity.path) != FileSystemEntityType.file) {
        continue;
      }
      final String rel = entity.path
          .substring(relativeRoot.length)
          .replaceAll(Platform.pathSeparator, '/');
      out.add(rel.startsWith('/') ? rel.substring(1) : rel);
      if (out.length >= _unzipListCap) break;
    }
    return out;
  }

  Future<ToolResult> _unzipFile(Map<String, dynamic> args) async {
    final FileSystemService? service = fs;
    if (service == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Archive tools are not available in this build.',
      );
    }
    final String path = args['path']?.toString() ?? '';
    if (path.trim().isEmpty) {
      return const ToolResult(ok: false, llmOutput: 'Parameter path is empty.');
    }
    final String password = args['password']?.toString() ?? '';
    final String? effectivePassword = password.trim().isEmpty ? null : password;
    final String dest;
    try {
      dest = await service.unzip(path, password: effectivePassword);
    } on ZipPasswordRequiredException {
      return ToolResult(
        ok: false,
        llmOutput:
            'The archive $path is password-protected. Ask the user for the '
            'password, then call unzip_file again passing it in the '
            '"password" argument.',
        displayText: 'unzip $path — password required',
      );
    } on ZipWrongPasswordException {
      return ToolResult(
        ok: false,
        llmOutput:
            'The password for $path is wrong. Ask the user to confirm the '
            'password, then call unzip_file again with the corrected '
            '"password" argument.',
        displayText: 'unzip $path — wrong password',
      );
    }
    final String? destDirPath = await service.resolve(dest);
    final List<String> files = destDirPath == null
        ? const <String>[]
        : await _listFiles(Directory(destDirPath), destDirPath);
    final StringBuffer output = StringBuffer()
      ..write('Extracted to $dest')
      ..writeln(
        files.isEmpty
            ? ' (no files inside the archive).'
            : ' — ${files.length} file(s):',
      );
    for (final String file in files) {
      output.writeln('- $dest/$file');
    }
    return ToolResult(
      ok: true,
      llmOutput: output.toString().trim(),
      displayText: 'unzip $path',
    );
  }

  Future<ToolResult> _zipFile(Map<String, dynamic> args) async {
    final FileSystemService? service = fs;
    if (service == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Archive tools are not available in this build.',
      );
    }
    final String path = args['path']?.toString() ?? '';
    if (path.trim().isEmpty) {
      return const ToolResult(ok: false, llmOutput: 'Parameter path is empty.');
    }
    final String zipPath = await service.zip(path);
    return ToolResult(
      ok: true,
      llmOutput: 'Created archive $zipPath',
      displayText: 'zip $path',
    );
  }

  // -- Task plan (todos) --------------------------------------------------

  /// The planning tool is stateless on purpose: the model re-sends the
  /// FULL list every time, so the latest `todo_write` call in the history
  /// always describes the current plan. The executor only validates and
  /// reports progress back to the model; UI and history read the same
  /// arguments from the persisted tool call.
  ToolResult _todoWrite(Map<String, dynamic> args) {
    final List<TodoItem> todos = parseTodoList(args['todos']);
    if (todos.isEmpty) {
      return const ToolResult(
        ok: false,
        llmOutput:
            'todo_write requires a non-empty "todos" array of objects with '
            '"content" (string) and "status" (pending | in_progress | '
            'completed). Send the complete updated list.',
      );
    }
    final int completed = todos
        .where((TodoItem t) => t.status == TodoStatus.completed)
        .length;
    final int inProgress = todos
        .where((TodoItem t) => t.status == TodoStatus.inProgress)
        .length;
    return ToolResult(
      ok: true,
      llmOutput: jsonEncode(<String, dynamic>{
        'ok': true,
        'total': todos.length,
        'completed': completed,
        'in_progress': inProgress,
        'pending': todos.length - completed - inProgress,
      }),
      displayText: 'plan $completed/${todos.length}',
    );
  }

  // -- Embedded Node.js-style runtime ------------------------------------

  Future<ToolResult> _nodeRun(Map<String, dynamic> args) async {
    final JsRuntime? runtime = js;
    if (runtime == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'The embedded JS runtime is not available in this build.',
      );
    }
    final code = args['code']?.toString() ?? '';
    if (code.trim().isEmpty) {
      return const ToolResult(ok: false, llmOutput: 'Parameter code is empty.');
    }
    final Directory base = await _safeBaseDir();
    final String modulesRoot =
        '${base.path}${Platform.pathSeparator}node_modules';
    final result = await runtime.run(
      code,
      moduleRoots: <String>[modulesRoot],
      workingDir: base.path,
    );
    final String output = result.output;
    if (!result.ok) {
      return ToolResult(
        ok: false,
        llmOutput: output.isEmpty
            ? 'Script error: ${result.error}'
            : '$output\nScript error: ${result.error}',
        displayText: 'node error',
      );
    }
    final List<String> parts = <String>[
      if (output.isNotEmpty) output,
      if (result.result != null && result.result != 'undefined')
        '=> ${result.result}',
    ];
    return ToolResult(
      ok: true,
      llmOutput: parts.isEmpty
          ? 'Script finished with no output.'
          : parts.join('\n'),
      displayText: 'node',
    );
  }

  Future<ToolResult> _nodeInstall(Map<String, dynamic> args) async {
    final NpmService? service = npm;
    if (service == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'npm management is not available in this build.',
      );
    }
    final String pkg = args['package']?.toString() ?? '';
    final String? version = args['version']?.toString();
    final result = await service.install(pkg, version: version);
    return ToolResult(
      ok: result.ok,
      llmOutput: result.ok
          ? '${result.message}. It can now be required from node_run.'
          : result.message,
      displayText: result.ok ? 'installed $pkg' : 'install failed',
    );
  }

  Future<ToolResult> _nodeRemove(Map<String, dynamic> args) async {
    final NpmService? service = npm;
    if (service == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'npm management is not available in this build.',
      );
    }
    final String pkg = args['package']?.toString() ?? '';
    if (pkg.trim().isEmpty) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Parameter package is empty.',
      );
    }
    final bool removed = await service.remove(pkg);
    return ToolResult(
      ok: removed,
      llmOutput: removed
          ? 'Removed $pkg from the embedded runtime.'
          : '$pkg is not installed.',
      displayText: removed ? 'removed $pkg' : 'not installed',
    );
  }
}
