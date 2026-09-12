import SwiftUI

/// 新規取引フォームの初期値（既存取引の編集ではなく、プリフィルされた未保存の新規取引を開くときに使う）。
struct TxDraft {
    var type: TxType = .expense
    var amount: Int = 0
    var date: Date = Date()
    var categoryId: Int64?
    var accountId: Int64?
    var toAccountId: Int64?
    var memo: String = ""
}

/// 取引の追加・編集画面。
struct TransactionEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let existing: TxRecord?

    @State private var type: TxType
    @State private var amountText: String
    @State private var date: Date
    @State private var categoryId: Int64?
    @State private var accountId: Int64?
    @State private var toAccountId: Int64?
    @State private var memo: String
    @State private var showDeleteConfirm = false
    @State private var validationMessage: String?

    init(existing: TxRecord?, draft: TxDraft? = nil) {
        self.existing = existing
        _type = State(initialValue: existing?.type ?? draft?.type ?? .expense)
        _amountText = State(initialValue: existing.map { String($0.amount) }
                             ?? draft.flatMap { $0.amount > 0 ? String($0.amount) : nil } ?? "")
        _date = State(initialValue: existing.map { Dates.parse($0.date) } ?? draft?.date ?? Date())
        _categoryId = State(initialValue: existing?.categoryId ?? draft?.categoryId)
        _accountId = State(initialValue: existing?.accountId ?? draft?.accountId)
        _toAccountId = State(initialValue: existing?.toAccountId ?? draft?.toAccountId)
        _memo = State(initialValue: existing?.memo ?? draft?.memo ?? "")
    }

    private var isEdit: Bool { existing != nil }

    /// 親→サブの順に並べたカテゴリ（サブはインデント表示）。
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
                }

                Section {
                    HStack {
                        Text(Money.currency.symbol).foregroundStyle(.secondary)
                        AmountField(placeholder: "金額", text: $amountText)
                            .font(.title2.bold())
                    }
                    DatePicker("日付", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                }

                if type == .transfer {
                    Section {
                        AccountPickerField(title: "振替元", selection: $accountId)
                        AccountPickerField(title: "振替先", selection: $toAccountId)
                    } footer: {
                        Text("クレジットカードの引き落としはここで「振替」として記録してください。「支出」で記録すると購入時と二重に計上されます。")
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

                Section {
                    TextField("メモ（任意）", text: $memo)
                }

                if isEdit {
                    Section {
                        Button("この取引を削除", role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(isEdit ? "取引を編集" : "取引を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "更新" : "保存") { save() }
                }
            }
            .alert("入力エラー", isPresented: .constant(validationMessage != nil)) {
                Button("OK") { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "")
            }
            .confirmationDialog("この取引を削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if let existing { store.delete(existing); dismiss() }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .onAppear {
                if accountId == nil { accountId = store.accountList.first?.id }
            }
        }
    }

    private func save() {
        guard let amount = Money.parse(amountText), amount > 0 else {
            validationMessage = "金額を正しく入力してください"; return
        }
        guard let account = accountId else {
            validationMessage = "口座を選択してください"; return
        }
        if type == .transfer {
            guard let to = toAccountId, to != account else {
                validationMessage = "振替先に別の口座を選択してください"; return
            }
        } else if categoryId == nil {
            validationMessage = "カテゴリを選択してください"; return
        }

        let record = TxRecord(
            id: existing?.id,
            type: type,
            amount: amount,
            date: Dates.ymd(date),
            categoryId: type == .transfer ? nil : categoryId,
            accountId: account,
            toAccountId: type == .transfer ? toAccountId : nil,
            memo: memo.trimmingCharacters(in: .whitespaces).isEmpty ? nil : memo,
            createdAt: existing?.createdAt ?? Int64(Date().timeIntervalSince1970 * 1000)
        )
        store.save(record)
        dismiss()
    }
}
