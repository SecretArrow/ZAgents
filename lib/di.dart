import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'models/models.dart';
import 'services/agent_composer.dart';
import 'services/agent_controller.dart';
import 'services/app_lock_service.dart';
import 'services/backup_service.dart';
import 'services/browser_automation.dart';
import 'services/browser_session_isolation.dart';
import 'services/chat_store.dart';
import 'services/context_repository.dart';
import 'services/device_export.dart';
import 'services/device_shell.dart';
import 'services/js_runtime.dart';
import 'services/llm_client.dart';
import 'services/model_catalog.dart';
import 'services/module_registry.dart';
import 'services/module_runtime.dart';
import 'services/npm_service.dart';
import 'services/prompt_repository.dart';
import 'services/session_export.dart';
import 'services/script_fetch_proxy.dart';
import 'services/session_sandbox.dart';
import 'services/skill_registry.dart';
import 'services/settings_repository.dart';
import 'services/subagents.dart';
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
  // Multi-context engine (v1.37.0): every chat session browses in its own
  // headless WebView, and every parallel subagent (fan of subagents) gets
  // ANOTHER one via withContext — browser work no longer queues behind a
  // single shared engine. The private-window guarantee (v1.19.0) is kept:
  // cookies, web storage and login state are captured per context and
  // persisted inside each session's own sandbox — one chat never sees
  // another chat's login.
  final manager = ContextualBrowserAutomation(
    makeInner: () => WebViewAutomation(
      pickUserAgent: () {
        final AppSettings settings = ref.read(settingsProvider);
        return ref.read(userAgentManagerProvider).resolve(settings.uaMode);
      },
    ),
    store: BrowserStateStore(
      rootFor: ref.watch(sessionSandboxProvider).rootFor,
    ),
    cookies: const InAppCookieGateway(),
    maxContexts: 4,
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Resolves the User-Agent applied to embedded browser surfaces according
/// to Settings → User Agent (sticky pick, no per-request rotation).
final userAgentManagerProvider = Provider<UserAgentManager>(
  UserAgentManager.new,
);

/// v1.38.0: REAL network for the embedded JS runtime (`node_run`, skill
/// scripts, isomorphic-git over HTTPS). Before this the `window.fetch`
/// shim rejected every call ("fetch is unavailable") — Web3/wallet skills
/// and git-over-HTTPS silently could not work.
final scriptFetchProxyProvider = Provider<ScriptFetchProxy>((ref) {
  final proxy = ScriptFetchProxy(
    resolveUserAgent: () {
      final AppSettings settings = ref.read(settingsProvider);
      return ref.read(userAgentManagerProvider).resolve(settings.uaMode).ua;
    },
  );
  ref.onDispose(proxy.dispose);
  return proxy;
});

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
    fetchProxy:
        (
          String url,
          String method,
          String? body, {
          Map<String, String> headers = const <String, String>{},
          bool bodyIsBase64 = false,
        }) {
          return ref
              .read(scriptFetchProxyProvider)
              .call(
                url,
                method,
                body,
                headers: headers,
                bodyIsBase64: bodyIsBase64,
              );
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

/// v1.38.0: installs/lists/configures/removes external agent skills under
/// `<docs>/skills` — global, shared by every chat (install once, use
/// everywhere).
final skillRegistryProvider = Provider<SkillRegistry>(
  (ref) => SkillRegistry(resolveBaseDir: ref.watch(documentsDirProvider)),
);

/// Native shell runner for the module `device` capability (v1.31.0):
/// rooted-device commands behind the Settings → Modules master switch.
final deviceShellServiceProvider = Provider<DeviceShellService>(
  (ref) => DeviceShellService(),
);

/// Official SDK shim source (`require('zagents-sdk')`), shipped from the
/// canonical `sdk/` directory of the repository. Overridden in tests.
final moduleSdkSourceProvider = FutureProvider<String>(
  (ref) => rootBundle.loadString('sdk/zagents-sdk.js'),
);

/// Per-chat module sandbox runtime: every (chat, module) pair gets its
/// own state directory, storage file, permission set and fresh JS
/// context — the private-window guarantee extended to plugins.
///
/// `agentCompose` implements `zagents.agent.compose`: the module asks the
/// CHAT'S OWN agent (provider/baseUrl/apiKey/model from Settings) to
/// compose one sentence from the live context it supplies; the request
/// runs through [AgentComposer]'s regulated gate (one casual English
/// sentence, no forbidden characters, word cap, no repeats) before the
/// module ever sees the text.
final moduleRuntimeProvider = Provider<ModuleRuntime>(
  (ref) => ModuleRuntime(
    js: ref.watch(jsRuntimeProvider),
    resolveSandboxRoot: ref.watch(sessionSandboxProvider).rootFor,
    // Cross-chat setup-form prefill scan (v1.33.0): the parent of every
    // per-chat sandbox, so a new chat can prefill a module's setup form
    // with the user's last submitted values for that module.
    resolveSessionsRoot: ref.watch(sessionSandboxProvider).sessionsRoot,
    resolveModulePath: (String name) async =>
        (await ref.read(moduleRegistryProvider).get(name))?.path,
    resolveSdkSource: () async =>
        (await ref
                .read(moduleSdkSourceProvider.future)
                .catchError((Object _) => ''))
            .trim(),
    resolveNpmModulesRoot: () async =>
        ref.read(moduleRegistryProvider).npmModulesRoot(),
    // Modules present the SAME identity the user picked in Settings →
    // User Agent — exposed read-only as zagents.info.userAgent and sent
    // (un-overridable) on every zagents.http request.
    resolveUserAgent: () {
      final AppSettings settings = ref.read(settingsProvider);
      return ref.read(userAgentManagerProvider).resolve(settings.uaMode).ua;
    },
    // v1.31.0 — module device commands (zagents.device.shell): the
    // manifest `device` permission gates the JS side, this settings
    // master switch gates the bridge, and the native channel is only
    // ever reached through both. Read per call so the toggle is live.
    deviceCommandsEnabled: () =>
        ref.read(settingsProvider).deviceCommandsEnabled,
    deviceShell: (String command, bool root, int timeoutMs) => ref
        .read(deviceShellServiceProvider)
        .run(command: command, root: root, timeoutMs: timeoutMs),
    // v1.32.0 — read-only airplane probe (zagents.device.airplane): no
    // root, no master switch; null on non-Android/test platforms.
    airplaneProbe: () =>
        ref.read(deviceShellServiceProvider).readAirplaneMode(),
    httpTransport:
        (
          String url,
          String method,
          String? body,
          Map<String, String> moduleHeaders, {
          int? timeoutMs,
          bool headOnly = false,
        }) async {
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
              ...moduleHeaders,
            };
            final http.Request request = http.Request(method.toUpperCase(), uri)
              ..headers.addAll(headers)
              ..followRedirects = true;
            if (body != null) request.body = body;
            Future<http.StreamedResponse> send() => client.send(request);
            final http.StreamedResponse streamed = timeoutMs != null
                ? await send().timeout(Duration(milliseconds: timeoutMs))
                : await send();
            // headOnly: the caller only needs the status line + headers (SSE
            // kick-off) — cancel the body stream so a long-lived server push
            // cannot stall the module run.
            final String responseBody = headOnly
                ? ''
                : await streamed.stream.bytesToString();
            final Map<String, String> responseHeaders = <String, String>{
              for (final MapEntry<String, String> h in streamed.headers.entries)
                h.key.toLowerCase(): h.value,
            };
            return <String, dynamic>{
              'status': streamed.statusCode,
              'body': responseBody,
              'headers': responseHeaders,
            };
          } on TimeoutException {
            return const <String, dynamic>{
              'status': 0,
              'body': '',
              'headers': <String, String>{},
            };
          } catch (_) {
            return const <String, dynamic>{
              'status': 0,
              'body': '',
              'headers': <String, String>{},
            };
          } finally {
            client.close();
          }
        },
    agentCompose: (AgentComposeRequest request) async {
      final AppSettings settings = ref.read(settingsProvider);
      if (settings.apiKey.trim().isEmpty) {
        throw const AgentComposeException('No API key configured in Settings');
      }
      if (settings.model.trim().isEmpty) {
        throw const AgentComposeException('No model configured in Settings');
      }
      return AgentComposer(llm: ref.read(llmClientProvider)).compose(
        request: request,
        config: LlmConfig(
          baseUrl: settings.baseUrl,
          apiKey: settings.apiKey,
          model: settings.model,
        ),
      );
    },
  ),
);

/// Per-session isolated workspaces ("private window" per chat): uploads,
/// agent files, archives and screenshots live under
/// `documents/sessions/<sessionId>/` and never mix between sessions.
final sessionSandboxProvider = Provider<SessionSandbox>((ref) {
  return SessionSandbox(resolveDocumentsDir: ref.watch(documentsDirProvider));
});

/// Copies a chat's workspace folder to the device file manager
/// (v1.29.0): MediaStore on Android 10+, zip + share sheet below.
final deviceExportServiceProvider = Provider<DeviceExportService>(
  (ref) => DeviceExportService(),
);

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
  // Fan-of-subagents runner: shares the executor itself for nested tool
  // calls (the late local resolves the constructor chicken-and-egg) and
  // reads the user's provider/model settings per spawn.
  late final ToolExecutor executor;
  executor = ToolExecutor(
    browser: ref.watch(browserAutomationProvider),
    // Session-scoped root: file tools only ever see their own chat's
    // workspace (null falls back to the legacy documents root).
    resolveBaseDir: sandbox.rootFor,
    isAutomationEnabled: () => ref.read(settingsProvider).automationEnabled,
    js: ref.watch(jsRuntimeProvider),
    npm: ref.watch(npmServiceProvider),
    fsFor: sandbox.fsFor,
    // Module doctor tools (module_list/read/export/stage_repair): the
    // registry is the ONLY doorway to installed modules, and the repair
    // tool merely stages a user-confirmed install card.
    modules: ref.watch(moduleRegistryProvider),
    // v1.38.0 — skill tools (install/list/info/config/remove/run): the
    // registry is the only doorway to installed skills.
    skills: ref.watch(skillRegistryProvider),
    // Per-chat setup state for module_list (v1.33.0): the agent sees
    // whether each module's setup form is already completed for THIS
    // chat — so it stops asking for credentials the user already gave.
    moduleRuntime: ref.watch(moduleRuntimeProvider),
    subagents: SubagentRunner(
      llm: ref.watch(llmClientProvider),
      resolveConfig: () {
        final AppSettings settings = ref.read(settingsProvider);
        return LlmConfig(
          baseUrl: settings.baseUrl,
          apiKey: settings.apiKey,
          model: settings.model,
        );
      },
      executeTool:
          (
            String name,
            Map<String, dynamic> args,
            String? sessionId, {
            String? browserContext,
          }) => executor.execute(
            name,
            args,
            sessionId: sessionId,
            browserContext: browserContext,
          ),
    ),
    // Server-side fetcher behind the `web_fetch` tool; it carries the same
    // User-Agent identity the embedded browser uses.
    fetcher: WebFetcher(
      resolveUserAgent: () {
        final AppSettings settings = ref.read(settingsProvider);
        return ref.read(userAgentManagerProvider).resolve(settings.uaMode).ua;
      },
    ),
    // v1.32.0 — device_status tool: verified airplane state (no root) +
    // root availability, so the agent can confirm what the user claims
    // instead of trusting a blind "yes".
    deviceStatus: () => ref.read(deviceShellServiceProvider),
    // v1.38.1 — SKILL.md files bundled with the app binary behind
    // `skill_install builtin:<name>` (no network needed).
    bundledSkills: bundledSkills,
  );
  return executor;
});

/// SKILL.md contents bundled with the app binary (assets/skills/*),
/// loaded lazily and cached. A missing asset simply does not appear.
final Map<String, String> bundledSkillCache = <String, String>{};

Future<Map<String, String>> bundledSkills() async {
  if (bundledSkillCache.isNotEmpty) return bundledSkillCache;
  const List<String> names = <String>[
    'web3-wallet-basics',
    'binance-agentic-wallet',
  ];
  for (final String name in names) {
    try {
      bundledSkillCache[name] = await rootBundle.loadString(
        'assets/skills/$name/SKILL.md',
      );
    } catch (_) {
      // A missing bundled asset simply does not appear in the list.
    }
  }
  return bundledSkillCache;
}

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

/// v1.38.0: whether the user has the live Plan panel open — GLOBAL and
/// user-owned. Riverpod state, not widget-local: element teardown during
/// streaming, step transitions, run end or chat switching must never
/// close the panel behind the user's back. It survives chat switches on
/// purpose (each chat renders its own plan in it) and only the user's
/// toggle (thinking-footer icon or the panel's close button) changes it.
final planPanelOpenProvider = StateProvider<bool>((ref) => false);

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
