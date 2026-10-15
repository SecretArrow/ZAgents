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

  /// Updates the stored title of a session (keeps messages untouched).
  Future<void> rename(String id, String title) async {
    final dir = await _chatsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map<String, dynamic>) {
        data['title'] = title;
        await file.writeAsString(jsonEncode(data));
      }
    } catch (_) {
      // Corrupted file: renaming must never crash the caller.
    }
  }

  /// Global search across every stored conversation. A session matches
  /// when its title or any message content contains [query]
  /// case-insensitively; each session yields at most two hits (the title
  /// hit + the first matching message). Title matches rank first, newest
  /// conversations first within each group. Corrupted files are skipped.
  Future<List<ChatSearchHit>> searchAll(String query, {int limit = 50}) async {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty || limit <= 0) return const <ChatSearchHit>[];
    final Directory dir = await _chatsDir();
    final List<(ChatSearchHit, bool)> ranked = <(ChatSearchHit, bool)>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final String id = data['id'] as String? ?? '';
        if (id.isEmpty) continue;
        final String title = (data['title'] as String?) ?? 'Untitled';
        final DateTime updatedAt =
            DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bool titleMatch = title.toLowerCase().contains(q);
        if (titleMatch) {
          ranked.add((
            ChatSearchHit(
              sessionId: id,
              title: title,
              snippet: _previewOf(data['messages'], fallback: title),
              role: null,
              createdAt: updatedAt,
            ),
            true,
          ));
        }
        // First matching message of the session (one hit per conversation
        // keeps the result list diverse).
        final Object? rawMessages = data['messages'];
        if (rawMessages is List) {
          for (final raw in rawMessages) {
            if (raw is! Map<String, dynamic>) continue;
            final String content = raw['content']?.toString() ?? '';
            if (!content.toLowerCase().contains(q)) continue;
            Role? role;
            for (final Role r in Role.values) {
              if (r.name == raw['role']) {
                role = r;
                break;
              }
            }
            ranked.add((
              ChatSearchHit(
                sessionId: id,
                title: title,
                snippet: _snippetFor(content, q),
                role: role,
                createdAt:
                    DateTime.tryParse(raw['createdAt']?.toString() ?? '') ??
                    updatedAt,
              ),
              false,
            ));
            break;
          }
        }
      } catch (_) {
        // Skip corrupted files.
      }
    }
    ranked.sort((a, b) {
      if (a.$2 != b.$2) return a.$2 ? -1 : 1; // title matches first
      return b.$1.createdAt.compareTo(a.$1.createdAt); // then newest
    });
    return <ChatSearchHit>[
      for (final (ChatSearchHit, bool) entry in ranked.take(limit)) entry.$1,
    ];
  }

  /// Short preview used for title-only hits: the first non-empty message
  /// content, truncated; falls back to [fallback] when none exists.
  static String _previewOf(Object? rawMessages, {required String fallback}) {
    if (rawMessages is List) {
      for (final raw in rawMessages) {
        if (raw is! Map<String, dynamic>) continue;
        final String content = raw['content']?.toString() ?? '';
        final String trimmed = content.trim();
        if (trimmed.isEmpty) continue;
        return trimmed.length <= 120
            ? trimmed
            : '${trimmed.substring(0, 120)}…';
      }
    }
    return fallback;
  }

  /// Up to ~120 characters of [content] around the first (case-insensitive)
  /// occurrence of [query], always keeping the matched substring intact.
  static String _snippetFor(String content, String query) {
    final int index = content.toLowerCase().indexOf(query);
    if (index < 0) {
      // Defensive: the caller already verified a match — this only guards
      // against case-mapping edge cases.
      return content.length <= 120 ? content : '${content.substring(0, 120)}…';
    }
    int start = index - 40;
    if (start < 0) start = 0;
    int end = index + query.length + 80;
    if (end > content.length) end = content.length;
    final String prefix = start > 0 ? '…' : '';
    final String suffix = end < content.length ? '…' : '';
    return '$prefix${content.substring(start, end).trim()}$suffix';
  }
}
