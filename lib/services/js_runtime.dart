import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Result of one embedded-JS execution.
class JsRunResult {
  const JsRunResult({required this.output, this.error, this.result});

  /// Captured console output (console.log/warn/error) joined by newlines.
  final String output;

  /// Non-null when the script threw or timed out.
  final String? error;

  /// JSON-encoded return value of the script (may be null).
  final String? result;

  bool get ok => error == null;
}

/// An embedded JavaScript runtime the agent can use for local data
/// processing ("Node.js-style"): CommonJS `require()` over the app's
/// `node_modules` folder, a Promise-based `fs` bridge sandboxed to the app
/// documents directory, and a global `fetch` proxied through Dart.
///
/// The production implementation runs inside a hidden off-screen WebView —
/// zero extra native footprint, guaranteed single-APK. Tests provide
/// scripted test doubles.
abstract class JsRuntime {
  Future<JsRunResult> run(
    String code, {
    List<String> moduleRoots = const <String>[],
    String? workingDir,
    Duration timeout = const Duration(seconds: 20),
  });

  /// Executes one chat-module entry point inside a fresh, permission-gated
  /// context: the [ModuleInvocation.permissions] decide which `zagents` SDK
  /// capabilities exist, [ModuleInvocation.bridge] carries the Dart-side
  /// operations, and nothing survives the run.
  Future<JsRunResult> runModule(ModuleInvocation invocation);

  void dispose();
}

/// One chat-module execution request handed to [JsRuntime.runModule].
class ModuleInvocation {
  ModuleInvocation({
    required this.entrySource,
    this.moduleRoots = const <String>[],
    this.workingDir,
    this.permissions = const <String>{},
    this.info = const <String, dynamic>{},
    this.allowedHosts,
    required this.bridge,
    this.sdkSource = '',
    this.timeout = const Duration(seconds: 30),
  });

  /// Source of the module entry point (e.g. `main.js`).
  final String entrySource;

  /// Roots used to resolve `require()` specifiers: the module directory
  /// first, then the shared npm library.
  final List<String> moduleRoots;

  /// Directory the `fs` bridge is sandboxed to (the module's per-chat
  /// state directory).
  final String? workingDir;

  /// Granted capability names (`storage`, `network`, `files`, `chat`) —
  /// the subset of the manifest permissions the user approved.
  final Set<String> permissions;

  /// Metadata exposed to the module as `zagents.info` (name, version,
  /// sessionId, ...).
  final Map<String, dynamic> info;

  /// When non-empty, `zagents.http` may only reach these hosts.
  final List<String>? allowedHosts;

  /// Dart-side capability provider; every SDK call lands here and
  /// re-checks permissions (defense in depth).
  final ModuleBridge bridge;

  /// Source of the official SDK shim — registered as the virtual module
  /// `zagents-sdk` so `require('zagents-sdk')` works in addition to the
  /// injected `zagents` global.
  final String sdkSource;

  final Duration timeout;
}

/// Dart-side capability provider for one module run. The JS SDK surfaces
/// these operations as the `zagents` global (`storage`, `fs`, `http`,
/// `chat`); the implementation enforces the granted permissions, per-chat
/// storage scoping and host allowlists.
abstract class ModuleBridge {
  Future<Map<String, dynamic>?> handleOp(Map<String, dynamic> request);
}

/// Hidden-WebView implementation of [JsRuntime].
///
/// How a run works:
///  1. Dart resolves the whole module graph reachable from the user script
///     (`require('…')` scan → on-disk files under [moduleRoots]).
///  2. A registry of `{path: {src, deps}}` plus a CommonJS loader are
///     evaluated in the hidden WebView; `require` inside every module is
///     pre-wired to its resolved dependencies (circular-safe).
///  3. The script result, console output and `fs`/`fetch` traffic travel
///     through the `zagentsNode` JavaScript handler; [run] awaits the
///     final `done` frame with a timeout.
///
/// Privacy guarantee (v1.20.0): every [run] boots a FRESH WebView — the
/// CommonJS cache, `window` globals and the module registry of a previous
/// run (possibly from a different chat session, e.g. git tokens embedded
/// in pushed scripts) are destroyed, matching real Node semantics where
/// each `node script.js` starts a clean process.
class WebViewJsRuntime implements JsRuntime {
  WebViewJsRuntime({this.fetchProxy, this.resolveUserAgent});

  /// Dart-side proxy for in-script `fetch(url)` calls (text bodies).
  final Future<Map<String, dynamic>?> Function(
    String url,
    String method,
    String? body,
  )?
  fetchProxy;

  /// Resolves the User-Agent applied to the sandbox WebView so in-page
  /// `fetch()` requests carry the same identity the browser automation
  /// uses (Settings → User Agent). Kept sticky per session.
  final String? Function()? resolveUserAgent;

  HeadlessInAppWebView? _webview;
  Completer<String>? _done;
  final List<String> _console = <String>[];
  List<String> _sandboxRoots = const <String>[];

  /// While a MODULE run is in flight: the granted permission names, used
  /// to gate the `fs` bridge on the Dart side too (defense in depth — the
  /// JS SDK already hides unauthorized APIs). Null during plain node_run
  /// executions, which keep their unrestricted (workspace-sandboxed) fs
  /// semantics.
  Set<String>? _modulePermissions;
  ModuleBridge? _moduleBridge;

  static const String _handlerName = 'zagentsNode';

  Future<void> _ensureRunning({String? bootstrap}) async {
    if (_webview != null) return;
    final Completer<void> ready = Completer<void>();
    final HeadlessInAppWebView wv = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: '<html><body></body></html>',
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        javaScriptEnabled: true,
        disableContextMenu: true,
        userAgent: resolveUserAgent?.call(),
      ),
      onWebViewCreated: (InAppWebViewController controller) {
        controller.addJavaScriptHandler(
          handlerName: _handlerName,
          callback: _handleMessage,
        );
      },
      onLoadStop: (_, _) {
        if (!ready.isCompleted) ready.complete();
      },
    );
    _webview = wv;
    await wv.run();
    await ready.future.timeout(const Duration(seconds: 20));
    await wv.webViewController!.evaluateJavascript(
      source: bootstrap ?? _bootstrap,
    );
  }

  /// Single entry point for all frames coming from the JS side.
  Future<List<dynamic>> _handleMessage(List<dynamic> args) async {
    Map<String, dynamic>? request;
    if (args.isNotEmpty && args.first is Map) {
      request = Map<String, dynamic>.from(args.first as Map<dynamic, dynamic>);
    }
    if (request == null) return const <dynamic>[null];
    try {
      final Map<String, dynamic>? response = await _dispatch(request);
      return <dynamic>[response];
    } catch (e) {
      return <dynamic>[
        <String, dynamic>{'ok': false, 'error': '$e'},
      ];
    }
  }

  Future<Map<String, dynamic>?> _dispatch(Map<String, dynamic> request) async {
    switch (request['op']) {
      case 'log':
        _console.add(request['text']?.toString() ?? '');
        return null;
      case 'done':
        if (!(_done?.isCompleted ?? true)) {
          _done!.complete(jsonEncode(request));
        }
        return null;
      case 'zapi':
        // Module-mode runs report their final frame over the same zapi
        // channel as every other SDK call (single guaranteed-delivery
        // path); plain post() frames proved lossy under the integration
        // test binding.
        if (request['zop'] == 'done') {
          if (!(_done?.isCompleted ?? true)) {
            _done!.complete(jsonEncode(request));
          }
          return const <String, dynamic>{'ok': true};
        }
        if (request['zop'] == 'log') {
          _console.add(request['text']?.toString() ?? '');
          return const <String, dynamic>{'ok': true};
        }
        final ModuleBridge? bridge = _moduleBridge;
        if (bridge == null) {
          return <String, dynamic>{
            'ok': false,
            'error': 'Module API is unavailable',
          };
        }
        try {
          return await bridge.handleOp(request);
        } catch (e) {
          return <String, dynamic>{'ok': false, 'error': '$e'};
        }
      case 'fs':
        return _fsOp(request);
      case 'fetch':
        final Future<Map<String, dynamic>?> Function(String, String, String?)?
        proxy = fetchProxy;
        if (proxy == null) {
          return <String, dynamic>{
            'ok': false,
            'error': 'fetch is unavailable',
          };
        }
        return proxy(
          request['url']?.toString() ?? '',
          request['method']?.toString() ?? 'GET',
          request['body']?.toString(),
        );
      default:
        return null;
    }
  }

  /// Sandbox the fs bridge to the app documents dir + module roots.
  bool _isSandboxed(String path) {
    if (_sandboxRoots.isEmpty) return false;
    final String normalized = path.endsWith(Platform.pathSeparator)
        ? path
        : '$path${Platform.pathSeparator}';
    for (final String root in _sandboxRoots) {
      final String r = root.endsWith(Platform.pathSeparator)
          ? root
          : '$root${Platform.pathSeparator}';
      if (normalized.startsWith(r)) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> _fsOp(Map<String, dynamic> request) async {
    final String action = request['action']?.toString() ?? '';
    try {
      // Module runs need the explicit `files` permission for ANY fs access
      // (the JS SDK hides zagents.fs without it; this is the Dart-side
      // backstop).
      final Set<String>? modulePerms = _modulePermissions;
      if (modulePerms != null && !modulePerms.contains('files')) {
        return <String, dynamic>{
          'ok': false,
          'error': 'Permission denied: files',
        };
      }
      final String rawPath = request['path']?.toString() ?? '';
      final String resolved = File(rawPath).absolute.path;
      if (!_isSandboxed(resolved)) {
        return <String, dynamic>{
          'ok': false,
          'error': 'fs path is outside the app sandbox',
        };
      }
      switch (action) {
        case 'readFile':
          return <String, dynamic>{
            'ok': true,
            'data': await File(resolved).readAsString(),
          };
        case 'writeFile':
          await File(resolved).parent.create(recursive: true);
          await File(resolved).writeAsString(request['data']?.toString() ?? '');
          return const <String, dynamic>{'ok': true};
        case 'appendFile':
          await File(resolved).parent.create(recursive: true);
          await File(resolved).writeAsString(
            request['data']?.toString() ?? '',
            mode: FileMode.append,
          );
          return const <String, dynamic>{'ok': true};
        case 'readdir':
          final List<FileSystemEntity> entities = await Directory(resolved)
              .list()
              .toList();
          return <String, dynamic>{
            'ok': true,
            'data': <String>[
              for (final FileSystemEntity e in entities)
                e.path.split(Platform.pathSeparator).last,
            ],
          };
        case 'mkdir':
          await Directory(resolved).create(recursive: true);
          return const <String, dynamic>{'ok': true};
        case 'unlink':
          final FileSystemEntity entity =
              FileSystemEntity.typeSync(resolved) ==
                  FileSystemEntityType.directory
              ? Directory(resolved)
              : File(resolved);
          await entity.delete(recursive: true);
          return const <String, dynamic>{'ok': true};
        case 'stat':
          final FileSystemEntity entity =
              FileSystemEntity.typeSync(resolved) ==
                  FileSystemEntityType.directory
              ? Directory(resolved)
              : File(resolved);
          final FileStat stat = await entity.stat();
          return <String, dynamic>{
            'ok': true,
            'data': <String, dynamic>{
              'isDirectory': stat.type == FileSystemEntityType.directory,
              'size': stat.size,
              'modified': stat.modified.toIso8601String(),
            },
          };
        default:
          return <String, dynamic>{'ok': false, 'error': 'Unknown fs action'};
      }
    } catch (e) {
      return <String, dynamic>{'ok': false, 'error': '$e'};
    }
  }

  /// Shared CommonJS core: message bridge, `fs` shim, module loader and
  /// console capture — used by BOTH plain runs and module runs.
  static String get _coreJs =>
      '''
  function post(msg){ try { return window.flutter_inappwebview.callHandler('$_handlerName', msg); } catch(e){ return Promise.resolve(null); } }
  function fmt(v){
    if (v === undefined) return 'undefined';
    if (v === null) return 'null';
    if (typeof v === 'string') return v;
    try { return JSON.stringify(v); } catch(e) { return String(v); }
  }
  var cache = {};
  var fsShim = {
    readFile: function(p){ return post2({op:'fs', action:'readFile', path:p}); },
    writeFile: function(p,d){ return post2({op:'fs', action:'writeFile', path:p, data:String(d)}); },
    appendFile: function(p,d){ return post2({op:'fs', action:'appendFile', path:p, data:String(d)}); },
    readdir: function(p){ return post2({op:'fs', action:'readdir', path:p}); },
    mkdir: function(p){ return post2({op:'fs', action:'mkdir', path:p}); },
    unlink: function(p){ return post2({op:'fs', action:'unlink', path:p}); },
    stat: function(p){ return post2({op:'fs', action:'stat', path:p}); }
  };
  function post2(msg){
    return window.flutter_inappwebview.callHandler('$_handlerName', msg).then(function(res){
      if (res && res.ok === false) throw new Error(res.error || 'fs error');
      return res ? res.data : null;
    });
  }
  function exec(path){
    if (cache[path] !== undefined) return cache[path].exports;
    var entry = window.__zRegistry[path];
    if (entry === undefined) throw new Error("Cannot find module '" + path + "'");
    var module = { exports: {} };
    cache[path] = module;
    var localRequire = function(spec){
      if (spec === 'fs') return fsShim;
      var resolved = entry.deps[spec];
      if (!resolved) throw new Error("Cannot find module '" + spec + "'. Install it with the node_install tool (Settings > Node.js runtime).");
      return exec(resolved);
    };
    var fn = new Function('module','exports','require','__filename','__dirname', entry.src);
    fn(module, module.exports, localRequire, path, path.substring(0, path.lastIndexOf('/')) || '.');
    return module.exports;
  }
  window.console = {
    log: function(){ return post({op:'log', text: Array.prototype.map.call(arguments, fmt).join(' ')}); },
    info: function(){ return post({op:'log', text: Array.prototype.map.call(arguments, fmt).join(' ')}); },
    warn: function(){ return post({op:'log', text: 'WARN ' + Array.prototype.map.call(arguments, fmt).join(' ')}); },
    error: function(){ return post({op:'log', text: 'ERROR ' + Array.prototype.map.call(arguments, fmt).join(' ')}); }
  };
  window.__zRun = function(entryPath){
    return (async function(){ return exec(entryPath); })().then(
      async function(v){ await post({op:'done', ok:true, result: fmt(v)}); },
      async function(e){ await post({op:'done', ok:false, error: (e && e.message) ? e.message : String(e)}); }
    );
  };
''';

  /// Plain-run bootstrap (node_run): adds the proxied global `fetch`.
  static final String _bootstrap =
      '''
window.__zDone = false;
(function(){
  \$_core
  window.fetch = function(url, opts){
    opts = opts || {};
    return post2({op:'fetch', url: String(url), method: opts.method || 'GET', body: opts.body ? String(opts.body) : null}).then(function(data){
      return {
        ok: true, status: 200,
        text: function(){ return Promise.resolve(typeof data === 'string' ? data : JSON.stringify(data)); },
        json: function(){ return Promise.resolve(typeof data === 'string' ? JSON.parse(data) : data); }
      };
    });
  };
})();
'''
          .replaceAll(r'$_core', _coreJs);

  /// Module-run bootstrap: NO global fetch (network goes through the
  /// permission-gated `zagents.http`) plus the official `zagents` SDK
  /// object. Every SDK capability checks `window.__zPerms` on the JS side;
  /// the Dart bridge re-checks on every call.
  static final String _moduleBootstrap =
      '''
window.__zDone = false;
(function(){
  \$_core
  function zHas(p){ return Object.prototype.hasOwnProperty.call(window.__zPermsMap, p); }
  function zDeny(p){ throw new Error('Permission denied: ' + p); }
  function zCall(op, payload){
    var msg = { op:'zapi', zop: op };
    for (var k in payload) { msg[k] = payload[k]; }
    return window.flutter_inappwebview.callHandler('$_handlerName', msg).then(function(res){
      if (res && res.ok === false) throw new Error(res.error || 'module API error');
      return res ? res.data : null;
    });
  }
  // Module runs deliver their completion frame + logs over the zapi
  // channel (awaited, guaranteed) instead of the fire-and-forget post().
  window.__zRun = function(entryPath){
    return (async function(){ return exec(entryPath); })().then(
      async function(v){ await zCall('done', { ok: true, result: fmt(v) }); },
      async function(e){ await zCall('done', { ok: false, error: (e && e.message) ? e.message : String(e) }); }
    );
  };
  window.zagents = {
    info: window.__zInfo,
    log: function(){
      return zCall('log', { text: Array.prototype.map.call(arguments, fmt).join(' ') });
    },
    chat: {
      emit: function(text){
        if (!zHas('chat')) return zDeny('chat');
        return zCall('chat.emit', { text: String(text) });
      }
    },
    http: {
      request: function(url, opts){
        if (!zHas('network')) return zDeny('network');
        opts = opts || {};
        return zCall('http.request', {
          url: String(url),
          method: opts.method || 'GET',
          body: (opts.body === undefined || opts.body === null) ? null : String(opts.body),
          headers: opts.headers || {}
        }).then(function(data){
          var body = data ? data.body : null;
          var status = data && data.status ? data.status : 200;
          return {
            ok: status >= 200 && status < 300,
            status: status,
            body: body,
            text: function(){ return Promise.resolve(typeof body === 'string' ? body : JSON.stringify(body)); },
            json: function(){ return Promise.resolve(typeof body === 'string' ? JSON.parse(body) : body); }
          };
        });
      }
    },
    storage: {
      get: function(k){ if (!zHas('storage')) return zDeny('storage'); return zCall('storage.get', { key: String(k) }); },
      set: function(k, v){ if (!zHas('storage')) return zDeny('storage'); return zCall('storage.set', { key: String(k), value: (v === undefined) ? null : v }); },
      keys: function(){ if (!zHas('storage')) return zDeny('storage'); return zCall('storage.keys', {}); },
      remove: function(k){ if (!zHas('storage')) return zDeny('storage'); return zCall('storage.remove', { key: String(k) }); }
    },
    fs: {
      readFile: function(p){ if (!zHas('files')) return zDeny('files'); return post2({op:'fs', action:'readFile', path:p}); },
      writeFile: function(p, d){ if (!zHas('files')) return zDeny('files'); return post2({op:'fs', action:'writeFile', path:p, data:String(d)}); },
      appendFile: function(p, d){ if (!zHas('files')) return zDeny('files'); return post2({op:'fs', action:'appendFile', path:p, data:String(d)}); },
      readdir: function(p){ if (!zHas('files')) return zDeny('files'); return post2({op:'fs', action:'readdir', path:p}); },
      mkdir: function(p){ if (!zHas('files')) return zDeny('files'); return post2({op:'fs', action:'mkdir', path:p}); },
      unlink: function(p){ if (!zHas('files')) return zDeny('files'); return post2({op:'fs', action:'unlink', path:p}); },
      stat: function(p){ if (!zHas('files')) return zDeny('files'); return post2({op:'fs', action:'stat', path:p}); }
    }
  };
})();
'''
          .replaceAll(r'$_core', _coreJs);

  /// Builds the module registry reachable from [code].
  Map<String, Map<String, dynamic>> _buildRegistry(
    String code,
    List<String> moduleRoots,
  ) {
    final Map<String, Map<String, dynamic>> registry =
        <String, Map<String, dynamic>>{};
    final String userEntry = '__user__.js';
    final Map<String, String> userDeps = <String, String>{};
    for (final String spec in _extractRequires(code)) {
      final String? resolved = _resolveSpec(spec, moduleRoots);
      if (resolved != null) userDeps[spec] = resolved;
    }
    registry[userEntry] = <String, dynamic>{'src': code, 'deps': userDeps};

    final Queue<String> pending = Queue<String>.of(userDeps.values);
    final Set<String> seen = <String>{...userDeps.values};
    while (pending.isNotEmpty) {
      final String path = pending.removeFirst();
      String source;
      try {
        source = File(path).readAsStringSync();
      } catch (_) {
        continue;
      }
      final String dir = path.contains(Platform.pathSeparator)
          ? path.substring(0, path.lastIndexOf(Platform.pathSeparator))
          : '.';
      final Map<String, String> deps = <String, String>{};
      for (final String spec in _extractRequires(source)) {
        String? resolved;
        if (spec.startsWith('./') || spec.startsWith('../')) {
          resolved = _resolveRelative(dir, spec);
        } else if (spec != 'fs') {
          resolved = _resolveSpec(spec, moduleRoots);
        }
        if (resolved != null) {
          deps[spec] = resolved;
          if (!seen.contains(resolved)) {
            seen.add(resolved);
            pending.add(resolved);
          }
        }
      }
      registry[path] = <String, dynamic>{'src': source, 'deps': deps};
    }
    return registry;
  }

  static final RegExp _requireRegex = RegExp(
    r'''require\s*\(\s*['"]([^'"]+)['"]\s*\)''',
  );

  static List<String> _extractRequires(String source) => <String>[
    for (final Match match in _requireRegex.allMatches(source))
      if ((match.group(1) ?? '').isNotEmpty) match.group(1)!,
  ];

  /// Resolves a bare specifier (pkg, pkg/sub, @scope/pkg[/sub]) to a file
  /// under one of [moduleRoots], honoring package.json "main".
  String? _resolveSpec(String spec, List<String> moduleRoots) {
    String pkg = spec;
    if (spec.startsWith('@')) {
      final List<String> parts = spec.split('/');
      pkg = parts.length >= 2 ? '${parts[0]}/${parts[1]}' : spec;
    } else {
      pkg = spec.split('/').first;
    }
    final String subPath = spec.contains('/')
        ? spec.substring(spec.indexOf('/') + 1)
        : '';
    for (final String root in moduleRoots) {
      final String base =
          '$root${Platform.pathSeparator}$pkg${Platform.pathSeparator}';
      final File pkgJson = File('${base}package.json');
      String main = 'index.js';
      if (pkgJson.existsSync()) {
        try {
          final Object? meta = jsonDecode(pkgJson.readAsStringSync());
          if (meta is Map) {
            final Object? mainField = meta['main'];
            if (mainField is String && mainField.isNotEmpty) main = mainField;
          }
        } catch (_) {}
      }
      final List<String> candidates = <String>[
        if (subPath.isNotEmpty) ...<String>[
          base + subPath,
          '$base$subPath.js',
          '$base$subPath${Platform.pathSeparator}index.js',
        ],
        base + main,
        '${base}index.js',
      ];
      for (final String candidate in candidates) {
        if (FileSystemEntity.typeSync(candidate) == FileSystemEntityType.file) {
          return candidate;
        }
      }
    }
    return null;
  }

  /// Resolves './x' / '../x' relative to [fromDir].
  String? _resolveRelative(String fromDir, String spec) {
    final List<String> segments = fromDir.split(Platform.pathSeparator);
    for (final String part in spec.split('/')) {
      if (part == '.' || part.isEmpty) continue;
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(part);
      }
    }
    final String base = segments.join(Platform.pathSeparator);
    for (final String candidate in <String>[
      base,
      '$base.js',
      '$base${Platform.pathSeparator}index.js',
    ]) {
      if (FileSystemEntity.typeSync(candidate) == FileSystemEntityType.file) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Future<JsRunResult> run(
    String code, {
    List<String> moduleRoots = const <String>[],
    String? workingDir,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    // Fresh context per run (v1.20.0): dispose whatever WebView exists —
    // its JS heap holds the previous run's module cache, window globals
    // and __zRegistry (which contains literal script sources, including
    // any credentials embedded there) — then boot a clean one.
    try {
      await _recycle();
      await _ensureRunning();
    } catch (e) {
      return JsRunResult(output: '', error: 'JS runtime failed to start: $e');
    }
    _console.clear();
    _sandboxRoots = <String>[?workingDir, ...moduleRoots];
    final Map<String, Map<String, dynamic>> registry = _buildRegistry(
      code,
      moduleRoots,
    );
    _done = Completer<String>();

    final String runner =
        '''
(function(){
  window.__zRegistry = ${jsonEncode(registry)};
  __zRun('__user__.js');
})();
''';

    String? raw;
    try {
      _webview!.webViewController!.evaluateJavascript(source: runner);
      raw = await _done!.future.timeout(timeout);
    } on TimeoutException {
      await _recycle();
      return JsRunResult(
        output: _console.join('\n'),
        error: 'Script timed out after ${timeout.inSeconds}s.',
      );
    } catch (e) {
      await _recycle();
      return JsRunResult(output: _console.join('\n'), error: '$e');
    }

    try {
      final Object? payload = jsonDecode(raw);
      if (payload is Map<String, dynamic>) {
        return JsRunResult(
          output: _console.join('\n'),
          error: payload['ok'] == true ? null : payload['error']?.toString(),
          result: payload['result']?.toString(),
        );
      }
    } catch (_) {}
    return JsRunResult(
      output: _console.join('\n'),
      error: 'JS runtime returned an unreadable result.',
    );
  }

  /// Module runs boot the same fresh-WebView pipeline as [run] but swap
  /// in the module bootstrap (permission-gated `zagents` SDK, no global
  /// fetch) and register the SDK shim as a require-able virtual module.
  @override
  Future<JsRunResult> runModule(ModuleInvocation invocation) async {
    try {
      await _recycle();
      await _ensureRunning(bootstrap: _moduleBootstrap);
    } catch (e) {
      return JsRunResult(output: '', error: 'JS runtime failed to start: $e');
    }
    _console.clear();
    _modulePermissions = invocation.permissions;
    _moduleBridge = invocation.bridge;
    _sandboxRoots = <String>[?invocation.workingDir, ...invocation.moduleRoots];
    final Map<String, Map<String, dynamic>> registry = _buildRegistry(
      invocation.entrySource,
      invocation.moduleRoots,
    );
    // Register the official SDK shim so `require('zagents-sdk')` works
    // next to the injected `zagents` global.
    if (invocation.sdkSource.trim().isNotEmpty) {
      registry['zagents-sdk.js'] = <String, dynamic>{
        'src': invocation.sdkSource,
        'deps': const <String, String>{},
      };
      final Map<String, dynamic> entry = registry['__user__.js']!;
      (entry['deps'] as Map<String, dynamic>)['zagents-sdk'] = 'zagents-sdk.js';
    }
    _done = Completer<String>();

    final String runner =
        '''
(function(){
  window.__zRegistry = ${jsonEncode(registry)};
  window.__zPermsMap = {};
  ${jsonEncode(invocation.permissions.toList())}.forEach(function(p){ window.__zPermsMap[p] = true; });
  window.__zInfo = ${jsonEncode(invocation.info)};
  __zRun('__user__.js');
})();
''';

    String? raw;
    try {
      _webview!.webViewController!.evaluateJavascript(source: runner);
      raw = await _done!.future.timeout(invocation.timeout);
    } on TimeoutException {
      await _recycle();
      return JsRunResult(
        output: _console.join('\n'),
        error: 'Module timed out after ${invocation.timeout.inSeconds}s.',
      );
    } catch (e) {
      await _recycle();
      return JsRunResult(output: _console.join('\n'), error: '$e');
    } finally {
      _modulePermissions = null;
      _moduleBridge = null;
    }

    try {
      final Object? payload = jsonDecode(raw);
      if (payload is Map<String, dynamic>) {
        return JsRunResult(
          output: _console.join('\n'),
          error: payload['ok'] == true ? null : payload['error']?.toString(),
          result: payload['result']?.toString(),
        );
      }
    } catch (_) {}
    return JsRunResult(
      output: _console.join('\n'),
      error: 'JS runtime returned an unreadable result.',
    );
  }

  Future<void> _recycle() async {
    try {
      await _webview?.dispose();
    } catch (_) {}
    _webview = null;
  }

  @override
  void dispose() {
    _recycle();
  }
}

/// Serializes executions through an inner [JsRuntime] so parallel calls
/// (node_run from multiple chat sessions running at once) never interleave
/// inside one hidden WebView: each run completes before the next starts,
/// and a failing run never poisons the queue.
///
/// Combined with [WebViewJsRuntime]'s fresh-context-per-run this is the
/// cross-chat privacy guarantee for the embedded Node.js runtime.
class SerializedJsRuntime implements JsRuntime {
  SerializedJsRuntime(this._inner);

  final JsRuntime _inner;

  Future<void> _tail = Future<void>.value();

  @override
  Future<JsRunResult> run(
    String code, {
    List<String> moduleRoots = const <String>[],
    String? workingDir,
    Duration timeout = const Duration(seconds: 20),
  }) {
    final Future<JsRunResult> run = _tail.then(
      (_) => _inner.run(
        code,
        moduleRoots: moduleRoots,
        workingDir: workingDir,
        timeout: timeout,
      ),
    );
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  @override
  Future<JsRunResult> runModule(ModuleInvocation invocation) {
    final Future<JsRunResult> run = _tail.then(
      (_) => _inner.runModule(invocation),
    );
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  @override
  void dispose() => _inner.dispose();
}
