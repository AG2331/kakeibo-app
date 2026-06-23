import SwiftUI

/// 口座・支払い方法の管理。残高表示・追加・編集・削除。
struct AccountListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Account?
    @State private var creating = false
    @State private var deleteError = false

    var body: some View {
        List {
            Section {
                ForEach(store.accountList) { account in
                    Button { editing = account } label: {
                        row(account)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            } footer: {
                Text("残高 = 初期残高 + 入金・振替入 − 出金・振替出")
            }

            Section {
                Button {
                    creating = true
                } label: {
                    Label("口座を追加", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("口座・支払い方法")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { account in
            AccountEditView(existing: account)
        }
        .sheet(isPresented: $creating) {
            AccountEditView(existing: nil)
        }
        .alert("削除できません", isPresented: $deleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("この口座を使っている取引があります。先に取引の口座を変更してください。")
        }
    }

    private func row(_ account: Account) -> some View {
        let balance = account.id.flatMap { store.accountBalances[$0] } ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.type.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(balance))
                .font(.callout.bold())
                .foregroundStyle(balance >= 0 ? Color.primary : TxPalette.expense)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            if !store.deleteAccount(store.accountList[index]) {
                deleteError = true
            }
        }
    }
}

/// 口座の追加・編集。
struct AccountEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let existing: Account?

    @State private var name: String
    @State private var type: AccountType
    @State private var initialBalanceText: String

    init(existing: Account?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _type = State(initialValue: existing?.type ?? .cash)
        _initialBalanceText = State(initialValue: existing.map { String($0.initialBalance) } ?? "0")
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
            archived: existing?.archived ?? false
        )
        store.saveAccount(account)
        dismiss()
    }
}
