import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/cron_job.dart';
import '../../services/cron_parser.dart';
import '../theme.dart';
import '../widgets/app_message.dart';

/// Predefined schedule presets shown in the editor. Values are standard
/// 5-field cron expressions understood by [CronExpression].
const List<(String, String)> kCronSchedulePresets = <(String, String)>[
  ('* * * * *', 'every-minute'),
  ('*/5 * * * *', 'every-5-minutes'),
  ('0 * * * *', 'hourly'),
  ('0 8 * * *', 'daily-8'),
  ('0 9 * * mon-fri', 'weekdays-9'),
  ('0 9 * * sun', 'weekly-sun'),
  ('0 8 1 * *', 'monthly-1'),
];

/// Full-screen editor for one cron job (the "activity" behind the
/// Settings tile). Creates a job with any of the three action kinds —
/// Telegram message, local notification or headless agent task — and
/// validates the cron expression live, showing the next three fire
/// times before saving.
class CronJobEditorScreen extends ConsumerStatefulWidget {
  const CronJobEditorScreen({super.key, required this.job});

  /// The job to edit. Pass a fresh [CronJob] (empty id) to create one.
  final CronJob job;

  @override
  ConsumerState<CronJobEditorScreen> createState() =>
      _CronJobEditorScreenState();
}

class _CronJobEditorScreenState extends ConsumerState<CronJobEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _expression;
  late final TextEditingController _telegramToken;
  late final TextEditingController _telegramChatId;
  late final TextEditingController _message;
  late final TextEditingController _notifTitle;
  late final TextEditingController _notifText;
  late final TextEditingController _agentPrompt;

  late CronActionKind _action;

  /// Null while the expression parses; carries the error text otherwise.
  CronFormatException? _expressionError;

  bool get _isNew => widget.job.id.isEmpty;

  AppStrings get _strings => stringsOf(context);

  @override
  void initState() {
    super.initState();
    final CronJob job = widget.job;
    _name = TextEditingController(text: job.name);
    _expression = TextEditingController(text: job.expression);
    _telegramToken = TextEditingController(text: job.telegramToken);
    _telegramChatId = TextEditingController(text: job.telegramChatId);
    _message = TextEditingController(text: job.messageText);
    _notifTitle = TextEditingController(text: job.notifTitle);
    _notifText = TextEditingController(text: job.notifText);
    _agentPrompt = TextEditingController(text: job.agentPrompt);
    _action = job.action;
    _revalidate();
  }

  @override
  void dispose() {
    _name.dispose();
    _expression.dispose();
    _telegramToken.dispose();
    _telegramChatId.dispose();
    _message.dispose();
    _notifTitle.dispose();
    _notifText.dispose();
    _agentPrompt.dispose();
    super.dispose();
  }

  void _revalidate() {
    try {
      CronExpression.parse(_expression.text);
      _expressionError = null;
    } on CronFormatException catch (error) {
      _expressionError = error;
    }
  }

  /// The next up-to-3 fire times for the live preview, empty when the
  /// expression is invalid.
  List<DateTime> _upcoming() {
    if (_expressionError != null) return const <DateTime>[];
    final CronExpression parsed = CronExpression.parse(_expression.text);
    final List<DateTime> out = <DateTime>[];
    DateTime? next = parsed.nextAfter(DateTime.now());
    while (next != null && out.length < 3) {
      out.add(next);
      next = parsed.nextAfter(next);
    }
    return out;
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return _strings.cronNameRequired;
    if (_expressionError != null) return _strings.cronExpressionInvalid;
    switch (_action) {
      case CronActionKind.telegram:
        if (_telegramToken.text.trim().isEmpty ||
            _telegramChatId.text.trim().isEmpty) {
          return _strings.cronTelegramFieldsRequired;
        }
        if (_message.text.trim().isEmpty) {
          return _strings.cronMessageRequired;
        }
      case CronActionKind.notification:
        if (_notifText.text.trim().isEmpty) {
          return _strings.cronNotifTextRequired;
        }
      case CronActionKind.agent:
        if (_agentPrompt.text.trim().isEmpty) {
          return _strings.cronAgentPromptRequired;
        }
    }
    return null;
  }

  Future<void> _save() async {
    final String? problem = _validate();
    if (problem != null) {
      _snack(problem);
      return;
    }
    final CronJob saved = widget.job.copyWith(
      name: _name.text.trim(),
      expression: _expression.text.trim(),
      action: _action,
      telegramToken: _telegramToken.text.trim(),
      telegramChatId: _telegramChatId.text.trim(),
      messageText: _message.text,
      notifTitle: _notifTitle.text.trim(),
      notifText: _notifText.text,
      agentPrompt: _agentPrompt.text.trim(),
    );
    await ref.read(cronJobsProvider.notifier).saveJob(saved);
    if (!mounted) return;
    // Close the editor FIRST, then surface the confirmation — the
    // feedback dialog lives on the ROOT navigator, so a pop() after
    // showing it would dismiss the DIALOG instead of this screen
    // (same ordering fix as PresetEditorScreen v1.49.6).
    final NavigatorState nav = Navigator.of(context);
    nav.pop();
    showAppMessage(nav.context, _strings.cronSaved);
  }

  void _snack(String message) {
    if (!mounted) return;
    showAppMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = _strings;
    final ZPalette palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? strings.cronNewTitle : strings.cronEditTitle),
        actions: <Widget>[
          IconButton(
            key: const Key('cron-editor-save-appbar'),
            tooltip: strings.save,
            icon: const Icon(Icons.check_rounded),
            onPressed: _save,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            TextField(
              key: const Key('cron-editor-name-field'),
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: strings.cronFieldName,
                hintText: 'Daily report',
              ),
            ),
            const SizedBox(height: 16),

            // -- Schedule ------------------------------------------------
            Text(
              strings.cronFieldSchedule,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              key: const Key('cron-schedule-presets'),
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final (String expr, String tag) in kCronSchedulePresets)
                  ActionChip(
                    key: Key('cron-preset-$tag'),
                    label: Text(_presetLabel(expr)),
                    onPressed: () {
                      _expression.text = expr;
                      setState(_revalidate);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('cron-editor-expression-field'),
              controller: _expression,
              onChanged: (_) => setState(_revalidate),
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: strings.cronFieldExpression,
                hintText: '30 8 * * *',
                helperText: strings.cronExpressionHint,
                errorText: _expressionError == null
                    ? null
                    : strings.cronExpressionInvalid,
              ),
            ),
            if (_expressionError == null && _upcoming().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              _NextRunsPreview(upcoming: _upcoming()),
            ],
            const SizedBox(height: 16),

            // -- Action --------------------------------------------------
            Text(
              strings.cronFieldAction,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<CronActionKind>(
              key: const Key('cron-editor-action-segmented'),
              segments: <ButtonSegment<CronActionKind>>[
                ButtonSegment<CronActionKind>(
                  value: CronActionKind.notification,
                  icon: const Icon(Icons.notifications_none_rounded, size: 18),
                  label: Text(strings.cronActionNotification),
                ),
                ButtonSegment<CronActionKind>(
                  value: CronActionKind.telegram,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: Text(strings.cronActionTelegram),
                ),
                ButtonSegment<CronActionKind>(
                  value: CronActionKind.agent,
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: Text(strings.cronActionAgent),
                ),
              ],
              selected: <CronActionKind>{_action},
              onSelectionChanged: (Set<CronActionKind> selection) =>
                  setState(() => _action = selection.first),
            ),
            const SizedBox(height: 12),
            ...switch (_action) {
              CronActionKind.notification => <Widget>[
                TextField(
                  key: const Key('cron-editor-notif-title-field'),
                  controller: _notifTitle,
                  decoration: InputDecoration(
                    labelText: strings.cronFieldNotifTitle,
                    hintText: 'ZAgents',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('cron-editor-notif-text-field'),
                  controller: _notifText,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: strings.cronFieldNotifText,
                  ),
                ),
              ],
              CronActionKind.telegram => <Widget>[
                TextField(
                  key: const Key('cron-editor-telegram-token-field'),
                  controller: _telegramToken,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: strings.cronFieldTelegramToken,
                    hintText: '123456:ABC-DEF…',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('cron-editor-telegram-chat-field'),
                  controller: _telegramChatId,
                  decoration: InputDecoration(
                    labelText: strings.cronFieldTelegramChat,
                    hintText: '123456789',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('cron-editor-message-field'),
                  controller: _message,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: strings.cronFieldMessage,
                  ),
                ),
              ],
              CronActionKind.agent => <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        strings.cronActionAgentHint,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.muted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('cron-editor-agent-prompt-field'),
                  controller: _agentPrompt,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: strings.cronFieldAgentPrompt,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('cron-editor-agent-telegram-token-field'),
                  controller: _telegramToken,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '${strings.cronFieldTelegramToken} (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('cron-editor-agent-telegram-chat-field'),
                  controller: _telegramChatId,
                  decoration: InputDecoration(
                    labelText: '${strings.cronFieldTelegramChat} (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  strings.cronAgentRelayHint,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.muted,
                    height: 1.35,
                  ),
                ),
              ],
            },
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('cron-editor-save-button'),
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(strings.save),
            ),
          ],
        ),
      ),
    );
  }

  /// Human label for a preset expression (falls back to the expression
  /// itself when it matches no preset).
  String _presetLabel(String expr) {
    final AppStrings strings = stringsOf(context);
    for (final (String preset, String tag) in kCronSchedulePresets) {
      if (preset != expr) continue;
      return switch (tag) {
        'every-minute' => strings.cronScheduleEveryMinute,
        'every-5-minutes' => strings.cronScheduleEvery5Minutes,
        'hourly' => strings.cronScheduleHourly,
        'daily-8' => strings.cronScheduleDaily8,
        'weekdays-9' => strings.cronScheduleWeekdays9,
        'weekly-sun' => strings.cronScheduleWeekly,
        'monthly-1' => strings.cronScheduleMonthly,
        _ => preset,
      };
    }
    return expr;
  }
}

/// Live preview of the next fire times under the expression field.
class _NextRunsPreview extends StatelessWidget {
  const _NextRunsPreview({required this.upcoming});

  final List<DateTime> upcoming;

  static String _fmt(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final ZPalette palette = context.palette;
    return Column(
      key: const Key('cron-next-runs-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.cronNextRuns,
          style: TextStyle(fontSize: 11.5, color: palette.muted),
        ),
        const SizedBox(height: 2),
        for (final DateTime t in upcoming)
          Text(
            '• ${_fmt(t)}',
            style: TextStyle(
              fontSize: 11.5,
              color: palette.muted,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}
