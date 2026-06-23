import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// アプリ全体で単一の Database を保持する薄いラッパ。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  /// テスト等で任意の Database を注入する。
  void overrideForTesting(Database db) => _db = db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'kakeibo.db');
    return openDatabase(
      path,
      version: kDbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await applyMigrations(db, 0, version);
        await seedDefaults(db);
      },
      onUpgrade: (db, oldV, newV) async {
        await applyMigrations(db, oldV, newV);
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
