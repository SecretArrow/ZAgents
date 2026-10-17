import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../models/models.dart';

/// Persists chat sessions as JSON files under `<documents>/chats/`.
///
/// ANR hardening (v1.28.0): every JSON decode/encode of chat payloads runs
/// inside [Isolate.run] — conversation files grow into the megabytes, and
/// `jsonDecode` of several megabytes on the MAIN isolate freezes the UI
/// long enough to trigger Android's "app isn't responding" dialog. File
/// bytes stay plain primitives so they cross the isolate boundary safely.
class ChatStore {
  ChatStore({required this.resolveBaseDir, this.offloadIsolate = true});

  final Future<Directory> Function() resolveBaseDir;

  /// When true (production), heavy JSON work runs inside [Isolate.run] so
  /// the UI thread never blocks on megabyte payloads. Widget tests run in
  /// a FakeAsync zone where real isolate replies can never arrive — there
  /// the flag is switched off (payloads are tiny) via testOverrides.
  final bool offloadIsolate;

  /// Runs [work] off the main isolate when enabled, synchronously (in a
  /// future) otherwise — the result is identical either way.
  Future<T> _offload<T>(T Function() work) =>
      offloadIsolate ? Isolate.run(work) : Future<T>.value(work());

  Future<Directory> _chatsDir() async {
    final base = await resolveBaseDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}chats');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<List<ChatSummary>> listSummaries() async {
    final Directory dir = await _chatsDir();
    final List<File> files = <File>[
      await for (final entity in dir.list())
        if (entity is File && entity.path.endsWith('.json')) entity,
    ];
    // Read (async IO) on the main isolate, decode+extract off it.
    final List<String> raws = <String>[
      for (final File file in files) await file.readAsString(),
    ];
    final List<ChatSummary> out = await _offload(() {
      final List<ChatSummary> summaries = <ChatSummary>[];
      for (final String raw in raws) {
        try {
          final Object? decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) continue;
          summaries.add(
            ChatSummary(
              id: decoded['id'] as String,
              title: (decoded['title'] as String?) ?? 'Untitled',
              updatedAt:
                  DateTime.tryParse(decoded['updatedAt'] as String? ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
        } catch (_) {
          // Skip corrupted files.
        }
      }
      summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return summaries;
    });
    return out;
  }

  Future<void> save({
    required String id,
    required String title,
    required List<ChatMessage> messages,
    List<String> modules = const <String>[],
  }) async {
    final dir = await _chatsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    // toJson maps stay on the main isolate (cheap, one pass over the list);
    // the megabyte-scale jsonEncode itself runs off the UI thread.
    final Map<String, dynamic> payload = <String, dynamic>{
      'id': id,
      'title': title,
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'modules': modules,
    };
    final String encoded = await _offload(() => jsonEncode(payload));
    await file.writeAsString(encoded);
  }

  Future<List<ChatMessage>?> load(String id) async {
    final dir = await _chatsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    if (!await file.exists()) return null;
    try {
      final String raw = await file.readAsString();
      final Map<String, dynamic>? data = await _offload(() {
        final Object? decoded = jsonDecode(raw);
        return decoded is Map<String, dynamic> ? decoded : null;
      });
      if (data == null) return null;
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

  /// Loads the list of chat modules activated for [sessionId] (plugins
  /// are a per-session private-window scope). Empty when unknown.
  Future<List<String>> loadModules(String id) async {
    final dir = await _chatsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    if (!await file.exists()) return const <String>[];
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final raw = data['modules'];
      if (raw is! List) return const <String>[];
      return <String>[
        for (final Object? name in raw)
          if (name != null && name.toString().trim().isNotEmpty)
            name.toString().trim(),
      ];
    } catch (_) {
      return const <String>[];
    }
  }

  /// Persists the module list of [sessionId] without touching messages.
  Future<void> saveModules(String id, List<String> modules) async {
    final dir = await _chatsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$id.json');
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map<String, dynamic>) {
        data['modules'] = modules;
        await file.writeAsString(jsonEncode(data));
      }
    } catch (_) {
      // Corrupted file: module bookkeeping must never crash the caller.
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
    final List<File> files = <File>[
      await for (final entity in dir.list())
        if (entity is File && entity.path.endsWith('.json')) entity,
    ];
    final List<String> raws = <String>[
      for (final File file in files) await file.readAsString(),
    ];
    // Decode + match every session off the main isolate; the closure works
    // on strings only and returns plain records — all isolate-sendable.
    final List<(ChatSearchHit, bool)> ranked = await _offload(() {
      final List<(ChatSearchHit, bool)> hits = <(ChatSearchHit, bool)>[];
      for (final String raw in raws) {
        try {
          final Object? decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) continue;
          final String id = decoded['id'] as String? ?? '';
          if (id.isEmpty) continue;
          final String title = (decoded['title'] as String?) ?? 'Untitled';
          final DateTime updatedAt =
              DateTime.tryParse(decoded['updatedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bool titleMatch = title.toLowerCase().contains(q);
          if (titleMatch) {
            hits.add((
              ChatSearchHit(
                sessionId: id,
                title: title,
                snippet: _previewOf(decoded['messages'], fallback: title),
                role: null,
                createdAt: updatedAt,
              ),
              true,
            ));
          }
          // First matching message of the session (one hit per conversation
          // keeps the result list diverse).
          final Object? rawMessages = decoded['messages'];
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
              hits.add((
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
      hits.sort((a, b) {
        if (a.$2 != b.$2) return a.$2 ? -1 : 1; // title matches first
        return b.$1.createdAt.compareTo(a.$1.createdAt); // then newest
      });
      return hits;
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
