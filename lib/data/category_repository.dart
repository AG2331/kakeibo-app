import 'package:sqflite/sqflite.dart';

import '../models/category.dart';

class CategoryRepository {
  final Database db;
  CategoryRepository(this.db);

  Future<List<Category>> all({TxType? type}) async {
    final rows = await db.query(
      'categories',
      where: type != null ? 'type = ?' : null,
      whereArgs: type != null ? [type.name] : null,
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<Category?> byId(int id) async {
    final rows = await db.query('categories', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Category.fromMap(rows.first);
  }

  Future<int> insert(Category c) => db.insert('categories', c.toMap());

  Future<int> update(Category c) => db.update(
        'categories',
        c.toMap(),
        where: 'id = ?',
        whereArgs: [c.id],
      );

  Future<int> delete(int id) =>
      db.delete('categories', where: 'id = ?', whereArgs: [id]);
}
