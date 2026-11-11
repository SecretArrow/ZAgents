import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/l10n/app_strings_es.dart';
import 'package:zagents/models/models.dart';

void main() {
  group('AppStrings resolution', () {
    test('default language is English', () {
      expect(defaultLanguageCode, 'en');
      expect(defaultLanguageCode, AppSettings().languageCode);
    });

    test('unknown / empty codes fall back to English', () {
      expect(appStringsFor('xx'), isA<AppStringsEn>());
      expect(appStringsFor(''), isA<AppStringsEn>());
      expect(appStringsFor('ID'), isA<AppStringsId>()); // case-insensitive
    });

    test('English bundle exposes default wording', () {
      final AppStrings en = appStringsFor('en');
      expect(en.settings, 'Settings');
      expect(en.askAnything, 'Ask anything…');
      expect(en.englishOption, 'English (default)');
      expect(en.missingApiKey, contains('API key is not set'));
      expect(en.suggestions, isNotEmpty);
    });

    test('Indonesian bundle exposes translated wording', () {
      final AppStrings id = appStringsFor('id');
      expect(id.settings, 'Pengaturan');
      expect(id.askAnything, 'Tanya apa saja…');
      expect(id.indonesianOption, 'Bahasa Indonesia');
      expect(id.missingApiKey, contains('API key belum diisi'));
      expect(id.suggestions.length, appStringsFor('en').suggestions.length);
    });

    test('plan-first strings are localized in all three bundles', () {
      final AppStrings en = appStringsFor('en');
      final AppStrings id = appStringsFor('id');
      final AppStrings es = appStringsFor('es');
      expect(en.planFirstTitle, contains('Plan first'));
      expect(en.planTitle, 'Plan');
      expect(en.planProgress(2, 5), '2 of 5 done');
      expect(id.planFirstTitle, contains('rencana'));
      expect(id.planTitle, 'Rencana');
      expect(id.planProgress(2, 5), '2 dari 5 selesai');
      expect(es.planFirstTitle, contains('Planificar'));
      expect(es.planTitle, 'Plan');
      expect(es.planProgress(2, 5), '2 de 5 completadas');
    });

    test('live plan toggle + provider activation strings are localized', () {
      final AppStrings en = appStringsFor('en');
      final AppStrings id = appStringsFor('id');
      expect(en.showPlanTooltip, 'Show plan');
      expect(en.hidePlanTooltip, 'Hide plan');
      expect(en.activateProviderTitle, 'Activate provider');
      expect(en.activateProviderBody('X'), contains('X'));
      expect(en.activateProviderConfirm, 'Activate');
      expect(id.showPlanTooltip, 'Tampilkan rencana');
      expect(id.hidePlanTooltip, 'Sembunyikan rencana');
      expect(id.activateProviderTitle, 'Aktifkan provider');
      expect(id.activateProviderBody('X'), contains('X'));
      expect(id.activateProviderConfirm, 'Aktifkan');
      expect(en.providersHint, contains('long-press'));
      expect(id.providersHint, contains('long-press'));
    });

    test('encrypted zip password strings are localized', () {
      final AppStrings en = appStringsFor('en');
      final AppStrings id = appStringsFor('id');
      expect(en.unzipPasswordTitle, 'Password required');
      expect(en.unzipPasswordBody('a.zip'), contains('a.zip'));
      expect(en.passwordFieldHint, 'Password');
      expect(en.unzipPasswordConfirm, 'Extract');
      expect(en.wrongPassword, 'Wrong password.');
      expect(id.unzipPasswordTitle, 'Kata sandi diperlukan');
      expect(id.unzipPasswordBody('a.zip'), contains('a.zip'));
      expect(id.passwordFieldHint, 'Kata sandi');
      expect(id.unzipPasswordConfirm, 'Ekstrak');
      expect(id.wrongPassword, 'Kata sandi salah.');
    });
  });

  group('AppSettings language persistence', () {
    test('languageCode round-trips through JSON', () {
      final AppSettings original = AppSettings(apiKey: 'k', languageCode: 'id');
      final Map<String, dynamic> json = original.toJson();
      final AppSettings restored = AppSettings.fromJson(json);
      expect(restored.languageCode, 'id');
    });

    test('missing languageCode in JSON defaults to English', () {
      final AppSettings restored = AppSettings.fromJson(<String, dynamic>{});
      expect(restored.languageCode, 'en');
    });

    test('copyWith only changes languageCode', () {
      final AppSettings base = AppSettings(apiKey: 'k', model: 'm');
      final AppSettings updated = base.copyWith(languageCode: 'id');
      expect(updated.languageCode, 'id');
      expect(updated.apiKey, 'k');
      expect(updated.model, 'm');
      expect(updated.baseUrl, base.baseUrl);
    });
  });

  test('copy-message strings are localized in both bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    expect(en.copyMessage, 'Copy');
    expect(en.copied, 'Copied');
    expect(id.copyMessage, 'Salin');
    expect(id.copied, 'Tersalin');
  });

  test('edit/regenerate message strings are localized in both bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    expect(en.editMessageAction, 'Edit message');
    expect(en.editDialogTitle, 'Edit message');
    expect(en.regenerate, 'Regenerate');
    expect(id.editMessageAction, 'Edit pesan');
    expect(id.editDialogTitle, 'Edit pesan');
    expect(id.regenerate, 'Buat ulang');
  });

  test('global search strings are localized in both bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    expect(en.searchChats, 'Search chats');
    expect(en.searchHint, 'Search all conversations…');
    expect(en.noSearchResults, contains('conversations'));
    expect(id.searchChats, 'Cari chat');
    expect(id.searchHint, 'Cari semua percakapan…');
    expect(id.noSearchResults, contains('percakapan'));
  });

  test('auto-title + prompt library strings are localized in both bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    expect(en.autoTitleTitle, 'Automatic titles');
    expect(en.promptLibrary, 'Prompt library');
    expect(en.newPrompt, 'New prompt');
    expect(en.insertPrompt, contains('prompt library'));
    expect(id.autoTitleTitle, 'Judul otomatis');
    expect(id.promptLibrary, 'Pustaka prompt');
    expect(id.newPrompt, 'Prompt baru');
    expect(id.insertPrompt, contains('pustaka prompt'));
  });

  test('random UA prompt + creator strings are localized in both bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    expect(en.uaAskRandomTitle, contains('random User-Agent'));
    expect(en.randomUaDialogTitle, 'Random User-Agent');
    expect(en.randomUaAccept, 'Yes, randomize');
    expect(en.randomUaDecline, 'Keep current');
    expect(en.createdBy('Maragung'), 'Created by Maragung');
    expect(id.uaAskRandomTitle, contains('acak'));
    expect(id.randomUaDialogTitle, 'User-Agent acak');
    expect(id.randomUaAccept, 'Ya, acak');
    expect(id.randomUaDecline, 'Pertahankan');
    expect(id.createdBy('Maragung'), 'Dibuat oleh Maragung');
    expect(en.aboutBody, contains('OpenAI-compatible'));
    expect(id.aboutBody, contains('OpenAI-compatible'));
    // v1.41.5 — Help & About screen strings are localized end to end.
    expect(en.helpAboutSection, 'Help & About');
    expect(id.helpAboutSection, 'Bantuan & Tentang');
    expect(en.helpTileTitle, contains('Help'));
    expect(id.helpTileTitle, contains('Bantuan'));
    expect(en.helpTopics.length, 12);
    expect(id.helpTopics.length, 12);
    for (final HelpEntry t in en.helpTopics) {
      expect(t.title, isNotEmpty);
      expect(t.body.length, greaterThan(80));
    }
    for (final HelpEntry t in id.helpTopics) {
      expect(t.title, isNotEmpty);
      expect(t.body.length, greaterThan(80));
    }
    expect(en.aboutDisclaimer, contains('Maragung'));
    expect(id.aboutDisclaimer, contains('Maragung'));
    expect(en.aboutTagline, isNotEmpty);
    expect(id.aboutTagline, isNotEmpty);
    expect(en.autoRetryAirplaneNote, contains('Airplane mode'));
    expect(id.autoRetryAirplaneNote, contains('Mode pesawat'));
    expect(en.autoRetryAirplaneResumeNote, isNotEmpty);
    expect(id.autoRetryAirplaneResumeNote, isNotEmpty);
  });

  test('module doctor strings are localized in both bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    expect(en.moduleRepairCardTitle('m', '1'), contains('Module repair'));
    expect(en.moduleRepairCardBody('storage'), contains('storage'));
    expect(en.moduleRepairInstall, 'Install');
    expect(en.moduleRepairDiscard, 'Discard');
    expect(en.moduleRepairInstalled('m'), contains('m'));
    expect(en.moduleRepairInstallFailed('x'), contains('x'));
    expect(en.moduleExportTooltip, 'Export ZIP');
    expect(id.moduleRepairCardTitle('m', '1'), contains('Perbaikan modul'));
    expect(id.moduleRepairCardBody('storage'), contains('izin'));
    expect(id.moduleRepairInstall, 'Install');
    expect(id.moduleRepairDiscard, 'Buang');
    expect(id.moduleRepairInstalled('m'), contains('m'));
    expect(id.moduleRepairInstallFailed('x'), contains('x'));
    expect(id.moduleExportTooltip, 'Ekspor ZIP');
  });

  test('module builder strings are localized in both bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    expect(en.moduleBuildCardTitle('p', '1'), contains('New plugin ready'));
    expect(en.moduleBuildCardTitle('p', '1'), contains('p'));
    expect(en.moduleBuildCardBody('storage'), contains('storage'));
    expect(en.moduleBuildCardBody('storage'), contains('/plugins'));
    expect(en.moduleBuildInstalled('p'), contains('p'));
    expect(en.moduleBuildInstalled('p'), contains('/plugins'));
    expect(id.moduleBuildCardTitle('p', '1'), contains('Plugin baru siap'));
    expect(id.moduleBuildCardBody('storage'), contains('izin'));
    expect(id.moduleBuildCardBody('storage'), contains('/plugins'));
    expect(id.moduleBuildInstalled('p'), contains('p'));
    expect(id.moduleBuildInstalled('p'), contains('/plugins'));
  });

  test('v1.49 blocked/depends plan strings are localized in all bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    final AppStrings es = appStringsFor('es');
    expect(en.todoBlocked, 'Blocked');
    expect(id.todoBlocked, 'Terblokir');
    expect(es.todoBlocked, 'Bloqueado');
    expect(en.todoDependsOn, 'Depends on');
    expect(id.todoDependsOn, 'Bergantung pada');
    expect(es.todoDependsOn, 'Depende de');
  });

  test('v1.49 skills manager strings are localized in all bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    final AppStrings es = appStringsFor('es');
    for (final AppStrings s in <AppStrings>[en, id, es]) {
      expect(s.skillsTitle, isNotEmpty);
      expect(s.skillsSubtitle, isNotEmpty);
      expect(s.skillsInstallUrl, isNotEmpty);
      expect(s.skillsUrlTitle, isNotEmpty);
      expect(s.skillsUrlLabel, isNotEmpty);
      expect(s.skillsInstallZip, isNotEmpty);
      expect(s.skillsSearchHint, isNotEmpty);
      expect(s.skillsEmptyTitle, isNotEmpty);
      expect(s.skillsEmptyBody, isNotEmpty);
      expect(s.skillBundledInstall, isNotEmpty);
      expect(s.skillEnabled, isNotEmpty);
      expect(s.skillDisabled, isNotEmpty);
      expect(s.skillConfigure, isNotEmpty);
      expect(s.skillConfigSave, isNotEmpty);
      expect(s.skillConfigRequired, isNotEmpty);
      expect(s.skillConfigSecret, isNotEmpty);
      expect(s.skillInspect, isNotEmpty);
      expect(s.skillInstructions, isNotEmpty);
      expect(s.skillUpdate, isNotEmpty);
      expect(s.skillRemove, isNotEmpty);
      expect(s.skillRemoveTitle, isNotEmpty);
      expect(s.skillRemoveBody, isNotEmpty);
      expect(s.skillStatusChecking, isNotEmpty);
      expect(s.skillFiles, isNotEmpty);
      expect(s.skillSheetTitle, isNotEmpty);
      expect(s.skillSheetHint, isNotEmpty);
      expect(s.skillSheetUseGlobal, isNotEmpty);
      expect(s.skillSheetClear, isNotEmpty);
      expect(s.skillSheetApply, isNotEmpty);
      expect(s.drawerSkills, isNotEmpty);
      expect(s.settingsSkillsManager, isNotEmpty);
      expect(s.agentRouterHint, isNotEmpty);
    }
    expect(en.skillsTitle, 'Skills');
    expect(id.drawerSkills, 'Skills');
    expect(es.drawerSkills, 'Habilidades');
    expect(en.settingsSkillsManager, 'Skills manager');
    expect(id.settingsSkillsManager, 'Pengelola skill');
    expect(es.agentRouterHint, contains('Anthropic'));
  });

  test('cron job strings (v1.49.9) are localized in all three bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    final AppStrings es = appStringsFor('es');
    // Every cron string must be present in every bundle.
    for (final AppStrings s in <AppStrings>[en, id, es]) {
      expect(s.cronSectionTitle, isNotEmpty);
      expect(s.cronTileTitle, isNotEmpty);
      expect(s.cronTileSubtitle, isNotEmpty);
      expect(s.cronMasterTitle, isNotEmpty);
      expect(s.cronMasterSubtitle, isNotEmpty);
      expect(s.cronJobsEmptyTitle, isNotEmpty);
      expect(s.cronJobsEmptyBody, isNotEmpty);
      expect(s.cronAddJobTooltip, isNotEmpty);
      expect(s.cronNewTitle, isNotEmpty);
      expect(s.cronEditTitle, isNotEmpty);
      expect(s.cronFieldName, isNotEmpty);
      expect(s.cronFieldSchedule, isNotEmpty);
      expect(s.cronScheduleEveryMinute, isNotEmpty);
      expect(s.cronScheduleEvery5Minutes, isNotEmpty);
      expect(s.cronScheduleHourly, isNotEmpty);
      expect(s.cronScheduleDaily8, isNotEmpty);
      expect(s.cronScheduleWeekdays9, isNotEmpty);
      expect(s.cronScheduleWeekly, isNotEmpty);
      expect(s.cronScheduleMonthly, isNotEmpty);
      expect(s.cronScheduleCustom, isNotEmpty);
      expect(s.cronFieldExpression, isNotEmpty);
      expect(s.cronExpressionHint, isNotEmpty);
      expect(s.cronNextRuns, isNotEmpty);
      expect(s.cronFieldAction, isNotEmpty);
      expect(s.cronActionNotification, isNotEmpty);
      expect(s.cronActionTelegram, isNotEmpty);
      expect(s.cronActionAgent, isNotEmpty);
      expect(s.cronActionAgentHint, isNotEmpty);
      expect(s.cronActionChat, isNotEmpty);
      expect(s.cronActionChatHint, isNotEmpty);
      expect(s.cronFieldChatTarget, isNotEmpty);
      expect(s.cronChatNewEveryRun, isNotEmpty);
      expect(s.cronFieldChatPrompt, isNotEmpty);
      expect(s.cronChatPromptRequired, isNotEmpty);
      expect(s.cronChatTargetMissing, isNotEmpty);
      expect(s.cronFieldNotifTitle, isNotEmpty);
      expect(s.cronFieldNotifText, isNotEmpty);
      expect(s.cronFieldTelegramToken, isNotEmpty);
      expect(s.cronFieldTelegramChat, isNotEmpty);
      expect(s.cronFieldMessage, isNotEmpty);
      expect(s.cronFieldAgentPrompt, isNotEmpty);
      expect(s.cronAgentRelayHint, isNotEmpty);
      expect(s.cronRunsWhileAppOpen, isNotEmpty);
      expect(s.cronNever, isNotEmpty);
      expect(s.cronNextRunLabel, isNotEmpty);
      expect(s.cronLastRunLabel, isNotEmpty);
      expect(s.cronDeleteTitle, isNotEmpty);
      expect(s.cronDeleteBody('X'), contains('X'));
      expect(s.cronRunNowTooltip, isNotEmpty);
      expect(s.cronNameRequired, isNotEmpty);
      expect(s.cronExpressionInvalid, isNotEmpty);
      expect(s.cronTelegramFieldsRequired, isNotEmpty);
      expect(s.cronMessageRequired, isNotEmpty);
      expect(s.cronNotifTextRequired, isNotEmpty);
      expect(s.cronAgentPromptRequired, isNotEmpty);
      expect(s.cronSaved, isNotEmpty);
      expect(s.cronHistoryTitle, isNotEmpty);
      expect(s.cronHistoryEmpty, isNotEmpty);
      expect(s.cronDisabledBadge, isNotEmpty);
      expect(s.cronPausedBadge, isNotEmpty);
    }
    // Spot-check the translations differ per locale.
    expect(en.cronTileTitle, 'Cron jobs');
    expect(id.cronJobsEmptyTitle, 'Belum ada job');
    expect(id.cronActionAgent, 'Tugas agent');
    expect(es.cronActionAgent, 'Tarea de agente');
    expect(es.cronJobsEmptyTitle, 'Aún no hay trabajos');
  });

  test('local AI strings are localized in all three bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    final AppStrings es = appStringsFor('es');
    // Every local AI string must be present in every bundle (v1.51.0).
    for (final AppStrings s in <AppStrings>[en, id, es]) {
      expect(s.ollamaTileSubtitle, isNotEmpty);
      expect(s.ollamaRuntimeUnavailable, isNotEmpty);
      expect(s.ollamaModelEmptyHint, isNotEmpty);
      expect(s.ollamaConfigInvalid, isNotEmpty);
      expect(s.ollamaOomWarning, isNotEmpty);
      expect(s.ollamaStatusRunning, isNotEmpty);
      expect(s.ollamaUseInChatBody('x'), contains('x'));
      expect(s.ollamaRiskBody('x'), contains('x'));
      expect(s.ollamaImportDone('x'), contains('x'));
      expect(s.ollamaDeleteBody('x'), contains('x'));
      expect(s.ollamaDownloadStarted('x'), contains('x'));
      // v1.53.0 — disk-guard message takes raw bytes, formats MiB inline.
      expect(
        s.ollamaDiskFull('qwen3:0.6b', 5 * 1024 * 1024, 1024 * 1024),
        allOf(contains('qwen3:0.6b'), contains('5 MB'), contains('1 MB')),
      );
    }
    // Representative wording per locale.
    expect(en.ollamaTileTitle, 'Ollama Manage');
    expect(en.ollamaTabDownloads, 'Downloads');
    expect(en.ollamaSizeProgress(300, 523), '300 of 523 MB');
    expect(id.ollamaTileTitle, 'Kelola Ollama');
    expect(id.ollamaTabCatalog, 'Katalog');
    expect(id.ollamaTabInstalled, 'Terpasang');
    expect(id.ollamaTabDownloads, 'Unduhan');
    expect(id.ollamaStatusFailed, 'Gagal');
    expect(id.ollamaSizeProgress(300, 523), '300 dari 523 MB');
    expect(es.ollamaTabServer, 'Servidor');
    expect(es.ollamaTabCatalog, 'Catálogo');
    expect(es.ollamaTabDownloads, 'Descargas');
    expect(es.ollamaProbeOk('0.6'), contains('0.6'));
    expect(es.ollamaSizeProgress(300, 523), '300 de 523 MB');
    // v1.53.0 — representative disk-guard wording per locale.
    expect(
      en.ollamaDiskFull('m1', 5 * 1024 * 1024, 1024 * 1024),
      'Not enough free space for “m1”: needs 5 MB, only 1 MB free.',
    );
    expect(
      id.ollamaDiskFull('m1', 5 * 1024 * 1024, 1024 * 1024),
      'Ruang kosong tidak cukup untuk “m1”: butuh 5 MB, tersisa 1 MB.',
    );
    expect(
      es.ollamaDiskFull('m1', 5 * 1024 * 1024, 1024 * 1024),
      'Espacio libre insuficiente para «m1»: se necesitan 5 MB, '
      'solo hay 1 MB.',
    );
  });

  test('fase 2 local AI strings are localized in all three bundles', () {
    final AppStrings en = appStringsFor('en');
    final AppStrings id = appStringsFor('id');
    final AppStrings es = appStringsFor('es');
    // v1.52.0 — every Fase 2 string present in every bundle.
    for (final AppStrings s in <AppStrings>[en, id, es]) {
      expect(s.ollamaBenchmark, isNotEmpty);
      expect(s.ollamaBenchmarkRunning, isNotEmpty);
      expect(s.ollamaBenchmarkFailed('boom'), contains('boom'));
      expect(
        s.ollamaBenchmarkSummary('12.3', 210, 20),
        allOf(contains('12.3'), contains('210'), contains('20')),
      );
      expect(s.ollamaViewFullLog, isNotEmpty);
      expect(s.ollamaCopyAll, isNotEmpty);
      expect(s.ollamaClose, isNotEmpty);
      expect(s.ollamaBattery(73), contains('73'));
      expect(s.ollamaBatteryCharging(73), contains('73'));
      expect(s.ollamaBatteryLow(12), contains('12'));
      expect(s.ollamaDeviceRam('3.6 GB'), contains('3.6 GB'));
      expect(s.ollamaTooLarge, isNotEmpty);
      expect(s.ollamaFitFilter, isNotEmpty);
      expect(s.ollamaCatalogRefresh, isNotEmpty);
      expect(s.ollamaCatalogReset, isNotEmpty);
      expect(s.ollamaCatalogRefreshDone(7), contains('7'));
      expect(s.ollamaCatalogRefreshFailed('offline'), contains('offline'));
      expect(s.ollamaCatalogResetDone, isNotEmpty);
      expect(s.cronLocalAiHint('qwen3:0.6b'), contains('qwen3:0.6b'));
      expect(s.cronLocalAiNoModel, isNotEmpty);
      expect(s.cronOpenOllamaManage, isNotEmpty);
      expect(s.ollamaSelectMode, isNotEmpty);
      expect(s.ollamaSelectedCount(2), contains('2'));
      expect(s.ollamaExportSelected, isNotEmpty);
      expect(s.ollamaExportSelectedDone(2), contains('2'));
      expect(s.ollamaExportNone, isNotEmpty);
    }
    // Representative wording per locale.
    expect(
      en.ollamaBenchmarkSummary('12.3', 210, 20),
      '12.3 tok/s · first token 210ms · 20 tokens',
    );
    expect(en.ollamaBatteryCharging(73), 'Battery 73% · charging');
    expect(en.ollamaBatteryLow(12), 'Battery 12% — low');
    expect(en.ollamaDeviceRam('8.0 GB'), 'Device RAM 8.0 GB');
    expect(id.ollamaBatteryCharging(73), 'Baterai 73% · mengisi');
    expect(id.ollamaBatteryLow(12), 'Baterai 12% — lemah');
    expect(id.ollamaDeviceRam('8.0 GB'), 'RAM perangkat 8.0 GB');
    expect(id.ollamaSelectedCount(2), '2 dipilih');
    expect(es.ollamaBatteryCharging(73), 'Batería 73% · cargando');
    expect(es.ollamaBatteryLow(12), 'Batería 12% — baja');
    expect(es.ollamaDeviceRam('8.0 GB'), 'RAM del dispositivo 8.0 GB');
    expect(es.cronOpenOllamaManage, 'Abrir Gestionar Ollama');
    expect(es.ollamaExportSelectedDone(2), '2 modelos exportados.');
  });

  // -- Assistant polish (v1.54.0) -------------------------------------------
  group('v1.54.0 assistant polish strings', () {
    test('errorOpenProviders is localized in all three bundles', () {
      final AppStrings en = appStringsFor('en');
      final AppStrings id = appStringsFor('id');
      final AppStrings es = appStringsFor('es');
      for (final AppStrings s in <AppStrings>[en, id, es]) {
        expect(s.errorOpenProviders, isNotEmpty);
      }
      expect(en.errorOpenProviders, 'Open Providers');
      expect(id.errorOpenProviders, 'Buka Providers');
      expect(es.errorOpenProviders, 'Abrir Proveedores');
    });

    test('Spanish is wired: native picker name + resolution + codes', () {
      // The picker label is the native name, identical in every locale
      // (same convention as 'Bahasa Indonesia').
      for (final AppStrings s in <AppStrings>[
        appStringsFor('en'),
        appStringsFor('id'),
        appStringsFor('es'),
      ]) {
        expect(s.spanishOption, 'Español');
      }
      expect(appStringsFor('es'), isA<AppStringsEs>());
      expect(appStringsFor('ES'), isA<AppStringsEs>()); // case-insensitive
      expect(supportedLanguageCodes, containsAll(<String>['en', 'id', 'es']));
    });
  });

  // -- Live browser (v1.54.0) -------------------------------------------------
  group('live browser strings are localized in all three bundles', () {
    test('every live browser getter is present in en/id/es', () {
      final AppStrings en = appStringsFor('en');
      final AppStrings id = appStringsFor('id');
      final AppStrings es = appStringsFor('es');
      for (final AppStrings s in <AppStrings>[en, id, es]) {
        expect(s.liveBrowserTitle, isNotEmpty);
        expect(s.liveBrowserModeUser, isNotEmpty);
        expect(s.liveBrowserModeAgent, isNotEmpty);
        expect(s.liveBrowserPromptHint, isNotEmpty);
        expect(s.liveBrowserUserHint, isNotEmpty);
        expect(s.liveBrowserSent, isNotEmpty);
        expect(s.liveBrowserAttachFailed, isNotEmpty);
        expect(s.liveBrowserRetry, isNotEmpty);
        expect(s.liveBrowserRefusalBusy, isNotEmpty);
        expect(s.liveBrowserRefusalNoKey, isNotEmpty);
        expect(s.liveBrowserRefusalNoModel, isNotEmpty);
        expect(s.liveBrowserRefusalSetup, isNotEmpty);
        expect(s.liveBrowserRefusalNotFound, isNotEmpty);
        expect(s.liveBrowserRefusalGeneric, isNotEmpty);
      }
    });

    test('exact wording spot checks per locale', () {
      final AppStrings en = appStringsFor('en');
      final AppStrings id = appStringsFor('id');
      final AppStrings es = appStringsFor('es');
      expect(en.liveBrowserTitle, 'Live Browser');
      expect(en.liveBrowserModeUser, 'You');
      expect(en.liveBrowserModeAgent, 'AI');
      expect(
        en.liveBrowserUserHint,
        'You hold the controls — browse freely. Switch to AI to let the '
        'agent drive this page.',
      );
      expect(id.liveBrowserTitle, 'Browser Langsung');
      expect(id.liveBrowserModeUser, 'Anda');
      expect(id.liveBrowserRetry, 'Coba lagi');
      expect(
        es.liveBrowserUserHint,
        startsWith('Tú'),
      );
      expect(es.liveBrowserTitle, 'Navegador en vivo');
      expect(es.liveBrowserModeAgent, 'IA');
    });
  });
}
