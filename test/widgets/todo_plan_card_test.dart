import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/ui/theme.dart';
import 'package:zagents/ui/widgets/message_bubble.dart';
import 'package:zagents/ui/widgets/todo_plan_card.dart';
import 'package:zagents/ui/widgets/tool_call_card.dart';

ChatMessage _assistantWith(Map<String, dynamic> args) => ChatMessage.assistant(
  '',
  toolCalls: <ToolCall>[
    ToolCall(
      id: 'p1',
      name: 'todo_write',
      arguments: args,
      status: ToolStatus.success,
      resultText: '{"ok":true}',
    ),
  ],
);

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: buildDarkTheme(),
    locale: const Locale('en'),
    supportedLocales: const <Locale>[Locale('en'), Locale('id')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      zLocalizationsDelegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: ListView(children: <Widget>[child])),
  );

  testWidgets('todo_write renders a plan card with progress and statuses', (
    WidgetTester tester,
  ) async {
    final ChatMessage message = _assistantWith(<String, dynamic>{
      'todos': <dynamic>[
        <String, dynamic>{'content': 'research topic', 'status': 'completed'},
        <String, dynamic>{'content': 'draft report', 'status': 'in_progress'},
        <String, dynamic>{'content': 'review output', 'status': 'pending'},
      ],
    });

    await tester.pumpWidget(wrap(MessageBubble(message: message)));

    expect(find.byType(TodoPlanCard), findsOneWidget);
    expect(find.byType(ToolCallCard), findsNothing);
    expect(find.byKey(const Key('todo-plan-card')), findsOneWidget);

    const AppStrings strings = AppStringsEn();
    expect(find.text(strings.planTitle), findsOneWidget);
    expect(find.text(strings.planProgress(1, 3)), findsOneWidget);
    expect(find.text('research topic'), findsOneWidget);
    expect(find.text('draft report'), findsOneWidget);
    expect(find.text('review output'), findsOneWidget);

    // Status icons: 1 completed check + 1 in-progress ring + 1 pending ring.
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
  });

  testWidgets('todo_write with malformed args falls back to ToolCallCard', (
    WidgetTester tester,
  ) async {
    final ChatMessage message = _assistantWith(<String, dynamic>{
      'todos': 'not-a-list',
    });

    await tester.pumpWidget(wrap(MessageBubble(message: message)));

    expect(find.byType(TodoPlanCard), findsNothing);
    expect(find.byType(ToolCallCard), findsOneWidget);
    expect(find.text('todo_write'), findsOneWidget);
  });

  testWidgets('plan card reflects the latest state of its own call', (
    WidgetTester tester,
  ) async {
    // A later todo_write (completed plan) renders fully checked.
    final ChatMessage message = _assistantWith(<String, dynamic>{
      'todos': <dynamic>[
        <String, dynamic>{'content': 'step', 'status': 'completed'},
      ],
    });

    await tester.pumpWidget(wrap(MessageBubble(message: message)));

    expect(find.byType(TodoPlanCard), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsNothing);
    expect(find.text(const AppStringsEn().planProgress(1, 1)), findsOneWidget);
  });
}
