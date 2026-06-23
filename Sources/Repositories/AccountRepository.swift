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
    func insert(_ a: Account) -> Int64 {
        db.run(
            "INSERT INTO accounts(name, type, initial_balance, sort_order, archived) VALUES(?,?,?,?,?)",
            [.text(a.name), .text(a.type.rawValue), .int(Int64(a.initialBalance)),
             .int(Int64(a.sortOrder)), .int(a.archived ? 1 : 0)])
    }

    func update(_ a: Account) {
        guard let id = a.id else { return }
        db.run(
            "UPDATE accounts SET name=?, type=?, initial_balance=?, sort_order=?, archived=? WHERE id=?",
            [.text(a.name), .text(a.type.rawValue), .int(Int64(a.initialBalance)),
             .int(Int64(a.sortOrder)), .int(a.archived ? 1 : 0), .int(id)])
    }

    func delete(id: Int64) {
        db.run("DELETE FROM accounts WHERE id=?", [.int(id)])
    }

    /// 現在残高 = 初期残高 + 入金/振替先 - 出金/振替元。
    func balance(id: Int64) -> Int {
        let initial = db.query(
            "SELECT initial_balance FROM accounts WHERE id=?", [.int(id)]
        ).first?.int("initial_balance") ?? 0

        let inflow = sum(
            """
            SELECT COALESCE(SUM(amount),0) AS s FROM transactions
            WHERE (type='income' AND account_id=?) OR (type='transfer' AND to_account_id=?)
            """, [.int(id), .int(id)])
        let outflow = sum(
            """
            SELECT COALESCE(SUM(amount),0) AS s FROM transactions
            WHERE (type='expense' AND account_id=?) OR (type='transfer' AND account_id=?)
            """, [.int(id), .int(id)])
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
            archived: (r.int("archived") ?? 0) == 1
        )
    }
}
