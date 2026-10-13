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
/// zero extra native footprint, guaranteed single-APK. Tests plug fakes in.
abstract class JsRuntime {
  Future<JsRunResult> run(
    String code, {
    List<String> moduleRoots = const <String>[],
    String? workingDir,
    Duration timeout = const Duration(seconds: 20),
  });

  void dispose();
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
class WebViewJsRuntime implements JsRuntime {
  WebViewJsRuntime({this.fetchProxy});

  /// Dart-side proxy for in-script `fetch(url)` calls (text bodies).
  final Future<Map<String, dynamic>?> Function(
    String url,
    String method,
    String? body,
  )?
  fetchProxy;

  HeadlessInAppWebView? _webview;
  Completer<String>? _done;
  final List<String> _console = <String>[];
  List<String> _sandboxRoots = const <String>[];

  static const String _handlerName = 'zagentsNode';

  Future<void> _ensureRunning() async {
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
    await wv.webViewController!.evaluateJavascript(source: _bootstrap);
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

  static const String _bootstrap =
      '''
window.__zDone = false;
(function(){
  function post(msg){ try { window.flutter_inappwebview.callHandler('$_handlerName', msg); } catch(e){} }
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
    log: function(){ post({op:'log', text: Array.prototype.map.call(arguments, fmt).join(' ')}); },
    info: function(){ post({op:'log', text: Array.prototype.map.call(arguments, fmt).join(' ')}); },
    warn: function(){ post({op:'log', text: 'WARN ' + Array.prototype.map.call(arguments, fmt).join(' ')}); },
    error: function(){ post({op:'log', text: 'ERROR ' + Array.prototype.map.call(arguments, fmt).join(' ')}); }
  };
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
  window.__zRun = function(entryPath){
    return (async function(){ return exec(entryPath); })().then(
      function(v){ post({op:'done', ok:true, result: fmt(v)}); },
      function(e){ post({op:'done', ok:false, error: (e && e.message) ? e.message : String(e)}); }
    );
  };
})();
''';

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
    try {
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

/// Records executions instead of running JS — for unit/widget tests.
class FakeJsRuntime implements JsRuntime {
  FakeJsRuntime([this.nextResult]);

  JsRunResult? nextResult;
  final List<String> runs = <String>[];

  @override
  Future<JsRunResult> run(
    String code, {
    List<String> moduleRoots = const <String>[],
    String? workingDir,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    runs.add(code);
    return nextResult ?? JsRunResult(output: 'ok', result: '"ok"');
  }

  @override
  void dispose() {}
}
