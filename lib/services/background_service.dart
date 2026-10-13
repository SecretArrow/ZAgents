import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps a running agent task alive when the user leaves the app.
///
/// On Android this drives [ZAgentsForegroundService] (foreground service +
/// partial wake lock + progress notification) through the
/// `zagents/background` method channel. While the service runs, Android
/// cannot freeze or kill the process, so the Dart agent loop and the
/// headless WebView automation keep working off-screen.
///
/// Everything is best-effort: a platform that does not implement the
/// channel (tests, unsupported OEM restriction) is swallowed and reported
/// through [lastOperationSucceeded] instead of ever crashing the app.
abstract class BackgroundRun {
  /// Starts the background hold. [title] is the notification title,
  /// [text] its initial body (e.g. "Processing…").
  Future<void> start({required String title, required String text});

  /// Replaces the notification body with the current agent step.
  Future<void> updateStatus(String text);

  /// Releases the hold and removes the notification.
  Future<void> stop();

  /// Whether the background hold is considered active right now.
  bool get isActive;
}

class BackgroundRunService implements BackgroundRun {
  static const MethodChannel _channel = MethodChannel('zagents/background');

  bool _active = false;
  bool _lastOperationSucceeded = false;

  /// Number of agent runs currently holding the service. With multi
  /// session the foreground service must stay up until EVERY run finishes,
  /// so start/stop are refcounted.
  int _holds = 0;

  @override
  bool get isActive => _active;

  /// False when the platform refused or lacked the channel — surfaced in
  /// tests and useful for debugging, never surfaced as a UI error.
  bool get lastOperationSucceeded => _lastOperationSucceeded;

  @override
  Future<void> start({required String title, required String text}) async {
    _holds++;
    if (_active) return; // Service already running for another session.
    try {
      _lastOperationSucceeded =
          await _channel.invokeMethod<bool>('start', <String, dynamic>{
            'title': title,
            'text': text,
          }) ??
          false;
      _active = _lastOperationSucceeded;
    } catch (_) {
      // MissingPluginException (tests) or platform failure: the agent run
      // continues in the foreground as before — never crash.
      _active = false;
      _lastOperationSucceeded = false;
    }
  }

  @override
  Future<void> updateStatus(String text) async {
    if (!_active) return;
    try {
      await _channel.invokeMethod<bool>('update', <String, dynamic>{
        'text': text,
      });
    } catch (_) {
      // A failed progress update must never abort the agent loop.
    }
  }

  @override
  Future<void> stop() async {
    if (_holds > 0) _holds--;
    if (_holds > 0 || !_active) return;
    _active = false;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {
      // Even if the channel call fails, the Dart side considers the hold
      // released; the native side also has safety valves (wake lock
      // timeout, service stop on task completion).
    }
  }
}

/// Overridable in tests with a recording fake.
final backgroundRunServiceProvider = Provider<BackgroundRun>(
  (ref) => BackgroundRunService(),
);
