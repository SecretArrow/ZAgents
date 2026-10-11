import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'models/models.dart';
import 'services/agent_controller.dart';
import 'services/browser_automation.dart';
import 'services/chat_store.dart';
import 'services/llm_client.dart';
import 'services/settings_repository.dart';
import 'services/tool_executor.dart';

/// Must be overridden in main() with a real repository.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError(
    'settingsRepositoryProvider must be overridden in main()',
  );
});

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Signature for a resolver that yields the app documents directory.
typedef DocumentsDirResolver = Future<Directory> Function();

/// Resolver for the app documents directory; overridden in tests.
final documentsDirProvider = Provider<DocumentsDirResolver>(
  (ref) => getApplicationDocumentsDirectory,
);

final llmClientProvider = Provider<LlmClient>((ref) => LlmClient());

final browserAutomationProvider = Provider<BrowserAutomation>((ref) {
  final automation = WebViewAutomation();
  ref.onDispose(automation.dispose);
  return automation;
});

final chatStoreProvider = Provider<ChatStore>(
  (ref) => ChatStore(resolveBaseDir: ref.watch(documentsDirProvider)),
);

final toolExecutorProvider = Provider<ToolExecutor>(
  (ref) => ToolExecutor(
    browser: ref.watch(browserAutomationProvider),
    resolveBaseDir: ref.watch(documentsDirProvider),
    isAutomationEnabled: () => ref.read(settingsProvider).automationEnabled,
  ),
);

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

final chatListProvider = FutureProvider<List<ChatSummary>>(
  (ref) => ref.watch(chatStoreProvider).listSummaries(),
);
