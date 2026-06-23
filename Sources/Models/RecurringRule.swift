import Foundation

/// 繰り返し頻度。
enum Frequency: String, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly
    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "毎日"
        case .weekly: return "毎週"
        case .monthly: return "毎月"
        case .yearly: return "毎年"
        }
    }
}

/// 定期取引のルール。next_date が到来するたびに取引を生成する。
struct RecurringRule: Identifiable, Hashable {
    var id: Int64?
    var type: TxType
    var amount: Int
    var categoryId: Int64?
    var accountId: Int64
    var toAccountId: Int64?
    var memo: String?
    var frequency: Frequency
    var interval: Int
    var nextDate: String      // YYYY-MM-DD
    var endDate: String?      // YYYY-MM-DD

    init(
        id: Int64? = nil,
        type: TxType,
        amount: Int,
        categoryId: Int64? = nil,
        accountId: Int64,
        toAccountId: Int64? = nil,
        memo: String? = nil,
        frequency: Frequency,
        interval: Int = 1,
        nextDate: String,
        endDate: String? = nil
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.categoryId = categoryId
        self.accountId = accountId
        self.toAccountId = toAccountId
        self.memo = memo
        self.frequency = frequency
        self.interval = interval
        self.nextDate = nextDate
        self.endDate = endDate
    }
}
