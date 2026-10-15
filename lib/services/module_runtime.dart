import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'js_runtime.dart';
import 'module_registry.dart';

/// Outcome of one chat-module execution.
class ModuleRunResult {
  const ModuleRunResult({
    required this.output,
    this.error,
    this.result,
    this.terminated = false,
  });

  /// Captured console output (capped).
  final String output;
  final String? error;
  final String? result;

  /// True when the user terminated the module while it was running; the
  /// captured output is then discarded on purpose.
  final bool terminated;

  bool get ok => error == null && !terminated;
}

/// One in-flight module execution with its per-chat security context.
class _RunContext {
  _RunContext({
    required this.sessionId,
    required this.moduleName,
    required this.permissions,
    required this.allowedHosts,
  });

  final String sessionId;
  final String moduleName;
  final Set<String> permissions;
  final List<String>? allowedHosts;

  /// Console lines captured through the bridge (`zagents.log`) — the same
  /// delivery path as every other SDK call.
  final List<String> consoleLines = <String>[];
  bool cancelled = false;
  void Function(String text)? onChatEmit;
}

/// Runs chat modules inside the per-chat "private window" sandbox.
///
/// Isolation guarantees (browser-private-window semantics):
/// * **Process/context** — every run boots a fresh embedded-JS context;
///   nothing (module cache, globals, previous secrets) survives between
///   runs, chats or modules.
/// * **State & storage** — each (chat, module) pair gets its own directory
///   `<session-sandbox>/modules/<name>/` with `state/` as the only
///   writable file scope and `storage.json` as a per-chat key/value store.
///   Chat A's module can never read chat B's storage, files or config.
/// * **Configuration** — the module manifest is read-only and comes from
///   the module's own install directory.
/// * **Permissions** — the manifest declares capabilities; the user
///   approves them at activation; the JS SDK hides unauthorized APIs AND
///   the Dart bridge re-checks every call (defense in depth).
/// * **Network** — requires the `network` permission; a manifest
///   `allowedHosts` list further restricts destinations.
/// * **Resources** — per-run timeout, console-output cap, storage caps,
///   file-scope confinement.
/// * **Safe termination** — [terminate] cancels an in-flight run: output
///   delivery stops immediately, already-persisted storage is kept.
class ModuleRuntime implements ModuleBridge {
  ModuleRuntime({
    required this.js,
    required this.resolveSandboxRoot,
    required this.resolveModulePath,
    required this.resolveSdkSource,
    required this.resolveNpmModulesRoot,
    this.httpTransport,
  });

  final JsRuntime js;

  /// Session sandbox root resolver (`SessionSandbox.rootFor`).
  final Future<Directory> Function(String? sessionId) resolveSandboxRoot;

  /// Resolves a module's install directory (null = unknown module).
  final Future<String?> Function(String name) resolveModulePath;

  /// Loads the official SDK shim source (`require('zagents-sdk')`).
  final Future<String> Function() resolveSdkSource;

  /// Shared npm library root, usable through `require()` alongside the
  /// module's own directory.
  final Future<String> Function() resolveNpmModulesRoot;

  /// Outbound HTTP for `zagents.http` (url, method, body → status/body).
  final Future<Map<String, dynamic>?> Function(
    String url,
    String method,
    String? body,
  )?
  httpTransport;

  /// Per-key JSON-size cap for `zagents.storage.set` (encoded).
  static const int maxStorageValueBytes = 64 * 1024;

  /// Total storage.json budget per (chat, module).
  static const int maxStorageTotalBytes = 1024 * 1024;

  /// Console-output caps for one module run.
  static const int maxOutputBytes = 32 * 1024;
  static const int maxOutputLines = 400;

  /// Runs are serialized through the shared [JsRuntime], so exactly one
  /// context is live at a time.
  _RunContext? _context;

  /// Absolute path of the (chat, module) instance directory:
  /// `<session-sandbox>/modules/<name>/`. Created on demand. Holds
  /// `storage.json` (per-chat key/value store) and `state/` (the only
  /// writable file scope for this module in THIS chat).
  Future<Directory> instanceDirFor(String sessionId, String name) async {
    final Directory root = await resolveSandboxRoot(sessionId);
    final Directory dir = Directory(
      '${root.path}${Platform.pathSeparator}modules'
      '${Platform.pathSeparator}$name',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Executes the module entry point for [sessionId]. [granted] is the
  /// user-approved subset of the manifest permissions. [onChatEmit]
  /// receives every `zagents.chat.emit(text)` call while the run is live.
  Future<ModuleRunResult> run({
    required String sessionId,
    required ChatModule module,
    required Set<ModulePermission> granted,
    void Function(String text)? onChatEmit,
  }) async {
    // Resolve FIRST so an uninstalled/removed module degrades into a
    // clean error instead of a raw file-not-found exception.
    final String? moduleDir = await resolveModulePath(module.name);
    if (moduleDir == null) {
      return ModuleRunResult(
        output: '',
        error: 'Module "${module.name}" is not installed',
      );
    }
    final String entrySource;
    try {
      entrySource = await File(module.entryPath).readAsString();
    } catch (e) {
      return ModuleRunResult(
        output: '',
        error: 'Cannot read module entry "${module.manifest.entry}": $e',
      );
    }
    final Directory instance = await instanceDirFor(sessionId, module.name);
    final Directory stateDir = Directory(
      '${instance.path}${Platform.pathSeparator}state',
    );
    if (!stateDir.existsSync()) stateDir.createSync(recursive: true);
    final String npmRoot = await resolveNpmModulesRoot();

    final _RunContext context = _RunContext(
      sessionId: sessionId,
      moduleName: module.name,
      permissions: granted.map((ModulePermission p) => p.name).toSet(),
      allowedHosts: module.manifest.allowedHosts,
    )..onChatEmit = onChatEmit;
    _context = context;

    String output = '';
    String? error;
    String? result;
    try {
      final JsRunResult run = await js.runModule(
        ModuleInvocation(
          entrySource: entrySource,
          moduleRoots: <String>[moduleDir, if (npmRoot.isNotEmpty) npmRoot],
          workingDir: stateDir.path,
          permissions: context.permissions,
          info: <String, dynamic>{
            'name': module.name,
            'version': module.manifest.version,
            'title': module.manifest.title,
            'sessionId': sessionId,
            'entry': module.manifest.entry,
          },
          allowedHosts: module.manifest.allowedHosts,
          bridge: this,
          sdkSource: await resolveSdkSource(),
          timeout: module.manifest.timeout,
        ),
      );
      // Console lines captured through the bridge + whatever the runtime
      // itself captured (core console.log frames).
      final List<String> outputParts = <String>[
        ...context.consoleLines,
        if (run.output.trim().isNotEmpty) run.output,
      ];
      output = _capOutput(outputParts.join('\n'));
      error = run.error;
      result = run.result;
    } finally {
      _context = null;
    }

    if (context.cancelled) {
      return ModuleRunResult(
        output: '',
        terminated: true,
        error: 'Module terminated by user',
      );
    }
    return ModuleRunResult(output: output, error: error, result: result);
  }

  /// Safely terminates the in-flight execution of (chat, module): live
  /// `zagents.chat.emit` delivery and the final output are discarded,
  /// persisted storage stays intact. Returns true when a run was active.
  bool terminate(String sessionId, String moduleName) {
    final _RunContext? context = _context;
    if (context == null ||
        context.sessionId != sessionId ||
        context.moduleName != moduleName) {
      return false;
    }
    context.cancelled = true;
    return true;
  }

  /// Terminates the module currently running for [sessionId] (used when a
  /// session is stopped or deleted). Returns the terminated module name.
  String? terminateSession(String sessionId) {
    final _RunContext? context = _context;
    if (context == null || context.sessionId != sessionId) return null;
    context.cancelled = true;
    return context.moduleName;
  }

  String _capOutput(String output) {
    if (output.isEmpty) return output;
    final List<String> lines = output.split('\n');
    if (lines.length > maxOutputLines) {
      lines.removeRange(maxOutputLines, lines.length);
      lines.add('…[output truncated at $maxOutputLines lines]');
    }
    String capped = lines.join('\n');
    if (capped.length > maxOutputBytes) {
      capped =
          '${capped.substring(0, maxOutputBytes)}…[output truncated at '
          '$maxOutputBytes bytes]';
    }
    return capped;
  }

  // -- ModuleBridge (Dart-side enforcement) -------------------------------

  @override
  Future<Map<String, dynamic>?> handleOp(Map<String, dynamic> request) async {
    final _RunContext? context = _context;
    if (context == null) {
      return const <String, dynamic>{
        'ok': false,
        'error': 'No module execution is active',
      };
    }
    final String op = request['zop']?.toString() ?? '';
    switch (op) {
      case 'log':
        // Always available (no permission): mirrors console output into
        // the run result. Yield once so the reply is never instantaneous.
        await Future<void>.delayed(Duration.zero);
        context.consoleLines.add(request['text']?.toString() ?? '');
        return const <String, dynamic>{'ok': true};
      case 'chat.emit':
        if (!context.permissions.contains('chat')) return _denied('chat');
        if (context.cancelled) return const <String, dynamic>{'ok': true};
        context.onChatEmit?.call(request['text']?.toString() ?? '');
        return const <String, dynamic>{'ok': true};
      case 'http.request':
        if (!context.permissions.contains('network')) return _denied('network');
        final String url = request['url']?.toString() ?? '';
        if (!_isHostAllowed(context, url)) {
          return const <String, dynamic>{
            'ok': false,
            'error': 'Host is not allowed by this module (allowedHosts)',
          };
        }
        final transport = httpTransport;
        if (transport == null) {
          return const <String, dynamic>{
            'ok': false,
            'error': 'Network transport is unavailable',
          };
        }
        final Map<String, dynamic>? response = await transport(
          url,
          request['method']?.toString() ?? 'GET',
          request['body']?.toString(),
        );
        return <String, dynamic>{
          'ok': true,
          'data': <String, dynamic>{
            'status': (response?['status'] as int?) ?? 200,
            'body': response?['body']?.toString() ?? '',
          },
        };
      case 'storage.get':
        if (!context.permissions.contains('storage')) return _denied('storage');
        final Map<String, dynamic> store = await _readStorage(
          context.sessionId,
          context.moduleName,
        );
        return <String, dynamic>{
          'ok': true,
          'data': store[request['key']?.toString() ?? ''],
        };
      case 'storage.set':
        if (!context.permissions.contains('storage')) return _denied('storage');
        final String key = request['key']?.toString() ?? '';
        if (key.isEmpty) {
          return const <String, dynamic>{
            'ok': false,
            'error': 'Storage key must not be empty',
          };
        }
        final Object? value = request['value'];
        final String encoded = jsonEncode(value);
        if (encoded.length > maxStorageValueBytes) {
          return <String, dynamic>{
            'ok': false,
            'error':
                'Storage value exceeds the $maxStorageValueBytes-byte limit',
          };
        }
        final Map<String, dynamic> store = await _readStorage(
          context.sessionId,
          context.moduleName,
        );
        store[key] = value;
        final String serialized = jsonEncode(store);
        if (serialized.length > maxStorageTotalBytes) {
          return <String, dynamic>{
            'ok': false,
            'error':
                'Module storage exceeds the $maxStorageTotalBytes-byte budget',
          };
        }
        await _writeStorage(context.sessionId, context.moduleName, store);
        return const <String, dynamic>{'ok': true};
      case 'storage.keys':
        if (!context.permissions.contains('storage')) return _denied('storage');
        final Map<String, dynamic> store = await _readStorage(
          context.sessionId,
          context.moduleName,
        );
        return <String, dynamic>{'ok': true, 'data': store.keys.toList()};
      case 'storage.remove':
        if (!context.permissions.contains('storage')) return _denied('storage');
        final Map<String, dynamic> store = await _readStorage(
          context.sessionId,
          context.moduleName,
        );
        store.remove(request['key']?.toString() ?? '');
        await _writeStorage(context.sessionId, context.moduleName, store);
        return const <String, dynamic>{'ok': true};
      default:
        return <String, dynamic>{'ok': false, 'error': 'Unknown module API'};
    }
  }

  Map<String, dynamic> _denied(String permission) => <String, dynamic>{
    'ok': false,
    'error': 'Permission denied: $permission',
  };

  bool _isHostAllowed(_RunContext context, String url) {
    final List<String>? allowlist = context.allowedHosts;
    if (allowlist == null || allowlist.isEmpty) return true;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    for (final String pattern in allowlist) {
      final String host = pattern.trim().toLowerCase();
      if (host.isEmpty) continue;
      if (uri.host.toLowerCase() == host) return true;
      // Subdomain wildcard: "*.example.com" style suffix match on
      // dot-boundary ("api.example.com" matches "example.com" only when
      // the pattern explicitly starts with "*.").
      if (host.startsWith('*.')) {
        final String suffix = host.substring(1); // ".example.com"
        if (uri.host.toLowerCase().endsWith(suffix)) return true;
      }
    }
    return false;
  }

  // -- storage io ---------------------------------------------------------

  Future<File> _storageFileFor(String sessionId, String name) async {
    final Directory dir = await instanceDirFor(sessionId, name);
    return File('${dir.path}${Platform.pathSeparator}storage.json');
  }

  Future<Map<String, dynamic>> _readStorage(
    String sessionId,
    String module,
  ) async {
    final File file = await _storageFileFor(sessionId, module);
    if (!file.existsSync()) return <String, dynamic>{};
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _writeStorage(
    String sessionId,
    String module,
    Map<String, dynamic> store,
  ) async {
    final File file = await _storageFileFor(sessionId, module);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(store));
  }
}
