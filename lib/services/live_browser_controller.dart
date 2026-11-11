import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart' show AppSettings;
import 'browser_live_engine.dart';
import 'browser_session_isolation.dart';

/// Who drives the live browser right now (v1.54.0).
///
/// * [user] — the control gate is ON: the engine refuses agent operations
///   on the live context (they come back as tool errors the model can
///   relay), so the user's manual browsing is never fought over.
/// * [agent] — the gate is OPEN: agent browser tool calls with
///   `context: "live"` act on the page the user is watching.
enum LiveBrowserMode { user, agent }

/// Immutable state of [LiveBrowserController].
class LiveBrowserState {
  const LiveBrowserState({
    this.mode = LiveBrowserMode.user,
    this.sessionId,
    this.attached = false,
    this.initialUrl = '',
    this.attachError = '',
  });

  /// Who drives: user (gate ON) or agent (gate open).
  final LiveBrowserMode mode;

  /// Owning chat session of the 'live' context (null while detached).
  final String? sessionId;

  /// Whether the engine is currently attached as the 'live' context of
  /// [sessionId].
  final bool attached;

  /// Restored hibernation lastUrl — the visible WebView's first load
  /// (empty when the previous session parked on a non-http page).
  final String initialUrl;

  /// Non-empty when the attach failed; the screen renders the retry card.
  final String attachError;

  LiveBrowserState copyWith({
    LiveBrowserMode? mode,
    String? sessionId,
    bool? attached,
    String? initialUrl,
    String? attachError,
  }) => LiveBrowserState(
    mode: mode ?? this.mode,
    sessionId: sessionId ?? this.sessionId,
    attached: attached ?? this.attached,
    initialUrl: initialUrl ?? this.initialUrl,
    attachError: attachError ?? this.attachError,
  );
}

/// v1.54.0 — the Live Browser controller.
///
/// Owns the 'live' named browser context of the ACTIVE chat: while the
/// screen is open, the context's engine is the user-visible InAppWebView
/// ([ContextualBrowserAutomation.attachExternalContext] with a
/// [LiveBrowserEngine]); agent browser tool calls with `context: "live"`
/// then act on the page the user is watching. The mode switch decides who
/// drives: in user mode the engine's control gate refuses agent ops (they
/// come back as tool errors the model can relay); in agent mode the gate
/// is open and the prompt bar sends the page into the chat through
/// [ChatController.sendToSession]. Closing the screen detaches: the
/// contextual engine captures + hibernates the live context (registry row
/// kept), so the next open restores the last page.
class LiveBrowserController extends Notifier<LiveBrowserState> {
  /// The visible WebView's controller, completed by the screen's
  /// [onWebViewCreated]. Recreated on every attach; handed to the engine
  /// as its controller seam.
  Completer<InAppWebViewController>? _controllerCompleter;

  /// Guards against a concurrent duplicate attach (initState + retry).
  bool _attaching = false;

  @override
  LiveBrowserState build() => const LiveBrowserState();

  /// The controller seam handed to the engine: awaits the visible
  /// WebView's controller (see [onWebViewCreated]).
  Future<InAppWebViewController> _controller() {
    final Completer<InAppWebViewController> completer =
        _controllerCompleter ??= Completer<InAppWebViewController>();
    return completer.future;
  }

  /// Attaches the visible-WebView engine as the 'live' named context of
  /// [sessionId], restoring the hibernated last page (if any) as
  /// [LiveBrowserState.initialUrl]. Never throws: failures land in
  /// [LiveBrowserState.attachError] and the screen offers a retry.
  Future<void> attach(String sessionId) async {
    if (_attaching || (state.attached && state.sessionId == sessionId)) {
      return;
    }
    // Defense: the live browser needs the multi-context engine's external
    // attach/detach API. di.dart always wires the contextual one; anything
    // else (a test double, a future wiring change) degrades to a clear
    // error instead of a crash.
    final dynamic raw = ref.read(browserAutomationProvider);
    if (raw is! ContextualBrowserAutomation) {
      state = state.copyWith(
        sessionId: sessionId,
        attachError: 'live browser needs the multi-context engine',
      );
      return;
    }
    final ContextualBrowserAutomation automation = raw;
    _attaching = true;
    _controllerCompleter = Completer<InAppWebViewController>();
    try {
      final LiveBrowserEngine engine = LiveBrowserEngine(
        userHoldsControl: () => state.mode == LiveBrowserMode.user,
        controller: _controller,
        pickUserAgent: () {
          final AppSettings settings = ref.read(settingsProvider);
          return ref
              .read(userAgentManagerProvider)
              .resolve(settings.uaMode);
        },
      );
      final Map<String, dynamic> info = await automation.attachExternalContext(
        name: 'live',
        sessionId: sessionId,
        engine: engine,
      );
      final String lastUrl = (info['lastUrl'] as String?) ?? '';
      state = state.copyWith(
        attached: true,
        sessionId: sessionId,
        // Only a real web page is worth restoring; about:blank and
        // half-written internal URLs start the fresh blank page instead.
        initialUrl:
            (lastUrl.startsWith('http://') || lastUrl.startsWith('https://'))
            ? lastUrl
            : '',
        attachError: '',
      );
    } catch (e) {
      state = state.copyWith(
        sessionId: sessionId,
        attachError: 'live browser attach failed: $e',
      );
    } finally {
      _attaching = false;
    }
  }

  /// Switches who drives. The engine's control gate reads the state live,
  /// so this single assignment opens/closes the gate for agent operations
  /// on the 'live' context.
  void setMode(LiveBrowserMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
  }

  /// Completes the engine's controller seam with the real WebView
  /// controller (called by the screen's onWebViewCreated).
  void onWebViewCreated(InAppWebViewController controller) {
    final Completer<InAppWebViewController> completer =
        _controllerCompleter ??= Completer<InAppWebViewController>();
    if (!completer.isCompleted) {
      completer.complete(controller);
    }
  }

  /// Detaches the 'live' context on screen close: the contextual engine
  /// captures + hibernates the visible WebView's state (registry row
  /// kept, so the next open restores it) and a straggler engine op that
  /// never saw a controller fails fast instead of hanging.
  ///
  /// Best-effort and never throws — a pop must always complete. Idempotent:
  /// the state flips to detached synchronously, so a second back press
  /// cannot run a second teardown.
  Future<void> detach(String currentUrl) async {
    if (!state.attached) return;
    final String? sessionId = state.sessionId;
    // Claim synchronously (double-pop guard) BEFORE any await.
    state = LiveBrowserState(mode: state.mode);
    // No WebView was ever created (preview seam / failed creation): there
    // is nothing to capture from, so anything parked on the controller
    // seam — including the capture inside detachExternalContext — must
    // fail fast instead of waiting forever.
    final Completer<InAppWebViewController>? completer = _controllerCompleter;
    _controllerCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        StateError('the live browser WebView is no longer available'),
      );
      // A straggler parked on the seam still sees the error; when NOBODY
      // is parked the .ignore() listener keeps it from surfacing as an
      // unhandled async error in the zone.
      completer.future.ignore();
    }
    if (sessionId == null) return;
    final dynamic raw = ref.read(browserAutomationProvider);
    if (raw is! ContextualBrowserAutomation) return;
    final ContextualBrowserAutomation automation = raw;
    final String trimmed = currentUrl.trim();
    try {
      await automation.detachExternalContext(
        name: 'live',
        sessionId: sessionId,
        lastUrl: trimmed.isEmpty ? null : trimmed,
      );
    } catch (_) {
      // Best-effort hibernation: a failed snapshot degrades to a fresh
      // 'live' context on the next open, never a stuck pop.
    }
  }

  /// Hands the current page + [prompt] to the owning chat through
  /// [ChatController.sendToSession] (exactly like a typed message, but
  /// pre-faced with the live-browser handover instructions).
  ///
  /// Returns null on success, or a LOCALIZED user-facing message built
  /// from sendToSession's English refusal (see [refusalMessage]).
  Future<String?> handToAgent(
    String prompt, {
    required String url,
    required String title,
  }) async {
    final AppStrings strings = appStringsFor(
      ref.read(settingsProvider).languageCode,
    );
    final String trimmed = prompt.trim();
    final String? sessionId = state.sessionId;
    if (sessionId == null || trimmed.isEmpty) {
      return refusalMessage(strings, 'empty prompt');
    }
    final String message = buildLiveHandoverMessage(url, title, trimmed);
    final String? refusal = await ref
        .read(chatControllerProvider.notifier)
        .sendToSession(sessionId, message);
    if (refusal == null) return null;
    return refusalMessage(strings, refusal);
  }

  /// The chat message the prompt bar sends: page context + the
  /// instruction to drive the NAMED browser context "live" (so the agent's
  /// browser tool calls act on the page the user is watching), then the
  /// user's prompt. English on purpose — it is model-facing, not
  /// user-facing.
  @visibleForTesting
  static String buildLiveHandoverMessage(
    String url,
    String title,
    String prompt,
  ) {
    final String label = title.trim().isEmpty ? url : title.trim();
    return '[live browser | $label]\n'
        'Page: $url\n'
        'Drive the named browser context "live" (pass context: "live" to '
        'your browser tools) so I can watch your actions on my screen.'
        '\n\n'
        '${prompt.trim()}';
  }

  /// Maps sendToSession's English refusal reasons onto the localized
  /// live-browser strings; unknown reasons get the generic message with
  /// the raw detail appended.
  @visibleForTesting
  static String refusalMessage(AppStrings strings, String refusal) {
    switch (refusal) {
      case 'chat busy':
        return strings.liveBrowserRefusalBusy;
      case 'missing API key':
        return strings.liveBrowserRefusalNoKey;
      case 'model not set':
        return strings.liveBrowserRefusalNoModel;
      case 'chat waiting for module setup':
        return strings.liveBrowserRefusalSetup;
      case 'chat not found':
        return strings.liveBrowserRefusalNotFound;
      case 'empty prompt':
      case 'app shutting down':
        return strings.liveBrowserRefusalGeneric;
      default:
        return '${strings.liveBrowserRefusalGeneric} ($refusal)';
    }
  }

  /// The controller seam's future as handed to the engine — visible for
  /// tests so the fail-fast contract of [detach] can be pinned without a
  /// platform WebView.
  @visibleForTesting
  Future<InAppWebViewController>? get debugControllerFuture =>
      _controllerCompleter?.future;
}

/// App-lifetime state + controller of the Live Browser screen.
final liveBrowserProvider =
    NotifierProvider<LiveBrowserController, LiveBrowserState>(
      LiveBrowserController.new,
    );
