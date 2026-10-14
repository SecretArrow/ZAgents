import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/models/models.dart';

void main() {
  group('ProviderPreset', () {
    test('json roundtrip preserves every field', () {
      const ProviderPreset preset = ProviderPreset(
        id: 'p1',
        name: 'InferHub',
        baseUrl: 'https://api.inferhub.dev/v1',
        apiKey: 'sk-airo-test',
        model: 'glm-4.6',
        modelsCache: <String>['glm-4.6', 'glm-4.5-air'],
      );
      final ProviderPreset decoded = ProviderPreset.fromJson(preset.toJson());
      expect(decoded.id, 'p1');
      expect(decoded.name, 'InferHub');
      expect(decoded.baseUrl, 'https://api.inferhub.dev/v1');
      expect(decoded.apiKey, 'sk-airo-test');
      expect(decoded.model, 'glm-4.6');
      expect(decoded.hasKey, isTrue);
      expect(decoded.hasModelsCache, isTrue);
      expect(decoded.modelsCache, <String>['glm-4.6', 'glm-4.5-air']);
    });

    test('hasKey is false for blank keys', () {
      const ProviderPreset preset = ProviderPreset(id: 'p', name: 'X');
      expect(preset.hasKey, isFalse);
    });

    test('modelsCache defaults to empty and tolerates missing json field', () {
      const ProviderPreset preset = ProviderPreset(id: 'p', name: 'X');
      expect(preset.modelsCache, isEmpty);
      expect(preset.hasModelsCache, isFalse);
      final ProviderPreset decoded = ProviderPreset.fromJson(<String, dynamic>{
        'id': 'p',
        'name': 'X',
      });
      expect(decoded.modelsCache, isEmpty);
    });

    test('copyWith modelsCache replaces the cached list', () {
      const ProviderPreset preset = ProviderPreset(id: 'p', name: 'X');
      final ProviderPreset cached = preset.copyWith(
        modelsCache: <String>['a/b'],
      );
      expect(cached.modelsCache, <String>['a/b']);
      expect(preset.modelsCache, isEmpty);
    });
  });

  group('presetHostLabel', () {
    test('reduces a base URL to its host', () {
      expect(
        presetHostLabel('https://api.inferhub.dev/v1'),
        'api.inferhub.dev',
      );
      expect(presetHostLabel('https://openrouter.ai/api/v1'), 'openrouter.ai');
    });

    test('falls back to the raw value when parsing fails', () {
      expect(presetHostLabel('not a url'), 'not a url');
      expect(presetHostLabel(''), '');
    });
  });

  group('AppSettings preset migration', () {
    test('fresh settings seed all built-in presets without keys', () {
      final AppSettings settings = AppSettings();
      expect(
        settings.presets.map((p) => p.name),
        containsAll(<String>['OpenRouter', 'InferHub', 'Z.AI', 'Custom']),
      );
      expect(settings.presets.every((p) => !p.hasKey), isTrue);
    });

    test('legacy storage (no presets) migrates the active key into the '
        'matching preset', () {
      final AppSettings migrated = AppSettings.fromJson(<String, dynamic>{
        'providerName': 'InferHub',
        'baseUrl': 'https://api.inferhub.dev/v1',
        'apiKey': 'sk-airo-legacy',
        'model': 'glm-4.6',
      });
      final ProviderPreset inferhub = migrated.presets.singleWhere(
        (p) => p.name == 'InferHub',
      );
      expect(inferhub.apiKey, 'sk-airo-legacy');
      expect(inferhub.model, 'glm-4.6');
      expect(inferhub.baseUrl, 'https://api.inferhub.dev/v1');
      // Other presets stay empty and the active connection is untouched.
      expect(migrated.apiKey, 'sk-airo-legacy');
      expect(
        migrated.presets.singleWhere((p) => p.name == 'OpenRouter').hasKey,
        isFalse,
      );
    });

    test('custom presets survive migration roundtrip', () {
      final AppSettings original = AppSettings(
        providerName: 'Custom',
        baseUrl: 'https://my.host/v1',
        apiKey: 'sk-custom',
        presets: <ProviderPreset>[
          const ProviderPreset(id: 'c1', name: 'Custom', baseUrl: ''),
          const ProviderPreset(
            id: 'c2',
            name: 'Mine',
            baseUrl: 'https://my.host/v1',
            apiKey: 'sk-custom',
          ),
        ],
      );
      final AppSettings decoded = AppSettings.fromJson(original.toJson());
      expect(decoded.presets.any((p) => p.name == 'Mine'), isTrue);
      expect(
        decoded.presets.singleWhere((p) => p.name == 'Mine').apiKey,
        'sk-custom',
      );
    });
  });

  group('theme mode setting', () {
    test('defaults to dark and parses valid names', () {
      expect(themeModeSettingFromName(null), ThemeModeSetting.dark);
      expect(themeModeSettingFromName('light'), ThemeModeSetting.light);
      expect(themeModeSettingFromName('system'), ThemeModeSetting.system);
      expect(themeModeSettingFromName('bogus'), ThemeModeSetting.dark);
    });
  });

  group('maxSteps bounds', () {
    test('clamps slider/input values into 1..100', () {
      expect(clampMaxSteps(0), 1);
      expect(clampMaxSteps(-5), 1);
      expect(clampMaxSteps(1), 1);
      expect(clampMaxSteps(42), 42);
      expect(clampMaxSteps(100), 100);
      expect(clampMaxSteps(1000), 100);
      expect(clampMaxSteps('77'), 77);
      expect(clampMaxSteps('abc'), 1);
    });

    test('copyWith clamps out-of-range values', () {
      final AppSettings settings = AppSettings().copyWith(maxSteps: 5000);
      expect(settings.maxSteps, 100);
    });

    test('json storage clamps corrupted values', () {
      final AppSettings settings = AppSettings.fromJson(<String, dynamic>{
        'maxSteps': 99999,
      });
      expect(settings.maxSteps, 100);
    });
  });

  group('run until done', () {
    test('defaults to true so the agent works until tasks finish', () {
      expect(AppSettings().runUntilDone, isTrue);
    });

    test('json roundtrip preserves the flag', () {
      final AppSettings off = AppSettings(runUntilDone: false);
      final AppSettings decoded = AppSettings.fromJson(off.toJson());
      expect(decoded.runUntilDone, isFalse);
      expect(decoded.maxSteps, off.maxSteps);
    });

    test('legacy storage without the flag falls back to true (backward '
        'compatible)', () {
      final AppSettings decoded = AppSettings.fromJson(<String, dynamic>{
        'apiKey': 'k',
        'maxSteps': 6,
      });
      expect(decoded.runUntilDone, isTrue);
    });

    test('copyWith toggles the flag without touching maxSteps', () {
      final AppSettings settings = AppSettings(maxSteps: 42);
      final AppSettings off = settings.copyWith(runUntilDone: false);
      expect(off.runUntilDone, isFalse);
      expect(off.maxSteps, 42);
      final AppSettings backOn = off.copyWith(runUntilDone: true);
      expect(backOn.runUntilDone, isTrue);
    });

    test('unboundedStepLimit stays far beyond any real task', () {
      expect(unboundedStepLimit, greaterThan(maxMaxSteps));
      expect(unboundedStepLimit, greaterThanOrEqualTo(10000));
    });
  });

  group('attachment kinds', () {
    test('images, text and binaries are classified by extension', () {
      expect(attachmentKindFor('photo.PNG'), AttachmentKind.image);
      expect(attachmentKindFor('scan.jpeg'), AttachmentKind.image);
      expect(attachmentKindFor('notes.md'), AttachmentKind.text);
      expect(attachmentKindFor('data.json'), AttachmentKind.text);
      expect(attachmentKindFor('script.dart'), AttachmentKind.text);
      expect(attachmentKindFor('report.pdf'), AttachmentKind.other);
      expect(attachmentKindFor('archive.zip'), AttachmentKind.other);
      expect(attachmentKindFor('noext'), AttachmentKind.other);
    });
  });

  group('ChatAttachment', () {
    test('json roundtrip', () {
      const ChatAttachment att = ChatAttachment(
        name: 'a.png',
        path: '/tmp/a.png',
        sizeBytes: 12,
        kind: AttachmentKind.image,
      );
      final ChatAttachment decoded = ChatAttachment.fromJson(att.toJson());
      expect(decoded.name, 'a.png');
      expect(decoded.kind, AttachmentKind.image);
      expect(decoded.sizeBytes, 12);
    });

    test('malformed json degrades to safe defaults', () {
      final ChatAttachment att = ChatAttachment.fromJson(<String, dynamic>{});
      expect(att.kind, AttachmentKind.other);
      expect(att.name, 'file');
    });
  });

  group('ContextEntry', () {
    test('json roundtrip', () {
      const ContextEntry entry = ContextEntry(
        id: 'c1',
        name: 'Rules',
        content: 'Be brief',
        enabled: true,
      );
      final ContextEntry decoded = ContextEntry.fromJson(entry.toJson());
      expect(decoded.id, 'c1');
      expect(decoded.enabled, isTrue);
      expect(decoded.content, 'Be brief');
    });
  });

  group('ChatMessage attachments', () {
    test('json roundtrip keeps attachments', () {
      final ChatMessage message = ChatMessage.user(
        'hello',
        attachments: <ChatAttachment>[
          const ChatAttachment(
            name: 'x.txt',
            path: '/x',
            sizeBytes: 3,
            kind: AttachmentKind.text,
          ),
        ],
      );
      final ChatMessage decoded = ChatMessage.fromJson(message.toJson());
      expect(decoded.attachments, hasLength(1));
      expect(decoded.attachments.first.name, 'x.txt');
    });
  });
}
