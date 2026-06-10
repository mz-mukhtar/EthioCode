// lib/features/projects/domain/models/project.dart

import 'package:flutter/foundation.dart';
import '../../../../core/database/database_helper.dart';

@immutable
class Project {
  final int id;
  final String title;
  final String language;
  final String currentCode;
  final int createdAt;
  final int updatedAt;
  final int lastOpenedAt;

  const Project({
    required this.id,
    required this.title,
    required this.language,
    required this.currentCode,
    required this.createdAt,
    required this.updatedAt,
    required this.lastOpenedAt,
  });

  Project copyWith({
    int? id,
    String? title,
    String? language,
    String? currentCode,
    int? updatedAt,
    int? lastOpenedAt,
  }) {
    return Project(
      id: id ?? this.id,
      title: title ?? this.title,
      language: language ?? this.language,
      currentCode: currentCode ?? this.currentCode,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map[DbSchema.projId] as int,
      title: map[DbSchema.projTitle] as String,
      language: map[DbSchema.projLanguage] as String,
      currentCode: map[DbSchema.projCurrentCode] as String,
      createdAt: map[DbSchema.projCreatedAt] as int,
      updatedAt: map[DbSchema.projUpdatedAt] as int,
      lastOpenedAt: map[DbSchema.projLastOpenedAt] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id > 0) DbSchema.projId: id, // Optional for inserts
      DbSchema.projTitle: title,
      DbSchema.projLanguage: language,
      DbSchema.projCurrentCode: currentCode,
      DbSchema.projCreatedAt: createdAt,
      DbSchema.projUpdatedAt: updatedAt,
      DbSchema.projLastOpenedAt: lastOpenedAt,
    };
  }

  @override
  String toString() {
    return 'Project(id: $id, title: "$title", code_len: ${currentCode.length})';
  }
}
