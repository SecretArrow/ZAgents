import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/user_agent.dart';
import 'browser_automation.dart';

/// Live-browser engine — v1.54.0.
///
/// A [WebViewAutomation] whose controller comes from the user-visible
/// InAppWebView hosted by the Live Browser screen (external seam), and
/// whose interactive operations can be refused by a control gate: while
/// the USER holds control of the live browser, agent operations against
/// this engine answer with the standard failure shapes (the model reads
/// them like any other tool error and can tell the user to flip control
/// back). Infrastructure calls (purge/reconcile/reset) are never gated.
///
/// Gate semantics: the gate is checked FIRST, before the controller is
/// touched at all, so a gated call never disturbs the page the user is
/// looking at. Every refusal keeps its operation's existing failure
/// contract — [navigate] answers a [BrowserPageInfo] whose
/// [BrowserPageInfo.error] carries the refusal; click/type/scroll answer
/// `{'ok': false, 'error': ...}` like any failed interaction;
/// [screenshot] answers null (its callers already treat null as "capture
/// failed"); extractText/runJs answer the refusal text itself (their
/// contract is a plain string and existing callers surface string errors
/// verbatim).
class LiveBrowserEngine extends WebViewAutomation {
  LiveBrowserEngine({
    required bool Function() userHoldsControl,
    required Future<InAppWebViewController> Function() controller,
    UserAgentRecord? Function()? pickUserAgent,
  }) : _userHoldsControl = userHoldsControl,
       super(pickUserAgent: pickUserAgent, externalController: controller);

  final bool Function() _userHoldsControl;

  static const String _refusal =
      'the user is driving the live browser right now — hand control back '
      'to the AI (flip the mode switch) and retry';

  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    String? sessionId,
  }) async {
    if (_userHoldsControl()) {
      return BrowserPageInfo(url: url, title: '', text: '', error: _refusal);
    }
    return super.navigate(url, timeout: timeout, sessionId: sessionId);
  }

  @override
  Future<Map<String, dynamic>> click({
    String? selector,
    String? text,
    String? sessionId,
  }) async {
    if (_userHoldsControl()) {
      return <String, dynamic>{'ok': false, 'error': _refusal};
    }
    return super.click(selector: selector, text: text, sessionId: sessionId);
  }

  @override
  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear = true,
    String? sessionId,
  }) async {
    if (_userHoldsControl()) {
      return <String, dynamic>{'ok': false, 'error': _refusal};
    }
    return super.type(
      text,
      selector: selector,
      clear: clear,
      sessionId: sessionId,
    );
  }

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
    String? sessionId,
  }) async {
    if (_userHoldsControl()) {
      return <String, dynamic>{'ok': false, 'error': _refusal};
    }
    return super.scroll(
      direction: direction,
      amount: amount,
      sessionId: sessionId,
    );
  }

  @override
  Future<String?> screenshot({
    required String saveDir,
    String? sessionId,
  }) async {
    if (_userHoldsControl()) return null;
    return super.screenshot(saveDir: saveDir, sessionId: sessionId);
  }

  @override
  Future<String> extractText({
    int maxLength = 8000,
    String? sessionId,
  }) async {
    if (_userHoldsControl()) return _refusal;
    return super.extractText(maxLength: maxLength, sessionId: sessionId);
  }

  @override
  Future<String> runJs(String code, {String? sessionId}) async {
    if (_userHoldsControl()) return _refusal;
    return super.runJs(code, sessionId: sessionId);
  }
}
