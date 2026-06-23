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
    func set(yearMonth: String, categoryId: Int64?, amount: Int) {
        if amount <= 0 {
            delete(yearMonth: yearMonth, categoryId: categoryId)
            return
        }
        // UNIQUE(year_month, category_id) だが NULL は UNIQUE 対象外なので分岐。
        let existing = db.query(
            "SELECT id FROM budgets WHERE year_month = ? AND " +
            (categoryId == nil ? "category_id IS NULL" : "category_id = ?"),
            categoryId == nil ? [.text(yearMonth)] : [.text(yearMonth), .int(categoryId!)]
        ).first?.int64("id")

        if let id = existing {
            db.run("UPDATE budgets SET amount = ? WHERE id = ?", [.int(Int64(amount)), .int(id)])
        } else {
            db.run("INSERT INTO budgets(year_month, category_id, amount) VALUES(?,?,?)",
                   [.text(yearMonth), SQLValue(categoryId), .int(Int64(amount))])
        }
    }

    func delete(yearMonth: String, categoryId: Int64?) {
        db.run("DELETE FROM budgets WHERE year_month = ? AND " +
               (categoryId == nil ? "category_id IS NULL" : "category_id = ?"),
               categoryId == nil ? [.text(yearMonth)] : [.text(yearMonth), .int(categoryId!)])
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
