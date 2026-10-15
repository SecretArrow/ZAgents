import 'dart:io';

import 'file_system_service.dart';

/// Per-chat-session file workspace, like a browser private window:
/// every chat session gets its OWN sandbox directory under
/// `documents/sessions/<sessionId>/` so uploads, agent-created files,
/// archives and screenshots never mix between sessions.
///
/// `null` session ids (legacy call sites / tests without a session)
/// resolve to the app documents root — the pre-isolation layout.
class SessionSandbox {
  SessionSandbox({required this.resolveDocumentsDir});

  /// Yields the app documents directory (overridden in tests).
  final Future<Directory> Function() resolveDocumentsDir;

  /// Directories/files at the documents root that belong to app services
  /// (not to a chat workspace) and are never migrated into a session.
  static const Set<String> _reservedNames = <String>{
    'chats', // ChatStore (per-session JSON transcripts)
    'node_modules', // NpmService (global package library)
    'modules', // ModuleRegistry (global chat-module programs)
    'exports', // SessionExporter
    'sessions', // the isolated sandboxes themselves
    'shots', // WebViewAutomation screenshots
  };

  /// Ensures the one-time import of the legacy shared workspace (files
  /// sitting directly in the documents root, e.g. `uploads/`) into the
  /// first session sandbox materialized after the update.
  bool _legacyChecked = false;

  /// Root workspace directory for [sessionId]. Creates the directory on
  /// first use and performs the legacy import once (guarded by the
  /// `.legacy-imported` marker). `null` yields the legacy shared root.
  Future<Directory> rootFor(String? sessionId) async {
    final Directory docs = await resolveDocumentsDir();
    if (!docs.existsSync()) docs.createSync(recursive: true);
    if (sessionId == null || sessionId.trim().isEmpty) return docs;
    final String root =
        '${docs.path}${Platform.pathSeparator}sessions'
        '${Platform.pathSeparator}$sessionId';
    final Directory dir = Directory(root);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await _importLegacyOnce(docs, dir);
    return dir;
  }

  /// A [FileSystemService] bound to [sessionId]'s workspace.
  FileSystemService fsFor(String? sessionId) =>
      FileSystemService(resolveBaseDir: () => rootFor(sessionId));

  Future<void> _importLegacyOnce(Directory docs, Directory target) async {
    if (_legacyChecked) return;
    _legacyChecked = true;
    try {
      final Directory sessionsDir = Directory(
        '${docs.path}${Platform.pathSeparator}sessions',
      );
      final File marker = File(
        '${sessionsDir.path}${Platform.pathSeparator}.legacy-imported',
      );
      if (marker.existsSync()) return;
      marker.createSync(recursive: true);
      // Move every non-reserved root entry into [target]. All IO is
      // SYNCHRONOUS on purpose: rootFor() is resolved inside the agent
      // tool path, which also runs under widget-test async-test zones
      // where real async IO would never complete. Entries may vanish
      // concurrently — ignore failures and move on.
      for (final FileSystemEntity entity in docs.listSync(followLinks: false)) {
        final String name = entity.path.split(Platform.pathSeparator).last;
        if (_reservedNames.contains(name) || name.startsWith('.')) continue;
        try {
          final String dest = '${target.path}${Platform.pathSeparator}$name';
          if (FileSystemEntity.typeSync(dest) !=
              FileSystemEntityType.notFound) {
            continue;
          }
          entity.renameSync(dest);
        } catch (_) {
          // best effort — the file simply stays in the legacy root
        }
      }
    } catch (_) {
      // Never let migration break sandbox creation.
    }
  }
}
