import 'dart:convert';
import 'dart:io';

import 'browser_automation.dart';

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

/// Executes agent tools: embedded browser automation, page JS, and file IO
/// scoped to the app documents directory.
class ToolExecutor {
  ToolExecutor({
    required this.browser,
    required this.resolveBaseDir,
    required this.isAutomationEnabled,
  });

  final BrowserAutomation browser;
  final Future<Directory> Function() resolveBaseDir;
  final bool Function() isAutomationEnabled;

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
        default:
          return ToolResult(ok: false, llmOutput: 'Unknown tool: $name');
      }
    } catch (e) {
      return ToolResult(ok: false, llmOutput: 'Tool $name gagal: $e');
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
        llmOutput: 'Screenshot gagal diambil.',
      );
    }
    return ToolResult(
      ok: true,
      llmOutput: 'Screenshot tersimpan di $path',
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
      llmOutput: text.isEmpty ? '(halaman kosong)' : text,
    );
  }

  Future<ToolResult> _runJs(Map<String, dynamic> args) async {
    final guard = _automationGuard('run_js');
    if (guard != null) return guard;
    final code = args['code']?.toString() ?? '';
    if (code.trim().isEmpty) {
      return const ToolResult(ok: false, llmOutput: 'Parameter code kosong.');
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
      return const ToolResult(ok: false, llmOutput: 'Path tidak valid.');
    }
    if (!await file.exists()) {
      return ToolResult(
        ok: false,
        llmOutput: 'File tidak ditemukan: ${file.path}',
      );
    }
    final content = await file.readAsString();
    final truncated = content.length > 20000
        ? '${content.substring(0, 20000)}\n... [dipotong]'
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
      return const ToolResult(ok: false, llmOutput: 'Path tidak valid.');
    }
    final content = args['content']?.toString() ?? '';
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return ToolResult(
      ok: true,
      llmOutput: 'Menulis ${content.length} karakter ke ${file.path}',
      displayText: file.path.split(Platform.pathSeparator).last,
    );
  }
}
