import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/services/browser_automation.dart';
import 'package:zagents/services/browser_session_isolation.dart';
import 'package:zagents/services/live_browser_controller.dart';
import 'package:zagents/services/settings_repository.dart';
import 'package:zagents/ui/screens/browser_screen.dart';

import '../support/test_doubles.dart';

/// No-op cookie gateway for the recording automation (its attach/detach
/// are overridden — the jar is never touched).
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

/// Recording stand-in for the multi-context engine (real constructor with
/// fake inner engines + temp-dir store; the external attach/detach surface
/// is overridden to record the service's calls).
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
  final List<String> detachNames = <String>[];
  final List<String?> detachLastUrls = <String?>[];

  Map<String, dynamic> info = <String, dynamic>{
    'name': 'live',
    'label': 'live',
    'persistent': true,
    'lastUrl': 'https://restored.example/',
    'lastUsedAt': '',
    'originCount': 1,
  };

  Object? attachFailure;

  @override
  Future<Map<String, dynamic>> attachExternalContext({
    required String name,
    required String sessionId,
    required BrowserAutomation engine,
  }) async {
    attachNames.add(name);
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
    detachLastUrls.add(lastUrl);
    return true;
  }
}

/// Stub live-browser controller for the send-path tests: attach lands on a
/// fixed restored page (after a microtask, like the real async attach), the
/// handover is recorded, and [sendOutcome] decides the reported result.
class _StubLiveBrowserController extends LiveBrowserController {
  int attachCalls = 0;
  int detachCalls = 0;
  int sendCalls = 0;
  String? sendOutcome;
  String? lastPrompt;
  String? lastUrl;
  String? lastTitle;

  @override
  Future<void> attach(String sessionId) async {
    attachCalls++;
    // A microtask of delay mirrors the real async attach: the screen
    // builds the spinner first and the restored URL arrives as a state
    // CHANGE (the URL-bar mirror listens for exactly that).
    await Future<void>.delayed(Duration.zero);
    state = LiveBrowserState(
      attached: true,
      sessionId: sessionId,
      initialUrl: 'https://restored.example/',
    );
  }

  @override
  Future<void> detach(String currentUrl) async {
    detachCalls++;
    state = const LiveBrowserState();
  }

  @override
  Future<String?> handToAgent(
    String prompt, {
    required String url,
    required String title,
  }) async {
    sendCalls++;
    lastPrompt = prompt;
    lastUrl = url;
    lastTitle = title;
    return sendOutcome;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('browser_screen_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Pumps the Live Browser screen in PREVIEW mode (no platform WebView).
  /// Minimal harness — the screen's tree reads only the live provider;
  /// the real service controller additionally needs the settings
  /// repository (UA + language resolution) and the browser automation.
  /// [automation] drives the real service controller; [stub] replaces it
  /// entirely for the send-path tests.
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    _RecordingContextualAutomation? automation,
    _StubLiveBrowserController? stub,
  }) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(
            MemorySettingsRepository(),
          ),
          if (automation != null)
            browserAutomationProvider.overrideWithValue(automation),
          if (stub != null) liveBrowserProvider.overrideWith(() => stub),
        ],
        child: Builder(
          builder: (BuildContext context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                zLocalizationsDelegate,
              ],
              supportedLocales: const <Locale>[Locale('en'), Locale('id')],
              home: const LiveBrowserScreen(
                sessionId: 'sess-1',
                preview: true,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  TextEditingController urlField(WidgetTester tester) =>
      tester
          .widget<TextField>(find.byKey(const Key('live-browser-url')))
          .controller!;

  TextEditingController promptField(WidgetTester tester) =>
      tester
          .widget<TextField>(find.byKey(const Key('live-browser-prompt')))
          .controller!;

  testWidgets('renders the chrome, restores the last URL into the bar and '
      'starts in user mode (hint row, no prompt bar)', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpScreen(
      tester,
      automation: _RecordingContextualAutomation(tempDir),
    );

    expect(find.text(const AppStringsEn().liveBrowserTitle), findsOneWidget);
    expect(find.byKey(const Key('live-browser-url')), findsOneWidget);
    expect(find.byKey(const Key('live-browser-go')), findsOneWidget);
    expect(find.byKey(const Key('live-browser-mode-user')), findsOneWidget);
    expect(find.byKey(const Key('live-browser-mode-agent')), findsOneWidget);
    // The hibernated lastUrl became the first load and mirrors into the
    // URL bar.
    expect(urlField(tester).text, 'https://restored.example/');
    expect(
      container.read(liveBrowserProvider).initialUrl,
      'https://restored.example/',
    );
    // User mode by default: hint row present, prompt bar ABSENT, and the
    // preview placeholder (no platform WebView in tests).
    expect(find.byKey(const Key('live-browser-user-hint')), findsOneWidget);
    expect(find.text(const AppStringsEn().liveBrowserUserHint), findsOneWidget);
    expect(find.byKey(const Key('live-browser-prompt')), findsNothing);
    expect(find.byKey(const Key('live-browser-preview')), findsOneWidget);
  });

  testWidgets('switching to AI swaps the hint row for the prompt bar',
      (WidgetTester tester) async {
    final ProviderContainer container = await pumpScreen(
      tester,
      automation: _RecordingContextualAutomation(tempDir),
    );

    await tester.tap(find.byKey(const Key('live-browser-mode-agent')));
    await tester.pumpAndSettle();

    expect(container.read(liveBrowserProvider).mode, LiveBrowserMode.agent);
    expect(find.byKey(const Key('live-browser-prompt')), findsOneWidget);
    expect(find.byKey(const Key('live-browser-send')), findsOneWidget);
    expect(find.byKey(const Key('live-browser-user-hint')), findsNothing);

    // And back: the gate re-arms.
    await tester.tap(find.byKey(const Key('live-browser-mode-user')));
    await tester.pumpAndSettle();
    expect(container.read(liveBrowserProvider).mode, LiveBrowserMode.user);
    expect(find.byKey(const Key('live-browser-prompt')), findsNothing);
    expect(find.byKey(const Key('live-browser-user-hint')), findsOneWidget);
  });

  testWidgets('the URL bar Go normalizes a bare host (preview seam keeps '
      'the bar in sync)', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      automation: _RecordingContextualAutomation(tempDir),
    );

    await tester.enterText(
      find.byKey(const Key('live-browser-url')),
      'example.com',
    );
    await tester.tap(find.byKey(const Key('live-browser-go')));
    await tester.pump();

    expect(urlField(tester).text, 'https://example.com');
  });

  testWidgets('send: success shows the sent message, clears the prompt '
      'field and passes the current page', (WidgetTester tester) async {
    final _StubLiveBrowserController stub = _StubLiveBrowserController();
    await pumpScreen(tester, stub: stub);

    await tester.tap(find.byKey(const Key('live-browser-mode-agent')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('live-browser-prompt')),
      'click login',
    );
    await tester.tap(find.byKey(const Key('live-browser-send')));
    await tester.pumpAndSettle();

    expect(find.text(const AppStringsEn().liveBrowserSent), findsOneWidget);
    expect(stub.sendCalls, 1);
    expect(stub.lastPrompt, 'click login');
    expect(stub.lastUrl, 'https://restored.example/');
    expect(promptField(tester).text, isEmpty, reason: 'cleared on success');
  });

  testWidgets('send: a refusal shows the error message and KEEPS the '
      'typed text', (WidgetTester tester) async {
    final _StubLiveBrowserController stub = _StubLiveBrowserController()
      ..sendOutcome = const AppStringsEn().liveBrowserRefusalBusy;
    await pumpScreen(tester, stub: stub);

    await tester.tap(find.byKey(const Key('live-browser-mode-agent')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('live-browser-prompt')),
      'click login',
    );
    await tester.tap(find.byKey(const Key('live-browser-send')));
    await tester.pumpAndSettle();

    expect(
      find.text(const AppStringsEn().liveBrowserRefusalBusy),
      findsOneWidget,
    );
    expect(promptField(tester).text, 'click login');
  });

  testWidgets('an empty prompt is not sent', (WidgetTester tester) async {
    final _StubLiveBrowserController stub = _StubLiveBrowserController();
    await pumpScreen(tester, stub: stub);

    await tester.tap(find.byKey(const Key('live-browser-mode-agent')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('live-browser-prompt')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('live-browser-send')));
    await tester.pumpAndSettle();

    expect(stub.sendCalls, 0);
    expect(find.text(const AppStringsEn().liveBrowserSent), findsNothing);
  });

  testWidgets('attach failure renders the retry card and a retry '
      're-attaches', (WidgetTester tester) async {
    final _RecordingContextualAutomation automation =
        _RecordingContextualAutomation(tempDir)
          ..attachFailure = StateError('engine down');
    final ProviderContainer container = await pumpScreen(
      tester,
      automation: automation,
    );

    expect(find.byKey(const Key('live-browser-attach-error')), findsOneWidget);
    expect(find.text(const AppStringsEn().liveBrowserAttachFailed),
        findsOneWidget);
    expect(find.byKey(const Key('live-browser-retry')), findsOneWidget);
    expect(find.byKey(const Key('live-browser-preview')), findsNothing);
    expect(container.read(liveBrowserProvider).attached, isFalse);

    // The engine recovers: retry attaches and the page area renders.
    automation.attachFailure = null;
    await tester.tap(find.byKey(const Key('live-browser-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('live-browser-attach-error')), findsNothing);
    expect(find.byKey(const Key('live-browser-preview')), findsOneWidget);
    expect(container.read(liveBrowserProvider).attached, isTrue);
    expect(automation.attachNames, hasLength(2), reason: 'attach retried');
  });

  testWidgets('back navigation detaches the live context BEFORE the route '
      'pops', (WidgetTester tester) async {
    final _RecordingContextualAutomation automation =
        _RecordingContextualAutomation(tempDir);
    final ProviderContainer container = await pumpScreen(
      tester,
      automation: automation,
    );
    expect(container.read(liveBrowserProvider).attached, isTrue);

    final bool handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(automation.detachNames, <String>['live']);
    // The restored page URL was kept current and handed back for the
    // hibernation snapshot.
    expect(automation.detachLastUrls.single, 'https://restored.example/');
    expect(container.read(liveBrowserProvider).attached, isFalse);
    expect(find.byType(LiveBrowserScreen), findsNothing);
  });

  testWidgets('the app-bar close button runs the same detach-then-pop '
      'path', (WidgetTester tester) async {
    final _RecordingContextualAutomation automation =
        _RecordingContextualAutomation(tempDir);
    final ProviderContainer container = await pumpScreen(
      tester,
      automation: automation,
    );

    await tester.tap(find.byKey(const Key('live-browser-close')));
    await tester.pumpAndSettle();

    expect(automation.detachNames, <String>['live']);
    expect(container.read(liveBrowserProvider).attached, isFalse);
    expect(find.byType(LiveBrowserScreen), findsNothing);
  });
}
