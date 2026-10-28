import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/ui/widgets/toast.dart';

/// Widget tests for the v1.49.5 overlay toast that replaced SnackBars:
/// appears, replaces itself, expires on its own and — the reason it exists
/// — NEVER intercepts taps (IgnorePointer), unlike a SnackBar.
void main() {
  testWidgets('toast appears after the fade-in and expires on its own', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: FilledButton(
                onPressed: () => showToast(
                  context,
                  'Saved!',
                  key: const Key('toast-under-test'),
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    // The entry is in the tree immediately (still fading in).
    expect(find.text('Saved!'), findsOneWidget);
    expect(find.byKey(const Key('toast-under-test')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved!'), findsOneWidget);

    // Hold expires (2.6s) → fade-out → removal.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved!'), findsNothing);
    expect(find.byKey(const Key('toast-under-test')), findsNothing);
  });

  testWidgets('a second toast replaces the first one immediately', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FilledButton(
                    onPressed: () => showToast(context, 'first'),
                    child: const Text('one'),
                  ),
                  FilledButton(
                    onPressed: () => showToast(context, 'second'),
                    child: const Text('two'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('one'));
    await tester.pump();
    expect(find.text('first'), findsOneWidget);

    await tester.tap(find.text('two'));
    await tester.pump();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    // Flush the replacement toast's full lifetime.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('second'), findsNothing);
  });

  testWidgets('the toast never intercepts taps (IgnorePointer)', (
    WidgetTester tester,
  ) async {
    bool hiddenTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              // Sits exactly where the toast floats (bottom center).
              Align(
                alignment: Alignment.bottomCenter,
                child: FilledButton(
                  onPressed: () => hiddenTapped = true,
                  child: const Text('hidden'),
                ),
              ),
              Builder(
                builder: (BuildContext context) => Align(
                  alignment: Alignment.topLeft,
                  child: TextButton(
                    onPressed: () => showToast(context, 'overlay toast'),
                    child: const Text('trigger'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('overlay toast'), findsOneWidget);

    // The toast floats over the hidden button — the tap must land THROUGH
    // it (a SnackBar would swallow it).
    await tester.tap(find.text('hidden'), warnIfMissed: false);
    await tester.pump();
    expect(hiddenTapped, isTrue);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('overlay toast'), findsNothing);
  });
}
