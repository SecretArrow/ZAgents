import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zagents/di.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/app_lock_service.dart';
import 'package:zagents/services/background_service.dart';
import 'package:zagents/services/browser_automation.dart';
import 'package:zagents/services/chat_store.dart';
import 'package:zagents/services/context_repository.dart';
import 'package:zagents/services/js_runtime.dart';
import 'package:zagents/services/llm_client.dart';
import 'package:zagents/services/prompt_repository.dart';
import 'package:zagents/services/settings_repository.dart';

/// Minimal valid 1x1 PNG used as fake screenshot bytes.
const String tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Scripted LLM client for tests: returns queued turns in order
/// (last turn repeats when the queue is exhausted).
class FakeLlmClient implements LlmClient {
  FakeLlmClient(this.turns, {this.onFirstDelta, this.onTurnComplete});

  final List<AssistantTurn> turns;
  int _index = 0;

  /// Invoked just before the first content delta of a turn is emitted —
  /// lets tests trigger controller.stop() mid-stream.
  final void Function()? onFirstDelta;

  /// Invoked right before a turn is handed back to the controller — lets
  /// tests trigger controller.stop() between steps.
  final void Function()? onTurnComplete;

  /// Wire messages captured for every call.
  final List<List<Map<String, dynamic>>> calls = <List<Map<String, dynamic>>>[];

  /// Tool schemas captured for every call (null = plain chat mode).
  final List<List<Map<String, dynamic>>?> toolSets =
      <List<Map<String, dynamic>>?>[];

  @override
  Future<AssistantTurn> complete({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    void Function(String delta)? onDelta,
    bool Function()? shouldAbort,
  }) async {
    if (shouldAbort?.call() ?? false) {
      throw const LlmAbortedException('');
    }
    calls.add(messages);
    toolSets.add(tools);
    final AssistantTurn turn =
        turns[_index < turns.length - 1 ? _index++ : turns.length - 1];
    if (turn.content.isNotEmpty && onDelta != null) {
      var first = true;
      final buffer = StringBuffer();
      for (final String part in turn.content.split(' ')) {
        if (first) {
          onFirstDelta?.call();
          first = false;
        }
        buffer.write('$part ');
        onDelta('$part ');
        await Future<void>.delayed(Duration.zero);
        // Abort mid-stream: Stop must cut the turn short, keeping what
        // was already streamed.
        if (shouldAbort?.call() ?? false) {
          throw LlmAbortedException(buffer.toString());
        }
      }
    }
    onTurnComplete?.call();
    return turn;
  }
}

/// Recording fake browser for tests. Screenshot writes a tiny PNG to disk
/// when [writeScreenshot] is true (real IO — only safe outside fake-async);
/// otherwise it returns a path without touching the filesystem.
class FakeBrowserAutomation implements BrowserAutomation {
  FakeBrowserAutomation(this.saveDir, {this.writeScreenshot = true});

  final String saveDir;
  final bool writeScreenshot;
  final List<String> calls = <String>[];

  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    String? sessionId,
  }) async {
    calls.add('navigate:$url${sessionId == null ? '' : ' @$sessionId'}');
    if (url.trim().isEmpty) {
      return BrowserPageInfo(url: '', title: '', text: '', error: 'URL kosong');
    }
    return BrowserPageInfo(
      url: url,
      title: 'Example Domain',
      text: 'Example Domain\nThis domain is for use in illustrative examples.',
    );
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
    final String path =
        '$saveDir${Platform.pathSeparator}fake_shot_${DateTime.now().microsecondsSinceEpoch}.png';
    if (!writeScreenshot) return path;
    final Directory dir = Directory(saveDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await File(path).writeAsBytes(base64Decode(tinyPngBase64));
    return path;
  }

  @override
  Future<String> extractText({int maxLength = 8000, String? sessionId}) async {
    calls.add('extract');
    const String text =
        'Example Domain\nThis domain is for use in illustrative examples.';
    return text.length > maxLength ? text.substring(0, maxLength) : text;
  }

  @override
  Future<String> runJs(String code, {String? sessionId}) async {
    calls.add('run_js:$code');
    return '"ok"';
  }

  @override
  Future<void> purgeSiteData() async {
    calls.add('purge_site_data');
  }

  @override
  Future<String> reconcileOriginStorage(String payloadJson) async {
    calls.add('reconcile_origin:$payloadJson');
    return 'reconciled';
  }

  @override
  Future<void> resetSession() async {}

  @override
  void dispose() {}
}

/// ChatStore fake whose [load]/[delete] throw — proves the chat controller
/// converts storage failures into localized error messages instead of
/// crashing (these futures are invoked without await from the UI).
class ThrowingChatStore implements ChatStore {
  @override
  Future<Directory> Function() get resolveBaseDir => _explode;

  Future<Directory> _explode() async =>
      throw const FileSystemException('disk exploded');

  @override
  Future<List<ChatSummary>> listSummaries() async => <ChatSummary>[];

  @override
  Future<List<ChatSearchHit>> searchAll(String query, {int limit = 50}) async =>
      <ChatSearchHit>[];

  @override
  Future<void> save({
    required String id,
    required String title,
    required List<ChatMessage> messages,
  }) async {}

  @override
  Future<List<ChatMessage>?> load(String id) async =>
      throw const FileSystemException('disk exploded');

  @override
  Future<void> delete(String id) async =>
      throw const FileSystemException('disk exploded');

  @override
  Future<void> rename(String id, String title) async =>
      throw const FileSystemException('disk exploded');
}

/// Browser fake whose every method throws — used to prove the tool
/// executor degrades platform failures into error results instead of
/// crashing the agent loop.
class ThrowingBrowserAutomation implements BrowserAutomation {
  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
    String? sessionId,
  }) async => throw const SocketException('browser exploded');

  @override
  Future<Map<String, dynamic>> click({
    String? selector,
    String? text,
    String? sessionId,
  }) async => throw const SocketException('browser exploded');

  @override
  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear = true,
    String? sessionId,
  }) async => throw const SocketException('browser exploded');

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
    String? sessionId,
  }) async => throw const SocketException('browser exploded');

  @override
  Future<String?> screenshot({
    required String saveDir,
    String? sessionId,
  }) async => throw const SocketException('browser exploded');

  @override
  Future<String> extractText({int maxLength = 8000, String? sessionId}) async =>
      throw const SocketException('browser exploded');

  @override
  Future<String> runJs(String code, {String? sessionId}) async =>
      throw const SocketException('browser exploded');

  @override
  Future<void> purgeSiteData() async =>
      throw const SocketException('browser exploded');

  @override
  Future<String> reconcileOriginStorage(String payloadJson) async =>
      throw const SocketException('browser exploded');

  @override
  Future<void> resetSession() async {}

  @override
  void dispose() {}
}

/// Recording fake for the background-run hold: captures every call so
/// tests can assert the foreground service is started/stopped around the
/// agent loop and receives per-step progress updates.
class RecordingBackgroundRun implements BackgroundRun {
  final List<String> calls = <String>[];
  bool _active = false;

  /// Recorded "task finished" notifications (v1.18.0).
  final List<String> doneNotifications = <String>[];

  /// Value returned by [drainPendingSession].
  String? pendingSession;

  @override
  bool get isActive => _active;

  @override
  Future<void> start({required String title, required String text}) async {
    calls.add('start:$title|$text');
    _active = true;
  }

  @override
  Future<void> updateStatus(String text) async {
    calls.add('update:$text');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _active = false;
  }

  @override
  Future<bool> notifyDone({
    required String title,
    required String text,
    String? sessionId,
  }) async {
    doneNotifications.add('$title|$text|$sessionId');
    return true;
  }

  @override
  Future<String?> drainPendingSession() async {
    final String? value = pendingSession;
    pendingSession = null;
    return value;
  }
}

/// Standard test overrides for the app's provider scope.
///
/// Set [writeScreenshots] to false for widget tests: the fake-async zone
/// cannot complete real file IO or image codec decoding.
/// In-memory SharedPreferences stand-in: AppLockService only needs
/// getString/setString/remove; everything else is explicitly unsupported.
class _MemoryPrefs implements SharedPreferences {
  final Map<String, String> _store = <String, String>{};

  @override
  String? getString(String key) => _store[key];

  @override
  Future<bool> setString(String key, String value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _store.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in tests');
}

/// Biometric fake for widget tests: never available, never prompts.
class _LockedOutBiometric implements BiometricAuth {
  @override
  Future<bool> canAuthenticate() async => false;

  @override
  Future<bool> authenticate(String localizedReason) async => false;
}

List<Override> testOverrides({
  LlmClient? llm,
  required Directory dir,
  AppSettings? settings,
  bool writeScreenshots = true,
  List<ContextEntry>? contexts,
  List<PromptEntry>? prompts,
  FakeJsRuntime? js,
}) => <Override>[
  settingsRepositoryProvider.overrideWithValue(
    MemorySettingsRepository(settings),
  ),
  contextRepositoryProvider.overrideWithValue(
    MemoryContextRepository(contexts),
  ),
  promptRepositoryProvider.overrideWithValue(MemoryPromptRepository(prompts)),
  documentsDirProvider.overrideWithValue(() async => dir),
  if (llm != null) llmClientProvider.overrideWithValue(llm),
  // Widget tests run in a fake-async zone: awaiting the real method
  // channel would hang forever (the engine reply never arrives inside
  // the zone). Always plug in the recording fake instead; tests that
  // assert on the background hold override it again explicitly.
  backgroundRunServiceProvider.overrideWithValue(RecordingBackgroundRun()),
  appLockServiceProvider.overrideWith(
    (Ref ref) =>
        AppLockService(prefs: _MemoryPrefs(), biometric: _LockedOutBiometric()),
  ),
  browserAutomationProvider.overrideWithValue(
    FakeBrowserAutomation(
      '${dir.path}${Platform.pathSeparator}shots',
      writeScreenshot: writeScreenshots,
    ),
  ),
  // The real JS runtime spins up a headless WebView — never available in
  // the test zone. Every test gets a deterministic fake by default.
  jsRuntimeProvider.overrideWithValue(js ?? FakeJsRuntime()),
];
