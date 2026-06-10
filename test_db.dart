import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ethiocode/core/database/database_helper.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  WidgetsFlutterBinding.ensureInitialized();
  try {
    print("[TEST] Getting database");
    await DatabaseHelper.instance.database;
    print("[TEST] Success!");
  } catch(e, st) {
    print("[TEST] Error: $e\n$st");
  }
}
