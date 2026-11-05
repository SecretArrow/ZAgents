import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cron_job.dart';

/// Abstraction over the persistent cron store (jobs + history + master
/// switch). [load] is synchronous on purpose — it mirrors the
/// [PrefsSettingsRepository] contract so the Riverpod controller can
/// build state without awaiting platform channels.
abstract class CronRepository {
  CronState load();
  Future<void> save(CronState state);
}

/// Production [CronRepository] backed by SharedPreferences under
/// `zagents.cronjobs.v1`. The store holds an UNBOUNDED job list — the
/// user can create as many scheduled tasks as they want — plus a run
/// history capped at [historyCap] entries (newest first).
class PrefsCronRepository implements CronRepository {
  PrefsCronRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'zagents.cronjobs.v1';

  /// Maximum recorded runs kept in the history list.
  static const int historyCap = 30;

  static Future<PrefsCronRepository> create() async =>
      PrefsCronRepository(await SharedPreferences.getInstance());

  @override
  CronState load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return CronState();
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return CronState();
      return CronState.fromJson(decoded);
    } catch (_) {
      // Corrupted store: fall back to defaults rather than crash boot.
      return CronState();
    }
  }

  @override
  Future<void> save(CronState state) async {
    final List<CronRunEntry> history = state.history.length > historyCap
        ? state.history.sublist(0, historyCap)
        : state.history;
    await _prefs.setString(
      _key,
      jsonEncode(state.copyWith(history: history).toJson()),
    );
  }
}

/// In-memory repository for unit and widget tests.
class MemoryCronRepository implements CronRepository {
  MemoryCronRepository([CronState? initial])
    : _state = initial ?? CronState();

  CronState _state;

  @override
  CronState load() => _state;

  @override
  Future<void> save(CronState state) async => _state = state;
}
