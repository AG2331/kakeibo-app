import Charts
import SwiftUI

/// 集計・分析画面: 前月比サマリ・カテゴリ別円グラフ・月別収支推移。
struct ReportsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var slices: [CategorySlice] = []
    @State private var trend: [MonthBar] = []
    @State private var previous: MonthlySummary = .empty

    private var totalExpense: Int { slices.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    comparisonCard
                    categorySection
                    trendSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("レポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.shiftMonth(by: -1) } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(Dates.yearMonthLabel(store.selectedMonth)).font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.shiftMonth(by: 1) } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
            .onAppear(perform: refresh)
            .onChange(of: store.selectedMonth) { _, _ in refresh() }
            .onChange(of: store.monthTransactions.count) { _, _ in refresh() }
        }
    }

    private func refresh() {
        slices = store.expenseBreakdown()
        trend = store.monthlyTrend(months: 6)
        previous = store.previousSummary()
    }

    // MARK: - 前月比サマリ

    private var comparisonCard: some View {
        let current = store.summary
        let delta = current.net - previous.net
        return VStack(spacing: 12) {
            HStack {
                metric("収入", current.income, TxPalette.income)
                metric("支出", current.expense, TxPalette.expense)
                metric("収支", current.net, current.net >= 0 ? TxPalette.income : TxPalette.expense)
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("前月比 \(delta >= 0 ? "+" : "")\(Money.format(delta))")
                Spacer()
                Text("前月の収支 \(Money.format(previous.net))")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .foregroundStyle(delta >= 0 ? TxPalette.income : TxPalette.expense)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ title: String, _ amount: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.format(amount)).font(.callout.bold()).foregroundStyle(color)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - カテゴリ別円グラフ

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ別支出").font(.headline)

            if slices.isEmpty {
                emptyHint("この期間の支出はまだありません")
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("金額", slice.amount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(Color(argb: slice.category.color ?? 0xFF90A4AE))
                }
                .frame(height: 200)
                .overlay {
                    VStack {
                        Text("支出計").font(.caption).foregroundStyle(.secondary)
                        Text(Money.format(totalExpense)).font(.headline)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(slices) { slice in
                        legendRow(slice)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func legendRow(_ slice: CategorySlice) -> some View {
        let pct = totalExpense > 0 ? Double(slice.amount) / Double(totalExpense) * 100 : 0
        return HStack {
            Circle()
                .fill(Color(argb: slice.category.color ?? 0xFF90A4AE))
                .frame(width: 12, height: 12)
            Text(slice.category.name)
            Spacer()
            Text(String(format: "%.0f%%", pct))
                .font(.caption).foregroundStyle(.secondary)
            Text(Money.format(slice.amount))
                .font(.callout).monospacedDigit()
                .frame(minWidth: 80, alignment: .trailing)
        }
    }

    // MARK: - 月別推移

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("月別の収支推移").font(.headline)

            Chart {
                ForEach(trend) { bar in
                    BarMark(
                        x: .value("月", bar.label),
                        y: .value("金額", bar.income)
                    )
                    .foregroundStyle(by: .value("種別", "収入"))
                    .position(by: .value("種別", "収入"))

                    BarMark(
                        x: .value("月", bar.label),
                        y: .value("金額", bar.expense)
                    )
                    .foregroundStyle(by: .value("種別", "支出"))
                    .position(by: .value("種別", "支出"))
                }
            }
            .chartForegroundStyleScale(["収入": TxPalette.income, "支出": TxPalette.expense])
            .frame(height: 220)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }
}
