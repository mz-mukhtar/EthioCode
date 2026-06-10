// lib/features/projects/data/repositories/project_repository.dart

import 'package:sqflite/sqflite.dart' hide DatabaseException;
import '../../../../core/database/database_helper.dart';
import '../../domain/models/project.dart';
import '../../domain/models/project_type.dart';

/// CRUD operations for the [Project] entity.
class ProjectRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Creates a new project with the given [title] and [projectType] and optional initial code.
  Future<Project> createProject({
    required String title,
    required ProjectType projectType,
    String pythonContent = '',
    String htmlContent = '',
    String cssContent = '',
    String jsContent = '',
  }) async {
    try {
      final db = await _dbHelper.database;
      final now = DatabaseHelper.nowMs();
      
      final project = Project(
        id: 0, // SQLite will autoincrement
        title: title,
        projectType: projectType,
        pythonContent: pythonContent,
        htmlContent: htmlContent,
        cssContent: cssContent,
        jsContent: jsContent,
        createdAt: now,
        updatedAt: now,
        lastOpenedAt: now,
      );

      final id = await db.insert(
        DbSchema.tableProjects,
        project.toMap()..remove(DbSchema.projId),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );

      return project.copyWith(id: id);
    } catch (e) {
      throw DatabaseException(operation: 'createProject', cause: e);
    }
  }

  /// Retrieves a specific project by [id].
  Future<Project?> getProject(int id) async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query(
        DbSchema.tableProjects,
        where: '${DbSchema.projId} = ?',
        whereArgs: [id],
        limit: 1,
      );
      
      if (maps.isEmpty) return null;
      return Project.fromMap(maps.first);
    } catch (e) {
      throw DatabaseException(operation: 'getProject', cause: e);
    }
  }

  /// Returns all projects, ordered by most recently opened first.
  Future<List<Project>> getProjects() async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query(
        DbSchema.tableProjects,
        orderBy: '${DbSchema.projLastOpenedAt} DESC',
      );
      
      return maps.map((map) => Project.fromMap(map)).toList();
    } catch (e) {
      throw DatabaseException(operation: 'getProjects', cause: e);
    }
  }

  /// Updates an existing project. Usually called for autosave (updating `current_code` and `updated_at`)
  /// or when opening a project (updating `last_opened_at`).
  Future<void> updateProject(Project project) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        DbSchema.tableProjects,
        project.toMap(),
        where: '${DbSchema.projId} = ?',
        whereArgs: [project.id],
      );
    } catch (e) {
      throw DatabaseException(operation: 'updateProject', cause: e);
    }
  }

  /// Deletes a project by [id]. Since `snapshots` table uses ON DELETE CASCADE,
  /// all associated snapshots will also be automatically deleted.
  Future<void> deleteProject(int id) async {
    try {
      final db = await _dbHelper.database;
      await db.delete(
        DbSchema.tableProjects,
        where: '${DbSchema.projId} = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw DatabaseException(operation: 'deleteProject', cause: e);
    }
  }
}
