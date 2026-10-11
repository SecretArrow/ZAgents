import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zagents/di.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/browser_automation.dart';
import 'package:zagents/services/chat_store.dart';
import 'package:zagents/services/llm_client.dart';
import 'package:zagents/services/settings_repository.dart';

/// Minimal valid 1x1 PNG used as fake screenshot bytes.
const String tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Scripted LLM client for tests: returns queued turns in order
/// (last turn repeats when the queue is exhausted).
class FakeLlmClient implements LlmClient {
  FakeLlmClient(this.turns);

  final List<AssistantTurn> turns;
  int _index = 0;

  /// Wire messages captured for every call.
  final List<List<Map<String, dynamic>>> calls = <List<Map<String, dynamic>>>[];

  @override
  Future<AssistantTurn> complete({
    required LlmConfig config,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    void Function(String delta)? onDelta,
  }) async {
    calls.add(messages);
    final AssistantTurn turn =
        turns[_index < turns.length - 1 ? _index++ : turns.length - 1];
    if (turn.content.isNotEmpty && onDelta != null) {
      for (final String part in turn.content.split(' ')) {
        onDelta('$part ');
        await Future<void>.delayed(Duration.zero);
      }
    }
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
  }) async {
    calls.add('navigate:$url');
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
  Future<Map<String, dynamic>> click({String? selector, String? text}) async {
    calls.add('click:${text ?? selector}');
    return <String, dynamic>{'ok': true, 'clicked': text ?? selector ?? ''};
  }

  @override
  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear = true,
  }) async {
    calls.add('type:$text');
    return <String, dynamic>{'ok': true, 'typed': text};
  }

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
  }) async {
    calls.add('scroll:$direction:$amount');
    return <String, dynamic>{'ok': true, 'scrollY': amount};
  }

  @override
  Future<String?> screenshot({required String saveDir}) async {
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
  Future<String> extractText({int maxLength = 8000}) async {
    calls.add('extract');
    const String text =
        'Example Domain\nThis domain is for use in illustrative examples.';
    return text.length > maxLength ? text.substring(0, maxLength) : text;
  }

  @override
  Future<String> runJs(String code) async {
    calls.add('run_js:$code');
    return '"ok"';
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
}

/// Browser fake whose every method throws — used to prove the tool
/// executor degrades platform failures into error results instead of
/// crashing the agent loop.
class ThrowingBrowserAutomation implements BrowserAutomation {
  @override
  Future<BrowserPageInfo> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 25),
  }) async => throw const SocketException('browser exploded');

  @override
  Future<Map<String, dynamic>> click({String? selector, String? text}) async =>
      throw const SocketException('browser exploded');

  @override
  Future<Map<String, dynamic>> type(
    String text, {
    String? selector,
    bool clear = true,
  }) async => throw const SocketException('browser exploded');

  @override
  Future<Map<String, dynamic>> scroll({
    String direction = 'down',
    int amount = 800,
  }) async => throw const SocketException('browser exploded');

  @override
  Future<String?> screenshot({required String saveDir}) async =>
      throw const SocketException('browser exploded');

  @override
  Future<String> extractText({int maxLength = 8000}) async =>
      throw const SocketException('browser exploded');

  @override
  Future<String> runJs(String code) async =>
      throw const SocketException('browser exploded');

  @override
  Future<void> resetSession() async {}

  @override
  void dispose() {}
}

/// Standard test overrides for the app's provider scope.
///
/// Set [writeScreenshots] to false for widget tests: the fake-async zone
/// cannot complete real file IO or image codec decoding.
List<Override> testOverrides({
  LlmClient? llm,
  required Directory dir,
  AppSettings? settings,
  bool writeScreenshots = true,
}) => <Override>[
  settingsRepositoryProvider.overrideWithValue(
    MemorySettingsRepository(settings),
  ),
  documentsDirProvider.overrideWithValue(() async => dir),
  if (llm != null) llmClientProvider.overrideWithValue(llm),
  browserAutomationProvider.overrideWithValue(
    FakeBrowserAutomation(
      '${dir.path}${Platform.pathSeparator}shots',
      writeScreenshot: writeScreenshots,
    ),
  ),
];
