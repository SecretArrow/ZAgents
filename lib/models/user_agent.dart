import '../data/user_agents.g.dart';

/// User-Agent selection mode (Settings → User Agent).
///
/// * [auto]    — pick the category that matches the device context: the
///   embedded browser engine IS an Android WebView, so Auto uses an Android
///   User-Agent (the truthful identity, best session stability).
/// * [desktop] — restrict selection to the PC/desktop pool (the classic
///   "desktop site" compatibility override).
/// * [android] — restrict selection to the Android pool.
enum UaMode { auto, desktop, android }

/// Parses the persisted mode name; unknown values fall back to [UaMode.auto].
UaMode uaModeFromName(String? name) {
  for (final UaMode mode in UaMode.values) {
    if (mode.name == name) return mode;
  }
  return UaMode.auto;
}

/// Category of a User-Agent record.
enum UserAgentCategory { desktop, android }

/// Browser family a User-Agent record represents.
enum UserAgentBrowser {
  chrome,
  edge,
  firefox,
  safari,
  opera,
  samsungInternet,
  vivaldi,
}

/// One entry of the bundled User-Agent database (500 records).
///
/// Every record was generated and format-validated by
/// `scripts/gen_user_agents.py` so [ua] matches the wire format of the real
/// browser it claims to be: Edge/EdgA majors equal their Chromium major,
/// Samsung Internet versions map to their real bundled Chromium, phone UAs
/// carry the `Mobile` token while tablet UAs never do, and Android versions
/// are plausible for each device model.
class UserAgentRecord {
  const UserAgentRecord({
    required this.id,
    required this.category,
    required this.browser,
    required this.label,
    required this.ua,
  });

  /// Stable id, unique across the whole database (1..500).
  final int id;

  final UserAgentCategory category;

  final UserAgentBrowser browser;

  /// Human-readable summary, e.g. `Chrome 143 · Windows 10/11` or
  /// `Samsung Internet 27 · Samsung Galaxy S24 (Android 15)`.
  final String label;

  /// The full User-Agent string as sent over the wire.
  final String ua;

  bool get isDesktop => category == UserAgentCategory.desktop;
}

/// All records (250 desktop + 250 Android), generated + validated.
List<UserAgentRecord> get userAgentDatabase => kUserAgentDatabase;

/// Records of one category, ordered by id.
List<UserAgentRecord> userAgentsOf(UserAgentCategory category) =>
    kUserAgentDatabase
        .where((UserAgentRecord r) => r.category == category)
        .toList();
