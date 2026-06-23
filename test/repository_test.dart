import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kakeibo_app/core/db/migrations.dart';
import 'package:kakeibo_app/data/account_repository.dart';
import 'package:kakeibo_app/data/category_repository.dart';
import 'package:kakeibo_app/data/transaction_repository.dart';
import 'package:kakeibo_app/models/account.dart';
import 'package:kakeibo_app/models/category.dart';
import 'package:kakeibo_app/models/transaction.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: kDbVersion,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) async {
          await applyMigrations(d, 0, v);
          await seedDefaults(d);
        },
      ),
    );
  });

  tearDown(() async => db.close());

  test('デフォルトデータが投入される', () async {
    final cats = await CategoryRepository(db).all();
    expect(cats.where((c) => c.type == TxType.expense), isNotEmpty);
    expect(cats.where((c) => c.type == TxType.income), isNotEmpty);

    final accounts = await AccountRepository(db).all();
    expect(accounts.length, 1);
    expect(accounts.first.name, '現金');
  });

  test('取引の追加と当月サマリ集計', () async {
    final txRepo = TransactionRepository(db);
    final acc = (await AccountRepository(db).all()).first;
    final expenseCat =
        (await CategoryRepository(db).all(type: TxType.expense)).first;
    final incomeCat =
        (await CategoryRepository(db).all(type: TxType.income)).first;
    final now = DateTime.now().millisecondsSinceEpoch;

    await txRepo.insert(TxRecord(
      type: TxType.expense,
      amount: 1200,
      date: '2026-06-10',
      categoryId: expenseCat.id,
      accountId: acc.id!,
      createdAt: now,
    ));
    await txRepo.insert(TxRecord(
      type: TxType.income,
      amount: 300000,
      date: '2026-06-25',
      categoryId: incomeCat.id,
      accountId: acc.id!,
      createdAt: now,
    ));
    // 範囲外（翌月）は集計に含まれない
    await txRepo.insert(TxRecord(
      type: TxType.expense,
      amount: 9999,
      date: '2026-07-01',
      categoryId: expenseCat.id,
      accountId: acc.id!,
      createdAt: now,
    ));

    final s = await txRepo.summary('2026-06-01', '2026-06-30');
    expect(s.income, 300000);
    expect(s.expense, 1200);
    expect(s.net, 298800);

    final list = await txRepo.range(start: '2026-06-01', end: '2026-06-30');
    expect(list.length, 2);
    // date DESC 順
    expect(list.first.date, '2026-06-25');
  });

  test('振替は収支に計上されず残高に反映される', () async {
    final accRepo = AccountRepository(db);
    final cash = (await accRepo.all()).first;
    final bankId = await accRepo.insert(const Account(
      name: '銀行',
      type: AccountType.bank,
      initialBalance: 50000,
    ));

    final txRepo = TransactionRepository(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    await txRepo.insert(TxRecord(
      type: TxType.transfer,
      amount: 10000,
      date: '2026-06-15',
      accountId: bankId, // 振替元
      toAccountId: cash.id,
      createdAt: now,
    ));

    final s = await txRepo.summary('2026-06-01', '2026-06-30');
    expect(s.income, 0);
    expect(s.expense, 0);

    expect(await accRepo.balance(bankId), 40000); // 50000 - 10000
    expect(await accRepo.balance(cash.id!), 10000); // 0 + 10000
  });

  test('取引の更新と削除', () async {
    final txRepo = TransactionRepository(db);
    final acc = (await AccountRepository(db).all()).first;
    final cat =
        (await CategoryRepository(db).all(type: TxType.expense)).first;
    final now = DateTime.now().millisecondsSinceEpoch;

    final id = await txRepo.insert(TxRecord(
      type: TxType.expense,
      amount: 500,
      date: '2026-06-05',
      categoryId: cat.id,
      accountId: acc.id!,
      createdAt: now,
    ));

    final loaded =
        (await txRepo.range(start: '2026-06-01', end: '2026-06-30')).first;
    await txRepo.update(loaded.copyWith(amount: 800));
    var s = await txRepo.summary('2026-06-01', '2026-06-30');
    expect(s.expense, 800);

    await txRepo.delete(id);
    s = await txRepo.summary('2026-06-01', '2026-06-30');
    expect(s.expense, 0);
  });
}
