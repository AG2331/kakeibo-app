import 'category.dart';

/// 1件の取引。amount は常に正の整数（最小通貨単位）。
class TxRecord {
  final int? id;
  final TxType type;
  final int amount;
  final String date; // YYYY-MM-DD
  final int? categoryId; // transfer 時は null
  final int accountId;
  final int? toAccountId; // transfer 時のみ
  final String? memo;
  final int createdAt; // epoch ms

  const TxRecord({
    this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.categoryId,
    required this.accountId,
    this.toAccountId,
    this.memo,
    required this.createdAt,
  });

  /// 収支差への寄与額（収入:+ / 支出:- / 振替:0）。
  int get signedAmount => switch (type) {
        TxType.income => amount,
        TxType.expense => -amount,
        TxType.transfer => 0,
      };

  TxRecord copyWith({
    int? id,
    TxType? type,
    int? amount,
    String? date,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    String? memo,
    int? createdAt,
  }) {
    return TxRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      toAccountId: toAccountId ?? this.toAccountId,
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type.name,
        'amount': amount,
        'date': date,
        'category_id': categoryId,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'memo': memo,
        'created_at': createdAt,
      };

  factory TxRecord.fromMap(Map<String, Object?> m) => TxRecord(
        id: m['id'] as int?,
        type: TxType.fromString(m['type'] as String),
        amount: m['amount'] as int,
        date: m['date'] as String,
        categoryId: m['category_id'] as int?,
        accountId: m['account_id'] as int,
        toAccountId: m['to_account_id'] as int?,
        memo: m['memo'] as String?,
        createdAt: m['created_at'] as int,
      );
}
