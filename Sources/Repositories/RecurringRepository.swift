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
             .text(r.nextDate), SQLValue(r.endDate)])
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

    func delete(id: Int64) {
        db.run("DELETE FROM recurring_rules WHERE id = ?", [.int(id)])
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
