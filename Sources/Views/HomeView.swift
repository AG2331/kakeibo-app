import SwiftUI

/// ホーム: 当月サマリ + 取引一覧。
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: TxRecord?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryCard(summary: store.summary)
                        .listRowInsets(EdgeInsets())
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

/// 1件の取引行。
private struct TransactionRow: View {
    let tx: TxRecord
    let category: Category?

    var body: some View {
        let isTransfer = tx.type == .transfer
        let color = isTransfer ? TxPalette.transfer
            : (tx.type == .expense ? TxPalette.expense : TxPalette.income)
        let catColor = category?.color.map { Color(argb: $0) } ?? .gray

        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(catColor.opacity(0.2)).frame(width: 36, height: 36)
                Image(systemName: isTransfer ? "arrow.left.arrow.right" : "tag")
                    .font(.footnote)
                    .foregroundStyle(catColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isTransfer ? "振替" : (category?.name ?? "未分類"))
                if let memo = tx.memo, !memo.isEmpty {
                    Text(memo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(tx.type == .expense ? "-\(Money.format(tx.amount))" : Money.format(tx.amount))
                .font(.callout.bold())
                .foregroundStyle(color)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
