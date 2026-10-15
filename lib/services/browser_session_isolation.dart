import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_automation.dart';

/// Per-origin browser state owned by ONE chat session: the last URL loaded
/// on that origin, the login cookies captured there, and the web storage
/// snapshots (localStorage / sessionStorage).
class OriginState {
  OriginState({
    required this.lastUrl,
    Map<String, String>? cookies,
    Map<String, String>? localStorage,
    Map<String, String>? sessionStorage,
  }) : cookies = cookies ?? <String, String>{},
       localStorage = localStorage ?? <String, String>{},
       sessionStorage = sessionStorage ?? <String, String>{};

  /// Full URL the state was captured at. Used as the cookie read/write
  /// scope because the Android cookie jar exposes no path metadata —
  /// restoring at the same URL keeps path-scoped login cookies working.
  String lastUrl;

  final Map<String, String> cookies;
  final Map<String, String> localStorage;
  final Map<String, String> sessionStorage;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'lastUrl': lastUrl,
    'cookies': cookies,
    'local': localStorage,
    'session': sessionStorage,
  };

  /// Defensive parse: a corrupted or hand-edited entry degrades to a fresh
  /// origin state instead of throwing.
  static OriginState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lastUrl = raw['lastUrl']?.toString() ?? '';
    return OriginState(
      lastUrl: lastUrl,
      cookies: _stringMap(raw['cookies']),
      localStorage: _stringMap(raw['local']),
      sessionStorage: _stringMap(raw['session']),
    );
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        if (entry.key != null && entry.value != null)
          entry.key.toString(): entry.value.toString(),
    };
  }
}

/// Everything one chat session owns in the embedded browser, keyed by
/// origin ("https://example.com"). Serialized into the session's own
/// sandbox as `browser_state.json`.
class BrowserState {
  BrowserState({Map<String, OriginState>? origins})
    : origins = origins ?? <String, OriginState>{};

  final Map<String, OriginState> origins;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': 1,
    'origins': <String, dynamic>{
      for (final entry in origins.entries) entry.key: entry.value.toJson(),
    },
  };

  static BrowserState fromJson(Object? raw) {
    if (raw is! Map) return BrowserState();
    final originsRaw = raw['origins'];
    if (originsRaw is! Map) return BrowserState();
    final origins = <String, OriginState>{};
    for (final entry in originsRaw.entries) {
      final state = OriginState.fromJson(entry.value);
      if (state != null) origins[entry.key.toString()] = state;
    }
    return BrowserState(origins: origins);
  }
}

/// Persists each session's browser state inside that session's sandbox
/// (`<sessionRoot>/browser_state.json`), so logins survive app restarts
/// and never leave the chat that created them. A null sessionId keeps the
/// state in memory only (legacy/global surface).
///
/// All disk IO is synchronous on purpose (see session_sandbox.dart): async
/// directory scans never complete inside async-test widget tests.
class BrowserStateStore {
  BrowserStateStore({required this.rootFor});

  /// Yields the workspace root for a session id (SessionSandbox.rootFor).
  final Future<Directory> Function(String? sessionId) rootFor;

  static const String _fileName = 'browser_state.json';
  static const String _legacyKey = '_legacy';

  final Map<String, BrowserState> _memory = <String, BrowserState>{};

  Future<BrowserState> load(String? sessionId) async {
    if (sessionId == null) {
      return _memory.putIfAbsent(_legacyKey, BrowserState.new);
    }
    try {
      final dir = await rootFor(sessionId);
      final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      if (!file.existsSync()) return BrowserState();
      final raw = jsonDecode(file.readAsStringSync());
      return BrowserState.fromJson(raw);
    } catch (_) {
      // Corrupt state = fresh private window, never a crash.
      return BrowserState();
    }
  }

  Future<void> save(String? sessionId, BrowserState state) async {
    if (sessionId == null) {
      _memory[_legacyKey] = state;
      return;
    }
    try {
      final dir = await rootFor(sessionId);
      dir.createSync(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      file.writeAsStringSync(jsonEncode(state.toJson()));
    } catch (_) {
      // Persistence is best-effort: losing a snapshot degrades to a
      // logged-out session, not an agent failure.
    }
  }

  /// Drops the persisted state: the session's next browser use starts
  /// logged out on every origin ("forget this window's history").
  Future<void> clear(String? sessionId) async {
    if (sessionId == null) {
      _memory.remove(_legacyKey);
      return;
    }
    try {
      final dir = await rootFor(sessionId);
      final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best effort.
    }
  }
}

/// Read/write access to the platform cookie jar. On Android the
/// CookieManager is GLOBAL — every WebView in the process shares one jar,
/// which is exactly why sessions must swap it under a lock.
abstract class CookieGateway {
  /// Cookies visible at [url] as a name→value map (metadata-free).
  Future<Map<String, String>> readForUrl(String url);

  /// Removes every cookie from the shared jar.
  Future<void> clearAll();

  /// Writes [cookies] so they are visible at [url].
  Future<void> writeForUrl(String url, Map<String, String> cookies);
}

/// Production gateway over flutter_inappwebview's CookieManager.
class InAppCookieGateway implements CookieGateway {
  const InAppCookieGateway();

  @override
  Future<Map<String, String>> readForUrl(String url) async {
    try {
      final list = await CookieManager.instance().getCookies(url: WebUri(url));
      return <String, String>{
        for (final cookie in list)
          if (cookie.name.isNotEmpty) cookie.name: cookie.value ?? '',
      };
    } catch (_) {
      return const <String, String>{};
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {
      // Best effort.
    }
  }

  @override
  Future<void> writeForUrl(String url, Map<String, String> cookies) async {
    if (cookies.isEmpty) return;
    final uri = WebUri(url);
    final manager = CookieManager.instance();
    for (final entry in cookies.entries) {
      try {
        await manager.setCookie(url: uri, name: entry.key, value: entry.value);
      } catch (_) {
        // Best effort: a rejected cookie degrades to a logged-out origin.
      }
    }
  }
}

/// Fair-enough mutex: chains queued closures behind a single tail future so
/// browser operations from parallel chat sessions never interleave.
class _Mutex {
  Future<void> _tail = Future<void>.value();

  Future<T> protect<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }
}

/// Wraps a [BrowserAutomation] so every operation is scoped to the calling
/// chat session — the "private window" guarantee for the embedded browser:
///
/// - Cookies are swapped under a lock when the session changes: the
///   outgoing session's jar is captured into its sandbox, the jar is
///   cleared, and the incoming session's cookies are restored.
/// - Web storage (localStorage / sessionStorage) is reconciled per origin
///   on first visit: leftovers from another session are wiped, the
///   session's own snapshot is re-injected, and the page is reloaded so it
///   boots with the right identity.
///
/// State lives in [BrowserStateStore] (per-session sandbox file), so a
/// chat keeps its logins across app restarts while remaining invisible to
/// every other chat.
class IsolatedBrowserAutomation implements BrowserAutomation {
  IsolatedBrowserAutomation({
    required this.inner,
    required this.store,
    required this.cookies,
  });

  final BrowserAutomation inner;
  final BrowserStateStore store;
  final CookieGateway cookies;

  String? _active;
  final Set<String> _reconciled = <String>{};
  final _Mutex _mutex = _Mutex();

  /// Session whose browser identity currently lives in the WebView.
  String? get activeSessionId => _active;

  /// JS run after a page settles: reports href + document.cookie +
  /// storage dumps so the snapshot can be persisted.
  static const String captureJs =
      '(function(){function dump(s){var o={};for(var i=0;i<s.length;i++)'
      '{var k=s.key(i);o[k]=String(s.getItem(k));}return o;}'
      'return JSON.stringify({href:location.href,'
      'cookie:document.cookie||"",local:dump(window.localStorage),'
      'session:dump(window.sessionStorage)});})()';

  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    String? sessionId,
  }) {
    return _mutex.protect(() async {
      await _activate(sessionId);
      final first = await inner.navigate(
        url,
        timeout: timeout,
        sessionId: sessionId,
      );
      final landing = first.url.isNotEmpty ? first.url : url;
      final origin = _originOf(landing);
      if (origin == null || !_reconciled.add(origin)) {
        await _capture(sessionId);
        return first;
      }
      // First visit of this origin inside this session: wipe any leftovers
      // from other chats, re-inject this session's snapshot, then reload so
      // the page boots with the right identity.
      await _reconcileStorage(sessionId, origin);
      final reloaded = await inner.navigate(
        url,
        timeout: timeout,
        sessionId: sessionId,
      );
      await _capture(sessionId);
      return reloaded;
    });
  }

  @override
  Future<Map<String, dynamic>> click({
    String? selector,
    String? text,
    String? sessionId,
  }) {
    return _scoped(sessionId, () async {
      final result = await inner.click(
        selector: selector,
        text: text,
        sessionId: sessionId,
      );
      await _capture(sessionId);
      return result;
    });
  }

  @override
  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear = true,
    String? sessionId,
  }) {
    return _scoped(sessionId, () async {
      final result = await inner.type(
        text,
        selector: selector,
        clear: clear,
        sessionId: sessionId,
      );
      await _capture(sessionId);
      return result;
    });
  }

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
    String? sessionId,
  }) {
    return _scoped(sessionId, () async {
      final result = await inner.scroll(
        direction: direction,
        amount: amount,
        sessionId: sessionId,
      );
      await _capture(sessionId);
      return result;
    });
  }

  @override
  Future<String?> screenshot({required String saveDir, String? sessionId}) {
    return _scoped(
      sessionId,
      () => inner.screenshot(saveDir: saveDir, sessionId: sessionId),
    );
  }

  @override
  Future<String> extractText({int maxLength = 8000, String? sessionId}) {
    return _scoped(
      sessionId,
      () => inner.extractText(maxLength: maxLength, sessionId: sessionId),
    );
  }

  @override
  Future<String> runJs(String code, {String? sessionId}) {
    return _scoped(sessionId, () async {
      final result = await inner.runJs(code, sessionId: sessionId);
      await _capture(sessionId);
      return result;
    });
  }

  @override
  Future<void> resetSession() => inner.resetSession();

  @override
  Future<void> purgeSiteData() => inner.purgeSiteData();

  @override
  Future<String> reconcileOriginStorage(String payloadJson) =>
      inner.reconcileOriginStorage(payloadJson);

  @override
  void dispose() => inner.dispose();

  /// Activates [sessionId] if needed, runs [action], then snapshots the
  /// resulting state back into the session — all under the global lock so
  /// parallel sessions never see each other's jar.
  Future<T> _scoped<T>(String? sessionId, Future<T> Function() action) {
    return _mutex.protect(() async {
      await _activate(sessionId);
      final result = await action();
      return result;
    });
  }

  Future<void> _activate(String? sessionId) async {
    if (sessionId == _active) return;
    // Flush the outgoing session first: late redirects (login POSTs, SSO
    // hops) may have touched cookies after its last capture.
    if (_active != null) {
      await _capture(_active);
    }
    final target = await store.load(sessionId);
    await cookies.clearAll();
    // Private-window hardening (v1.20.0): while the identities are
    // swapped, also wipe the shared HTTP cache and ALL web storage
    // (localStorage / sessionStorage / IndexedDB / AppCache). Auth tokens
    // hidden in IndexedDB or cached authenticated responses of the
    // outgoing chat are destroyed, not just its cookies.
    await inner.purgeSiteData();
    for (final origin in target.origins.keys) {
      final o = target.origins[origin]!;
      if (o.cookies.isNotEmpty) {
        await cookies.writeForUrl(
          o.lastUrl.isNotEmpty ? o.lastUrl : origin,
          o.cookies,
        );
      }
    }
    _active = sessionId;
    _reconciled.clear();
  }

  /// Snapshots the current page (cookies + web storage) into [sessionId]'s
  /// state. Safe to call repeatedly; skips cleanly when no page is loaded.
  Future<void> _capture(String? sessionId) async {
    final state = await store.load(sessionId);
    final raw = await inner.runJs(captureJs, sessionId: sessionId);
    final data = _decodeMap(raw);
    if (data == null) {
      await store.save(sessionId, state);
      return;
    }
    final href = data['href']?.toString() ?? '';
    final origin = _originOf(href);
    if (origin == null) {
      await store.save(sessionId, state);
      return;
    }
    final o = state.origins.putIfAbsent(
      origin,
      () => OriginState(lastUrl: href),
    );
    o.lastUrl = href;

    // Cookies: the platform jar (includes httpOnly) merged with
    // document.cookie (covers host-only quirks of plugin readers).
    final jar = <String, String>{};
    try {
      jar.addAll(await cookies.readForUrl(href));
    } catch (_) {}
    jar.addAll(_parseCookieHeader(data['cookie']?.toString()));
    o.cookies
      ..clear()
      ..addAll(jar);

    o.localStorage
      ..clear()
      ..addAll(OriginState._stringMap(data['local']));
    o.sessionStorage
      ..clear()
      ..addAll(OriginState._stringMap(data['session']));
    await store.save(sessionId, state);
  }

  Future<void> _reconcileStorage(String? sessionId, String origin) async {
    final state = await store.load(sessionId);
    final o = state.origins[origin];
    final payload = jsonEncode(<String, dynamic>{
      'local': o?.localStorage ?? const <String, String>{},
      'session': o?.sessionStorage ?? const <String, String>{},
    });
    // v1.20.0: reconciliation is async now — it also deletes this
    // origin's IndexedDB databases and unregisters its service workers
    // before re-injecting the session snapshot (awaited on the page, then
    // the caller reloads so the site boots with the right identity).
    await inner.reconcileOriginStorage(payload);
  }

  static Map<String, dynamic>? _decodeMap(Object? raw) {
    Object? current = raw;
    // evaluateJavascript may hand back a JSON string (sometimes doubly
    // encoded) — peel strings until a Map shows up.
    for (var i = 0; i < 3 && current is String; i++) {
      if (current.trim().isEmpty) return null;
      try {
        current = jsonDecode(current);
      } catch (_) {
        return null;
      }
    }
    return current is Map<String, dynamic> ? current : null;
  }

  static Map<String, String> _parseCookieHeader(String? header) {
    if (header == null || header.trim().isEmpty) {
      return const <String, String>{};
    }
    final map = <String, String>{};
    for (final part in header.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final name = part.substring(0, idx).trim();
      final value = part.substring(idx + 1).trim();
      if (name.isNotEmpty) map[name] = value;
    }
    return map;
  }

  /// scheme://host[:port] or null for non-web URLs (about:blank, data:...).
  static String? _originOf(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    try {
      final uri = Uri.parse(trimmed);
      if ((uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty) {
        return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
