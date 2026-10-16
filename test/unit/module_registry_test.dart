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

  group('ModuleSetup (per-chat setup form)', () {
    test('parses fields defensively: types, keys, caps, dedupe', () {
      final ModuleSetup? setup = ModuleSetup.fromJson(<String, dynamic>{
        'title': 'Acct',
        'description': 'creds',
        'fields': <dynamic>[
          <String, dynamic>{'key': 'Email', 'label': 'Email', 'required': true},
          <String, dynamic>{'key': 'email', 'label': 'Duplicate dropped'},
          <String, dynamic>{
            'key': 'pass',
            'type': 'password',
            'required': true,
            'placeholder': 'hunter2',
          },
          <String, dynamic>{'key': 'retries', 'type': 'number'},
          <String, dynamic>{'key': 'verbose', 'type': 'boolean'},
          <String, dynamic>{'key': 'weird type', 'type': 'nonsense'},
          <String, dynamic>{'key': '', 'label': 'dropped (no key)'},
          'not-a-map',
        ],
      });
      expect(setup, isNotNull);
      // email, pass, retries, verbose, weird_type — duplicate/empty/
      // non-map entries dropped, keys sanitized, first duplicate wins.
      expect(setup!.fields, hasLength(5));
      expect(setup.fields.first.key, 'email');
      expect(setup.fields.first.required, isTrue);
      expect(setup.fields[1].type, ModuleSetupFieldType.password);
      expect(setup.fields[2].type, ModuleSetupFieldType.number);
      expect(setup.fields[3].type, ModuleSetupFieldType.boolean);
      // Unknown type degrades to text; key whitespace collapsed.
      expect(setup.fields.last.type, ModuleSetupFieldType.text);
      expect(setup.fields.last.key, 'weird_type');
      expect(setup.hasRequired, isTrue);
    });

    test('caps the field list at 12 and long text fields', () {
      final List<Map<String, dynamic>> many = <Map<String, dynamic>>[
        for (int i = 0; i < 20; i++)
          <String, dynamic>{'key': 'f$i', 'label': 'F$i'},
      ];
      final ModuleSetup? setup = ModuleSetup.fromJson(<String, dynamic>{
        'title': 'T' * 100,
        'fields': many,
      });
      expect(setup, isNotNull);
      expect(setup!.fields, hasLength(ModuleSetup.maxFields));
      expect(setup.title.length, 80);
    });

    test('empty or unusable blocks parse to null', () {
      expect(
        ModuleSetup.fromJson(<String, dynamic>{'fields': <dynamic>[]}),
        isNull,
      );
      expect(
        ModuleSetup.fromJson(<String, dynamic>{
          'fields': <dynamic>['x'],
        }),
        isNull,
      );
      expect(ModuleSetup.fromJson(<String, dynamic>{}), isNull);
    });

    test('satisfiedBy gates on required fields only', () {
      final ModuleSetup setup = ModuleSetup.fromJson(<String, dynamic>{
        'fields': <dynamic>[
          <String, dynamic>{'key': 'user', 'required': true},
          <String, dynamic>{'key': 'note'},
          <String, dynamic>{
            'key': 'retries',
            'type': 'number',
            'required': true,
          },
          <String, dynamic>{'key': 'verbose', 'type': 'boolean'},
        ],
      })!;
      expect(setup.satisfiedBy(null), isFalse);
      expect(setup.satisfiedBy(<String, dynamic>{}), isFalse);
      expect(
        setup.satisfiedBy(<String, dynamic>{'user': 'a'}),
        isFalse,
      ); // required number missing
      expect(
        setup.satisfiedBy(<String, dynamic>{'user': '  ', 'retries': 3}),
        isFalse,
      ); // blank text
      expect(
        setup.satisfiedBy(<String, dynamic>{'user': 'a', 'retries': 'x'}),
        isFalse,
      ); // wrong type
      expect(
        setup.satisfiedBy(<String, dynamic>{
          'user': 'a',
          'retries': 3,
          'verbose': false,
        }),
        isTrue,
      ); // boolean false counts as filled
      expect(
        setup.satisfiedBy(<String, dynamic>{'user': 'a', 'retries': 2.5}),
        isTrue,
      );
    });

    test('no required fields means never blocked', () {
      final ModuleSetup setup = ModuleSetup.fromJson(<String, dynamic>{
        'fields': <dynamic>[
          <String, dynamic>{'key': 'note'},
        ],
      })!;
      expect(setup.hasRequired, isFalse);
      expect(setup.satisfiedBy(null), isTrue);
    });

    test('manifest round-trips the setup block through toJson', () {
      final ModuleManifest manifest = ModuleManifest.fromJson(<String, dynamic>{
        'name': 'demo',
        'setup': <String, dynamic>{
          'title': 'Acct',
          'fields': <dynamic>[
            <String, dynamic>{'key': 'email', 'required': true},
            <String, dynamic>{
              'key': 'pass',
              'type': 'password',
              'required': true,
            },
          ],
        },
      });
      expect(manifest.setup, isNotNull);
      expect(manifest.setup!.fields, hasLength(2));
      final ModuleManifest restored = ModuleManifest.fromJson(
        manifest.toJson(),
      );
      expect(restored.setup, isNotNull);
      expect(restored.setup!.title, 'Acct');
      expect(restored.setup!.fields.map((f) => f.key), <String>[
        'email',
        'pass',
      ]);
      expect(restored.setup!.fields.every((f) => f.required), isTrue);
    });

    test('ChatModule persistence keeps the setup block', () async {
      final File zip = File('${tempDir.path}${Platform.pathSeparator}setup.zip')
        ..writeAsBytesSync(
          textZip(<String, String>{
            'module.json':
                '{"name":"setupmod","setup":{"title":"Acct","fields":['
                '{"key":"email","type":"text","required":true},'
                '{"key":"pass","type":"password","required":true}]}}',
            'main.js': 'module.exports = 1;',
          }),
        );
      final ModuleInstallResult result = await registry.installFromZip(
        zip.path,
      );
      expect(result.ok, isTrue, reason: result.message);
      final List<ChatModule> installed = await registry.listInstalled();
      expect(installed.single.manifest.setup, isNotNull);
      expect(installed.single.manifest.setup!.fields, hasLength(2));
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
