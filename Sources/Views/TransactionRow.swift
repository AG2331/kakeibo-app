import SwiftUI

/// 1件の取引行。
struct TransactionRow: View {
    let tx: TxRecord
    let category: Category?

    var body: some View {
        let isTransfer = tx.type == .transfer
        let color = isTransfer ? TxPalette.transfer
            : (tx.type == .expense ? TxPalette.expense : TxPalette.income)
        let catColor = category?.color.map { Color(argb: $0) } ?? .gray

        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(catColor.opacity(0.2)).frame(width: 36, height: 36)
                Image(systemName: isTransfer ? "arrow.left.arrow.right" : "tag")
                    .font(.footnote)
                    .foregroundStyle(catColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isTransfer ? "振替" : (category?.name ?? "未分類"))
                if let memo = tx.memo, !memo.isEmpty {
                    Text(memo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(tx.type == .expense ? "-\(Money.format(tx.amount))" : Money.format(tx.amount))
                .font(.callout.bold())
                .foregroundStyle(color)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
