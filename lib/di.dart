import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'models/models.dart';
import 'services/agent_controller.dart';
import 'services/app_lock_service.dart';
import 'services/backup_service.dart';
import 'services/browser_automation.dart';
import 'services/browser_session_isolation.dart';
import 'services/chat_store.dart';
import 'services/context_repository.dart';
import 'services/js_runtime.dart';
import 'services/llm_client.dart';
import 'services/model_catalog.dart';
import 'services/module_registry.dart';
import 'services/module_runtime.dart';
import 'services/npm_service.dart';
import 'services/prompt_repository.dart';
import 'services/session_export.dart';
import 'services/session_sandbox.dart';
import 'services/settings_repository.dart';
import 'services/tool_executor.dart';
import 'services/user_agent_manager.dart';
import 'services/web_fetcher.dart';

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

/// Must be overridden in main() with a real repository.
final promptRepositoryProvider = Provider<PromptRepository>((ref) {
  throw UnimplementedError(
    'promptRepositoryProvider must be overridden in main()',
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
  final webview = WebViewAutomation(
    pickUserAgent: () {
      final AppSettings settings = ref.read(settingsProvider);
      return ref.read(userAgentManagerProvider).resolve(settings.uaMode);
    },
  );
  // Private-window guarantee (v1.19.0): cookies, web storage and login
  // state are swapped per chat session under a lock and persisted inside
  // each session's own sandbox — one chat never sees another chat's login.
  final isolated = IsolatedBrowserAutomation(
    inner: webview,
    store: BrowserStateStore(
      rootFor: ref.watch(sessionSandboxProvider).rootFor,
    ),
    cookies: const InAppCookieGateway(),
  );
  ref.onDispose(webview.dispose);
  return isolated;
});

/// Resolves the User-Agent applied to embedded browser surfaces according
/// to Settings → User Agent (sticky pick, no per-request rotation).
final userAgentManagerProvider = Provider<UserAgentManager>(
  UserAgentManager.new,
);

/// Hidden-WebView JavaScript runtime for the embedded Node.js-style tools.
/// Serialized: node_run calls from parallel chat sessions execute one at a
/// time, and every run boots a fresh JS context (no module cache, window
/// globals or registry can survive from one chat into another).
final jsRuntimeProvider = Provider<JsRuntime>((ref) {
  final runtime = WebViewJsRuntime(
    resolveUserAgent: () {
      final AppSettings settings = ref.read(settingsProvider);
      return ref.read(userAgentManagerProvider).resolve(settings.uaMode).ua;
    },
  );
  ref.onDispose(runtime.dispose);
  return SerializedJsRuntime(runtime);
});

final npmServiceProvider = Provider<NpmService>(
  (ref) => NpmService(resolveBaseDir: ref.watch(documentsDirProvider)),
);

/// Installs/lists/removes chat modules (plugins) under `<docs>/modules`.
final moduleRegistryProvider = Provider<ModuleRegistry>(
  (ref) => ModuleRegistry(resolveBaseDir: ref.watch(documentsDirProvider)),
);

/// Official SDK shim source (`require('zagents-sdk')`) shipped as an app
/// asset. Overridden in tests.
final moduleSdkSourceProvider = FutureProvider<String>(
  (ref) => rootBundle.loadString('assets/modules/zagents-sdk.js'),
);

/// Per-chat module sandbox runtime: every (chat, module) pair gets its
/// own state directory, storage file, permission set and fresh JS
/// context — the private-window guarantee extended to plugins.
final moduleRuntimeProvider = Provider<ModuleRuntime>(
  (ref) => ModuleRuntime(
    js: ref.watch(jsRuntimeProvider),
    resolveSandboxRoot: ref.watch(sessionSandboxProvider).rootFor,
    resolveModulePath: (String name) async =>
        (await ref.read(moduleRegistryProvider).get(name))?.path,
    resolveSdkSource: () async =>
        (await ref
                .read(moduleSdkSourceProvider.future)
                .catchError((Object _) => ''))
            .trim(),
    resolveNpmModulesRoot: () async =>
        ref.read(moduleRegistryProvider).npmModulesRoot(),
    httpTransport: (String url, String method, String? body) async {
      // Outbound transport for `zagents.http` (permission + host
      // allowlist already enforced by ModuleRuntime before this call).
      final http.Client client = http.Client();
      try {
        final Uri uri = Uri.parse(url);
        final Map<String, String> headers = <String, String>{
          'User-Agent': ref
              .read(userAgentManagerProvider)
              .resolve(ref.read(settingsProvider).uaMode)
              .ua,
        };
        final String verb = method.toUpperCase();
        final http.Response response = switch (verb) {
          'POST' => await client.post(uri, headers: headers, body: body ?? ''),
          'PUT' => await client.put(uri, headers: headers, body: body ?? ''),
          'DELETE' => await client.delete(uri, headers: headers),
          _ => await client.get(uri, headers: headers),
        };
        return <String, dynamic>{
          'status': response.statusCode,
          'body': response.body,
        };
      } catch (_) {
        return const <String, dynamic>{'status': 0, 'body': ''};
      } finally {
        client.close();
      }
    },
  ),
);

/// Per-session isolated workspaces ("private window" per chat): uploads,
/// agent files, archives and screenshots live under
/// `documents/sessions/<sessionId>/` and never mix between sessions.
final sessionSandboxProvider = Provider<SessionSandbox>((ref) {
  return SessionSandbox(resolveDocumentsDir: ref.watch(documentsDirProvider));
});

/// Must be overridden in main() — SharedPreferences is async at boot.
final appLockPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('appLockPrefsProvider must be overridden in main()');
});

/// App lock service (v1.18.0): PIN hashing/verification + biometric prompt.
final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(prefs: ref.watch(appLockPrefsProvider));
});

/// Whether the Flutter app is currently visible to the user. Updated by
/// the lifecycle observer in LockGate; the agent loop reads it when a run
/// finishes to decide whether a completion notification is needed.
final appInForegroundProvider = StateProvider<bool>((ref) => true);

/// Id of the chat session currently open in the UI (null = none yet).
final activeSessionIdProvider = Provider<String?>(
  (ref) => ref.watch(chatControllerProvider).sessionId,
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

/// Encrypted whole-app backup & restore (v1.17.0): settings + chats +
/// context entries into one passphrase-protected .zabak file.
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    store: ref.watch(chatStoreProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    contextRepository: ref.watch(contextRepositoryProvider),
    resolveBaseDir: ref.watch(documentsDirProvider),
  );
});

final toolExecutorProvider = Provider<ToolExecutor>((ref) {
  final SessionSandbox sandbox = ref.watch(sessionSandboxProvider);
  return ToolExecutor(
    browser: ref.watch(browserAutomationProvider),
    // Session-scoped root: file tools only ever see their own chat's
    // workspace (null falls back to the legacy documents root).
    resolveBaseDir: sandbox.rootFor,
    isAutomationEnabled: () => ref.read(settingsProvider).automationEnabled,
    js: ref.watch(jsRuntimeProvider),
    npm: ref.watch(npmServiceProvider),
    fsFor: sandbox.fsFor,
    // Server-side fetcher behind the `web_fetch` tool; it carries the same
    // User-Agent identity the embedded browser uses.
    fetcher: WebFetcher(
      resolveUserAgent: () {
        final AppSettings settings = ref.read(settingsProvider);
        return ref.read(userAgentManagerProvider).resolve(settings.uaMode).ua;
      },
    ),
  );
});

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

/// Installed chat modules (reactive across the Modules screen, the
/// /plugins menu and the new-chat chips).
final moduleListProvider = FutureProvider<List<ChatModule>>(
  (ref) => ref.watch(moduleRegistryProvider).listInstalled(),
);

/// Current Context Manager entries (reactive across screens).
final contextListProvider = FutureProvider<List<ContextEntry>>(
  (ref) async => ref.watch(contextRepositoryProvider).load(),
);

/// Prompt Library entries (reactive across screens).
final promptListProvider = FutureProvider<List<PromptEntry>>(
  (ref) => ref.watch(promptRepositoryProvider).load(),
);
