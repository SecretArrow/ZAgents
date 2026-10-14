import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../theme.dart';

/// Plan card rendered for every `todo_write` tool call (z.ai agent-mode
/// style): a header with progress ("2/5 done") + a thin progress bar, then
/// one row per todo with its status icon. The state shown is the one the
/// model wrote in THIS call, so the cards read as a timeline of the plan.
class TodoPlanCard extends StatelessWidget {
  const TodoPlanCard({super.key, required this.call});

  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final List<TodoItem> todos = parseTodoList(call.arguments['todos']);
    final int total = todos.length;
    final int done = todos
        .where((TodoItem t) => t.status == TodoStatus.completed)
        .length;
    final ZPalette palette = context.palette;

    return Container(
      key: const Key('todo-plan-card'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.zSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.zBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.checklist_rounded,
                size: 16,
                color: kAccentColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.planTitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                strings.planProgress(done, total),
                style: TextStyle(fontSize: 11.5, color: palette.muted),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 3,
                valueColor: const AlwaysStoppedAnimation<Color>(kAccentColor),
                backgroundColor: palette.border,
              ),
            ),
          ),
          if (todos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                call.name,
                style: TextStyle(fontSize: 11.5, color: palette.muted),
              ),
            )
          else ...<Widget>[
            for (final TodoItem todo in todos)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: _TodoStatusIcon(status: todo.status),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        todo.content,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: switch (todo.status) {
                            TodoStatus.completed => palette.muted,
                            TodoStatus.inProgress => Theme.of(
                              context,
                            ).colorScheme.onSurface,
                            TodoStatus.pending => palette.muted,
                          },
                          decoration: todo.status == TodoStatus.completed
                              ? TextDecoration.lineThrough
                              : null,
                          fontWeight: todo.status == TodoStatus.inProgress
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TodoStatusIcon extends StatelessWidget {
  const _TodoStatusIcon({required this.status});

  final TodoStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case TodoStatus.completed:
        return const Icon(
          Icons.check_circle_rounded,
          size: 15,
          color: Color(0xFF4ADE80),
        );
      case TodoStatus.inProgress:
        // Static glyph on purpose: historical plan cards show the state at
        // the time of the call, so a spinner would be misleading there.
        return const Icon(
          Icons.radio_button_checked_rounded,
          size: 15,
          color: kAccentColor,
        );
      case TodoStatus.pending:
        return Icon(
          Icons.radio_button_unchecked_rounded,
          size: 15,
          color: context.palette.muted,
        );
    }
  }
}
