// lib/features/projects/domain/models/project.dart

import 'package:flutter/foundation.dart';
import '../../../../core/database/database_helper.dart';
import 'project_type.dart';

@immutable
class Project {
  final int id;
  final String title;
  final ProjectType projectType;
  final String pythonContent;
  final String htmlContent;
  final String cssContent;
  final String jsContent;
  final int createdAt;
  final int updatedAt;
  final int lastOpenedAt;

  const Project({
    required this.id,
    required this.title,
    required this.projectType,
    required this.pythonContent,
    required this.htmlContent,
    required this.cssContent,
    required this.jsContent,
    required this.createdAt,
    required this.updatedAt,
    required this.lastOpenedAt,
  });

  Project copyWith({
    int? id,
    String? title,
    ProjectType? projectType,
    String? pythonContent,
    String? htmlContent,
    String? cssContent,
    String? jsContent,
    int? updatedAt,
    int? lastOpenedAt,
  }) {
    return Project(
      id: id ?? this.id,
      title: title ?? this.title,
      projectType: projectType ?? this.projectType,
      pythonContent: pythonContent ?? this.pythonContent,
      htmlContent: htmlContent ?? this.htmlContent,
      cssContent: cssContent ?? this.cssContent,
      jsContent: jsContent ?? this.jsContent,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map[DbSchema.projId] as int,
      title: map[DbSchema.projTitle] as String,
      projectType: ProjectTypeExtension.fromString(map[DbSchema.projType] as String),
      pythonContent: map[DbSchema.projPythonContent] as String,
      htmlContent: map[DbSchema.projHtmlContent] as String,
      cssContent: map[DbSchema.projCssContent] as String,
      jsContent: map[DbSchema.projJsContent] as String,
      createdAt: map[DbSchema.projCreatedAt] as int,
      updatedAt: map[DbSchema.projUpdatedAt] as int,
      lastOpenedAt: map[DbSchema.projLastOpenedAt] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id > 0) DbSchema.projId: id, // Optional for inserts
      DbSchema.projTitle: title,
      DbSchema.projType: projectType.name,
      DbSchema.projPythonContent: pythonContent,
      DbSchema.projHtmlContent: htmlContent,
      DbSchema.projCssContent: cssContent,
      DbSchema.projJsContent: jsContent,
      DbSchema.projCreatedAt: createdAt,
      DbSchema.projUpdatedAt: updatedAt,
      DbSchema.projLastOpenedAt: lastOpenedAt,
    };
  }

  @override
  String toString() {
    return 'Project(id: $id, title: "$title", type: ${projectType.name})';
  }
}
