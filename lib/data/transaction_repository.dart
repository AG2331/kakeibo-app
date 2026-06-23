import 'package:sqflite/sqflite.dart';

import '../models/transaction.dart';

/// 当月などの収支サマリ。
class MonthlySummary {
  final int income;
  final int expense;
  const MonthlySummary({required this.income, required this.expense});

  int get net => income - expense;

  static const empty = MonthlySummary(income: 0, expense: 0);
}

class TransactionRepository {
  final Database db;
  TransactionRepository(this.db);

  /// 期間指定で取引を取得（date は YYYY-MM-DD、両端含む）。
  Future<List<TxRecord>> range({
    String? start,
    String? end,
    int? categoryId,
    String? keyword,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (start != null) {
      where.add('date >= ?');
      args.add(start);
    }
    if (end != null) {
      where.add('date <= ?');
      args.add(end);
    }
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    if (keyword != null && keyword.isNotEmpty) {
      where.add('memo LIKE ?');
      args.add('%$keyword%');
    }
    final rows = await db.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(TxRecord.fromMap).toList();
  }

  Future<int> insert(TxRecord t) => db.insert('transactions', t.toMap());

  Future<int> update(TxRecord t) => db.update(
        'transactions',
        t.toMap(),
        where: 'id = ?',
        whereArgs: [t.id],
      );

  Future<int> delete(int id) =>
      db.delete('transactions', where: 'id = ?', whereArgs: [id]);

  /// [start, end]（YYYY-MM-DD）の収入・支出合計。
  Future<MonthlySummary> summary(String start, String end) async {
    final rows = await db.rawQuery(
      "SELECT type, COALESCE(SUM(amount),0) AS s FROM transactions "
      "WHERE date >= ? AND date <= ? AND type IN ('income','expense') "
      "GROUP BY type",
      [start, end],
    );
    var income = 0, expense = 0;
    for (final r in rows) {
      final s = (r['s'] as int?) ?? 0;
      if (r['type'] == 'income') income = s;
      if (r['type'] == 'expense') expense = s;
    }
    return MonthlySummary(income: income, expense: expense);
  }

  /// 期間内のカテゴリ別支出合計（円グラフ用）。category_id -> 金額。
  Future<Map<int, int>> expenseByCategory(String start, String end) async {
    final rows = await db.rawQuery(
      "SELECT category_id, COALESCE(SUM(amount),0) AS s FROM transactions "
      "WHERE date >= ? AND date <= ? AND type='expense' AND category_id IS NOT NULL "
      "GROUP BY category_id ORDER BY s DESC",
      [start, end],
    );
    return {
      for (final r in rows) (r['category_id'] as int): (r['s'] as int?) ?? 0,
    };
  }
}
