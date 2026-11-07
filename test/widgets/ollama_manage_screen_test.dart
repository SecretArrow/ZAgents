import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zagents/di.dart';
import 'package:zagents/main.dart';
import 'package:zagents/models/local_model.dart';
import 'package:zagents/services/local_ai/llm_server_controller.dart'
    show FakeLlmServerPlatform;
import 'package:zagents/services/local_ai/local_model_store.dart'
    show MemoryLocalModelRepository;
import 'package:zagents/services/local_ai/model_downloader.dart'
    show DownloadProgress, DownloadStatus, DownloadQueueController;
import 'package:zagents/ui/screens/ollama_manage_screen.dart';

import '../../test/support/test_doubles.dart';

/// Recording stand-in for the download queue: starts with [initial] rows
/// (rendered by the Downloads tab) and records everything enqueued through
/// the Catalog buttons. No network, no disk — the real controller would
/// resolve registry refs over http.
class _FakeDownloadQueueController extends DownloadQueueController {
  _FakeDownloadQueueController([
    this.initial = const <DownloadProgress>[],
  ]);

  final List<DownloadProgress> initial;
  final List<LocalModelEntry> enqueued = <LocalModelEntry>[];

  @override
  List<DownloadProgress> build() => initial;

  @override
  Future<String> modelsDirPath() async => '/tmp/local_models';

  @override
  Future<void> enqueue(LocalModelEntry entry) async {
    enqueued.add(entry);
  }

  @override
  Future<void> pause(String modelId) async {}

  @override
  Future<void> resume(String modelId) async {}

  @override
  Future<void> cancel(String modelId) async {}

  @override
  void clearFinished() {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_ollama_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 15),
  );

  /// v1.49.6: feedback arrives as a centered modal dialog — acknowledge it
  /// via the OK button so the dialog barrier cannot swallow the next tap.
  Future<void> dismissAppMessage(WidgetTester tester) async {
    final Finder ok = find.byKey(const Key('app-message-ok'));
    if (ok.evaluate().isNotEmpty) {
      await tester.tap(ok);
      await settle(tester);
    }
  }

  /// The vertical catalog list. Two disambiguations: the screen owns the
  /// TabBarView's horizontal PageView scrollable (so a global
  /// `find.byType(Scrollable).first` would drag TABS, not the list), and
  /// the catalog subtree itself contains the custom-URL TextField's own
  /// horizontal Scrollable — the list's Scrollable is its ANCESTOR, so
  /// traversal reports it first and `.first` is unambiguous.
  Finder catalogScrollable() => find
      .descendant(
        of: find.byKey(const Key('ollama-catalog-list')),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Pumps the app, navigates Settings → Local AI tile, and lands on the
  /// Ollama Manage screen with the in-memory model store pre-seeded with
  /// [installed], the scriptable platform fake and a recording download
  /// queue; returns the container. The REAL server controller runs against
  /// the fake platform (no method channel inside the test zone).
  Future<ProviderContainer> openOllamaScreen(
    WidgetTester tester, {
    List<LocalModelEntry> installed = const <LocalModelEntry>[],
    FakeLlmServerPlatform? platform,
    _FakeDownloadQueueController? queue,
    List<DownloadProgress> downloads = const <DownloadProgress>[],
  }) async {
    late ProviderContainer container;
    final FakeLlmServerPlatform platformFake =
        platform ?? FakeLlmServerPlatform();
    final _FakeDownloadQueueController queueController =
        queue ?? _FakeDownloadQueueController(downloads);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...testOverrides(dir: tempDir),
          localModelRepositoryProvider.overrideWithValue(
            MemoryLocalModelRepository(
              LocalModelState(installed: installed),
            ),
          ),
          llmServerPlatformProvider.overrideWithValue(platformFake),
          downloadQueueProvider.overrideWith(() => queueController),
        ],
        child: Builder(
          builder: (BuildContext context) {
            container = ProviderScope.containerOf(context);
            return const ZAgentsApp();
          },
        ),
      ),
    );
    await tester.pump();

    // Navigate: Settings tab → the Local AI tile sits right below the
    // Cron jobs section (lazy ListView — reveal it before tapping).
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('ollama-manage-tile')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('ollama-manage-tile')));
    await settle(tester);
    expect(find.byType(OllamaManageScreen), findsOneWidget);
    return container;
  }

  testWidgets('renders all four tabs and switches between them', (
    WidgetTester tester,
  ) async {
    await openOllamaScreen(tester);

    // All four tabs are in the AppBar with their contract keys.
    expect(find.byKey(const Key('ollama-tab-server')), findsOneWidget);
    expect(find.byKey(const Key('ollama-tab-catalog')), findsOneWidget);
    expect(find.byKey(const Key('ollama-tab-installed')), findsOneWidget);
    expect(find.byKey(const Key('ollama-tab-downloads')), findsOneWidget);
    // The Server tab is active first — its list is on screen (the
    // TabBarView builds pages lazily; at most a cached neighbor exists).
    expect(find.byKey(const Key('ollama-server-list')), findsOneWidget);
    expect(
      find.byKey(const Key('ollama-server-list')).hitTestable(),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('ollama-tab-catalog')));
    await settle(tester);
    expect(find.byKey(const Key('ollama-catalog-list')), findsOneWidget);
    expect(find.byKey(const Key('ollama-custom-url')), findsOneWidget);
    expect(find.byKey(const Key('ollama-import')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ollama-tab-installed')));
    await settle(tester);
    expect(find.byKey(const Key('ollama-installed-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ollama-tab-downloads')));
    await settle(tester);
    expect(find.byKey(const Key('ollama-downloads-empty')), findsOneWidget);
  });

  testWidgets(
    'server tab shows the runtime-unavailable banner when the platform '
    'reports runtimeAvailable: false',
    (WidgetTester tester) async {
      // An armeabi-v7a-style build: the runtime .so is missing → the real
      // controller's refresh() maps it to the `unavailable` status.
      await openOllamaScreen(
        tester,
        platform: FakeLlmServerPlatform(available: false),
      );

      expect(find.byKey(const Key('ollama-unavailable-banner')), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      final FilledButton start = tester.widget<FilledButton>(
        find.byKey(const Key('ollama-start')),
      );
      expect(start.onPressed, isNull);
      expect(find.byKey(const Key('ollama-stop')), findsNothing);
      // No models installed: the empty hint + catalog shortcut render.
      expect(find.byKey(const Key('ollama-model-empty')), findsOneWidget);
      expect(find.byKey(const Key('ollama-go-catalog')), findsOneWidget);
    },
  );

  testWidgets(
    'catalog renders the model cards; tier-1 enqueues directly, '
    'upper-bound asks first',
    (WidgetTester tester) async {
      final _FakeDownloadQueueController queue = _FakeDownloadQueueController();
      await openOllamaScreen(tester, queue: queue);

      await tester.tap(find.byKey(const Key('ollama-tab-catalog')));
      await settle(tester);

      // First catalog card (tier 1) is on screen; its Download button
      // enqueues without any confirmation.
      expect(find.byKey(const Key('ollama-catalog-qwen3:0.6b')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ollama-download-qwen3:0.6b')));
      await settle(tester);
      expect(queue.enqueued, hasLength(1));
      expect(queue.enqueued.single.ollamaRef, 'qwen3:0.6b');
      expect(queue.enqueued.single.source, LocalModelSource.catalog);
      expect(queue.enqueued.single.name, 'qwen3:0.6b');
      expect(queue.enqueued.single.fileName, endsWith('.gguf'));

      // Acknowledge the queued feedback dialog before the next tap.
      await dismissAppMessage(tester);

      // The upper-bound card sits deep in the lazy list — drag it into
      // view (dragUntilVisible builds offscreen items).
      await tester.dragUntilVisible(
        find.byKey(const Key('ollama-download-minicpm5-2b')),
        catalogScrollable(),
        const Offset(0, -250),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('ollama-download-minicpm5-2b')));
      await settle(tester);
      // Heavy tier: the OOM-risk confirmation dialog appears first.
      expect(find.byKey(const Key('ollama-risk-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ollama-risk-confirm')));
      await settle(tester);
      expect(queue.enqueued, hasLength(2));
      expect(queue.enqueued.last.ollamaRef, 'minicpm5-2b');
    },
  );

  testWidgets(
    'installed tab lists seeded models and deletes after confirmation',
    (WidgetTester tester) async {
      const LocalModelEntry entry = LocalModelEntry(
        id: 'm-1',
        name: 'Qwen3 0.6B',
        source: LocalModelSource.catalog,
        ollamaRef: 'qwen3:0.6b',
        fileName: 'm-1.gguf',
        sizeBytes: 548577280,
        addedAtMs: 1736500000000,
      );
      final ProviderContainer container = await openOllamaScreen(
        tester,
        installed: const <LocalModelEntry>[entry],
      );

      await tester.tap(find.byKey(const Key('ollama-tab-installed')));
      await settle(tester);
      expect(find.byKey(const Key('ollama-installed-m-1')), findsOneWidget);
      expect(find.text('Qwen3 0.6B'), findsOneWidget);
      expect(find.byKey(const Key('ollama-start-m-1')), findsOneWidget);
      expect(find.byKey(const Key('ollama-export-m-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ollama-delete-m-1')));
      await settle(tester);
      expect(find.byKey(const Key('ollama-delete-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ollama-delete-confirm')));
      await settle(tester);
      expect(container.read(localModelsProvider).installed, isEmpty);
      expect(find.byKey(const Key('ollama-installed-empty')), findsOneWidget);
    },
  );

  testWidgets('downloads tab renders live progress rows with actions', (
    WidgetTester tester,
  ) async {
    const List<DownloadProgress> rows = <DownloadProgress>[
      DownloadProgress(
        modelId: 'd1',
        modelName: 'qwen3:0.6b',
        receivedBytes: 314572800,
        totalBytes: 548577280,
        status: DownloadStatus.running,
      ),
      DownloadProgress(
        modelId: 'd2',
        modelName: 'smollm2:135m',
        receivedBytes: 0,
        totalBytes: 0,
        status: DownloadStatus.queued,
      ),
    ];
    await openOllamaScreen(tester, downloads: rows);

    await tester.tap(find.byKey(const Key('ollama-tab-downloads')));
    await settle(tester);
    expect(find.byKey(const Key('ollama-download-row-d1')), findsOneWidget);
    expect(find.byKey(const Key('ollama-download-row-d2')), findsOneWidget);
    expect(find.text('qwen3:0.6b'), findsOneWidget);
    // "x of y MB" progress text + status chips.
    expect(find.text('300 of 523 MB'), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
    // One indicator per row (indeterminate when the total is unknown).
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    // Running + queued rows expose pause and cancel; nothing finished yet,
    // so the clear-finished action stays hidden.
    expect(find.byKey(const Key('ollama-pause-d1')), findsOneWidget);
    expect(find.byKey(const Key('ollama-cancel-d1')), findsOneWidget);
    expect(find.byKey(const Key('ollama-pause-d2')), findsOneWidget);
    expect(find.byKey(const Key('ollama-clear-finished')), findsNothing);
  });
}
