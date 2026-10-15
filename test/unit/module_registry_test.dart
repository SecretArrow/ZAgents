import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/services/module_registry.dart';

/// Builds a ZIP in memory from {path: bytes}.
List<int> buildZip(Map<String, List<int>> files) {
  final Archive archive = Archive();
  files.forEach((String path, List<int> bytes) {
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}

List<int> textZip(Map<String, String> files) => buildZip(<String, List<int>>{
  for (final MapEntry<String, String> e in files.entries)
    e.key: e.value.codeUnits,
});

void main() {
  late Directory tempDir;
  late ModuleRegistry registry;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('module_registry_test');
    registry = ModuleRegistry(resolveBaseDir: () async => tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('ModuleManifest', () {
    test('sanitizes hostile names into safe directory names', () {
      expect(ModuleManifest.sanitizeName('My Cool Module!'), 'my-cool-module');
      expect(ModuleManifest.sanitizeName('../../etc/passwd'), 'etc-passwd');
      expect(ModuleManifest.sanitizeName('..'), 'module');
      expect(ModuleManifest.sanitizeName(''), 'module');
      expect(ModuleManifest.sanitizeName('A' * 60).length, 40);
      expect(ModuleManifest.sanitizeName('...'), 'module');
    });

    test('parses permissions defensively and drops unknown names', () {
      final ModuleManifest manifest = ModuleManifest.fromJson(<String, dynamic>{
        'name': 'demo',
        'permissions': <String>['storage', 'nonsense', 'network'],
      });
      expect(manifest.permissions, <ModulePermission>{
        ModulePermission.storage,
        ModulePermission.network,
      });
      expect(manifest.entry, 'main.js');
      expect(manifest.timeout, const Duration(seconds: 30));
    });

    test('clamps the timeout to the documented maximum', () {
      final ModuleManifest manifest = ModuleManifest.fromJson(<String, dynamic>{
        'name': 'demo',
        'timeoutSeconds': 9999,
      });
      expect(manifest.timeout.inSeconds, ModuleManifest.maxTimeoutSeconds);
    });
  });

  group('installFromZip', () {
    test('installs a flat module with module.json', () async {
      final File zip = File('${tempDir.path}${Platform.pathSeparator}demo.zip')
        ..writeAsBytesSync(
          textZip(<String, String>{
            'module.json':
                '{"name":"demo","version":"1.2.0","description":"Demo module",'
                '"permissions":["storage"],"entry":"main.js"}',
            'main.js': "console.log('hi');",
            'lib/util.js': 'module.exports = 1;',
          }),
        );
      final ModuleInstallResult result = await registry.installFromZip(
        zip.path,
      );
      expect(result.ok, isTrue, reason: result.message);
      expect(result.module!.name, 'demo');
      expect(result.module!.manifest.version, '1.2.0');
      expect(
        File(result.module!.entryPath).readAsStringSync(),
        contains('console.log'),
      );
      expect(
        File(
          '${result.module!.path}${Platform.pathSeparator}lib'
          '${Platform.pathSeparator}util.js',
        ).existsSync(),
        isTrue,
      );
      // Registry persistence: a fresh instance sees the module.
      final List<ChatModule> installed = await registry.listInstalled();
      expect(installed, hasLength(1));
      expect(installed.single.manifest.description, 'Demo module');
    });

    test('unwraps a single top-level directory (GitHub ZIP layout)', () async {
      final File zip =
          File('${tempDir.path}${Platform.pathSeparator}wrapped.zip')
            ..writeAsBytesSync(
              textZip(<String, String>{
                'wrapped-main/module.json': '{"name":"wrapped"}',
                'wrapped-main/main.js': 'module.exports = "ok";',
              }),
            );
      final ModuleInstallResult result = await registry.installFromZip(
        zip.path,
      );
      expect(result.ok, isTrue, reason: result.message);
      expect(result.module!.name, 'wrapped');
      expect(File(result.module!.entryPath).existsSync(), isTrue);
    });

    test('falls back to package.json (name/version/main)', () async {
      final File zip = File('${tempDir.path}${Platform.pathSeparator}pkged.zip')
        ..writeAsBytesSync(
          textZip(<String, String>{
            'package.json':
                '{"name":"pkged","version":"0.1.0","main":"lib/entry.js"}',
            'lib/entry.js': 'module.exports = "entry";',
          }),
        );
      final ModuleInstallResult result = await registry.installFromZip(
        zip.path,
      );
      expect(result.ok, isTrue, reason: result.message);
      expect(result.module!.name, 'pkged');
      expect(result.module!.manifest.entry, 'lib/entry.js');
    });

    test('falls back to the ZIP file name without any manifest', () async {
      final File zip = File('${tempDir.path}${Platform.pathSeparator}bare.zip')
        ..writeAsBytesSync(
          textZip(<String, String>{'main.js': 'module.exports = "bare";'}),
        );
      final ModuleInstallResult result = await registry.installFromZip(
        zip.path,
      );
      expect(result.ok, isTrue, reason: result.message);
      expect(result.module!.name, 'bare');
    });

    test('rejects a missing entry point with a clear message', () async {
      final File zip =
          File('${tempDir.path}${Platform.pathSeparator}broken.zip')
            ..writeAsBytesSync(
              textZip(<String, String>{
                'module.json': '{"name":"broken","entry":"start.js"}',
                'main.js': '// not the declared entry',
              }),
            );
      final ModuleInstallResult result = await registry.installFromZip(
        zip.path,
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('start.js'));
    });

    test('blocks zip-slip path traversal entries', () async {
      final File zip = File('${tempDir.path}${Platform.pathSeparator}evil.zip')
        ..writeAsBytesSync(
          textZip(<String, String>{
            'module.json': '{"name":"evil"}',
            'main.js': '// ok',
            '../escaped.js': 'module.exports = "pwned";',
          }),
        );
      final ModuleInstallResult result = await registry.installFromZip(
        zip.path,
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('Unsafe ZIP entry'));
      // Nothing was installed.
      expect(await registry.listInstalled(), isEmpty);
      expect(
        File('${tempDir.path}${Platform.pathSeparator}escaped.js').existsSync(),
        isFalse,
      );
    });

    test('rejects invalid archives and empty ZIPs', () async {
      final File garbage = File(
        '${tempDir.path}${Platform.pathSeparator}garbage.zip',
      )..writeAsBytesSync(<int>[1, 2, 3, 4]);
      expect((await registry.installFromZip(garbage.path)).ok, isFalse);

      final File empty = File(
        '${tempDir.path}${Platform.pathSeparator}empty.zip',
      )..writeAsBytesSync(buildZip(<String, List<int>>{}));
      expect((await registry.installFromZip(empty.path)).ok, isFalse);

      final File missing = File(
        '${tempDir.path}${Platform.pathSeparator}nope.zip',
      );
      expect((await registry.installFromZip(missing.path)).ok, isFalse);
    });

    test('re-installing the same name replaces the module', () async {
      final File first =
          File('${tempDir.path}${Platform.pathSeparator}replace.zip')
            ..writeAsBytesSync(
              textZip(<String, String>{
                'module.json': '{"name":"replace","version":"1.0.0"}',
                'main.js': 'v1',
              }),
            );
      expect((await registry.installFromZip(first.path)).ok, isTrue);

      final File second =
          File('${tempDir.path}${Platform.pathSeparator}replace2.zip')
            ..writeAsBytesSync(
              textZip(<String, String>{
                'module.json': '{"name":"replace","version":"2.0.0"}',
                'main.js': 'v2',
                'extra.js': 'x',
              }),
            );
      expect((await registry.installFromZip(second.path)).ok, isTrue);

      final List<ChatModule> installed = await registry.listInstalled();
      expect(installed, hasLength(1));
      expect(installed.single.manifest.version, '2.0.0');
      expect(File(installed.single.entryPath).readAsStringSync(), 'v2');
      // No staging directories left behind.
      final Directory modules = await registry.modulesDir();
      expect(
        modules.listSync().where((e) => e.path.contains('.staging')),
        isEmpty,
      );
    });

    test(
      'remove deletes the directory but keeps chat sandboxes untouched',
      () async {
        final File zip =
            File('${tempDir.path}${Platform.pathSeparator}gone.zip')
              ..writeAsBytesSync(
                textZip(<String, String>{
                  'module.json': '{"name":"gone"}',
                  'main.js': '//',
                }),
              );
        final ChatModule module = (await registry.installFromZip(zip.path))
            .module!;
        // Simulated per-chat state elsewhere.
        final Directory chatState = Directory(
          '${tempDir.path}${Platform.pathSeparator}sessions'
          '${Platform.pathSeparator}s1${Platform.pathSeparator}modules'
          '${Platform.pathSeparator}gone',
        )..createSync(recursive: true);
        File('${chatState.path}${Platform.pathSeparator}storage.json')
            .writeAsStringSync('{"k":1}');

        expect(await registry.remove('gone'), isTrue);
        expect(Directory(module.path).existsSync(), isFalse);
        expect(
          File('${chatState.path}${Platform.pathSeparator}storage.json')
              .existsSync(),
          isTrue,
        );
        expect(await registry.remove('gone'), isFalse);
      },
    );

    test(
      'get() sanitizes lookups and returns null for unknown modules',
      () async {
        final File zip =
            File('${tempDir.path}${Platform.pathSeparator}named.zip')
              ..writeAsBytesSync(
                textZip(<String, String>{
                  'module.json': '{"name":"named"}',
                  'main.js': '//',
                }),
              );
        await registry.installFromZip(zip.path);
        expect((await registry.get('named'))!.name, 'named');
        expect(await registry.get('NAMED'), isNotNull);
        expect(await registry.get('unknown'), isNull);
      },
    );
  });
}
