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

    init(
        id: Int64? = nil,
        name: String,
        type: AccountType,
        initialBalance: Int = 0,
        sortOrder: Int = 0,
        archived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.initialBalance = initialBalance
        self.sortOrder = sortOrder
        self.archived = archived
    }
}
