import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zagents/di.dart';
import 'package:zagents/main.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/file_system_service.dart';

import '../../test/fakes/fakes.dart';

/// In-memory FileSystemService for widget tests: the real service does
/// real IO which never completes inside the fake-async test zone (its
/// logic is fully covered by unit tests).
class StaticFileSystemService extends FileSystemService {
  StaticFileSystemService()
    : super(resolveBaseDir: () async => Directory.systemTemp);

  final List<FsEntry> entries = <FsEntry>[];
  final List<String> createdFolders = <String>[];

  @override
  Future<List<FsEntry>> list(String relative) async =>
      relative.isEmpty ? entries : const <FsEntry>[];

  @override
  Future<bool> exists(String relative) async => true;

  @override
  Future<void> mkdir(String relative) async => createdFolders.add(relative);

  @override
  Future<void> rename(String relative, String newName) async {}

  @override
  Future<void> delete(String relative) async {
    entries.removeWhere((FsEntry e) => e.relativePath == relative);
  }

  @override
  Future<void> copy(String srcRelative, String destRelative) async {}

  @override
  Future<void> move(String srcRelative, String destRelative) async {
    entries.removeWhere((FsEntry e) => e.relativePath == srcRelative);
  }

  @override
  Future<String> zip(String srcRelative) async => '$srcRelative.zip';

  @override
  Future<String> unzip(String zipRelative, {String? destName}) async =>
      destName ?? zipRelative;

  @override
  Future<String> readText(String relative, {int maxChars = 20000}) async =>
      'preview text';
}

void main() {
  late Directory tempDir;
  late StaticFileSystemService fs;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_files_test');
    fs = StaticFileSystemService();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> openFilesScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...testOverrides(dir: tempDir),
          fileSystemServiceProvider.overrideWithValue(fs),
          chatListProvider.overrideWith(
            (Ref ref) async => const <ChatSummary>[],
          ),
        ],
        child: const ZAgentsApp(),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(find.byKey(const Key('drawer-files')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  testWidgets('files screen lists entries from the file service', (
    tester,
  ) async {
    fs.entries.add(
      FsEntry(
        name: 'hello.txt',
        relativePath: 'hello.txt',
        isDirectory: false,
        sizeBytes: 5,
        modified: DateTime(2025, 1, 1),
      ),
    );
    await openFilesScreen(tester);
    expect(find.byKey(const Key('file-hello.txt')), findsOneWidget);
  });

  testWidgets('files screen shows the empty state for a fresh app', (
    tester,
  ) async {
    await openFilesScreen(tester);
    expect(find.textContaining('No files yet'), findsOneWidget);
  });

  testWidgets('file search filters entries by name', (tester) async {
    FsEntry file(String name) => FsEntry(
      name: name,
      relativePath: name,
      isDirectory: false,
      sizeBytes: 1,
      modified: DateTime(2025, 1, 1),
    );
    fs.entries.addAll(<FsEntry>[file('report.txt'), file('photo.png')]);
    await openFilesScreen(tester);

    expect(find.byKey(const Key('file-report.txt')), findsOneWidget);
    expect(find.byKey(const Key('file-photo.png')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('files-search-field')),
      'report',
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.byKey(const Key('file-report.txt')), findsOneWidget);
    expect(find.byKey(const Key('file-photo.png')), findsNothing);

    // No match shows the localized empty state.
    await tester.enterText(find.byKey(const Key('files-search-field')), 'zzz');
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('new folder dialog reaches the service with the name', (
    tester,
  ) async {
    await openFilesScreen(tester);
    await tester.tap(find.byKey(const Key('files-new-folder')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.enterText(
      find.byKey(const Key('new-folder-field')),
      'exports',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(fs.createdFolders, contains('exports'));
  });

  testWidgets('cut an entry then paste shows the clipboard flow', (
    tester,
  ) async {
    fs.entries.add(
      FsEntry(
        name: 'move-me.txt',
        relativePath: 'move-me.txt',
        isDirectory: false,
        sizeBytes: 2,
        modified: DateTime(2025, 1, 1),
      ),
    );
    await openFilesScreen(tester);

    // Cut via the per-entry menu.
    await tester.tap(find.byKey(const Key('file-menu-move-me.txt')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(find.text('Cut').last);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    // The paste button becomes enabled.
    final Finder paste = find.byKey(const Key('files-paste'));
    expect(tester.widget<IconButton>(paste).onPressed, isNotNull);
    await tester.tap(paste);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    // Pasting a CUT item into its own folder is a deliberate no-op:
    // the clipboard stays armed so the user can navigate elsewhere.
    expect(tester.widget<IconButton>(paste).onPressed, isNotNull);
  });

  testWidgets('delete entry flow removes it from the list', (tester) async {
    fs.entries.add(
      FsEntry(
        name: 'gone.txt',
        relativePath: 'gone.txt',
        isDirectory: false,
        sizeBytes: 1,
        modified: DateTime(2025, 1, 1),
      ),
    );
    await openFilesScreen(tester);
    await tester.tap(find.byKey(const Key('file-menu-gone.txt')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    // Confirm the dialog.
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    expect(find.byKey(const Key('file-gone.txt')), findsNothing);
  });
}
