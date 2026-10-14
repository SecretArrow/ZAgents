import 'dart:io';

import 'package:archive/archive.dart';

/// One entry in the app's file workspace.
class FsEntry {
  const FsEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modified,
  });

  final String name;
  final String relativePath;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime modified;

  String get extension => name.contains('.') && !isDirectory
      ? name.split('.').last.toLowerCase()
      : '';
}

/// Thrown when an archive is encrypted (ZipCrypto or WinZip AES) and no
/// password was supplied to [FileSystemService.unzip].
class ZipPasswordRequiredException implements Exception {
  const ZipPasswordRequiredException(this.filename);

  final String filename;

  @override
  String toString() => 'ZipPasswordRequiredException: $filename';
}

/// Thrown when the supplied password does not decrypt the archive.
class ZipWrongPasswordException implements Exception {
  const ZipWrongPasswordException();

  @override
  String toString() => 'ZipWrongPasswordException';
}

/// All file-management operations for the in-app File Manager and the
/// zip/unzip features. Every path is sandboxed under the app documents
/// directory — traversal attempts are rejected.
class FileSystemService {
  FileSystemService({required this.resolveBaseDir});

  final Future<Directory> Function() resolveBaseDir;

  Future<String> _root() async => (await resolveBaseDir()).path;

  /// Resolves [relative] under the root, rejecting traversal. Dot segments
  /// (`..`, `.`) are normalized the same way the tool executor does it.
  Future<String?> resolve(String relative) async {
    final String root = await _root();
    if (relative.trim().isEmpty || relative == '.' || relative == '/') {
      return root;
    }
    try {
      final String normalizedRoot = root.endsWith(Platform.pathSeparator)
          ? root
          : '$root${Platform.pathSeparator}';
      final String resolved = Directory(normalizedRoot).uri
          .resolve(relative)
          .toFilePath();
      if (!resolved.startsWith(normalizedRoot)) return null;
      return resolved;
    } catch (_) {
      return null;
    }
  }

  /// Lists entries of [relative] directory (names, sizes, mtimes), sorted
  /// folders-first then alphabetically.
  Future<List<FsEntry>> list(String relative) async {
    final String? dirPath = await resolve(relative);
    if (dirPath == null) return const <FsEntry>[];
    final Directory dir = Directory(dirPath);
    if (!dir.existsSync()) return const <FsEntry>[];
    final List<FsEntry> out = <FsEntry>[];
    await for (final FileSystemEntity entity in dir.list(followLinks: false)) {
      final String name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue; // hidden/internal files
      try {
        final FileStat stat = entity.statSync();
        final bool isDir = stat.type == FileSystemEntityType.directory;
        final String rel = relative.trim().isEmpty || relative == '.'
            ? name
            : '$relative${Platform.pathSeparator}$name';
        out.add(
          FsEntry(
            name: name,
            relativePath: rel,
            isDirectory: isDir,
            sizeBytes: isDir ? 0 : stat.size,
            modified: stat.modified,
          ),
        );
      } catch (_) {
        // Unreadable entry: skip, never crash the manager.
      }
    }
    out.sort((FsEntry a, FsEntry b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  Future<bool> exists(String relative) async {
    final String? path = await resolve(relative);
    return path != null &&
        FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  Future<void> mkdir(String relative) async {
    final String? path = await resolve(relative);
    if (path == null) throw const FileSystemException('Invalid path');
    await Directory(path).create(recursive: true);
  }

  Future<void> rename(String relative, String newName) async {
    final String? path = await resolve(relative);
    if (path == null) throw const FileSystemException('Invalid path');
    if (newName.contains('/') ||
        newName.contains('\\') ||
        newName.trim().isEmpty) {
      throw const FileSystemException('Invalid name');
    }
    final FileSystemEntity entity =
        FileSystemEntity.typeSync(path) == FileSystemEntityType.directory
        ? Directory(path)
        : File(path);
    final String parent = path.substring(
      0,
      path.lastIndexOf(Platform.pathSeparator),
    );
    await entity.rename('$parent${Platform.pathSeparator}$newName');
  }

  Future<void> delete(String relative) async {
    final String? path = await resolve(relative);
    if (path == null) throw const FileSystemException('Invalid path');
    final FileSystemEntityType type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) return;
    final FileSystemEntity entity = type == FileSystemEntityType.directory
        ? Directory(path)
        : File(path);
    await entity.delete(recursive: true);
  }

  /// Copies a file or a whole directory (recursive). [destRelative] is the
  /// full destination path (file name for files).
  Future<void> copy(String srcRelative, String destRelative) async {
    final String? src = await resolve(srcRelative);
    final String? dest = await resolve(destRelative);
    if (src == null || dest == null) {
      throw const FileSystemException('Invalid path');
    }
    final FileSystemEntityType type = FileSystemEntity.typeSync(src);
    if (type == FileSystemEntityType.directory) {
      await _copyDir(Directory(src), Directory(dest));
    } else if (type == FileSystemEntityType.file) {
      await File(src).parent.create(recursive: true);
      await File(src).copy(dest);
    } else {
      throw const FileSystemException('Source not found');
    }
  }

  /// Moves (cut+paste) a file or directory.
  Future<void> move(String srcRelative, String destRelative) async {
    final String? src = await resolve(srcRelative);
    final String? dest = await resolve(destRelative);
    if (src == null || dest == null) {
      throw const FileSystemException('Invalid path');
    }
    final FileSystemEntityType type = FileSystemEntity.typeSync(src);
    if (type == FileSystemEntityType.notFound) {
      throw const FileSystemException('Source not found');
    }
    await File(dest).parent.create(recursive: true);
    final FileSystemEntity entity = type == FileSystemEntityType.directory
        ? Directory(src)
        : File(src);
    try {
      await entity.rename(dest);
    } on FileSystemException {
      // Cross-container rename fallback: copy + delete.
      if (type == FileSystemEntityType.directory) {
        await _copyDir(Directory(src), Directory(dest));
        await Directory(src).delete(recursive: true);
      } else {
        await File(src).copy(dest);
        await File(src).delete();
      }
    }
  }

  Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final FileSystemEntity entity in from.list(followLinks: false)) {
      final String name = entity.path.split(Platform.pathSeparator).last;
      final String destPath = '${to.path}${Platform.pathSeparator}$name';
      final FileSystemEntityType type = FileSystemEntity.typeSync(entity.path);
      if (type == FileSystemEntityType.directory) {
        await _copyDir(entity as Directory, Directory(destPath));
      } else if (type == FileSystemEntityType.file) {
        await (entity as File).copy(destPath);
      }
    }
  }

  /// Compresses a file or directory into `<name>.zip` next to it.
  /// Returns the zip's relative path.
  Future<String> zip(String srcRelative) async {
    final String? src = await resolve(srcRelative);
    if (src == null) throw const FileSystemException('Invalid path');
    final FileSystemEntityType type = FileSystemEntity.typeSync(src);
    if (type == FileSystemEntityType.notFound) {
      throw const FileSystemException('Source not found');
    }
    final bool isDir = type == FileSystemEntityType.directory;
    final Archive archive = Archive();
    final String baseName = src.split(Platform.pathSeparator).last;
    if (isDir) {
      await for (final FileSystemEntity entity in Directory(
        src,
      ).list(recursive: true, followLinks: false)) {
        final FileSystemEntityType t = FileSystemEntity.typeSync(entity.path);
        // Entries are stored relative to the compressed folder itself so
        // extracting proj.zip yields proj_extracted/a.txt (no double nest).
        final String relInZip = entity.path
            .substring(src.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        if (t == FileSystemEntityType.file) {
          final File file = entity as File;
          final List<int> bytes = await file.readAsBytes();
          archive.addFile(
            ArchiveFile(relInZip, bytes.length, bytes)
              ..lastModTime = file.lastModifiedSync().millisecondsSinceEpoch,
          );
        }
      }
    } else {
      final List<int> bytes = await File(src).readAsBytes();
      archive.addFile(ArchiveFile(baseName, bytes.length, bytes));
    }
    final String zipPath = '$src.zip';
    final List<int> encoded = ZipEncoder().encode(archive);
    await File(zipPath).writeAsBytes(encoded);
    final String root = await _root();
    return zipPath.startsWith(root)
        ? zipPath.substring(root.length + 1)
        : zipPath;
  }

  /// Extracts [zipRelative] into a sibling folder named after the archive
  /// (or [destName]). Returns the destination's relative path.
  ///
  /// Encrypted archives (legacy ZipCrypto and WinZip AES-128/192/256) are
  /// decrypted with [password]. Passing no password to an encrypted archive
  /// throws [ZipPasswordRequiredException]; a wrong password throws
  /// [ZipWrongPasswordException].
  Future<String> unzip(
    String zipRelative, {
    String? destName,
    String? password,
  }) async {
    final String? zipPath = await resolve(zipRelative);
    if (zipPath == null) throw const FileSystemException('Invalid path');
    final List<int> bytes = await File(zipPath).readAsBytes();
    // The archive package decrypts lazily: encryption problems surface
    // while entries are read, not only during decodeBytes, so both the
    // decode and the extraction loop must be covered here.
    try {
      final Archive archive = ZipDecoder().decodeBytes(
        bytes,
        password: (password == null || password.isEmpty) ? null : password,
      );
      final String zipName = zipPath.split(Platform.pathSeparator).last;
      final String parentDir = zipPath.substring(
        0,
        zipPath.lastIndexOf(Platform.pathSeparator),
      );
      String folderName =
          destName ??
          (zipName.toLowerCase().endsWith('.zip')
              ? zipName.substring(0, zipName.length - 4)
              : '${zipName}_extracted');
      // Never collide with an existing entry next to the archive (e.g.
      // extracting proj.zip next to the original proj/ folder).
      if (FileSystemEntity.typeSync(
            '$parentDir${Platform.pathSeparator}$folderName',
          ) !=
          FileSystemEntityType.notFound) {
        folderName = '${folderName}_extracted';
      }
      final Directory dest = Directory(
        '$parentDir${Platform.pathSeparator}$folderName',
      );
      await dest.create(recursive: true);
      for (final ArchiveFile file in archive.files) {
        final String outPath =
            '${dest.path}${Platform.pathSeparator}${file.name.replaceAll('/', Platform.pathSeparator)}';
        if (file.isFile) {
          final File outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(outPath).create(recursive: true);
        }
      }
      final String root = await _root();
      return dest.path.startsWith(root)
          ? dest.path.substring(root.length + 1)
          : dest.path;
    } on ArchiveException catch (error) {
      // The archive package reports encryption problems through message
      // text only, so map them onto typed exceptions callers can act on.
      final String message = error.message;
      if (message.contains('A password is needed')) {
        throw ZipPasswordRequiredException(
          zipPath.split(Platform.pathSeparator).last,
        );
      }
      if (message.contains('Wrong password')) {
        throw const ZipWrongPasswordException();
      }
      rethrow;
    }
  }

  /// Reads a text preview (max [maxChars]) of a file.
  Future<String> readText(String relative, {int maxChars = 20000}) async {
    final String? path = await resolve(relative);
    if (path == null) throw const FileSystemException('Invalid path');
    final String content = await File(path).readAsString();
    return content.length > maxChars ? content.substring(0, maxChars) : content;
  }
}
