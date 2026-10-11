import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/main.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/model_catalog.dart';
import 'package:zagents/ui/widgets/model_picker.dart';

import '../../test/fakes/fakes.dart';

/// Scripted catalog: returns [models] or throws [error].
class FakeModelCatalog implements ModelCatalogClient {
  FakeModelCatalog({this.models = const <RemoteModel>[], this.error});

  final List<RemoteModel> models;
  final Object? error;

  int callCount = 0;

  @override
  Future<List<RemoteModel>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    callCount++;
    final Object? failure = error;
    if (failure != null) throw failure;
    return models;
  }

  @override
  List<RemoteModel> parseCatalog(String body) => models;
}

RemoteModel m(
  String id, {
  String? name,
  bool tools = false,
  bool free = false,
  int? ctx,
}) => RemoteModel(
  id: id,
  name: name ?? id,
  supportsTools: tools,
  isFree: free,
  contextLength: ctx,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_picker_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 25 models so the default page size (20) yields exactly 2 pages.
  List<RemoteModel> bigCatalog() => <RemoteModel>[
    for (var i = 0; i < 25; i++)
      m('vendor/model-${i.toString().padLeft(2, '0')}'),
  ];

  /// The home-screen model chip shows the same text as catalog tiles, so
  /// every text assertion must be scoped to the picker sheet.
  Finder inSheet(Finder finder) =>
      find.descendant(of: find.byType(ModelPickerSheet), matching: finder);

  Future<ProviderContainer> openSheet(
    WidgetTester tester, {
    required FakeModelCatalog catalog,
    AppSettings? settings,
  }) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...testOverrides(
            dir: tempDir,
            // A distinct default model keeps the custom-model TextField from
            // colliding (find.text also matches EditableText) with catalog
            // tile texts like 'z-ai/glm-4.6'.
            settings:
                settings ??
                AppSettings(apiKey: 'sk-test', model: 'default/model-x'),
          ),
          modelCatalogProvider.overrideWithValue(catalog),
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

    await tester.tap(find.byKey(const Key('model-chip')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(find.byType(ModelPickerSheet), findsOneWidget);
    return container;
  }

  testWidgets('fetches and lists the live catalog with paging', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, catalog: FakeModelCatalog(models: bigCatalog()));

    // Page 1 of 2: indicator shown, first item visible, page-2 item absent.
    expect(inSheet(find.byKey(const Key('model-list-page-0'))), findsOneWidget);
    expect(inSheet(find.text('Page 1 of 2')), findsOneWidget);
    expect(inSheet(find.text('vendor/model-00')), findsOneWidget);
    expect(inSheet(find.text('vendor/model-20')), findsNothing);

    // Next page: first page-2 item becomes visible, page-1 item is gone.
    await tester.tap(find.byKey(const Key('model-page-next')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(inSheet(find.text('Page 2 of 2')), findsOneWidget);
    expect(inSheet(find.text('vendor/model-20')), findsOneWidget);
    expect(inSheet(find.text('vendor/model-00')), findsNothing);

    // Prev button returns to page 1.
    await tester.tap(find.byKey(const Key('model-page-prev')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(inSheet(find.text('Page 1 of 2')), findsOneWidget);
  });

  testWidgets('search box filters models by id and name', (
    WidgetTester tester,
  ) async {
    await openSheet(
      tester,
      catalog: FakeModelCatalog(
        models: <RemoteModel>[
          m('z-ai/glm-4.6', name: 'Z.AI: GLM 4.6'),
          m('google/gemini-2.5-pro', name: 'Gemini 2.5 Pro'),
          m('openai/gpt-4.1', name: 'OpenAI: GPT 4.1'),
        ],
      ),
    );

    await tester.enterText(
      find.byKey(const Key('model-search-field')),
      'gemini',
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    expect(inSheet(find.text('google/gemini-2.5-pro')), findsOneWidget);
    expect(inSheet(find.text('z-ai/glm-4.6')), findsNothing);
    expect(inSheet(find.text('openai/gpt-4.1')), findsNothing);

    // Search also matches display names.
    await tester.enterText(find.byKey(const Key('model-search-field')), 'GLM');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(inSheet(find.text('z-ai/glm-4.6')), findsOneWidget);

    // No match shows the empty state.
    await tester.enterText(find.byKey(const Key('model-search-field')), 'zzz');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(inSheet(find.text('No models match')), findsOneWidget);
  });

  testWidgets('filter chips narrow the catalog', (WidgetTester tester) async {
    await openSheet(
      tester,
      catalog: FakeModelCatalog(
        models: <RemoteModel>[
          m('paid/tool-model', tools: true),
          m('paid/plain-model'),
          m('x/free-model', free: true, tools: true),
        ],
      ),
    );

    // Tools filter: only tool-calling models remain.
    await tester.tap(find.byKey(const Key('model-filter-tools')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(inSheet(find.text('paid/tool-model')), findsOneWidget);
    expect(inSheet(find.text('x/free-model')), findsOneWidget);
    expect(inSheet(find.text('paid/plain-model')), findsNothing);

    // Free filter.
    await tester.tap(find.byKey(const Key('model-filter-free')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(inSheet(find.text('x/free-model')), findsOneWidget);
    expect(inSheet(find.text('paid/tool-model')), findsNothing);

    // Back to all.
    await tester.tap(find.byKey(const Key('model-filter-all')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(inSheet(find.text('paid/plain-model')), findsOneWidget);
  });

  testWidgets('selecting a model updates settings and closes the sheet', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openSheet(
      tester,
      catalog: FakeModelCatalog(
        models: <RemoteModel>[m('chosen/model-1'), m('chosen/model-2')],
      ),
    );
    expect(container.read(settingsProvider).model, isNot('chosen/model-1'));

    await tester.tap(inSheet(find.text('chosen/model-1')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    expect(container.read(settingsProvider).model, 'chosen/model-1');
    expect(find.byType(ModelPickerSheet), findsNothing);
  });

  testWidgets('without an API key shows the hint and offline suggestions', (
    WidgetTester tester,
  ) async {
    final FakeModelCatalog catalog = FakeModelCatalog(
      models: <RemoteModel>[m('should/not-be-fetched')],
    );
    await openSheet(
      tester,
      catalog: catalog,
      // Distinct model id so the custom-model TextField does not collide
      // with the 'z-ai/glm-4.6' suggestion tile (find.text also matches
      // EditableText values).
      settings: AppSettings(apiKey: '', model: 'default/model-x'),
    );

    expect(catalog.callCount, 0);
    expect(inSheet(find.textContaining('Enter your API key')), findsOneWidget);
    // Static fallback suggestions are visible.
    expect(inSheet(find.text('z-ai/glm-4.6')), findsOneWidget);
  });

  testWidgets('fetch failure shows error card with retry and suggestions', (
    WidgetTester tester,
  ) async {
    final FakeModelCatalog catalog = FakeModelCatalog(
      error: ModelCatalogException('Unauthorized — check the API key.'),
    );
    await openSheet(tester, catalog: catalog);

    expect(
      inSheet(find.text('Failed to load the model list.')),
      findsOneWidget,
    );
    expect(inSheet(find.textContaining('Unauthorized')), findsOneWidget);
    expect(inSheet(find.text('z-ai/glm-4.6')), findsOneWidget);

    // Retry re-invokes the catalog; the fake still throws, so the error
    // card remains visible.
    await tester.tap(find.byKey(const Key('model-retry-button')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(catalog.callCount, 2);
    expect(
      inSheet(find.text('Failed to load the model list.')),
      findsOneWidget,
    );
  });
}
