// lib/features/projects/data/repositories/snapshot_repository.dart
//
// Repository implementation for the Git-Lite engine.
// Every code execution inserts a new row into the snapshots table.
//
// Responsibilities:
//   • Provide safe, parameter-bound insert/query methods.
//   • Track basic line diff metrics (lines added/removed) by comparing
//     the incoming code to the most recent previous snapshot.
//   • Map raw SQLite Map<String, Object?> rows back to Dart models.

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Snapshot Model
// ─────────────────────────────────────────────────────────────────────────────
@immutable
class CodeSnapshot {
  final int id;
  final int projectId;
  final String codeContent;
  final int timestamp;
  final int linesAdded;
  final int linesRemoved;
  final String? label;

  const CodeSnapshot({
    required this.id,
    required this.projectId,
    required this.codeContent,
    required this.timestamp,
    required this.linesAdded,
    required this.linesRemoved,
    this.label,
  });

  factory CodeSnapshot.fromMap(Map<String, Object?> map) {
    return CodeSnapshot(
      id:           map[DbSchema.snapId]           as int,
      projectId:    map[DbSchema.snapProjectId]    as int,
      codeContent:  map[DbSchema.snapCode]         as String,
      timestamp:    map[DbSchema.snapTimestamp]    as int,
      linesAdded:   map[DbSchema.snapLinesAdded]   as int,
      linesRemoved: map[DbSchema.snapLinesRemoved] as int,
      label:        map[DbSchema.snapLabel]        as String?,
    );
  }

  /// Calculates a simplistic line-diff between two strings.
  /// (A true LCS diff is too heavy for on-device synchronous execution;
  /// this fast delta provides enough info for a spark-line graph).
  static Map<String, int> computeLineDiff(String oldText, String newText) {
    final oldLines = oldText.isEmpty ? [] : oldText.split('\n');
    final newLines = newText.isEmpty ? [] : newText.split('\n');

    int added = 0;
    int removed = 0;

    // Convert to sets for fast set difference (order doesn't matter for pure counts).
    final oldSet = oldLines.toSet();
    final newSet = newLines.toSet();

    for (final line in newLines) {
      if (!oldSet.contains(line)) added++;
    }
    for (final line in oldLines) {
      if (!newSet.contains(line)) removed++;
    }

    return {'added': added, 'removed': removed};
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────────
class SnapshotRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Inserts a new snapshot for [projectId].
  /// Computes the line delta by looking up the most recent snapshot first.
  Future<CodeSnapshot> insertSnapshot({
    required int projectId,
    required String codeContent,
    String? label,
  }) async {
    try {
      final db = await _dbHelper.database;

      // 1. Fetch previous snapshot to compute line diff.
      // Use parameterized query to protect against SQL injection.
      final prevRows = await db.query(
        DbSchema.tableSnapshots,
        columns: [DbSchema.snapCode],
        where: '${DbSchema.snapProjectId} = ?',
        whereArgs: [projectId],
        orderBy: '${DbSchema.snapTimestamp} DESC',
        limit: 1,
      );

      final prevCode = prevRows.isNotEmpty
          ? (prevRows.first[DbSchema.snapCode] as String)
          : '';

      final diff = CodeSnapshot.computeLineDiff(prevCode, codeContent);
      final ts = DatabaseHelper.nowMs();

      // 2. Insert new row via safe Map binding.
      final values = {
        DbSchema.snapProjectId:    projectId,
        DbSchema.snapCode:         codeContent,
        DbSchema.snapTimestamp:    ts,
        DbSchema.snapLinesAdded:   diff['added'] ?? 0,
        DbSchema.snapLinesRemoved: diff['removed'] ?? 0,
        DbSchema.snapLabel:        label,
      };

      final id = await db.insert(
        DbSchema.tableSnapshots,
        values,
        conflictAlgorithm: ConflictAlgorithm.abort, // FK violations will throw.
      );

      return CodeSnapshot(
        id: id,
        projectId: projectId,
        codeContent: codeContent,
        timestamp: ts,
        linesAdded: values[DbSchema.snapLinesAdded] as int,
        linesRemoved: values[DbSchema.snapLinesRemoved] as int,
        label: label,
      );
    } catch (e) {
      throw DatabaseException(operation: 'insertSnapshot', cause: e);
    }
  }

  /// Retrieves a chronological history of snapshots for [projectId].
  /// Returns the newest snapshot first.
  Future<List<CodeSnapshot>> getHistory(int projectId, {int limit = 100}) async {
    try {
      final db = await _dbHelper.database;

      // Uses idx_snapshots_project_time covering index for fast O(log n) read.
      final rows = await db.query(
        DbSchema.tableSnapshots,
        where: '${DbSchema.snapProjectId} = ?',
        whereArgs: [projectId],
        orderBy: '${DbSchema.snapTimestamp} DESC',
        limit: limit,
      );

      return rows.map((row) => CodeSnapshot.fromMap(row)).toList();
    } catch (e) {
      throw DatabaseException(operation: 'getHistory', cause: e);
    }
  }
}
