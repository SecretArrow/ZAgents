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
  String get open;
  String get share;
  String get rename;
  String get copy;
  String get cut;
  String get paste;
  String get save;
  String get edit;
  String get add;
  String get confirm;
  String get operationFailed;

  // -- Home / chat -----------------------------------------------------
  String get askAnything;
  String get attachFile;
  String get newChat;
  String get historyTitle;
  String get historyLoadFailed;
  String get noChats;
  String get deleteChatTitle;
  String get deleteChatBody;
  String get renameChatTitle;
  String get nameHint;
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
  String get searchProvidersHint;
  String get searchSessionsHint;
  String get searchFilesHint;
  String get searchContextHint;
  String get searchLibsHint;
  String get noResults;
  String get agentTagline;
  String get emptySubtitle;
  List<String> get suggestions;

  // -- Files manager ----------------------------------------------------
  String get filesTitle;
  String get filesEmpty;
  String get filesHint;
  String get newFolder;
  String get newFolderTitle;
  String get compress;
  String get extractHere;
  String get noPreview;
  String get filePreviewTitle;
  String get clipboardCopied;
  String get clipboardCut;
  String get pastedOk;
  String get zipCreatedOk;
  String get unzippedOk;
  String get deleteEntryTitle;
  String get deleteEntryBody;

  // -- Context Manager ---------------------------------------------------
  String get contextSection;
  String get contextManagerTitle;
  String get contextManagerHint;
  String contextActiveCount(int n);
  String get addContext;
  String get editContext;
  String get contextNameLabel;
  String get contextContentLabel;
  String get contextEnabledLabel;
  String get deleteContextTitle;
  String get deleteContextBody;
  String get contextEmpty;

  // -- Node.js runtime ---------------------------------------------------
  String get nodeSection;
  String get nodeManagerTitle;
  String get nodeManagerHint;
  String nodeInstalledCount(int n);
  String get nodeAddHint;
  String get nodeAddButton;
  String get nodeVersionHint;
  String get nodeEmpty;
  String get nodeInstalling;
  String get nodeDescription;
  String get nodeRemoveTitle;
  String get nodeRemoveBody;

  // -- Appearance --------------------------------------------------------
  String get appearanceSection;
  String get themeLight;
  String get themeDark;
  String get themeSystem;

  // -- User Agent (browser identity) -------------------------------------
  String get uaSection;
  String get uaModeTitle;
  String get uaModeSubtitle;
  String get uaModeAuto;
  String get uaModeDesktop;
  String get uaModeAndroid;
  String get uaModeHint;
  String get uaCurrentLabel;
  String get uaRotateTooltip;

  // -- Settings --------------------------------------------------------
  String get providerSection;
  String get providerPreset;
  String get baseUrlLabel;
  String get apiKeyLabel;
  String get apiKeyStoredLocally;
  String get modelLabel;
  String get modelHint;
  String get presetsTitle;
  String get savePreset;
  String get savePresetTitle;
  String get presetNameLabel;
  String get editPreset;
  String get deletePresetTitle;
  String get deletePresetBody;
  String get presetHasKey;
  String get presetNoKey;

  // -- Providers management (v1.5.0) -----------------------------------
  String get providersTileSubtitle;
  String get providersTitle;
  String get providersHint;
  String get addProvider;
  String get newProviderTitle;
  String get activeBadge;
  String get useProviderTooltip;
  String providerActivatedSnack(String name);
  String get saveApiKey;
  String get apiKeySavedSnack;
  String get fetchModels;
  String get fetchingModels;
  String modelsFetchedSnack(int n);
  String get modelsCachedNote;
  String modelsCachedCount(int n);
  String get noModelsYet;
  String get nameRequiredError;
  String get urlRequiredError;
  String get duplicateNameError;
  String get providerSavedSnack;
  String get providerDeletedSnack;
  String get keyStatusSection;

  String get maxStepsTitle;
  String get maxStepsHint;
  String get runUntilDoneTitle;
  String get runUntilDoneSubtitle;
  String get runUntilDoneHint;
  String maxStepsReachedMarkdown(int steps);
  String get agentSection;
  String get agentModeTitle;
  String get agentModeSubtitle;
  String get automationTitle;
  String get automationSubtitle;
  String get runInBackgroundTitle;
  String get runInBackgroundSubtitle;
  String get languageSection;
  String get languageSubtitle;
  String get englishOption;
  String get indonesianOption;
  String get dataSection;
  String get exportSessions;
  String get importSessions;
  String exportDone(String path);
  String importDone(int count);
  String get importFailed;
  String get aboutSection;
  String get aboutBody;

  // -- Controller messages (no BuildContext available) -----------------
  String get missingApiKey;
  String get modelNotSet;
  String get stoppedMarkdown;
  String get chatOpenError;
  String get chatDeleteError;
  String get chatRenameError;

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
  @override
  String get open => 'Open';
  @override
  String get share => 'Share';
  @override
  String get rename => 'Rename';
  @override
  String get copy => 'Copy';
  @override
  String get cut => 'Cut';
  @override
  String get paste => 'Paste';
  @override
  String get save => 'Save';
  @override
  String get edit => 'Edit';
  @override
  String get add => 'Add';
  @override
  String get confirm => 'OK';
  @override
  String get operationFailed => 'Operation failed.';

  // -- Home / chat -----------------------------------------------------
  @override
  String get askAnything => 'Ask anything…';
  @override
  String get attachFile => 'Attach file';
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
  String get renameChatTitle => 'Rename conversation';
  @override
  String get nameHint => 'Name';
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
  String get searchProvidersHint => 'Search providers…';
  @override
  String get searchSessionsHint => 'Search chats…';
  @override
  String get searchFilesHint => 'Search files…';
  @override
  String get searchContextHint => 'Search contexts…';
  @override
  String get searchLibsHint => 'Search libraries…';
  @override
  String get noResults => 'No results';
  @override
  String get agentTagline => 'AI Agent · Flutter';
  @override
  String get emptySubtitle =>
      'Your on-device AI agent — browse, take screenshots,\n'
      'run code, and manage files right from chat.';
  @override
  List<String> get suggestions => const <String>[
    'Open wikipedia.org and summarize its main page',
    "Search today's Bitcoin price and take a screenshot",
    'Create a notes.txt file with my daily plan',
    'Run JavaScript to parse this JSON I attached',
  ];

  // -- Files manager ----------------------------------------------------
  @override
  String get filesTitle => 'Files';
  @override
  String get filesEmpty => 'No files yet.';
  @override
  String get filesHint =>
      'Files created by the agent (write_file) and your uploads live here. '
      'Copy, paste, zip and share them.';
  @override
  String get newFolder => 'New folder';
  @override
  String get newFolderTitle => 'New folder';
  @override
  String get compress => 'Compress to ZIP';
  @override
  String get extractHere => 'Extract';
  @override
  String get noPreview => 'No preview available for this file type.';
  @override
  String get filePreviewTitle => 'Preview';
  @override
  String get clipboardCopied => 'Copied.';
  @override
  String get clipboardCut => 'Cut. Paste it in another folder.';
  @override
  String get pastedOk => 'Pasted.';
  @override
  String get zipCreatedOk => 'ZIP created.';
  @override
  String get unzippedOk => 'Extracted.';
  @override
  String get deleteEntryTitle => 'Delete?';
  @override
  String get deleteEntryBody => 'This item will be permanently deleted.';

  // -- Context Manager ---------------------------------------------------
  @override
  String get contextSection => 'Context';
  @override
  String get contextManagerTitle => 'Context manager';
  @override
  String get contextManagerHint =>
      'Reusable prompt blocks. Enabled entries are sent with every request '
      'so the agent always follows your rules.';
  @override
  String contextActiveCount(int n) => '$n active';
  @override
  String get addContext => 'Add context';
  @override
  String get editContext => 'Edit context';
  @override
  String get contextNameLabel => 'Name';
  @override
  String get contextContentLabel => 'Content (sent as prompt context)';
  @override
  String get contextEnabledLabel => 'Use this context';
  @override
  String get deleteContextTitle => 'Delete context?';
  @override
  String get deleteContextBody =>
      'This context entry will be permanently deleted.';
  @override
  String get contextEmpty =>
      'No context entries yet. Add rules the agent should always follow.';

  // -- Node.js runtime ---------------------------------------------------
  @override
  String get nodeSection => 'Node.js runtime';
  @override
  String get nodeManagerTitle => 'Node.js runtime & modules';
  @override
  String get nodeManagerHint =>
      'An embedded JavaScript runtime the agent can use to process data. '
      'Install npm packages it needs and remove them when done.';
  @override
  String nodeInstalledCount(int n) => '$n package(s) installed';
  @override
  String get nodeAddHint => 'Package name, e.g. lodash';
  @override
  String get nodeAddButton => 'Install';
  @override
  String get nodeVersionHint => 'Version (optional)';
  @override
  String get nodeEmpty => 'No packages installed yet.';
  @override
  String get nodeInstalling => 'Installing…';
  @override
  String get nodeDescription =>
      'node_run lets the agent execute JavaScript with require(), fs and '
      'fetch. Packages are downloaded from the npm registry and stored in '
      'the app sandbox.';
  @override
  String get nodeRemoveTitle => 'Remove package?';
  @override
  String get nodeRemoveBody => 'The package files will be deleted.';

  // -- Appearance --------------------------------------------------------
  @override
  String get appearanceSection => 'Appearance';
  @override
  String get themeLight => 'Light';
  @override
  String get themeDark => 'Dark';
  @override
  String get themeSystem => 'System';

  // -- User Agent ---------------------------------------------------------
  @override
  String get uaSection => 'User Agent';
  @override
  String get uaModeTitle => 'User-Agent Mode';
  @override
  String get uaModeSubtitle =>
      'Applied to the embedded browser the agent browses with.';
  @override
  String get uaModeAuto => 'Auto (device default)';
  @override
  String get uaModeDesktop => 'PC/Desktop';
  @override
  String get uaModeAndroid => 'Android Mobile';
  @override
  String get uaModeHint =>
      'Auto uses an Android identity that matches this device and stays '
      'stable for the whole session. PC/Desktop also switches page layout '
      'to desktop rendering.';
  @override
  String get uaCurrentLabel => 'Active User-Agent';
  @override
  String get uaRotateTooltip => 'Use another User-Agent';

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
      'Each preset keeps its own key, stored only on this device. '
      'InferHub keys look like sk-airo-…';
  @override
  String get modelLabel => 'Model';
  @override
  String get modelHint => 'e.g. z-ai/glm-4.6 or anthropic/claude-sonnet-4.5';
  @override
  String get presetsTitle => 'Presets (each keeps its own API key)';
  @override
  String get savePreset => 'Save current as preset';
  @override
  String get savePresetTitle => 'Save preset';
  @override
  String get presetNameLabel => 'Preset name';
  @override
  String get editPreset => 'Edit preset';
  @override
  String get deletePresetTitle => 'Delete preset?';
  @override
  String get deletePresetBody => 'The preset and its stored key are removed.';
  @override
  String get presetHasKey => 'key saved';
  @override
  String get presetNoKey => 'no key';

  // -- Providers management (v1.5.0) -----------------------------------
  @override
  String get providersTileSubtitle => 'Manage providers, API keys and models';
  @override
  String get providersTitle => 'Providers';
  @override
  String get providersHint =>
      'Tap a provider to edit it. Each provider stores its own API key '
      'and model list.';
  @override
  String get addProvider => 'Add provider';
  @override
  String get newProviderTitle => 'New provider';
  @override
  String get activeBadge => 'ACTIVE';
  @override
  String get useProviderTooltip => 'Use this provider';
  @override
  String providerActivatedSnack(String name) => 'Connected to $name';
  @override
  String get saveApiKey => 'Save API key';
  @override
  String get apiKeySavedSnack => 'API key saved for this provider';
  @override
  String get fetchModels => 'Fetch models';
  @override
  String get fetchingModels => 'Fetching…';
  @override
  String modelsFetchedSnack(int n) => '$n models available';
  @override
  String get modelsCachedNote =>
      'Showing the last fetched list for this provider.';
  @override
  String modelsCachedCount(int n) => '$n models cached';
  @override
  String get noModelsYet =>
      'No models fetched yet — tap “Fetch models” to load the list from '
      'this provider.';
  @override
  String get nameRequiredError => 'Name is required.';
  @override
  String get urlRequiredError => 'Base URL is required.';
  @override
  String get duplicateNameError => 'A provider with this name already exists.';
  @override
  String get providerSavedSnack => 'Provider saved';
  @override
  String get providerDeletedSnack => 'Provider deleted';
  @override
  String get keyStatusSection => 'Key status';

  @override
  String get maxStepsTitle => 'Max agent steps';
  @override
  String get maxStepsHint =>
      'How many tool-call rounds the agent may take (1-100). Type a custom '
      'value or use the slider.';
  @override
  String get runUntilDoneTitle => 'Run until done';
  @override
  String get runUntilDoneSubtitle =>
      'The agent keeps working until the task is really finished instead of '
      'stopping at the steps cap (recommended). Turn off to enforce the '
      'limit below.';
  @override
  String maxStepsReachedMarkdown(int steps) =>
      '*Paused: reached the max agent steps limit ($steps). The task may not '
      'be finished — raise the limit in Settings or keep “Run until done” '
      'enabled.*';
  @override
  String get runUntilDoneHint =>
      'Bypassed while “Run until done” is on — the agent works until the '
      'task is finished.';
  @override
  String get agentSection => 'Agent';
  @override
  String get agentModeTitle => 'Agent mode';
  @override
  String get agentModeSubtitle =>
      'Enable tool calling: browsing, screenshots, files, code. '
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
  String get languageSection => 'Language';
  @override
  String get languageSubtitle => 'App interface language. Default: English.';
  @override
  String get englishOption => 'English (default)';
  @override
  String get indonesianOption => 'Bahasa Indonesia';
  @override
  String get dataSection => 'Data';
  @override
  String get exportSessions => 'Export sessions';
  @override
  String get importSessions => 'Import sessions';
  @override
  String exportDone(String path) => 'Exported to $path';
  @override
  String importDone(int count) => '$count session(s) imported.';
  @override
  String get importFailed => 'Import failed: not a valid export file.';
  @override
  String get aboutSection => 'About';
  @override
  String get aboutBody =>
      'ZAgents v1.4.0 — an Android clone of the chat.z.ai agent mode UI, '
      'with custom OpenAI-compatible providers (OpenRouter, InferHub, '
      'Z.AI, OpenAI, DeepSeek, Groq, and more), per-provider API keys, '
      'light/dark themes, multi-session chat with background running, '
      'file uploads, a Context Manager, an in-app file manager with '
      'zip support, and an embedded Node.js-style runtime with npm '
      'package management. Your keys stay on this device.';

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
  @override
  String get chatRenameError => 'Could not rename this conversation.';

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
  @override
  String get open => 'Buka';
  @override
  String get share => 'Bagikan';
  @override
  String get rename => 'Ganti nama';
  @override
  String get copy => 'Salin';
  @override
  String get cut => 'Potong';
  @override
  String get paste => 'Tempel';
  @override
  String get save => 'Simpan';
  @override
  String get edit => 'Ubah';
  @override
  String get add => 'Tambah';
  @override
  String get confirm => 'OK';
  @override
  String get operationFailed => 'Operasi gagal.';

  // -- Home / chat -----------------------------------------------------
  @override
  String get askAnything => 'Tanya apa saja…';
  @override
  String get attachFile => 'Lampirkan file';
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
  String get renameChatTitle => 'Ganti nama percakapan';
  @override
  String get nameHint => 'Nama';
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
  String get searchProvidersHint => 'Cari provider…';
  @override
  String get searchSessionsHint => 'Cari chat…';
  @override
  String get searchFilesHint => 'Cari file…';
  @override
  String get searchContextHint => 'Cari context…';
  @override
  String get searchLibsHint => 'Cari pustaka…';
  @override
  String get noResults => 'Tidak ada hasil';
  @override
  String get agentTagline => 'AI Agent · Flutter';
  @override
  String get emptySubtitle =>
      'Agent AI di perangkat Anda — browsing, screenshot,\n'
      'jalankan kode, dan kelola file langsung dari chat.';
  @override
  List<String> get suggestions => const <String>[
    'Buka wikipedia.org lalu rangkum halaman utamanya',
    'Cari harga Bitcoin hari ini dan ambil screenshot',
    'Buat file catatan.txt berisi rencana harian',
    'Jalankan JavaScript untuk memproses JSON yang saya lampirkan',
  ];

  // -- Files manager ----------------------------------------------------
  @override
  String get filesTitle => 'File';
  @override
  String get filesEmpty => 'Belum ada file.';
  @override
  String get filesHint =>
      'File yang dibuat agent (write_file) dan hasil unggahan Anda ada di '
      'sini. Salin, tempel, zip, dan bagikan.';
  @override
  String get newFolder => 'Folder baru';
  @override
  String get newFolderTitle => 'Folder baru';
  @override
  String get compress => 'Kompres ke ZIP';
  @override
  String get extractHere => 'Ekstrak';
  @override
  String get noPreview => 'Pratinjau tidak tersedia untuk tipe file ini.';
  @override
  String get filePreviewTitle => 'Pratinjau';
  @override
  String get clipboardCopied => 'Disalin.';
  @override
  String get clipboardCut => 'Dipotong. Tempel di folder lain.';
  @override
  String get pastedOk => 'Ditempel.';
  @override
  String get zipCreatedOk => 'ZIP dibuat.';
  @override
  String get unzippedOk => 'Diekstrak.';
  @override
  String get deleteEntryTitle => 'Hapus?';
  @override
  String get deleteEntryBody => 'Item ini akan dihapus permanen.';

  // -- Context Manager ---------------------------------------------------
  @override
  String get contextSection => 'Konteks';
  @override
  String get contextManagerTitle => 'Manajer konteks';
  @override
  String get contextManagerHint =>
      'Blok prompt yang bisa dipakai ulang. Entri yang aktif dikirim dengan '
      'setiap permintaan agar agent selalu mengikuti aturan Anda.';
  @override
  String contextActiveCount(int n) => '$n aktif';
  @override
  String get addContext => 'Tambah konteks';
  @override
  String get editContext => 'Ubah konteks';
  @override
  String get contextNameLabel => 'Nama';
  @override
  String get contextContentLabel => 'Isi (dikirim sebagai konteks prompt)';
  @override
  String get contextEnabledLabel => 'Pakai konteks ini';
  @override
  String get deleteContextTitle => 'Hapus konteks?';
  @override
  String get deleteContextBody => 'Entri konteks ini akan dihapus permanen.';
  @override
  String get contextEmpty =>
      'Belum ada entri konteks. Tambahkan aturan yang harus selalu '
      'diikuti agent.';

  // -- Node.js runtime ---------------------------------------------------
  @override
  String get nodeSection => 'Runtime Node.js';
  @override
  String get nodeManagerTitle => 'Runtime & modul Node.js';
  @override
  String get nodeManagerHint =>
      'Runtime JavaScript tersemat yang bisa dipakai agent untuk memproses '
      'data. Instal package npm yang dibutuhkan dan hapus saat selesai.';
  @override
  String nodeInstalledCount(int n) => '$n package terpasang';
  @override
  String get nodeAddHint => 'Nama package, mis. lodash';
  @override
  String get nodeAddButton => 'Instal';
  @override
  String get nodeVersionHint => 'Versi (opsional)';
  @override
  String get nodeEmpty => 'Belum ada package terpasang.';
  @override
  String get nodeInstalling => 'Menginstal…';
  @override
  String get nodeDescription =>
      'node_run memungkinkan agent menjalankan JavaScript dengan require(), '
      'fs, dan fetch. Package diunduh dari registry npm dan disimpan di '
      'sandbox aplikasi.';
  @override
  String get nodeRemoveTitle => 'Hapus package?';
  @override
  String get nodeRemoveBody => 'File package akan dihapus.';

  // -- Appearance --------------------------------------------------------
  @override
  String get appearanceSection => 'Tampilan';
  @override
  String get themeLight => 'Terang';
  @override
  String get themeDark => 'Gelap';
  @override
  String get themeSystem => 'Sistem';

  // -- User Agent ---------------------------------------------------------
  @override
  String get uaSection => 'User Agent';
  @override
  String get uaModeTitle => 'Mode User-Agent';
  @override
  String get uaModeSubtitle =>
      'Berlaku untuk browser tersemat yang dipakai agent untuk browsing.';
  @override
  String get uaModeAuto => 'Otomatis (ikut perangkat)';
  @override
  String get uaModeDesktop => 'PC/Desktop';
  @override
  String get uaModeAndroid => 'Android Mobile';
  @override
  String get uaModeHint =>
      'Otomatis memakai identitas Android yang sesuai dengan perangkat ini '
      'dan tetap stabil selama sesi. Mode PC/Desktop juga mengubah tata '
      'letak halaman menjadi rendering desktop.';
  @override
  String get uaCurrentLabel => 'User-Agent aktif';
  @override
  String get uaRotateTooltip => 'Pakai User-Agent lain';

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
      'Setiap preset menyimpan key-nya sendiri, hanya di perangkat ini. '
      'Key InferHub berformat sk-airo-…';
  @override
  String get modelLabel => 'Model';
  @override
  String get modelHint => 'mis. z-ai/glm-4.6 atau anthropic/claude-sonnet-4.5';
  @override
  String get presetsTitle => 'Preset (masing-masing punya API key sendiri)';
  @override
  String get savePreset => 'Simpan sebagai preset';
  @override
  String get savePresetTitle => 'Simpan preset';
  @override
  String get presetNameLabel => 'Nama preset';
  @override
  String get editPreset => 'Ubah preset';
  @override
  String get deletePresetTitle => 'Hapus preset?';
  @override
  String get deletePresetBody => 'Preset beserta key tersimpannya dihapus.';
  @override
  String get presetHasKey => 'key tersimpan';
  @override
  String get presetNoKey => 'tanpa key';

  // -- Providers management (v1.5.0) -----------------------------------
  @override
  String get providersTileSubtitle =>
      'Kelola provider, API key, dan daftar model';
  @override
  String get providersTitle => 'Provider';
  @override
  String get providersHint =>
      'Ketuk provider untuk mengubahnya. Setiap provider menyimpan API key '
      'dan daftar modelnya sendiri.';
  @override
  String get addProvider => 'Tambah provider';
  @override
  String get newProviderTitle => 'Provider baru';
  @override
  String get activeBadge => 'AKTIF';
  @override
  String get useProviderTooltip => 'Gunakan provider ini';
  @override
  String providerActivatedSnack(String name) => 'Terhubung ke $name';
  @override
  String get saveApiKey => 'Simpan API key';
  @override
  String get apiKeySavedSnack => 'API key tersimpan untuk provider ini';
  @override
  String get fetchModels => 'Ambil daftar model';
  @override
  String get fetchingModels => 'Mengambil…';
  @override
  String modelsFetchedSnack(int n) => '$n model tersedia';
  @override
  String get modelsCachedNote =>
      'Menampilkan daftar terakhir yang berhasil diambil dari provider ini.';
  @override
  String modelsCachedCount(int n) => '$n model tersimpan';
  @override
  String get noModelsYet =>
      'Belum ada model — ketuk “Ambil daftar model” untuk memuat daftar '
      'dari provider ini.';
  @override
  String get nameRequiredError => 'Nama wajib diisi.';
  @override
  String get urlRequiredError => 'Base URL wajib diisi.';
  @override
  String get duplicateNameError => 'Provider dengan nama ini sudah ada.';
  @override
  String get providerSavedSnack => 'Provider tersimpan';
  @override
  String get providerDeletedSnack => 'Provider dihapus';
  @override
  String get keyStatusSection => 'Status key';

  @override
  String get maxStepsTitle => 'Maks. langkah agent';
  @override
  String get maxStepsHint =>
      'Jumlah maksimum putaran tool-call agent (1-100). Isi angka kustom '
      'atau gunakan slider.';
  @override
  String get runUntilDoneTitle => 'Jalankan sampai selesai';
  @override
  String get runUntilDoneSubtitle =>
      'Agent terus bekerja sampai tugas benar-benar selesai alih-alih '
      'berhenti di batas langkah (disarankan). Matikan untuk menerapkan '
      'batas di bawah.';
  @override
  String maxStepsReachedMarkdown(int steps) =>
      '*Berhenti sementara: batas maks. langkah agent ($steps) tercapai. '
      'Tugas mungkin belum selesai — naikkan batas di Pengaturan atau '
      'biarkan “Jalankan sampai selesai” aktif.*';
  @override
  String get runUntilDoneHint =>
      'Dinonaktifkan selama “Jalankan sampai selesai” aktif — agent bekerja '
      'sampai tugas selesai.';
  @override
  String get agentSection => 'Agent';
  @override
  String get agentModeTitle => 'Mode Agent';
  @override
  String get agentModeSubtitle =>
      'Aktifkan tool calling: browsing, screenshot, file, kode. '
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
  String get languageSection => 'Bahasa';
  @override
  String get languageSubtitle => 'Bahasa antarmuka aplikasi. Bawaan: English.';
  @override
  String get englishOption => 'English (bawaan)';
  @override
  String get indonesianOption => 'Bahasa Indonesia';
  @override
  String get dataSection => 'Data';
  @override
  String get exportSessions => 'Ekspor sesi';
  @override
  String get importSessions => 'Impor sesi';
  @override
  String exportDone(String path) => 'Diekspor ke $path';
  @override
  String importDone(int count) => '$count sesi diimpor.';
  @override
  String get importFailed => 'Impor gagal: file ekspor tidak valid.';
  @override
  String get aboutSection => 'Tentang';
  @override
  String get aboutBody =>
      'ZAgents v1.4.0 — klon UI agent mode chat.z.ai untuk Android, '
      'dengan custom provider OpenAI-compatible (OpenRouter, InferHub, '
      'Z.AI, OpenAI, DeepSeek, Groq, dan lainnya), API key per-provider, '
      'tema terang/gelap, multi-sesi dengan proses latar belakang, '
      'unggah file, Manajer Konteks, manajer file dengan dukungan zip, '
      'serta runtime bergaya Node.js tersemat dengan manajemen package '
      'npm. Key Anda tetap di perangkat ini.';

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
  @override
  String get chatRenameError => 'Gagal mengganti nama percakapan ini.';

  // -- Background service notification ----------------------------------
  @override
  String get notifTitle => 'Agent ZAgents sedang berjalan';
  @override
  String get notifProcessing => 'Memproses permintaan Anda…';
  @override
  String notifStep(int step, String tool) => 'Langkah $step · $tool';
}
