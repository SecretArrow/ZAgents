import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/ui/widgets/app_message.dart';

/// Widget tests for the v1.49.6 centered message dialog that replaced both
/// SnackBars (v1.48-) and the bottom overlay toast (v1.49.5): appears at
/// the center of the screen, replaces itself, expires on its own for info
/// messages and stays until acknowledged for errors.
void main() {
  Widget host(VoidCallback onShow) => MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const <Locale>[Locale('en'), Locale('id')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      zLocalizationsDelegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: FilledButton(
            onPressed: () => onShow(),
            child: const Text('trigger'),
          ),
        ),
      ),
    ),
  );

  Future<void> trigger(WidgetTester tester, VoidCallback onShow) async {
    await tester.pumpWidget(host(onShow));
    await tester.tap(find.text('trigger'));
    await tester.pump();
  }

  testWidgets('info message appears as a centered dialog and auto-expires', (
    WidgetTester tester,
  ) async {
    await trigger(
      tester,
      () => showAppMessage(tester.element(find.text('trigger')), 'Saved!'),
    );

    // Visible immediately (during the entrance transition).
    expect(find.text('Saved!'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('app-message-ok')), findsOneWidget);

    // pumpAndSettle must NOT burn the hold timer (SnackBar-parity contract
    // the surrounding flows rely on).
    await tester.pumpAndSettle();
    expect(find.text('Saved!'), findsOneWidget);

    // Hold (2.6 s) elapses → the dialog is removed.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Saved!'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a second message replaces the visible one immediately', (
    WidgetTester tester,
  ) async {
    BuildContext? captured;
    await trigger(
      tester,
      () => showAppMessage(
        captured ??= tester.element(find.text('trigger')),
        'first',
      ),
    );
    expect(find.text('first'), findsOneWidget);

    showAppMessage(captured!, 'second');
    await tester.pump();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('second'), findsNothing);
  });

  testWidgets('error messages stay until acknowledged via OK', (
    WidgetTester tester,
  ) async {
    await trigger(
      tester,
      () => showAppMessage(
        tester.element(find.text('trigger')),
        'Operation failed',
        error: true,
      ),
    );
    await tester.pumpAndSettle();

    // Errors never auto-expire.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Operation failed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-message-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Operation failed'), findsNothing);
  });

  testWidgets('info messages can be dismissed early via the OK button', (
    WidgetTester tester,
  ) async {
    await trigger(
      tester,
      () => showAppMessage(tester.element(find.text('trigger')), 'Copied'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app-message-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('v1.54.0: an optional action button renders before OK and '
      'runs after the dialog closes', (WidgetTester tester) async {
    bool acted = false;
    await trigger(
      tester,
      () => showAppMessage(
        tester.element(find.text('trigger')),
        'HTTP 401: Unauthorized',
        error: true,
        actionLabel: 'Open Providers',
        onAction: () => acted = true,
      ),
    );
    await tester.pumpAndSettle();

    // Error + action: both buttons are offered and the error never
    // auto-expires (the action must stay tappable).
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('HTTP 401: Unauthorized'), findsOneWidget);
    expect(find.byKey(const Key('app-message-action')), findsOneWidget);
    expect(find.byKey(const Key('app-message-ok')), findsOneWidget);

    // Tapping the action closes the dialog first, then runs the callback.
    await tester.tap(find.byKey(const Key('app-message-action')));
    await tester.pumpAndSettle();
    expect(find.text('HTTP 401: Unauthorized'), findsNothing);
    expect(acted, isTrue);
  });

  testWidgets('v1.54.0: without the optional params the dialog stays '
      'single-button (old API unchanged)', (WidgetTester tester) async {
    await trigger(
      tester,
      () => showAppMessage(tester.element(find.text('trigger')), 'Saved!'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-message-action')), findsNothing);
    expect(find.byKey(const Key('app-message-ok')), findsOneWidget);
  });
}
