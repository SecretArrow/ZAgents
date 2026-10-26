import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/ui/widgets/composer.dart';

import '../support/test_doubles.dart';

/// v1.46.0 — the composer TOOLBAR: attach / prompt library / mic moved
/// OUT of the text row into a toolbar row above the "Ask anything" box
/// (text row = field + send only, maximum typing width), with the Plan
/// show/hide eye parked on the toolbar's right side when the displayed
/// chat has a plan.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('composer_toolbar_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(dir: tempDir, writeScreenshots: false),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            zLocalizationsDelegate,
          ],
          supportedLocales: const <Locale>[Locale('en'), Locale('id')],
          home: const Scaffold(body: Composer()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tool icons render in the toolbar above the text field', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(find.byKey(const Key('attach-button')), findsOneWidget);
    expect(find.byKey(const Key('prompt-insert-button')), findsOneWidget);
    expect(find.byKey(const Key('mic-button')), findsOneWidget);
    expect(find.byKey(const Key('composer-field')), findsOneWidget);
    expect(find.byKey(const Key('send-button')), findsOneWidget);

    // Toolbar is a SEPARATE row from the text field: the attach button's
    // center sits ABOVE the field's top edge (v1.45 and below had them
    // in one Row, i.e. vertically overlapping).
    final Rect attach = tester.getRect(find.byKey(const Key('attach-button')));
    final Rect field = tester.getRect(find.byKey(const Key('composer-field')));
    expect(attach.bottom, lessThanOrEqualTo(field.top + 1));
  });

  testWidgets('the plan toggle only exists when the chat has a plan', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('composer-plan-toggle')), findsNothing);
  });
}
