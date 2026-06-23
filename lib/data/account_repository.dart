import 'package:sqflite/sqflite.dart';

import '../models/account.dart';

class AccountRepository {
  final Database db;
  AccountRepository(this.db);

  Future<List<Account>> all({bool includeArchived = false}) async {
    final rows = await db.query(
      'accounts',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(Account.fromMap).toList();
  }

  Future<int> insert(Account a) => db.insert('accounts', a.toMap());

  Future<int> update(Account a) => db.update(
        'accounts',
        a.toMap(),
        where: 'id = ?',
        whereArgs: [a.id],
      );

  Future<int> delete(int id) =>
      db.delete('accounts', where: 'id = ?', whereArgs: [id]);

  /// 口座の現在残高 = 初期残高 + 入金/振替先 - 出金/振替元。
  Future<int> balance(int accountId) async {
    final acc = await db.query('accounts',
        columns: ['initial_balance'], where: 'id = ?', whereArgs: [accountId], limit: 1);
    if (acc.isEmpty) return 0;
    final initial = (acc.first['initial_balance'] as int?) ?? 0;

    final inflow = await _sum(
      "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
      "WHERE (type='income' AND account_id=?) OR (type='transfer' AND to_account_id=?)",
      [accountId, accountId],
    );
    final outflow = await _sum(
      "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
      "WHERE (type='expense' AND account_id=?) OR (type='transfer' AND account_id=?)",
      [accountId, accountId],
    );
    return initial + inflow - outflow;
  }

  Future<int> _sum(String sql, List<Object?> args) async {
    final r = await db.rawQuery(sql, args);
    return (r.first['s'] as int?) ?? 0;
  }
}
