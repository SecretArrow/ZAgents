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

  /// Removes cookies from the shared jar as seen at [url] (v1.37.0).
  ///
  /// With [names] set, only those cookie names are deleted — the surgical
  /// primitive the multi-context engine uses to take one context's
  /// identity off the shared jar without disturbing concurrent contexts.
  /// Without [names], everything readable at [url] is deleted.
  ///
  /// Android's CookieManager offers no per-URL deletion, so the
  /// production gateway rewrites each cookie with an expired epoch
  /// (best effort — a rejected delete degrades to a lingering cookie).
  Future<void> deleteForUrl(String url, {Set<String>? names});
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

  @override
  Future<void> deleteForUrl(String url, {Set<String>? names}) async {
    try {
      final Map<String, String> visible = await readForUrl(url);
      final Iterable<String> targets = names ?? visible.keys;
      final uri = WebUri(url);
      final manager = CookieManager.instance();
      for (final String name in targets) {
        if (!visible.containsKey(name) && names != null) continue;
        try {
          await manager.setCookie(
            url: uri,
            name: name,
            value: '',
            path: '/',
            expiresDate: 0,
            maxAge: 0,
          );
        } catch (_) {
          // Best effort.
        }
      }
    } catch (_) {
      // Best effort: a failed delete keeps the cookie until the next
      // full jar purge; never crash the agent loop over it.
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
  BrowserAutomation withContext(String contextId) => this;

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

/// One independent browser context (v1.37.0): its own headless WebView,
/// its own operation lock and its own captured per-origin state. Two
/// contexts never wait on each other — page loads, clicks and extractions
/// run in genuine parallel, which is what the fan of subagents needs.
class _ContextSlot {
  _ContextSlot({
    required this.key,
    required this.inner,
    required this.ephemeral,
  }) : mutex = _Mutex();

  /// Identity of the slot inside the manager (`s:<sessionId>` for chat
  /// sessions, `ctx:<id>` for named parallel contexts, `_legacy` when no
  /// scope was supplied).
  final String key;

  /// The private WebView engine backing this context.
  final BrowserAutomation inner;

  /// Named parallel contexts (subagents) live in memory only: their
  /// browsing identity dies with the task. Chat-session slots persist
  /// their state through the [BrowserStateStore] like v1.19.0 did.
  final bool ephemeral;

  /// v1.38.0: ops that have ENTERED _run for this slot but not finished
  /// their mutex turn (queued included). Eviction must never dispose a
  /// slot with queued work — the queued op would otherwise boot an
  /// untracked replacement engine (leak) and run against a dead context.
  int pendingOps = 0;

  /// Operations inside ONE context serialize here; different contexts
  /// hold different mutexes and run side by side.
  final _Mutex mutex;

  BrowserState state = BrowserState();
  String? sessionId;
  bool loaded = false;

  /// Origins whose storage was already reconciled in this context.
  final Set<String> reconciled = <String>{};

  /// True while an operation of this slot is queued or running — guards
  /// jar cleanup against concurrent same-origin contexts.
  bool inOp = false;

  /// LRU stamp for eviction.
  int lastUsed = 0;
  bool disposed = false;
}

/// Multi-context browser engine (v1.37.0): the "private window" guarantee
/// of [IsolatedBrowserAutomation], extended from one shared WebView to a
/// pool of independent contexts.
///
/// Why the old engine could not scale: it serialized EVERY browser
/// operation behind one global mutex because one WebView carried all
/// sessions' identities — a fan of subagents waited one by one. This
/// engine gives every scope (chat session, subagent task) its own
/// WebView, so parallel workers browse simultaneously.
///
/// The platform cookie jar is still process-global on Android, so cross
/// context isolation is maintained surgically instead of by wholesale
/// jar swaps:
/// * first use in the process purges the shared jar, cache and web
///   storage exactly like the old first activation;
/// * a context's first visit of an origin removes the cookie names other
///   IDLE contexts recorded for that origin from the shared jar, then
///   writes its own snapshot (never touching contexts that are mid-op);
/// * a context's cookies are re-captured after every operation into its
///   own state — persisted per chat session, in-memory for ephemeral
///   subagent contexts;
/// * evicting a slot disposes its WebView and takes its recorded cookie
///   names off the shared jar (best-effort logout).
///
/// Known soft edge (documented): two contexts actively using the SAME
/// origin at the same moment share that origin's jar slice for the
/// overlap window — same as two real browser windows of one profile.
class ContextualBrowserAutomation implements BrowserAutomation {
  ContextualBrowserAutomation({
    required this._makeInner,
    required this.store,
    required this.cookies,
    this.maxContexts = 4,
  });

  final BrowserAutomation Function() _makeInner;
  final BrowserStateStore store;
  final CookieGateway cookies;

  /// Live WebView cap. The fan of subagents uses maxParallel=3 plus the
  /// chat's own context; beyond this cap the least-recently-used idle
  /// context is disposed and recreated on demand.
  final int maxContexts;

  final Map<String, _ContextSlot> _slots = <String, _ContextSlot>{};
  BrowserAutomation? _sharedInner;
  int _stamp = 0;
  int _opsInFlight = 0;
  bool _purgedOnce = false;

  /// v1.38.0: set when the one-time jar purge had to be deferred because
  /// the process's first browser activity was a parallel fan; retried in
  /// _run's teardown the moment _opsInFlight reaches 0.
  bool _purgePending = false;

  static const String _legacyKey = '_legacy';

  @override
  BrowserAutomation withContext(String contextId) =>
      _PinnedContextAutomation(this, contextId);

  // ---- public API (context resolved from sessionId) -----------------------

  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    String? sessionId,
  }) => _navigate(url, timeout: timeout, sessionId: sessionId);

  @override
  Future<Map<String, dynamic>> click({
    String? selector,
    String? text,
    String? sessionId,
  }) => _click(selector: selector, text: text, sessionId: sessionId);

  @override
  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear = true,
    String? sessionId,
  }) => _type(text, selector: selector, clear: clear, sessionId: sessionId);

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
    String? sessionId,
  }) => _scroll(direction: direction, amount: amount, sessionId: sessionId);

  @override
  Future<String?> screenshot({required String saveDir, String? sessionId}) =>
      _run<String?>(
        null,
        sessionId: sessionId,
        op: (slot) => slot.inner.screenshot(saveDir: saveDir, sessionId: null),
      );

  @override
  Future<String> extractText({int maxLength = 8000, String? sessionId}) =>
      _run<String>(
        null,
        sessionId: sessionId,
        op: (slot) => slot.inner.extractText(maxLength: maxLength),
      );

  @override
  Future<String> runJs(String code, {String? sessionId}) => _run<String>(
    null,
    sessionId: sessionId,
    op: (slot) async {
      final String result = await slot.inner.runJs(code);
      await _capture(slot);
      return result;
    },
  );

  @override
  Future<void> purgeSiteData() async {
    final BrowserAutomation inner = await _ensureSharedInner();
    await inner.purgeSiteData();
  }

  @override
  Future<String> reconcileOriginStorage(String payloadJson) async {
    final BrowserAutomation inner = await _ensureSharedInner();
    return inner.reconcileOriginStorage(payloadJson);
  }

  @override
  Future<void> resetSession() async {
    final BrowserAutomation inner = await _ensureSharedInner();
    await inner.resetSession();
  }

  @override
  void dispose() {
    for (final _ContextSlot slot in _slots.values) {
      try {
        slot.inner.dispose();
      } catch (_) {
        // Best effort.
      }
      slot.disposed = true;
    }
    _slots.clear();
    try {
      _sharedInner?.dispose();
    } catch (_) {
      // Best effort.
    }
    _sharedInner = null;
  }

  // ---- context-scoped internals (also used by the pinned view) ------------

  Future<BrowserAutomation> _ensureSharedInner() async {
    if (_sharedInner != null) return _sharedInner!;
    final BrowserAutomation inner = _makeInner();
    _sharedInner = inner;
    return inner;
  }

  Future<BrowserPageInfo> _navigate(
    String url, {
    required Duration timeout,
    String? sessionId,
    String? contextId,
  }) => _run<BrowserPageInfo>(
    contextId,
    sessionId: sessionId,
    op: (slot) => _navigateOp(slot, url, timeout),
  );

  Future<Map<String, dynamic>> _click({
    String? selector,
    String? text,
    String? sessionId,
    String? contextId,
  }) => _run<Map<String, dynamic>>(
    contextId,
    sessionId: sessionId,
    op: (slot) async {
      final Map<String, dynamic> result = await slot.inner.click(
        selector: selector,
        text: text,
      );
      await _capture(slot);
      return result;
    },
  );

  Future<Map<String, dynamic>> _type(
    String text, {
    String? selector,
    bool clear = true,
    String? sessionId,
    String? contextId,
  }) => _run<Map<String, dynamic>>(
    contextId,
    sessionId: sessionId,
    op: (slot) async {
      final Map<String, dynamic> result = await slot.inner.type(
        text,
        selector: selector,
        clear: clear,
      );
      await _capture(slot);
      return result;
    },
  );

  Future<Map<String, dynamic>> _scroll({
    String direction = 'down',
    int amount = 800,
    String? sessionId,
    String? contextId,
  }) => _run<Map<String, dynamic>>(
    contextId,
    sessionId: sessionId,
    op: (slot) async {
      final Map<String, dynamic> result = await slot.inner.scroll(
        direction: direction,
        amount: amount,
      );
      await _capture(slot);
      return result;
    },
  );

  Future<BrowserPageInfo> _navigateOp(
    _ContextSlot slot,
    String url,
    Duration timeout,
  ) async {
    if (url.trim().isEmpty) {
      return BrowserPageInfo(
        url: '',
        title: '',
        text: '',
        error: 'URL is empty',
      );
    }
    // Claim the origin BEFORE the first load so the request already leaves
    // with this context's cookies and without another idle context's.
    final String? requestedOrigin = _originOf(
      url.trim().contains('://') ? url.trim() : 'https://${url.trim()}',
    );
    if (requestedOrigin != null && !slot.reconciled.contains(requestedOrigin)) {
      await _claimOrigin(slot, requestedOrigin);
    }
    final BrowserPageInfo first = await slot.inner.navigate(
      url,
      timeout: timeout,
    );
    final String landing = first.url.isNotEmpty ? first.url : url;
    final String? origin = _originOf(landing);
    if (origin == null || !slot.reconciled.add(origin)) {
      await _capture(slot);
      return first;
    }
    // First visit of this origin inside this context: wipe leftovers from
    // other contexts, re-inject this context's snapshot, then reload so
    // the page boots with the right identity.
    await _reconcileStorage(slot, origin);
    final BrowserPageInfo reloaded = await slot.inner.navigate(
      url,
      timeout: timeout,
    );
    await _capture(slot);
    return reloaded;
  }

  /// Runs [op] against the slot for [contextId] (named parallel context)
  /// or the calling [sessionId] (chat session), serialized per slot but
  /// parallel across slots.
  Future<T> _run<T>(
    String? contextId, {
    String? sessionId,
    required Future<T> Function(_ContextSlot slot) op,
  }) async {
    final String key = contextId != null && contextId.isNotEmpty
        ? 'ctx:$contextId'
        : sessionId != null
        ? 's:$sessionId'
        : _legacyKey;
    _opsInFlight++;
    _stamp++;
    final int stamp = _stamp;
    // Hoisted so the idle-teardown finally below can reach the slot.
    _ContextSlot? slot;
    try {
      slot = _slotFor(key, sessionId);
      slot.lastUsed = stamp;
      slot.inOp = true;
      slot.pendingOps++;
      try {
        return await slot.mutex.protect(() async {
          await _ensureLoaded(slot!, sessionId);
          return op(slot!);
        });
      } finally {
        // v1.38.0: keep inOp true while sibling ops are still QUEUED on
        // this slot's mutex — clearing it early made the slot look idle,
        // so eviction could dispose a context that still had work lined
        // up (the queued op then leaked an untracked engine).
        slot.inOp = slot.pendingOps > 1;
        slot.pendingOps--;
      }
    } finally {
      _opsInFlight--;
      if (!_purgedOnce && _purgePending && _opsInFlight == 0) {
        // The whole process just went idle after a parallel first fan —
        // now the shared jar can be wiped safely.
        _purgePending = false;
        _purgedOnce = true;
        try {
          await cookies.clearAll();
        } catch (_) {
          // Best effort.
        }
        try {
          await slot!.inner.purgeSiteData();
        } catch (_) {
          // Best effort.
        }
      }
      _evictIdleSlots();
    }
  }

  _ContextSlot _slotFor(String key, String? sessionId) {
    final _ContextSlot? existing = _slots[key];
    if (existing != null && !existing.disposed) return existing;
    final bool ephemeral = !key.startsWith('s:');
    final _ContextSlot slot = _ContextSlot(
      key: key,
      inner: _makeInner(),
      ephemeral: ephemeral,
    );
    _slots[key] = slot;
    return slot;
  }

  /// Loads the slot's persisted state (chat sessions) or starts fresh
  /// (ephemeral contexts), then performs the process-first purge and the
  /// additive restore of the context's own cookies.
  Future<void> _ensureLoaded(_ContextSlot slot, String? sessionId) async {
    if (slot.loaded) return;
    slot.loaded = true;
    if (slot.ephemeral) {
      slot.state = BrowserState();
    } else {
      slot.sessionId = sessionId;
      slot.state = await store.load(sessionId);
    }
    // Process-first purge: leftovers from previous app runs (the WebView
    // profile outlives the process) must not leak into any context. Only
    // safe when this is the only live operation — with parallel contexts
    // the jar is already shared by design. v1.38.0: when the first
    // activity is a parallel fan (every op sees _opsInFlight > 1), the
    // purge is DEFERRED and retried at the moment the process goes fully
    // idle instead of being skipped for the whole app run.
    if (!_purgedOnce) {
      final bool otherBusy = _slots.values.any(
        (_ContextSlot s) => !identical(s, slot) && (s.inOp || s.pendingOps > 0),
      );
      if (_opsInFlight <= 1 && !otherBusy) {
        _purgedOnce = true;
        _purgePending = false;
        try {
          await cookies.clearAll();
        } catch (_) {
          // Best effort.
        }
        try {
          await slot.inner.purgeSiteData();
        } catch (_) {
          // Best effort.
        }
      } else {
        _purgePending = true;
      }
    }
    // Restore this context's own cookies additively (never a wholesale
    // clear — concurrent contexts share the jar by design).
    for (final MapEntry<String, OriginState> entry
        in slot.state.origins.entries) {
      final OriginState o = entry.value;
      if (o.cookies.isEmpty) continue;
      final String url = o.lastUrl.isNotEmpty ? o.lastUrl : entry.key;
      try {
        await cookies.writeForUrl(url, o.cookies);
      } catch (_) {
        // Best effort.
      }
    }
  }

  /// Before the first visit of [origin] in [slot]: take other idle
  /// contexts' recorded cookie names for the origin off the shared jar and
  /// write this context's own snapshot. Contexts that are mid-op on the
  /// origin are left untouched (soft edge, see class doc).
  Future<void> _claimOrigin(_ContextSlot slot, String origin) async {
    final List<OriginState> leases = <OriginState>[];
    var busy = false;
    for (final _ContextSlot other in _slots.values) {
      if (identical(other, slot) || other.disposed) continue;
      final OriginState? o = other.state.origins[origin];
      if (o == null || o.cookies.isEmpty) continue;
      if (other.inOp) {
        busy = true;
        break;
      }
      leases.add(o);
    }
    if (!busy) {
      for (final OriginState lease in leases) {
        final String url = lease.lastUrl.isNotEmpty ? lease.lastUrl : origin;
        try {
          await cookies.deleteForUrl(url, names: lease.cookies.keys.toSet());
        } catch (_) {
          // Best effort.
        }
      }
    }
    final OriginState? own = slot.state.origins[origin];
    if (own != null && own.cookies.isNotEmpty) {
      final String url = own.lastUrl.isNotEmpty ? own.lastUrl : origin;
      try {
        await cookies.writeForUrl(url, own.cookies);
      } catch (_) {
        // Best effort.
      }
    }
  }

  Future<void> _reconcileStorage(_ContextSlot slot, String origin) async {
    final OriginState? o = slot.state.origins[origin];
    final payload = jsonEncode(<String, dynamic>{
      'local': o?.localStorage ?? const <String, String>{},
      'session': o?.sessionStorage ?? const <String, String>{},
    });
    await slot.inner.reconcileOriginStorage(payload);
  }

  /// Snapshots the context's current page (cookies + web storage) into its
  /// own state; chat-session contexts persist it into their sandbox.
  Future<void> _capture(_ContextSlot slot) async {
    final BrowserState state = slot.state;
    final raw = await slot.inner.runJs(IsolatedBrowserAutomation.captureJs);
    final data = _decodeMap(raw);
    if (data == null) {
      await _persist(slot, state);
      return;
    }
    final href = data['href']?.toString() ?? '';
    final origin = _originOf(href);
    if (origin == null) {
      await _persist(slot, state);
      return;
    }
    final o = state.origins.putIfAbsent(
      origin,
      () => OriginState(lastUrl: href),
    );
    o.lastUrl = href;
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
    await _persist(slot, state);
  }

  Future<void> _persist(_ContextSlot slot, BrowserState state) async {
    if (slot.ephemeral || slot.sessionId == null) return;
    await store.save(slot.sessionId, state);
  }

  /// Disposes idle slots beyond [maxContexts] (LRU, ephemeral first).
  /// Disposed contexts' recorded cookie names leave the shared jar — an
  /// ephemeral subagent's login does not outlive its task.
  void _evictIdleSlots() {
    var excess = _slots.length - maxContexts;
    if (excess <= 0) return;
    final List<_ContextSlot> candidates =
        _slots.values
            .where(
              (_ContextSlot s) => !s.inOp && s.pendingOps <= 0 && !s.disposed,
            )
            .toList()
          ..sort((_ContextSlot a, _ContextSlot b) {
            if (a.ephemeral != b.ephemeral) return a.ephemeral ? -1 : 1;
            return a.lastUsed.compareTo(b.lastUsed);
          });
    for (final _ContextSlot victim in candidates) {
      if (excess <= 0) break;
      victim.disposed = true;
      _slots.remove(victim.key);
      excess--;
      // Async cleanup — eviction must not block the completing operation.
      Future<void>(() async {
        await _releaseCookies(victim);
        try {
          victim.inner.dispose();
        } catch (_) {
          // Best effort.
        }
      });
    }
  }

  Future<void> _releaseCookies(_ContextSlot slot) async {
    // v1.38.0: the eviction release runs async — if the same context key
    // was recreated in the meantime, the jar now holds the NEW context's
    // fresh cookies and deleting the victim's recorded names would log
    // the new context out on its very next op.
    if (_slots.containsKey(slot.key)) return;
    for (final MapEntry<String, OriginState> entry
        in slot.state.origins.entries) {
      final OriginState o = entry.value;
      if (o.cookies.isEmpty) continue;
      var busy = false;
      for (final _ContextSlot other in _slots.values) {
        if (other.disposed) continue;
        final OriginState? oo = other.state.origins[entry.key];
        if (oo != null && oo.cookies.isNotEmpty && other.inOp) {
          busy = true;
          break;
        }
      }
      if (busy) continue;
      final String url = o.lastUrl.isNotEmpty ? o.lastUrl : entry.key;
      try {
        await cookies.deleteForUrl(url, names: o.cookies.keys.toSet());
      } catch (_) {
        // Best effort.
      }
    }
  }

  static Map<String, dynamic>? _decodeMap(Object? raw) {
    Object? current = raw;
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

/// A [BrowserAutomation] view pinned to ONE named context of a
/// [ContextualBrowserAutomation] — what the executor hands to a subagent
/// so its browser tools run in its own engine without touching the
/// parent's or sibling contexts.
class _PinnedContextAutomation implements BrowserAutomation {
  _PinnedContextAutomation(this._manager, this._contextId);

  final ContextualBrowserAutomation _manager;
  final String _contextId;

  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    String? sessionId,
  }) => _manager._navigate(
    url,
    timeout: timeout,
    sessionId: sessionId,
    contextId: _contextId,
  );

  @override
  Future<Map<String, dynamic>> click({
    String? selector,
    String? text,
    String? sessionId,
  }) => _manager._click(
    selector: selector,
    text: text,
    sessionId: sessionId,
    contextId: _contextId,
  );

  @override
  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear = true,
    String? sessionId,
  }) => _manager._type(
    text,
    selector: selector,
    clear: clear,
    sessionId: sessionId,
    contextId: _contextId,
  );

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
    String? sessionId,
  }) => _manager._scroll(
    direction: direction,
    amount: amount,
    sessionId: sessionId,
    contextId: _contextId,
  );

  @override
  Future<String?> screenshot({required String saveDir, String? sessionId}) =>
      _manager._run<String?>(
        _contextId,
        sessionId: sessionId,
        op: (_ContextSlot slot) =>
            slot.inner.screenshot(saveDir: saveDir, sessionId: null),
      );

  @override
  Future<String> extractText({int maxLength = 8000, String? sessionId}) =>
      _manager._run<String>(
        _contextId,
        sessionId: sessionId,
        op: (_ContextSlot slot) => slot.inner.extractText(maxLength: maxLength),
      );

  @override
  Future<String> runJs(String code, {String? sessionId}) =>
      _manager._run<String>(
        _contextId,
        sessionId: sessionId,
        op: (_ContextSlot slot) async {
          final String result = await slot.inner.runJs(code);
          await _manager._capture(slot);
          return result;
        },
      );

  @override
  Future<void> purgeSiteData() => _manager._run<void>(
    _contextId,
    op: (_ContextSlot slot) => slot.inner.purgeSiteData(),
  );

  @override
  Future<String> reconcileOriginStorage(String payloadJson) =>
      _manager._run<String>(
        _contextId,
        op: (_ContextSlot slot) =>
            slot.inner.reconcileOriginStorage(payloadJson),
      );

  @override
  Future<void> resetSession() => _manager._run<void>(
    _contextId,
    op: (_ContextSlot slot) => slot.inner.resetSession(),
  );

  @override
  BrowserAutomation withContext(String contextId) =>
      _manager.withContext(contextId);

  @override
  void dispose() => _manager.dispose();
}
