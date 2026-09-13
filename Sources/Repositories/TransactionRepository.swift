import Foundation

/// 期間の収支サマリ。
struct MonthlySummary {
    var income: Int
    var expense: Int
    var net: Int { income - expense }
    static let empty = MonthlySummary(income: 0, expense: 0)
}

struct TransactionRepository {
    let db: Database

    /// 期間指定で取引を取得（date は YYYY-MM-DD、両端含む）。
    func range(start: String? = nil,
               end: String? = nil,
               categoryId: Int64? = nil,
               keyword: String? = nil) -> [TxRecord] {
        var clauses: [String] = []
        var args: [SQLValue] = []
        if let start { clauses.append("date >= ?"); args.append(.text(start)) }
        if let end { clauses.append("date <= ?"); args.append(.text(end)) }
        if let categoryId { clauses.append("category_id = ?"); args.append(.int(categoryId)) }
        if let keyword, !keyword.isEmpty {
            clauses.append("memo LIKE ?"); args.append(.text("%\(keyword)%"))
        }
        let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = "SELECT * FROM transactions \(whereSQL) ORDER BY date DESC, created_at DESC"
        return db.query(sql, args).map(Self.map)
    }

    @discardableResult
    func insert(_ t: TxRecord) -> Bool {
        db.run(
            """
            INSERT INTO transactions(type, amount, date, category_id, account_id, to_account_id, memo, created_at)
            VALUES(?,?,?,?,?,?,?,?)
            """,
            [.text(t.type.rawValue), .int(Int64(t.amount)), .text(t.date),
             SQLValue(t.categoryId), .int(t.accountId), SQLValue(t.toAccountId),
             SQLValue(t.memo), .int(t.createdAt)]).ok
    }

    @discardableResult
    func update(_ t: TxRecord) -> Bool {
        guard let id = t.id else { return false }
        return db.run(
            """
            UPDATE transactions SET type=?, amount=?, date=?, category_id=?, account_id=?, to_account_id=?, memo=?
            WHERE id=?
            """,
            [.text(t.type.rawValue), .int(Int64(t.amount)), .text(t.date),
             SQLValue(t.categoryId), .int(t.accountId), SQLValue(t.toAccountId),
             SQLValue(t.memo), .int(id)]).ok
    }

    @discardableResult
    func delete(id: Int64) -> Bool {
        db.run("DELETE FROM transactions WHERE id=?", [.int(id)]).ok
    }

    /// [start, end] の収入・支出合計。
    func summary(start: String, end: String) -> MonthlySummary {
        let rows = db.query(
            """
            SELECT type, COALESCE(SUM(amount),0) AS s FROM transactions
            WHERE date >= ? AND date <= ? AND type IN ('income','expense')
            GROUP BY type
            """, [.text(start), .text(end)])
        var income = 0, expense = 0
        for r in rows {
            let s = r.int("s") ?? 0
            if r.string("type") == "income" { income = s }
            if r.string("type") == "expense" { expense = s }
        }
        return MonthlySummary(income: income, expense: expense)
    }

    /// 期間内のカテゴリ別支出合計（円グラフ用）。categoryId -> 金額。
    func expenseByCategory(start: String, end: String) -> [Int64: Int] {
        let rows = db.query(
            """
            SELECT category_id, COALESCE(SUM(amount),0) AS s FROM transactions
            WHERE date >= ? AND date <= ? AND type='expense' AND category_id IS NOT NULL
            GROUP BY category_id ORDER BY s DESC
            """, [.text(start), .text(end)])
        var result: [Int64: Int] = [:]
        for r in rows {
            if let cid = r.int64("category_id") { result[cid] = r.int("s") ?? 0 }
        }
        return result
    }

    /// カテゴリを参照する取引数。削除可否の判定に使う。
    func countByCategory(id: Int64) -> Int {
        db.query("SELECT COUNT(*) AS c FROM transactions WHERE category_id = ?", [.int(id)])
            .first?.int("c") ?? 0
    }

    /// 指定口座・期間内の正味利用額（支出 − 収入）。クレカ請求額の算出用。
    /// カードへの返金を「収入」で記録した場合に請求額から差し引かれる。
    func netUsage(accountId: Int64, start: String, end: String) -> Int {
        db.query(
            """
            SELECT COALESCE(SUM(CASE WHEN type='expense' THEN amount END),0)
                 - COALESCE(SUM(CASE WHEN type='income' THEN amount END),0) AS s
            FROM transactions
            WHERE account_id=? AND date >= ? AND date <= ? AND type IN ('expense','income')
            """, [.int(accountId), .text(start), .text(end)]
        ).first?.int("s") ?? 0
    }

    /// 指定日より後に、その口座へ入ってきた振替の合計（クレカの支払済額の算出用）。
    func transferInSum(accountId: Int64, since: String) -> Int {
        db.query(
            """
            SELECT COALESCE(SUM(amount),0) AS s FROM transactions
            WHERE type='transfer' AND to_account_id=? AND date > ?
            """, [.int(accountId), .text(since)]
        ).first?.int("s") ?? 0
    }

    /// 口座を参照する取引数（出金元/振替先の両方）。
    func countByAccount(id: Int64) -> Int {
        db.query(
            "SELECT COUNT(*) AS c FROM transactions WHERE account_id = ? OR to_account_id = ?",
            [.int(id), .int(id)]
        ).first?.int("c") ?? 0
    }

    static func map(_ r: Row) -> TxRecord {
        TxRecord(
            id: r.int64("id"),
            type: TxType(rawValue: r.string("type") ?? "expense") ?? .expense,
            amount: r.int("amount") ?? 0,
            date: r.string("date") ?? "",
            categoryId: r.int64("category_id"),
            accountId: r.int64("account_id") ?? 0,
            toAccountId: r.int64("to_account_id"),
            memo: r.string("memo"),
            createdAt: r.int64("created_at") ?? 0
        )
    }
}
