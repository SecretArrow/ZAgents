import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zagents/di.dart';
import 'package:zagents/main.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/ui/screens/settings_screen.dart';

import '../../test/fakes/fakes.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_settings_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('settings screen: fields render and edits update state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(dir: tempDir),
        child: const ZAgentsApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(const Key('base-url-field')), findsOneWidget);
    expect(find.byKey(const Key('api-key-field')), findsOneWidget);
    expect(find.byKey(const Key('model-field')), findsOneWidget);

    // Type an API key; state must be persisted into the controller.
    await tester.enterText(
      find.byKey(const Key('api-key-field')),
      'sk-test-123',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    final BuildContext context = tester.element(find.byType(SettingsScreen));
    final ProviderContainer container = ProviderScope.containerOf(context);
    expect(container.read(settingsProvider).apiKey, 'sk-test-123');

    // Type a custom model.
    await tester.enterText(
      find.byKey(const Key('model-field')),
      'openai/gpt-4o-mini',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(container.read(settingsProvider).model, 'openai/gpt-4o-mini');

    // The agent section sits below the fold (the provider card grew with
    // helper texts): scroll the settings list before asserting its controls.
    await tester.dragUntilVisible(
      find.byKey(const Key('agent-mode-switch')),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(find.byKey(const Key('agent-mode-switch')), findsOneWidget);
    expect(find.byKey(const Key('automation-switch')), findsOneWidget);
  });

  testWidgets('theme picker switches light/dark/system and persists', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(dir: tempDir),
        child: const ZAgentsApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    // Dark is the default (v1.3.0 look preserved).
    final BuildContext context = tester.element(find.byType(SettingsScreen));
    final ProviderContainer container = ProviderScope.containerOf(context);
    expect(container.read(settingsProvider).themeMode, ThemeModeSetting.dark);

    // Switch to light (segments are identified by their icons —
    // ButtonSegment does not expose a key parameter).
    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(container.read(settingsProvider).themeMode, ThemeModeSetting.light);
    // Switch to system.
    await tester.tap(find.byIcon(Icons.settings_suggest_outlined));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(container.read(settingsProvider).themeMode, ThemeModeSetting.system);
  });

  testWidgets('max steps accepts a custom typed value (clamped 1-100)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(dir: tempDir),
        child: const ZAgentsApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('max-steps-field')),
      find.byType(ListView),
      const Offset(0, -140),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    final BuildContext context = tester.element(find.byType(SettingsScreen));
    final ProviderContainer container = ProviderScope.containerOf(context);

    await tester.enterText(find.byKey(const Key('max-steps-field')), '55');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(container.read(settingsProvider).maxSteps, 55);

    // Out-of-range input is clamped into the allowed bounds.
    await tester.enterText(find.byKey(const Key('max-steps-field')), '5000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(container.read(settingsProvider).maxSteps, 100);
  });

  testWidgets('presets are listed with key status and the active marker', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(dir: tempDir),
        child: const ZAgentsApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    // Built-in presets render as tiles.
    expect(find.byKey(const Key('preset-OpenRouter')), findsOneWidget);
    expect(find.byKey(const Key('preset-InferHub')), findsOneWidget);

    // Applying a preset copies its stored values into the active fields.
    final BuildContext context = tester.element(find.byType(SettingsScreen));
    final ProviderContainer container = ProviderScope.containerOf(context);
    await tester.tap(find.byKey(const Key('preset-Z.AI')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(container.read(settingsProvider).providerName, 'Z.AI');
    expect(
      container.read(settingsProvider).baseUrl,
      'https://api.z.ai/api/paas/v4',
    );
  });
}
