// lib/features/workspace/domain/repositories/editor_repository.dart
//
// Abstract repository contract for persisting/loading editor buffers.
// Concrete implementations live in the data layer (not yet scaffolded).

import '../entities/editor_state.dart';

/// Repository interface for loading and saving editor buffers.
abstract class EditorRepository {
  /// Load the content of a file at [path] and return an [EditorState].
  /// Throws [FileNotFoundException] if the path does not exist.
  Future<EditorState> loadFile(String path);

  /// Save the [state] content to its [EditorState.filePath].
  /// Throws [StorageException] if the write fails (e.g. no space on device).
  Future<void> saveFile(EditorState state);

  /// List all files available in the local workspace directory.
  Future<List<String>> listFiles(String workspacePath);
}
