import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zagents/services/local_ai/model_catalog_data.dart';
import 'package:zagents/services/local_ai/remote_catalog.dart';

String _payload({
  Object? version = 1,
  List<Map<String, Object?>> models = const <Map<String, Object>>[],
}) => jsonEncode(<String, Object?>{'version': version, 'models': models});

Map<String, Object?> _model(
  String ref, {
  int download = 548405248,
  int ram = 1073741824,
  int ctx = 40960,
  String tier = 'tier1',
  String license = 'Apache-2.0',
}) => <String, Object?>{
  'ollamaRef': ref,
  'downloadBytes': download,
  'ramEstBytes': ram,
  'contextTokens': ctx,
  'tier': tier,
  'license': license,
};

void main() {
  group('RemoteCatalogEntry', () {
    test('tolerant fromJson degrades missing fields to defaults', () {
      final RemoteCatalogEntry entry = RemoteCatalogEntry.fromJson(
        <String, dynamic>{'ollamaRef': 'x:1b'},
      );
      expect(entry.ollamaRef, 'x:1b');
      expect(entry.downloadBytes, 0);
      expect(entry.ramEstBytes, 0);
      expect(entry.contextTokens, 0);
      expect(entry.tierName, 'tier2'); // default when absent
      expect(entry.license, '');
    });

    test('toEntry maps tier wire names; unknown → tier2', () {
      expect(
        RemoteCatalogEntry.fromJson(<String, dynamic>{
          'ollamaRef': 'a',
          'tier': 'tier1',
        }).toEntry().tier,
        CatalogTier.tier1,
      );
      expect(
        RemoteCatalogEntry.fromJson(<String, dynamic>{
          'ollamaRef': 'b',
          'tier': 'upperBound',
        }).toEntry().tier,
        CatalogTier.upperBound,
      );
      expect(
        RemoteCatalogEntry.fromJson(<String, dynamic>{
          'ollamaRef': 'c',
          'tier': 'tier2',
        }).toEntry().tier,
        CatalogTier.tier2,
      );
      expect(
        RemoteCatalogEntry.fromJson(<String, dynamic>{
          'ollamaRef': 'd',
          'tier': 'from-the-future',
        }).toEntry().tier,
        CatalogTier.tier2,
      );
    });
  });

  group('RemoteCatalogService.fetch', () {
    test('happy path: two models, one with an unknown tier', () async {
      final List<Uri> seen = <Uri>[];
      final RemoteCatalogService service = RemoteCatalogService(
        client: MockClient((http.Request request) async {
          seen.add(request.url);
          return http.Response(
            _payload(
              models: <Map<String, Object?>>[
                _model('qwen3:0.6b'),
                _model(
                  'new-model:1b',
                  download: 306184192,
                  ram: 751619276,
                  ctx: 32768,
                  tier: 'mystery', // unknown → tier2
                  license: 'MIT',
                ),
              ],
            ),
            200,
          );
        }),
      );

      final List<CatalogModelEntry> entries = await service.fetch(
        'https://example.com/catalog.json',
      );

      expect(seen.single.toString(), 'https://example.com/catalog.json');
      expect(entries, hasLength(2));
      expect(entries.first.ollamaRef, 'qwen3:0.6b');
      expect(entries.first.downloadBytes, 548405248);
      expect(entries.last.ollamaRef, 'new-model:1b');
      expect(entries.last.tier, CatalogTier.tier2);
      expect(entries.last.license, 'MIT');
    });

    test('404 → RemoteCatalogException', () async {
      final RemoteCatalogService service = RemoteCatalogService(
        client: MockClient(
          (http.Request request) async => http.Response('nope', 404),
        ),
      );

      await expectLater(
        service.fetch(kRemoteCatalogUrl),
        throwsA(
          isA<RemoteCatalogException>().having(
            (RemoteCatalogException e) => e.message,
            'message',
            'HTTP 404',
          ),
        ),
      );
    });

    test('corrupt JSON → RemoteCatalogException', () async {
      final RemoteCatalogService service = RemoteCatalogService(
        client: MockClient(
          (http.Request request) async => http.Response('{not json', 200),
        ),
      );

      await expectLater(
        service.fetch(kRemoteCatalogUrl),
        throwsA(
          isA<RemoteCatalogException>().having(
            (RemoteCatalogException e) => e.message,
            'message',
            contains('invalid catalog JSON'),
          ),
        ),
      );
    });

    test('empty models list → RemoteCatalogException', () async {
      final RemoteCatalogService service = RemoteCatalogService(
        client: MockClient(
          (http.Request request) async => http.Response(
            _payload(models: const <Map<String, Object>>[]),
            200,
          ),
        ),
      );

      await expectLater(
        service.fetch(kRemoteCatalogUrl),
        throwsA(
          isA<RemoteCatalogException>().having(
            (RemoteCatalogException e) => e.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });

    test('unsupported version → RemoteCatalogException', () async {
      final RemoteCatalogService service = RemoteCatalogService(
        client: MockClient((http.Request request) async {
          return http.Response(
            _payload(version: 2, models: <Map<String, Object?>>[_model('x')]),
            200,
          );
        }),
      );

      await expectLater(
        service.fetch(kRemoteCatalogUrl),
        throwsA(
          isA<RemoteCatalogException>().having(
            (RemoteCatalogException e) => e.message,
            'message',
            contains('unsupported catalog version'),
          ),
        ),
      );
    });

    test('ref-less and junk rows are skipped', () async {
      final RemoteCatalogService service = RemoteCatalogService(
        client: MockClient((http.Request request) async {
          return http.Response(
            _payload(
              models: <Map<String, Object?>>[
                _model(''), // empty ref → useless row
                _model('ok:1b'),
                <String, Object?>{'junk': true}, // no ollamaRef → dropped too
              ],
            ),
            200,
          );
        }),
      );

      final List<CatalogModelEntry> entries = await service.fetch(
        kRemoteCatalogUrl,
      );
      expect(entries, hasLength(1));
      expect(entries.single.ollamaRef, 'ok:1b');
    });

    test('network error → RemoteCatalogException', () async {
      final RemoteCatalogService service = RemoteCatalogService(
        client: MockClient((http.Request request) async {
          throw Exception('offline');
        }),
      );

      await expectLater(
        service.fetch(kRemoteCatalogUrl),
        throwsA(isA<RemoteCatalogException>()),
      );
    });
  });

  group('assets/local_ai_catalog.json (the remote source of truth)', () {
    test('parses and mirrors the built-in catalog values', () async {
      final String raw = await File('assets/local_ai_catalog.json')
          .readAsString();
      final RemoteCatalogService service = RemoteCatalogService(
        client: MockClient(
          (http.Request request) async => http.Response(raw, 200),
        ),
      );

      final List<CatalogModelEntry> entries = await service.fetch(
        kRemoteCatalogUrl,
      );
      expect(entries, hasLength(kLocalAiCatalog.length));

      // Same refs in the same order, same numbers per field.
      for (int i = 0; i < entries.length; i++) {
        final CatalogModelEntry asset = entries[i];
        final CatalogModelEntry builtin = kLocalAiCatalog[i];
        expect(asset.ollamaRef, builtin.ollamaRef, reason: 'index $i');
        expect(
          asset.downloadBytes,
          builtin.downloadBytes,
          reason: builtin.ollamaRef,
        );
        expect(
          asset.ramEstBytes,
          builtin.ramEstBytes,
          reason: builtin.ollamaRef,
        );
        expect(
          asset.contextTokens,
          builtin.contextTokens,
          reason: builtin.ollamaRef,
        );
        expect(asset.tier, builtin.tier, reason: builtin.ollamaRef);
        expect(asset.license, builtin.license, reason: builtin.ollamaRef);
      }
    });
  });
}
