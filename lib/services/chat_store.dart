import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

/// Persists chat sessions as JSON files under `<documents>/chats/`.
class ChatStore {
  ChatStore({required this.resolveBaseDir});

  final Future<Directory> Function() resolveBaseDir;

  Future<Directory> _chatsDir() async {
    final base = await resolveBaseDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}chats');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<List<ChatSummary>> listSummaries() async {
    final dir = await _chatsDir();
    final out = <ChatSummary>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        out.add(
          ChatSummary(
            id: data['id'] as String,
            title: (data['title'] as String?) ?? 'Untitled',
            updatedAt:
                DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      } catch (_) {
        // Skip corrupted files.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> save({
    required String id,
    required String title,
    required List<ChatMessage> messages,
  }) async {
    final dir = await _chatsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'id': id,
        'title': title,
        'updatedAt': DateTime.now().toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      }),
    );
  }

  Future<List<ChatMessage>?> load(String id) async {
    final dir = await _chatsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    if (!await file.exists()) return null;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rawMessages = data['messages'];
      if (rawMessages is! List) return null;
      return <ChatMessage>[
        for (final raw in rawMessages)
          if (raw is Map<String, dynamic>) ChatMessage.fromJson(raw),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String id) async {
    final dir = await _chatsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    if (await file.exists()) await file.delete();
  }
}
