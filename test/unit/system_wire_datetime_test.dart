import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/agent_controller.dart';

/// v1.54.0 — the wall-clock line the system wire carries so the model can
/// answer "today", handle relative dates and schedule work. The runtime
/// zone cannot be forced on a CI machine, so the default-offset case
/// asserts the shape via regex while explicit offsets pin the exact
/// output (whole-hour, negative and half-hour zones).
void main() {
  test('formats date, time and a whole-hour UTC offset exactly', () {
    expect(
      ChatController.systemWireDateTimeLine(
        DateTime(2026, 11, 11, 14, 3),
        offset: const Duration(hours: 7),
      ),
      'Current local date/time: 2026-11-11 14:03 (UTC+07:00).',
    );
    expect(
      ChatController.systemWireDateTimeLine(
        DateTime(2026, 11, 11, 14, 3),
        offset: const Duration(hours: -7),
      ),
      'Current local date/time: 2026-11-11 14:03 (UTC-07:00).',
    );
  });

  test('half-hour zones keep their minutes (e.g. UTC+05:30)', () {
    expect(
      ChatController.systemWireDateTimeLine(
        DateTime(2026, 11, 11, 14, 3),
        offset: const Duration(hours: 5, minutes: 30),
      ),
      'Current local date/time: 2026-11-11 14:03 (UTC+05:30).',
    );
  });

  test('default offset follows the runtime zone (regex-level)', () {
    expect(
      ChatController.systemWireDateTimeLine(DateTime(2026, 11, 11, 14, 3)),
      matches(
        RegExp(
          r'Current local date/time: \d{4}-\d{2}-\d{2} \d{2}:\d{2} '
          r'\(UTC[+-]\d{2}:\d{2}\)\.',
        ),
      ),
    );
  });
}
