import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/background_service.dart';

/// Tests for the Dart side of the background-run hold (foreground service
/// bridge). The native side is exercised by the e2e suite on the Android
/// emulator; here we verify the channel contract and — critically — that
/// every failure path degrades to a no-op instead of crashing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('zagents/background');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start/update/stop round-trip through the method channel', () async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return true;
    });

    final BackgroundRunService service = BackgroundRunService();
    expect(service.isActive, isFalse);

    await service.start(title: 'ZAgents agent is running', text: 'Processing…');
    expect(service.isActive, isTrue);
    expect(calls.single.method, 'start');
    expect(calls.single.arguments['title'], 'ZAgents agent is running');
    expect(calls.single.arguments['text'], 'Processing…');

    await service.updateStatus('Step 1 · browser_navigate');
    expect(calls, hasLength(2));
    expect(calls.last.method, 'update');
    expect(calls.last.arguments['text'], 'Step 1 · browser_navigate');

    await service.stop();
    expect(service.isActive, isFalse);
    expect(calls, hasLength(3));
    expect(calls.last.method, 'stop');
  });

  test('updateStatus is skipped while inactive (no channel traffic)',
      () async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return true;
    });

    final BackgroundRunService service = BackgroundRunService();
    await service.updateStatus('Step 1 · browser_click');
    expect(calls, isEmpty); // never started → nothing sent
  });

  test('missing platform implementation never throws', () async {
    // No mock handler registered → invokeMethod throws
    // MissingPluginException, which must be swallowed.
    final BackgroundRunService service = BackgroundRunService();

    await service.start(title: 't', text: 'x');
    expect(service.isActive, isFalse);
    expect(service.lastOperationSucceeded, isFalse);

    // Still safe afterwards: update is skipped, stop is a no-op.
    await service.updateStatus('Step 1 · read_file');
    await service.stop();
    expect(service.isActive, isFalse);
  });

  test('platform returning null / throwing keeps the Dart side safe',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'start') return null; // ambiguous platform answer
      if (call.method == 'update') throw PlatformException(code: 'boom');
      return true;
    });

    final BackgroundRunService service = BackgroundRunService();
    await service.start(title: 't', text: 'x');
    expect(service.isActive, isFalse); // null is treated as failure
    expect(service.lastOperationSucceeded, isFalse);

    await service.updateStatus('Step 1 · scroll'); // must not throw
    await service.stop(); // inactive → no channel call, must not throw
  });
}
