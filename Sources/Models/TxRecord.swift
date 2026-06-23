import Foundation

/// 1件の取引。amount は常に正の整数（最小通貨単位 / 円なら1円）。
struct TxRecord: Identifiable, Hashable {
    var id: Int64?
    var type: TxType
    var amount: Int
    var date: String        // YYYY-MM-DD
    var categoryId: Int64?  // transfer 時は nil
    var accountId: Int64
    var toAccountId: Int64? // transfer 時のみ
    var memo: String?
    var createdAt: Int64    // epoch ms

    init(
        id: Int64? = nil,
        type: TxType,
        amount: Int,
        date: String,
        categoryId: Int64? = nil,
        accountId: Int64,
        toAccountId: Int64? = nil,
        memo: String? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.date = date
        self.categoryId = categoryId
        self.accountId = accountId
        self.toAccountId = toAccountId
        self.memo = memo
        self.createdAt = createdAt
    }

    /// 収支差への寄与額（収入:+ / 支出:- / 振替:0）。
    var signedAmount: Int {
        switch type {
        case .income: return amount
        case .expense: return -amount
        case .transfer: return 0
        }
    }
}
