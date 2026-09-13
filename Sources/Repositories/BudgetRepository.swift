import Foundation

struct BudgetRepository {
    let db: Database

    func forMonth(_ yearMonth: String) -> [Budget] {
        db.query("SELECT * FROM budgets WHERE year_month = ?", [.text(yearMonth)])
            .map(Self.map)
    }

    /// 全体予算（category_id IS NULL）。
    func overall(_ yearMonth: String) -> Budget? {
        db.query("SELECT * FROM budgets WHERE year_month = ? AND category_id IS NULL",
                 [.text(yearMonth)]).first.map(Self.map)
    }

    /// 予算を設定（同じ year_month × category は上書き）。amount<=0 は削除。
    @discardableResult
    func set(yearMonth: String, categoryId: Int64?, amount: Int) -> Bool {
        if amount <= 0 {
            return delete(yearMonth: yearMonth, categoryId: categoryId)
        }
        // UNIQUE(year_month, category_id) だが NULL は UNIQUE 対象外なので分岐。
        let existing = db.query(
            "SELECT id FROM budgets WHERE year_month = ? AND " +
            (categoryId == nil ? "category_id IS NULL" : "category_id = ?"),
            categoryId == nil ? [.text(yearMonth)] : [.text(yearMonth), .int(categoryId!)]
        ).first?.int64("id")

        if let id = existing {
            return db.run("UPDATE budgets SET amount = ? WHERE id = ?",
                          [.int(Int64(amount)), .int(id)]).ok
        }
        return db.run("INSERT INTO budgets(year_month, category_id, amount) VALUES(?,?,?)",
                      [.text(yearMonth), SQLValue(categoryId), .int(Int64(amount))]).ok
    }

    /// 指定カテゴリに予算が設定されている月数。
    func countByCategory(id: Int64) -> Int {
        db.query("SELECT COUNT(*) AS c FROM budgets WHERE category_id = ?", [.int(id)])
            .first?.int("c") ?? 0
    }

    @discardableResult
    func delete(yearMonth: String, categoryId: Int64?) -> Bool {
        db.run("DELETE FROM budgets WHERE year_month = ? AND " +
               (categoryId == nil ? "category_id IS NULL" : "category_id = ?"),
               categoryId == nil ? [.text(yearMonth)] : [.text(yearMonth), .int(categoryId!)]).ok
    }

    static func map(_ r: Row) -> Budget {
        Budget(
            id: r.int64("id"),
            yearMonth: r.string("year_month") ?? "",
            categoryId: r.int64("category_id"),
            amount: r.int("amount") ?? 0
        )
    }
}
