import Foundation

extension Database {
    /// 現在のスキーマバージョン。変更時はインクリメントして差分DDLを足す。
    static let schemaVersion: Int32 = 3

    func migrateIfNeeded() throws {
        let current = userVersion()
        guard current < Database.schemaVersion else { return }

        if current < 1 {
            applyV1()
            seedDefaults()
        }
        if current < 2 {
            applyV2()
        }
        if current < 3 {
            applyV3()
        }
        // 以降のバージョンはここに分岐を追加する。

        setUserVersion(Database.schemaVersion)
    }

    private func userVersion() -> Int32 {
        Int32(query("PRAGMA user_version").first?.int("user_version") ?? 0)
    }

    private func setUserVersion(_ v: Int32) {
        exec("PRAGMA user_version = \(v)")
    }

    private func applyV1() {
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
        for stmt in ddl { exec(stmt) }
    }

    /// v2: 定期取引ルール。
    private func applyV2() {
        exec(
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
    private func applyV3() {
        exec("ALTER TABLE accounts ADD COLUMN parent_id INTEGER REFERENCES accounts(id)")
    }

    /// デフォルトカテゴリ・現金口座・既定設定を投入する。
    private func seedDefaults() {
        run("INSERT INTO accounts(name, type, initial_balance, sort_order, archived) VALUES(?,?,?,?,?)",
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
            run("INSERT INTO categories(name, type, color, sort_order) VALUES(?,?,?,?)",
                [.text(c.0), .text("expense"), .int(Int64(c.1)), .int(Int64(i))])
        }
        for (i, c) in incomeCats.enumerated() {
            run("INSERT INTO categories(name, type, color, sort_order) VALUES(?,?,?,?)",
                [.text(c.0), .text("income"), .int(Int64(c.1)), .int(Int64(i))])
        }

        for (k, v) in [("currency", "JPY"), ("theme", "system"), ("month_start_day", "1")] {
            run("INSERT INTO settings(key, value) VALUES(?,?)", [.text(k), .text(v)])
        }
    }
}
