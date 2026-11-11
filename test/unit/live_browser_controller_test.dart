import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/l10n/app_strings_es.dart';
import 'package:zagents/services/agent_controller.dart'
    show ChatController, ChatState;
import 'package:zagents/services/browser_automation.dart';
import 'package:zagents/services/browser_live_engine.dart';
import 'package:zagents/services/browser_session_isolation.dart';
import 'package:zagents/services/live_browser_controller.dart';
import 'package:zagents/services/settings_repository.dart';

import '../support/test_doubles.dart';

/// No-op cookie gateway for the recording automation below (its attach /
/// detach are overridden, so the jar is never touched anyway).
class _NoopCookieGateway implements CookieGateway {
  const _NoopCookieGateway();

  @override
  Future<Map<String, String>> readForUrl(String url) async =>
      const <String, String>{};

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> writeForUrl(String url, Map<String, String> cookies) async {}

  @override
  Future<void> deleteForUrl(String url, {Set<String>? names}) async {}
}

/// Recording stand-in for the multi-context engine: the REAL
/// [ContextualBrowserAutomation] constructor (fake inner engines + a
/// temp-dir store + a no-op cookie gateway) with the v1.54.0 external
/// attach/detach surface overridden to record the service's calls and
/// reply with a scriptable info map.
class _RecordingContextualAutomation extends ContextualBrowserAutomation {
  _RecordingContextualAutomation(Directory dir)
    : super(
        makeInner: () => ScriptedBrowserAutomation(
          '${dir.path}${Platform.pathSeparator}shots',
          writeScreenshot: false,
        ),
        store: BrowserStateStore(
          rootFor: (String? sessionId) async => dir,
        ),
        cookies: const _NoopCookieGateway(),
      );

  final List<String> attachNames = <String>[];
  final List<String> attachSessions = <String>[];
  final List<BrowserAutomation> attachEngines = <BrowserAutomation>[];
  final List<String> detachNames = <String>[];
  final List<String> detachSessions = <String>[];
  final List<String?> detachLastUrls = <String?>[];

  /// What attachExternalContext reports (same shape as
  /// browser_context_list rows).
  Map<String, dynamic> info = <String, dynamic>{
    'name': 'live',
    'label': 'live',
    'persistent': true,
    'lastUrl': '',
    'lastUsedAt': '',
    'originCount': 0,
  };

  /// When set, attachExternalContext throws this instead of replying.
  Object? attachFailure;

  @override
  Future<Map<String, dynamic>> attachExternalContext({
    required String name,
    required String sessionId,
    required BrowserAutomation engine,
  }) async {
    attachNames.add(name);
    attachSessions.add(sessionId);
    attachEngines.add(engine);
    if (attachFailure != null) throw attachFailure!;
    return Map<String, dynamic>.of(info);
  }

  @override
  Future<bool> detachExternalContext({
    required String name,
    required String sessionId,
    String? lastUrl,
  }) async {
    detachNames.add(name);
    detachSessions.add(sessionId);
    detachLastUrls.add(lastUrl);
    return true;
  }
}

/// Stub chat controller: canned [ChatController.sendToSession] refusals
/// plus a recorder of the handover messages (same override trick as
/// plan_progress_test's parked controller).
class _StubChatController extends ChatController {
  String? refusal;
  final List<String?> sentTo = <String?>[];
  final List<String> sentTexts = <String>[];

  @override
  ChatState build() => const ChatState();

  @override
  Future<String?> sendToSession(String? targetSessionId, String text) async {
    sentTo.add(targetSessionId);
    sentTexts.add(text);
    return refusal;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('live_browser_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ProviderContainer container(
    _RecordingContextualAutomation automation, {
    _StubChatController? chat,
  }) {
    // Minimal harness: the service only ever reads the settings
    // repository (UA + language resolution), the browser automation and
    // — in the handover path — the chat controller (stubbed here).
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(
          MemorySettingsRepository(),
        ),
        browserAutomationProvider.overrideWithValue(automation),
        if (chat != null) chatControllerProvider.overrideWith(() => chat),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('attach', () {
    test('registers the visible engine as the live context and restores '
        'the hibernated lastUrl', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir)
            ..info = <String, dynamic>{
              'name': 'live',
              'label': 'live',
              'persistent': true,
              'lastUrl': 'https://example.com/start',
              'lastUsedAt': '',
              'originCount': 2,
            };
      final ProviderContainer c = container(automation);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );

      await controller.attach('sess-1');

      final LiveBrowserState state = c.read(liveBrowserProvider);
      expect(state.attached, isTrue);
      expect(state.sessionId, 'sess-1');
      expect(state.initialUrl, 'https://example.com/start');
      expect(state.attachError, isEmpty);
      // The engine handed to the contextual manager is the LIVE one, wired
      // to this controller's controller seam + UA resolver.
      expect(automation.attachNames, <String>['live']);
      expect(automation.attachSessions, <String>['sess-1']);
      expect(automation.attachEngines.single, isA<LiveBrowserEngine>());
    });

    test('a non-http lastUrl degrades to a blank first load', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir)
            ..info = <String, dynamic>{
              'name': 'live',
              'persistent': true,
              'lastUrl': 'about:blank',
              'lastUsedAt': '',
              'originCount': 0,
            };
      final ProviderContainer c = container(automation);
      await c.read(liveBrowserProvider.notifier).attach('sess-1');

      expect(c.read(liveBrowserProvider).initialUrl, isEmpty);
    });

    test('a failed attach lands in attachError and never throws', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir)
            ..attachFailure = StateError('engine unavailable');
      final ProviderContainer c = container(automation);

      await c.read(liveBrowserProvider.notifier).attach('sess-1');

      final LiveBrowserState state = c.read(liveBrowserProvider);
      expect(state.attached, isFalse);
      expect(state.attachError, contains('live browser attach failed'));
      expect(state.attachError, contains('engine unavailable'));
    });

    test('a non-contextual automation is refused with a clear error',
        () async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(
            MemorySettingsRepository(),
          ),
          browserAutomationProvider.overrideWithValue(
            ScriptedBrowserAutomation(tempDir.path, writeScreenshot: false),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c.read(liveBrowserProvider.notifier).attach('sess-1');

      expect(
        c.read(liveBrowserProvider).attachError,
        'live browser needs the multi-context engine',
      );
    });
  });

  group('mode + control gate', () {
    test('user mode is the default: agent ops on the live engine are '
        'refused before the controller is touched', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir);
      final ProviderContainer c = container(automation);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );
      await controller.attach('sess-1');

      expect(c.read(liveBrowserProvider).mode, LiveBrowserMode.user);
      final LiveBrowserEngine engine =
          automation.attachEngines.single as LiveBrowserEngine;
      final BrowserPageInfo refused = await engine.navigate(
        'https://x.test/',
      );
      expect(refused.error, contains('user is driving'));
    });

    test('setMode flips the gate: agent-mode ops proceed to the controller '
        'seam instead of the user-driving refusal', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir);
      final ProviderContainer c = container(automation);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );
      await controller.attach('sess-1');
      final LiveBrowserEngine engine =
          automation.attachEngines.single as LiveBrowserEngine;

      controller.setMode(LiveBrowserMode.agent);
      expect(c.read(liveBrowserProvider).mode, LiveBrowserMode.agent);

      // No WebView exists in the unit-test zone, so the agent-mode op parks
      // on the controller seam. detach must break it loose (fail fast) and
      // the outcome must NOT be the user-driving refusal — the gate read
      // the flipped state live.
      final Future<BrowserPageInfo> guarded = engine
          .navigate('https://y.test/')
          .catchError((Object e) {
            return BrowserPageInfo(
              url: 'https://y.test/',
              title: '',
              text: '',
              error: e.toString(),
            );
          });
      await controller.detach('https://y.test/now');
      final BrowserPageInfo outcome = await guarded.timeout(
        const Duration(seconds: 2),
      );
      expect(outcome.error ?? '', isNot(contains('user is driving')));
    });
  });

  group('detach', () {
    test('hands the current URL to the contextual engine and resets the '
        'state', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir);
      final ProviderContainer c = container(automation);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );
      await controller.attach('sess-1');

      await controller.detach('https://example.com/page');

      expect(automation.detachNames, <String>['live']);
      expect(automation.detachSessions, <String>['sess-1']);
      expect(automation.detachLastUrls, <String?>['https://example.com/page']);
      final LiveBrowserState state = c.read(liveBrowserProvider);
      expect(state.attached, isFalse);
      expect(state.sessionId, isNull);
    });

    test('a blank current URL is reported as null (nothing to restore)',
        () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir);
      final ProviderContainer c = container(automation);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );
      await controller.attach('sess-1');

      await controller.detach('   ');

      expect(automation.detachLastUrls, <String?>[null]);
    });

    test('a never-created controller seam is errored so straggler ops '
        'fail fast instead of hanging', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir);
      final ProviderContainer c = container(automation);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );
      await controller.attach('sess-1');

      final seam = controller.debugControllerFuture;
      expect(seam, isNotNull);
      // Attach the listener BEFORE the detach so the errored seam is
      // never an unhandled async error (the service attaches its own
      // .ignore() listener; this one asserts the straggler outcome).
      final Future<Object?> outcome = seam!.then(
        (Object? controller) => controller,
        onError: (Object e) => e,
      );

      await controller.detach('');

      expect(await outcome, isA<StateError>());
    });

    test('is idempotent: a second back press records nothing extra',
        () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir);
      final ProviderContainer c = container(automation);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );
      await controller.attach('sess-1');

      await controller.detach('https://a.test/');
      await controller.detach('https://a.test/');

      expect(automation.detachNames, hasLength(1));
    });
  });

  group('handToAgent', () {
    test('buildLiveHandoverMessage carries the page, the context "live" '
        'instruction and the prompt', () {
      final String message = LiveBrowserController.buildLiveHandoverMessage(
        'https://x.test/p',
        'X Test',
        'click login',
      );
      expect(message, startsWith('[live browser | X Test]'));
      expect(message, contains('Page: https://x.test/p'));
      expect(message, contains('context: "live"'));
      expect(message, endsWith('click login'));
      // ≤4 instruction lines before the prompt (3 lines + blank separator).
      expect(message.split('\n'), hasLength(5));

      // An empty title falls back to the URL.
      final String untitled = LiveBrowserController.buildLiveHandoverMessage(
        'https://x.test/p',
        '',
        'go',
      );
      expect(untitled, startsWith('[live browser | https://x.test/p]'));
    });

    test('sends the built message to the owning session and maps the '
        'refusal onto the localized busy message', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir);
      final _StubChatController chat = _StubChatController()
        ..refusal = 'chat busy';
      final ProviderContainer c = container(automation, chat: chat);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );
      await controller.attach('sess-9');

      final String? refusal = await controller.handToAgent(
        'do it',
        url: 'https://x.test/p',
        title: 'X Test',
      );

      expect(
        refusal,
        'That chat is busy right now — try again in a moment.',
      );
      expect(chat.sentTo, <String?>['sess-9']);
      expect(chat.sentTexts.single, startsWith('[live browser | X Test]'));
      expect(chat.sentTexts.single, contains('context: "live"'));
      expect(chat.sentTexts.single, endsWith('do it'));
    });

    test('returns null on success', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir);
      final _StubChatController chat = _StubChatController();
      final ProviderContainer c = container(automation, chat: chat);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );
      await controller.attach('sess-9');

      final String? refusal = await controller.handToAgent(
        'summarize this page',
        url: 'https://x.test/p',
        title: '',
      );

      expect(refusal, isNull);
      expect(chat.sentTexts.single, endsWith('summarize this page'));
    });

    test('an empty prompt never reaches the chat', () async {
      final _RecordingContextualAutomation automation =
          _RecordingContextualAutomation(tempDir);
      final _StubChatController chat = _StubChatController();
      final ProviderContainer c = container(automation, chat: chat);
      final LiveBrowserController controller = c.read(
        liveBrowserProvider.notifier,
      );
      await controller.attach('sess-9');

      final String? refusal = await controller.handToAgent(
        '   ',
        url: 'https://x.test/p',
        title: 'X',
      );

      expect(refusal, isNotNull);
      expect(chat.sentTexts, isEmpty);
    });

    test('every refusal reason maps onto its localized message', () {
      const AppStringsEn en = AppStringsEn();
      const AppStringsId id = AppStringsId();
      const AppStringsEs es = AppStringsEs();
      expect(
        LiveBrowserController.refusalMessage(en, 'chat busy'),
        en.liveBrowserRefusalBusy,
      );
      expect(
        LiveBrowserController.refusalMessage(en, 'missing API key'),
        en.liveBrowserRefusalNoKey,
      );
      expect(
        LiveBrowserController.refusalMessage(en, 'model not set'),
        en.liveBrowserRefusalNoModel,
      );
      expect(
        LiveBrowserController.refusalMessage(en, 'chat waiting for module '
            'setup'),
        en.liveBrowserRefusalSetup,
      );
      expect(
        LiveBrowserController.refusalMessage(en, 'chat not found'),
        en.liveBrowserRefusalNotFound,
      );
      expect(
        LiveBrowserController.refusalMessage(en, 'empty prompt'),
        en.liveBrowserRefusalGeneric,
      );
      expect(
        LiveBrowserController.refusalMessage(en, 'app shutting down'),
        en.liveBrowserRefusalGeneric,
      );
      // Unknown reasons keep the generic message + the raw detail.
      expect(
        LiveBrowserController.refusalMessage(en, 'weird failure'),
        '${en.liveBrowserRefusalGeneric} (weird failure)',
      );
      // And the mapping is bundle-aware (the service resolves the bundle
      // from the app language).
      expect(
        LiveBrowserController.refusalMessage(id, 'chat busy'),
        id.liveBrowserRefusalBusy,
      );
      expect(
        LiveBrowserController.refusalMessage(es, 'chat busy'),
        es.liveBrowserRefusalBusy,
      );
      expect(
        LiveBrowserController.refusalMessage(es, 'chat busy'),
        isNot(en.liveBrowserRefusalBusy),
      );
    });
  });
}
