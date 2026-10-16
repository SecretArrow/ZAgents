import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// Capabilities a chat module can request in its manifest. Every granted
/// capability maps to a slice of the `zagents` SDK:
/// * `storage` — per-chat key/value store (`zagents.storage`)
/// * `network` — outbound HTTP (`zagents.http`)
/// * `files`   — file access sandboxed to the module's per-chat state dir
/// * `chat`    — post text into the conversation (`zagents.chat.emit`)
/// * `agent`   — ask the chat's own agent (LLM) to compose text
///   (`zagents.agent.compose`) — every sentence is generated live from the
///   context the module provides and passes the host-side composer gate
enum ModulePermission { storage, network, files, chat, agent }

/// Parses a manifest permission name; unknown names are dropped so a
/// typo in a third-party manifest can never widen the sandbox.
ModulePermission? modulePermissionFromName(String? name) {
  for (final ModulePermission p in ModulePermission.values) {
    if (p.name == name) return p;
  }
  return null;
}

/// Declared + parsed manifest of an installed chat module.
class ModuleManifest {
  const ModuleManifest({
    required this.name,
    required this.version,
    required this.title,
    required this.description,
    required this.entry,
    this.permissions = const <ModulePermission>{},
    this.allowedHosts,
    this.timeoutSeconds = defaultTimeoutSeconds,
  });

  /// Default execution budget for one module run (seconds). A manifest may
  /// raise this up to [maxTimeoutSeconds]; anything higher is clamped.
  static const int defaultTimeoutSeconds = 30;
  static const int maxTimeoutSeconds = 120;

  /// Machine identifier, lowercase `[a-z0-9._-]`, used as directory name.
  final String name;
  final String version;

  /// Human-readable display name (defaults to [name]).
  final String title;
  final String description;

  /// Entry point relative to the module root (e.g. `main.js`).
  final String entry;
  final Set<ModulePermission> permissions;

  /// When non-empty, `zagents.http` may only reach these hosts.
  final List<String>? allowedHosts;
  final int timeoutSeconds;

  Duration get timeout =>
      Duration(seconds: timeoutSeconds.clamp(1, maxTimeoutSeconds));

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'version': version,
    'title': title,
    'description': description,
    'entry': entry,
    'permissions': permissions.map((p) => p.name).toList(),
    if (allowedHosts != null) 'allowedHosts': allowedHosts,
    'timeoutSeconds': timeoutSeconds,
  };

  /// Defensive parse: bad types fall back to safe defaults, unknown
  /// permissions are dropped, [name] is sanitized.
  static ModuleManifest fromJson(Map<String, dynamic> json) => ModuleManifest(
    name: sanitizeName(json['name']?.toString() ?? ''),
    version: json['version']?.toString() ?? '0.0.0',
    title: json['title']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    entry: json['entry']?.toString() ?? 'main.js',
    permissions:
        ((json['permissions'] as List<dynamic>? ?? const <dynamic>[])
                .map((Object? p) => modulePermissionFromName(p?.toString()))
                .whereType<ModulePermission>())
            .toSet(),
    allowedHosts: (json['allowedHosts'] as List<dynamic>?)
        ?.map((Object? h) => h.toString())
        .toList(),
    timeoutSeconds: json['timeoutSeconds'] is int
        ? json['timeoutSeconds'] as int
        : defaultTimeoutSeconds,
  );

  /// Lowercase, keep `[a-z0-9._-]`, collapse the rest into `-`, trim
  /// leading dots/dashes. Empty results fall back to `module`.
  static String sanitizeName(String raw) {
    String name = raw.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]+'),
      '-',
    );
    while (name.startsWith('.') || name.startsWith('-')) {
      name = name.substring(1);
    }
    while (name.endsWith('.') || name.endsWith('-')) {
      name = name.substring(0, name.length - 1);
    }
    name = name.replaceAll(RegExp(r'-{2,}'), '-');
    if (name.length > maxNameLength) name = name.substring(0, maxNameLength);
    if (name.isEmpty || name == '.' || name == '..') return 'module';
    return name;
  }

  static const int maxNameLength = 40;
}

/// An installed chat module: manifest plus on-disk location.
class ChatModule {
  const ChatModule({
    required this.manifest,
    required this.path,
    required this.installedAt,
  });

  final ModuleManifest manifest;
  final String path;
  final DateTime installedAt;

  String get name => manifest.name;

  /// Absolute path of the entry point (e.g. `<path>/main.js`).
  String get entryPath => '$path${Platform.pathSeparator}${manifest.entry}';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'manifest': manifest.toJson(),
    'path': path,
    'installedAt': installedAt.toIso8601String(),
  };

  static ChatModule fromJson(Map<String, dynamic> json) => ChatModule(
    manifest: ModuleManifest.fromJson(
      (json['manifest'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
    ),
    path: json['path']?.toString() ?? '',
    installedAt:
        DateTime.tryParse(json['installedAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}

/// Outcome of [ModuleRegistry.installFromZip].
class ModuleInstallResult {
  const ModuleInstallResult({
    required this.ok,
    required this.message,
    this.module,
  });

  final bool ok;
  final String message;
  final ChatModule? module;
}

/// Installs, lists and removes chat modules ("plugins").
///
/// A module is a ZIP archive containing at least one JavaScript entry
/// point (default `main.js`) plus an optional `module.json` manifest
/// (fallback: `package.json` name/version/main). Archives may wrap
/// everything in a single top-level directory — the standard GitHub
/// "Download ZIP" layout — which is unwrapped automatically.
///
/// Security model:
/// * ZIP entries are validated against path traversal (`zip-slip`):
///   absolute paths and `..` escapes abort the whole install.
/// * Resource caps: file count, per-file size and total unpacked size.
/// * The sanitized module name doubles as the install directory name, so
///   a hostile manifest can never write outside `<docs>/modules/`.
class ModuleRegistry {
  ModuleRegistry({required this.resolveBaseDir});

  /// Yields the app documents directory (overridden in tests).
  final Future<Directory> Function() resolveBaseDir;

  /// Unpacked-size budget per module.
  static const int maxTotalBytes = 32 * 1024 * 1024;
  static const int maxFileBytes = 8 * 1024 * 1024;
  static const int maxFileCount = 500;

  /// Compressed-install budget (ZIP bytes).
  static const int maxZipBytes = 48 * 1024 * 1024;

  Directory? _modulesDirCache;

  /// Synchronous view of the registry, refreshed by every async registry
  /// operation — lets the chat controller enrich the system prompt without
  /// awaiting IO inside the wire build.
  Map<String, ChatModule>? _syncCache;

  /// Idempotently loads the synchronous cache.
  Future<void> ensureCacheLoaded() async {
    if (_syncCache != null) return;
    await _loadRegistry();
  }

  /// Synchronous lookup after [ensureCacheLoaded]/any registry operation.
  ChatModule? getSync(String name) =>
      _syncCache?[ModuleManifest.sanitizeName(name)];

  /// `<docs>/modules` (created on demand).
  Future<Directory> modulesDir() async {
    if (_modulesDirCache != null) return _modulesDirCache!;
    final Directory base = await resolveBaseDir();
    final Directory dir = Directory(
      '${base.path}${Platform.pathSeparator}modules',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _modulesDirCache = dir;
    return dir;
  }

  /// `<docs>/modules/registry.json` — durable install bookkeeping.
  Future<File> registryFile() async {
    final Directory dir = await modulesDir();
    return File('${dir.path}${Platform.pathSeparator}registry.json');
  }

  /// Lists installed modules, sorted by name. Corrupted registry entries
  /// and modules whose directory vanished are skipped.
  Future<List<ChatModule>> listInstalled() async {
    final Map<String, ChatModule> registry = await _loadRegistry();
    final List<ChatModule> out = <ChatModule>[];
    for (final ChatModule module in registry.values) {
      if (!Directory(module.path).existsSync()) continue;
      out.add(module);
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// Looks one module up by (sanitized) name.
  Future<ChatModule?> get(String name) async {
    final String key = ModuleManifest.sanitizeName(name);
    final Map<String, ChatModule> registry = await _loadRegistry();
    final ChatModule? module = registry[key];
    if (module == null || !Directory(module.path).existsSync()) return null;
    return module;
  }

  /// Removes a module (directory + registry entry). Returns true when it
  /// existed. Per-chat state lives inside session sandboxes and is NOT
  /// touched — deleting a module never deletes chat data.
  Future<bool> remove(String name) async {
    final String key = ModuleManifest.sanitizeName(name);
    final Map<String, ChatModule> registry = await _loadRegistry();
    final ChatModule? module = registry.remove(key);
    if (module == null) return false;
    final Directory dir = Directory(module.path);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    await _saveRegistry(registry);
    return true;
  }

  /// Installs a module from a local `.zip` file. Re-installing an existing
  /// module name replaces it atomically (staging directory + rename).
  Future<ModuleInstallResult> installFromZip(String zipPath) async {
    final File zip = File(zipPath);
    if (!zip.existsSync()) {
      return const ModuleInstallResult(
        ok: false,
        message: 'ZIP file not found',
      );
    }
    final List<int> bytes;
    try {
      bytes = await zip.readAsBytes();
    } catch (e) {
      return ModuleInstallResult(ok: false, message: 'Cannot read ZIP: $e');
    }
    if (bytes.length > maxZipBytes) {
      return const ModuleInstallResult(
        ok: false,
        message: 'ZIP is too large (limit 48 MB)',
      );
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      return ModuleInstallResult(ok: false, message: 'Not a valid ZIP: $e');
    }
    if (archive.isEmpty) {
      return const ModuleInstallResult(ok: false, message: 'ZIP is empty');
    }

    // Unwrap the common "single top-level directory" layout.
    final String prefix = _commonRootPrefix(archive);
    final Map<String, ArchiveFile> files = <String, ArchiveFile>{};
    int totalBytes = 0;
    for (final ArchiveFile entry in archive) {
      if (entry.isFile) {
        final String rel = entry.name
            .replaceAll('\\', '/')
            .substring(prefix.length);
        if (rel.isEmpty) continue;
        files[rel] = entry;
        totalBytes += entry.size;
        if (files.length > maxFileCount) {
          return ModuleInstallResult(
            ok: false,
            message: 'Module has too many files (limit $maxFileCount)',
          );
        }
        if (entry.size > maxFileBytes) {
          return const ModuleInstallResult(
            ok: false,
            message: 'Module file exceeds 8 MB (limit per file)',
          );
        }
        if (totalBytes > maxTotalBytes) {
          return const ModuleInstallResult(
            ok: false,
            message: 'Module unpacked size exceeds 32 MB (limit)',
          );
        }
      }
    }
    if (files.isEmpty) {
      return const ModuleInstallResult(
        ok: false,
        message: 'ZIP contains no files',
      );
    }

    // Manifest: module.json > package.json > synthesized from ZIP name.
    final Map<String, dynamic>? manifestJson =
        _readJsonFile(files, 'module.json') ??
        _readJsonFile(files, 'package.json');
    final String zipStem = zipPath
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');
    final ModuleManifest manifest = ModuleManifest.fromJson(<String, dynamic>{
      ...?manifestJson,
      'name': (manifestJson?['name'] as String?)?.isNotEmpty == true
          ? manifestJson!['name']
          : zipStem,
      'entry':
          (manifestJson?['entry'] ?? manifestJson?['main'])?.toString() ??
          'main.js',
    });
    if (manifest.name.isEmpty) {
      return const ModuleInstallResult(
        ok: false,
        message: 'Module name is missing (add module.json)',
      );
    }
    if (!files.containsKey(manifest.entry)) {
      return ModuleInstallResult(
        ok: false,
        message: 'Entry point "${manifest.entry}" not found in the ZIP',
      );
    }

    // zip-slip check BEFORE any byte touches the disk.
    for (final String rel in files.keys) {
      if (!_isSafeRelativePath(rel)) {
        return ModuleInstallResult(
          ok: false,
          message: 'Unsafe ZIP entry rejected: $rel',
        );
      }
    }

    final Directory modules = await modulesDir();
    final Directory staging = Directory(
      '${modules.path}${Platform.pathSeparator}'
      '.staging_${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      await staging.create(recursive: true);
      for (final MapEntry<String, ArchiveFile> entry in files.entries) {
        final File target = File(
          '${staging.path}${Platform.pathSeparator}'
          '${entry.key.replaceAll('/', Platform.pathSeparator)}',
        );
        // Paths are pre-validated (_isSafeRelativePath), so a direct byte
        // write is safe — and preserves the RELATIVE layout, unlike
        // extractArchiveToDisk which would replay original entry names.
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value.content as List<int>);
      }
      final Directory target = Directory(
        '${modules.path}${Platform.pathSeparator}${manifest.name}',
      );
      if (target.existsSync()) {
        await target.delete(recursive: true);
      }
      await staging.rename(target.path);
      final ChatModule module = ChatModule(
        manifest: manifest,
        path: target.path,
        installedAt: DateTime.now(),
      );
      final Map<String, ChatModule> registry = await _loadRegistry();
      registry[manifest.name] = module;
      await _saveRegistry(registry);
      return ModuleInstallResult(
        ok: true,
        message: 'Installed ${manifest.name} v${manifest.version}',
        module: module,
      );
    } catch (e) {
      try {
        if (staging.existsSync()) await staging.delete(recursive: true);
      } catch (_) {}
      return ModuleInstallResult(ok: false, message: 'Install failed: $e');
    }
  }

  /// Resolves the shared npm library root used alongside the module dir
  /// for `require()` (modules may reuse globally installed packages).
  Future<String> npmModulesRoot() async {
    final Directory base = await resolveBaseDir();
    return '${base.path}${Platform.pathSeparator}node_modules';
  }

  Map<String, dynamic>? _readJsonFile(
    Map<String, ArchiveFile> files,
    String name,
  ) {
    final ArchiveFile? file = files[name];
    if (file == null) return null;
    try {
      final Object? decoded = jsonDecode(
        utf8.decode(file.content as List<int>),
      );
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  /// True when [rel] (forward-slash relative path) cannot escape the
  /// module directory: no absolute paths, no `..`, no empty segments, no
  /// Windows drive letters.
  static bool _isSafeRelativePath(String rel) {
    if (rel.isEmpty || rel.startsWith('/')) return false;
    if (rel.contains(':')) return false;
    for (final String segment in rel.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') return false;
    }
    return true;
  }

  /// Longest `dir/` prefix shared by ALL entries ("" when the archive is
  /// flat). Enables automatic unwrapping of `module-main/...` layouts.
  static String _commonRootPrefix(Archive archive) {
    final List<String> names = <String>[
      for (final ArchiveFile e in archive)
        if (e.isFile) e.name.replaceAll('\\', '/'),
    ];
    if (names.isEmpty) return '';
    String? prefix;
    for (final String name in names) {
      final int slash = name.indexOf('/');
      final String head = slash == -1 ? '' : '${name.substring(0, slash)}/';
      prefix = prefix == null ? head : (prefix == head ? prefix : '');
      if (prefix.isEmpty) return '';
    }
    return prefix ?? '';
  }

  Future<Map<String, ChatModule>> _loadRegistry() async {
    final File file = await registryFile();
    if (!file.existsSync()) {
      _syncCache = <String, ChatModule>{};
      return <String, ChatModule>{};
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        _syncCache = <String, ChatModule>{};
        return <String, ChatModule>{};
      }
      final Map<String, ChatModule> registry = <String, ChatModule>{
        for (final MapEntry<dynamic, dynamic> entry in decoded.entries)
          if (entry.value is Map)
            entry.key.toString(): ChatModule.fromJson(
              (entry.value as Map<dynamic, dynamic>).cast<String, dynamic>(),
            ),
      };
      _syncCache = registry;
      return registry;
    } catch (_) {
      _syncCache = <String, ChatModule>{};
      return <String, ChatModule>{};
    }
  }

  Future<void> _saveRegistry(Map<String, ChatModule> registry) async {
    final File file = await registryFile();
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, ChatModule> e in registry.entries)
          e.key: e.value.toJson(),
      }),
    );
  }
}
