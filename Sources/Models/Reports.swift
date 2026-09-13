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

/// 残高推移の1点（口座詳細のグラフ用）。
struct BalancePoint: Identifiable {
    let month: Date
    let label: String   // "6月"
    let balance: Int
    var id: Date { month }
}

/// カレンダーの1日分の内訳。振替は収支に響かないが、その日に何があったかは示す。
struct DayTotals: Equatable {
    var income = 0
    var expense = 0
    var transfer = 0

    var isEmpty: Bool { income == 0 && expense == 0 && transfer == 0 }
    /// その日の収支（振替は含めない）。
    var net: Int { income - expense }
}
