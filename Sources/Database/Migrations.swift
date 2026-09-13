import Foundation

extension Database {
    /// 現在のスキーマバージョン。変更時はインクリメントして差分DDLを足す。
    static let schemaVersion: Int32 = 6

    func migrateIfNeeded() throws {
        let current = userVersion()
        guard current < Database.schemaVersion else { return }

        if current < 1 {
            try applyV1()
            try seedDefaults()
        }
        if current < 2 {
            try applyV2()
        }
        if current < 3 {
            try applyV3()
        }
        if current < 4 {
            try applyV4()
        }
        if current < 5 {
            try applyV5()
        }
        if current < 6 {
            try applyV6()
        }
        // 以降のバージョンはここに分岐を追加する。

        try setUserVersion(Database.schemaVersion)
    }

    /// DDL を実行し、失敗したらマイグレーションを中断する。
    /// 握り潰すと中途半端なスキーマのまま動き続けてしまうため必ず投げる。
    private func migrate(_ version: Int32, _ sql: String) throws {
        guard exec(sql) else {
            throw DatabaseError.migrationFailed(version: version,
                                                detail: lastErrorMessage() ?? "unknown")
        }
    }

    private func migrate(_ version: Int32, _ sql: String, _ args: [SQLValue]) throws {
        let result = run(sql, args)
        guard result.ok else {
            throw DatabaseError.migrationFailed(version: version,
                                                detail: result.message ?? "unknown")
        }
    }

    private func userVersion() -> Int32 {
        Int32(query("PRAGMA user_version").first?.int("user_version") ?? 0)
    }

    private func setUserVersion(_ v: Int32) throws {
        try migrate(v, "PRAGMA user_version = \(v)")
    }

    private func applyV1() throws {
        let ddl = [
            """
            CREATE TABLE accounts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              initial_balance INTEGER NOT NULL DEFAULT 0,
              sort_order INTEGER NOT NULL DEFAULT 0,
              archived INTEGER NOT NULL DEFAULT 0
            )
            """,
            """
            CREATE TABLE categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              parent_id INTEGER REFERENCES categories(id),
              icon TEXT,
              color INTEGER,
              sort_order INTEGER NOT NULL DEFAULT 0
            )
            """,
            """
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
            """,
            "CREATE INDEX idx_tx_date ON transactions(date)",
            "CREATE INDEX idx_tx_category ON transactions(category_id)",
            "CREATE INDEX idx_tx_account ON transactions(account_id)",
            """
            CREATE TABLE budgets (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              year_month TEXT NOT NULL,
              category_id INTEGER REFERENCES categories(id),
              amount INTEGER NOT NULL,
              UNIQUE(year_month, category_id)
            )
            """,
            """
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
            """,
        ]
        for stmt in ddl { try migrate(1, stmt) }
    }

    /// v2: 定期取引ルール。
    private func applyV2() throws {
        try migrate(2,
            """
            CREATE TABLE recurring_rules (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT NOT NULL,
              amount INTEGER NOT NULL,
              category_id INTEGER REFERENCES categories(id),
              account_id INTEGER NOT NULL REFERENCES accounts(id),
              to_account_id INTEGER REFERENCES accounts(id),
              memo TEXT,
              frequency TEXT NOT NULL,
              interval INTEGER NOT NULL DEFAULT 1,
              next_date TEXT NOT NULL,
              end_date TEXT
            )
            """)
    }

    /// v3: 口座に親子関係（仮想口座 / サブ口座）を追加。
    private func applyV3() throws {
        try migrate(3, "ALTER TABLE accounts ADD COLUMN parent_id INTEGER REFERENCES accounts(id)")
    }

    /// v4: クレジットカードの締め日・支払日・引き落とし元口座を追加。
    private func applyV4() throws {
        try migrate(4, "ALTER TABLE accounts ADD COLUMN closing_day INTEGER")
        try migrate(4, "ALTER TABLE accounts ADD COLUMN payment_day INTEGER")
        try migrate(4, "ALTER TABLE accounts ADD COLUMN payment_month_offset INTEGER NOT NULL DEFAULT 1")
        try migrate(4, "ALTER TABLE accounts ADD COLUMN payment_account_id INTEGER REFERENCES accounts(id)")
    }

    /// v5: 振替先のインデックス。残高計算が to_account_id で全表走査していたため。
    private func applyV5() throws {
        try migrate(5, "CREATE INDEX IF NOT EXISTS idx_tx_to_account ON transactions(to_account_id)")
    }

    /// v6: よく使う小分類を用意する。取引は小分類まで選ぶ運用にしたため、
    /// どの大分類にも最低ひとつは小分類がある状態にしておく。
    /// すでに自分で小分類を作っている大分類には手を触れない。
    private func applyV6() throws {
        for group in Database.defaultSubcategories {
            let parent = query(
                "SELECT id, color FROM categories WHERE name=? AND type=? AND parent_id IS NULL",
                [.text(group.parent), .text(group.type)]).first
            // ユーザーが大分類を消していたら何もしない
            guard let parentId = parent?.int64("id") else { continue }

            let existing = query("SELECT COUNT(*) AS c FROM categories WHERE parent_id=?",
                                 [.int(parentId)]).first?.int("c") ?? 0
            guard existing == 0 else { continue }

            for (index, child) in group.children.enumerated() {
                try migrate(6,
                    "INSERT INTO categories(name, type, parent_id, color, sort_order) VALUES(?,?,?,?,?)",
                    [.text(child), .text(group.type), .int(parentId),
                     SQLValue(parent?.int("color")), .int(Int64(index))])
            }
        }
    }

    /// 既定の小分類。親の名前で結び付ける。
    private static let defaultSubcategories:
        [(parent: String, type: String, children: [String])] = [
        ("食費",   "expense", ["食料品", "外食", "カフェ・間食"]),
        ("日用品", "expense", ["消耗品", "衣類", "家具・家電"]),
        ("交通費", "expense", ["電車・バス", "タクシー", "ガソリン"]),
        ("住居費", "expense", ["家賃・ローン", "管理費", "修繕"]),
        ("光熱費", "expense", ["電気", "ガス", "水道"]),
        ("通信費", "expense", ["携帯", "インターネット"]),
        ("娯楽",   "expense", ["趣味", "旅行", "サブスク"]),
        ("医療",   "expense", ["診察・薬", "保険"]),
        ("交際費", "expense", ["飲み会", "プレゼント"]),
        ("その他", "expense", ["その他"]),
        ("給与",   "income",  ["給料", "手当"]),
        ("賞与",   "income",  ["賞与"]),
        ("副収入", "income",  ["副業", "臨時収入"]),
        ("その他", "income",  ["その他"]),
    ]

    /// デフォルトカテゴリ・現金口座・既定設定を投入する。
    private func seedDefaults() throws {
        try migrate(1,
            "INSERT INTO accounts(name, type, initial_balance, sort_order, archived) VALUES(?,?,?,?,?)",
            [.text("現金"), .text("cash"), .int(0), .int(0), .int(0)])

        let expenseCats: [(String, Int)] = [
            ("食費", 0xFFE57373), ("日用品", 0xFF9575CD), ("交通費", 0xFF64B5F6),
            ("住居費", 0xFF4DB6AC), ("光熱費", 0xFFFFB74D), ("通信費", 0xFF4FC3F7),
            ("娯楽", 0xFFF06292), ("医療", 0xFF81C784), ("交際費", 0xFFBA68C8),
            ("その他", 0xFF90A4AE),
        ]
        let incomeCats: [(String, Int)] = [
            ("給与", 0xFF66BB6A), ("賞与", 0xFF26A69A),
            ("副収入", 0xFF42A5F5), ("その他", 0xFF90A4AE),
        ]

        for (i, c) in expenseCats.enumerated() {
            try migrate(1, "INSERT INTO categories(name, type, color, sort_order) VALUES(?,?,?,?)",
                        [.text(c.0), .text("expense"), .int(Int64(c.1)), .int(Int64(i))])
        }
        for (i, c) in incomeCats.enumerated() {
            try migrate(1, "INSERT INTO categories(name, type, color, sort_order) VALUES(?,?,?,?)",
                        [.text(c.0), .text("income"), .int(Int64(c.1)), .int(Int64(i))])
        }

        for (k, v) in [("currency", "JPY"), ("theme", "system"), ("month_start_day", "1")] {
            try migrate(1, "INSERT INTO settings(key, value) VALUES(?,?)", [.text(k), .text(v)])
        }
    }
}
