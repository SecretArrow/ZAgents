import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:zagents/services/module_registry.dart';
import 'package:zagents/ui/screens/modules_screen.dart';

/// Guard for the module development kit that lives in the repository:
///
/// * `sdk/`       — official SDK shim, TypeScript definitions, package metadata
/// * `samples/`   — complete, installable example modules
/// * `docs/modules/` — official SDK reference (EN + ID), shipped in-app
///
/// These directories are developer-facing AND partially bundled into the
/// app as assets (pubspec.yaml). This suite fails when any piece goes
/// missing, drifts out of the app bundle, or ships a broken sample —
/// so the folders can never silently disappear again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sdk/ — official SDK package', () {
    test('shim is bundled as an app asset (pubspec wiring intact)', () async {
      final String source = await rootBundle.loadString('sdk/zagents-sdk.js');
      expect(source, contains('module.exports = zagents'));
      expect(source, contains("require('zagents-sdk')"));
    });

    test('package.json points at the real files', () async {
      // package.json is developer metadata, NOT an app asset — read it
      // from disk; only the shim and the docs ride inside the APK.
      final Map<String, dynamic> json = jsonDecode(
        await File('sdk/package.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(json['name'], 'zagents-sdk');
      expect(json['main'], 'zagents-sdk.js');
      expect(json['types'], 'index.d.ts');
      expect(
        File('sdk/zagents-sdk.js').existsSync(),
        isTrue,
        reason: 'sdk/package.json main file must exist',
      );
      expect(
        File('sdk/index.d.ts').existsSync(),
        isTrue,
        reason: 'sdk/package.json types file must exist',
      );
    });

    test(
      'TypeScript definitions cover the full documented API surface',
      () async {
        final String dts = await File('sdk/index.d.ts').readAsString();
        expect(dts, contains('interface ZAgentsSdk'));
        // Every capability from the reference docs is typed.
        for (final String member in <String>[
          'info',
          'log',
          'chat',
          'http',
          'storage',
          'fs',
          'agent',
        ]) {
          expect(dts, contains(member), reason: 'missing SDK member: $member');
        }
        for (final String method in <String>[
          'emit',
          'request',
          'set',
          'get',
          'keys',
          'remove',
          'readFile',
          'writeFile',
          'appendFile',
          'readdir',
          'mkdir',
          'unlink',
          'stat',
          'compose',
        ]) {
          expect(
            dts,
            contains(method),
            reason: 'missing SDK method in typings: $method',
          );
        }
      },
    );

    test('README links the other development-kit folders', () async {
      final String readme = await File('sdk/README.md').readAsString();
      expect(readme, contains('docs/modules/sdk-reference-en.md'));
      expect(readme, contains('samples/'));
    });
  });

  group('docs/modules/ — official reference (EN + ID)', () {
    for (final String asset in <String>[
      SdkDocsScreen.docAssetEn,
      SdkDocsScreen.docAssetId,
    ]) {
      test('$asset is bundled and complete', () async {
        final String doc = await rootBundle.loadString(asset);
        expect(doc, isNotEmpty);
        // The in-app viewer and the repo doc share one source; keep the
        // documented API sections in place.
        for (final String section in <String>[
          'zagents.storage',
          'zagents.fs',
          'zagents.http',
          'zagents.chat',
          'zagents.agent',
          'agent.compose',
          'allowedHosts',
          'module.json',
          'appendFile',
          'samples/',
          'sdk/',
          'onhomeroom-daily',
        ]) {
          expect(
            doc,
            contains(section),
            reason: '$asset is missing section: $section',
          );
        }
      });
    }

    test('reference README indexes both languages', () async {
      final String readme = await File('docs/modules/README.md').readAsString();
      expect(readme, contains('sdk-reference-en.md'));
      expect(readme, contains('sdk-reference-id.md'));
    });
  });

  group('samples/ — installable example modules', () {
    final Directory samplesDir = Directory('samples');
    final List<String> sampleNames =
        samplesDir
            .listSync()
            .whereType<Directory>()
            .map(
              (Directory d) => d.uri.pathSegments.reversed
                  .skip(1)
                  .firstWhere((String s) => s.isNotEmpty),
            )
            .toList()
          ..sort();

    test('all five permission-covering samples are present', () {
      expect(
        sampleNames,
        containsAll(<String>[
          'counter',
          'network-fetcher',
          'file-notes',
          'chat-streamer',
          'onhomeroom-daily',
        ]),
      );
    });

    for (final String sample in sampleNames) {
      test('sample "$sample" is a valid, installable module', () async {
        final File manifestFile = File('samples/$sample/module.json');
        expect(
          manifestFile.existsSync(),
          isTrue,
          reason: 'samples/$sample must ship module.json',
        );
        final Map<String, dynamic> manifest = jsonDecode(
          await manifestFile.readAsString(),
        ) as Map<String, dynamic>;

        // Name is canonical (already sanitized) and stable.
        final String name = manifest['name'] as String;
        expect(
          name,
          ModuleManifest.sanitizeName(name),
          reason: 'manifest name must already be canonical',
        );
        expect(name.length, lessThanOrEqualTo(ModuleManifest.maxNameLength));
        expect(
          (manifest['version'] as String? ?? '').isNotEmpty,
          isTrue,
          reason: 'samples must declare a version',
        );

        // Entry point exists inside the sample.
        final String entry = manifest['entry'] as String? ?? 'main.js';
        expect(
          File('samples/$sample/$entry').existsSync(),
          isTrue,
          reason: 'samples/$sample entry "$entry" must exist',
        );

        // Permissions are real (unknown names would be silently dropped
        // by the runtime — a sample must never rely on that).
        final Object? permissions = manifest['permissions'];
        expect(permissions, isA<List<dynamic>>());
        for (final Object? permission in permissions! as List<dynamic>) {
          expect(
            modulePermissionFromName(permission.toString()),
            isNotNull,
            reason:
                'sample "$sample" requests unknown permission '
                '"$permission"',
          );
        }

        // Network samples must declare their allowlist.
        if ((permissions as List<dynamic>).contains('network')) {
          expect(
            (manifest['allowedHosts'] as List<dynamic>? ?? const <dynamic>[])
                .isNotEmpty,
            isTrue,
            reason: 'network sample "$sample" must declare allowedHosts',
          );
        }

        // Every sample documents itself.
        expect(
          File('samples/$sample/README.md').existsSync(),
          isTrue,
          reason: 'samples/$sample must ship a README',
        );
      });
    }

    test('samples README explains packaging + install', () async {
      final String readme = await File('samples/README.md').readAsString();
      expect(readme, contains('zip'));
      expect(readme, contains('/plugins'));
      expect(readme, contains('Install module'));
    });
  });
}
