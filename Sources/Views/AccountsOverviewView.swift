import SwiftUI

/// 口座・支払い方法のタブ。総額と内訳の表示に加え、登録・編集・削除もここで行う。
/// 親口座（実口座）はその総額を、仮想口座（サブ口座）は内訳として表示する。
struct AccountsOverviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Account?
    @State private var creating = false
    @State private var deleteError = false

    var body: some View {
        NavigationStack {
            let overview = store.accountOverview()
            List {
                Section {
                    HStack {
                        Text("総資産").font(.headline)
                        Spacer()
                        Text(Money.format(overview.grandTotal))
                            .font(.title3.bold())
                            .foregroundStyle(overview.grandTotal >= 0 ? TxPalette.income : TxPalette.expense)
                    }
                    .padding(.vertical, 4)
                }

                // 支払い方法はひとつのセクションにまとめ、相互の間隔を詰める。
                Section {
                    ForEach(overview.nodes) { node in
                        Button { editing = node.account } label: { parentRow(node) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) { deleteButton(node.account) }

                        if node.hasChildren {
                            // 親口座に直接ある（仮想口座に振り分けていない）残高
                            if node.ownBalance != 0 {
                                breakdownRow(name: "（振分なし）", balance: node.ownBalance, isOwn: true)
                            }
                            ForEach(node.children, id: \.account.id) { child in
                                Button {
                                    editing = child.account
                                } label: {
                                    breakdownRow(name: child.account.name, balance: child.balance, isOwn: false)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) { deleteButton(child.account) }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        creating = true
                    } label: {
                        Label("口座・支払い方法を追加", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("口座を選ぶと「貯金用」などの仮想口座を中に作れます。左スワイプで削除できます。")
                }
            }
            .navigationTitle("口座")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if store.accountList.isEmpty {
                    ContentUnavailableView {
                        Label("口座がありません", systemImage: "banknote")
                    } description: {
                        Text("右上の＋から口座・支払い方法を追加できます。")
                    } actions: {
                        Button("口座を追加") { creating = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
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
    }

    private func deleteButton(_ account: Account) -> some View {
        Button(role: .destructive) {
            if !store.deleteAccount(account) { deleteError = true }
        } label: {
            Label("削除", systemImage: "trash")
        }
    }

    private func parentRow(_ node: AccountNode) -> some View {
        HStack {
            Image(systemName: icon(for: node.account.type))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.account.name).font(.body.weight(.semibold))
                Text(node.account.type.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(node.total))
                .font(.callout.bold())
                .foregroundStyle(node.total >= 0 ? Color.primary : TxPalette.expense)
        }
        .padding(.vertical, 2)
    }

    private func breakdownRow(name: String, balance: Int, isOwn: Bool) -> some View {
        HStack {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 24)
            Text(name)
                .font(.callout)
                .foregroundStyle(isOwn ? .secondary : .primary)
            Spacer()
            Text(Money.format(balance))
                .font(.callout).monospacedDigit()
                .foregroundStyle(balance >= 0 ? .secondary : TxPalette.expense)
        }
        .padding(.leading, 8)
    }

    private func icon(for type: AccountType) -> String {
        switch type {
        case .cash: return "yensign.circle"
        case .bank: return "building.columns"
        case .emoney: return "wave.3.right.circle"
        case .credit: return "creditcard"
        }
    }
}
