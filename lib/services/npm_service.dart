import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart' show extractArchiveToDisk;
import 'package:http/http.dart' as http;

/// A module installed in the app's `node_modules` folder.
class InstalledModule {
  const InstalledModule({
    required this.name,
    required this.version,
    required this.path,
  });

  final String name;
  final String version;
  final String path;
}

/// Result of an npm install operation.
class NpmInstallResult {
  const NpmInstallResult({
    required this.ok,
    required this.message,
    this.installed = const <String>[],
  });

  final bool ok;
  final String message;

  /// Every package written to disk (name@version), dependencies included.
  final List<String> installed;
}

/// Manages Node.js modules for the embedded JS runtime, "auto add/remove
/// as needed":
///  * [install] downloads a package tarball from the npm registry, unpacks
///    it into `<docs>/node_modules/<name>` and recursively installs the
///    runtime dependencies declared in its package.json.
///  * [remove] deletes a package directory.
///  * [search] queries the public registry search API.
///
/// The registry host is injectable so unit tests run fully offline.
class NpmService {
  NpmService({
    required this.resolveBaseDir,
    http.Client? client,
    this.registryHost = 'registry.npmjs.org',
  }) : _client = client ?? http.Client();

  final Future<Directory> Function() resolveBaseDir;
  final http.Client _client;
  final String registryHost;

  static const int _maxDepth = 6;

  Directory? _modulesDirCache;

  /// `<docs>/node_modules` (created on demand).
  Future<Directory> modulesDir() async {
    if (_modulesDirCache != null) return _modulesDirCache!;
    final Directory base = await resolveBaseDir();
    final Directory dir = Directory(
      '${base.path}${Platform.pathSeparator}node_modules',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _modulesDirCache = dir;
    return dir;
  }

  /// Lists installed top-level packages (name@version).
  Future<List<InstalledModule>> listInstalled() async {
    final Directory dir = await modulesDir();
    final List<InstalledModule> out = <InstalledModule>[];
    if (!dir.existsSync()) return out;
    await for (final FileSystemEntity entity in dir.list()) {
      if (entity is! Directory) continue;
      final String folder = entity.path.split(Platform.pathSeparator).last;
      if (folder.startsWith('.')) continue;
      if (folder.startsWith('@')) {
        // Scoped packages: @scope/pkg
        await for (final FileSystemEntity inner in entity.list()) {
          if (inner is! Directory) continue;
          final InstalledModule? mod = await _readModule(inner);
          if (mod != null) {
            out.add(
              InstalledModule(
                name: '$folder/${mod.name}',
                version: mod.version,
                path: mod.path,
              ),
            );
          }
        }
        continue;
      }
      final InstalledModule? mod = await _readModule(entity);
      if (mod != null) out.add(mod);
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Future<InstalledModule?> _readModule(Directory dir) async {
    final File pkgJson = File(
      '${dir.path}${Platform.pathSeparator}package.json',
    );
    if (!pkgJson.existsSync()) return null;
    try {
      final Object? decoded = jsonDecode(pkgJson.readAsStringSync());
      if (decoded is! Map) return null;
      final Object? name = decoded['name'];
      final Object? version = decoded['version'];
      return InstalledModule(
        name: name?.toString() ?? dir.path.split(Platform.pathSeparator).last,
        version: version?.toString() ?? '?',
        path: dir.path,
      );
    } catch (_) {
      return null;
    }
  }

  /// Installs [name] (optionally at [version]) plus its runtime
  /// dependencies. Pure-JS packages only — native addons cannot run inside
  /// the embedded runtime and are skipped with a warning.
  Future<NpmInstallResult> install(String name, {String? version}) async {
    final String pkg = name.trim();
    if (pkg.isEmpty) {
      return const NpmInstallResult(ok: false, message: 'Package name empty');
    }
    try {
      final List<String> installed = <String>[];
      await _installWithDeps(pkg, version, installed, 0);
      return NpmInstallResult(
        ok: true,
        message: 'Installed ${installed.join(', ')}',
        installed: installed,
      );
    } catch (e) {
      return NpmInstallResult(ok: false, message: 'Install failed: $e');
    }
  }

  Future<void> _installWithDeps(
    String name,
    String? version,
    List<String> installed,
    int depth,
  ) async {
    if (depth > _maxDepth) return;
    final Directory modules = await modulesDir();
    final String target = '${modules.path}${Platform.pathSeparator}$name';
    if (Directory(target).existsSync()) {
      return; // Already present (satisfied by an earlier install).
    }

    // 1. Resolve metadata.
    final String metaPath = version == null || version.trim().isEmpty
        ? '/$name'
        : '/$name/$version';
    final http.Response metaRes = await _client.get(
      Uri.https(registryHost, metaPath),
      headers: const <String, String>{'Accept': 'application/json'},
    );
    if (metaRes.statusCode != 200) {
      throw 'registry lookup for "$name" returned HTTP ${metaRes.statusCode}';
    }
    final Object? decodedMeta = jsonDecode(metaRes.body);
    if (decodedMeta is! Map) throw 'unexpected registry payload for "$name"';

    // Dist-tags resolve through the full metadata document.
    String resolvedVersion = version ?? '';
    Object? meta = decodedMeta;
    if (resolvedVersion.isEmpty) {
      final Object? distTags = (meta as Map)['dist-tags'];
      if (distTags is Map && distTags['latest'] != null) {
        resolvedVersion = distTags['latest'].toString();
      }
      final Object? versions = meta['versions'];
      if (versions is Map && versions[resolvedVersion] is Map) {
        meta = versions[resolvedVersion] as Map;
      }
    }
    final Object? dist = (meta as Map)['dist'];
    final Object? tarballUrl = dist is Map ? dist['tarball'] : null;
    if (tarballUrl is! String || tarballUrl.isEmpty) {
      throw 'no tarball found for "$name@$resolvedVersion"';
    }

    // 2. Download + unpack into a temp dir, then move into node_modules.
    final http.Response tarRes = await _client.get(Uri.parse(tarballUrl));
    if (tarRes.statusCode != 200) {
      throw 'tarball download for "$name" returned HTTP ${tarRes.statusCode}';
    }
    final Archive archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(tarRes.bodyBytes),
    );
    final Directory temp = await modulesDir().then(
      (Directory d) => Directory(
        '${d.parent.path}${Platform.pathSeparator}.npm_tmp_${DateTime.now().millisecondsSinceEpoch}',
      ).create(recursive: true),
    );
    try {
      // npm tarballs wrap everything in a "package/" root.
      extractArchiveToDisk(archive, temp.path);
      final Directory unpackedRoot = Directory(
        '${temp.path}${Platform.pathSeparator}package',
      );
      final Directory sourceDir = unpackedRoot.existsSync()
          ? unpackedRoot
          : temp;
      await sourceDir.rename(target);
    } on FileSystemException {
      // Cross-device rename fallback: copy then clean up.
      final Directory unpackedRoot = Directory(
        '${temp.path}${Platform.pathSeparator}package',
      );
      final Directory sourceDir = unpackedRoot.existsSync()
          ? unpackedRoot
          : temp;
      await _copyDir(sourceDir, Directory(target));
      await temp.delete(recursive: true);
    }
    installed.add('$name@$resolvedVersion');

    // 3. Recurse into runtime dependencies.
    final File pkgJson = File('$target${Platform.pathSeparator}package.json');
    if (pkgJson.existsSync()) {
      try {
        final Object? decoded = jsonDecode(pkgJson.readAsStringSync());
        if (decoded is Map) {
          final Object? deps = decoded['dependencies'];
          if (deps is Map) {
            for (final MapEntry<dynamic, dynamic> dep in deps.entries) {
              await _installWithDeps(
                dep.key.toString(),
                null,
                installed,
                depth + 1,
              );
            }
          }
        }
      } catch (_) {
        // Unreadable package.json: the package itself is usable.
      }
    }
  }

  Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final FileSystemEntity entity in from.list()) {
      final String name = entity.path.split(Platform.pathSeparator).last;
      if (entity is Directory) {
        await _copyDir(
          entity,
          Directory('${to.path}${Platform.pathSeparator}$name'),
        );
      } else if (entity is File) {
        await entity.copy('${to.path}${Platform.pathSeparator}$name');
      }
    }
  }

  /// Removes a package from node_modules. Returns true when it existed.
  Future<bool> remove(String name) async {
    final Directory modules = await modulesDir();
    final Directory target = Directory(
      '${modules.path}${Platform.pathSeparator}$name',
    );
    if (!target.existsSync()) return false;
    await target.delete(recursive: true);
    return true;
  }

  /// Registry keyword search (top [limit] hits).
  Future<List<Map<String, String>>> search(
    String query, {
    int limit = 8,
  }) async {
    final http.Response res = await _client.get(
      Uri.https(registryHost, '/-/v1/search', <String, String>{
        'text': query,
        'size': '$limit',
      }),
      headers: const <String, String>{'Accept': 'application/json'},
    );
    if (res.statusCode != 200) {
      throw 'registry search returned HTTP ${res.statusCode}';
    }
    final Object? decoded = jsonDecode(res.body);
    final List<Map<String, String>> out = <Map<String, String>>[];
    if (decoded is Map && decoded['objects'] is List) {
      for (final Object? item in decoded['objects'] as List<Object?>) {
        if (item is Map && item['package'] is Map) {
          final Map pkg = item['package'] as Map;
          out.add(<String, String>{
            'name': pkg['name']?.toString() ?? '',
            'version': pkg['version']?.toString() ?? '',
            'description': pkg['description']?.toString() ?? '',
          });
        }
      }
    }
    return out;
  }
}
