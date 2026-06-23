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
                ForEach(store.orderedAccounts, id: \.account.id) { entry in
                    Button { editing = entry.account } label: {
                        row(entry.account, depth: entry.depth)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            } footer: {
                Text("残高 = 初期残高 + 入金・振替入 − 出金・振替出。口座を選ぶと「貯金用」などの仮想口座を中に作れます。")
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
            Text("この口座は取引で使われているか、仮想口座を持っています。先にそれらを変更・削除してください。")
        }
    }

    private func row(_ account: Account, depth: Int) -> some View {
        let balance = account.id.flatMap { store.accountBalances[$0] } ?? 0
        return HStack {
            if depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                if depth == 0 {
                    Text(account.type.label).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("仮想口座").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Money.format(balance))
                .font(.callout.bold())
                .foregroundStyle(balance >= 0 ? Color.primary : TxPalette.expense)
        }
        .padding(.leading, depth > 0 ? 12 : 0)
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            if !store.deleteAccount(store.orderedAccounts[index].account) {
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
