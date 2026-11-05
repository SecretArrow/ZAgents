import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zagents/models/cron_job.dart';
import 'package:zagents/services/cron_repository.dart';

CronJob _job(String id, {String expression = '0 8 * * *'}) => CronJob(
  id: id,
  name: 'Job $id',
  expression: expression,
  action: CronActionKind.telegram,
  telegramToken: 't',
  telegramChatId: 'c',
  messageText: 'hello',
  createdAtMs: 1000,
);

void main() {
  group('PrefsCronRepository', () {
    test('empty store loads defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PrefsCronRepository repo = await PrefsCronRepository.create();
      final CronState state = repo.load();
      expect(state.jobs, isEmpty);
      expect(state.history, isEmpty);
      expect(state.enabled, isTrue);
    });

    test('many jobs survive a save/load roundtrip (unbounded list)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PrefsCronRepository repo = await PrefsCronRepository.create();
      final List<CronJob> jobs = <CronJob>[
        for (var i = 0; i < 25; i++)
          _job('job-$i', expression: '*/${(i % 59) + 1} * * * *'),
      ];
      await repo.save(
        CronState(
          jobs: jobs,
          history: <CronRunEntry>[
            const CronRunEntry(
              jobId: 'job-0',
              jobName: 'Job job-0',
              atMs: 42,
              ok: true,
              detail: 'sent',
            ),
          ],
        ),
      );
      final CronState reloaded = repo.load();
      expect(reloaded.jobs.length, 25);
      expect(reloaded.jobs[7].id, 'job-7');
      expect(reloaded.jobs[7].expression, '*/8 * * * *');
      expect(reloaded.jobs[7].action, CronActionKind.telegram);
      expect(reloaded.jobs.last.name, 'Job job-24');
      expect(reloaded.history.single.detail, 'sent');
    });

    test('history is capped at 30 newest-first entries', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PrefsCronRepository repo = await PrefsCronRepository.create();
      final List<CronRunEntry> history = <CronRunEntry>[
        for (var i = 0; i < 40; i++)
          CronRunEntry(
            jobId: 'j',
            jobName: 'J',
            atMs: 1000 - i,
            ok: true,
            detail: 'run-$i',
          ),
      ];
      await repo.save(CronState(history: history));
      final CronState reloaded = repo.load();
      expect(reloaded.history.length, PrefsCronRepository.historyCap);
      expect(reloaded.history.length, 30);
      expect(reloaded.history.first.detail, 'run-0');
    });

    test('corrupted JSON degrades to defaults instead of crashing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'zagents.cronjobs.v1': '{not json',
      });
      final PrefsCronRepository repo = await PrefsCronRepository.create();
      expect(repo.load().jobs, isEmpty);
    });

    test('all three action kinds roundtrip through JSON', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PrefsCronRepository repo = await PrefsCronRepository.create();
      await repo.save(
        CronState(
          jobs: <CronJob>[
            CronJob(
              id: 'a',
              name: 'A',
              expression: '* * * * *',
              action: CronActionKind.notification,
              notifTitle: 'T',
              notifText: 'B',
              createdAtMs: 1,
            ),
            CronJob(
              id: 'b',
              name: 'B',
              expression: '* * * * *',
              action: CronActionKind.agent,
              agentPrompt: 'do it',
              createdAtMs: 2,
            ),
          ],
        ),
      );
      final CronState reloaded = repo.load();
      expect(reloaded.jobs[0].action, CronActionKind.notification);
      expect(reloaded.jobs[1].action, CronActionKind.agent);
      expect(reloaded.jobs[1].agentPrompt, 'do it');
    });
  });
}
