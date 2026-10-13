import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'models/models.dart';
import 'services/agent_controller.dart';
import 'services/browser_automation.dart';
import 'services/chat_store.dart';
import 'services/context_repository.dart';
import 'services/file_system_service.dart';
import 'services/js_runtime.dart';
import 'services/llm_client.dart';
import 'services/model_catalog.dart';
import 'services/npm_service.dart';
import 'services/session_export.dart';
import 'services/settings_repository.dart';
import 'services/tool_executor.dart';

/// Must be overridden in main() with a real repository.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError(
    'settingsRepositoryProvider must be overridden in main()',
  );
});

/// Must be overridden in main() with a real repository.
final contextRepositoryProvider = Provider<ContextRepository>((ref) {
  throw UnimplementedError(
    'contextRepositoryProvider must be overridden in main()',
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

final modelCatalogProvider = Provider<ModelCatalogClient>(
  (ref) => ModelCatalogClient(),
);

final browserAutomationProvider = Provider<BrowserAutomation>((ref) {
  final automation = WebViewAutomation();
  ref.onDispose(automation.dispose);
  return automation;
});

/// Hidden-WebView JavaScript runtime for the embedded Node.js-style tools.
final jsRuntimeProvider = Provider<JsRuntime>((ref) {
  final runtime = WebViewJsRuntime();
  ref.onDispose(runtime.dispose);
  return runtime;
});

final npmServiceProvider = Provider<NpmService>(
  (ref) => NpmService(resolveBaseDir: ref.watch(documentsDirProvider)),
);

final fileSystemServiceProvider = Provider<FileSystemService>(
  (ref) => FileSystemService(resolveBaseDir: ref.watch(documentsDirProvider)),
);

final chatStoreProvider = Provider<ChatStore>(
  (ref) => ChatStore(resolveBaseDir: ref.watch(documentsDirProvider)),
);

final sessionExporterProvider = Provider<SessionExporter>(
  (ref) => SessionExporter(
    store: ref.watch(chatStoreProvider),
    resolveBaseDir: ref.watch(documentsDirProvider),
  ),
);

final toolExecutorProvider = Provider<ToolExecutor>(
  (ref) => ToolExecutor(
    browser: ref.watch(browserAutomationProvider),
    resolveBaseDir: ref.watch(documentsDirProvider),
    isAutomationEnabled: () => ref.read(settingsProvider).automationEnabled,
    js: ref.watch(jsRuntimeProvider),
    npm: ref.watch(npmServiceProvider),
  ),
);

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

/// Session ids with an in-flight agent run — drives the "running" badges
/// in the drawer while the user is chatting in another session.
final runningSessionsProvider = StateProvider<Set<String>>((ref) => <String>{});

/// Pending (not yet sent) attachments staged in the composer.
final pendingAttachmentsProvider = StateProvider<List<ChatAttachment>>(
  (ref) => const <ChatAttachment>[],
);

final chatListProvider = FutureProvider<List<ChatSummary>>(
  (ref) => ref.watch(chatStoreProvider).listSummaries(),
);

/// Current Context Manager entries (reactive across screens).
final contextListProvider = FutureProvider<List<ContextEntry>>(
  (ref) async => ref.watch(contextRepositoryProvider).load(),
);
