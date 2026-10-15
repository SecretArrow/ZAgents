import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/browser_automation.dart';
import 'package:zagents/services/browser_session_isolation.dart';

/// Cookie jar fake recording every mutation so tests can assert exactly
/// when the shared jar is cleared and whose cookies are restored.
class _FakeCookies implements CookieGateway {
  final Map<String, Map<String, String>> jar = <String, Map<String, String>>{};
  int clearCalls = 0;
  final List<String> writes = <String>[];

  @override
  Future<Map<String, String>> readForUrl(String url) async =>
      Map<String, String>.of(jar[url] ?? const <String, String>{});

  @override
  Future<void> clearAll() async {
    clearCalls++;
    jar.clear();
  }

  @override
  Future<void> writeForUrl(String url, Map<String, String> cookies) async {
    writes.add('$url <- $cookies');
    final bucket = jar.putIfAbsent(url, () => <String, String>{});
    bucket.addAll(cookies);
  }
}

/// Inner automation fake: records calls, answers the snapshot JS with a
/// canned page description, and lets tests simulate "the site set a
/// cookie" by writing to the gateway from within navigate.
class _FakeInner implements BrowserAutomation {
  _FakeInner();

  final List<String> calls = <String>[];
  String pageUrl = 'about:blank';

  /// Gateway the "site" writes cookies to during page load (simulates
  /// Set-Cookie after activation cleared the shared jar).
  CookieGateway? site;
  Map<String, String> siteCookies = const <String, String>{};

  /// JSON payload answered for the capture script (href/cookie/storage).
  /// `href` defaults to the current [pageUrl] like a real page would.
  Map<String, dynamic> capture = <String, dynamic>{};

  /// Runs when any other JS (e.g. agent-provided) executes.
  Object? Function(String code)? onOtherJs;

  bool _isCapture(String code) => code.contains('location.href');
  bool _isReconcile(String code) => code.contains('localStorage.clear()');

  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    String? sessionId,
  }) async {
    calls.add('navigate:$url');
    pageUrl = url;
    if (site != null && siteCookies.isNotEmpty) {
      await site!.writeForUrl(url, siteCookies);
    }
    return BrowserPageInfo(url: url, title: 'T', text: 'body');
  }

  @override
  Future<Map<String, dynamic>> click({
    String? selector,
    String? text,
    String? sessionId,
  }) async {
    calls.add('click:${text ?? selector}');
    return <String, dynamic>{'ok': true, 'clicked': text ?? selector ?? ''};
  }

  @override
  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear = true,
    String? sessionId,
  }) async {
    calls.add('type:$text');
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
    String? sessionId,
  }) async {
    calls.add('scroll');
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<String?> screenshot({
    required String saveDir,
    String? sessionId,
  }) async {
    calls.add('screenshot');
    return null;
  }

  @override
  Future<String> extractText({int maxLength = 8000, String? sessionId}) async {
    calls.add('extract');
    return 'body';
  }

  @override
  Future<String> runJs(String code, {String? sessionId}) async {
    if (_isCapture(code)) {
      calls.add('capture');
      final payload = <String, dynamic>{...capture};
      payload.putIfAbsent('href', () => pageUrl);
      return jsonEncode(payload);
    }
    if (_isReconcile(code)) {
      calls.add('reconcile:${code.substring(code.indexOf('(') + 1)}');
      return 'reconciled';
    }
    calls.add('js');
    final r = onOtherJs?.call(code);
    return r == null ? 'null' : jsonEncode(r);
  }

  @override
  Future<void> resetSession() async {}

  @override
  void dispose() {}
}

IsolatedBrowserAutomation _build(
  _FakeInner inner,
  _FakeCookies cookies,
  BrowserStateStore store,
) => IsolatedBrowserAutomation(inner: inner, store: store, cookies: cookies);

void main() {
  late Directory temp;
  late BrowserStateStore store;
  late _FakeCookies cookies;
  late _FakeInner inner;
  late IsolatedBrowserAutomation isolated;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('browser_iso_test');
    store = BrowserStateStore(
      rootFor: (String? sessionId) async {
        if (sessionId == null) return temp;
        return Directory('${temp.path}${Platform.pathSeparator}$sessionId');
      },
    );
    cookies = _FakeCookies();
    inner = _FakeInner();
    isolated = _build(inner, cookies, store);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Map<String, dynamic> pageJson({
    String href = 'https://a.test/home',
    String cookie = '',
    Map<String, String> local = const {},
    Map<String, String> session = const {},
  }) => <String, dynamic>{
    'href': href,
    'cookie': cookie,
    'local': local,
    'session': session,
  };

  group('BrowserStateStore', () {
    test('persists state per session inside its sandbox', () async {
      final state = BrowserState(
        origins: {
          'https://x.test': OriginState(
            lastUrl: 'https://x.test/app',
            cookies: {'sid': 'abc'},
            localStorage: {'jwt': 't'},
          ),
        },
      );
      await store.save('s1', state);
      final file = File(
        '${temp.path}${Platform.pathSeparator}s1${Platform.pathSeparator}'
        'browser_state.json',
      );
      expect(file.existsSync(), isTrue);
      final loaded = await store.load('s1');
      expect(loaded.origins['https://x.test']!.cookies['sid'], 'abc');
      expect(loaded.origins['https://x.test']!.localStorage['jwt'], 't');
      expect(loaded.origins['https://x.test']!.lastUrl, 'https://x.test/app');
    });

    test('sessions are independent buckets', () async {
      await store.save(
        's1',
        BrowserState(
          origins: {
            'https://x.test': OriginState(
              lastUrl: 'https://x.test/',
              cookies: {'sid': 'A'},
            ),
          },
        ),
      );
      final other = await store.load('s2');
      expect(other.origins, isEmpty);
    });

    test('corrupt file degrades to fresh state', () async {
      final dir = Directory('${temp.path}${Platform.pathSeparator}bad');
      dir.createSync(recursive: true);
      File('${dir.path}${Platform.pathSeparator}browser_state.json')
          .writeAsStringSync('{not json');
      final loaded = await store.load('bad');
      expect(loaded.origins, isEmpty);
    });

    test('clear removes the persisted snapshot', () async {
      await store.save(
        's1',
        BrowserState(
          origins: {
            'https://x.test': OriginState(
              lastUrl: 'https://x.test/',
              cookies: {'sid': 'A'},
            ),
          },
        ),
      );
      await store.clear('s1');
      expect((await store.load('s1')).origins, isEmpty);
    });
  });

  group('IsolatedBrowserAutomation', () {
    test('captures cookies and web storage into the session sandbox', () async {
      // The site sets cookies while the page loads (after activation has
      // cleared the shared jar) and document.cookie exposes two of them.
      inner.site = cookies;
      inner.siteCookies = <String, String>{'httponly': 'yes'};
      inner.capture = pageJson(
        cookie: 'sid=doc; theme=dark',
        local: {'k': 'v'},
      );
      await isolated.navigate('https://a.test/home', sessionId: 's1');

      final state = await store.load('s1');
      final o = state.origins['https://a.test']!;
      expect(o.cookies['sid'], 'doc');
      expect(o.cookies['theme'], 'dark');
      // Manager jar (would include httpOnly) merged with document.cookie.
      expect(o.cookies['httponly'], 'yes');
      expect(o.localStorage['k'], 'v');
      expect(o.lastUrl, 'https://a.test/home');
    });

    test(
      'switching sessions clears the jar and restores only the target',
      () async {
        // Session A logs in: the site sets its cookie during page load.
        inner.site = cookies;
        inner.siteCookies = <String, String>{'sid': 'A-token'};
        inner.capture = pageJson();
        await isolated.navigate('https://a.test/home', sessionId: 'sA');
        expect(cookies.jar['https://a.test/home']!['sid'], 'A-token');

        // Session B owns a different login.
        await store.save(
          'sB',
          BrowserState(
            origins: {
              'https://b.test': OriginState(
                lastUrl: 'https://b.test/app',
                cookies: {'sid': 'B-token'},
              ),
            },
          ),
        );

        inner.siteCookies = const <String, String>{};
        inner.capture = pageJson(href: 'https://b.test/app');
        await isolated.extractText(sessionId: 'sB');

        // The shared jar was cleared then restored with B's identity only.
        expect(
          cookies.jar['https://a.test/home']?.containsKey('sid') ?? false,
          isFalse,
        );
        expect(cookies.jar['https://b.test/app']!['sid'], 'B-token');
        // A's snapshot is intact in its own sandbox.
        final a = await store.load('sA');
        expect(a.origins['https://a.test']!.cookies['sid'], 'A-token');
      },
    );

    test('same session reuse does not churn the shared jar', () async {
      inner.capture = pageJson();
      await isolated.navigate('https://a.test/', sessionId: 's1');
      final clearsAfterFirst = cookies.clearCalls;
      await isolated.navigate('https://a.test/other', sessionId: 's1');
      expect(cookies.clearCalls, clearsAfterFirst);
    });

    test(
      'first visit of an origin reloads once to apply stored web storage',
      () async {
        await store.save(
          's1',
          BrowserState(
            origins: {
              'https://s.test': OriginState(
                lastUrl: 'https://s.test/p',
                localStorage: {'jwt': 'abc'},
              ),
            },
          ),
        );
        inner.capture = pageJson(href: 'https://s.test/p');
        await isolated.navigate('https://s.test/p', sessionId: 's1');

        expect(
          inner.calls.where((c) => c.startsWith('navigate:')).length,
          2,
          reason: 'initial load + reload after storage reconcile',
        );
        final reconcile = inner.calls
            .firstWhere((c) => c.startsWith('reconcile:'))
            .substring('reconcile:'.length);
        expect(reconcile, contains('"jwt"'));
        expect(reconcile, contains('"abc"'));
      },
    );

    test(
      'first visit for a fresh session wipes leftovers from other chats',
      () async {
        // Chat A leaves storage behind on the shared origin.
        inner.capture = pageJson(
          href: 'https://shared.test/app',
          local: {'a': 'leak'},
        );
        await isolated.navigate('https://shared.test/app', sessionId: 'sA');

        // Chat B opens the same origin: its snapshot must be empty.
        inner.capture = pageJson(href: 'https://shared.test/app', local: {});
        await isolated.navigate('https://shared.test/app', sessionId: 'sB');

        final reconcile = inner.calls.lastWhere(
          (c) => c.startsWith('reconcile:'),
        );
        expect(reconcile.contains('"leak"'), isFalse);
        final b = await store.load('sB');
        expect(
          b.origins['https://shared.test']!.localStorage.containsKey('a'),
          isFalse,
        );
      },
    );

    test('storage reconcile runs once per origin per activation', () async {
      inner.capture = pageJson(href: 'https://s.test/p');
      await isolated.navigate('https://s.test/p', sessionId: 's1');
      final reconcilesAfterFirst = inner.calls
          .where((c) => c.startsWith('reconcile:'))
          .length;
      await isolated.click(text: 'btn', sessionId: 's1');
      await isolated.navigate('https://s.test/p2', sessionId: 's1');
      expect(
        inner.calls.where((c) => c.startsWith('reconcile:')).length,
        reconcilesAfterFirst,
      );
    });

    test(
      'parallel operations from different sessions never interleave',
      () async {
        // Two operations racing: each must run as one atomic block and
        // capture its own origin state (the fake's default href follows the
        // last loaded page, so each session snapshots its own origin).
        final t1 = isolated.navigate('https://a.test/', sessionId: 'sA');
        final t2 = isolated.navigate('https://b.test/', sessionId: 'sB');
        await Future.wait(<Future<void>>[t1, t2]);

        final a = await store.load('sA');
        final b = await store.load('sB');
        expect(a.origins.containsKey('https://a.test'), isTrue);
        expect(b.origins.containsKey('https://b.test'), isTrue);
        expect(a.origins.containsKey('https://b.test'), isFalse);
        expect(b.origins.containsKey('https://a.test'), isFalse);
      },
    );

    test('capture skips non-web pages (about:blank) without crash', () async {
      inner.capture = <String, dynamic>{'href': 'about:blank'};
      await isolated.navigate('about:blank', sessionId: 's1');
      final state = await store.load('s1');
      expect(state.origins, isEmpty);
    });

    test('screenshot and runJs stay scoped to the calling session', () async {
      inner.capture = pageJson();
      await isolated.screenshot(saveDir: '/tmp/x', sessionId: 's1');
      expect(isolated.activeSessionId, 's1');
      await isolated.runJs('1+1', sessionId: 's2');
      expect(isolated.activeSessionId, 's2');
    });
  });
}
