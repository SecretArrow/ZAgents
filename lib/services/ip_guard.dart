import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../di.dart';
import '../l10n/app_strings.dart';

/// Chat-switch IP guard (v1.48.0): before a user-initiated switch into a
/// chat, optionally compare the device's current public IP with the last
/// IP recorded for THAT chat and ask for confirmation when they match.
///
/// Failure contract: the guard is a convenience warning, never a gate.
/// ANY problem fetching or parsing the IP (offline, timeout, captive
/// portal HTML, garbage body) degrades silently to "no warning, proceed".
/// The recorded memo is only refreshed when the current IP is actually
/// known — a failed fetch never overwrites previously stored data.
class IpGuard {
  IpGuard({required this.prefs, Future<String?> Function()? fetchIp})
    : _fetchIpOverride = fetchIp,
      client = null,
      timeout = defaultTimeout;

  /// Creates the production guard with the default HTTP probe.
  ///
  /// [timeout] is injectable so tests can exercise the abort-on-stall path
  /// without waiting out the real 5 s budget.
  IpGuard.withClient({
    required this.prefs,
    this.client,
    this.timeout = defaultTimeout,
  }) : _fetchIpOverride = null;

  final Future<String?> Function()? _fetchIpOverride;

  /// Optional HTTP client override (tests inject a MockClient here).
  final http.Client? client;

  /// SharedPreferences holding the per-chat last-IP memo (injected via
  /// ipMemoPrefsProvider in production; a mock instance in tests).
  final SharedPreferences prefs;

  /// Plain-text public-IP echo service (no JSON, no HTML — the response
  /// body IS the address).
  static const String _ipEchoUrl = 'https://api.ipify.org';

  /// Production connect + response budget. A chat switch must stay snappy;
  /// when the probe cannot answer in time the switch simply proceeds
  /// unguarded.
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// Per-instance budget (see [IpGuard.withClient]).
  final Duration timeout;

  /// SharedPreferences key holding the per-chat last-IP memo
  /// (`{'<chatId>': '<ip>', ...}` as JSON, most-recent last, capped).
  static const String memoKey = 'zagents.ipmemo.v1';

  /// Upper bound of tracked chats. The memo is a rotating fingerprint of
  /// recent usage, not an archive — the oldest entry is dropped first.
  static const int memoCap = 200;

  /// Fetches the current public IP. Returns null whenever the address
  /// cannot be determined — callers must treat null as "skip the check".
  Future<String?> fetchPublicIp() async {
    if (_fetchIpOverride != null) return _fetchIpOverride();
    return _fetchIpFromClient(client ?? http.Client());
  }

  Future<String?> _fetchIpFromClient(http.Client client) async {
    try {
      final http.Response response = await client
          .get(
            Uri.parse(_ipEchoUrl),
            headers: <String, String>{'Accept': 'text/plain'},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      return normalizeIp(response.body);
    } catch (_) {
      // Offline / timeout / socket error / redirect-to-portal: the guard
      // degrades to "no warning, proceed".
      return null;
    }
  }

  /// Trims a candidate body and accepts it only when it looks like a
  /// plausible IPv4 or IPv6 literal — never HTML, JSON or an error page.
  /// Returns null for anything implausible.
  static String? normalizeIp(String body) {
    final String candidate = body.trim();
    if (candidate.isEmpty || candidate.length > 45) return null;
    // A literal address can only contain hex digits, dots and colons —
    // this alone rejects HTML pages, JSON envelopes and "invalid request"
    // prose from misbehaving mirrors.
    if (RegExp(r'^[0-9A-Fa-f.:]+$').allMatches(candidate).isEmpty) {
      return null;
    }
    if (_isPlausibleIpv4(candidate) || _isPlausibleIpv6(candidate)) {
      return candidate;
    }
    return null;
  }

  static bool _isPlausibleIpv4(String value) {
    final List<String> parts = value.split('.');
    if (parts.length != 4) return false;
    for (final String part in parts) {
      if (part.isEmpty || part.length > 3) return false;
      final int? octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return false;
    }
    return true;
  }

  static bool _isPlausibleIpv6(String value) {
    // Light validation on purpose: at least one ':' (so bare IPv4 never
    // takes this path), hex groups only, and a sane length. Full RFC 4291
    // parsing is overkill for a warning heuristic.
    if (!value.contains(':')) return false;
    if (RegExp(r':::{2,}').hasMatch(value)) return false;
    return RegExp(r'^[0-9A-Fa-f:]{2,45}$').hasMatch(value);
  }

  /// Centralized pre-switch check. Returns true when the caller may
  /// proceed with the chat switch, false when the user cancelled.
  ///
  /// Order of guarantees:
  /// 1. Setting off → allow immediately (no network call).
  /// 2. IP unknown → allow (never block on a failed probe).
  /// 3. No memo / different IP → allow AND refresh the memo.
  /// 4. Same IP → warn; Cancel → abort (false), Continue → refresh memo
  ///    and allow.
  Future<bool> confirmChatSwitch(
    BuildContext context,
    WidgetRef ref,
    String targetChatId,
  ) async {
    if (!ref.read(settingsProvider).ipSwitchWarnEnabled) return true;
    final String? currentIp = await fetchPublicIp();
    if (currentIp == null) return true;
    if (!context.mounted) return false;
    final String? lastIp = readMemo()[targetChatId];
    if (lastIp != null && lastIp == currentIp) {
      final AppStrings strings = stringsOf(context);
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          key: const Key('ip-switch-warn-dialog'),
          title: Text(strings.ipSwitchWarnDialogTitle),
          content: Text(strings.ipSwitchWarnDialogBody(currentIp)),
          actions: <Widget>[
            TextButton(
              key: const Key('ip-switch-warn-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const Key('ip-switch-warn-continue'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.ipSwitchWarnContinue),
            ),
          ],
        ),
      );
      if (proceed != true) return false;
    }
    // Refresh the memo BEFORE returning so the next switch compares
    // against fresh data (also covers the no-warning-needed path).
    recordMemo(targetChatId, currentIp);
    return true;
  }

  /// Reads the per-chat last-IP map. A missing/corrupted entry degrades to
  /// an empty map — the guard then behaves like "first visit".
  Map<String, String> readMemo() {
    try {
      final String? raw = prefs.getString(memoKey);
      if (raw == null || raw.isEmpty) return <String, String>{};
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, String>{};
      return <String, String>{
        for (final MapEntry<String, dynamic> e in decoded.entries)
          if (e.value is String) e.key: e.value as String,
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Stores [ip] as the last-seen IP for [chatId], marking it the most
  /// recent entry and evicting the oldest beyond [memoCap].
  void recordMemo(String chatId, String ip) {
    final Map<String, String> memo = readMemo()
      ..remove(chatId)
      ..[chatId] = ip;
    while (memo.length > memoCap) {
      memo.remove(memo.keys.first);
    }
    try {
      prefs.setString(memoKey, jsonEncode(memo));
    } catch (_) {
      // A failed memo write only means the next switch may warn once more.
    }
  }
}
