import Foundation

enum AccountType: String, CaseIterable, Identifiable {
    case cash
    case bank
    case emoney
    case credit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: return "現金"
        case .bank: return "銀行"
        case .emoney: return "電子マネー"
        case .credit: return "クレジット"
        }
    }
}

struct Account: Identifiable, Hashable {
    var id: Int64?
    var name: String
    var type: AccountType
    var initialBalance: Int
    var sortOrder: Int
    var archived: Bool
    var parentId: Int64?          // nil = 独立した実口座 / 値あり = 親口座の下の仮想口座
    var closingDay: Int?          // クレカ締め日。1-31、0=月末、nil=未設定（typeがcreditの場合のみ意味を持つ）
    var paymentDay: Int?          // クレカ支払日（引き落とし日）。1-31、0=月末、nil=未設定
    var paymentMonthOffset: Int   // 締め月から支払月までのオフセット。0=当月/1=翌月/2=翌々月
    var paymentAccountId: Int64?  // 引き落とし元口座

    init(
        id: Int64? = nil,
        name: String,
        type: AccountType,
        initialBalance: Int = 0,
        sortOrder: Int = 0,
        archived: Bool = false,
        parentId: Int64? = nil,
        closingDay: Int? = nil,
        paymentDay: Int? = nil,
        paymentMonthOffset: Int = 1,
        paymentAccountId: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.initialBalance = initialBalance
        self.sortOrder = sortOrder
        self.archived = archived
        self.parentId = parentId
        self.closingDay = closingDay
        self.paymentDay = paymentDay
        self.paymentMonthOffset = paymentMonthOffset
        self.paymentAccountId = paymentAccountId
    }

    var isVirtual: Bool { parentId != nil }

    /// 締め日・支払日の両方が設定済みのクレジット口座か。
    var hasStatementConfig: Bool { type == .credit && closingDay != nil && paymentDay != nil }
}

/// 総額タブ用: 親口座とその仮想口座の残高内訳。
struct AccountNode: Identifiable {
    let account: Account
    let ownBalance: Int                  // 親口座自身（仮想口座に振り分けていない分）の残高
    let children: [(account: Account, balance: Int)]

    var id: Int64 { account.id ?? -1 }
    var total: Int { ownBalance + children.reduce(0) { $0 + $1.balance } }
    var hasChildren: Bool { !children.isEmpty }
}

/// 口座タブ用: クレジットカードの請求サイクル情報。
struct CreditCardStatementInfo: Identifiable {
    let accountId: Int64
    let periodStart: String     // 直近で締めた期間の開始日
    let periodEnd: String       // 直近の締め日
    let outstandingAmount: Int  // 未精算額（= max(0, -口座残高)）
    let nextPaymentDate: String // 次回引き落とし予定日
    let suggestedAmount: Int    // 今回請求予定額（= periodStart〜periodEndの支出合計）

    var id: Int64 { accountId }
}
