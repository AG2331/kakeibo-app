import Charts
import SwiftUI

/// 口座の詳細。残高の推移とその口座の取引履歴を見る。
/// 口座そのものの編集・削除は右上のメニューから行う。
struct AccountDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let accountId: Int64

    @State private var editingAccount: Account?
    @State private var editingTx: TxRecord?
    @State private var deleteError: String?
    @State private var confirmDelete = false

    /// 一覧の更新に追従できるよう、保持した値ではなく毎回引き直す。
    private var account: Account? {
        store.accountList.first { $0.id == accountId }
    }

    var body: some View {
        List {
            if let account {
                summarySection(account)
                trendSection
                historySection
            } else {
                // 削除された直後など
                Text("この口座は見つかりませんでした")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(account?.name ?? "口座")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editingAccount = account
                    } label: {
                        Label("この口座を編集", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("この口座を削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editingAccount) { account in
            AccountEditView(existing: account)
        }
        .sheet(item: $editingTx) { tx in
            TransactionEditView(existing: tx)
        }
        .confirmationDialog("この口座を削除しますか？", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) { deleteAccount() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("取引などから使われている口座は削除できません。")
        }
        .errorAlert("削除できません", message: $deleteError)
    }

    // MARK: - 残高

    private func summarySection(_ account: Account) -> some View {
        let balance = store.accountBalances[accountId] ?? 0
        return Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.type.label)
                        .font(.caption).foregroundStyle(.secondary)
                    if account.isVirtual, let parent = parentName {
                        Text("\(parent) の中").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("現在の残高").font(.caption).foregroundStyle(.secondary)
                    Text(Money.format(balance))
                        .font(.title3.bold())
                        .foregroundStyle(balance >= 0 ? Color.primary : TxPalette.expense)
                }
            }
            .padding(.vertical, 4)

            if let info = store.creditCardStatements[accountId] {
                HStack {
                    Text("未精算額").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.format(info.outstandingAmount)).font(.callout)
                }
            }
        }
    }

    private var parentName: String? {
        account?.parentId.flatMap { pid in store.accountList.first { $0.id == pid }?.name }
    }

    // MARK: - 残高推移

    private var trendSection: some View {
        let points = store.balanceTrend(accountId: accountId)
        return Section("残高の推移") {
            if points.allSatisfy({ $0.balance == 0 }) {
                Text("まだ推移を表示できる記録がありません")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("月", point.label),
                             y: .value("残高", point.balance))
                    .foregroundStyle(TxPalette.accent)
                    .interpolationMethod(.monotone)

                    PointMark(x: .value("月", point.label),
                              y: .value("残高", point.balance))
                    .foregroundStyle(TxPalette.accent)

                    AreaMark(x: .value("月", point.label),
                             y: .value("残高", point.balance))
                    .foregroundStyle(TxPalette.accent.opacity(0.12))
                    .interpolationMethod(.monotone)
                }
                .frame(height: 180)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 取引履歴

    private var historySection: some View {
        let items = store.transactions(ofAccount: accountId)
        return Section("この口座の記録") {
            if items.isEmpty {
                Text("記録がありません")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ForEach(items) { tx in
                    Button { editingTx = tx } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Dates.displayDate(tx.date))
                                .font(.caption2).foregroundStyle(.secondary)
                            TransactionRow(
                                tx: tx,
                                category: tx.categoryId.flatMap { store.categoriesById[$0] },
                                perspective: RowPerspective(
                                    accountId: accountId,
                                    counterpartName: counterpartName(of: tx)))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 振替の相手側の口座名。
    private func counterpartName(of tx: TxRecord) -> String? {
        guard tx.type == .transfer else { return nil }
        let otherId = tx.accountId == accountId ? tx.toAccountId : tx.accountId
        return otherId.flatMap { id in store.accountList.first { $0.id == id }?.name }
    }

    // MARK: -

    private func deleteAccount() {
        guard let account else { return }
        if let reason = store.deleteAccount(account) {
            deleteError = reason
        } else {
            dismiss()
        }
    }
}
