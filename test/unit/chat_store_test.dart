import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/chat_store.dart';

/// Writes a session file the way ChatStore.save would (plus raw variants
/// for corrupted-file coverage).
Future<void> _writeSession(
  Directory base,
  String id, {
  required String title,
  required List<Map<String, dynamic>> messages,
  String? rawUpdated,
}) async {
  final Directory dir = Directory('${base.path}/chats');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  await File('${dir.path}/$id.json').writeAsString(
    jsonEncode(<String, dynamic>{
      'id': id,
      'title': title,
      'updatedAt': rawUpdated ?? '2025-03-01T10:00:00.000',
      'messages': messages,
    }),
  );
}

Map<String, dynamic> _userJson(String content) =>
    ChatMessage.user(content).toJson();

Map<String, dynamic> _assistantJson(String content) =>
    ChatMessage.assistant(content).toJson();

void main() {
  late Directory tempDir;
  late ChatStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_chat_store');
    store = ChatStore(resolveBaseDir: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('searchAll (v1.15.0)', () {
    setUp(() async {
      await _writeSession(
        tempDir,
        's1',
        title: 'Resep kue cokelat',
        messages: <Map<String, dynamic>>[
          _userJson('Bagaimana cara membuat kue cokelat yang lembut?'),
          _assistantJson('Campur adonan, lalu panggang 30 menit.'),
        ],
      );
      await _writeSession(
        tempDir,
        's2',
        title: 'Jadwal kereta api',
        messages: <Map<String, dynamic>>[
          _userJson('Kapan jadwal KERETA terbaru keluar?'),
          _assistantJson('Besok pagi.'),
        ],
      );
      await _writeSession(
        tempDir,
        's3',
        title: 'Catatan rapat',
        messages: <Map<String, dynamic>>[
          _userJson('Tidak ada yang relevan di sini.'),
        ],
      );
      // Corrupted file: must be skipped without breaking the search.
      final Directory dir = Directory('${tempDir.path}/chats');
      await File('${dir.path}/bad.json').writeAsString('{not json!!');
    });

    test('title match keeps the session metadata, no role', () async {
      // 'resep' appears ONLY in s1's title.
      final List<ChatSearchHit> hits = await store.searchAll('resep');
      expect(hits, hasLength(1));
      expect(hits.single.sessionId, 's1');
      expect(hits.single.title, 'Resep kue cokelat');
      expect(hits.single.role, isNull, reason: 'title hits carry no role');
      expect(hits.single.snippet, isNotEmpty);
    });

    test('content match returns a snippet around the first hit', () async {
      // 'kapan' appears ONLY in s2's message content (title is different).
      final List<ChatSearchHit> hits = await store.searchAll('kapan');
      expect(hits, hasLength(1));
      expect(hits.single.sessionId, 's2');
      expect(hits.single.role, Role.user);
      expect(hits.single.snippet.toLowerCase(), contains('kapan'));
      // ~120 chars around the match, not the whole world.
      expect(hits.single.snippet.length, lessThan(140));
    });

    test('matching is case-insensitive in both directions', () async {
      // Query uppercase, content lowercase.
      final List<ChatSearchHit> upper = await store.searchAll('TERBARU KELUAR');
      expect(upper.single.sessionId, 's2');
      // Query lowercase, content uppercase.
      final List<ChatSearchHit> lower = await store.searchAll('panggang');
      expect(lower.single.sessionId, 's1');
    });

    test('no match returns an empty list; blank query too', () async {
      expect(await store.searchAll('quantum-flux-nonsense'), isEmpty);
      expect(await store.searchAll('   '), isEmpty);
    });

    test('corrupted files are skipped, not thrown', () async {
      final List<ChatSearchHit> hits = await store.searchAll('rapat');
      expect(hits, hasLength(1));
      expect(hits.single.sessionId, 's3');
    });

    test('title matches sort before content matches', () async {
      // Session A matches by TITLE, session B only by message content —
      // the same query 'zebra' must list the title hit first.
      await _writeSession(
        tempDir,
        'sA',
        title: 'Zebra spesial ulang tahun',
        messages: <Map<String, dynamic>>[_userJson('tolong dibantu')],
      );
      await _writeSession(
        tempDir,
        'sB',
        title: 'Pembahasan arsitektur',
        messages: <Map<String, dynamic>>[_userJson('hewan zebra apa terbaik?')],
      );
      final List<ChatSearchHit> hits = await store.searchAll('zebra');
      expect(hits, hasLength(2));
      expect(hits.first.sessionId, 'sA', reason: 'title hit ranks first');
      expect(hits.last.sessionId, 'sB');
      expect(hits.last.role, Role.user);
    });

    test('limit caps the result count', () async {
      await _writeSession(
        tempDir,
        'sA',
        title: 'Zebra spesial ulang tahun',
        messages: <Map<String, dynamic>>[_userJson('tolong dibantu')],
      );
      await _writeSession(
        tempDir,
        'sB',
        title: 'Pembahasan arsitektur',
        messages: <Map<String, dynamic>>[_userJson('hewan zebra apa terbaik?')],
      );
      final List<ChatSearchHit> hits = await store.searchAll('zebra', limit: 1);
      expect(hits, hasLength(1));
      expect(hits.single.sessionId, 'sA');
    });

    test('a session yields at most two hits (title + first message)', () async {
      await _writeSession(
        tempDir,
        's4',
        title: 'berulang berulang',
        messages: <Map<String, dynamic>>[
          _userJson('berulang satu'),
          _userJson('berulang dua'),
        ],
      );
      final List<ChatSearchHit> hits = await store.searchAll('berulang');
      expect(hits, hasLength(2));
      expect(
        hits.where((h) => h.sessionId == 's4'),
        hasLength(2),
        reason: 'one title hit + one (first) message hit',
      );
    });
  });

  group('isolate offload (v1.28.0 ANR hardening)', () {
    test(
      'a multi-megabyte session roundtrips through save/load/list',
      () async {
        // ~1.5 MB of message text: the JSON decode/encode of this payload
        // runs inside Isolate.run — the test doubles as a correctness check
        // for the isolate boundary (all data must survive the hop).
        final List<ChatMessage> big = <ChatMessage>[
          for (var i = 0; i < 400; i++)
            ChatMessage.assistant(
              'baris $i — ${'lorem ipsum dolor sit amet ' * 120}',
            ),
        ];
        await store.save(id: 'big-1', title: 'besar', messages: big);

        final List<ChatMessage>? loaded = await store.load('big-1');
        expect(loaded, hasLength(400));
        expect(loaded!.last.content, contains('baris 399'));

        final List<ChatSummary> summaries = await store.listSummaries();
        expect(summaries.single.id, 'big-1');

        final List<ChatSearchHit> hits = await store.searchAll('baris 399');
        expect(hits, isNotEmpty);
        expect(hits.first.sessionId, 'big-1');
      },
    );

    test('listSummaries skips corrupted files in big folders', () async {
      await _writeSession(
        tempDir,
        'ok-1',
        title: 'sehat',
        messages: [_userJson('halo')],
      );
      final Directory dir = Directory('${tempDir.path}/chats');
      await File('${dir.path}/broken.json').writeAsString('{not json');

      final List<ChatSummary> summaries = await store.listSummaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.title, 'sehat');
    });
  });

  group('waiting-for-setup flag (v1.29.0)', () {
    test(
      'save persists the flag and loadWaitingForSetup reads it back',
      () async {
        await store.save(
          id: 'waiting-1',
          title: 't',
          messages: [ChatMessage.user('queued')],
          waitingForSetup: true,
        );
        expect(await store.loadWaitingForSetup('waiting-1'), isTrue);
        // Default is false when the flag is omitted.
        await store.save(
          id: 'waiting-2',
          title: 't',
          messages: [ChatMessage.user('normal')],
        );
        expect(await store.loadWaitingForSetup('waiting-2'), isFalse);
      },
    );

    test(
      'loadWaitingForSetup defaults to false for unknown/corrupt ids',
      () async {
        expect(await store.loadWaitingForSetup('missing'), isFalse);
        final Directory dir = Directory('${tempDir.path}/chats');
        await File('${dir.path}/broken.json').writeAsString('{not json');
        expect(await store.loadWaitingForSetup('broken'), isFalse);
      },
    );
  });
}
