/// Curated Local AI catalog — v1.53.0.
///
/// The download list offered by the Ollama Manage → Catalog tab: 30
/// llama.cpp-compatible GGUF picks from the Ollama registry, sized for
/// on-device use (16 tier1 / 9 tier2 / 5 upperBound). Every entry carries
/// the registry ref the downloader resolves, the expected download size
/// (a live registry manifest sum, Σ layers, MB = 1024²), a RAM estimate
/// for the running KV cache, the context window the model is known to
/// support and the license label shown in the UI. Two `hf.co/…` rows
/// additionally carry a [CatalogModelEntry.directUrl] — a direct https
/// .gguf link the download queue fetches because the registry cannot
/// serve those files.
///
/// Tiers drive the UI treatment:
/// * [CatalogTier.tier1] — safe on every supported device.
/// * [CatalogTier.tier2] — heavier; fine on 6 GB+ RAM devices.
/// * [CatalogTier.upperBound] — risky; the UI shows an OOM warning and
///   asks for confirmation before downloading.
library;

/// Risk tier of a catalog entry (drives warnings in the UI).
enum CatalogTier { tier1, tier2, upperBound }

/// One catalog row (a curated Ollama registry model).
class CatalogModelEntry {
  const CatalogModelEntry({
    required this.ollamaRef,
    required this.downloadBytes,
    required this.ramEstBytes,
    required this.contextTokens,
    required this.tier,
    this.license = '',
    this.directUrl = '',
  });

  /// Ollama registry reference, e.g. `qwen3:0.6b` — the same string the
  /// downloader passes to the registry client.
  final String ollamaRef;

  /// Expected blob download size in bytes (MB = 1024² in the source
  /// proposal).
  final int downloadBytes;

  /// Rough RAM footprint of the running model + KV cache.
  final int ramEstBytes;

  /// Context window (tokens) the model is known to support.
  final int contextTokens;

  final CatalogTier tier;

  /// License label shown in the UI ('' = not yet vetted).
  final String license;

  /// Direct https .gguf URL for models the Ollama registry cannot serve
  /// (Hugging Face-hosted files). Empty = resolve [ollamaRef] through the
  /// registry as usual; non-empty = the download queue fetches this URL
  /// directly (the screen passes it through as the custom-URL source).
  final String directUrl;

  /// Stable row id (the ref itself).
  String get id => ollamaRef;
}

const int _gb = 1024 * 1024 * 1024;

/// The 30 curated Local AI models (v1.53.0). Download sizes are live
/// Ollama registry manifest sums (Σ layers) — exact bytes, not rounded.
/// `assets/local_ai_catalog.json` mirrors these values (same numbers,
/// tier wire names) — the remote-catalog source of truth AND the
/// documentation of the wire shape.
const List<CatalogModelEntry> kLocalAiCatalog = <CatalogModelEntry>[
  // -- tier 1: safe on every supported device (16) -----------------------
  CatalogModelEntry(
    ollamaRef: 'qwen3:0.6b',
    downloadBytes: 522653277,
    ramEstBytes: _gb,
    contextTokens: 40960,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'gemma3:1b',
    downloadBytes: 806067267,
    ramEstBytes: (12 * _gb) ~/ 10,
    contextTokens: 32768,
    tier: CatalogTier.tier1,
    license: 'Gemma',
  ),
  CatalogModelEntry(
    ollamaRef: 'bonsai-2:2b',
    downloadBytes: 911364059,
    ramEstBytes: (13 * _gb) ~/ 10,
    contextTokens: 262144,
    tier: CatalogTier.tier1,
  ),
  CatalogModelEntry(
    ollamaRef: 'gemma3:270m',
    downloadBytes: 291554440,
    ramEstBytes: (7 * _gb) ~/ 10,
    contextTokens: 32768,
    tier: CatalogTier.tier1,
    license: 'Gemma',
  ),
  CatalogModelEntry(
    ollamaRef: 'smollm2:135m',
    downloadBytes: 270898111,
    ramEstBytes: (6 * _gb) ~/ 10,
    contextTokens: 8192,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'smollm2:360m',
    downloadBytes: 725565951,
    ramEstBytes: (11 * _gb) ~/ 10,
    contextTokens: 8192,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'qwen2.5-coder:0.5b',
    downloadBytes: 397821026,
    ramEstBytes: (8 * _gb) ~/ 10,
    contextTokens: 32768,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'smollm:135m',
    downloadBytes: 91738925,
    ramEstBytes: (5 * _gb) ~/ 10,
    contextTokens: 2048,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'smollm:360m',
    downloadBytes: 229130573,
    ramEstBytes: (7 * _gb) ~/ 10,
    contextTokens: 2048,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'tinyllama:1.1b',
    downloadBytes: 637699655,
    ramEstBytes: (9 * _gb) ~/ 10,
    contextTokens: 2048,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'yi-coder:1.5b',
    downloadBytes: 866168498,
    ramEstBytes: (12 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'stablelm2:1.6b',
    downloadBytes: 982789899,
    ramEstBytes: (12 * _gb) ~/ 10,
    contextTokens: 4096,
    tier: CatalogTier.tier1,
    license: 'StabilityAI',
  ),
  CatalogModelEntry(
    ollamaRef: 'reader-lm:0.5b',
    downloadBytes: 352166385,
    ramEstBytes: (8 * _gb) ~/ 10,
    contextTokens: 256000,
    tier: CatalogTier.tier1,
    license: 'CC-BY-NC-4.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'reader-lm:1.5b',
    downloadBytes: 934966449,
    ramEstBytes: (12 * _gb) ~/ 10,
    contextTokens: 256000,
    tier: CatalogTier.tier1,
    license: 'CC-BY-NC-4.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'openbmb/minicpm5:latest',
    downloadBytes: 688066182,
    ramEstBytes: (11 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'hf.co/taobao-mnn/MNN-Pocket-0.3B-GGUF:Q4_1',
    downloadBytes: 191896672,
    ramEstBytes: (5 * _gb) ~/ 10,
    contextTokens: 40960,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
    directUrl:
        'https://huggingface.co/taobao-mnn/MNN-Pocket-0.3B-GGUF/resolve/'
        'main/MNN-Pocket-0.3B-Instruct-Q4_1.gguf',
  ),
  // -- tier 2: heavier, fine on 6 GB+ RAM devices (9) --------------------
  CatalogModelEntry(
    ollamaRef: 'qwen2.5-coder:1.5b',
    downloadBytes: 986061602,
    ramEstBytes: (15 * _gb) ~/ 10,
    contextTokens: 32768,
    tier: CatalogTier.tier2,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'deepseek-r1:1.5b',
    downloadBytes: 1117322281,
    ramEstBytes: (16 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.tier2,
    license: 'MIT',
  ),
  CatalogModelEntry(
    ollamaRef: 'lfm3:1.7b',
    downloadBytes: 1099638463,
    ramEstBytes: (16 * _gb) ~/ 10,
    contextTokens: 262144,
    tier: CatalogTier.tier2,
  ),
  CatalogModelEntry(
    ollamaRef: 'qwen3.5:0.8b',
    downloadBytes: 1322069043,
    ramEstBytes: (17 * _gb) ~/ 10,
    contextTokens: 262144,
    tier: CatalogTier.tier2,
  ),
  CatalogModelEntry(
    ollamaRef: 'llama3.2:1b',
    downloadBytes: 1321097844,
    ramEstBytes: (17 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.tier2,
    license: 'Llama-Community',
  ),
  CatalogModelEntry(
    ollamaRef: 'qwen3:1.7b',
    downloadBytes: 1359292957,
    ramEstBytes: (18 * _gb) ~/ 10,
    contextTokens: 40960,
    tier: CatalogTier.tier2,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'smollm2:1.7b',
    downloadBytes: 1820427974,
    ramEstBytes: (19 * _gb) ~/ 10,
    contextTokens: 8192,
    tier: CatalogTier.tier2,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'sam860/olmo2:1b',
    downloadBytes: 1581667706,
    ramEstBytes: (18 * _gb) ~/ 10,
    contextTokens: 4096,
    tier: CatalogTier.tier2,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'hf.co/zyr-AGENT/ZY-S2:Q5_K_M',
    downloadBytes: 1125049984,
    ramEstBytes: (14 * _gb) ~/ 10,
    contextTokens: 32768,
    tier: CatalogTier.tier2,
    license: 'Apache-2.0',
    directUrl:
        'https://huggingface.co/zyr-AGENT/ZY-S2/resolve/'
        'main/ZY-S2-Q5_K_M.gguf',
  ),
  // -- upper bound: risky, the UI warns about OOM kills (5) ---------------
  CatalogModelEntry(
    ollamaRef: 'bonsai-2:4b',
    downloadBytes: 1579008347,
    ramEstBytes: (26 * _gb) ~/ 10,
    contextTokens: 262144,
    tier: CatalogTier.upperBound,
  ),
  CatalogModelEntry(
    ollamaRef: 'qwen3.5:2b',
    downloadBytes: 2683396637,
    ramEstBytes: (29 * _gb) ~/ 10,
    contextTokens: 262144,
    tier: CatalogTier.upperBound,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'phi4-mini:3.8b',
    downloadBytes: 2491876363,
    ramEstBytes: (24 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.upperBound,
    license: 'MIT',
  ),
  CatalogModelEntry(
    ollamaRef: 'granite4.2:3b',
    downloadBytes: 2244023548,
    ramEstBytes: (26 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.upperBound,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'gemma4:e2b',
    downloadBytes: 4587156264,
    ramEstBytes: (35 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.upperBound,
    license: 'Apache-2.0',
  ),
];

// -- v1.52.0 (Fase 2) pure helpers ----------------------------------------

/// RAM auto-filter heuristic — v1.52.0 (Fase 2).
///
/// A model "fits" when its running footprint ([ramEstBytes], model
/// weights + KV cache) stays at or under 55% of the device's total RAM.
/// The 45% headroom is deliberate: the OS, the app itself, the GPU-side
/// buffers and KV-cache growth past the estimate all live in that slice,
/// so a model above the line is a realistic OOM-kill candidate on
/// low-RAM devices.
///
/// Defensive edges: unknown device RAM (`totalRamBytes <= 0`) means
/// nothing can be judged, so everything fits (the UI then hides the
/// filter); an unknown estimate (`ramEstBytes <= 0`) is never filtered.
bool catalogModelFits(int ramEstBytes, int totalRamBytes) {
  if (totalRamBytes <= 0) return true;
  if (ramEstBytes <= 0) return true;
  return ramEstBytes <= totalRamBytes * 55 ~/ 100;
}

/// Overlays [remote] (a fetched remote catalog) onto [base] (the
/// built-ins) — v1.52.0 (Fase 2).
///
/// * entries sharing an `ollamaRef` REPLACE the built-in row (remote
///   wins, last duplicate inside [remote] wins);
/// * entries with a ref unknown to [base] are APPENDED after the
///   built-ins, in [remote] order;
/// * an empty [remote] returns a copy of [base] untouched.
List<CatalogModelEntry> mergeCatalog(
  List<CatalogModelEntry> base,
  List<CatalogModelEntry> remote,
) {
  if (remote.isEmpty) return List<CatalogModelEntry>.of(base);
  final Map<String, CatalogModelEntry> byRef = <String, CatalogModelEntry>{
    for (final CatalogModelEntry entry in remote) entry.ollamaRef: entry,
  };
  final Set<String> baseRefs = <String>{
    for (final CatalogModelEntry entry in base) entry.ollamaRef,
  };
  final List<CatalogModelEntry> out = <CatalogModelEntry>[
    for (final CatalogModelEntry entry in base) byRef[entry.ollamaRef] ?? entry,
  ];
  for (final CatalogModelEntry entry in remote) {
    if (!baseRefs.contains(entry.ollamaRef)) out.add(entry);
  }
  return out;
}

/// Tolerant JSON of one entry — the SAME wire shape as
/// `assets/local_ai_catalog.json` (tier serialized by enum name).
Map<String, dynamic> catalogEntryToJson(CatalogModelEntry entry) =>
    <String, dynamic>{
      'ollamaRef': entry.ollamaRef,
      'downloadBytes': entry.downloadBytes,
      'ramEstBytes': entry.ramEstBytes,
      'contextTokens': entry.contextTokens,
      'tier': entry.tier.name,
      'license': entry.license,
      'directUrl': entry.directUrl,
    };

/// Tolerant reader for [catalogEntryToJson] output: missing keys degrade
/// to defaults, an unknown tier wire name falls back to [CatalogTier.tier2]
/// (the same rule the remote catalog applies).
CatalogModelEntry catalogEntryFromJson(Map<String, dynamic> json) =>
    CatalogModelEntry(
      ollamaRef: json['ollamaRef'] as String? ?? '',
      downloadBytes: (json['downloadBytes'] as num?)?.toInt() ?? 0,
      ramEstBytes: (json['ramEstBytes'] as num?)?.toInt() ?? 0,
      contextTokens: (json['contextTokens'] as num?)?.toInt() ?? 0,
      tier: switch (json['tier']) {
        'tier1' => CatalogTier.tier1,
        'upperBound' => CatalogTier.upperBound,
        _ => CatalogTier.tier2,
      },
      license: json['license'] as String? ?? '',
      directUrl: json['directUrl'] as String? ?? '',
    );
