import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ethiocode/core/database/database_helper.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  WidgetsFlutterBinding.ensureInitialized();
  
  // Wipe and create v1
  final docsDir = await getApplicationDocumentsDirectory();
  final dbPath = "${docsDir.path}/ethiocode.db";
  await deleteDatabase(dbPath);
  
  final db1 = await openDatabase(dbPath, version: 1, onCreate: (db, version) async {
    await db.execute("CREATE TABLE projects (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL DEFAULT 'Untitled', language TEXT NOT NULL DEFAULT 'python', created_at INTEGER NOT NULL)");
  });
  await db1.close();
  
  try {
    print("[TEST] Upgrading database");
    DatabaseHelper.instance.database.then((_){
      print("[TEST] Upgrade Success!");
    }).catchError((e){
      print("[TEST] Upgrade Error: $e");
    });
    // Add a sleep so we can see what hangs
    await Future.delayed(Duration(seconds: 3));
    print("[TEST] Wait Finished");
  } catch(e, st) {
    print("[TEST] Upgrade Error: $e\n$st");
  }
}
