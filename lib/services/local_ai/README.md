# Local AI (Ollama Manage) — Frozen Contracts v1.51.0

Single source of truth for the Local AI feature (Route B: bundled llama.cpp
`llama-server` + Route D: external Ollama detection). All parallel workstreams
(Kotlin, Dart core, CI, UI) MUST implement exactly the public names below.
Private helpers are free. If a deviation is unavoidable, flag it clearly in
your report — never silently rename a contract symbol.

Runtime pin: llama.cpp **b12182**, built per-ABI by CI (CMake + NDK,
`c++_static`, 16 KB page alignment) into
`android/app/src/main/jniLibs/<abi>/libllamaserver.so` (NOT committed; the
directory is git-ignored). ABIs: `arm64-v8a`, `x86_64`. `armeabi-v7a` ships
without the runtime and the app must degrade gracefully (`runtimeAvailable`
→ false).

## 1. Platform channel `zagents/llmserver` (Kotlin implements / Dart calls)

All methods defensive: never throw across the channel; failures resolve to
safe defaults (`false` / `0` / empty list).

| Method | Args | Returns |
| --- | --- | --- |
| `runtimeAvailable` | – | `bool` — `libllamaserver.so` exists in `nativeLibraryDir` |
| `deviceTotalRamBytes` | – | `int` — `ActivityManager.MemoryInfo.totalMem` (0 unknown) |
| `startServer` | `modelPath: String`, `alias: String`, `port: int`, `contextSize: int`, `threads: int`, `extraArgs: List<String>` | `bool` |
| `stopServer` | – | `bool` |
| `isRunning` | – | `Map`: `running: bool`, `exitCode: int?`, `startedAtMs: int?` |
| `getLogs` | – | `List<String>` — last ≤200 stdout+stderr lines, oldest first |

`startServer` launches the dedicated foreground service `LlmServerService`
(type `dataSync`, notification channel `zagents_llm_server`, distinct
notification id) which spawns:
`<nativeLibraryDir>/libllamaserver.so -m <modelPath> --host 127.0.0.1
--port <port> --alias <alias> -c <contextSize> -t <threads> <extraArgs…>`
with `redirectErrorStream(true)`, a reader thread feeding a synchronized
ring buffer (200 lines). Process exit records `exitCode` and latches state
so `isRunning` reports it. `stopServer` destroys the process and stops the
service. Starting while already running returns `false`. Missing runtime
returns `false`. `threads <= 0` → Kotlin picks a sensible default
(`Runtime.availableProcessors() / 2`, min 1).

## 2. Dart core (`lib/models/local_model.dart` + `lib/services/local_ai/`)

### 2.1 `lib/models/local_model.dart`

```dart
enum LocalModelSource { catalog, customUrl, imported }
LocalModelSource localModelSourceFromName(String? name); // unknown → imported

class LocalModelEntry {
  const LocalModelEntry({
    required this.id, required this.name,
    this.source = LocalModelSource.imported,
    this.ollamaRef = '', this.customUrl = '', required this.fileName,
    this.sizeBytes = 0, this.sha256 = '',
    required this.addedAtMs, this.lastUsedAtMs,
  });
  final String id;        // uuid
  final String name;      // display name, also used as server alias
  final LocalModelSource source;
  final String ollamaRef; // e.g. 'qwen3:0.6b' ('' when not from registry)
  final String customUrl; // direct GGUF url ('' when not custom)
  final String fileName;  // '<id>.gguf' inside the models dir
  final int sizeBytes; final String sha256; final int addedAtMs; final int? lastUsedAtMs;
  // copyWith / toJson / fromJson — tolerant, CronJob style
}

class LocalModelState {
  const LocalModelState({
    this.installed = const <LocalModelEntry>[],
    this.serverPort = 11434, this.contextSize = 2048,
    this.threads = 0,             // 0 = auto
    this.autoStartOnBoot = false, // Fase 2
  });
  // copyWith / toJson / fromJson
}
```

### 2.2 Services (follow `cron_*` + `update_checker` + `telegram_sender` patterns)

- **`llm_server_controller.dart`**
  `enum LlmServerStatus { unavailable, stopped, starting, running, stopping, failed }`
  `class LlmServerState` — fields: `status`, `activeModelName`, `activeModelPath`,
  `port`, `message`, `logTail` (`List<String>`); `const` constructor with
  defaults (status `stopped`), `copyWith`.
  `abstract class LlmServerPlatform` — mirrors channel §1 (returns
  `Future<Map<String, dynamic>>` for `isRunning`, `Future<List<String>>` for
  `getLogs`).
  `class MethodChannelLlmServerPlatform implements LlmServerPlatform` —
  channel `zagents/llmserver`, every call wrapped in try/catch.
  `class FakeLlmServerPlatform implements LlmServerPlatform` — scriptable
  in-memory fake for tests.
  `class LlmServerController extends Notifier<LlmServerState>` — deps via
  `ref.read(llmServerPlatformProvider)` / `ref.read(llmHttpClientProvider)`;
  methods `Future<void> refresh()` (runtimeAvailable + isRunning + health →
  coherent status), `Future<bool> start({required String modelPath, required
  String modelName, int? port, int? contextSize, int? threads})` (status
  `starting` → launch → poll `GET http://127.0.0.1:<port>/health` until 200
  or 90 s timeout → `running` / `failed` with message + logTail), 
  `Future<bool> stop()`, `Future<void> pollNow()` (one health check for the
  UI timer). Health via injectable `http.Client`.

- **`ollama_registry_client.dart`**
  `class RegistryBlob { final String blobUrl; final String sha256; final int sizeBytes; }`
  `class OllamaRegistryException implements Exception`
  `class OllamaRegistryClient` — ctor `{http.Client? client}`; 
  `Future<RegistryBlob> resolve(String ref)`. `qwen3:0.6b` → repo
  `library/qwen3`, tag `0.6b`; `hf.co/user/repo:tag` → repo `hf.co/user/repo`.
  `GET https://registry.ollama.ai/v2/<repo>/manifests/<tag>` with
  `Accept: application/vnd.docker.distribution.manifest.v2+json,
  application/vnd.oci.image.manifest.v1+json`; pick the largest non-config
  layer; `blobUrl = https://registry.ollama.ai/v2/<repo>/blobs/<digest>`;
  `sha256` = digest minus `sha256:` prefix; `sizeBytes` = layer size.

- **`model_downloader.dart`**
  `enum DownloadStatus { queued, running, paused, completed, failed, canceled }`
  `class DownloadProgress` — fields `modelId`, `modelName`, `receivedBytes`,
  `totalBytes`, `status`, `error`; const ctor, `copyWith`.
  `class DownloadQueueController extends Notifier<List<DownloadProgress>>` —
  ctor `{http.Client? httpClient, Directory? modelsDir}` (null dir resolved
  lazily: `getExternalStorageDirectory()` → fallback
  `getApplicationDocumentsDirectory()`, subfolder `local_models`); methods
  `Future<void> enqueue(LocalModelEntry entry)` (resolve ref → URL+sha via
  registry client or direct custom URL; queue row + start), 
  `Future<void> pause(String modelId)`, `Future<void> resume(String modelId)`
  (HTTP `Range: bytes=<part>-`; 206 appends, 200 restarts), 
  `Future<void> cancel(String modelId)` (deletes `.part`),
  `void clearFinished()`, `Future<String> modelsDirPath()`. Streams progress;
  verifies sha256 when known (registry digest) via `crypto` streaming —
  mismatch → `failed` + delete. Writes `<dir>/<fileName>.part` → rename on
  success → fires `onCompleted(LocalModelEntry)` callback given by di
  (wired to `LocalModelsController.addInstalled`).

- **`local_model_store.dart`**
  `abstract class LocalModelRepository` — `LocalModelState load()` +
  `Future<void> save(LocalModelState)`.
  `class PrefsLocalModelRepository` — SharedPreferences key
  `zagents.localai.v1`, static `create()`, corrupt-store fallback to defaults
  (mirror `PrefsCronRepository`).
  `class MemoryLocalModelRepository`.
  `class LocalModelsController extends Notifier<LocalModelState>` — methods
  `addInstalled(LocalModelEntry)`, `removeInstalled(String id)` (also delete
  file), `markUsed(String id)`, `setServerConfig({int? port, int? contextSize,
  int? threads})`, `setAutoStartOnBoot(bool)`; persists via repository.

- **`local_model_io.dart`**
  `class LocalModelIo` — `Future<LocalModelEntry?> importFromFile({required
  String sourcePath, required String fileNameHint})` (copy into models dir,
  uuid id, name from hint minus `.gguf`, size + streaming sha256),
  `Future<bool> exportModel(LocalModelEntry entry)` (copy to tmp + 
  `share_plus`, follow `session_export.dart`), `Future<int> exportModels(
  List<LocalModelEntry>)` (Fase 2 bulk — single share), 
  `Future<void> deleteModelFile(LocalModelEntry)`.

- **`external_ollama_scanner.dart`**
  `class ExternalOllamaScan` — `host`, `ok`, `version`, `error`; const ctor.
  `class ExternalOllamaScanner` — ctor `{http.Client? client}`;
  `Future<ExternalOllamaScan> probe(String host)` (normalize scheme →
  `http://`, 2.5 s timeout, `GET /api/version`).

- **`model_catalog_data.dart`**
  `enum CatalogTier { tier1, tier2, upperBound }`
  `class CatalogModelEntry` — `ollamaRef`, `downloadBytes`, `ramEstBytes`,
  `contextTokens`, `tier`, `license`; `String get id => ollamaRef`.
  `const List<CatalogModelEntry> kLocalAiCatalog` — 14 entries (values from
  the approved proposal; MB = 1024²):
  tier1: `qwen3:0.6b` 523MB/40960/1.0GB Apache-2.0 · `gemma3:1b` 806MB/32768/
  1.2GB Gemma · `bonsai-2:2b` 911MB/262144/1.3GB · `gemma3:270m` 292MB/32768/
  0.7GB Gemma · `smollm2:135m` 271MB/8192/0.6GB Apache-2.0 ·
  `smollm2:360m` 726MB/8192/1.1GB Apache-2.0;
  tier2: `qwen2.5-coder:1.5b` 1014MB/32768/1.5GB Apache-2.0 ·
  `deepseek-r1:1.5b` 1153MB/131072/1.6GB MIT · `lfm3:1.7b` 1423MB/262144/
  1.6GB · `qwen3.5:0.8b` 1311MB/262144/1.7GB · `llama3.2:1b` 1365MB/131072/
  1.7GB Llama-Community · `qwen3:1.7b` 1468MB/40960/1.8GB Apache-2.0;
  upperBound (risky, OOM warning in UI): `minicpm5-2b` 1718MB/131072/2.2GB ·
  `bonsai-2:4b` 1718MB/262144/2.6GB.

### 2.3 `lib/di.dart` additions (S2 owns; exact names)

```dart
final localModelRepositoryProvider = Provider<LocalModelRepository>(/* throw, overridden in main() */);
final localModelsProvider = NotifierProvider<LocalModelsController, LocalModelState>(LocalModelsController.new);
final llmServerPlatformProvider = Provider<LlmServerPlatform>((ref) => MethodChannelLlmServerPlatform());
final llmHttpClientProvider = Provider<http.Client>((ref) => http.Client());
final llmServerProvider = NotifierProvider<LlmServerController, LlmServerState>(LlmServerController.new);
final downloadQueueProvider = NotifierProvider<DownloadQueueController, List<DownloadProgress>>(/* closure wiring onCompleted → localModelsProvider.addInstalled */);
final ollamaRegistryClientProvider = Provider<OllamaRegistryClient>((ref) => OllamaRegistryClient());
final externalOllamaScannerProvider = Provider<ExternalOllamaScanner>((ref) => ExternalOllamaScanner());
final localModelIoProvider = Provider<LocalModelIo>((ref) => LocalModelIo());
```
`lib/main.dart`: override `localModelRepositoryProvider` with
`await PrefsLocalModelRepository.create()` (same spot as the cron override).

## 3. UI contract (S4) — consumers use ONLY §2 symbols

- Settings tile BELOW the Cron jobs section: `Key('ollama-manage-tile')`,
  title/subtitle localized ("Ollama Manage" / "Local AI runtime compatible
  with Ollama" style), opens `OllamaManageScreen` (new route).
- `lib/ui/screens/ollama_manage_screen.dart` — `DefaultTabController`
  length 4, Keys `ollama-tab-server`, `ollama-tab-catalog`,
  `ollama-tab-installed`, `ollama-tab-downloads`:
  - **Server**: runtime-unavailable banner (armeabi-v7a / missing runtime),
    status card (status, active model, port), model dropdown (installed) +
    Start/Stop (`Key('ollama-start')` / `Key('ollama-stop')`), config fields
    (port / context / threads, saved via `setServerConfig`), log tail
    (monospace, refreshed by a 3 s `Timer` calling `pollNow` + log read),
    external-server probe row (`127.0.0.1:11434` default, editable host),
    device RAM line.
  - **Catalog**: card per `kLocalAiCatalog` entry (ref, size, RAM est,
    context, tier chip; `upperBound` gets a risk warning + confirm dialog),
    Download button (disabled when installed / already queued), custom-URL
    field + download (`Key('ollama-custom-url')`), Import-from-file button
    (`file_selector`, follows existing import patterns).
  - **Installed**: list with name/size/date; actions Export (share), Delete
    (confirm), Start-with-this-model.
  - **Downloads**: progress cards (`LinearProgressIndicator`, MB counters),
    pause/resume/cancel per row, Clear-finished.
- Local AI provider preset in `_defaultPresets()`: name `Local AI`,
  baseUrl `http://127.0.0.1:11434/v1`, empty apiKey, empty model, engine
  auto → built-in preset count becomes **10** (update
  `test/widgets/settings_test.dart`, comment `v1.51.0`).
- l10n: every user-facing string localized in **en + id + es**
  (`AppStringsEn`/`AppStringsId` in `app_strings.dart`, `AppStringsEs` in
  `app_strings_es.dart`), keys prefixed `ollama…`/`localAi…`; add a
  localization test block for the new keys (all three bundles).

## 4. CI contract (S3)

- New composite action `.github/actions/llama-runtime/action.yml`, input
  `abis` (space-separated) + `llama-tag` (default `b12182`); builds (cache
  keyed on tag+abi+ndk+action rev, restore early) and copies
  `llama-server` → `android/app/src/main/jniLibs/<abi>/libllamaserver.so`.
  CMake: NDK toolchain, `ANDROID_STL=c++_static`, `Release`,
  `-DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
  -DLLAMA_CURL=OFF`, linker flag `-Wl,-z,max-page-size=16384`,
  `ANDROID_PLATFORM=android-24`.
- `ci.yml`: inject runtime (x86_64 only) in `build-android` + `e2e` jobs
  before the flutter build/test steps.
- `release.yml`: inject `arm64-v8a x86_64` before the APK builds; verify
  both `.so` files exist (fail release otherwise).
- Fix `auto-release.yml` trigger typo `branches: ain]` → `branches: [main]`.
- `.gitignore`: ignore `android/app/src/main/jniLibs/` (S1 adds).
