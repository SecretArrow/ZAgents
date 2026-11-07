import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zagents/di.dart';
import 'package:zagents/models/local_model.dart';
import 'package:zagents/services/local_ai/model_downloader.dart';
import 'package:zagents/services/local_ai/ollama_registry_client.dart';

const String _fullBody = '0123456789';
final List<int> _fullBytes = utf8.encode(_fullBody);
final String _fullSha = sha256.convert(_fullBytes).toString();
final String _wrongSha = sha256.convert(utf8.encode('XXXXXXXXXX')).toString();

LocalModelEntry _customEntry(String id, {String sha = ''}) => LocalModelEntry(
  id: id,
  name: 'Model $id',
  source: LocalModelSource.customUrl,
  customUrl: 'https://example.test/$id.gguf',
  fileName: '$id.gguf',
  sha256: sha,
  addedAtMs: 0,
);

/// Polls [condition] until true; fails the test after 5 s.
Future<void> _until(FutureOr<bool> Function() condition, String what) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// One booted download queue bound to a mock transport and a temp dir.
class _Boot {
  _Boot(this.container, this.controller);

  final ProviderContainer container;
  final DownloadQueueController controller;

  static _Boot create(
    http.Client client, {
    required Directory modelsDir,
    http.Client? registryClient,
    void Function(LocalModelEntry)? onCompleted,
  }) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        downloadQueueProvider.overrideWith(
          () =>
              DownloadQueueController(httpClient: client, modelsDir: modelsDir),
        ),
        if (registryClient != null)
          ollamaRegistryClientProvider.overrideWithValue(
            OllamaRegistryClient(client: registryClient),
          ),
      ],
    );
    addTearDown(container.dispose);
    final DownloadQueueController controller = container.read(
      downloadQueueProvider.notifier,
    );
    controller.onCompleted = onCompleted ?? (LocalModelEntry entry) {};
    return _Boot(container, controller);
  }

  DownloadProgress? rowOf(String modelId) {
    for (final DownloadProgress row in container.read(downloadQueueProvider)) {
      if (row.modelId == modelId) return row;
    }
    return null;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents-localai-');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {
      // Already removed by the test itself.
    }
  });

  String p(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  test(
    'custom URL: verifies sha256, renames .part, reports completion',
    () async {
      final List<LocalModelEntry> completed = <LocalModelEntry>[];
      final _Boot boot = _Boot.create(
        MockClient.streaming(
          (http.BaseRequest request, http.ByteStream body) async =>
              http.StreamedResponse(
                Stream<List<int>>.value(_fullBytes),
                200,
                contentLength: _fullBytes.length,
              ),
        ),
        modelsDir: tempDir,
        onCompleted: completed.add,
      );

      await boot.controller.enqueue(_customEntry('ok1', sha: _fullSha));

      await _until(
        () => boot.rowOf('ok1')?.status == DownloadStatus.completed,
        'completion',
      );

      final File file = File(p('ok1.gguf'));
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), _fullBody);
      expect(await File('${file.path}.part').exists(), isFalse);
      final DownloadProgress row = boot.rowOf('ok1')!;
      expect(row.receivedBytes, 10);
      expect(row.totalBytes, 10);
      // '' = explicitly cleared (copyWith cannot reset to null) — the UI
    // treats null and '' identically via (error ?? '').
    expect(row.error ?? '', isEmpty);
      expect(completed, hasLength(1));
      expect(completed.single.sizeBytes, 10);
      expect(completed.single.sha256, _fullSha);
      expect(await boot.controller.modelsDirPath(), tempDir.path);
    },
  );

  test('sha256 mismatch fails the row and deletes the .part file', () async {
    final List<LocalModelEntry> completed = <LocalModelEntry>[];
    final _Boot boot = _Boot.create(
      MockClient.streaming(
        (http.BaseRequest request, http.ByteStream body) async =>
            http.StreamedResponse(
              Stream<List<int>>.value(_fullBytes),
              200,
              contentLength: _fullBytes.length,
            ),
      ),
      modelsDir: tempDir,
      onCompleted: completed.add,
    );

    await boot.controller.enqueue(_customEntry('bad1', sha: _wrongSha));

    await _until(
      () => boot.rowOf('bad1')?.status == DownloadStatus.failed,
      'sha failure',
    );

    expect(boot.rowOf('bad1')!.error, contains('sha256 mismatch'));
    expect(await File(p('bad1.gguf.part')).exists(), isFalse);
    expect(await File(p('bad1.gguf')).exists(), isFalse);
    expect(completed, isEmpty);
  });

  test(
    'pause keeps the .part; resume with HTTP 206 appends the remainder',
    () async {
      final StreamController<List<int>> firstBody =
          StreamController<List<int>>();
      final List<http.BaseRequest> requests = <http.BaseRequest>[];
      final _Boot boot = _Boot.create(
        MockClient.streaming((
          http.BaseRequest request,
          http.ByteStream body,
        ) async {
          requests.add(request);
          if (request.headers['range'] == 'bytes=5-') {
            return http.StreamedResponse(
              Stream<List<int>>.value(utf8.encode('56789')),
              206,
              contentLength: 5,
            );
          }
          return http.StreamedResponse(
            firstBody.stream,
            200,
            contentLength: 10,
          );
        }),
        modelsDir: tempDir,
      );

      await boot.controller.enqueue(_customEntry('pause1', sha: _fullSha));
      await _until(() => requests.length == 1, 'first request');
      firstBody.add(utf8.encode('01234'));
      await _until(
        () => boot.rowOf('pause1')?.receivedBytes == 5,
        'first chunk persisted',
      );

      await boot.controller.pause('pause1');
      expect(boot.rowOf('pause1')!.status, DownloadStatus.paused);
      // The paused loop wakes on the next chunk, consumes the pause intent
      // and DISCARDS the chunk (it is never appended).
      firstBody.add(utf8.encode('56789'));
      await firstBody.close();

      await boot.controller.resume('pause1');
      await _until(
        () => boot.rowOf('pause1')?.status == DownloadStatus.completed,
        'resumed completion',
      );

      expect(requests, hasLength(2));
      expect(requests.last.headers['range'], 'bytes=5-');
      final File file = File(p('pause1.gguf'));
      expect(await file.readAsString(), _fullBody);
      expect(await File('${file.path}.part').exists(), isFalse);
    },
  );

  test(
    'resume against a server that ignores Range (HTTP 200) restarts',
    () async {
      final StreamController<List<int>> firstBody =
          StreamController<List<int>>();
      final List<http.BaseRequest> requests = <http.BaseRequest>[];
      final _Boot boot = _Boot.create(
        MockClient.streaming((
          http.BaseRequest request,
          http.ByteStream body,
        ) async {
          requests.add(request);
          if (request.headers['range'] != null) {
            // Range ignored: the whole body comes back with 200.
            return http.StreamedResponse(
              Stream<List<int>>.value(_fullBytes),
              200,
              contentLength: _fullBytes.length,
            );
          }
          return http.StreamedResponse(
            firstBody.stream,
            200,
            contentLength: 10,
          );
        }),
        modelsDir: tempDir,
      );

      await boot.controller.enqueue(_customEntry('restart1', sha: _fullSha));
      await _until(() => requests.length == 1, 'first request');
      firstBody.add(utf8.encode('01234'));
      await _until(
        () => boot.rowOf('restart1')?.receivedBytes == 5,
        'first chunk persisted',
      );

      await boot.controller.pause('restart1');
      firstBody.add(utf8.encode('56789')); // consumed as pause, discarded
      await firstBody.close();

      await boot.controller.resume('restart1');
      await _until(
        () => boot.rowOf('restart1')?.status == DownloadStatus.completed,
        'restart completion',
      );

      expect(requests.last.headers['range'], 'bytes=5-');
      // FULL content — the 5 stale bytes were truncated, not kept.
      expect(await File(p('restart1.gguf')).readAsString(), _fullBody);
    },
  );

  test('cancel marks the row canceled, deletes the .part and skips '
      'completion', () async {
    final List<LocalModelEntry> completed = <LocalModelEntry>[];
    final StreamController<List<int>> body = StreamController<List<int>>();
    final List<http.BaseRequest> requests = <http.BaseRequest>[];
    final _Boot boot = _Boot.create(
      MockClient.streaming((
        http.BaseRequest request,
        http.ByteStream bodyStream,
      ) async {
        requests.add(request);
        return http.StreamedResponse(body.stream, 200, contentLength: 10);
      }),
      modelsDir: tempDir,
      onCompleted: completed.add,
    );

    await boot.controller.enqueue(_customEntry('cancel1', sha: _fullSha));
    await _until(() => requests.length == 1, 'request');
    body.add(utf8.encode('01234'));
    await _until(
      () => boot.rowOf('cancel1')?.receivedBytes == 5,
      'chunk persisted',
    );

    await boot.controller.cancel('cancel1');
    expect(boot.rowOf('cancel1')!.status, DownloadStatus.canceled);
    expect(await File(p('cancel1.gguf.part')).exists(), isFalse);

    // The winding-down writer consumes the cancel intent and stays dead.
    body.add(utf8.encode('56789'));
    await body.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(boot.rowOf('cancel1')!.status, DownloadStatus.canceled);
    expect(completed, isEmpty);
    expect(await File(p('cancel1.gguf')).exists(), isFalse);

    boot.controller.clearFinished();
    expect(boot.container.read(downloadQueueProvider), isEmpty);
  });

  test('registry-sourced enqueue resolves the blob URL through the '
      'manifest', () async {
    final List<int> blobBytes = utf8.encode('registry-model-bytes');
    final String blobSha = sha256.convert(blobBytes).toString();
    final Map<String, Object?> manifest = <String, Object?>{
      'schemaVersion': 2,
      'config': <String, Object?>{
        'mediaType': 'application/vnd.docker.container.image.v1+json',
        'digest': 'sha256:deadbeef',
        'size': 100,
      },
      'layers': <Object?>[
        <String, Object?>{
          'mediaType': 'application/vnd.ollama.image.model',
          'digest': 'sha256:$blobSha',
          'size': blobBytes.length,
        },
      ],
    };
    final http.Client registryClient = MockClient(
      (http.Request request) async => http.Response(jsonEncode(manifest), 200),
    );
    final List<Uri> downloadUrls = <Uri>[];
    final _Boot boot = _Boot.create(
      MockClient.streaming((
        http.BaseRequest request,
        http.ByteStream body,
      ) async {
        downloadUrls.add(request.url);
        return http.StreamedResponse(
          Stream<List<int>>.value(blobBytes),
          200,
          contentLength: blobBytes.length,
        );
      }),
      modelsDir: tempDir,
      registryClient: registryClient,
      onCompleted: (LocalModelEntry entry) {},
    );

    await boot.controller.enqueue(
      LocalModelEntry(
        id: 'reg1',
        name: 'Qwen3 0.6B',
        source: LocalModelSource.catalog,
        ollamaRef: 'qwen3:0.6b',
        fileName: 'reg1.gguf',
        addedAtMs: 0,
      ),
    );

    await _until(
      () => boot.rowOf('reg1')?.status == DownloadStatus.completed,
      'registry download',
    );

    expect(
      downloadUrls.single.toString(),
      'https://registry.ollama.ai/v2/library/qwen3/blobs/sha256:$blobSha',
    );
    expect(boot.rowOf('reg1')!.totalBytes, blobBytes.length);
    expect(await File(p('reg1.gguf')).readAsString(), 'registry-model-bytes');
  });

  test(
    'a registry miss fails the row without touching the download client',
    () async {
      final http.Client registryClient = MockClient(
        (http.Request request) async => http.Response('not found', 404),
      );
      final _Boot boot = _Boot.create(
        MockClient.streaming(
          (http.BaseRequest request, http.ByteStream body) async =>
              fail('no blob download expected'),
        ),
        modelsDir: tempDir,
        registryClient: registryClient,
      );

      await boot.controller.enqueue(
        LocalModelEntry(
          id: 'regbad',
          name: 'Nope',
          source: LocalModelSource.catalog,
          ollamaRef: 'nope:9b',
          fileName: 'regbad.gguf',
          addedAtMs: 0,
        ),
      );

      await _until(
        () => boot.rowOf('regbad')?.status == DownloadStatus.failed,
        'registry failure',
      );
      expect(boot.rowOf('regbad')!.error, contains('not found'));
    },
  );

  test('an entry without source fails fast', () async {
    final _Boot boot = _Boot.create(
      MockClient.streaming(
        (http.BaseRequest request, http.ByteStream body) async =>
            fail('no request expected'),
      ),
      modelsDir: tempDir,
    );

    await boot.controller.enqueue(
      LocalModelEntry(
        id: 'noSrc',
        name: 'Nothing',
        fileName: 'noSrc.gguf',
        addedAtMs: 0,
      ),
    );

    expect(boot.rowOf('noSrc')?.status, DownloadStatus.failed);
    expect(boot.rowOf('noSrc')!.error, contains('no download source'));
  });
}
