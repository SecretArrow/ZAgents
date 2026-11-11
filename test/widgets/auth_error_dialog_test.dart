import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/main.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/agent_controller.dart' show ChatController;
import 'package:zagents/ui/screens/providers_screen.dart';

import '../support/test_doubles.dart';

/// v1.54.0 — the home-shell error listener turns provider auth/config
/// failures into an ACTIONABLE dialog: the raw error text stays in the
/// body (honesty) and an "Open Providers" button jumps straight to the
/// provider manager. Any other error keeps the plain message dialog.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_auth_dialog');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(
          dir: tempDir,
          settings: AppSettings(apiKey: 'k'),
        ),
        child: Builder(
          builder: (BuildContext context) {
            container = ProviderScope.containerOf(context);
            return const ZAgentsApp();
          },
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Surfaces an error the same way a failed send does: the ChatState
  /// error field flips and the home-shell listener shows the dialog.
  Future<void> surfaceError(
    WidgetTester tester,
    ProviderContainer container,
    String error,
  ) async {
    final ChatController controller = container.read(
      chatControllerProvider.notifier,
    );
    controller.state = controller.state.copyWith(error: error);
    await tester.pump();
  }

  testWidgets('an HTTP 401 failure offers Open Providers and pushes it', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpApp(tester);

    await surfaceError(
      tester,
      container,
      'HTTP 401: {"error":{"code":"invalid_api_key"}}',
    );

    // Raw error kept in the body + the extra action before OK.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('HTTP 401: {"error":{"code":"invalid_api_key"}}'),
      findsOneWidget,
    );
    expect(find.text('Open Providers'), findsOneWidget);
    expect(find.byKey(const Key('app-message-ok')), findsOneWidget);

    // The action lands on the provider manager (pumpAndSettle completes
    // the dialog pop + page push transitions; an error dialog has no
    // auto-expire timer, so settling is safe here).
    await tester.tap(find.byKey(const Key('app-message-action')));
    await tester.pumpAndSettle();
    expect(find.byType(ProvidersScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a transport error keeps the plain single-button dialog', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpApp(tester);

    await surfaceError(
      tester,
      container,
      'Could not connect to provider: SocketException',
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('app-message-action')), findsNothing);
    expect(find.byKey(const Key('app-message-ok')), findsOneWidget);
  });
}
