import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Abstraction over persistent settings storage.
abstract class SettingsRepository {
  AppSettings load();
  Future<void> save(AppSettings settings);
}

/// SharedPreferences-backed repository used in production.
class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs);

  final SharedPreferences _prefs;
  static const String _key = 'zagents.settings.v1';

  static Future<PrefsSettingsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PrefsSettingsRepository(prefs);
  }

  @override
  AppSettings load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AppSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return AppSettings.fromJson(decoded);
    } catch (_) {
      // Corrupted settings: fall back to defaults.
    }
    return AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) =>
      _prefs.setString(_key, jsonEncode(settings.toJson()));
}

/// In-memory repository for unit and widget tests.
class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([AppSettings? initial])
    : _settings = initial ?? AppSettings();

  AppSettings _settings;

  @override
  AppSettings load() => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}
