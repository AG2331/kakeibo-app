import SwiftUI

/// ホーム: 当月サマリ + 取引一覧。
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: TxRecord?
    @State private var creating = false
    @State private var editingBudget = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryCard(summary: store.summary)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                    Button {
                        editingBudget = true
                    } label: {
                        Label("予算の編集", systemImage: "chart.bar.doc.horizontal")
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                }

                if store.monthTransactions.isEmpty {
                    Section {
                        Text("この月の記録はまだありません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(store.groupedByDate, id: \.date) { group in
                        Section {
                            ForEach(group.items) { tx in
                                Button { editing = tx } label: {
                                    TransactionRow(tx: tx,
                                                   category: tx.categoryId.flatMap { store.categoriesById[$0] })
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            dayHeader(for: group.items, date: group.date)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Dates.yearMonthLabel(store.selectedMonth))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.shiftMonth(by: -1) } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.shiftMonth(by: 1) } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    creating = true
                } label: {
                    Label("記録", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(TxPalette.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .sheet(isPresented: $creating) {
                TransactionEditView(existing: nil)
            }
            .sheet(item: $editing) { tx in
                TransactionEditView(existing: tx)
            }
            .sheet(isPresented: $editingBudget) {
                BudgetView()
            }
        }
    }

    private func dayHeader(for items: [TxRecord], date: String) -> some View {
        let dayNet = items.reduce(0) { $0 + $1.signedAmount }
        return HStack {
            Text(Dates.displayDate(date))
            Spacer()
            Text(Money.format(dayNet))
                .foregroundStyle(.secondary)
        }
    }
}

/// 当月サマリのカード。
private struct SummaryCard: View {
    let summary: MonthlySummary

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                summaryItem(title: "収入", amount: summary.income, color: TxPalette.income)
                Divider().frame(height: 36)
                summaryItem(title: "支出", amount: summary.expense, color: TxPalette.expense)
            }
            Divider()
            HStack {
                Text("収支").font(.subheadline)
                Spacer()
                Text(Money.format(summary.net))
                    .font(.title2.bold())
                    .foregroundStyle(summary.net >= 0 ? TxPalette.income : TxPalette.expense)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .padding()
    }

    private func summaryItem(title: String, amount: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.format(amount)).font(.title3.bold()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}
