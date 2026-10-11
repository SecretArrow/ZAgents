import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zagents/di.dart';
import 'package:zagents/main.dart';
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
    expect(find.byKey(const Key('agent-mode-switch')), findsOneWidget);
    expect(find.byKey(const Key('automation-switch')), findsOneWidget);

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
  });
}
