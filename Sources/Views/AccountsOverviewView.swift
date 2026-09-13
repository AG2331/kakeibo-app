import SwiftUI

/// 口座・支払い方法のタブ。総額と内訳の表示に加え、登録・編集・削除もここで行う。
/// 親口座（実口座）はその総額を、仮想口座（サブ口座）は内訳として表示する。
struct AccountsOverviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var creating = false
    @State private var deleteError: String?
    @State private var collapsed: Set<Int64> = []
    @State private var settlementDraft: CreditCardStatementInfo?

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
                        parentRowContainer(node)
                        if let info = store.creditCardStatements[node.account.id ?? -1] {
                            creditStatementRow(info)
                        }

                        if node.hasChildren && !isCollapsed(node.account.id) {
                            // 親口座に直接ある（仮想口座に振り分けていない）残高
                            if node.ownBalance != 0 {
                                breakdownRow(name: "（振分なし）", balance: node.ownBalance, isOwn: true)
                            }
                            ForEach(node.children, id: \.account.id) { child in
                                NavigationLink {
                                    detail(for: child.account)
                                } label: {
                                    breakdownRow(name: child.account.name, balance: child.balance, isOwn: false)
                                }
                                .swipeActions(edge: .trailing) { deleteButton(child.account) }
                                if let info = store.creditCardStatements[child.account.id ?? -1] {
                                    creditStatementRow(info)
                                }
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
            .sheet(isPresented: $creating) {
                AccountEditView(existing: nil)
            }
            .sheet(item: $settlementDraft) { info in
                let card = store.accountList.first { $0.id == info.accountId }
                TransactionEditView(existing: nil, draft: TxDraft(
                    type: .transfer,
                    amount: info.dueAmount,
                    date: Dates.parse(info.dueDate),
                    accountId: card?.paymentAccountId,
                    toAccountId: info.accountId,
                    memo: "カード引き落とし"
                ))
            }
            .errorAlert("削除できません", message: $deleteError)
        }
    }

    @ViewBuilder
    private func detail(for account: Account) -> some View {
        if let id = account.id {
            AccountDetailView(accountId: id)
        }
    }

    private func deleteButton(_ account: Account) -> some View {
        Button(role: .destructive) {
            deleteError = store.deleteAccount(account)
        } label: {
            Label("削除", systemImage: "trash")
        }
    }

    /// 親口座の行。仮想口座があれば折りたたみ用シェブロンを左に表示する。
    private func parentRowContainer(_ node: AccountNode) -> some View {
        HStack(spacing: 8) {
            if node.hasChildren {
                Button { toggle(node.account.id) } label: {
                    Image(systemName: isCollapsed(node.account.id) ? "chevron.right" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
            } else {
                Spacer().frame(width: 22)
            }
            NavigationLink { detail(for: node.account) } label: { parentRow(node) }
        }
        .swipeActions(edge: .trailing) { deleteButton(node.account) }
    }

    private func isCollapsed(_ id: Int64?) -> Bool {
        id.map { collapsed.contains($0) } ?? false
    }

    private func toggle(_ id: Int64?) {
        guard let id else { return }
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
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

    /// クレジット口座の未精算額・請求状況を表示する行。
    /// 引き落としを記録済みなら請求は消え、進行中サイクルの見込みに切り替わる。
    private func creditStatementRow(_ info: CreditCardStatementInfo) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("未精算額 \(Money.format(info.outstandingAmount))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(statementCaption(info))
                    .font(.caption2)
                    .foregroundStyle(info.isOverdue ? AnyShapeStyle(TxPalette.expense)
                                                    : AnyShapeStyle(.tertiary))
            }
            Spacer()
            // 支払うべき請求があるときだけ出す（支払い済みの再記録＝二重払いを防ぐ）
            if !info.isSettled {
                Button("引き落としを記録") { settlementDraft = info }
                    .font(.caption2)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.leading, 32)
        .padding(.vertical, 2)
    }

    private func statementCaption(_ info: CreditCardStatementInfo) -> String {
        if info.isOverdue {
            return "支払期限超過(\(Dates.displayDate(info.dueDate))): \(Money.format(info.dueAmount))"
        }
        if !info.isSettled {
            return "次回請求(\(Dates.displayDate(info.dueDate))): \(Money.format(info.dueAmount))"
        }
        return "次回請求(\(Dates.displayDate(info.upcomingDueDate))予定): \(Money.format(info.upcomingAmount))"
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
