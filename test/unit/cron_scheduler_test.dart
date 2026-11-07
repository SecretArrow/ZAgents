import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/models/cron_job.dart';
import 'package:zagents/services/cron_repository.dart';
import 'package:zagents/services/cron_scheduler.dart';
import 'package:zagents/services/llm_client.dart';
import 'package:zagents/services/telegram_sender.dart';
import 'package:zagents/services/tool_executor.dart';

import '../support/test_doubles.dart';

class FakeDispatcher implements CronActionDispatcher {
  FakeDispatcher([
    this.result = const CronDispatchResult(ok: true, detail: 'sent'),
  ]);

  CronDispatchResult result;
  final List<CronJob> calls = <CronJob>[];

  @override
  Future<CronDispatchResult> dispatch(CronJob job) async {
    calls.add(job);
    return result;
  }
}

CronJob _job(
  String id, {
  String expression = '* * * * *',
  int? nextRunAtMs,
  bool enabled = true,
  CronActionKind action = CronActionKind.telegram,
}) => CronJob(
  id: id,
  name: 'Job $id',
  expression: expression,
  action: action,
  telegramToken: 'tok',
  telegramChatId: 'chat',
  messageText: 'm',
  enabled: enabled,
  createdAtMs: 0,
  nextRunAtMs: nextRunAtMs,
);

void main() {
  // Fixed anchor: Wednesday 2026-01-14 10:30 local.
  final DateTime now = DateTime(2026, 1, 14, 10, 30);

  group('CronSchedulerCore.dueJobs', () {
    test('returns enabled jobs whose nextRunAt is due', () {
      const CronSchedulerCore core = CronSchedulerCore();
      final CronState state = CronState(
        jobs: <CronJob>[
          _job('due', nextRunAtMs: now.millisecondsSinceEpoch - 1),
          _job('future', nextRunAtMs: now.millisecondsSinceEpoch + 60000),
          _job(
            'disabled',
            nextRunAtMs: now.millisecondsSinceEpoch - 1,
            enabled: false,
          ),
          _job('unscheduled', nextRunAtMs: null),
        ],
      );
      final List<CronJob> due = core.dueJobs(state, now);
      expect(due.map((j) => j.id), <String>['due']);
    });

    test('master switch off pauses everything without touching jobs', () {
      const CronSchedulerCore core = CronSchedulerCore();
      final CronState state = CronState(
        enabled: false,
        jobs: <CronJob>[_job('due', nextRunAtMs: now.millisecondsSinceEpoch)],
      );
      expect(core.dueJobs(state, now), isEmpty);
    });
  });

  group('CronSchedulerCore.rescheduleMissed', () {
    test('re-anchors past jobs WITHOUT firing them', () {
      const CronSchedulerCore core = CronSchedulerCore();
      final CronState state = CronState(
        jobs: <CronJob>[
          _job(
            'missed',
            expression: '0 8 * * *',
            nextRunAtMs: DateTime(2026, 1, 14, 8).millisecondsSinceEpoch,
          ),
        ],
      );
      final CronState? next = core.rescheduleMissed(state, now);
      expect(next, isNotNull);
      expect(
        next!.jobs.single.nextRunAtMs,
        DateTime(2026, 1, 15, 8).millisecondsSinceEpoch,
      );
    });

    test('future and disabled jobs are left untouched', () {
      const CronSchedulerCore core = CronSchedulerCore();
      final CronState state = CronState(
        jobs: <CronJob>[
          _job('future', nextRunAtMs: now.millisecondsSinceEpoch + 1),
          _job(
            'disabled',
            nextRunAtMs: now.millisecondsSinceEpoch - 1,
            enabled: false,
          ),
        ],
      );
      expect(core.rescheduleMissed(state, now), isNull);
    });

    test(
      'an invalid stored expression clears nextRunAt instead of crashing',
      () {
        const CronSchedulerCore core = CronSchedulerCore();
        final CronState state = CronState(
          jobs: <CronJob>[
            _job(
              'bad',
              expression: '99 * * * *',
              nextRunAtMs: now.millisecondsSinceEpoch - 1,
            ),
          ],
        );
        final CronState? next = core.rescheduleMissed(state, now);
        expect(next!.jobs.single.nextRunAtMs, isNull);
      },
    );
  });

  group('CronSchedulerService', () {
    late ProviderContainer container;
    late MemoryCronRepository repo;
    late FakeDispatcher dispatcher;
    late CronSchedulerService scheduler;

    /// Boots a fresh container. The seed lands in the repository BEFORE
    /// the controller is first read, so the stale nextRunAtMs survives
    /// (saveJob would re-anchor it to the next real occurrence).
    void boot({CronState? seed}) {
      repo = MemoryCronRepository(seed);
      container = ProviderContainer(
        overrides: <Override>[
          cronRepositoryProvider.overrideWithValue(repo),
          cronClockProvider.overrideWithValue(() => now),
        ],
      );
      dispatcher = FakeDispatcher();
      scheduler = CronSchedulerService(
        controller: container.read(cronJobsProvider.notifier),
        readState: () => container.read(cronJobsProvider),
        dispatcher: dispatcher,
        now: () => now,
      );
    }

    tearDown(() {
      scheduler.stop();
      container.dispose();
    });

    test(
      'tick fires a due job, records history and advances nextRun',
      () async {
        boot(
          seed: CronState(
            jobs: <CronJob>[
              _job('a', nextRunAtMs: now.millisecondsSinceEpoch - 1),
            ],
          ),
        );

        await scheduler.tick();

        expect(dispatcher.calls, hasLength(1));
        final CronState state = repo.load();
        expect(state.history, hasLength(1));
        expect(state.history.single.jobId, 'a');
        expect(state.history.single.ok, isTrue);
        expect(state.history.single.detail, 'sent');
        expect(
          state.jobs.single.nextRunAtMs,
          greaterThan(now.millisecondsSinceEpoch),
        );
        expect(state.jobs.single.lastResultOk, isTrue);
      },
    );

    test('a failed dispatch is recorded as a failure, not thrown', () async {
      boot(
        seed: CronState(
          jobs: <CronJob>[
            _job('b', nextRunAtMs: now.millisecondsSinceEpoch - 1),
          ],
        ),
      );
      dispatcher.result = const CronDispatchResult(
        ok: false,
        detail: 'HTTP 400: chat not found',
      );

      await scheduler.tick();

      final CronState state = repo.load();
      expect(state.history.single.ok, isFalse);
      expect(state.history.single.detail, contains('chat not found'));
      expect(state.jobs.single.lastResultOk, isFalse);
      // A failed run still advances the schedule (no hot retry loop).
      expect(
        state.jobs.single.nextRunAtMs,
        greaterThan(now.millisecondsSinceEpoch),
      );
    });

    test('tick skips jobs when the master switch is off', () async {
      boot(
        seed: CronState(
          enabled: false,
          jobs: <CronJob>[
            _job('c', nextRunAtMs: now.millisecondsSinceEpoch - 1),
          ],
        ),
      );
      await scheduler.tick();
      expect(dispatcher.calls, isEmpty);
      expect(repo.load().history, isEmpty);
    });

    test('a job disabled mid-store is not fired', () async {
      boot(
        seed: CronState(
          jobs: <CronJob>[
            _job(
              'x',
              nextRunAtMs: now.millisecondsSinceEpoch - 1,
              enabled: false,
            ),
          ],
        ),
      );
      await scheduler.tick();
      expect(dispatcher.calls, isEmpty);
    });

    test('start() applies missed-run recovery before ticking', () async {
      boot(
        seed: CronState(
          jobs: <CronJob>[
            _job(
              'd',
              expression: '0 8 * * *',
              nextRunAtMs: DateTime(2026, 1, 14, 8).millisecondsSinceEpoch,
            ),
          ],
        ),
      );

      await scheduler.start();

      final CronState state = repo.load();
      expect(
        state.jobs.single.nextRunAtMs,
        DateTime(2026, 1, 15, 8).millisecondsSinceEpoch,
      );
      expect(dispatcher.calls, isEmpty); // recovery never fires
      expect(scheduler.isRunning, isTrue);
    });

    test('runNow fires immediately and records history', () async {
      boot(
        seed: CronState(jobs: <CronJob>[_job('e', expression: '0 0 * * *')]),
      );
      dispatcher.calls.clear();

      final CronDispatchResult result = await scheduler.runNow(
        repo.load().jobs.single,
      );

      expect(result.ok, isTrue);
      expect(dispatcher.calls, hasLength(1));
      expect(repo.load().history, hasLength(1));
    });

    test('saveJob recomputes nextRunAt from the (fixed-clock) now', () async {
      boot();
      await container
          .read(cronJobsProvider.notifier)
          .saveJob(_job('f', expression: '0 8 * * *'));
      final CronState state = repo.load();
      expect(
        state.jobs.single.nextRunAtMs,
        DateTime(2026, 1, 15, 8).millisecondsSinceEpoch,
      );
    });
  });

  group('DefaultCronDispatcher — chat action (v1.50.0)', () {
    CronJob chatJob({String sessionId = ''}) => CronJob(
      id: 'chat-1',
      name: 'Chat job',
      expression: '0 9 * * *',
      action: CronActionKind.chat,
      agentPrompt: 'summarize the news',
      chatSessionId: sessionId,
      createdAtMs: 0,
    );

    DefaultCronDispatcher dispatcher(
      Future<String?> Function(String? sessionId, String prompt) runner,
    ) => DefaultCronDispatcher(
      llm: LlmClient(),
      telegram: TelegramSender(),
      background: RecordingBackgroundRun(),
      executeTool: (
        String name,
        Map<String, dynamic> args, {
        String? sessionId,
        String? browserContext,
      }) async => const ToolResult(ok: true, llmOutput: 'unused'),
      resolveConfig: () => const LlmConfig(
        baseUrl: 'https://example.invalid',
        apiKey: 'k',
        model: 'm',
      ),
      runInChat: runner,
    );

    test('accepted run forwards target+prompt and reports success', () async {
      String? seenSession;
      String? seenPrompt;
      final CronDispatchResult result = await dispatcher((
        session,
        prompt,
      ) async {
        seenSession = session;
        seenPrompt = prompt;
        return null;
      }).dispatch(chatJob(sessionId: 'session-42'));

      expect(result.ok, isTrue);
      expect(result.detail, 'prompt sent to chat');
      expect(seenSession, 'session-42');
      expect(seenPrompt, 'summarize the news');
    });

    test('empty target maps to null (new chat per fire)', () async {
      String? seenSession;
      await dispatcher((session, prompt) async {
        seenSession = session;
        return null;
      }).dispatch(chatJob());

      expect(seenSession, isNull);
    });

    test('a refusal reason becomes a recorded failure detail', () async {
      final CronDispatchResult result = await dispatcher(
        (session, prompt) async => 'chat busy',
      ).dispatch(chatJob(sessionId: 's1'));

      expect(result.ok, isFalse);
      expect(result.detail, 'chat busy');
    });

    test('a null runner fails the fire instead of crashing', () async {
      final CronJob job = chatJob();
      final CronDispatchResult result = await DefaultCronDispatcher(
        llm: LlmClient(),
        telegram: TelegramSender(),
        background: RecordingBackgroundRun(),
        executeTool: (
          String name,
          Map<String, dynamic> args, {
          String? sessionId,
          String? browserContext,
        }) async => const ToolResult(ok: true, llmOutput: 'unused'),
        resolveConfig: () => const LlmConfig(
          baseUrl: 'https://example.invalid',
          apiKey: 'k',
          model: 'm',
        ),
      ).dispatch(job);

      expect(result.ok, isFalse);
      expect(result.detail, 'chat runner unavailable');
    });
  });
}
