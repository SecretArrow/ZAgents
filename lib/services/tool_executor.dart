import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import 'browser_automation.dart';
import 'device_shell.dart';
import 'file_system_service.dart';
import 'js_runtime.dart';
import 'module_registry.dart';
import 'npm_service.dart';
import 'subagents.dart';
import 'web_fetcher.dart';

/// Result of executing one tool.
class ToolResult {
  const ToolResult({
    required this.ok,
    required this.llmOutput,
    this.screenshotPath,
    this.displayText,
    this.data,
  });

  final bool ok;

  /// Content sent back to the model as the tool message.
  final String llmOutput;

  /// Optional screenshot path to render in the UI.
  final String? screenshotPath;

  /// Optional short label for the UI.
  final String? displayText;

  /// Optional structured payload for the controller (e.g. the staged
  /// module repair metadata behind `module_stage_repair`).
  final Map<String, dynamic>? data;
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
    this.fsFor,
    this.fetcher,
    this.modules,
    this.subagents,
    this.deviceStatus,
  });

  final BrowserAutomation browser;

  /// Yields the workspace root for the given chat session id — isolated
  /// per session ("private window"). `null` = legacy shared root
  /// (documents dir), used by call sites that predate sessions.
  final Future<Directory> Function(String? sessionId) resolveBaseDir;
  final bool Function() isAutomationEnabled;

  /// Embedded JS runtime + npm manager. Nullable so existing tests and
  /// minimal setups keep working; the node tools degrade gracefully.
  final JsRuntime? js;
  final NpmService? npm;

  /// File workspace (zip/unzip + sandboxed paths). Nullable for legacy
  /// tests; the zip tools degrade gracefully when absent.
  final FileSystemService? fs;

  /// Session-aware workspace factory, preferred over [fs] when set:
  /// archive tools operate on the calling session's own sandbox.
  final FileSystemService? Function(String? sessionId)? fsFor;

  /// Server-side URL fetcher behind the `web_fetch` tool. Nullable for
  /// legacy tests; the tool degrades gracefully when absent.
  final WebFetcher? fetcher;

  /// Installed chat-module registry behind the module doctor tools
  /// (`module_list` / `module_read` / `module_export` /
  /// `module_stage_repair`). Nullable for legacy tests; the tools
  /// degrade gracefully when absent.
  final ModuleRegistry? modules;

  /// Fan-of-subagents runner behind `spawn_subagents`. Nullable for
  /// legacy tests; the tool degrades gracefully when absent.
  final SubagentRunner? subagents;

  /// Device-state probe behind the `device_status` tool (v1.32.0):
  /// verified airplane state (world-readable, NO root) + root
  /// availability. Nullable for legacy tests; the tool degrades
  /// gracefully when absent. The root probe is expensive (`su -c id -u`),
  /// so its outcome is cached for the process lifetime — root status
  /// never changes while the app runs.
  final DeviceShellService? Function()? deviceStatus;

  /// Cached root-availability outcome (null = not probed yet).
  bool? _rootAvailable;

  static const Set<String> _browserTools = <String>{
    'browser_navigate',
    'browser_click',
    'browser_type',
    'browser_scroll',
    'browser_screenshot',
    'browser_extract_text',
    'run_js',
  };

  Future<ToolResult> execute(
    String name,
    Map<String, dynamic> args, {
    String? sessionId,
    bool Function()? shouldAbort,
  }) async {
    try {
      switch (name) {
        case 'todo_write':
          return _todoWrite(args);
        case 'browser_navigate':
          return await _navigate(args, sessionId);
        case 'browser_click':
          return await _click(args, sessionId);
        case 'browser_type':
          return await _type(args, sessionId);
        case 'browser_scroll':
          return await _scroll(args, sessionId);
        case 'browser_screenshot':
          return await _screenshot(sessionId);
        case 'browser_extract_text':
          return await _extract(args, sessionId);
        case 'run_js':
          return await _runJs(args, sessionId);
        case 'read_file':
          return await _readFile(args, sessionId);
        case 'write_file':
          return await _writeFile(args, sessionId);
        case 'unzip_file':
          return await _unzipFile(args, sessionId);
        case 'zip_file':
          return await _zipFile(args, sessionId);
        case 'node_run':
          return await _nodeRun(args, sessionId);
        case 'node_install':
          return await _nodeInstall(args);
        case 'node_remove':
          return await _nodeRemove(args);
        case 'web_fetch':
          return await _webFetch(args);
        case 'git_clone':
          return await _gitClone(args, sessionId);
        case 'git_status':
          return await _gitStatus(args, sessionId);
        case 'git_commit':
          return await _gitCommit(args, sessionId);
        case 'git_push':
          return await _gitPush(args, sessionId);
        case 'git_log':
          return await _gitLog(args, sessionId);
        case 'module_list':
          return await _moduleList();
        case 'module_read':
          return await _moduleRead(args);
        case 'module_export':
          return await _moduleExport(args, sessionId);
        case 'module_stage_repair':
          return await _moduleStageRepair(args, sessionId);
        case 'spawn_subagents':
          return await _spawnSubagents(args, sessionId, shouldAbort);
        case 'device_status':
          return await _deviceStatus();
        default:
          return ToolResult(ok: false, llmOutput: 'Unknown tool: $name');
      }
    } catch (e) {
      // Never let a tool failure crash the agent loop: degrade to a result
      // the model can read and retry around.
      return ToolResult(ok: false, llmOutput: 'Tool $name failed: $e');
    }
  }

  /// `spawn_subagents` (v1.28.0): runs 1..N independent subagent loops in
  /// parallel and returns their labeled answers together. The runner is
  /// optional (legacy tests); the calling session's id scopes every nested
  /// tool call to the same per-chat sandbox.
  Future<ToolResult> _spawnSubagents(
    Map<String, dynamic> args,
    String? sessionId,
    bool Function()? shouldAbort,
  ) async {
    final SubagentRunner? runner = subagents;
    if (runner == null) {
      return const ToolResult(
        ok: false,
        llmOutput:
            'spawn_subagents is unavailable in this build (no runner '
            'configured).',
      );
    }
    final (List<SubagentTaskSpec> tasks, String? error) = runner.parseTasks(
      args['tasks'],
    );
    if (error != null) {
      return ToolResult(ok: false, llmOutput: 'spawn_subagents: $error');
    }
    if (shouldAbort?.call() ?? false) {
      return const ToolResult(ok: false, llmOutput: 'spawn_subagents aborted');
    }
    final List<SubagentOutcome> outcomes = await runner.run(
      tasks,
      sessionId: sessionId,
      shouldAbort: shouldAbort,
    );
    return ToolResult(
      ok: true,
      llmOutput: runner.formatOutcomes(outcomes),
      displayText: 'subagents ×${outcomes.length}',
    );
  }

  /// `device_status` (v1.32.0): the verified device facts the agent needs
  /// to ground airplane-mode workflows — the REAL airplane state (world
  /// readable, no root) and whether `su` is available (rooted phone).
  /// Grounding matters: the agent can now CHECK a user's "yes, airplane
  /// is on/off" claim instead of trusting it blindly.
  Future<ToolResult> _deviceStatus() async {
    final DeviceShellService? Function()? resolve = deviceStatus;
    final DeviceShellService? shell = resolve?.call();
    if (shell == null) {
      return const ToolResult(
        ok: false,
        llmOutput:
            'device_status is unavailable in this build (no shell bridge).',
      );
    }
    final bool? airplane = await shell.readAirplaneMode();
    if (_rootAvailable == null) {
      // One-shot probe with a short budget: `su -c id -u` prints 0 on a
      // rooted phone; anything else (missing su, user denial, timeout)
      // counts as "no root". Cached — root never changes at runtime.
      final DeviceShellResult probe = await shell.run(
        command: 'id -u',
        root: true,
        timeoutMs: 5000,
      );
      _rootAvailable =
          probe.succeeded &&
          probe.stdout.trim().split(RegExp(r'\s+')).last == '0';
    }
    final String airplaneText = airplane == null
        ? 'unknown (this platform cannot report it)'
        : airplane
        ? 'ON'
        : 'OFF';
    return ToolResult(
      ok: true,
      llmOutput:
          'Device status:\n'
          '- airplane_mode: $airplaneText\n'
          '- root_available: ${_rootAvailable!}\n'
          'Note: with airplane_mode ON the device has no internet — chat '
          'requests to the AI provider will fail until the user turns it '
          'back off (auto-retry then resumes the task automatically).',
      displayText:
          'airplane: ${airplane == null ? "?" : (airplane ? "ON" : "OFF")}, root: ${_rootAvailable!}',
    );
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

  Future<ToolResult> _navigate(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final guard = _automationGuard('browser_navigate');
    if (guard != null) return guard;
    final url = args['url']?.toString() ?? '';
    final info = await browser.navigate(url, sessionId: sessionId);
    return ToolResult(
      ok: info.error == null,
      llmOutput: jsonEncode(info.toJson()),
      displayText: info.title.isEmpty ? info.url : info.title,
    );
  }

  Future<ToolResult> _click(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final guard = _automationGuard('browser_click');
    if (guard != null) return guard;
    final result = await browser.click(
      selector: args['selector']?.toString(),
      text: args['text']?.toString(),
      sessionId: sessionId,
    );
    final ok = result['ok'] == true;
    return ToolResult(
      ok: ok,
      llmOutput: jsonEncode(result),
      displayText: result['clicked']?.toString(),
    );
  }

  Future<ToolResult> _type(Map<String, dynamic> args, String? sessionId) async {
    final guard = _automationGuard('browser_type');
    if (guard != null) return guard;
    final result = await browser.type(
      args['text']?.toString() ?? '',
      selector: args['selector']?.toString(),
      clear: args['clear'] is bool ? args['clear'] as bool : true,
      sessionId: sessionId,
    );
    return ToolResult(ok: result['ok'] == true, llmOutput: jsonEncode(result));
  }

  Future<ToolResult> _scroll(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final guard = _automationGuard('browser_scroll');
    if (guard != null) return guard;
    final result = await browser.scroll(
      direction: args['direction']?.toString() ?? 'down',
      amount: args['amount'] is int ? args['amount'] as int : 800,
      sessionId: sessionId,
    );
    return ToolResult(ok: result['ok'] == true, llmOutput: jsonEncode(result));
  }

  Future<ToolResult> _screenshot(String? sessionId) async {
    final guard = _automationGuard('browser_screenshot');
    if (guard != null) return guard;
    final base = await resolveBaseDir(sessionId);
    final shotsDir = '${base.path}${Platform.pathSeparator}browser_shots';
    final path = await browser.screenshot(
      saveDir: shotsDir,
      sessionId: sessionId,
    );
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

  Future<ToolResult> _extract(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final guard = _automationGuard('browser_extract_text');
    if (guard != null) return guard;
    final maxLength = args['maxLength'] is int
        ? args['maxLength'] as int
        : 8000;
    final text = await browser.extractText(
      maxLength: maxLength,
      sessionId: sessionId,
    );
    return ToolResult(
      ok: true,
      llmOutput: text.isEmpty ? '(empty page)' : text,
    );
  }

  Future<ToolResult> _runJs(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final guard = _automationGuard('run_js');
    if (guard != null) return guard;
    final code = args['code']?.toString() ?? '';
    if (code.trim().isEmpty) {
      return const ToolResult(ok: false, llmOutput: 'Parameter code is empty.');
    }
    final result = await browser.runJs(code, sessionId: sessionId);
    return ToolResult(ok: true, llmOutput: result);
  }

  Future<Directory> _safeBaseDir(String? sessionId) async =>
      resolveBaseDir(sessionId);

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

  Future<ToolResult> _readFile(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final base = await _safeBaseDir(sessionId);
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

  Future<ToolResult> _writeFile(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final base = await _safeBaseDir(sessionId);
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

  Future<ToolResult> _unzipFile(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final FileSystemService? service = fsFor != null ? fsFor!(sessionId) : fs;
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

  Future<ToolResult> _zipFile(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final FileSystemService? service = fsFor != null ? fsFor!(sessionId) : fs;
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

  Future<ToolResult> _nodeRun(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
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
    // node_run works inside the session workspace, but packages stay in
    // the GLOBAL npm library (documents/node_modules) — installs are
    // shared across sessions, scripts are not.
    final Directory base = await _safeBaseDir(sessionId);
    final Directory global = await _safeBaseDir(null);
    final String modulesRoot =
        '${global.path}${Platform.pathSeparator}node_modules';
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

  // -- Server-side web fetch ----------------------------------------------

  Future<ToolResult> _webFetch(Map<String, dynamic> args) async {
    final WebFetcher? service = fetcher;
    if (service == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'web_fetch is not available in this build.',
      );
    }
    final String url = args['url']?.toString() ?? '';
    if (url.trim().isEmpty) {
      return const ToolResult(ok: false, llmOutput: 'Parameter url is empty.');
    }
    final int maxLength =
        (args['maxLength'] as int?) ?? WebFetcher.defaultMaxLength;
    final WebFetchResult result = await service.fetch(
      url,
      maxLength: maxLength,
    );
    return ToolResult(
      ok: result.ok,
      llmOutput: result.output,
      displayText: result.ok
          ? 'fetched ${Uri.tryParse(url.trim())?.host ?? url.trim()}'
          : 'fetch failed',
    );
  }

  // -- Git tools (isomorphic-git through the embedded JS runtime) ---------

  /// Cached outcome of the isomorphic-git availability check (null until the
  /// first git tool call). npm packages are GLOBAL, so one app-lifetime
  /// check is enough.
  bool? _isoGitAvailable;

  /// Makes sure `isomorphic-git` is installed in the global npm library —
  /// the git tools are thin JS wrappers around it. Installs on first use.
  Future<bool> _ensureIsoGit() async {
    final NpmService? service = npm;
    if (service == null) return false;
    final bool? cached = _isoGitAvailable;
    if (cached != null) return cached;
    try {
      final List<InstalledModule> installed = await service.listInstalled();
      if (installed.any((InstalledModule m) => m.name == 'isomorphic-git')) {
        return _isoGitAvailable = true;
      }
    } catch (_) {
      // Listing failed: fall through and try an install.
    }
    try {
      final result = await service.install('isomorphic-git');
      return _isoGitAvailable = result.ok;
    } catch (_) {
      return _isoGitAvailable = false;
    }
  }

  /// Resolves [requested] as a directory under [base], rejecting path
  /// traversal (git repos must stay inside the session workspace).
  Directory? _resolveDir(Directory base, String requested) {
    final String rel = requested.trim().isEmpty ? '.' : requested.trim();
    try {
      final String resolved = base.uri.resolve(rel).toFilePath();
      final String normalizedBase = base.path.endsWith(Platform.pathSeparator)
          ? base.path
          : '${base.path}${Platform.pathSeparator}';
      if (!resolved.startsWith(normalizedBase)) return null;
      return Directory(resolved);
    } catch (_) {
      return null;
    }
  }

  /// Shared runner for all git tools: guarantees the runtime + package are
  /// available, then executes the generated script with the session
  /// workspace as workingDir and the GLOBAL npm library for modules.
  Future<ToolResult> _gitRun(
    String op,
    Map<String, dynamic> payload,
    String? sessionId,
  ) async {
    final JsRuntime? runtime = js;
    if (runtime == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'The embedded JS runtime is not available in this build.',
      );
    }
    if (!await _ensureIsoGit()) {
      return const ToolResult(
        ok: false,
        llmOutput:
            'Could not make isomorphic-git available (npm unavailable or '
            'offline). Git tools need it — try again once connected.',
      );
    }
    final Directory base = await _safeBaseDir(sessionId);
    final Directory global = await _safeBaseDir(null);
    final result = await runtime.run(
      _gitScript(op, payload),
      moduleRoots: <String>[
        '${global.path}${Platform.pathSeparator}node_modules',
      ],
      workingDir: base.path,
    );
    final String output = result.output;
    if (!result.ok) {
      return ToolResult(
        ok: false,
        llmOutput: output.isEmpty
            ? 'git $op failed: ${result.error}'
            : '$output\ngit $op failed: ${result.error}',
        displayText: 'git $op failed',
      );
    }
    return ToolResult(
      ok: true,
      llmOutput: output.isEmpty
          ? (result.result == 'undefined' || result.result == null
                ? 'git $op finished (no output).'
                : '=> ${result.result}')
          : output,
      displayText: 'git $op',
    );
  }

  /// Builds the JavaScript source for one git operation. [payload] carries
  /// pre-validated, Dart-resolved values (absolute `dir`, sanitized url…).
  /// Network clients prefer the browser build of isomorphic-git (fetch is
  /// available in the embedded runtime) and fall back to the node build.
  String _gitScript(String op, Map<String, dynamic> payload) {
    final String args = jsonEncode(payload);
    final String prelude =
        '''
const ARGS = $args;
const git = require('isomorphic-git');
const fs = require('fs');
let http = null;
function gitHttp() {
  if (http) return http;
  try { http = require('isomorphic-git/http/web'); } catch (e) {}
  if (!http) { try { http = require('isomorphic-git/http/node'); } catch (e) {} }
  return http;
}
''';
    switch (op) {
      case 'clone':
        return '''
$prelude
await git.clone({
  fs, http: gitHttp(), dir: ARGS.dir, url: ARGS.url,
  singleBranch: true, depth: ARGS.depth || 1,
  onAuth: () => ({ username: 'x-access-token', password: ARGS.token || '' }),
});
let files = [];
try { files = fs.readdirSync(ARGS.dir).filter((f) => f !== '.git'); } catch (e) {}
console.log('Cloned ' + (files.length) + ' top-level entries into ' + ARGS.dir);
return files.slice(0, 50).join('\\n');
''';
      case 'status':
        return '''
$prelude
const branch = (await git.currentBranch({ fs, dir: ARGS.dir })) || '(detached HEAD)';
const rows = await git.statusMatrix({ fs, dir: ARGS.dir });
const changed = [];
for (const row of rows) {
  const file = row[0], head = row[1], workdir = row[2];
  if (head === 1 && workdir === 1) continue;
  if (head === 0 && workdir === 2) changed.push('+ ' + file);
  else if (workdir === 0) changed.push('- ' + file);
  else changed.push('~ ' + file);
}
console.log('branch: ' + branch);
console.log(changed.length === 0 ? 'working tree clean' : changed.slice(0, 100).join('\\n'));
return 'branch ' + branch + ', ' + changed.length + ' change(s)';
''';
      case 'commit':
        return '''
$prelude
await git.add({ fs, dir: ARGS.dir, filepath: '.' });
const sha = await git.commit({
  fs, dir: ARGS.dir, message: ARGS.message,
  author: { name: ARGS.authorName, email: ARGS.authorEmail },
});
console.log('Staged all changes.');
return 'Committed ' + sha;
''';
      case 'push':
        return '''
$prelude
let ref = ARGS.branch;
if (!ref) { ref = await git.currentBranch({ fs, dir: ARGS.dir }); }
if (!ref) throw new Error('No branch to push (detached HEAD?).');
await git.push({
  fs, http: gitHttp(), dir: ARGS.dir,
  remote: ARGS.remote || 'origin', ref,
  onAuth: () => ({ username: 'x-access-token', password: ARGS.token || '' }),
});
console.log('Pushed ' + ref + ' to ' + (ARGS.remote || 'origin'));
return 'pushed ' + ref;
''';
      default: // log
        return '''
$prelude
const commits = await git.log({ fs, dir: ARGS.dir, depth: ARGS.limit || 10 });
if (commits.length === 0) { console.log('No commits yet.'); return 'empty history'; }
for (const c of commits) {
  const when = new Date(c.commit.author.timestamp * 1000).toISOString().slice(0, 10);
  console.log(c.oid.slice(0, 7) + ' ' + when + ' ' + c.commit.author.name + ': ' + String(c.commit.message).split('\\n')[0]);
}
return commits.length + ' commit(s)';
''';
    }
  }

  Future<ToolResult> _gitClone(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final String url = args['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      return const ToolResult(ok: false, llmOutput: 'Parameter url is empty.');
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return const ToolResult(
        ok: false,
        llmOutput: 'git_clone needs an http(s) repository URL.',
      );
    }
    final Directory base = await _safeBaseDir(sessionId);
    final String requested = args['destination']?.toString() ?? '';
    String dest = requested.trim();
    if (dest.isEmpty) {
      final String last = uri.pathSegments.lastWhere(
        (String s) => s.isNotEmpty,
        orElse: () => 'repo',
      );
      dest = last.endsWith('.git') ? last.substring(0, last.length - 4) : last;
      dest = dest.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    }
    final Directory? target = _resolveDir(base, dest);
    if (target == null) {
      return const ToolResult(
        ok: false,
        llmOutput:
            'Invalid destination (must stay inside this chat workspace).',
      );
    }
    if (target.existsSync() && target.listSync().isNotEmpty) {
      return ToolResult(
        ok: false,
        llmOutput: 'Destination already exists and is not empty: $dest',
      );
    }
    return _gitRun('clone', <String, dynamic>{
      'dir': target.path,
      'url': url,
      'token': args['token']?.toString() ?? '',
      'depth': (args['depth'] as int?) ?? 1,
    }, sessionId);
  }

  Future<ToolResult> _gitRepo(
    Map<String, dynamic> args,
    String? sessionId,
    String op,
    Map<String, dynamic> Function(String dir) payloadFor,
  ) async {
    final Directory base = await _safeBaseDir(sessionId);
    final Directory? repo = _resolveDir(
      base,
      args['repoPath']?.toString() ?? '.',
    );
    if (repo == null || !repo.existsSync()) {
      return ToolResult(
        ok: false,
        llmOutput:
            'Repository folder not found inside this chat workspace '
            '(use git_clone first).',
      );
    }
    return _gitRun(op, payloadFor(repo.path), sessionId);
  }

  Future<ToolResult> _gitStatus(Map<String, dynamic> args, String? sessionId) =>
      _gitRepo(
        args,
        sessionId,
        'status',
        (String dir) => <String, dynamic>{'dir': dir},
      );

  Future<ToolResult> _gitCommit(Map<String, dynamic> args, String? sessionId) {
    final String message = args['message']?.toString().trim() ?? '';
    if (message.isEmpty) {
      return Future.value(
        const ToolResult(ok: false, llmOutput: 'Parameter message is empty.'),
      );
    }
    final String authorName = args['authorName']?.toString().trim() ?? '';
    final String authorEmail = args['authorEmail']?.toString().trim() ?? '';
    if (authorName.isEmpty || authorEmail.isEmpty) {
      return Future.value(
        const ToolResult(
          ok: false,
          llmOutput:
              'git_commit needs authorName and authorEmail '
              '(ask the user for their identity).',
        ),
      );
    }
    return _gitRepo(
      args,
      sessionId,
      'commit',
      (String dir) => <String, dynamic>{
        'dir': dir,
        'message': message,
        'authorName': authorName,
        'authorEmail': authorEmail,
      },
    );
  }

  Future<ToolResult> _gitPush(Map<String, dynamic> args, String? sessionId) =>
      _gitRepo(
        args,
        sessionId,
        'push',
        (String dir) => <String, dynamic>{
          'dir': dir,
          'token': args['token']?.toString() ?? '',
          'branch': args['branch']?.toString() ?? '',
          'remote': args['remote']?.toString() ?? '',
        },
      );

  Future<ToolResult> _gitLog(Map<String, dynamic> args, String? sessionId) =>
      _gitRepo(
        args,
        sessionId,
        'log',
        (String dir) => <String, dynamic>{
          'dir': dir,
          'limit': (args['limit'] as int?) ?? 10,
        },
      );

  // -- Module doctor (v1.26.0): read-only inspection + export + a
  // user-confirmed repair install path. The agent can NEVER install or
  // overwrite a module silently: `module_stage_repair` only validates a
  // zip and surfaces a confirmation card the user must tap. -------------

  Future<ToolResult> _moduleList() async {
    final ModuleRegistry? registry = modules;
    if (registry == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Module management is not available in this build.',
      );
    }
    await registry.ensureCacheLoaded();
    final List<ChatModule> installed = await registry.listInstalled();
    if (installed.isEmpty) {
      return const ToolResult(ok: true, llmOutput: 'No modules installed.');
    }
    final StringBuffer out = StringBuffer();
    for (final ChatModule module in installed) {
      final ModuleManifest m = module.manifest;
      out.writeln(
        '${m.name} v${m.version} — ${m.title.isEmpty ? m.name : m.title} — '
        'permissions: ${m.permissions.isEmpty ? '(none)' : m.permissions.map((p) => p.name).join(',')} '
        '— setup form: ${m.setup != null && m.setup!.hasRequired ? 'yes' : 'no'} '
        '— entry: ${m.entry}',
      );
    }
    return ToolResult(ok: true, llmOutput: out.toString().trim());
  }

  Future<ToolResult> _moduleRead(Map<String, dynamic> args) async {
    final ModuleRegistry? registry = modules;
    if (registry == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Module management is not available in this build.',
      );
    }
    final String name = args['name']?.toString() ?? '';
    if (name.trim().isEmpty) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Missing module name. Call module_list first.',
      );
    }
    final String rel = args['path']?.toString() ?? '';
    final ModuleFileRead read = await registry.readModuleFile(name, rel);
    if (!read.ok) {
      return ToolResult(ok: false, llmOutput: read.message);
    }
    if (read.content != null) {
      return ToolResult(
        ok: true,
        llmOutput: read.content!,
        displayText: rel.isEmpty ? 'module listing' : rel,
      );
    }
    return ToolResult(
      ok: true,
      llmOutput: 'Module files:\n${read.listing.join('\n')}',
      displayText: 'module listing',
    );
  }

  Future<ToolResult> _moduleExport(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final ModuleRegistry? registry = modules;
    if (registry == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Module management is not available in this build.',
      );
    }
    final String name = args['name']?.toString() ?? '';
    if (name.trim().isEmpty) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Missing module name. Call module_list first.',
      );
    }
    // The zip lands inside THIS chat's sandbox (exports/), so the user
    // finds it in the File Manager / can share it — never outside.
    final Directory base = await resolveBaseDir(sessionId);
    final ChatModule? module = await registry.get(name);
    if (module == null) {
      return ToolResult(ok: false, llmOutput: 'Module not installed: $name');
    }
    final String fileName = '${module.name}-v${module.manifest.version}.zip';
    final String target =
        '${base.path}${Platform.pathSeparator}exports'
        '${Platform.pathSeparator}$fileName';
    final ModuleExportResult result = await registry.exportToZip(name, target);
    return ToolResult(
      ok: result.ok,
      llmOutput: result.ok
          ? '${result.message}. Archive: exports/$fileName — the user can '
                'share or reinstall it from the File Manager.'
          : result.message,
      displayText: result.ok ? 'exported $fileName' : 'export failed',
    );
  }

  Future<ToolResult> _moduleStageRepair(
    Map<String, dynamic> args,
    String? sessionId,
  ) async {
    final ModuleRegistry? registry = modules;
    if (registry == null) {
      return const ToolResult(
        ok: false,
        llmOutput: 'Module management is not available in this build.',
      );
    }
    final String path = args['path']?.toString() ?? '';
    if (path.trim().isEmpty) {
      return const ToolResult(
        ok: false,
        llmOutput:
            'Missing zip path. Build the repaired module folder in this '
            'workspace (module.json + entry at the folder root), zip it '
            'with zip_file, then pass that zip path here.',
      );
    }
    final Directory base = await resolveBaseDir(sessionId);
    final String? resolved = _resolveFile(base, path)?.path;
    if (resolved == null) {
      return const ToolResult(
        ok: false,
        llmOutput:
            'Invalid path: the zip must live inside THIS chat workspace '
            '(no traversal).',
      );
    }
    if (!File(resolved).existsSync()) {
      return ToolResult(ok: false, llmOutput: 'ZIP not found: $path');
    }
    final ModuleInstallResult validation = await registry.validateZip(resolved);
    if (!validation.ok || validation.module == null) {
      return ToolResult(
        ok: false,
        llmOutput:
            'The zip is not a valid module — fix it and retry: '
            '${validation.message}',
      );
    }
    final ModuleManifest m = validation.module!.manifest;
    return ToolResult(
      ok: true,
      llmOutput:
          'Valid module zip: ${m.name} v${m.version} '
          '(permissions: ${m.permissions.isEmpty ? '(none)' : m.permissions.map((p) => p.name).join(',')}). '
          'A confirmation card is shown to the user — the module is NOT '
          'installed until the user taps Install. Tell the user what you '
          'fixed and why they should (or should not) install it.',
      displayText: 'repair ready: ${m.name} v${m.version}',
      data: <String, dynamic>{
        'zipPath': resolved,
        'name': m.name,
        'version': m.version,
        'title': m.title.isEmpty ? m.name : m.title,
        'permissions': m.permissions.map((p) => p.name).toList(),
      },
    );
  }
}
