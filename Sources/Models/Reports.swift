import Foundation

/// カテゴリ別支出の1スライス（円グラフ用）。
struct CategorySlice: Identifiable {
    let category: Category
    let amount: Int
    var id: Int64 { category.id ?? -1 }
}

/// 1か月分の収支（棒グラフ用）。
struct MonthBar: Identifiable {
    let month: Date
    let label: String   // "6月"
    let income: Int
    let expense: Int
    var id: Date { month }
}
