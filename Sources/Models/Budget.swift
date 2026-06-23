import Foundation

/// 月次予算。categoryId が nil なら全体予算。
struct Budget: Identifiable, Hashable {
    var id: Int64?
    var yearMonth: String    // YYYY-MM
    var categoryId: Int64?   // nil = 全体
    var amount: Int

    init(id: Int64? = nil, yearMonth: String, categoryId: Int64? = nil, amount: Int) {
        self.id = id
        self.yearMonth = yearMonth
        self.categoryId = categoryId
        self.amount = amount
    }
}

/// 予算の消化状況（画面表示用）。
struct BudgetProgress: Identifiable {
    let categoryId: Int64?      // nil = 全体
    let name: String
    let color: Int?
    let budget: Int
    let spent: Int

    var id: Int64 { categoryId ?? -1 }
    var ratio: Double { budget > 0 ? Double(spent) / Double(budget) : 0 }
    var isOver: Bool { spent > budget }
    var remaining: Int { budget - spent }
}
