import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
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
  Widget wrap(Widget child) => ProviderScope(
    child: MaterialApp(
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
    ),
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

  group('live plan toggle (thinking indicator)', () {
    final List<TodoItem> todos = const <TodoItem>[
      TodoItem(content: 'research topic', status: TodoStatus.completed),
      TodoItem(content: 'draft report', status: TodoStatus.inProgress),
      TodoItem(content: 'review output', status: TodoStatus.pending),
    ];

    testWidgets('streaming message with a plan shows the right-aligned '
        'show/hide toggle that flips the GLOBAL panel open state', (
      WidgetTester tester,
    ) async {
      final ChatMessage message = ChatMessage.assistant(
        'Working on it…',
        isStreaming: true,
      );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        wrap(
          Consumer(
            builder: (_, WidgetRef ref, _) {
              capturedRef = ref;
              return MessageBubble(message: message, todos: todos);
            },
          ),
        ),
      );

      // Toggle exists, panel closed at first.
      expect(find.byKey(const Key('todo-toggle-button')), findsOneWidget);
      expect(find.text('thinking…'), findsOneWidget);
      expect(
        capturedRef.read(planPanelOpenProvider),
        isFalse,
        reason: 'panel starts closed',
      );

      // Show: the toggle flips the global state — the pinned panel
      // (rendered by ChatBody, covered by plan_panel_test) reacts to it.
      await tester.tap(find.byKey(const Key('todo-toggle-button')));
      await tester.pump();
      expect(capturedRef.read(planPanelOpenProvider), isTrue);
      expect(
        find.byTooltip(const AppStringsEn().hidePlanTooltip),
        findsOneWidget,
      );

      // Hide again.
      await tester.tap(find.byKey(const Key('todo-toggle-button')));
      await tester.pump();
      expect(capturedRef.read(planPanelOpenProvider), isFalse);
    });

    testWidgets('no plan yet: the toggle is not rendered', (
      WidgetTester tester,
    ) async {
      final ChatMessage message = ChatMessage.assistant('', isStreaming: true);

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, todos: const <TodoItem>[])),
      );

      expect(find.text('thinking…'), findsOneWidget);
      expect(find.byKey(const Key('todo-toggle-button')), findsNothing);
    });

    testWidgets('tool execution phase: footer stays visible on the newest '
        'message while the agent works', (WidgetTester tester) async {
      // Not streaming (a finalized tool-call turn), but the agent loop is
      // still running — the thinking indicator must remain available.
      final ChatMessage message = _assistantWith(<String, dynamic>{
        'todos': <dynamic>[
          <String, dynamic>{'content': 'step', 'status': 'in_progress'},
        ],
      });

      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: message,
            todos: const <TodoItem>[
              TodoItem(content: 'step', status: TodoStatus.inProgress),
            ],
            agentWorking: true,
          ),
        ),
      );

      expect(find.text('thinking…'), findsOneWidget);
      expect(find.byKey(const Key('todo-toggle-button')), findsOneWidget);
    });

    testWidgets('a finished message without a running session shows no '
        'thinking footer', (WidgetTester tester) async {
      final ChatMessage message = ChatMessage.assistant('All done.');

      await tester.pumpWidget(
        wrap(MessageBubble(message: message, todos: todos)),
      );

      expect(find.text('thinking…'), findsNothing);
      expect(find.byKey(const Key('todo-toggle-button')), findsNothing);
    });
  });
}
