import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'core/utils/dates.dart';
import 'data/account_repository.dart';
import 'data/category_repository.dart';
import 'data/transaction_repository.dart';
import 'models/category.dart';
import 'models/transaction.dart';

/// 開いた Database を供給する。main で overrideWith して初期化する。
final databaseProvider = Provider<Database>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in main()');
});

final transactionRepoProvider = Provider<TransactionRepository>(
    (ref) => TransactionRepository(ref.watch(databaseProvider)));
final categoryRepoProvider = Provider<CategoryRepository>(
    (ref) => CategoryRepository(ref.watch(databaseProvider)));
final accountRepoProvider = Provider<AccountRepository>(
    (ref) => AccountRepository(ref.watch(databaseProvider)));

/// ホームで表示中の月（その月の任意日をアンカーに持つ）。
final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

/// 取引が変化したら集計・一覧を作り直すためのトリガ。
final refreshTickProvider = StateProvider<int>((ref) => 0);

/// カテゴリ id -> Category の参照テーブル。
final categoriesProvider = FutureProvider<Map<int, Category>>((ref) async {
  ref.watch(refreshTickProvider);
  final cats = await ref.watch(categoryRepoProvider).all();
  return {for (final c in cats) if (c.id != null) c.id!: c};
});

/// 当月（選択中の月）のサマリ。
final monthlySummaryProvider = FutureProvider<MonthlySummary>((ref) async {
  ref.watch(refreshTickProvider);
  final month = ref.watch(selectedMonthProvider);
  final (start, end) = Dates.monthRange(month);
  return ref.watch(transactionRepoProvider).summary(start, end);
});

/// 当月（選択中の月）の取引一覧。
final monthTransactionsProvider = FutureProvider<List<TxRecord>>((ref) async {
  ref.watch(refreshTickProvider);
  final month = ref.watch(selectedMonthProvider);
  final (start, end) = Dates.monthRange(month);
  return ref.watch(transactionRepoProvider).range(start: start, end: end);
});
