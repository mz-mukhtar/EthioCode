// lib/core/session/session_manager.dart

import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

/// Manages key-value session state using the `session_state` SQLite table.
/// 
/// Used to persist app-level UI state (e.g., last active project, cursor position)
/// across app restarts, avoiding the need for a separate shared_preferences package.
class SessionManager {
  // ── Keys ───────────────────────────────────────────────────────────────────
  static const String _keyLastProjectId = 'last_project_id';
  static const String _keyLastCursorPos = 'last_cursor_position';
  static const String _keyLastOpenedAt  = 'last_opened_timestamp';
  static const String _keyLastWebTab    = 'last_web_tab';
  static const String _keyLastPanel     = 'last_workspace_panel';

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ── Generic Get/Set ────────────────────────────────────────────────────────

  Future<void> _setString(String key, String value) async {
    final db = await _dbHelper.database;
    await db.insert(
      DbSchema.tableSessionState,
      {
        DbSchema.sessionKey: key,
        DbSchema.sessionValue: value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _getString(String key) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      DbSchema.tableSessionState,
      columns: [DbSchema.sessionValue],
      where: '${DbSchema.sessionKey} = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first[DbSchema.sessionValue] as String?;
  }

  Future<void> _setInt(String key, int value) async {
    await _setString(key, value.toString());
  }

  Future<int?> _getInt(String key) async {
    final str = await _getString(key);
    if (str == null) return null;
    return int.tryParse(str);
  }

  // ── Typed API ──────────────────────────────────────────────────────────────

  /// The ID of the project the user was last working on.
  Future<int?> getLastProjectId() => _getInt(_keyLastProjectId);

  /// Save the ID of the currently active project.
  Future<void> setLastProjectId(int projectId) async {
    await _setInt(_keyLastProjectId, projectId);
    await setLastOpenedTimestamp(DatabaseHelper.nowMs());
  }

  /// The cursor position (offset) in the text editor.
  Future<int> getLastCursorPosition() async {
    return (await _getInt(_keyLastCursorPos)) ?? 0;
  }

  /// Save the cursor position.
  Future<void> setLastCursorPosition(int position) async {
    await _setInt(_keyLastCursorPos, position);
  }

  /// The timestamp when the app was last active.
  Future<int?> getLastOpenedTimestamp() => _getInt(_keyLastOpenedAt);

  /// Save the current timestamp.
  Future<void> setLastOpenedTimestamp(int ms) async {
    await _setInt(_keyLastOpenedAt, ms);
  }

  /// The last active web tab (html, css, js).
  Future<String> getLastWebTab() async {
    return (await _getString(_keyLastWebTab)) ?? 'html';
  }

  /// Save the last active web tab.
  Future<void> setLastWebTab(String tab) async {
    await _setString(_keyLastWebTab, tab);
  }

  /// The last active workspace panel (editor, output, console, preview).
  Future<String?> getLastWorkspacePanel() async {
    return _getString(_keyLastPanel);
  }

  /// Save the last active workspace panel.
  Future<void> setLastWorkspacePanel(String panel) async {
    await _setString(_keyLastPanel, panel);
  }
}
