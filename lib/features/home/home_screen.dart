import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../data/transaction_repository.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers.dart';
import '../transaction_edit/transaction_edit_screen.dart';

/// ホーム: 当月サマリ + 取引一覧。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final summary = ref.watch(monthlySummaryProvider);
    final txs = ref.watch(monthTransactionsProvider);
    final cats = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('${month.year}年${month.month}月'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _shiftMonth(ref, -1),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftMonth(ref, 1),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(refreshTickProvider.notifier).state++,
        child: ListView(
          children: [
            summary.when(
              data: (s) => _SummaryCard(summary: s),
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorTile(message: '$e'),
            ),
            const Divider(height: 1),
            txs.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: Text('この月の記録はまだありません')),
                  );
                }
                final catMap = cats.asData?.value ?? const <int, Category>{};
                return _TransactionList(items: list, categories: catMap);
              },
              loading: () => const SizedBox.shrink(),
              error: (e, _) => _ErrorTile(message: '$e'),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('記録'),
      ),
    );
  }

  void _shiftMonth(WidgetRef ref, int delta) {
    final m = ref.read(selectedMonthProvider);
    ref.read(selectedMonthProvider.notifier).state =
        DateTime(m.year, m.month + delta, 1);
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      {TxRecord? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransactionEditScreen(existing: existing),
      ),
    );
    if (saved == true) {
      ref.read(refreshTickProvider.notifier).state++;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final MonthlySummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryItem(
                    label: '収入',
                    amount: summary.income,
                    color: TxColors.income,
                  ),
                  _SummaryItem(
                    label: '支出',
                    amount: summary.expense,
                    color: TxColors.expense,
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('収支', style: TextStyle(fontSize: 16)),
                  Text(
                    Money.format(summary.net),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: summary.net >= 0
                          ? TxColors.income
                          : TxColors.expense,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final int amount;
  final Color color;
  const _SummaryItem(
      {required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          Money.format(amount),
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

class _TransactionList extends ConsumerWidget {
  final List<TxRecord> items;
  final Map<int, Category> categories;
  const _TransactionList({required this.items, required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 日付ごとにグルーピング（items は date DESC 済み）。
    final groups = <String, List<TxRecord>>{};
    for (final t in items) {
      groups.putIfAbsent(t.date, () => []).add(t);
    }

    final children = <Widget>[];
    groups.forEach((date, list) {
      final dayNet = list.fold<int>(0, (a, t) => a + t.signedAmount);
      children.add(
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(Dates.displayDate(date),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(Money.format(dayNet),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
      for (final t in list) {
        children.add(_TxTile(tx: t, categories: categories));
      }
    });

    return Column(children: children);
  }
}

class _TxTile extends ConsumerWidget {
  final TxRecord tx;
  final Map<int, Category> categories;
  const _TxTile({required this.tx, required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = tx.categoryId != null ? categories[tx.categoryId] : null;
    final isExpense = tx.type == TxType.expense;
    final isTransfer = tx.type == TxType.transfer;
    final color = isTransfer
        ? Colors.blueGrey
        : (isExpense ? TxColors.expense : TxColors.income);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(cat?.color ?? 0xFF90A4AE).withValues(alpha: 0.2),
        child: Icon(
          isTransfer ? Icons.swap_horiz : Icons.label_outline,
          color: Color(cat?.color ?? 0xFF90A4AE),
          size: 20,
        ),
      ),
      title: Text(isTransfer ? '振替' : (cat?.name ?? '未分類')),
      subtitle: (tx.memo != null && tx.memo!.isNotEmpty)
          ? Text(tx.memo!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Text(
        isExpense ? '-${Money.format(tx.amount)}' : Money.format(tx.amount),
        style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 15),
      ),
      onTap: () => _edit(context, ref),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransactionEditScreen(existing: tx),
      ),
    );
    if (saved == true) {
      ref.read(refreshTickProvider.notifier).state++;
    }
  }
}

class _ErrorTile extends StatelessWidget {
  final String message;
  const _ErrorTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text('エラー: $message',
          style: const TextStyle(color: Colors.red)),
    );
  }
}
