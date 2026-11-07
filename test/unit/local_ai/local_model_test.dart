import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/models/local_model.dart';

LocalModelEntry _entry() => const LocalModelEntry(
  id: 'm-1',
  name: 'Qwen3 0.6B',
  source: LocalModelSource.catalog,
  ollamaRef: 'qwen3:0.6b',
  fileName: 'm-1.gguf',
  sizeBytes: 548407808,
  sha256: 'aa11',
  addedAtMs: 42,
  lastUsedAtMs: 99,
);

void main() {
  group('localModelSourceFromName', () {
    test('maps every wire name', () {
      expect(localModelSourceFromName('catalog'), LocalModelSource.catalog);
      expect(localModelSourceFromName('customUrl'), LocalModelSource.customUrl);
      expect(localModelSourceFromName('imported'), LocalModelSource.imported);
    });

    test('unknown and null spellings fall back to imported', () {
      expect(localModelSourceFromName('bogus'), LocalModelSource.imported);
      expect(localModelSourceFromName(null), LocalModelSource.imported);
      expect(localModelSourceFromName(''), LocalModelSource.imported);
    });
  });

  group('LocalModelEntry json roundtrip', () {
    test('survives toJson → fromJson with every field', () {
      final LocalModelEntry restored = LocalModelEntry.fromJson(
        _entry().toJson(),
      );
      expect(restored.id, 'm-1');
      expect(restored.name, 'Qwen3 0.6B');
      expect(restored.source, LocalModelSource.catalog);
      expect(restored.ollamaRef, 'qwen3:0.6b');
      expect(restored.customUrl, '');
      expect(restored.fileName, 'm-1.gguf');
      expect(restored.sizeBytes, 548407808);
      expect(restored.sha256, 'aa11');
      expect(restored.addedAtMs, 42);
      expect(restored.lastUsedAtMs, 99);
    });

    test('tolerant fromJson: missing keys degrade to defaults', () {
      final LocalModelEntry restored = LocalModelEntry.fromJson(
        <String, dynamic>{'id': 'x'},
      );
      expect(restored.id, 'x');
      expect(restored.name, '');
      expect(restored.source, LocalModelSource.imported);
      expect(restored.ollamaRef, '');
      expect(restored.customUrl, '');
      expect(restored.fileName, '');
      expect(restored.sizeBytes, 0);
      expect(restored.sha256, '');
      expect(restored.addedAtMs, 0);
      expect(restored.lastUsedAtMs, isNull);
    });

    test('an unknown source wire name degrades to imported', () {
      final Map<String, dynamic> json = _entry().toJson()
        ..['source'] = 'from-the-future';
      expect(
        LocalModelEntry.fromJson(json).source,
        LocalModelSource.imported,
      );
    });
  });

  group('LocalModelEntry copyWith', () {
    test('replaces given fields and keeps the rest', () {
      final LocalModelEntry updated = _entry().copyWith(
        name: 'Renamed',
        sizeBytes: 1,
        lastUsedAtMs: 7,
      );
      expect(updated.name, 'Renamed');
      expect(updated.sizeBytes, 1);
      expect(updated.lastUsedAtMs, 7);
      expect(updated.id, 'm-1');
      expect(updated.ollamaRef, 'qwen3:0.6b');
      expect(updated.sha256, 'aa11');
    });

    test('an explicit null clears lastUsedAtMs (CronJob sentinel style)', () {
      final LocalModelEntry cleared = _entry().copyWith(lastUsedAtMs: null);
      expect(cleared.lastUsedAtMs, isNull);
    });
  });

  group('LocalModelState', () {
    test('defaults match the frozen contract', () {
      const LocalModelState state = LocalModelState();
      expect(state.installed, isEmpty);
      expect(state.serverPort, 11434);
      expect(state.contextSize, 2048);
      expect(state.threads, 0);
      expect(state.autoStartOnBoot, isFalse);
    });

    test('survives toJson → fromJson with entries and config', () {
      final LocalModelState state = LocalModelState(
        installed: <LocalModelEntry>[_entry()],
        serverPort: 8080,
        contextSize: 8192,
        threads: 4,
        autoStartOnBoot: true,
      );
      final LocalModelState restored = LocalModelState.fromJson(
        state.toJson(),
      );
      expect(restored.installed.single.id, 'm-1');
      expect(restored.serverPort, 8080);
      expect(restored.contextSize, 8192);
      expect(restored.threads, 4);
      expect(restored.autoStartOnBoot, isTrue);
    });

    test('tolerant fromJson: non-map entries are skipped, missing config '
        'falls back', () {
      final LocalModelState restored = LocalModelState.fromJson(
        <String, dynamic>{
          'installed': <dynamic>[
            _entry().toJson(),
            'not-a-map',
            <String, dynamic>{},
          ],
        },
      );
      expect(restored.installed, hasLength(2));
      expect(restored.installed.first.id, 'm-1');
      expect(restored.installed.last.id, '');
      expect(restored.serverPort, 11434);
      expect(restored.contextSize, 2048);
    });

    test('copyWith patches only the given fields', () {
      const LocalModelState state = LocalModelState();
      final LocalModelState next = state.copyWith(threads: 6);
      expect(next.serverPort, 11434);
      expect(next.threads, 6);
      expect(next.contextSize, 2048);
      expect(next.autoStartOnBoot, isFalse);
    });
  });
}
