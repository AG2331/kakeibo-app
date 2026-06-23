import SwiftUI

/// 月のカレンダー。日ごとの支出額を色の濃さで表す（ヒートマップ風）。
struct CalendarMonthView: View {
    let month: Date
    let dailyExpense: [String: Int]   // "YYYY-MM-DD" -> 支出額

    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    private var maxExpense: Int { max(dailyExpense.values.max() ?? 0, 1) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(weekdays, id: \.self) { d in
                    Text(d).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells.indices, id: \.self) { i in
                    cell(cells[i])
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: Date?) -> some View {
        if let day {
            let key = Dates.ymd(day)
            let expense = dailyExpense[key] ?? 0
            let intensity = expense > 0 ? 0.15 + 0.6 * Double(expense) / Double(maxExpense) : 0
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.caption2)
                if expense > 0 {
                    Text(compact(expense)).font(.system(size: 8)).foregroundStyle(.secondary)
                } else {
                    Text(" ").font(.system(size: 8))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(TxPalette.expense.opacity(intensity), in: RoundedRectangle(cornerRadius: 6))
        } else {
            Color.clear.frame(minHeight: 34)
        }
    }

    /// その月のセル配列（先頭は曜日合わせの空白）。
    private var cells: [Date?] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let leading = cal.component(.weekday, from: first) - 1 // 日曜=0
        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            result.append(cal.date(byAdding: .day, value: day - 1, to: first))
        }
        return result
    }

    /// 「1.2k」「12k」のような短縮表記。
    private func compact(_ value: Int) -> String {
        if value >= 10000 { return "\(value / 1000)k" }
        if value >= 1000 { return String(format: "%.1fk", Double(value) / 1000) }
        return "\(value)"
    }
}
