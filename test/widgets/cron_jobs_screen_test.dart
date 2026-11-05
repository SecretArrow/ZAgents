import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zagents/di.dart';
import 'package:zagents/main.dart';
import 'package:zagents/models/cron_job.dart';
import 'package:zagents/services/cron_repository.dart';
import 'package:zagents/services/cron_scheduler.dart';
import 'package:zagents/ui/screens/cron_job_editor_screen.dart';
import 'package:zagents/ui/screens/cron_jobs_screen.dart';

import '../../test/support/test_doubles.dart';

/// Recording dispatcher: succeeds for telegram/notification, fails when
/// [failNext] is set — used to assert the run-now feedback path.
class RecordingCronDispatcher implements CronActionDispatcher {
  final List<CronJob> calls = <CronJob>[];
  bool failNext = false;

  @override
  Future<CronDispatchResult> dispatch(CronJob job) async {
    calls.add(job);
    return CronDispatchResult(
      ok: !failNext,
      detail: failNext ? 'HTTP 400: chat not found' : 'sent',
    );
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_cron_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Pumps the app, navigates Settings → cron tile, and lands on the
  /// manager screen with an in-memory store pre-seeded with [jobs] and
  /// the recording dispatcher; returns the container.
  Future<ProviderContainer> openCronScreen(
    WidgetTester tester, {
    List<CronJob> jobs = const <CronJob>[],
    RecordingCronDispatcher? dispatcher,
    bool enabled = true,
  }) async {
    late ProviderContainer container;
    final RecordingCronDispatcher disp =
        dispatcher ?? RecordingCronDispatcher();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...testOverrides(dir: tempDir),
          cronRepositoryProvider.overrideWithValue(
            MemoryCronRepository(CronState(jobs: jobs, enabled: enabled)),
          ),
          cronClockProvider.overrideWithValue(
            () => DateTime(2026, 1, 14, 10, 30),
          ),
          cronSchedulerProvider.overrideWith(
            (Ref ref) => CronSchedulerService(
              controller: ref.read(cronJobsProvider.notifier),
              readState: () => ref.read(cronJobsProvider),
              dispatcher: disp,
            ),
          ),
        ],
        child: Builder(
          builder: (BuildContext context) {
            container = ProviderScope.containerOf(context);
            return const ZAgentsApp();
          },
        ),
      ),
    );
    await tester.pump();

    // Navigate: Settings tab → the cron tile sits right below the
    // Appearance section (second card from the top of the list).
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('cron-jobs-tile')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('cron-jobs-tile')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(find.byType(CronJobsScreen), findsOneWidget);
    return container;
  }

  testWidgets('empty store shows the empty state and the add FAB', (
    WidgetTester tester,
  ) async {
    await openCronScreen(tester);
    expect(find.byKey(const Key('cron-empty-card')), findsOneWidget);
    expect(find.byKey(const Key('cron-add-job-fab')), findsOneWidget);
    expect(find.byKey(const Key('cron-master-switch')), findsOneWidget);
  });

  testWidgets('renders EVERY stored job (multiple jobs, not just one)', (
    WidgetTester tester,
  ) async {
    final List<CronJob> jobs = <CronJob>[
      for (var i = 0; i < 7; i++)
        CronJob(
          id: 'job-$i',
          name: 'Job $i',
          expression: i.isEven ? '0 8 * * *' : '*/5 * * * *',
          action: CronActionKind.telegram,
          telegramToken: 't',
          telegramChatId: 'c',
          messageText: 'hi',
          createdAtMs: 1,
          nextRunAtMs: DateTime(2026, 1, 14, 11).millisecondsSinceEpoch,
        ),
    ];
    await openCronScreen(tester, jobs: jobs);
    expect(find.byKey(const Key('cron-empty-card')), findsNothing);
    for (var i = 0; i < 7; i++) {
      expect(find.text('Job $i'), findsOneWidget);
      expect(find.byKey(Key('cron-job-card-job-$i')), findsOneWidget);
      expect(find.byKey(Key('cron-job-switch-job-$i')), findsOneWidget);
    }
  });

  testWidgets(
    'master switch off shows the paused badge and toggling persists',
    (WidgetTester tester) async {
      final ProviderContainer container = await openCronScreen(
        tester,
        jobs: <CronJob>[
          CronJob(
            id: 'j1',
            name: 'J1',
            expression: '0 8 * * *',
            createdAtMs: 1,
            nextRunAtMs: DateTime(2026, 1, 14, 11).millisecondsSinceEpoch,
          ),
        ],
      );
      expect(container.read(cronJobsProvider).enabled, isTrue);
      await tester.tap(find.byKey(const Key('cron-master-switch')));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 15),
      );
      expect(container.read(cronJobsProvider).enabled, isFalse);
      expect(find.byKey(const Key('cron-master-switch')), findsOneWidget);
    },
  );

  testWidgets('the add FAB opens the full-screen editor', (
    WidgetTester tester,
  ) async {
    await openCronScreen(tester);
    await tester.tap(find.byKey(const Key('cron-add-job-fab')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(find.byType(CronJobEditorScreen), findsOneWidget);
    expect(find.byKey(const Key('cron-editor-name-field')), findsOneWidget);
  });

  testWidgets('run-now dispatches the job and shows the outcome', (
    WidgetTester tester,
  ) async {
    final RecordingCronDispatcher dispatcher = RecordingCronDispatcher();
    await openCronScreen(
      tester,
      jobs: <CronJob>[
        CronJob(
          id: 'r1',
          name: 'Run me',
          expression: '0 8 * * *',
          action: CronActionKind.telegram,
          telegramToken: 't',
          telegramChatId: 'c',
          messageText: 'hi',
          createdAtMs: 1,
        ),
      ],
      dispatcher: dispatcher,
    );
    await tester.tap(find.byKey(const Key('cron-job-run-now-r1')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(dispatcher.calls, hasLength(1));
    expect(dispatcher.calls.single.id, 'r1');
    // History recorded the run.
    expect(find.textContaining('Run me · sent'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation and removes the job', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openCronScreen(
      tester,
      jobs: <CronJob>[
        CronJob(
          id: 'd1',
          name: 'Doomed',
          expression: '0 8 * * *',
          createdAtMs: 1,
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('cron-job-delete-d1')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(find.byKey(const Key('cron-delete-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cron-delete-confirm')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(container.read(cronJobsProvider).jobs, isEmpty);
    expect(find.byKey(const Key('cron-empty-card')), findsOneWidget);
  });

  testWidgets('the editor saves a new notification job through the UI', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openCronScreen(tester);
    await tester.tap(find.byKey(const Key('cron-add-job-fab')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    await tester.enterText(
      find.byKey(const Key('cron-editor-name-field')),
      'Morning ping',
    );
    // Daily-8 preset chip.
    await tester.tap(find.byKey(const Key('cron-preset-daily-8')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    // Notification is the default action: fill the text.
    await tester.enterText(
      find.byKey(const Key('cron-editor-notif-text-field')),
      'Standup in 30 minutes',
    );
    await tester.tap(find.byKey(const Key('cron-editor-save-button')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    // Editor popped, job persisted with the preset expression.
    expect(find.byType(CronJobEditorScreen), findsNothing);
    final CronState state = container.read(cronJobsProvider);
    expect(state.jobs, hasLength(1));
    expect(state.jobs.single.name, 'Morning ping');
    expect(state.jobs.single.expression, '0 8 * * *');
    expect(state.jobs.single.action, CronActionKind.notification);
    expect(state.jobs.single.nextRunAtMs, isNotNull);
  });

  testWidgets('the editor rejects an invalid cron expression', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await openCronScreen(tester);
    await tester.tap(find.byKey(const Key('cron-add-job-fab')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    await tester.enterText(
      find.byKey(const Key('cron-editor-name-field')),
      'Broken',
    );
    await tester.enterText(
      find.byKey(const Key('cron-editor-expression-field')),
      '99 * * * *',
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    // Live validation flags the field.
    expect(find.text('Invalid cron expression.'), findsOneWidget);
    // No next-runs preview while invalid.
    expect(find.byKey(const Key('cron-next-runs-preview')), findsNothing);
    // Saving is blocked (still on the editor, nothing persisted).
    await tester.tap(find.byKey(const Key('cron-editor-save-button')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(find.byType(CronJobEditorScreen), findsOneWidget);
    expect(container.read(cronJobsProvider).jobs, isEmpty);
  });
}
