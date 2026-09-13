import SwiftUI

/// 予算管理: 全体予算とカテゴリ別予算の設定・消化率表示。
struct BudgetView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: BudgetTarget?

    var body: some View {
        NavigationStack {
            let progress = store.budgetProgress()
            List {
                Section("全体予算") {
                    if let overall = progress.overall {
                        Button { editing = BudgetTarget(categoryId: nil, name: "全体") } label: {
                            BudgetProgressRow(progress: overall)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            editing = BudgetTarget(categoryId: nil, name: "全体")
                        } label: {
                            Label("全体予算を設定", systemImage: "plus.circle")
                        }
                    }
                }

                Section {
                    ForEach(store.categories(of: .expense)) { category in
                        let prog = progress.categories.first { $0.categoryId == category.id }
                        Button {
                            editing = BudgetTarget(categoryId: category.id, name: category.name)
                        } label: {
                            categoryRow(category, progress: prog)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("カテゴリ別予算")
                } footer: {
                    Text("予算を超えると赤く表示されます。タップで設定・変更できます。")
                }
            }
            .navigationTitle("予算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .principal) {
                    Text(Dates.yearMonthLabel(store.selectedMonth)).font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .sheet(item: $editing) { target in
                BudgetEditView(target: target)
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: Category, progress: BudgetProgress?) -> some View {
        if let progress {
            BudgetProgressRow(progress: progress)
        } else {
            HStack {
                Circle().fill(category.color.map { Color(argb: $0) } ?? .gray)
                    .frame(width: 12, height: 12)
                Text(category.name)
                Spacer()
                Text("未設定").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

/// 予算編集対象（全体 or カテゴリ）。
struct BudgetTarget: Identifiable {
    let categoryId: Int64?
    let name: String
    var id: Int64 { categoryId ?? -1 }
}

/// 消化率の行（名前・金額・バー）。
struct BudgetProgressRow: View {
    let progress: BudgetProgress

    private var barColor: Color {
        if progress.isOver { return TxPalette.expense }
        if progress.ratio >= 0.8 { return .orange }
        return TxPalette.income
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let color = progress.color {
                    Circle().fill(Color(argb: color)).frame(width: 12, height: 12)
                }
                Text(progress.name)
                Spacer()
                Text("\(Money.format(progress.spent)) / \(Money.format(progress.budget))")
                    .font(.callout).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 8)
                    Capsule().fill(barColor)
                        .frame(width: geo.size.width * min(progress.ratio, 1), height: 8)
                }
            }
            .frame(height: 8)
            HStack {
                if progress.isOver {
                    Label("予算を\(Money.format(-progress.remaining))超過", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(TxPalette.expense)
                } else {
                    Text("残り \(Money.format(progress.remaining))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.0f%%", progress.ratio * 100))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 予算額の入力シート。
struct BudgetEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let target: BudgetTarget
    @State private var amountText: String = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("\(target.name)の月予算") {
                    HStack {
                        Text(Money.currency.symbol).foregroundStyle(.secondary)
                        AmountField(placeholder: "0", text: $amountText)
                            .font(.title3.bold())
                    }
                }
                Section {
                    Text("0 を入力すると予算を解除します。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("予算を設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let error = store.setBudget(categoryId: target.categoryId,
                                                       amount: Money.parse(amountText) ?? 0) {
                            saveError = error
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .errorAlert("保存できません", message: $saveError)
            .onAppear {
                let current = store.budgetAmount(categoryId: target.categoryId)
                amountText = current > 0 ? String(current) : ""
            }
        }
    }
}
