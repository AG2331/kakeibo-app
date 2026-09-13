import SwiftUI

/// 月のカレンダー。日ごとに収入・支出・振替の合計を表示し、日付を選べる。
struct CalendarMonthView: View {
    let month: Date
    let totals: [String: DayTotals]      // "YYYY-MM-DD" -> 内訳
    @Binding var selected: String?       // 選択中の日（"YYYY-MM-DD"）

    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
    private let today = Dates.today()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(weekdayColor(index))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                      spacing: 4) {
                ForEach(cells.indices, id: \.self) { index in
                    cell(cells[index])
                }
            }
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("収入", TxPalette.income)
            legendItem("支出", TxPalette.expense)
            legendItem("振替", TxPalette.transfer)
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }

    @ViewBuilder
    private func cell(_ day: Date?) -> some View {
        if let day {
            let key = Dates.ymd(day)
            let totals = totals[key] ?? DayTotals()
            let isSelected = selected == key

            Button {
                // 同じ日をもう一度押したら選択を解除する
                selected = isSelected ? nil : key
            } label: {
                VStack(spacing: 1) {
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.caption2)
                        .fontWeight(key == today ? .bold : .regular)
                        .foregroundStyle(key == today ? TxPalette.accent : .primary)
                    amountLine(totals.income, color: TxPalette.income)
                    amountLine(totals.expense, color: TxPalette.expense)
                    amountLine(totals.transfer, color: TxPalette.transfer)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? TxPalette.accent.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? TxPalette.accent : Color.clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(minHeight: 52)
        }
    }

    /// 金額が無い行も高さを保って、日付の並びが崩れないようにする。
    @ViewBuilder
    private func amountLine(_ amount: Int, color: Color) -> some View {
        if amount > 0 {
            Text(compact(amount))
                .font(.system(size: 9))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text(" ").font(.system(size: 9))
        }
    }

    private func weekdayColor(_ index: Int) -> Color {
        switch index {
        case 0: return TxPalette.expense.opacity(0.8)   // 日曜
        case 6: return TxPalette.transfer               // 土曜
        default: return .secondary
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

    /// 「1.2k」「12k」のような短縮表記。セルの幅に収めるため。
    private func compact(_ value: Int) -> String {
        if value >= 10000 { return "\(value / 1000)k" }
        if value >= 1000 { return String(format: "%.1fk", Double(value) / 1000) }
        return "\(value)"
    }
}
