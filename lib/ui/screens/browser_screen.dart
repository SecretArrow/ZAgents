import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/user_agent.dart';
import '../../services/browser_automation.dart';
import '../../services/live_browser_controller.dart';
import '../theme.dart';
import '../widgets/app_message.dart';

/// v1.54.0 — the Live Browser screen: a user-visible in-app browser where
/// the user can browse manually OR hand the page to the agent.
///
/// Handover model:
/// * **You (user mode, default)** — the user holds the controls and
///   browses freely. The live engine's control gate is ON: agent browser
///   tool calls targeting the `live` context are refused (the refusal
///   comes back as a tool error the model relays), so the agent can never
///   fight the user over the visible page.
/// * **AI (agent mode)** — the gate opens: the agent's browser tool calls
///   with `context: "live"` act on THIS visible WebView, so the user
///   watches every action live. The prompt bar at the bottom sends the
///   current page (URL + title) plus the typed request into the owning
///   chat through [LiveBrowserController.handToAgent].
///
/// The screen attaches on open ([LiveBrowserController.attach]) — the
/// 'live' named context of the active chat is backed by this visible
/// WebView — and detaches on close: the pop guard runs the detach BEFORE
/// the route disposes the WebView, so the contextual engine can capture +
/// hibernate the page state (the registry row survives; the next open
/// restores the last page as the first load).
class LiveBrowserScreen extends ConsumerStatefulWidget {
  const LiveBrowserScreen({
    super.key,
    required this.sessionId,
    this.preview = false,
  });

  /// Owning chat session: the 'live' browser context is registered under
  /// this id and the prompt bar hands pages to THIS chat.
  final String sessionId;

  /// Widget-test seam: when true the page area renders a
  /// `Key('live-browser-preview')` placeholder and NO real InAppWebView is
  /// embedded (widget tests cannot host the platform view). Everything
  /// else — chrome, URL bar, mode switch, prompt bar, pop guard — works
  /// identically.
  @visibleForTesting
  final bool preview;

  @override
  ConsumerState<LiveBrowserScreen> createState() => _LiveBrowserScreenState();
}

class _LiveBrowserScreenState extends ConsumerState<LiveBrowserScreen> {
  final TextEditingController _urlField = TextEditingController();
  final TextEditingController _promptField = TextEditingController();

  /// Controller of the real WebView (null in preview mode / before
  /// creation). Local copy for URL-bar loads; the engine gets its own
  /// copy through the service's controller seam.
  InAppWebViewController? _webviewController;

  /// Last known page URL + title — kept in sync with redirects and SPA
  /// history (onUpdateVisitedHistory) for the detach snapshot and the
  /// handover message.
  String _currentUrl = '';
  String _currentTitle = '';

  /// Load progress of the visible WebView (100 = idle/hidden bar).
  int _progress = 100;

  /// The User-Agent identity for the visible WebView, resolved once per
  /// mount exactly like di.dart wires the headless engines.
  UserAgentRecord? _ua;

  @override
  void initState() {
    super.initState();
    // Attach before the view settles: the restored lastUrl must be in the
    // service state when the page area is first built. Preview mode
    // attaches too — the service's dependencies are provider overrides in
    // tests. Deferred to the event queue on purpose: attach WRITES the
    // provider state, and a synchronous write from initState throws
    // Riverpod's "modified while the widget tree was building" guard.
    Future<void>(() async {
      if (!mounted) return;
      await ref.read(liveBrowserProvider.notifier).attach(widget.sessionId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ua ??= ref
        .read(userAgentManagerProvider)
        .resolve(ref.read(settingsProvider).uaMode);
  }

  @override
  void dispose() {
    _urlField.dispose();
    _promptField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final LiveBrowserState live = ref.watch(liveBrowserProvider);
    // The restored URL lands asynchronously with the attach result: mirror
    // it into the URL bar once it arrives.
    ref.listen<String>(
      liveBrowserProvider.select((LiveBrowserState s) => s.initialUrl),
      (String? previous, String next) {
        if (next.isEmpty || next == previous) return;
        _currentUrl = next;
        _urlField.value = TextEditingValue(
          text: next,
          selection: const TextSelection.collapsed(offset: 0),
        );
      },
    );

    return PopScope<void>(
      // Back/close run the detach FIRST (the capture inside
      // detachExternalContext needs the WebView alive), then pop.
      // The lambda params are left un-annotated on purpose: the SDK
      // signature is (bool, void) and inferring keeps this compatible
      // across Flutter versions (an explicit void? annotation is
      // rejected by the CFE on older toolchains).
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.liveBrowserTitle),
          actions: <Widget>[
            _modeControl(strings, live.mode),
            const SizedBox(width: 4),
            IconButton(
              key: const Key('live-browser-close'),
              tooltip: strings.cancel,
              onPressed: _close,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        body: SafeArea(
          // top:false: the AppBar already reserves the status-bar strip.
          top: false,
          child: Column(
            children: <Widget>[
              _urlBar(strings),
              if (_progress > 0 && _progress < 100)
                LinearProgressIndicator(
                  key: const Key('live-browser-progress'),
                  value: _progress / 100,
                  minHeight: 2,
                ),
              Expanded(child: _pageArea(strings, live)),
              if (live.mode == LiveBrowserMode.agent)
                _promptBar(strings)
              else
                _userHint(strings),
            ],
          ),
        ),
      ),
    );
  }

  /// The You/AI segmented control — who drives the visible page. Tapping
  /// flips the service state; the live engine's control gate reads it
  /// live, so agent ops are refused/allowed immediately.
  Widget _modeControl(AppStrings strings, LiveBrowserMode mode) {
    return SegmentedButton<LiveBrowserMode>(
      key: const Key('live-browser-mode'),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: <ButtonSegment<LiveBrowserMode>>[
        ButtonSegment<LiveBrowserMode>(
          value: LiveBrowserMode.user,
          label: KeyedSubtree(
            key: const Key('live-browser-mode-user'),
            child: Text(strings.liveBrowserModeUser),
          ),
        ),
        ButtonSegment<LiveBrowserMode>(
          value: LiveBrowserMode.agent,
          label: KeyedSubtree(
            key: const Key('live-browser-mode-agent'),
            child: Text(strings.liveBrowserModeAgent),
          ),
        ),
      ],
      selected: <LiveBrowserMode>{mode},
      onSelectionChanged: (Set<LiveBrowserMode> selection) =>
          ref.read(liveBrowserProvider.notifier).setMode(selection.first),
    );
  }

  /// Editable URL bar + Go. Always editable: the user can drive even while
  /// the agent holds the controls.
  Widget _urlBar(AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              key: const Key('live-browser-url'),
              controller: _urlField,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (String _) => _go(),
              decoration: const InputDecoration(
                hintText: 'https://',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('live-browser-go'),
            tooltip: strings.open,
            onPressed: _go,
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  /// The page area: attach failure → retry card, attaching → spinner,
  /// attached → the real WebView (or the preview placeholder in tests).
  Widget _pageArea(AppStrings strings, LiveBrowserState live) {
    if (live.attachError.isNotEmpty) {
      return Center(
        child: Card(
          key: const Key('live-browser-attach-error'),
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.cloud_off_rounded, size: 32, color: context.zMuted),
                const SizedBox(height: 8),
                Text(
                  strings.liveBrowserAttachFailed,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  live.attachError,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: context.zMuted),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  key: const Key('live-browser-retry'),
                  onPressed: () => ref
                      .read(liveBrowserProvider.notifier)
                      .attach(widget.sessionId),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(strings.liveBrowserRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!live.attached) {
      return Center(
        child: CircularProgressIndicator(
          key: const Key('live-browser-attaching'),
          strokeWidth: 2,
          semanticsLabel: strings.loading,
        ),
      );
    }
    if (widget.preview) {
      return Container(
        key: const Key('live-browser-preview'),
        alignment: Alignment.center,
        color: context.zSurfaceAlt,
        child: Icon(
          Icons.travel_explore_rounded,
          size: 48,
          color: context.zMuted,
        ),
      );
    }
    return InAppWebView(
      key: const Key('live-browser-webview'),
      initialUrlRequest: URLRequest(
        url: WebUri(live.initialUrl.isEmpty ? 'about:blank' : live.initialUrl),
      ),
      initialSettings: WebViewAutomation.settingsFor(_ua!),
      // Same private-window hardening the headless engines apply: new
      // service-worker registrations are rejected at document start in
      // every frame.
      initialUserScripts: UnmodifiableListView<UserScript>(<UserScript>[
        UserScript(
          source: WebViewAutomation.serviceWorkerBlockScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
      ]),
      onWebViewCreated: _onWebViewCreated,
      onLoadStop: _syncUrl,
      // Keeps the bar in sync with redirects and SPA history pushes.
      onUpdateVisitedHistory: (
        InAppWebViewController controller,
        WebUri? url,
        bool? isReload,
      ) => _syncUrl(controller, url),
      onProgressChanged: (InAppWebViewController controller, int progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      },
    );
  }

  /// The AGENT-mode prompt bar: sends the current page + the typed request
  /// into the owning chat; the user watches the agent work on this page.
  Widget _promptBar(AppStrings strings) {
    return Padding(
      key: const Key('live-browser-prompt-bar'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              key: const Key('live-browser-prompt'),
              controller: _promptField,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (String _) => _sendPrompt(),
              decoration: InputDecoration(
                hintText: strings.liveBrowserPromptHint,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('live-browser-send'),
            tooltip: strings.send,
            onPressed: _sendPrompt,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  /// The USER-mode hint row (replaces the prompt bar while the user
  /// drives).
  Widget _userHint(AppStrings strings) {
    return Padding(
      key: const Key('live-browser-user-hint'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.touch_app_rounded, size: 16, color: context.zMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              strings.liveBrowserUserHint,
              style: TextStyle(fontSize: 12, color: context.zMuted),
            ),
          ),
        ],
      ),
    );
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _webviewController = controller;
    ref.read(liveBrowserProvider.notifier).onWebViewCreated(controller);
  }

  /// Loads the URL bar's text: a bare host gets https:// prepended (same
  /// normalization as the automation's navigate).
  void _go() {
    final String raw = _urlField.text.trim();
    if (raw.isEmpty) return;
    _load(raw.contains('://') ? raw : 'https://$raw');
  }

  Future<void> _load(String url) async {
    final InAppWebViewController? controller = _webviewController;
    if (controller == null) {
      // Preview seam (widget tests): no platform view — keep the bar and
      // the remembered page in sync only.
      if (!mounted) return;
      setState(() {
        _currentUrl = url;
        _urlField.value = TextEditingValue(
          text: url,
          selection: const TextSelection.collapsed(offset: 0),
        );
      });
      return;
    }
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } catch (_) {
      // The WebView renders its own error page; the bar keeps the target.
    }
  }

  /// Mirrors the WebView's URL into the bar and remembers url + title for
  /// the detach snapshot and the handover message.
  Future<void> _syncUrl(InAppWebViewController controller, WebUri? url) async {
    if (!mounted) return;
    final String href = url?.toString() ?? '';
    if (href.isEmpty) return;
    if (href != _currentUrl || _urlField.text != href) {
      setState(() {
        _currentUrl = href;
        _urlField.value = TextEditingValue(
          text: href,
          selection: const TextSelection.collapsed(offset: 0),
        );
      });
    }
    // Title best-effort: only for the handover message, never fatal.
    try {
      final String? title = await controller.getTitle();
      if (mounted && title != null && title.isNotEmpty) {
        if (title != _currentTitle) {
          setState(() => _currentTitle = title);
        }
      }
    } catch (_) {
      // Ignore: the page may be mid-navigation.
    }
  }

  Future<void> _sendPrompt() async {
    final String text = _promptField.text.trim();
    if (text.isEmpty) return;
    final AppStrings strings = stringsOf(context);
    final String? refusal = await ref
        .read(liveBrowserProvider.notifier)
        .handToAgent(text, url: _currentUrl, title: _currentTitle);
    if (!mounted) return;
    if (refusal == null) {
      // Success: clear the field — the request is now in the chat.
      _promptField.clear();
      showAppMessage(context, strings.liveBrowserSent);
    } else {
      showAppMessage(context, refusal, error: true);
    }
  }

  /// Pop path: detach (capture + hibernate while the WebView is still
  /// alive) and only then pop the route. A second invocation is a no-op —
  /// the service flips to detached synchronously.
  Future<void> _close() async {
    await ref.read(liveBrowserProvider.notifier).detach(_currentUrl);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
