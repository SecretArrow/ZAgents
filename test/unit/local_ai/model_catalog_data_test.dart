import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/local_ai/model_catalog_data.dart';

CatalogModelEntry _e(
  String ref, {
  int ram = 1024,
  int download = 2048,
  CatalogTier tier = CatalogTier.tier2,
}) => CatalogModelEntry(
  ollamaRef: ref,
  downloadBytes: download,
  ramEstBytes: ram,
  contextTokens: 4096,
  tier: tier,
);

void main() {
  group('kLocalAiCatalog (v1.53.0 live-registry catalog)', () {
    test('has exactly 30 entries with unique refs', () {
      expect(kLocalAiCatalog, hasLength(30));
      final Set<String> refs = <String>{};
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        expect(
          refs.add(entry.ollamaRef),
          isTrue,
          reason: 'duplicate ref ${entry.ollamaRef}',
        );
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

    test('tier split is 16 / 9 / 5', () {
      final Map<CatalogTier, int> counts = <CatalogTier, int>{
        for (final CatalogTier tier in CatalogTier.values) tier: 0,
      };
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        counts[entry.tier] = counts[entry.tier]! + 1;
      }
      expect(counts[CatalogTier.tier1], 16);
      expect(counts[CatalogTier.tier2], 9);
      expect(counts[CatalogTier.upperBound], 5);
    });

    test('spot-checks against exact live registry manifest sums '
        '(Σ layers, verified 2026-11-07)', () {
      // Every downloadBytes below is the exact byte sum of the registry
      // manifest layers (Σ layers) — no MiB rounding.
      final Map<String, CatalogModelEntry> byRef = <String, CatalogModelEntry>{
        for (final CatalogModelEntry entry in kLocalAiCatalog)
          entry.ollamaRef: entry,
      };

      final CatalogModelEntry qwen = byRef['qwen3:0.6b']!;
      expect(qwen.downloadBytes, 522653277);
      expect(qwen.contextTokens, 40960);
      expect(qwen.ramEstBytes, 1024 * 1024 * 1024);
      expect(qwen.tier, CatalogTier.tier1);
      expect(qwen.license, 'Apache-2.0');

      final CatalogModelEntry gemma = byRef['gemma3:1b']!;
      expect(gemma.downloadBytes, 806067267);
      expect(gemma.ramEstBytes, (12 * 1024 * 1024 * 1024) ~/ 10);
      expect(gemma.license, 'Gemma');

      final CatalogModelEntry coder = byRef['qwen2.5-coder:1.5b']!;
      expect(coder.downloadBytes, 986061602);
      expect(coder.tier, CatalogTier.tier2);
      expect(coder.contextTokens, 32768);
      expect(coder.license, 'Apache-2.0');

      final CatalogModelEntry deepseek = byRef['deepseek-r1:1.5b']!;
      expect(deepseek.downloadBytes, 1117322281);
      expect(deepseek.license, 'MIT');
      expect(deepseek.contextTokens, 131072);

      final CatalogModelEntry llama = byRef['llama3.2:1b']!;
      expect(llama.downloadBytes, 1321097844);
      expect(llama.license, 'Llama-Community');

      final CatalogModelEntry minicpm = byRef['openbmb/minicpm5:latest']!;
      expect(minicpm.tier, CatalogTier.tier1);
      expect(minicpm.downloadBytes, 688066182);
      expect(minicpm.contextTokens, 131072);
      expect(minicpm.license, 'Apache-2.0');

      final CatalogModelEntry bonsai4 = byRef['bonsai-2:4b']!;
      expect(bonsai4.tier, CatalogTier.upperBound);
      expect(bonsai4.downloadBytes, 1579008347);
      expect(bonsai4.contextTokens, 262144);
      expect(bonsai4.ramEstBytes, (26 * 1024 * 1024 * 1024) ~/ 10);
    });

    test('directUrl rows are registry-bypassed HF picks', () {
      final Map<String, CatalogModelEntry> byRef = <String, CatalogModelEntry>{
        for (final CatalogModelEntry entry in kLocalAiCatalog)
          entry.ollamaRef: entry,
      };
      const List<String> hfRefs = <String>[
        'hf.co/taobao-mnn/MNN-Pocket-0.3B-GGUF:Q4_1',
        'hf.co/zyr-AGENT/ZY-S2:Q5_K_M',
      ];
      for (final String ref in hfRefs) {
        final CatalogModelEntry entry = byRef[ref]!;
        expect(
          entry.directUrl,
          startsWith('https://huggingface.co/'),
          reason: ref,
        );
        expect(entry.directUrl, endsWith('.gguf'), reason: ref);
      }
      // Every OTHER entry keeps the default (registry-resolved) URL.
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        if (hfRefs.contains(entry.ollamaRef)) continue;
        expect(entry.directUrl, isEmpty, reason: entry.ollamaRef);
      }
    });

    test('every tier-1 download fits the smallest approved budget', () {
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        if (entry.tier != CatalogTier.tier1) continue;
        expect(
          entry.downloadBytes,
          lessThan(1024 * 1024 * 1024),
          reason: entry.ollamaRef,
        );
      }
    });
  });

  group('catalogModelFits (v1.52.0 RAM heuristic)', () {
    const int gb = 1024 * 1024 * 1024;

    test('unknown device RAM (0 or negative) → everything fits', () {
      expect(catalogModelFits(10 * gb, 0), isTrue);
      expect(catalogModelFits(10 * gb, -1), isTrue);
      // Sanity on a real 4 GB device: a 2.6 GB footprint (bonsai-2:4b
      // territory) is over 55% → filtered.
      expect(catalogModelFits((26 * gb) ~/ 10, 4 * gb), isFalse);
    });

    test('55% is the exact boundary (inclusive)', () {
      const int total = 2 * gb;
      const int limit = total * 55 ~/ 100; // 1181116006
      expect(
        catalogModelFits(limit, total),
        isTrue,
        reason: 'exactly 55% fits',
      );
      expect(
        catalogModelFits(limit + 1, total),
        isFalse,
        reason: 'one byte over 55% does not',
      );
      expect(catalogModelFits(limit - 1, total), isTrue);
    });

    test('unknown estimate (0 or negative) is never filtered', () {
      expect(catalogModelFits(0, 2 * gb), isTrue);
      expect(catalogModelFits(-5, 2 * gb), isTrue);
    });

    test('spot checks against the real catalog on a 4 GB device', () {
      // 4 GiB → 55%-of-total limit = 2362232012 B (inclusive boundary).
      // Every real entry fits EXCEPT the five upper-bound rows whose RAM
      // estimate exceeds that limit: bonsai-2:4b (2.6 GiB), qwen3.5:2b
      // (2.9 GiB), phi4-mini:3.8b (2.4 GiB), granite4.2:3b (2.6 GiB) and
      // gemma4:e2b (3.5 GiB). Everything else stays under 55%.
      const Set<String> tooBigFor4GiB = <String>{
        'bonsai-2:4b',
        'qwen3.5:2b',
        'phi4-mini:3.8b',
        'granite4.2:3b',
        'gemma4:e2b',
      };
      for (final CatalogModelEntry entry in kLocalAiCatalog) {
        final bool fits = catalogModelFits(entry.ramEstBytes, 4 * gb);
        expect(
          fits,
          !tooBigFor4GiB.contains(entry.ollamaRef),
          reason: entry.ollamaRef,
        );
      }
    });
  });

  group('mergeCatalog (v1.52.0)', () {
    test('empty remote returns the base untouched (a copy)', () {
      final List<CatalogModelEntry> merged = mergeCatalog(
        kLocalAiCatalog,
        const <CatalogModelEntry>[],
      );
      expect(merged, hasLength(kLocalAiCatalog.length));
      expect(merged.first.ollamaRef, kLocalAiCatalog.first.ollamaRef);
      // A copy, not the same list instance: mutating it must not leak into
      // the const built-ins.
      expect(identical(merged, kLocalAiCatalog), isFalse);
    });

    test('remote replaces by ref and appends new refs in order', () {
      final CatalogModelEntry base = _e(
        'a:1b',
        ram: 100,
        tier: CatalogTier.tier1,
      );
      final CatalogModelEntry other = _e('b:2b', ram: 200);
      final CatalogModelEntry replaced = _e(
        'a:1b',
        ram: 999,
        tier: CatalogTier.upperBound,
      );
      final CatalogModelEntry appended = _e(
        'c:3b',
        ram: 300,
        tier: CatalogTier.tier1,
      );

      final List<CatalogModelEntry> merged = mergeCatalog(
        <CatalogModelEntry>[base, other],
        <CatalogModelEntry>[replaced, appended],
      );

      expect(merged, hasLength(3));
      expect(merged[0].ollamaRef, 'a:1b');
      expect(merged[0].ramEstBytes, 999, reason: 'remote wins by ref');
      expect(merged[0].tier, CatalogTier.upperBound);
      expect(merged[1].ollamaRef, 'b:2b');
      expect(merged[1].ramEstBytes, 200, reason: 'untouched base row');
      expect(merged[2].ollamaRef, 'c:3b', reason: 'new ref appended last');
    });

    test('duplicate refs inside remote: the last one wins', () {
      final CatalogModelEntry first = _e('a:1b', ram: 10);
      final CatalogModelEntry second = _e('a:1b', ram: 20);
      final List<CatalogModelEntry> merged = mergeCatalog(
        <CatalogModelEntry>[_e('a:1b', ram: 1)],
        <CatalogModelEntry>[first, second],
      );
      expect(merged, hasLength(1));
      expect(merged.single.ramEstBytes, 20);
    });
  });
}
