import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Manual localization layer (no codegen) so CI stays deterministic.
///
/// Two languages are supported:
/// * English — the default (`languageCode: 'en'`), always used on first run
///   regardless of the device locale.
/// * Bahasa Indonesia (`languageCode: 'id'`) — selectable in Settings.
///
/// [appStringsFor] also works without a [BuildContext] so controllers
/// (Riverpod notifiers) can produce localized error messages.

/// Locale codes the app can render.
const List<String> supportedLanguageCodes = <String>['en', 'id'];

/// Human-readable native names for the language picker.
const Map<String, String> languageNames = <String, String>{
  'en': 'English',
  'id': 'Bahasa Indonesia',
};

/// Default language used when no preference is stored.
const String defaultLanguageCode = 'en';

/// Resolves [languageCode] to a strings bundle; unknown codes fall back to
/// English.
AppStrings appStringsFor(String languageCode) =>
    languageCode.toLowerCase().startsWith('id')
    ? AppStringsId()
    : AppStringsEn();

/// Lookup wrapper registered through a [LocalizationsDelegate].
class ZLocalizations {
  const ZLocalizations(this.locale, this.strings);

  final Locale locale;
  final AppStrings strings;

  static ZLocalizations of(BuildContext context) =>
      Localizations.of<ZLocalizations>(context, ZLocalizations)!;
}

/// Convenience accessor for widgets.
AppStrings stringsOf(BuildContext context) =>
    Localizations.of<ZLocalizations>(context, ZLocalizations)!.strings;

const LocalizationsDelegate<ZLocalizations> zLocalizationsDelegate =
    _ZLocalizationsDelegate();

class _ZLocalizationsDelegate extends LocalizationsDelegate<ZLocalizations> {
  const _ZLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      supportedLanguageCodes.contains(locale.languageCode);

  @override
  Future<ZLocalizations> load(Locale locale) =>
      SynchronousFuture<ZLocalizations>(
        ZLocalizations(locale, appStringsFor(locale.languageCode)),
      );

  @override
  bool shouldReload(_ZLocalizationsDelegate old) => false;
}

/// Every user-facing string in the app.
abstract class AppStrings {
  // -- Generic ---------------------------------------------------------
  String get menu;
  String get settings;
  String get cancel;
  String get delete;
  String get send;
  String get stop;
  String get result;
  String get resultError;
  String get screenshotUnavailable;
  String get thinking;
  String get readPageText;

  // -- Home / chat -----------------------------------------------------
  String get askAnything;
  String get newChat;
  String get historyTitle;
  String get historyLoadFailed;
  String get noChats;
  String get deleteChatTitle;
  String get deleteChatBody;
  String get pickModel;
  String get customModelHint;
  String get searchModelsHint;
  String get filterAll;
  String get filterTools;
  String get filterFree;
  String get refreshCatalog;
  String get modelsRetry;
  String get modelsLoadError;
  String get modelsEmpty;
  String get modelsEmptyHint;
  String get modelsApiKeyHint;
  String get suggestedFallback;
  String get suggestedFallbackBody;
  String get toolsBadge;
  String get freeBadge;
  String get browseModels;
  String get browseModelsHint;
  String pageIndicator(int current, int total);
  String get agentTagline;
  String get emptySubtitle;
  List<String> get suggestions;

  // -- Settings --------------------------------------------------------
  String get providerSection;
  String get providerPreset;
  String get baseUrlLabel;
  String get apiKeyLabel;
  String get apiKeyStoredLocally;
  String get modelLabel;
  String get modelHint;
  String get agentSection;
  String get agentModeTitle;
  String get agentModeSubtitle;
  String get automationTitle;
  String get automationSubtitle;
  String get runInBackgroundTitle;
  String get runInBackgroundSubtitle;
  String get maxStepsTitle;
  String get languageSection;
  String get languageSubtitle;
  String get englishOption;
  String get indonesianOption;
  String get aboutSection;
  String get aboutBody;

  // -- Controller messages (no BuildContext available) -----------------
  String get missingApiKey;
  String get modelNotSet;
  String get stoppedMarkdown;
  String get chatOpenError;
  String get chatDeleteError;

  // -- Background service notification (no BuildContext available) -----
  String get notifTitle;
  String get notifProcessing;
  String notifStep(int step, String tool);
}

/// English strings (default).
class AppStringsEn implements AppStrings {
  const AppStringsEn();

  // -- Generic ---------------------------------------------------------
  @override
  String get menu => 'Menu';
  @override
  String get settings => 'Settings';
  @override
  String get cancel => 'Cancel';
  @override
  String get delete => 'Delete';
  @override
  String get send => 'Send';
  @override
  String get stop => 'Stop';
  @override
  String get result => 'result';
  @override
  String get resultError => 'result (error)';
  @override
  String get screenshotUnavailable => 'screenshot unavailable';
  @override
  String get thinking => 'thinking…';
  @override
  String get readPageText => 'Read page text';

  // -- Home / chat -----------------------------------------------------
  @override
  String get askAnything => 'Ask anything…';
  @override
  String get newChat => 'New chat';
  @override
  String get historyTitle => 'History';
  @override
  String get historyLoadFailed => 'Failed to load history.';
  @override
  String get noChats => 'No conversations yet.';
  @override
  String get deleteChatTitle => 'Delete conversation?';
  @override
  String get deleteChatBody => 'This conversation will be permanently deleted.';
  @override
  String get pickModel => 'Pick a model';
  @override
  String get customModelHint => 'Custom model (e.g. openai/gpt-4o-mini)';
  @override
  String get searchModelsHint => 'Search models…';
  @override
  String get filterAll => 'All';
  @override
  String get filterTools => 'Tools';
  @override
  String get filterFree => 'Free';
  @override
  String get refreshCatalog => 'Refresh catalog';
  @override
  String get modelsRetry => 'Retry';
  @override
  String get modelsLoadError => 'Failed to load the model list.';
  @override
  String get modelsEmpty => 'No models match';
  @override
  String get modelsEmptyHint =>
      'Try another keyword or filter — some providers do not advertise '
      'tool support.';
  @override
  String get modelsApiKeyHint =>
      'Enter your API key in Settings to browse the full model catalog '
      'of your provider.';
  @override
  String get suggestedFallback => 'SUGGESTED MODELS';
  @override
  String get suggestedFallbackBody =>
      'Showing suggested models instead. Check your connection or the '
      'Base URL, then retry.';
  @override
  String get toolsBadge => 'tools';
  @override
  String get freeBadge => 'FREE';
  @override
  String get browseModels => 'Browse models';
  @override
  String get browseModelsHint =>
      'Tap the search icon to browse the live model catalog.';
  @override
  String pageIndicator(int current, int total) => 'Page $current of $total';
  @override
  String get agentTagline => 'AI Agent · Flutter';
  @override
  String get emptySubtitle =>
      'Your on-device AI agent — browse, take screenshots,\n'
      'and manage files right from chat.';
  @override
  List<String> get suggestions => const <String>[
    'Open wikipedia.org and summarize its main page',
    "Search today's Bitcoin price and take a screenshot",
    'Create a notes.txt file with my daily plan',
    'Explain how tool calling works in LLMs',
  ];

  // -- Settings --------------------------------------------------------
  @override
  String get providerSection => 'AI provider';
  @override
  String get providerPreset => 'Provider preset';
  @override
  String get baseUrlLabel => 'Base URL (OpenAI-compatible)';
  @override
  String get apiKeyLabel => 'API key';
  @override
  String get apiKeyStoredLocally =>
      'Stored only on this device. InferHub keys look like sk-airo-…';
  @override
  String get modelLabel => 'Model';
  @override
  String get modelHint => 'e.g. z-ai/glm-4.6 or anthropic/claude-sonnet-4.5';
  @override
  String get agentSection => 'Agent';
  @override
  String get agentModeTitle => 'Agent mode';
  @override
  String get agentModeSubtitle =>
      'Enable tool calling: browsing, screenshots, files. '
      'Turn off for plain chat.';
  @override
  String get automationTitle => 'Browser automation';
  @override
  String get automationSubtitle =>
      'Let the agent control the embedded browser.';
  @override
  String get runInBackgroundTitle => 'Run in background';
  @override
  String get runInBackgroundSubtitle =>
      'Keep the agent working when you leave the app '
      '(shows a progress notification).';
  @override
  String get maxStepsTitle => 'Max agent steps';
  @override
  String get languageSection => 'Language';
  @override
  String get languageSubtitle => 'App interface language. Default: English.';
  @override
  String get englishOption => 'English (default)';
  @override
  String get indonesianOption => 'Bahasa Indonesia';
  @override
  String get aboutSection => 'About';
  @override
  String get aboutBody =>
      'ZAgents v1.3.0 — an Android clone of the chat.z.ai agent mode UI, '
      'with custom OpenAI-compatible providers (OpenRouter, InferHub, '
      'Z.AI, OpenAI, DeepSeek, Groq, and more). Agent tasks can keep '
      'running in the background. Your API key is stored only on this '
      'device.';

  // -- Controller messages ----------------------------------------------
  @override
  String get missingApiKey =>
      'API key is not set. Open Settings to configure your provider.';
  @override
  String get modelNotSet =>
      'No model selected. Pick one in Settings or from the model menu.';
  @override
  String get stoppedMarkdown => '_(stopped)_';
  @override
  String get chatOpenError => 'Could not open this conversation.';
  @override
  String get chatDeleteError => 'Could not delete this conversation.';

  // -- Background service notification ----------------------------------
  @override
  String get notifTitle => 'ZAgents agent is running';
  @override
  String get notifProcessing => 'Processing your request…';
  @override
  String notifStep(int step, String tool) => 'Step $step · $tool';
}

/// Bahasa Indonesia strings.
class AppStringsId implements AppStrings {
  const AppStringsId();

  // -- Generic ---------------------------------------------------------
  @override
  String get menu => 'Menu';
  @override
  String get settings => 'Pengaturan';
  @override
  String get cancel => 'Batal';
  @override
  String get delete => 'Hapus';
  @override
  String get send => 'Kirim';
  @override
  String get stop => 'Hentikan';
  @override
  String get result => 'hasil';
  @override
  String get resultError => 'hasil (error)';
  @override
  String get screenshotUnavailable => 'screenshot tidak tersedia';
  @override
  String get thinking => 'berpikir…';
  @override
  String get readPageText => 'Baca teks halaman';

  // -- Home / chat -----------------------------------------------------
  @override
  String get askAnything => 'Tanya apa saja…';
  @override
  String get newChat => 'Percakapan baru';
  @override
  String get historyTitle => 'Riwayat';
  @override
  String get historyLoadFailed => 'Gagal memuat riwayat.';
  @override
  String get noChats => 'Belum ada percakapan.';
  @override
  String get deleteChatTitle => 'Hapus percakapan?';
  @override
  String get deleteChatBody => 'Percakapan ini akan dihapus permanen.';
  @override
  String get pickModel => 'Pilih model';
  @override
  String get customModelHint => 'Model kustom (mis. openai/gpt-4o-mini)';
  @override
  String get searchModelsHint => 'Cari model…';
  @override
  String get filterAll => 'Semua';
  @override
  String get filterTools => 'Tools';
  @override
  String get filterFree => 'Gratis';
  @override
  String get refreshCatalog => 'Segarkan katalog';
  @override
  String get modelsRetry => 'Coba lagi';
  @override
  String get modelsLoadError => 'Gagal memuat daftar model.';
  @override
  String get modelsEmpty => 'Tidak ada model yang cocok';
  @override
  String get modelsEmptyHint =>
      'Coba kata kunci atau filter lain — sebagian provider tidak '
      'mengiklankan dukungan tools.';
  @override
  String get modelsApiKeyHint =>
      'Masukkan API key di Pengaturan untuk melihat katalog model '
      'lengkap dari provider Anda.';
  @override
  String get suggestedFallback => 'MODEL YANG DISARANKAN';
  @override
  String get suggestedFallbackBody =>
      'Menampilkan model yang disarankan. Periksa koneksi atau Base URL, '
      'lalu coba lagi.';
  @override
  String get toolsBadge => 'tools';
  @override
  String get freeBadge => 'GRATIS';
  @override
  String get browseModels => 'Lihat daftar model';
  @override
  String get browseModelsHint =>
      'Ketuk ikon pencarian untuk melihat katalog model langsung.';
  @override
  String pageIndicator(int current, int total) =>
      'Halaman $current dari $total';
  @override
  String get agentTagline => 'AI Agent · Flutter';
  @override
  String get emptySubtitle =>
      'Agent AI di perangkat Anda — browsing, screenshot,\n'
      'dan kelola file langsung dari chat.';
  @override
  List<String> get suggestions => const <String>[
    'Buka wikipedia.org lalu rangkum halaman utamanya',
    'Cari harga Bitcoin hari ini dan ambil screenshot',
    'Buat file catatan.txt berisi rencana harian',
    'Jelaskan cara kerja tool calling pada LLM',
  ];

  // -- Settings --------------------------------------------------------
  @override
  String get providerSection => 'Provider AI';
  @override
  String get providerPreset => 'Preset provider';
  @override
  String get baseUrlLabel => 'Base URL (OpenAI-compatible)';
  @override
  String get apiKeyLabel => 'API key';
  @override
  String get apiKeyStoredLocally =>
      'Disimpan hanya di perangkat ini. Key InferHub berformat sk-airo-…';
  @override
  String get modelLabel => 'Model';
  @override
  String get modelHint => 'mis. z-ai/glm-4.6 atau anthropic/claude-sonnet-4.5';
  @override
  String get agentSection => 'Agent';
  @override
  String get agentModeTitle => 'Mode Agent';
  @override
  String get agentModeSubtitle =>
      'Aktifkan tool calling: browsing, screenshot, file. '
      'Matikan untuk chat biasa.';
  @override
  String get automationTitle => 'Otomasi browser';
  @override
  String get automationSubtitle =>
      'Izinkan agent mengendalikan browser tersemat.';
  @override
  String get runInBackgroundTitle => 'Jalankan di latar belakang';
  @override
  String get runInBackgroundSubtitle =>
      'Agent tetap bekerja saat keluar dari aplikasi '
      '(menampilkan notifikasi progres).';
  @override
  String get maxStepsTitle => 'Maks. langkah agent';
  @override
  String get languageSection => 'Bahasa';
  @override
  String get languageSubtitle => 'Bahasa antarmuka aplikasi. Bawaan: English.';
  @override
  String get englishOption => 'English (bawaan)';
  @override
  String get indonesianOption => 'Bahasa Indonesia';
  @override
  String get aboutSection => 'Tentang';
  @override
  String get aboutBody =>
      'ZAgents v1.3.0 — klon UI agent mode chat.z.ai untuk Android, '
      'dengan custom provider OpenAI-compatible (OpenRouter, InferHub, '
      'Z.AI, OpenAI, DeepSeek, Groq, dan lainnya). Tugas agent dapat '
      'tetap berjalan di latar belakang. API key disimpan hanya di '
      'penyimpanan lokal perangkat.';

  // -- Controller messages ----------------------------------------------
  @override
  String get missingApiKey =>
      'API key belum diisi. Buka Pengaturan untuk mengatur provider.';
  @override
  String get modelNotSet =>
      'Model belum dipilih. Pilih di Pengaturan atau dari menu model.';
  @override
  String get stoppedMarkdown => '_(dihentikan)_';
  @override
  String get chatOpenError => 'Gagal membuka percakapan ini.';
  @override
  String get chatDeleteError => 'Gagal menghapus percakapan ini.';

  // -- Background service notification ----------------------------------
  @override
  String get notifTitle => 'Agent ZAgents sedang berjalan';
  @override
  String get notifProcessing => 'Memproses permintaan Anda…';
  @override
  String notifStep(int step, String tool) => 'Langkah $step · $tool';
}
