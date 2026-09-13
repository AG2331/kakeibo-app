import Foundation

struct AccountRepository {
    let db: Database

    func all(includeArchived: Bool = false) -> [Account] {
        let sql = includeArchived
            ? "SELECT * FROM accounts ORDER BY sort_order ASC, id ASC"
            : "SELECT * FROM accounts WHERE archived = 0 ORDER BY sort_order ASC, id ASC"
        return db.query(sql).map(Self.map)
    }

    @discardableResult
    func insert(_ a: Account) -> Bool {
        db.run(
            """
            INSERT INTO accounts(
              name, type, initial_balance, sort_order, archived, parent_id,
              closing_day, payment_day, payment_month_offset, payment_account_id
            ) VALUES(?,?,?,?,?,?,?,?,?,?)
            """,
            [.text(a.name), .text(a.type.rawValue), .int(Int64(a.initialBalance)),
             .int(Int64(a.sortOrder)), .int(a.archived ? 1 : 0), SQLValue(a.parentId),
             SQLValue(a.closingDay), SQLValue(a.paymentDay), .int(Int64(a.paymentMonthOffset)),
             SQLValue(a.paymentAccountId)]).ok
    }

    @discardableResult
    func update(_ a: Account) -> Bool {
        guard let id = a.id else { return false }
        return db.run(
            """
            UPDATE accounts SET
              name=?, type=?, initial_balance=?, sort_order=?, archived=?, parent_id=?,
              closing_day=?, payment_day=?, payment_month_offset=?, payment_account_id=?
            WHERE id=?
            """,
            [.text(a.name), .text(a.type.rawValue), .int(Int64(a.initialBalance)),
             .int(Int64(a.sortOrder)), .int(a.archived ? 1 : 0), SQLValue(a.parentId),
             SQLValue(a.closingDay), SQLValue(a.paymentDay), .int(Int64(a.paymentMonthOffset)),
             SQLValue(a.paymentAccountId), .int(id)]).ok
    }

    /// 削除できたかを返す。他から参照されている場合は false。
    @discardableResult
    func delete(id: Int64) -> Bool {
        db.run("DELETE FROM accounts WHERE id=?", [.int(id)]).ok
    }

    /// 指定口座の子（仮想口座）名。
    func childNames(id: Int64) -> [String] {
        db.query("SELECT name FROM accounts WHERE parent_id=? ORDER BY sort_order, id",
                 [.int(id)]).compactMap { $0.string("name") }
    }

    /// 指定口座の子（仮想口座）数。
    func childCount(id: Int64) -> Int {
        db.query("SELECT COUNT(*) AS c FROM accounts WHERE parent_id=?", [.int(id)])
            .first?.int("c") ?? 0
    }

    /// 指定口座を引き落とし元に設定しているクレジット口座名。
    func paymentSourceOf(id: Int64) -> [String] {
        db.query("SELECT name FROM accounts WHERE payment_account_id=? ORDER BY sort_order, id",
                 [.int(id)]).compactMap { $0.string("name") }
    }

    /// 現在残高 = 初期残高 + 入金/振替先 - 出金/振替元。
    /// asOf を渡すとその日までの残高（残高推移のグラフ用）。
    func balance(id: Int64, asOf: String? = nil) -> Int {
        let initial = db.query(
            "SELECT initial_balance FROM accounts WHERE id=?", [.int(id)]
        ).first?.int("initial_balance") ?? 0

        let cutoff = asOf == nil ? "" : " AND date <= ?"
        var args: [SQLValue] = [.int(id), .int(id)]
        if let asOf { args.append(.text(asOf)) }

        let inflow = sum(
            """
            SELECT COALESCE(SUM(amount),0) AS s FROM transactions
            WHERE ((type='income' AND account_id=?) OR (type='transfer' AND to_account_id=?))\(cutoff)
            """, args)
        let outflow = sum(
            """
            SELECT COALESCE(SUM(amount),0) AS s FROM transactions
            WHERE ((type='expense' AND account_id=?) OR (type='transfer' AND account_id=?))\(cutoff)
            """, args)
        return initial + inflow - outflow
    }

    private func sum(_ sql: String, _ args: [SQLValue]) -> Int {
        db.query(sql, args).first?.int("s") ?? 0
    }

    static func map(_ r: Row) -> Account {
        Account(
            id: r.int64("id"),
            name: r.string("name") ?? "",
            type: AccountType(rawValue: r.string("type") ?? "cash") ?? .cash,
            initialBalance: r.int("initial_balance") ?? 0,
            sortOrder: r.int("sort_order") ?? 0,
            archived: (r.int("archived") ?? 0) == 1,
            parentId: r.int64("parent_id"),
            closingDay: r.int("closing_day"),
            paymentDay: r.int("payment_day"),
            paymentMonthOffset: r.int("payment_month_offset") ?? 1,
            paymentAccountId: r.int64("payment_account_id")
        )
    }
}
