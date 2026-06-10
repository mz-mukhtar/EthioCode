import re

with open('lib/core/database/database_helper.dart', 'r') as f:
    content = f.read()

replacement = """
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    
    try {
      // ignore: unused_local_variable \u2014 the loop variable `v` drives ordering
      for (int v = oldVersion; v < newVersion; v++) {
        switch (v) {
          case 1:
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projCurrentCode)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projCurrentCode} TEXT NOT NULL DEFAULT \\'\\'');
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
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projType} TEXT NOT NULL DEFAULT \\'python\\'');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projPythonContent)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projPythonContent} TEXT NOT NULL DEFAULT \\'\\'');
              await db.execute('UPDATE ${DbSchema.tableProjects} SET ${DbSchema.projPythonContent} = ${DbSchema.projCurrentCode}');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projHtmlContent)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projHtmlContent} TEXT NOT NULL DEFAULT \\'\\'');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projCssContent)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projCssContent} TEXT NOT NULL DEFAULT \\'\\'');
            }
            if (!await _columnExists(db, DbSchema.tableProjects, DbSchema.projJsContent)) {
              await db.execute('ALTER TABLE ${DbSchema.tableProjects} ADD COLUMN ${DbSchema.projJsContent} TEXT NOT NULL DEFAULT \\'\\'');
            }
            break;
          // Add `case 3:`, `case 4:` etc. as the schema grows.
        }
      }
    } catch (e) {
      throw DatabaseException(operation: 'onUpgrade($oldVersion\u2192$newVersion)', cause: e);
    }
  }
"""

pattern = r"  Future<void> _onUpgrade\(Database db, int oldVersion, int newVersion\) async \{.*?^\s*\}\n  \}"
content = re.sub(pattern, replacement.strip(), content, flags=re.DOTALL | re.MULTILINE)

with open('lib/core/database/database_helper.dart', 'w') as f:
    f.write(content)
