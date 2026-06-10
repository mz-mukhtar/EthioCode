// lib/features/workspace/domain/entities/editor_state.dart
//
// Domain entity representing the logical state of an open editor buffer.
// Kept immutable; changes produce new instances (value semantics).

import 'package:flutter/foundation.dart';

/// Represents a single open file buffer in the IDE.
@immutable
class EditorState {
  /// The raw source text content of the buffer.
  final String content;

  /// The file path; null if the buffer has never been saved.
  final String? filePath;

  /// The programming language – used to pick the syntax highlighter.
  final EditorLanguage language;

  /// Whether the buffer has unsaved changes.
  final bool isDirty;

  const EditorState({
    required this.content,
    this.filePath,
    this.language = EditorLanguage.python,
    this.isDirty  = false,
  });

  EditorState copyWith({
    String?         content,
    String?         filePath,
    EditorLanguage? language,
    bool?           isDirty,
  }) {
    return EditorState(
      content:  content  ?? this.content,
      filePath: filePath ?? this.filePath,
      language: language ?? this.language,
      isDirty:  isDirty  ?? this.isDirty,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorState &&
          runtimeType == other.runtimeType &&
          content  == other.content  &&
          filePath == other.filePath &&
          language == other.language &&
          isDirty  == other.isDirty;

  @override
  int get hashCode =>
      content.hashCode  ^
      filePath.hashCode ^
      language.hashCode ^
      isDirty.hashCode;
}

enum EditorLanguage { python, html, plainText }
