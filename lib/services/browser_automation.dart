import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Snapshot of the current page returned after navigation.
class BrowserPageInfo {
  BrowserPageInfo({
    required this.url,
    required this.title,
    required this.text,
    this.error,
  });

  final String url;
  final String title;
  final String text;
  final String? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'title': title,
    'text': text,
    if (error != null) 'error': error,
  };
}

/// Abstraction over the embedded browser used by the agent.
abstract class BrowserAutomation {
  Future<BrowserPageInfo> navigate(String url, {Duration timeout});

  Future<Map<String, dynamic>> click({String? selector, String? text});

  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear,
  });

  Future<Map<String, dynamic>> scroll({String direction, int amount});

  /// Captures the current page and saves a PNG under [saveDir]. Returns path.
  Future<String?> screenshot({required String saveDir});

  Future<String> extractText({int maxLength});

  Future<String> runJs(String code);

  Future<void> resetSession();

  void dispose();
}

/// Production implementation backed by a headless InAppWebView.
class WebViewAutomation implements BrowserAutomation {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  Completer<WebUri?>? _navCompleter;

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  Future<InAppWebViewController> _ensure() async {
    if (_controller != null) {
      return _controller!;
    }
    final headless = HeadlessInAppWebView(
      initialSize: const Size(1080, 1920),
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        supportZoom: false,
        userAgent: _userAgent,
      ),
      onLoadStop: (InAppWebViewController controller, WebUri? url) {
        final completer = _navCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(url);
        }
      },
      onReceivedError:
          (
            InAppWebViewController controller,
            WebResourceRequest request,
            WebResourceError error,
          ) {
            final completer = _navCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.complete(null);
            }
          },
    );
    await headless.run();
    _headless = headless;
    _controller = headless.webViewController;
    return _controller!;
  }

  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (url.trim().isEmpty) {
      return BrowserPageInfo(url: '', title: '', text: '', error: 'URL kosong');
    }
    final controller = await _ensure();
    final normalized = url.trim().contains('://')
        ? url.trim()
        : 'https://${url.trim()}';
    _navCompleter = Completer<WebUri?>();
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(normalized)));

    String? error;
    try {
      final loaded = await _navCompleter!.future.timeout(timeout);
      if (loaded == null) {
        error = 'Halaman gagal dimuat (jaringan/timeout).';
      }
    } on TimeoutException {
      error = 'Halaman tidak selesai memuat dalam ${timeout.inSeconds}s.';
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final info = await _pageInfo();
    return BrowserPageInfo(
      url: info['url']?.toString() ?? normalized,
      title: info['title']?.toString() ?? '',
      text: info['text']?.toString() ?? '',
      error: error,
    );
  }

  Future<Map<String, dynamic>> _pageInfo() async {
    final controller = await _ensure();
    try {
      final raw = await controller.evaluateJavascript(
        source:
            'JSON.stringify({url: location.href, title: document.title || "", '
            'text: ((document.body && document.body.innerText) || "").slice(0, 5000)})',
      );
      final decoded = _decodeMap(raw);
      if (decoded != null) return decoded;
    } catch (_) {
      // Ignore JS errors while collecting page info.
    }
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> click({String? selector, String? text}) async {
    final controller = await _ensure();
    final raw = await controller.evaluateJavascript(
      source: _jsClick(jsonEncode(selector), jsonEncode(text)),
    );
    return _decodeMap(raw) ??
        <String, dynamic>{'ok': false, 'error': 'Tidak ada hasil dari JS.'};
  }

  String _jsClick(String selectorJson, String textJson) =>
      '''
(function() {
  var selector = $selectorJson;
  var text = $textJson;
  var el = null;
  if (selector && selector.length) {
    try { el = document.querySelector(selector); }
    catch (e) { return JSON.stringify({ok: false, error: 'Selector tidak valid: ' + e.message}); }
  } else if (text && text.length) {
    var candidates = Array.prototype.slice.call(document.querySelectorAll(
      'a, button, [role="button"], input[type="submit"], input[type="button"], summary, li, span, div'));
    for (var i = 0; i < candidates.length; i++) {
      var c = candidates[i];
      var label = (c.innerText || c.value || c.getAttribute('aria-label') || '').trim();
      if (label && label.toLowerCase().indexOf(text.toLowerCase()) !== -1 && c.offsetParent !== null) {
        el = c; break;
      }
    }
  }
  if (!el) return JSON.stringify({ok: false, error: 'Elemen tidak ditemukan'});
  try { el.scrollIntoView({block: 'center'}); } catch (e) {}
  el.click();
  return JSON.stringify({ok: true, clicked: (el.innerText || el.value || '').trim().slice(0, 100)});
})()
''';

  @override
  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear = true,
  }) async {
    final controller = await _ensure();
    final raw = await controller.evaluateJavascript(
      source: _jsType(jsonEncode(text), jsonEncode(selector), clear),
    );
    return _decodeMap(raw) ??
        <String, dynamic>{'ok': false, 'error': 'Tidak ada hasil dari JS.'};
  }

  String _jsType(String textJson, String selectorJson, bool clear) =>
      '''
(function() {
  var text = $textJson;
  var selector = $selectorJson;
  var el = null;
  if (selector && selector.length) { el = document.querySelector(selector); }
  if (!el) {
    var active = document.activeElement;
    var activeIsInput = active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable);
    el = activeIsInput ? active : document.querySelector('input:not([type=hidden]), textarea, [contenteditable="true"]');
  }
  if (!el) return JSON.stringify({ok: false, error: 'Elemen input tidak ditemukan'});
  el.focus();
  try { el.scrollIntoView({block: 'center'}); } catch (e) {}
  if (el.isContentEditable) {
    if (clear) el.textContent = '';
    el.textContent = (clear ? '' : (el.textContent || '')) + text;
    el.dispatchEvent(new InputEvent('input', {bubbles: true, data: text}));
  } else {
    var proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
    if (clear) setter.call(el, '');
    setter.call(el, (clear ? '' : el.value) + text);
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
  }
  return JSON.stringify({ok: true, typed: String(text).slice(0, 100)});
})()
''';

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
  }) async {
    final controller = await _ensure();
    final dy = direction == 'up' ? -amount : amount;
    final raw = await controller.evaluateJavascript(
      source:
          '(function(){ window.scrollBy(0, $dy); '
          'return JSON.stringify({ok: true, scrollY: window.scrollY}); })()',
    );
    return _decodeMap(raw) ??
        <String, dynamic>{'ok': false, 'error': 'Scroll gagal.'};
  }

  @override
  Future<String> extractText({int maxLength = 8000}) async {
    final controller = await _ensure();
    final raw = await controller.evaluateJavascript(
      source: 'JSON.stringify({text: ((document.body && document.body.innerText) || "")})',
    );
    final map = _decodeMap(raw) ?? <String, dynamic>{};
    final text = map['text']?.toString() ?? '';
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}\n... [teks dipotong]';
  }

  @override
  Future<String> runJs(String code) async {
    final controller = await _ensure();
    final result = await controller.evaluateJavascript(source: code);
    if (result == null) return 'null';
    if (result is String) return result;
    return jsonEncode(result);
  }

  @override
  Future<String?> screenshot({required String saveDir}) async {
    final controller = await _ensure();
    final Uint8List? bytes;
    try {
      bytes = await controller.takeScreenshot();
    } catch (_) {
      return null;
    }
    if (bytes == null || bytes.isEmpty) return null;
    final dir = Directory(saveDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path =
        '${dir.path}${Platform.pathSeparator}shot_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  @override
  Future<void> resetSession() async {
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {
      // Best effort.
    }
  }

  @override
  void dispose() {
    _headless?.dispose();
    _headless = null;
    _controller = null;
  }

  Map<String, dynamic>? _decodeMap(Object? raw) {
    try {
      if (raw is Map<String, dynamic>) return raw;
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {
      // Ignore malformed JS results.
    }
    return null;
  }
}
