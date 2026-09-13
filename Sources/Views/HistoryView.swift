import SwiftUI

/// 履歴タブ。カレンダーで日ごとの収入・支出・振替を見て、
/// 日を選ぶとその日の記録が並び、選ぶと編集できる。
struct HistoryView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedDay: String?
    @State private var dayItems: [TxRecord] = []
    @State private var editing: TxRecord?
    @State private var creatingOn: DayDraft?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    calendarCard
                    if let selectedDay {
                        dayDetailCard(selectedDay)
                    } else {
                        monthSummaryCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .principal) {
                    Text(Dates.yearMonthLabel(store.selectedMonth)).font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                }
            }
            .sheet(item: $editing) { tx in
                TransactionEditView(existing: tx)
            }
            .sheet(item: $creatingOn) { draft in
                TransactionEditView(existing: nil, draft: TxDraft(date: Dates.parse(draft.day)))
            }
            .onChange(of: selectedDay) { _, _ in reloadDayItems() }
            // 保存・削除のあとも表示を合わせる
            .onChange(of: store.monthCalendar) { _, _ in reloadDayItems() }
        }
    }

    // MARK: - カレンダー

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CalendarMonthView(month: store.selectedMonth,
                              totals: store.monthCalendar,
                              selected: $selectedDay)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 選択した日の記録

    private func dayDetailCard(_ day: String) -> some View {
        let totals = store.monthCalendar[day] ?? DayTotals()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Dates.displayDate(day)).font(.headline)
                Spacer()
                Button {
                    creatingOn = DayDraft(day: day)
                } label: {
                    Label("この日に記録", systemImage: "plus.circle")
                        .font(.caption)
                }
            }

            if totals.isEmpty {
                Text("この日の記録はありません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                dayTotalsRow(totals)
                Divider()
                VStack(spacing: 8) {
                    ForEach(dayItems) { tx in
                        Button { editing = tx } label: {
                            TransactionRow(tx: tx,
                                           category: tx.categoryId.flatMap { store.categoriesById[$0] })
                        }
                        .buttonStyle(.plain)
                        if tx.id != dayItems.last?.id { Divider() }
                    }
                }
                Text("記録をタップすると修正できます")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func dayTotalsRow(_ totals: DayTotals) -> some View {
        HStack {
            totalItem("収入", totals.income, TxPalette.income)
            Divider().frame(height: 28)
            totalItem("支出", totals.expense, TxPalette.expense)
            Divider().frame(height: 28)
            totalItem("振替", totals.transfer, TxPalette.transfer)
        }
    }

    private func totalItem(_ title: String, _ amount: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(amount > 0 ? Money.format(amount) : "—")
                .font(.callout.bold())
                .foregroundStyle(amount > 0 ? color : Color.secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 日を選んでいないとき

    private var monthSummaryCard: some View {
        let monthTotals = store.monthCalendar.values.reduce(into: DayTotals()) { sum, day in
            sum.income += day.income
            sum.expense += day.expense
            sum.transfer += day.transfer
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(Dates.yearMonthLabel(store.selectedMonth))の合計").font(.headline)
            dayTotalsRow(monthTotals)
            Text("日付をタップすると、その日の記録を確認・修正できます")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: -

    private func shiftMonth(_ delta: Int) {
        selectedDay = nil
        store.shiftMonth(by: delta)
    }

    private func reloadDayItems() {
        dayItems = selectedDay.map { store.transactions(on: $0) } ?? []
    }
}

/// sheet(item:) に日付を渡すための包み。
private struct DayDraft: Identifiable {
    let day: String
    var id: String { day }
}
