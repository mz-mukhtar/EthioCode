// lib/core/database/database_helper.dart
//
// Single-file SQLite database engine for EthioCode.
//
// Tables
// ──────
//   projects           – student workspace metadata
//   snapshots          – Git-Lite: one row per code execution (append-only)
//   curriculum_progress – per-node unlock/completion state
//
// Design decisions
// ────────────────
//   • DatabaseHelper is a singleton so there is exactly ONE open database
//     connection for the lifetime of the app process. sqflite is NOT
//     process-safe for concurrent multi-isolate access; since all IO happens
//     on the main isolate this is the safest pattern.
//   • All public methods are wrapped in try/catch and return either a typed
//     result or throw a descriptive [DatabaseException] so callers always
//     receive an actionable error rather than a raw sqflite exception.
//   • Every write uses parameter bindings (`whereArgs` / positional `?`)
//     so multi-line code strings with quotes, backslashes, and semicolons
//     cannot corrupt the SQL statement.
//   • Foreign-key enforcement is enabled explicitly per connection via
//     `PRAGMA foreign_keys = ON;` inside [_onConfigure] – sqflite does not
//     enable it by default.
//   • Version migration uses [_onUpgrade] with a switch-fall-through pattern
//     so incremental upgrades from any previous version always apply in order.

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Schema constants  (column names are declared as class-level constants so
// repository classes can reference them without hard-coded strings)
// ─────────────────────────────────────────────────────────────────────────────

/// Public schema constants shared across all repository classes.
abstract class DbSchema {
  // ── Table names ────────────────────────────────────────────────────────────
  static const String tableProjects           = 'projects';
  static const String tableSnapshots          = 'snapshots';
  static const String tableCurriculumProgress = 'curriculum_progress';
  static const String tableSessionState       = 'session_state';

  // ── session_state columns ──────────────────────────────────────────────────
  static const String sessionKey   = 'key';
  static const String sessionValue = 'value';

  // ── projects columns ───────────────────────────────────────────────────────
  static const String projId         = 'id';
  static const String projTitle      = 'title';
  static const String projLanguage   = 'language';
  static const String projCurrentCode = 'current_code';
  static const String projType       = 'project_type';
  static const String projPythonContent = 'python_content';
  static const String projHtmlContent   = 'html_content';
  static const String projCssContent    = 'css_content';
  static const String projJsContent     = 'js_content';
  static const String projCreatedAt  = 'created_at';
  static const String projUpdatedAt  = 'updated_at';
  static const String projLastOpenedAt = 'last_opened_at';

  // ── snapshots columns ──────────────────────────────────────────────────────
  static const String snapId          = 'id';
  static const String snapProjectId   = 'project_id';
  static const String snapCode        = 'code_content';
  static const String snapTimestamp   = 'timestamp';
  static const String snapLinesAdded  = 'lines_added';
  static const String snapLinesRemoved = 'lines_removed';
  static const String snapLabel       = 'label';          // optional user note

  // ── curriculum_progress columns ────────────────────────────────────────────
  static const String cpNodeId      = 'node_id';
  static const String cpIsUnlocked  = 'is_unlocked';
  static const String cpIsCompleted = 'is_completed';
  static const String cpUnlockedAt  = 'unlocked_at';
  static const String cpCompletedAt = 'completed_at';
}

// ─────────────────────────────────────────────────────────────────────────────
// Typed exception for callers
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps any raw database error with context about which operation failed.
class DatabaseException implements Exception {
  final String operation;
  final Object cause;

  const DatabaseException({required this.operation, required this.cause});

  @override
  String toString() =>
      'DatabaseException during "$operation": $cause';
}

// ─────────────────────────────────────────────────────────────────────────────
// DatabaseHelper  (singleton)
// ─────────────────────────────────────────────────────────────────────────────

class DatabaseHelper {
  // ── Singleton plumbing ────────────────────────────────────────────────────
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  factory DatabaseHelper() => instance;

  static Database? _db;

  /// The current schema version.  Increment this whenever [_onUpgrade] gains
  /// a new migration block, then add a corresponding `case` clause.
  static const int _kSchemaVersion = 3;

  static const String _kDbFileName = 'ethiocode.db';

  // ── Public: get or open the database ─────────────────────────────────────

  /// Returns the open [Database] instance, initialising it on first call.
  Future<Database> get database async {
    
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<Database> _initDatabase() async {
    try {
      final docsDir   = await getApplicationDocumentsDirectory();
      final dbPath    = p.join(docsDir.path, _kDbFileName);

      
      return await openDatabase(
        dbPath,
        version:     _kSchemaVersion,
        onConfigure: _onConfigure,
        onCreate:    _onCreate,
        onUpgrade:   _onUpgrade,
        onDowngrade: onDatabaseDowngradeDelete,  // safe fallback: wipe & recreate
      );
    } catch (e) {
      throw DatabaseException(operation: 'initDatabase', cause: e);
    }
  }

  /// Enable foreign-key constraints for every new connection.
  Future<void> _onConfigure(Database db) async {
    
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  // ── Schema creation (version 1) ───────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    
    final batch = db.batch();

    // ── projects ─────────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSchema.tableProjects} (
        ${DbSchema.projId}        INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbSchema.projTitle}     TEXT    NOT NULL DEFAULT 'Untitled',
        ${DbSchema.projLanguage}  TEXT    NOT NULL DEFAULT 'python',
        ${DbSchema.projCurrentCode} TEXT    NOT NULL DEFAULT '',
        ${DbSchema.projType}      TEXT    NOT NULL DEFAULT 'python'
                                  CHECK(${DbSchema.projType} IN ('python','web')),
        ${DbSchema.projPythonContent} TEXT NOT NULL DEFAULT '',
        ${DbSchema.projHtmlContent}   TEXT NOT NULL DEFAULT '',
        ${DbSchema.projCssContent}    TEXT NOT NULL DEFAULT '',
        ${DbSchema.projJsContent}     TEXT NOT NULL DEFAULT '',
        ${DbSchema.projCreatedAt} INTEGER NOT NULL,
        ${DbSchema.projUpdatedAt} INTEGER NOT NULL,
        ${DbSchema.projLastOpenedAt} INTEGER NOT NULL
      );
    ''');

    // Index for chronological listing of all projects.
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_projects_created_at
        ON ${DbSchema.tableProjects}(${DbSchema.projCreatedAt} DESC);
    ''');

    // ── snapshots ─────────────────────────────────────────────────────────────
    // Append-only table: rows are NEVER updated or deleted by the application.
    // Keeping all history is intentional (Git-Lite design).
    batch.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSchema.tableSnapshots} (
        ${DbSchema.snapId}           INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbSchema.snapProjectId}    INTEGER NOT NULL
                                     REFERENCES ${DbSchema.tableProjects}(${DbSchema.projId})
                                     ON DELETE CASCADE,
        ${DbSchema.snapCode}         TEXT    NOT NULL,
        ${DbSchema.snapTimestamp}    INTEGER NOT NULL,
        ${DbSchema.snapLinesAdded}   INTEGER NOT NULL DEFAULT 0,
        ${DbSchema.snapLinesRemoved} INTEGER NOT NULL DEFAULT 0,
        ${DbSchema.snapLabel}        TEXT
      );
    ''');

    // Covering index: fetch history for a project in timestamp order (O(log n)).
    batch.execute('''
      CREATE INDEX IF NOT EXISTS idx_snapshots_project_time
        ON ${DbSchema.tableSnapshots}(
          ${DbSchema.snapProjectId},
          ${DbSchema.snapTimestamp} DESC
        );
    ''');

    // ── curriculum_progress ───────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSchema.tableCurriculumProgress} (
        ${DbSchema.cpNodeId}      TEXT    PRIMARY KEY,
        ${DbSchema.cpIsUnlocked}  INTEGER NOT NULL DEFAULT 0
                                  CHECK(${DbSchema.cpIsUnlocked} IN (0, 1)),
        ${DbSchema.cpIsCompleted} INTEGER NOT NULL DEFAULT 0
                                  CHECK(${DbSchema.cpIsCompleted} IN (0, 1)),
        ${DbSchema.cpUnlockedAt}  INTEGER,
        ${DbSchema.cpCompletedAt} INTEGER
      );
    ''');

    // ── session_state ────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS ${DbSchema.tableSessionState} (
        ${DbSchema.sessionKey}   TEXT PRIMARY KEY,
        ${DbSchema.sessionValue} TEXT NOT NULL
      );
    ''');

    try {
      await batch.commit(noResult: true, continueOnError: false);
    } catch (e) {
      throw DatabaseException(operation: 'onCreate(batch.commit)', cause: e);
    }
  }

  // ── Schema migrations ─────────────────────────────────────────────────────
  //
  // Pattern: switch without breaks so migrations chain naturally.
  // Example: upgrading from v1 → v3 runs cases 1, 2, and (falls through to)
  // the default which exits.  Add new cases as the schema evolves.

  Future<bool> _columnExists(Database db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    for (final row in info) {
      if (row['name'] == column) return true;
    }
    return false;
  }

Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    
    try {
      // ignore: unused_local_variable — the loop variable `v` drives ordering
      for (int v = oldVersion; v < newVersion; v++) {
        switch (v) {
          case 1:
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projCurrentCode)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projCurrentCode} TEXT NOT NULL DEFAULT \'\'');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projUpdatedAt)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projUpdatedAt} INTEGER NOT NULL DEFAULT 0');
              await db.execute('UPDATE ${DbSchema.tableProjects} SET ${DbSchema.projUpdatedAt} = ${DbSchema.projCreatedAt}');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projLastOpenedAt)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projLastOpenedAt} INTEGER NOT NULL DEFAULT 0');
              await db.execute('UPDATE ${DbSchema.tableProjects} SET ${DbSchema.projLastOpenedAt} = ${DbSchema.projCreatedAt}');
            }
            await db.execute('''
              CREATE TABLE IF NOT EXISTS ${DbSchema.tableSessionState} (
                ${DbSchema.sessionKey}   TEXT PRIMARY KEY,
                ${DbSchema.sessionValue} TEXT NOT NULL
              );
            ''');
            break;
          case 2:
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projType)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projType} TEXT NOT NULL DEFAULT \'python\'');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projPythonContent)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projPythonContent} TEXT NOT NULL DEFAULT \'\'');
              await db.execute('UPDATE ${DbSchema.tableProjects} SET ${DbSchema.projPythonContent} = ${DbSchema.projCurrentCode}');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projHtmlContent)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projHtmlContent} TEXT NOT NULL DEFAULT \'\'');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projCssContent)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projCssContent} TEXT NOT NULL DEFAULT \'\'');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projJsContent)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projJsContent} TEXT NOT NULL DEFAULT \'\'');
            }
            break;
          // Add `case 3:`, `case 4:` etc. as the schema grows.
        }
      }
    } catch (e) {
      throw DatabaseException(operation: 'onUpgrade($oldVersion→$newVersion)', cause: e);
    }
  }

  // ── Public: close (used in tests / teardown) ──────────────────────────────

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── Utility helpers (used by repositories) ───────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────

  /// Current wall-clock time as a Unix epoch millisecond integer.
  static int nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// Convert a raw [Map] integer boolean (0/1) to [bool].
  static bool intToBool(Object? value) => (value as int? ?? 0) == 1;

  /// Convert a [bool] to SQLite integer (0/1).
  static int boolToInt(bool value) => value ? 1 : 0;

  // ── Diagnostics ───────────────────────────────────────────────────────────

  /// Returns the absolute path of the open database file.
  Future<String> getDatabasePath() async {
    final db = await database;
    return db.path;
  }

  /// Returns a map of table → row-count for debug/diagnostics screens.
  Future<Map<String, int>> getTableRowCounts() async {
    const tables = [
      DbSchema.tableProjects,
      DbSchema.tableSnapshots,
      DbSchema.tableCurriculumProgress,
    ];
    final result = <String, int>{};
    try {
      final db = await database;
      for (final table in tables) {
        final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $table;');
        result[table] = Sqflite.firstIntValue(rows) ?? 0;
      }
    } catch (e) {
      debugPrint('[DatabaseHelper] getTableRowCounts error: $e');
    }
    return result;
  }
}
