enum AccountType {
  cash,
  bank,
  emoney,
  credit;

  static AccountType fromString(String s) => AccountType.values
      .firstWhere((e) => e.name == s, orElse: () => AccountType.cash);

  String get label => switch (this) {
        AccountType.cash => '現金',
        AccountType.bank => '銀行',
        AccountType.emoney => '電子マネー',
        AccountType.credit => 'クレジット',
      };
}

class Account {
  final int? id;
  final String name;
  final AccountType type;
  final int initialBalance;
  final int sortOrder;
  final bool archived;

  const Account({
    this.id,
    required this.name,
    required this.type,
    this.initialBalance = 0,
    this.sortOrder = 0,
    this.archived = false,
  });

  Account copyWith({
    int? id,
    String? name,
    AccountType? type,
    int? initialBalance,
    int? sortOrder,
    bool? archived,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      initialBalance: initialBalance ?? this.initialBalance,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type.name,
        'initial_balance': initialBalance,
        'sort_order': sortOrder,
        'archived': archived ? 1 : 0,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: AccountType.fromString(m['type'] as String),
        initialBalance: (m['initial_balance'] as int?) ?? 0,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        archived: ((m['archived'] as int?) ?? 0) == 1,
      );
}
