import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;

/// Free-disk probe — v1.53.0.
///
/// One-shot platform-channel query for the bytes available where model
/// files live (`freeDiskBytes` on `zagents/llmserver`; StatFs on the
/// Kotlin side). Returns null when the channel is unavailable (tests,
/// unsupported platforms) or the platform reports an error — callers
/// must treat null as "unknown, allow", so the downloader's disk guard
/// can never wedge the queue on a device it cannot measure.
class DiskSpace {
  static const MethodChannel _channel = MethodChannel('zagents/llmserver');

  /// Injectable invoke seam for tests; when null the real channel is
  /// used (which degrades to null off-platform like every other call
  /// on this channel).
  final Future<Object?> Function(String, {dynamic arguments})? invoke;

  const DiskSpace({this.invoke});

  /// Bytes available where model files live; null = unknown.
  Future<int?> freeDiskBytes() async {
    try {
      final Object? raw = invoke != null
          ? await invoke!('freeDiskBytes')
          : await _channel.invokeMethod<Object?>('freeDiskBytes');
      if (raw is int) return raw;
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
