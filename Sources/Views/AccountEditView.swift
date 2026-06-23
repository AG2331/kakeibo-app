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

    init(existing: Account?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _type = State(initialValue: existing?.type ?? .cash)
        _initialBalanceText = State(initialValue: existing.map { String($0.initialBalance) } ?? "0")
        _parentId = State(initialValue: existing?.parentId)
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
                Section("初期残高") {
                    HStack {
                        Text(Money.currency.symbol).foregroundStyle(.secondary)
                        TextField("0", text: $initialBalanceText)
                            .keyboardType(.numbersAndPunctuation)
                    }
                }
            }
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
            parentId: parentId
        )
        store.saveAccount(account)
        dismiss()
    }
}
