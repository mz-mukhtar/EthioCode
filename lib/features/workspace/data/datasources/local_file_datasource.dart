// lib/features/workspace/data/datasources/local_file_datasource.dart
//
// Concrete data source that reads/writes files from the device's local
// filesystem using dart:io. Implements the contract expected by the
// EditorRepository. Separated for testability and offline-first design.

import 'dart:io';

/// Low-level local file I/O.  Used by [LocalEditorRepository] (not yet wired).
class LocalFileDatasource {
  /// Read a file at [path] and return its UTF-8 content.
  Future<String> readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }
    return file.readAsString();
  }

  /// Write [content] to the file at [path], creating it if necessary.
  Future<void> writeFile(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  /// List all file paths under [directoryPath].
  Future<List<String>> listFiles(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];
    final entities = await dir
        .list(recursive: false, followLinks: false)
        .where((e) => e is File)
        .toList();
    return entities.map((e) => e.path).toList();
  }
}
