import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/l10n/app_strings.dart';
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

    test('plan-first strings are localized in both bundles', () {
      final AppStrings en = appStringsFor('en');
      final AppStrings id = appStringsFor('id');
      expect(en.planFirstTitle, contains('Plan first'));
      expect(en.planTitle, 'Plan');
      expect(en.planProgress(2, 5), '2/5 done');
      expect(id.planFirstTitle, contains('rencana'));
      expect(id.planTitle, 'Rencana');
      expect(id.planProgress(2, 5), '2/5 selesai');
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
    expect(en.aboutBody, contains('v1.14.0'));
    expect(id.aboutBody, contains('v1.14.0'));
  });
}
