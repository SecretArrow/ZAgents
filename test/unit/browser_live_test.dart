import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/browser_automation.dart';
import 'package:zagents/services/browser_live_engine.dart';
import 'package:zagents/services/browser_session_isolation.dart';

/// v1.54.0 (live browser) — the LIVE BROWSER core: a user-visible WebView
/// becomes the engine of a NAMED browser context ('live'), so the user and
/// the agent operate the SAME browser surface. These tests pin the
/// attach / re-attach / detach lifecycle of ContextualBrowserAutomation,
/// the LiveBrowserEngine control gate, and the named-context routing of
/// every interactive tool (click/type/scroll/screenshot/extract/runJs).

/// Cookie gateway double recording every mutation (mirrors
/// browser_contexts_test.dart).
class _Jar implements CookieGateway {
  final Map<String, Map<String, String>> jar = <String, Map<String, String>>{};
  int clearCalls = 0;

  @override
  Future<Map<String, String>> readForUrl(String url) async =>
      Map<String, String>.of(jar[url] ?? const <String, String>{});

  @override
  Future<void> clearAll() async {
    clearCalls++;
    jar.clear();
  }

  @override
  Future<void> writeForUrl(String url, Map<String, String> cookies) async =>
      jar.putIfAbsent(url, () => <String, String>{}).addAll(cookies);

  @override
  Future<void> deleteForUrl(String url, {Set<String>? names}) async {
    final Map<String, String>? bucket = jar[url];
    if (bucket == null) return;
    if (names == null) {
      jar.remove(url);
    } else {
      bucket.removeWhere((String name, _) => names.contains(name));
    }
  }
}

/// State shared by all engines of one manager under test.
class _Shared {
  final List<_FakeEngine> created = <_FakeEngine>[];
  late _Jar cookies;
}

/// Engine double usable as BOTH the manager's headless makeInner engine
/// ([headless] — recorded in [shared.created], one per revived slot) and
/// the EXTERNAL engine the Live Browser screen would attach (what the
/// user-visible webview wraps). Records every routed op and answers the
/// capture JS (IsolatedBrowserAutomation.captureJs shape) with the last
/// loaded page and this fake 'site's' cookies.
class _FakeEngine implements BrowserAutomation {
  _FakeEngine(this.shared, {bool headless = true}) {
    if (headless) shared.created.add(this);
  }

  final _Shared shared;
  final List<String> calls = <String>[];
  bool disposed = false;
  String pageUrl = 'about:blank';

  /// Site cookies written into the shared jar when a page loads.
  Map<String, String> siteCookies = const <String, String>{};

  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    String? sessionId,
  }) async {
    calls.add('navigate:$url');
    pageUrl = url;
    if (siteCookies.isNotEmpty) {
      await shared.cookies.writeForUrl(url, siteCookies);
    }
    return BrowserPageInfo(url: url, title: 'Live', text: 'live body');
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
    return <String, dynamic>{'ok': true, 'typed': text};
  }

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
    String? sessionId,
  }) async {
    calls.add('scroll:$direction:$amount');
    return <String, dynamic>{'ok': true, 'scrollY': amount};
  }

  @override
  Future<String?> screenshot({
    required String saveDir,
    String? sessionId,
  }) async {
    calls.add('screenshot');
    return '$saveDir${Platform.pathSeparator}live.png';
  }

  @override
  Future<String> extractText({int maxLength = 8000, String? sessionId}) async {
    calls.add('extractText');
    return 'live page text';
  }

  @override
  Future<String> runJs(String code, {String? sessionId}) async {
    calls.add('runJs:$code');
    if (code.contains('location.href')) {
      return jsonEncode(<String, dynamic>{
        'href': pageUrl,
        'cookie': siteCookies.entries
            .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
            .join('; '),
        'local': <String, String>{},
        'session': <String, String>{},
      });
    }
    return 'null';
  }

  @override
  Future<void> purgeSiteData() async {
    calls.add('purge');
  }

  @override
  Future<String> reconcileOriginStorage(String payloadJson) async =>
      'reconciled';

  @override
  Future<void> resetSession() async {}

  @override
  BrowserAutomation withContext(String contextId) => this;

  @override
  void dispose() {
    disposed = true;
  }
}

/// Manager harness: temp-sandbox store + fake headless engines created by
/// the injected makeInner (their count proves headless revives) + the
/// manager's real registry.
class _Harness {
  _Harness(this.store) {
    shared.cookies = _Jar();
    manager = ContextualBrowserAutomation(
      makeInner: () => _FakeEngine(shared),
      store: store,
      cookies: shared.cookies,
      maxContexts: 4,
    );
  }

  final _Shared shared = _Shared();
  final BrowserStateStore store;
  late final ContextualBrowserAutomation manager;

  /// Headless engine created Nth (slot creation follows first use).
  _FakeEngine engine(int n) => shared.created[n];

  /// An EXTERNAL engine double — what the Live Browser screen attaches.
  _FakeEngine externalEngine({
    Map<String, String> siteCookies = const <String, String>{},
  }) => _FakeEngine(shared, headless: false)..siteCookies = siteCookies;
}

BrowserStateStore _store(Directory temp) => BrowserStateStore(
  rootFor: (String? sessionId) async {
    if (sessionId == null) return temp;
    return Directory('${temp.path}${Platform.pathSeparator}$sessionId');
  },
);

void main() {
  late Directory temp;
  late BrowserStateStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('browser_live_test');
    store = _store(temp);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  group('attachExternalContext', () {
    test(
      'registers a persistent live row and restores the hibernation file',
      () async {
        final _Harness h = _Harness(store);
        // A hibernation file left by a previous screen instance.
        await store.saveNamed(
          'chat-1',
          'live',
          BrowserState(
            origins: <String, OriginState>{
              'https://example.com': OriginState(
                lastUrl: 'https://example.com/home',
                cookies: <String, String>{'sid': 'old-login'},
              ),
            },
          ),
          createdAt: DateTime.utc(2024, 1, 1),
          lastUrl: 'https://example.com/home',
          originCount: 1,
        );
        final _FakeEngine ext = h.externalEngine();
        final Map<String, dynamic> info = await h.manager.attachExternalContext(
          name: 'live',
          sessionId: 'chat-1',
          engine: ext,
        );
        expect(info['name'], 'live');
        expect(info['persistent'], isTrue);
        expect(info['lastUrl'], 'https://example.com/home');
        expect(info['originCount'], 1);
        expect(
          h.manager.contextRegistry.isRegistered('nctx:chat-1:live'),
          isTrue,
        );

        // Ops route to the EXTERNAL engine — no headless engine boots.
        final BrowserPageInfo page = await h.manager.navigate(
          'https://example.com/page',
          sessionId: 'chat-1',
          contextName: 'live',
        );
        expect(page.error, isNull);
        expect(ext.calls, contains('navigate:https://example.com/page'));
        expect(h.shared.created, isEmpty);
        // The pre-applied state made the first op's _claimOrigin restore
        // the context's cookies into the shared jar.
        expect(
          h.shared.cookies.jar['https://example.com/home']!['sid'],
          'old-login',
        );
        h.manager.dispose();
      },
    );

    test('re-attach while alive hibernates the old slot, keeps ONE row, '
        'routes to the new engine', () async {
      final _Harness h = _Harness(store);
      final _FakeEngine a = h.externalEngine(
        siteCookies: <String, String>{'sid': 'A-login'},
      );
      await h.manager.attachExternalContext(
        name: 'live',
        sessionId: 'chat-1',
        engine: a,
      );
      await h.manager.navigate(
        'https://x.test/home',
        sessionId: 'chat-1',
        contextName: 'live',
      );

      final _FakeEngine b = h.externalEngine();
      final Map<String, dynamic> info = await h.manager.attachExternalContext(
        name: 'live',
        sessionId: 'chat-1',
        engine: b,
      );
      // Async teardown of the old slot — let it land.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(info['name'], 'live');
      expect(
        info['originCount'],
        1,
        reason: 'B\'s slot carries A\'s captured state',
      );
      expect(a.disposed, isTrue, reason: 'the old engine was dropped');
      // The hibernation file holds A's captured cookie.
      final NamedContextSnapshot? saved = await store.loadNamed(
        'chat-1',
        'live',
      );
      expect(saved, isNotNull);
      expect(saved!.state.origins['https://x.test']!.cookies['sid'], 'A-login');
      // The registry kept exactly ONE row (no double registration).
      expect(h.manager.contextRegistry.list('chat-1'), hasLength(1));

      // New ops route to B, never to A again.
      await h.manager.click(
        selector: 'a.next',
        sessionId: 'chat-1',
        contextName: 'live',
      );
      expect(b.calls, contains('click:a.next'));
      expect(a.calls, isNot(contains('click:a.next')));
      expect(h.shared.created, isEmpty);
      h.manager.dispose();
    });
  });

  group('detachExternalContext', () {
    test('captures state under the mutex, hibernates with the caller URL, '
        'keeps the row, and later ops revive headlessly', () async {
      final _Harness h = _Harness(store);
      final _FakeEngine ext = h.externalEngine(
        siteCookies: <String, String>{'sid': 'live-login'},
      );
      await h.manager.attachExternalContext(
        name: 'live',
        sessionId: 'chat-1',
        engine: ext,
      );
      await h.manager.navigate(
        'https://example.com/start',
        sessionId: 'chat-1',
        contextName: 'live',
      );

      // The user then browsed on to another page OUTSIDE engine ops —
      // detach is told the URL the visible webview is showing.
      final bool detached = await h.manager.detachExternalContext(
        name: 'live',
        sessionId: 'chat-1',
        lastUrl: 'https://example.com/page',
      );
      expect(detached, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ext.disposed, isFalse, reason: 'the widget owns the webview');

      // The hibernation file carries the caller-supplied lastUrl plus
      // the captured state.
      final NamedContextSnapshot? saved = await store.loadNamed(
        'chat-1',
        'live',
      );
      expect(saved, isNotNull);
      expect(saved!.lastUrl, 'https://example.com/page');
      expect(
        saved.state.origins['https://example.com']!.cookies['sid'],
        'live-login',
      );
      // The registry row SURVIVES (browser_context_list still shows it).
      expect(h.manager.contextRegistry.list('chat-1'), hasLength(1));
      // Nothing left to detach — the slot is gone.
      expect(
        await h.manager.detachExternalContext(
          name: 'live',
          sessionId: 'chat-1',
        ),
        isFalse,
      );

      // A later op revives the context HEADLESSLY: a fresh makeInner
      // engine boots (creation count proves it) and _ensureLoaded
      // restores the captured cookie into the shared jar — the revived
      // engine has NO site cookies of its own, only the restore can
      // supply 'sid'.
      expect(h.shared.created, isEmpty);
      await h.manager.navigate(
        'https://example.com/revive',
        sessionId: 'chat-1',
        contextName: 'live',
      );
      expect(h.shared.created, hasLength(1));
      expect(
        h.shared.cookies.jar['https://example.com/start']!['sid'],
        'live-login',
      );
      h.manager.dispose();
    });

    test('detach with no live slot or an unknown name returns false', () async {
      final _Harness h = _Harness(store);
      // Unknown name: nothing was ever registered.
      expect(
        await h.manager.detachExternalContext(
          name: 'ghost',
          sessionId: 'chat-1',
        ),
        isFalse,
      );
      // Registered but slotless: createContext boots slots lazily.
      await h.manager.createContext('live', sessionId: 'chat-1');
      expect(
        await h.manager.detachExternalContext(
          name: 'live',
          sessionId: 'chat-1',
        ),
        isFalse,
      );
      // Another chat's name is a different key entirely.
      expect(
        await h.manager.detachExternalContext(
          name: 'live',
          sessionId: 'chat-2',
        ),
        isFalse,
      );
      h.manager.dispose();
    });

    test(
      'user-mode close still records the page — the gated capture falls '
      'back to the shared jar (v1.54.0 fix)',
      () async {
        final _Harness h = _Harness(store);
        // A real LiveBrowserEngine with the control gate SHUT (user
        // mode): its interactive ops — including the capture JS — answer
        // the refusal, exactly like on a device where the user holds
        // control while closing the screen.
        final LiveBrowserEngine gated = LiveBrowserEngine(
          control: () => true,
          controller: () async {
            throw StateError('the webview is gone');
          },
        );
        await h.manager.attachExternalContext(
          name: 'live',
          sessionId: 'chat-1',
          engine: gated,
        );
        // The user browsed manually: the visible webview left fresh
        // login cookies in the (process-global) jar for this page.
        await h.shared.cookies.writeForUrl(
          'https://example.com/profile',
          <String, String>{'session': 'fresh-login'},
        );
        final bool detached = await h.manager.detachExternalContext(
          name: 'live',
          sessionId: 'chat-1',
          lastUrl: 'https://example.com/profile',
        );
        expect(detached, isTrue);
        final NamedContextSnapshot? saved = await store.loadNamed(
          'chat-1',
          'live',
        );
        expect(saved, isNotNull);
        expect(saved!.lastUrl, 'https://example.com/profile');
        final OriginState? o = saved.state.origins['https://example.com'];
        expect(o, isNotNull, reason: 'the fallback must record the origin');
        expect(o!.lastUrl, 'https://example.com/profile');
        expect(
          o.cookies['session'],
          'fresh-login',
          reason: 'jar cookies survive the gated capture',
        );
        h.manager.dispose();
      },
    );
  });

  group('LiveBrowserEngine control gate', () {
    test(
      'all 7 interactive ops refuse while the user holds control, then '
      'delegate once control flips back',
      () async {
        // A controller source that errors immediately when FIRST touched.
        // Built lazily on purpose: an eagerly-completed erroring future
        // would surface as an unhandled async error during the gated
        // phase below, when nobody has listened to it yet.
        Future<InAppWebViewController> deadController() =>
            Future<InAppWebViewController>.error(
              StateError('the webview is gone'),
            );
        bool userHolds = true;
        final LiveBrowserEngine engine = LiveBrowserEngine(
          control: () => userHolds,
          controller: deadController,
        );

      // Gated: every op answers its standard failure shape without
      // ever touching the controller.
      final BrowserPageInfo nav = await engine.navigate('https://x.test/');
      expect(nav.error, contains('user is driving'));
      final Map<String, dynamic> click = await engine.click(selector: 'a');
      expect(click['ok'], isFalse);
      expect(click['error'], contains('user is driving'));
      final Map<String, dynamic> type = await engine.type('hello');
      expect(type['ok'], isFalse);
      expect(type['error'], contains('user is driving'));
      final Map<String, dynamic> scroll = await engine.scroll();
      expect(scroll['ok'], isFalse);
      expect(scroll['error'], contains('user is driving'));
      expect(await engine.screenshot(saveDir: temp.path), isNull);
      expect(await engine.extractText(), contains('user is driving'));
      expect(await engine.runJs('1+1'), contains('user is driving'));

      // Control flips back: navigate now delegates PAST the gate — the
      // errored controller future surfaces as the usual navigation
      // failure, proving super.navigate ran.
      userHolds = false;
      final BrowserPageInfo delegated = await engine.navigate(
        'https://x.test/',
      );
      expect(delegated.error, contains('Navigation failed'));
      engine.dispose();
    });
  });

  group('named-context routing for every tool', () {
    test('click/type/scroll/screenshot/extractText/runJs reach the external '
        'slot\'s engine', () async {
      final _Harness h = _Harness(store);
      final _FakeEngine ext = h.externalEngine();
      await h.manager.attachExternalContext(
        name: 'live',
        sessionId: 'chat-1',
        engine: ext,
      );
      await h.manager.click(
        selector: 'a.next',
        sessionId: 'chat-1',
        contextName: 'live',
      );
      expect(ext.calls, contains('click:a.next'));
      await h.manager.type(
        'hello',
        selector: 'input',
        sessionId: 'chat-1',
        contextName: 'live',
      );
      expect(ext.calls, contains('type:hello'));
      await h.manager.scroll(
        direction: 'up',
        amount: 300,
        sessionId: 'chat-1',
        contextName: 'live',
      );
      expect(ext.calls, contains('scroll:up:300'));
      await h.manager.screenshot(
        saveDir: temp.path,
        sessionId: 'chat-1',
        contextName: 'live',
      );
      expect(ext.calls, contains('screenshot'));
      await h.manager.extractText(sessionId: 'chat-1', contextName: 'live');
      expect(ext.calls, contains('extractText'));
      await h.manager.runJs('2+2', sessionId: 'chat-1', contextName: 'live');
      expect(ext.calls, contains('runJs:2+2'));
      // Everything ran on the EXTERNAL engine — no headless boot.
      expect(h.shared.created, isEmpty);
      h.manager.dispose();
    });

    test(
      'unknown, foreign and anonymous context names are ArgumentErrors',
      () async {
        final _Harness h = _Harness(store);
        final _FakeEngine ext = h.externalEngine();
        await h.manager.attachExternalContext(
          name: 'live',
          sessionId: 'chat-1',
          engine: ext,
        );
        await expectLater(
          h.manager.click(
            selector: 'a',
            sessionId: 'chat-1',
            contextName: 'ghost',
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.message,
              'message',
              'no such browser context: ghost',
            ),
          ),
        );
        for (final Future<void> call in <Future<void>>[
          h.manager.type('x', sessionId: 'chat-1', contextName: 'ghost'),
          h.manager.scroll(sessionId: 'chat-1', contextName: 'ghost'),
          h.manager.screenshot(
            saveDir: temp.path,
            sessionId: 'chat-1',
            contextName: 'ghost',
          ),
          h.manager.extractText(sessionId: 'chat-1', contextName: 'ghost'),
          h.manager.runJs('1', sessionId: 'chat-1', contextName: 'ghost'),
          // Same name but a DIFFERENT chat: keys are per-session.
          h.manager.click(
            selector: 'a',
            sessionId: 'chat-2',
            contextName: 'live',
          ),
          // Named routing without the owning session is rejected instead
          // of leaking into the legacy slot.
          h.manager.click(selector: 'a', contextName: 'live'),
        ]) {
          await expectLater(call, throwsArgumentError);
        }
        expect(h.shared.created, isEmpty, reason: 'no engine was booted');
        h.manager.dispose();
      },
    );
  });
}
