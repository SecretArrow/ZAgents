import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/local_ai/model_catalog_data.dart';

void main() {
  group('kLocalAiCatalog (frozen v1.51.0 proposal)', () {
    test('has exactly 14 entries with unique refs', () {
      expect(kLocalAiCatalog, hasLength(14));
      final Set<String> refs = <String>{};
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        expect(refs.add(entry.ollamaRef), isTrue,
            reason: 'duplicate ref ${entry.ollamaRef}');
      }
    });

    test('id is the ollama ref', () {
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        expect(entry.id, entry.ollamaRef);
      }
    });

    test('every entry carries positive sizes and context windows', () {
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        expect(entry.downloadBytes, greaterThan(0), reason: entry.ollamaRef);
        expect(entry.ramEstBytes, greaterThan(0), reason: entry.ollamaRef);
        expect(entry.contextTokens, greaterThan(0), reason: entry.ollamaRef);
      }
    });

    test('tier split is 6 / 6 / 2', () {
      final Map<CatalogTier, int> counts = <CatalogTier, int>{
        for (final CatalogTier tier in CatalogTier.values) tier: 0,
      };
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        counts[entry.tier] = counts[entry.tier]! + 1;
      }
      expect(counts[CatalogTier.tier1], 6);
      expect(counts[CatalogTier.tier2], 6);
      expect(counts[CatalogTier.upperBound], 2);
    });

    test('spot-checks against the approved proposal values (MB = 1024²)',
        () {
      const int mb = 1024 * 1024;
      final Map<String, CatalogModelEntry> byRef = <String, CatalogModelEntry>{
        for (final CatalogModelEntry entry in kLocalAiCatalog)
          entry.ollamaRef: entry,
      };

      final CatalogModelEntry qwen = byRef['qwen3:0.6b']!;
      expect(qwen.downloadBytes, 523 * mb);
      expect(qwen.contextTokens, 40960);
      expect(qwen.ramEstBytes, 1024 * 1024 * 1024);
      expect(qwen.tier, CatalogTier.tier1);
      expect(qwen.license, 'Apache-2.0');

      final CatalogModelEntry gemma = byRef['gemma3:1b']!;
      expect(gemma.downloadBytes, 806 * mb);
      expect(gemma.ramEstBytes, (12 * 1024 * 1024 * 1024) ~/ 10);
      expect(gemma.license, 'Gemma');

      final CatalogModelEntry coder = byRef['qwen2.5-coder:1.5b']!;
      expect(coder.tier, CatalogTier.tier2);
      expect(coder.contextTokens, 32768);
      expect(coder.license, 'Apache-2.0');

      final CatalogModelEntry deepseek = byRef['deepseek-r1:1.5b']!;
      expect(deepseek.license, 'MIT');
      expect(deepseek.contextTokens, 131072);

      final CatalogModelEntry llama = byRef['llama3.2:1b']!;
      expect(llama.license, 'Llama-Community');

      final CatalogModelEntry minicpm = byRef['minicpm5-2b']!;
      expect(minicpm.tier, CatalogTier.upperBound);
      expect(minicpm.downloadBytes, 1718 * mb);
      expect(minicpm.contextTokens, 131072);

      final CatalogModelEntry bonsai4 = byRef['bonsai-2:4b']!;
      expect(bonsai4.tier, CatalogTier.upperBound);
      expect(bonsai4.contextTokens, 262144);
      expect(bonsai4.ramEstBytes, (26 * 1024 * 1024 * 1024) ~/ 10);
    });

    test('every tier-1 download fits the smallest approved budget', () {
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        if (entry.tier != CatalogTier.tier1) continue;
        expect(entry.downloadBytes, lessThan(1024 * 1024 * 1024),
            reason: entry.ollamaRef);
      }
    });
  });
}
