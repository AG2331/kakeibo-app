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
    var parentId: Int64?   // nil = 独立した実口座 / 値あり = 親口座の下の仮想口座

    init(
        id: Int64? = nil,
        name: String,
        type: AccountType,
        initialBalance: Int = 0,
        sortOrder: Int = 0,
        archived: Bool = false,
        parentId: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.initialBalance = initialBalance
        self.sortOrder = sortOrder
        self.archived = archived
        self.parentId = parentId
    }

    var isVirtual: Bool { parentId != nil }
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
