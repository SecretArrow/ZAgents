import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/cron_job.dart';
import '../../models/models.dart' show newId;
import '../../services/cron_scheduler.dart' show CronDispatchResult;
import '../theme.dart';
import '../widgets/app_message.dart';
import 'cron_job_editor_screen.dart';

/// Full-screen cron job manager (the "activity" opened from the Settings
/// tile). Supports an UNBOUNDED number of jobs: every job is a card with
/// its enabled switch, next/last run summary and Run-now action; the FAB
/// opens the full-screen editor to add another one. A master switch at
/// the top pauses every job at once, and the recent-runs history sits at
/// the bottom.
class CronJobsScreen extends ConsumerWidget {
  const CronJobsScreen({super.key});

  static String _fmt(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  void _openEditor(BuildContext context, CronJob job) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CronJobEditorScreen(job: job)),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CronJob job,
  ) async {
    final AppStrings strings = stringsOf(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('cron-delete-dialog'),
        title: Text(strings.cronDeleteTitle),
        content: Text(strings.cronDeleteBody(job.name)),
        actions: <Widget>[
          TextButton(
            key: const Key('cron-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('cron-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(cronJobsProvider.notifier).removeJob(job.id);
    }
  }

  Future<void> _runNow(BuildContext context, WidgetRef ref, CronJob job) async {
    final AppStrings strings = stringsOf(context);
    final CronDispatchResult result = await ref
        .read(cronSchedulerProvider)
        .runNow(job);
    if (!context.mounted) return;
    showAppMessage(
      context,
      '${strings.cronRunNowTooltip}: ${result.detail}',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    final ZPalette palette = context.palette;
    final CronState state = ref.watch(cronJobsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.cronJobsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('cron-add-job-fab'),
        heroTag: 'cron-add-job-fab',
        tooltip: strings.cronAddJobTooltip,
        icon: const Icon(Icons.add_rounded),
        label: Text(strings.cronAddJobTooltip),
        onPressed: () => _openEditor(
          context,
          CronJob(
            id: newId(),
            name: '',
            expression: '',
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: <Widget>[
            // -- Master switch -------------------------------------------
            Card(
              child: SwitchListTile(
                key: const Key('cron-master-switch'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(strings.cronMasterTitle),
                subtitle: Text(
                  strings.cronMasterSubtitle,
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
                value: state.enabled,
                onChanged: (bool value) =>
                    ref.read(cronJobsProvider.notifier).setEnabled(value),
              ),
            ),
            Text(
              strings.cronRunsWhileAppOpen,
              style: TextStyle(
                fontSize: 11.5,
                color: palette.muted,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),

            // -- Jobs ------------------------------------------------------
            if (state.jobs.isEmpty)
              Card(
                key: const Key('cron-empty-card'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.schedule_rounded,
                        size: 32,
                        color: palette.muted,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        strings.cronJobsEmptyTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.cronJobsEmptyBody,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...<Widget>[
              for (final CronJob job in state.jobs)
                _JobCard(
                  key: Key('cron-job-card-${job.id}'),
                  job: job,
                  fmt: _fmt,
                  onEdit: () => _openEditor(context, job),
                  onDelete: () => _confirmDelete(context, ref, job),
                  onToggle: (bool value) => ref
                      .read(cronJobsProvider.notifier)
                      .toggleJob(job.id, value),
                  onRunNow: () => _runNow(context, ref, job),
                ),
            ],
            const SizedBox(height: 16),

            // -- History ---------------------------------------------------
            Text(
              strings.cronHistoryTitle,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (state.history.isEmpty)
              Text(
                strings.cronHistoryEmpty,
                style: TextStyle(fontSize: 12, color: palette.muted),
              )
            else ...<Widget>[
              for (final CronRunEntry entry in state.history)
                Padding(
                  key: Key('cron-history-row-${entry.jobId}-${entry.atMs}'),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        entry.ok
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 16,
                        color: entry.ok
                            ? const Color(0xFF2E9E5B)
                            : const Color(0xFFD0453E),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_fmt(DateTime.fromMillisecondsSinceEpoch(entry.atMs))} · '
                          '${entry.jobName} · ${entry.detail}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: palette.muted,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One job card: name + action icon, schedule, next/last run lines, the
/// enabled switch and the Run-now / delete actions.
class _JobCard extends StatelessWidget {
  const _JobCard({
    super.key,
    required this.job,
    required this.fmt,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onRunNow,
  });

  final CronJob job;
  final String Function(DateTime) fmt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final ZPalette palette = context.palette;
    final IconData actionIcon = switch (job.action) {
      CronActionKind.notification => Icons.notifications_none_rounded,
      CronActionKind.telegram => Icons.send_outlined,
      CronActionKind.agent => Icons.smart_toy_outlined,
    };
    final String? nextLine = job.nextRunAtMs == null
        ? null
        : '${strings.cronNextRunLabel}: ${fmt(
            DateTime.fromMillisecondsSinceEpoch(job.nextRunAtMs!),
          )}';
    final String? lastLine = job.lastRunAtMs == null
        ? null
        : '${strings.cronLastRunLabel}: ${fmt(
            DateTime.fromMillisecondsSinceEpoch(job.lastRunAtMs!),
          )}${job.lastResult.isEmpty ? '' : ' · ${job.lastResult}'}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(actionIcon, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      job.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!job.enabled)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        strings.cronDisabledBadge,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: palette.muted,
                        ),
                      ),
                    ),
                  Switch(
                    key: Key('cron-job-switch-${job.id}'),
                    value: job.enabled,
                    onChanged: onToggle,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                job.expression,
                style: TextStyle(
                  fontSize: 12,
                  color: palette.muted,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              if (nextLine != null)
                Text(
                  nextLine,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.muted,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              if (lastLine != null)
                Text(
                  lastLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: job.lastResultOk
                        ? palette.muted
                        : const Color(0xFFD0453E),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    key: Key('cron-job-run-now-${job.id}'),
                    tooltip: strings.cronRunNowTooltip,
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: onRunNow,
                  ),
                  IconButton(
                    key: Key('cron-job-delete-${job.id}'),
                    tooltip: strings.delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
