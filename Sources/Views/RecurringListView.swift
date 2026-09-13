import SwiftUI

/// 定期取引の一覧・追加・編集・削除。
struct RecurringListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: RecurringRule?
    @State private var creating = false
    @State private var deleteError: String?

    var body: some View {
        List {
            if store.recurringRules.isEmpty {
                ContentUnavailableView {
                    Label("定期取引はありません", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("家賃・給与・サブスクなどを登録すると、予定日に自動で記録されます。")
                }
            } else {
                ForEach(store.recurringRules) { rule in
                    Button { editing = rule } label: { row(rule) }
                        .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for rule in offsets.map({ store.recurringRules[$0] }) {
                        if let error = store.deleteRecurring(rule) { deleteError = error; break }
                    }
                }
            }
        }
        .errorAlert("削除できません", message: $deleteError)
        .navigationTitle("定期取引")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { rule in RecurringEditView(existing: rule) }
        .sheet(isPresented: $creating) { RecurringEditView(existing: nil) }
    }

    private func row(_ rule: RecurringRule) -> some View {
        let cat = rule.categoryId.flatMap { store.categoriesById[$0] }
        let color = rule.type == .income ? TxPalette.income
            : (rule.type == .transfer ? TxPalette.transfer : TxPalette.expense)
        // メモ（家賃・サブスク名など）があればそれを見出しにする方が見分けやすい。
        let fallback = rule.type == .transfer ? "振替" : (cat?.name ?? rule.type.label)
        let title = rule.memo?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? rule.memo! : fallback
        let subtitle = title == fallback ? "" : "\(fallback) ・ "
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text("\(subtitle)\(rule.frequency.label) ・ 次回 \(rule.nextDate)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(rule.amount))
                .font(.callout.bold()).foregroundStyle(color)
        }
    }
}

/// 定期取引ルールの追加・編集。
struct RecurringEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let existing: RecurringRule?

    @State private var type: TxType
    @State private var amountText: String
    @State private var categoryId: Int64?
    @State private var accountId: Int64?
    @State private var toAccountId: Int64?
    @State private var memo: String
    @State private var frequency: Frequency
    @State private var interval: Int
    @State private var nextDate: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var message: String?

    init(existing: RecurringRule?) {
        self.existing = existing
        _type = State(initialValue: existing?.type ?? .expense)
        _amountText = State(initialValue: existing.map { String($0.amount) } ?? "")
        _categoryId = State(initialValue: existing?.categoryId)
        _accountId = State(initialValue: existing?.accountId)
        _toAccountId = State(initialValue: existing?.toAccountId)
        _memo = State(initialValue: existing?.memo ?? "")
        _frequency = State(initialValue: existing?.frequency ?? .monthly)
        _interval = State(initialValue: existing?.interval ?? 1)
        _nextDate = State(initialValue: existing.map { Dates.parse($0.nextDate) } ?? Date())
        _hasEnd = State(initialValue: existing?.endDate != nil)
        _endDate = State(initialValue: existing?.endDate.map(Dates.parse) ?? Date())
    }

    private var categoryOptions: [(category: Category, depth: Int)] {
        store.orderedCategories(of: type)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("種別", selection: $type) {
                        ForEach(TxType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, _ in categoryId = nil }

                    HStack {
                        Text(Money.currency.symbol).foregroundStyle(.secondary)
                        AmountField(placeholder: "金額", text: $amountText)
                    }
                }

                Section {
                    Picker("頻度", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("間隔: \(interval)", value: $interval, in: 1...30)
                    DatePicker("次回予定日", selection: $nextDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                    Toggle("終了日を設定", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("終了日", selection: $endDate, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                    }
                }

                if type == .transfer {
                    Section {
                        AccountPickerField(title: "振替元", selection: $accountId)
                        AccountPickerField(title: "振替先", selection: $toAccountId)
                    }
                } else {
                    Section {
                        Picker("カテゴリ", selection: $categoryId) {
                            Text("選択してください").tag(Int64?.none)
                            ForEach(categoryOptions, id: \.category.id) { entry in
                                Text(entry.depth == 0 ? entry.category.name : "　└ \(entry.category.name)")
                                    .tag(Int64?.some(entry.category.id ?? 0))
                            }
                        }
                        AccountPickerField(title: "口座", selection: $accountId)
                    }
                }

                Section { TextField("メモ（任意）", text: $memo) }
            }
            .navigationTitle(existing == nil ? "定期取引を追加" : "定期取引を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .alert("入力エラー", isPresented: .constant(message != nil)) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
            .onAppear { if accountId == nil { accountId = store.accountList.first?.id } }
        }
    }

    private func save() {
        guard let amount = Money.parse(amountText), amount > 0 else {
            message = "金額を正しく入力してください"; return
        }
        guard let account = accountId else { message = "口座を選択してください"; return }
        if type == .transfer {
            guard let to = toAccountId, to != account else {
                message = "振替先に別の口座を選択してください"; return
            }
        } else if categoryId == nil {
            message = "カテゴリを選択してください"; return
        }

        let rule = RecurringRule(
            id: existing?.id,
            type: type,
            amount: amount,
            categoryId: type == .transfer ? nil : categoryId,
            accountId: account,
            toAccountId: type == .transfer ? toAccountId : nil,
            memo: memo.trimmingCharacters(in: .whitespaces).isEmpty ? nil : memo,
            frequency: frequency,
            interval: interval,
            nextDate: Dates.ymd(nextDate),
            endDate: hasEnd ? Dates.ymd(endDate) : nil
        )
        if let error = store.saveRecurring(rule) { message = error; return }
        dismiss()
    }
}
