import 'package:sqflite/sqflite.dart';

/// スキーマDDLをバージョン別に管理する。
/// バージョンを上げる際は [migrations] に新しいキーで差分DDLを追加する。
const int kDbVersion = 1;

/// version -> その版へ上げる際に実行するDDL群。
const Map<int, List<String>> migrations = {
  1: [
    '''
    CREATE TABLE accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      initial_balance INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      parent_id INTEGER REFERENCES categories(id),
      icon TEXT,
      color INTEGER,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      date TEXT NOT NULL,
      category_id INTEGER REFERENCES categories(id),
      account_id INTEGER NOT NULL REFERENCES accounts(id),
      to_account_id INTEGER REFERENCES accounts(id),
      memo TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_tx_date ON transactions(date)',
    'CREATE INDEX idx_tx_category ON transactions(category_id)',
    'CREATE INDEX idx_tx_account ON transactions(account_id)',
    '''
    CREATE TABLE budgets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      year_month TEXT NOT NULL,
      category_id INTEGER REFERENCES categories(id),
      amount INTEGER NOT NULL,
      UNIQUE(year_month, category_id)
    )
    ''',
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ],
};

/// 指定範囲のマイグレーションを順に適用する（(from, to]）。
Future<void> applyMigrations(Database db, int from, int to) async {
  for (var v = from + 1; v <= to; v++) {
    final ddl = migrations[v];
    if (ddl == null) continue;
    for (final stmt in ddl) {
      await db.execute(stmt);
    }
  }
}

/// 初期データ（デフォルトカテゴリ・現金口座・既定設定）を投入する。
Future<void> seedDefaults(Database db) async {
  final now = DateTime.now().millisecondsSinceEpoch;

  await db.insert('accounts', {
    'name': '現金',
    'type': 'cash',
    'initial_balance': 0,
    'sort_order': 0,
    'archived': 0,
  });

  const expenseCats = [
    ['食費', 0xFFE57373],
    ['日用品', 0xFF9575CD],
    ['交通費', 0xFF64B5F6],
    ['住居費', 0xFF4DB6AC],
    ['光熱費', 0xFFFFB74D],
    ['通信費', 0xFF4FC3F7],
    ['娯楽', 0xFFF06292],
    ['医療', 0xFF81C784],
    ['交際費', 0xFFBA68C8],
    ['その他', 0xFF90A4AE],
  ];
  const incomeCats = [
    ['給与', 0xFF66BB6A],
    ['賞与', 0xFF26A69A],
    ['副収入', 0xFF42A5F5],
    ['その他', 0xFF90A4AE],
  ];

  var order = 0;
  for (final c in expenseCats) {
    await db.insert('categories', {
      'name': c[0],
      'type': 'expense',
      'color': c[1],
      'sort_order': order++,
    });
  }
  order = 0;
  for (final c in incomeCats) {
    await db.insert('categories', {
      'name': c[0],
      'type': 'income',
      'color': c[1],
      'sort_order': order++,
    });
  }

  await db.insert('settings', {'key': 'currency', 'value': 'JPY'});
  await db.insert('settings', {'key': 'theme', 'value': 'system'});
  await db.insert('settings', {'key': 'month_start_day', 'value': '1'});
  // seeded_at は将来の判定用
  await db.insert('settings', {'key': 'seeded_at', 'value': '$now'});
}
