import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../models/account.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';
import '../../providers.dart';

/// 取引の追加・編集画面。保存/削除に成功したら true を pop で返す。
class TransactionEditScreen extends ConsumerStatefulWidget {
  final TxRecord? existing;
  const TransactionEditScreen({super.key, this.existing});

  @override
  ConsumerState<TransactionEditScreen> createState() =>
      _TransactionEditScreenState();
}

class _TransactionEditScreenState
    extends ConsumerState<TransactionEditScreen> {
  late TxType _type;
  late DateTime _date;
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  int? _categoryId;
  int? _accountId;
  int? _toAccountId;

  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? TxType.expense;
    _date = e != null ? Dates.parse(e.date) : DateTime.now();
    if (e != null) {
      _amountCtrl.text = e.amount.toString();
      _memoCtrl.text = e.memo ?? '';
      _categoryId = e.categoryId;
      _accountId = e.accountId;
      _toAccountId = e.toAccountId;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider);
    final accountsAsync = ref.watch(_accountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '取引を編集' : '取引を記録'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: accountsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
        data: (accounts) {
          _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;
          final catMap = cats.asData?.value ?? const <int, Category>{};
          final categoryList = catMap.values
              .where((c) => c.type == _type)
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TypeSelector(
                type: _type,
                onChanged: (t) => setState(() {
                  _type = t;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: '金額',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(Dates.displayDate(Dates.ymd(_date))),
                onTap: _pickDate,
              ),
              const Divider(),
              if (_type == TxType.transfer)
                _transferFields(accounts)
              else
                _categoryAndAccount(categoryList, accounts),
              const SizedBox(height: 16),
              TextField(
                controller: _memoCtrl,
                decoration: const InputDecoration(
                  labelText: 'メモ（任意）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_isEdit ? '更新' : '保存'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _categoryAndAccount(
      List<Category> categoryList, List<Account> accounts) {
    return Column(
      children: [
        DropdownButtonFormField<int>(
          initialValue: _categoryId,
          decoration: const InputDecoration(
            labelText: 'カテゴリ',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final c in categoryList)
              DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: 16),
        _accountDropdown(
          label: '口座',
          value: _accountId,
          accounts: accounts,
          onChanged: (v) => setState(() => _accountId = v),
        ),
      ],
    );
  }

  Widget _transferFields(List<Account> accounts) {
    return Column(
      children: [
        _accountDropdown(
          label: '振替元',
          value: _accountId,
          accounts: accounts,
          onChanged: (v) => setState(() => _accountId = v),
        ),
        const SizedBox(height: 16),
        _accountDropdown(
          label: '振替先',
          value: _toAccountId,
          accounts: accounts,
          onChanged: (v) => setState(() => _toAccountId = v),
        ),
      ],
    );
  }

  Widget _accountDropdown({
    required String label,
    required int? value,
    required List<Account> accounts,
    required ValueChanged<int?> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final a in accounts)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
      onChanged: onChanged,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = Money.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _snack('金額を正しく入力してください');
      return;
    }
    if (_accountId == null) {
      _snack('口座を選択してください');
      return;
    }
    if (_type == TxType.transfer) {
      if (_toAccountId == null || _toAccountId == _accountId) {
        _snack('振替先に別の口座を選択してください');
        return;
      }
    } else if (_categoryId == null) {
      _snack('カテゴリを選択してください');
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(transactionRepoProvider);
    final record = TxRecord(
      id: widget.existing?.id,
      type: _type,
      amount: amount,
      date: Dates.ymd(_date),
      categoryId: _type == TxType.transfer ? null : _categoryId,
      accountId: _accountId!,
      toAccountId: _type == TxType.transfer ? _toAccountId : null,
      memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ??
          DateTime.now().millisecondsSinceEpoch,
    );
    if (_isEdit) {
      await repo.update(record);
    } else {
      await repo.insert(record);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除しますか？'),
        content: const Text('この取引を削除します。元に戻せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    await ref.read(transactionRepoProvider).delete(widget.existing!.id!);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 口座一覧（編集画面ローカルで利用）。
final _accountsProvider = FutureProvider<List<Account>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.watch(accountRepoProvider).all();
});

class _TypeSelector extends StatelessWidget {
  final TxType type;
  final ValueChanged<TxType> onChanged;
  const _TypeSelector({required this.type, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TxType>(
      segments: const [
        ButtonSegment(
            value: TxType.expense,
            label: Text('支出'),
            icon: Icon(Icons.remove)),
        ButtonSegment(
            value: TxType.income,
            label: Text('収入'),
            icon: Icon(Icons.add)),
        ButtonSegment(
            value: TxType.transfer,
            label: Text('振替'),
            icon: Icon(Icons.swap_horiz)),
      ],
      selected: {type},
      onSelectionChanged: (s) => onChanged(s.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: switch (type) {
          TxType.expense => TxColors.expense.withValues(alpha: 0.15),
          TxType.income => TxColors.income.withValues(alpha: 0.15),
          TxType.transfer => Colors.blueGrey.withValues(alpha: 0.15),
        },
      ),
    );
  }
}
