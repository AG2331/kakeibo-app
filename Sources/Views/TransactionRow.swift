import SwiftUI

/// 口座詳細で使う表示の観点。振替が「入ってくる」のか「出ていく」のかを決める。
struct RowPerspective {
    let accountId: Int64
    /// 振替の相手先の口座名（分かれば表示する）。
    let counterpartName: String?
}

/// 1件の取引行。
struct TransactionRow: View {
    let tx: TxRecord
    let category: Category?
    /// 口座詳細のように「その口座から見た増減」で見せたいときに渡す。
    var perspective: RowPerspective?

    var body: some View {
        let isTransfer = tx.type == .transfer
        let catColor = category?.color.map { Color(argb: $0) } ?? .gray

        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(catColor.opacity(0.2)).frame(width: 36, height: 36)
                Image(systemName: isTransfer ? "arrow.left.arrow.right" : "tag")
                    .font(.footnote)
                    .foregroundStyle(catColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let memo = tx.memo, !memo.isEmpty {
                    Text(memo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(amountText)
                .font(.callout.bold())
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var title: String {
        guard tx.type == .transfer else { return category?.name ?? "未分類" }
        guard let perspective, let counterpart = perspective.counterpartName else { return "振替" }
        // その口座から見て、どこへ出たか / どこから入ったかを示す
        return isOutgoingTransfer ? "振替 → \(counterpart)" : "振替 ← \(counterpart)"
    }

    /// 振替がこの口座から出ていくか（観点が無いときは出金側として扱う）。
    private var isOutgoingTransfer: Bool {
        guard let perspective else { return true }
        return tx.accountId == perspective.accountId
    }

    private var amountText: String {
        switch tx.type {
        case .expense:
            return "-\(Money.format(tx.amount))"
        case .income:
            return Money.format(tx.amount)
        case .transfer:
            // 口座詳細では、その口座の増減として符号を付ける
            guard perspective != nil else { return Money.format(tx.amount) }
            return isOutgoingTransfer ? "-\(Money.format(tx.amount))" : "+\(Money.format(tx.amount))"
        }
    }

    private var amountColor: Color {
        switch tx.type {
        case .expense: return TxPalette.expense
        case .income: return TxPalette.income
        case .transfer: return TxPalette.transfer
        }
    }
}
