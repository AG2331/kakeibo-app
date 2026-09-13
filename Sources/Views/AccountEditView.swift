import SwiftUI

/// 口座・支払い方法の追加・編集。仮想口座（サブ口座）の作成にも対応。
struct AccountEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let existing: Account?

    @State private var name: String
    @State private var type: AccountType
    @State private var initialBalanceText: String
    @State private var parentId: Int64?
    @State private var closingDay: Int
    @State private var paymentDay: Int
    @State private var paymentMonthOffset: Int
    @State private var paymentAccountId: Int64?
    @State private var saveError: String?

    init(existing: Account?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _type = State(initialValue: existing?.type ?? .cash)
        _initialBalanceText = State(initialValue: existing.map { String($0.initialBalance) } ?? "0")
        _parentId = State(initialValue: existing?.parentId)
        _closingDay = State(initialValue: existing?.closingDay ?? 0)
        _paymentDay = State(initialValue: existing?.paymentDay ?? 27)
        _paymentMonthOffset = State(initialValue: existing?.paymentMonthOffset ?? 1)
        _paymentAccountId = State(initialValue: existing?.paymentAccountId)
    }

    /// 締め日・支払日ピッカーの選択肢（1-31日 + 月末）。
    private var dayOptions: some View {
        ForEach(Array(1...31) + [0], id: \.self) { d in
            Text(d == 0 ? "月末" : "\(d)日").tag(d)
        }
    }

    /// クレジット口座用: 締め日・支払日・引き落とし元口座の設定セクション。
    @ViewBuilder
    private var creditSettingsSection: some View {
        Section {
            Picker("締め日", selection: $closingDay) { dayOptions }
            Picker("支払月", selection: $paymentMonthOffset) {
                Text("当月").tag(0)
                Text("翌月").tag(1)
                Text("翌々月").tag(2)
            }
            Picker("支払日", selection: $paymentDay) { dayOptions }
            Picker("引き落とし元口座", selection: $paymentAccountId) {
                Text("未設定").tag(Int64?.none)
                ForEach(store.accountList.filter { $0.type != .credit && $0.id != existing?.id }) { acc in
                    Text(acc.name).tag(Int64?.some(acc.id ?? 0))
                }
            }
        } header: {
            Text("締め日・支払日")
        } footer: {
            Text("引き落とし（口座からの支払い）は、この口座への「振替」として記録してください。「支出」として記録すると、購入時と二重に計上されます。")
        }
    }

    /// 親候補（独立口座のみ、自分自身は除く）。子を持つ口座は親に従属させない。
    private var parentOptions: [Account] {
        let hasChildren = existing?.id.map { store.accounts.childCount(id: $0) > 0 } ?? false
        return hasChildren ? [] : store.parentCandidates(excluding: existing?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("口座名", text: $name)
                    Picker("種別", selection: $type) {
                        ForEach(AccountType.allCases) { Text($0.label).tag($0) }
                    }
                }
                if !parentOptions.isEmpty {
                    Section {
                        Picker("所属（仮想口座にする）", selection: $parentId) {
                            Text("独立した口座").tag(Int64?.none)
                            ForEach(parentOptions) { Text("\($0.name) の中").tag(Int64?.some($0.id ?? 0)) }
                        }
                    } footer: {
                        Text("親口座を選ぶと、その口座内の仮想口座（例: 貯金用）になります。")
                    }
                }
                if type == .credit {
                    creditSettingsSection
                }
                Section("初期残高") {
                    HStack {
                        Text(Money.currency.symbol).foregroundStyle(.secondary)
                        AmountField(placeholder: "0", text: $initialBalanceText)
                    }
                }
            }
            .errorAlert("保存できません", message: $saveError)
            .navigationTitle(existing == nil ? "口座を追加" : "口座を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let account = Account(
            id: existing?.id,
            name: trimmed,
            type: type,
            initialBalance: Money.parse(initialBalanceText) ?? 0,
            sortOrder: existing?.sortOrder ?? 0,
            archived: existing?.archived ?? false,
            parentId: parentId,
            closingDay: type == .credit ? closingDay : nil,
            paymentDay: type == .credit ? paymentDay : nil,
            paymentMonthOffset: paymentMonthOffset,
            paymentAccountId: type == .credit ? paymentAccountId : nil
        )
        if let error = store.saveAccount(account) { saveError = error; return }
        dismiss()
    }
}
