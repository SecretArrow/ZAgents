import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/js_runtime.dart';

/// Inner runtime whose runs take a controllable amount of time and record
/// their lifecycle, so tests can prove parallel calls execute one after
/// another (never interleaved inside one hidden WebView).
class _SlowScriptedRuntime implements JsRuntime {
  final List<String> events = <String>[];
  final List<Completer<void>> gates = <Completer<void>>[];

  /// Resolves when the run at [index] may finish. Waits (event-loop)
  /// until that run has actually started — callers may release before the
  /// serialized wrapper got a chance to invoke the inner runtime.
  Future<void> release(int index) async {
    while (gates.length <= index) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    gates[index].complete();
  }

  @override
  Future<JsRunResult> run(
    String code, {
    List<String> moduleRoots = const <String>[],
    String? workingDir,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final Completer<void> gate = Completer<void>();
    gates.add(gate);
    events.add('start:$code');
    await gate.future;
    events.add('end:$code');
    if (code == 'explode') {
      throw StateError('boom');
    }
    return JsRunResult(output: code, result: '"$code"');
  }

  @override
  Future<JsRunResult> runModule(ModuleInvocation invocation) async =>
      JsRunResult(output: invocation.entrySource);

  @override
  void dispose() => events.add('dispose');
}

void main() {
  group('SerializedJsRuntime', () {
    test('runs submitted in parallel execute strictly one at a time', () async {
      final inner = _SlowScriptedRuntime();
      final runtime = SerializedJsRuntime(inner);

      // Two chat sessions fire node_run at the same moment.
      final f1 = runtime.run('first');
      final f2 = runtime.run('second');

      // Neither may finish until its gate opens; the second must not have
      // STARTED before the first ends (no interleaving in one WebView).
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(inner.events, <String>['start:first']);

      await inner.release(0);
      await f1;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(inner.events, <String>[
        'start:first',
        'end:first',
        'start:second',
      ]);

      await inner.release(1);
      final r2 = await f2;
      expect(inner.events.last, 'end:second');
      expect(r2.result, '"second"');
    });

    test('a failing run does not poison the queue', () async {
      final inner = _SlowScriptedRuntime();
      final runtime = SerializedJsRuntime(inner);

      final f1 = runtime.run('explode');
      final f2 = runtime.run('after');
      await inner.release(0);
      await expectLater(f1, throwsA(isA<StateError>()));

      await inner.release(1);
      final r2 = await f2;
      expect(r2.output, 'after');
      expect(inner.events, contains('start:after'));
    });

    test('results and errors from the inner runtime pass through', () async {
      final inner = _SlowScriptedRuntime();
      final runtime = SerializedJsRuntime(inner);

      final f1 = runtime.run('ok');
      await inner.release(0);
      final ok = await f1;
      expect(ok.ok, isTrue);
      expect(ok.output, 'ok');

      final f2 = runtime.run('explode');
      await inner.release(1);
      final bad = await f2.catchError((Object e) {
        return JsRunResult(output: '', error: '$e');
      });
      expect(bad.error, isNotNull);
    });

    test('dispose forwards to the inner runtime', () async {
      final inner = _SlowScriptedRuntime();
      final runtime = SerializedJsRuntime(inner);
      runtime.dispose();
      expect(inner.events, <String>['dispose']);
    });
  });
}
