/// Curated Local AI catalog — v1.51.0.
///
/// The download list offered by the Ollama Manage → Catalog tab: 14
/// llama.cpp-compatible GGUF picks from the Ollama registry, sized for
/// on-device use. Every entry carries the registry ref the downloader
/// resolves, the expected download size (from the approved proposal,
/// MB = 1024²), a RAM estimate for the running KV cache, the context
/// window the model is known to support and the license label shown in
/// the UI.
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

  /// Stable row id (the ref itself).
  String get id => ollamaRef;
}

const int _mb = 1024 * 1024;
const int _gb = 1024 * 1024 * 1024;

/// The 14 curated Local AI models (values from the approved v1.51.0
/// proposal). Keep in sync with the frozen contract §2.2 — S4's UI keys
/// off the tier counts (6 / 6 / 2).
const List<CatalogModelEntry> kLocalAiCatalog = <CatalogModelEntry>[
  // -- tier 1: safe on every supported device ---------------------------
  CatalogModelEntry(
    ollamaRef: 'qwen3:0.6b',
    downloadBytes: 523 * _mb,
    ramEstBytes: _gb,
    contextTokens: 40960,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'gemma3:1b',
    downloadBytes: 806 * _mb,
    ramEstBytes: (12 * _gb) ~/ 10,
    contextTokens: 32768,
    tier: CatalogTier.tier1,
    license: 'Gemma',
  ),
  CatalogModelEntry(
    ollamaRef: 'bonsai-2:2b',
    downloadBytes: 911 * _mb,
    ramEstBytes: (13 * _gb) ~/ 10,
    contextTokens: 262144,
    tier: CatalogTier.tier1,
  ),
  CatalogModelEntry(
    ollamaRef: 'gemma3:270m',
    downloadBytes: 292 * _mb,
    ramEstBytes: (7 * _gb) ~/ 10,
    contextTokens: 32768,
    tier: CatalogTier.tier1,
    license: 'Gemma',
  ),
  CatalogModelEntry(
    ollamaRef: 'smollm2:135m',
    downloadBytes: 271 * _mb,
    ramEstBytes: (6 * _gb) ~/ 10,
    contextTokens: 8192,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'smollm2:360m',
    downloadBytes: 726 * _mb,
    ramEstBytes: (11 * _gb) ~/ 10,
    contextTokens: 8192,
    tier: CatalogTier.tier1,
    license: 'Apache-2.0',
  ),
  // -- tier 2: heavier, fine on 6 GB+ RAM devices ------------------------
  CatalogModelEntry(
    ollamaRef: 'qwen2.5-coder:1.5b',
    downloadBytes: 1014 * _mb,
    ramEstBytes: (15 * _gb) ~/ 10,
    contextTokens: 32768,
    tier: CatalogTier.tier2,
    license: 'Apache-2.0',
  ),
  CatalogModelEntry(
    ollamaRef: 'deepseek-r1:1.5b',
    downloadBytes: 1153 * _mb,
    ramEstBytes: (16 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.tier2,
    license: 'MIT',
  ),
  CatalogModelEntry(
    ollamaRef: 'lfm3:1.7b',
    downloadBytes: 1423 * _mb,
    ramEstBytes: (16 * _gb) ~/ 10,
    contextTokens: 262144,
    tier: CatalogTier.tier2,
  ),
  CatalogModelEntry(
    ollamaRef: 'qwen3.5:0.8b',
    downloadBytes: 1311 * _mb,
    ramEstBytes: (17 * _gb) ~/ 10,
    contextTokens: 262144,
    tier: CatalogTier.tier2,
  ),
  CatalogModelEntry(
    ollamaRef: 'llama3.2:1b',
    downloadBytes: 1365 * _mb,
    ramEstBytes: (17 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.tier2,
    license: 'Llama-Community',
  ),
  CatalogModelEntry(
    ollamaRef: 'qwen3:1.7b',
    downloadBytes: 1468 * _mb,
    ramEstBytes: (18 * _gb) ~/ 10,
    contextTokens: 40960,
    tier: CatalogTier.tier2,
    license: 'Apache-2.0',
  ),
  // -- upper bound: risky, the UI warns about OOM kills ------------------
  CatalogModelEntry(
    ollamaRef: 'minicpm5-2b',
    downloadBytes: 1718 * _mb,
    ramEstBytes: (22 * _gb) ~/ 10,
    contextTokens: 131072,
    tier: CatalogTier.upperBound,
  ),
  CatalogModelEntry(
    ollamaRef: 'bonsai-2:4b',
    downloadBytes: 1718 * _mb,
    ramEstBytes: (26 * _gb) ~/ 10,
    contextTokens: 262144,
    tier: CatalogTier.upperBound,
  ),
];
