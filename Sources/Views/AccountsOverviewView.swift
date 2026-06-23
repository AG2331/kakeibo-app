import SwiftUI

/// 口座・支払い方法の一覧と総額を表示するタブ。
/// 親口座（実口座）はその総額を、仮想口座（サブ口座）は内訳として表示する。
struct AccountsOverviewView: View {
    @EnvironmentObject private var store: AppStore

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

                ForEach(overview.nodes) { node in
                    Section {
                        parentRow(node)
                        if node.hasChildren {
                            // 親口座に直接ある（仮想口座に振り分けていない）残高
                            if node.ownBalance != 0 {
                                breakdownRow(name: "（振分なし）", balance: node.ownBalance, isOwn: true)
                            }
                            ForEach(node.children, id: \.account.id) { child in
                                breakdownRow(name: child.account.name, balance: child.balance, isOwn: false)
                            }
                        }
                    }
                }
            }
            .navigationTitle("口座")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if store.accountList.isEmpty {
                    ContentUnavailableView("口座がありません", systemImage: "banknote",
                                           description: Text("設定 > 口座・支払い方法 から追加できます。"))
                }
            }
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
