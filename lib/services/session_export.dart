import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'chat_store.dart';

const Uuid _uuid = Uuid();

/// Exports all chat sessions to a portable JSON file and imports them back.
///
/// Export format:
/// ```json
/// { "app": "ZAgents", "format": 1, "exportedAt": "...",
///   "sessions": [ { "id","title","updatedAt","messages":[…] } ] }
/// ```
class SessionExporter {
  SessionExporter({required this.store, required this.resolveBaseDir});

  final ChatStore store;
  final Future<Directory> Function() resolveBaseDir;

  /// Writes every stored session into
  /// `<docs>/exports/zagents-sessions-<timestamp>.json` and returns the file.
  Future<File> exportAll() async {
    final List<ChatSummary> summaries = await store.listSummaries();
    final List<Map<String, dynamic>> sessions = <Map<String, dynamic>>[];
    for (final ChatSummary summary in summaries) {
      final List<ChatMessage>? messages = await store.load(summary.id);
      if (messages == null) continue; // Corrupted entry: skip silently.
      sessions.add(<String, dynamic>{
        'id': summary.id,
        'title': summary.title,
        'updatedAt': summary.updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      });
    }
    final Directory base = await resolveBaseDir();
    final Directory exportsDir = Directory(
      '${base.path}${Platform.pathSeparator}exports',
    );
    if (!exportsDir.existsSync()) exportsDir.createSync(recursive: true);
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final File file = File(
      '${exportsDir.path}${Platform.pathSeparator}zagents-sessions-$stamp.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'app': 'ZAgents',
        'format': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'sessions': sessions,
      }),
    );
    return file;
  }

  /// Parses a previously exported (or hand-edited) JSON file and stores
  /// every session under a NEW id (imports never overwrite existing chats).
  /// Returns the number of imported sessions.
  Future<int> importFrom(String filePath) async {
    final String raw = await File(filePath).readAsString();
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['sessions'] is! List) {
      throw const FormatException('Not a ZAgents sessions export file');
    }
    var imported = 0;
    for (final Object? rawSession in decoded['sessions'] as List<Object?>) {
      if (rawSession is! Map) continue;
      final Object? rawMessages = rawSession['messages'];
      if (rawMessages is! List) continue;
      final List<ChatMessage> messages = <ChatMessage>[
        for (final Object? m in rawMessages)
          if (m is Map<String, dynamic>) ChatMessage.fromJson(m),
      ];
      final String title = rawSession['title']?.toString() ?? 'Imported';
      await store.save(id: _uuid.v4(), title: title, messages: messages);
      imported++;
    }
    return imported;
  }
}
