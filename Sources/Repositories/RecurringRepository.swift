import Foundation

struct RecurringRepository {
    let db: Database

    func all() -> [RecurringRule] {
        db.query("SELECT * FROM recurring_rules ORDER BY next_date ASC, id ASC")
            .map(Self.map)
    }

    @discardableResult
    func insert(_ r: RecurringRule) -> Int64 {
        db.run(
            """
            INSERT INTO recurring_rules(type, amount, category_id, account_id, to_account_id, memo,
              frequency, interval, next_date, end_date)
            VALUES(?,?,?,?,?,?,?,?,?,?)
            """,
            [.text(r.type.rawValue), .int(Int64(r.amount)), SQLValue(r.categoryId),
             .int(r.accountId), SQLValue(r.toAccountId), SQLValue(r.memo),
             .text(r.frequency.rawValue), .int(Int64(r.interval)),
             .text(r.nextDate), SQLValue(r.endDate)]).rowId
    }

    func update(_ r: RecurringRule) {
        guard let id = r.id else { return }
        db.run(
            """
            UPDATE recurring_rules SET type=?, amount=?, category_id=?, account_id=?, to_account_id=?,
              memo=?, frequency=?, interval=?, next_date=?, end_date=? WHERE id=?
            """,
            [.text(r.type.rawValue), .int(Int64(r.amount)), SQLValue(r.categoryId),
             .int(r.accountId), SQLValue(r.toAccountId), SQLValue(r.memo),
             .text(r.frequency.rawValue), .int(Int64(r.interval)),
             .text(r.nextDate), SQLValue(r.endDate), .int(id)])
    }

    func updateNextDate(id: Int64, _ nextDate: String) {
        db.run("UPDATE recurring_rules SET next_date = ? WHERE id = ?", [.text(nextDate), .int(id)])
    }

    @discardableResult
    func delete(id: Int64) -> Bool {
        db.run("DELETE FROM recurring_rules WHERE id = ?", [.int(id)]).ok
    }

    /// 指定口座を使っている定期取引の表示名（メモ、無ければ「定期取引」）。
    func usingAccount(id: Int64) -> [String] {
        db.query("SELECT memo FROM recurring_rules WHERE account_id=? OR to_account_id=?",
                 [.int(id), .int(id)]).map { $0.string("memo") ?? "定期取引" }
    }

    /// 指定カテゴリを使っている定期取引の表示名。
    func usingCategory(id: Int64) -> [String] {
        db.query("SELECT memo FROM recurring_rules WHERE category_id=?", [.int(id)])
            .map { $0.string("memo") ?? "定期取引" }
    }

    static func map(_ r: Row) -> RecurringRule {
        RecurringRule(
            id: r.int64("id"),
            type: TxType(rawValue: r.string("type") ?? "expense") ?? .expense,
            amount: r.int("amount") ?? 0,
            categoryId: r.int64("category_id"),
            accountId: r.int64("account_id") ?? 0,
            toAccountId: r.int64("to_account_id"),
            memo: r.string("memo"),
            frequency: Frequency(rawValue: r.string("frequency") ?? "monthly") ?? .monthly,
            interval: r.int("interval") ?? 1,
            nextDate: r.string("next_date") ?? "",
            endDate: r.string("end_date")
        )
    }
}
